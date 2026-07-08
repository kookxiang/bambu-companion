import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppState: NSObject, ObservableObject {
    @Published private(set) var configuration: PrinterConfiguration
    @Published private(set) var connectionState: ConnectionState = .notConfigured
    @Published private(set) var status: PrinterStatus = .empty
    @Published private(set) var coverImageState: CoverImageState = .unavailable
    @Published var isShowingSettings = false

    private let configurationStore: PrinterConfigurationStore
    private let coverImageService = CoverImageService()
    private let notificationService = PrintNotificationService()
    private var mqttClient: BambuMQTTClient?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var coverImageTask: Task<Void, Never>?
    private var currentCoverJobKey: String?
    private var currentCoverAttemptKey: String?
    private var notificationGate = PrintNotificationGate()

    private static let reconnectDelays: [UInt64] = [3, 10, 30, 60]

    var menuBarSymbolName: String {
        switch connectionState {
        case .connected:
            return status.activity == .printing ? "printer.filled.and.paper" : "printer"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .authenticationFailed, .failed:
            return "printer.dotmatrix.fill.and.paper.fill"
        default:
            return "printer"
        }
    }

    var menuBarProgressTitle: String? {
        guard connectionState == .connected,
              status.activity == .printing || status.activity == .paused,
              let progress = status.progress else {
            return nil
        }
        return "\(progress)%"
    }

    var videoStreamURL: URL? {
        VideoStreamURLBuilder.url(configuration: configuration, status: status)
    }

    override init() {
        let configurationStore = PrinterConfigurationStore()
        self.configurationStore = configurationStore
        self.configuration = configurationStore.load()
        super.init()
        reconnectIfConfigured()
    }

    func save(configuration: PrinterConfiguration) throws {
        try configurationStore.save(configuration)
        self.configuration = configuration
        reconnectIfConfigured()
    }

    func reconnectIfConfigured() {
        reconnectIfConfigured(resetBackoff: true)
    }

    private func reconnectIfConfigured(resetBackoff: Bool) {
        reconnectTask?.cancel()
        reconnectTask = nil
        if resetBackoff {
            reconnectAttempt = 0
        }
        mqttClient?.disconnect()
        mqttClient = nil
        coverImageTask?.cancel()
        coverImageTask = nil
        coverImageService.reset()
        currentCoverJobKey = nil
        currentCoverAttemptKey = nil
        notificationGate.reset()
        status = .empty
        coverImageState = .unavailable

        guard configuration.isComplete else {
            connectionState = .notConfigured
            return
        }

        connectionState = .connecting
        let client = BambuMQTTClient(configuration: configuration)
        client.delegate = self
        mqttClient = client
        client.connect()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        mqttClient?.disconnect()
        mqttClient = nil
        coverImageTask?.cancel()
        coverImageTask = nil
        notificationGate.reset()
        connectionState = configuration.isComplete ? .disconnected : .notConfigured
    }

    private func scheduleReconnect(for client: BambuMQTTClient) {
        guard mqttClient === client,
              configuration.isComplete,
              connectionState != .authenticationFailed,
              reconnectTask == nil else {
            return
        }

        let delay = Self.reconnectDelays[min(reconnectAttempt, Self.reconnectDelays.count - 1)]
        reconnectAttempt += 1
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.reconnectIfConfigured(resetBackoff: false)
        }
    }

    private func apply(status newStatus: PrinterStatus) {
        let mergedStatus = status.mergingIncrementalUpdate(newStatus)
        let notificationEvents = notificationGate.observe(status: mergedStatus)
        status = mergedStatus

        for event in notificationEvents {
            notificationService.notifyIfNeeded(
                event: event,
                status: mergedStatus,
                printerName: configuration.resolvedDisplayName
            )
        }

        updateCoverImageIfNeeded(for: mergedStatus)
    }

    private func updateCoverImageIfNeeded(for status: PrinterStatus) {
        guard configuration.isComplete,
              status.activity == .printing || status.activity == .paused,
              status.gcodeFile?.isEmpty == false || status.subtaskName?.isEmpty == false else {
            coverImageState = .unavailable
            coverImageTask?.cancel()
            coverImageTask = nil
            coverImageService.reset()
            currentCoverJobKey = nil
            currentCoverAttemptKey = nil
            return
        }

        let job = CoverImageJob(
            host: configuration.host,
            accessCode: configuration.accessCode,
            rawFile: status.rawFile,
            gcodeFile: status.gcodeFile,
            gcodeFileDownloaded: status.gcodeFileDownloaded,
            subtaskName: status.subtaskName
        )
        guard let jobKey = job.cacheKey else {
            return
        }
        if case .ready = coverImageState, jobKey == currentCoverJobKey {
            return
        }
        let attemptKey = "\(jobKey)|\(status.activity.rawValue)|\(status.gcodeFilePreparePercent ?? -1)"
        guard attemptKey != currentCoverAttemptKey else {
            return
        }
        currentCoverAttemptKey = attemptKey
        currentCoverJobKey = jobKey

        coverImageTask?.cancel()
        coverImageState = .loading
        coverImageTask = Task { [coverImageService] in
            do {
                let url = try await coverImageService.loadCover(for: job)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let url {
                        self.coverImageState = .ready(url)
                    } else if case .loading = self.coverImageState {
                        self.coverImageState = .unavailable
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.coverImageState = .failed(error.localizedDescription)
                }
            }
        }
    }
}

struct PrintNotificationGate {
    private var lastEffectiveActivity: PrinterActivity?
    private var lastHMSAlert: PrinterAlert?

    mutating func observe(status: PrinterStatus) -> [PrintNotificationEvent] {
        var events: [PrintNotificationEvent] = []
        if let activity = observeActivity(status.activity) {
            events.append(.activity(activity))
        }
        if let alert = observeHMSAlert(status.alert) {
            events.append(.hmsAlert(alert))
        }
        return events
    }

    mutating func observe(activity: PrinterActivity) -> Bool {
        observeActivity(activity) != nil
    }

    private mutating func observeActivity(_ activity: PrinterActivity) -> PrinterActivity? {
        guard activity.isEffectivePrintEvent else {
            return nil
        }
        defer {
            lastEffectiveActivity = activity
        }
        guard let lastEffectiveActivity else {
            return nil
        }
        return lastEffectiveActivity != activity ? activity : nil
    }

    private mutating func observeHMSAlert(_ alert: PrinterAlert?) -> PrinterAlert? {
        guard let alert, alert.source == .hms else {
            lastHMSAlert = nil
            return nil
        }
        defer {
            lastHMSAlert = alert
        }
        guard lastHMSAlert != alert else {
            return nil
        }
        return alert
    }

    mutating func reset() {
        lastEffectiveActivity = nil
        lastHMSAlert = nil
    }
}

enum PrintNotificationEvent: Equatable {
    case activity(PrinterActivity)
    case hmsAlert(PrinterAlert)
}

private extension PrinterActivity {
    var isEffectivePrintEvent: Bool {
        switch self {
        case .printing, .cancelled, .paused, .finished, .failed:
            return true
        case .idle, .unknown:
            return false
        }
    }
}

enum VideoStreamURLBuilder {
    static func url(configuration: PrinterConfiguration, status: PrinterStatus) -> URL? {
        guard configuration.isComplete else {
            return nil
        }
        if let rawURL = status.cameraStreamURL,
           let url = authenticatedURL(from: rawURL, configuration: configuration) {
            return url
        }
        return defaultURL(configuration: configuration)
    }

    private static func authenticatedURL(from rawURL: String, configuration: PrinterConfiguration) -> URL? {
        let normalizedRawURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()

        if let parsed = URLComponents(string: normalizedRawURL), parsed.host != nil {
            components = parsed
        } else {
            if let withScheme = URLComponents(string: "rtsp://\(normalizedRawURL)"), withScheme.host != nil {
                components = withScheme
            } else {
                return nil
            }
        }

        guard let host = components.host else {
            return nil
        }

        let scheme = {
            guard let sourceScheme = components.scheme?.lowercased(),
                  ["rtsp", "rtsps"].contains(sourceScheme) else {
                return "rtsps"
            }
            return sourceScheme
        }

        var rebuilt = URLComponents()
        rebuilt.scheme = scheme()
        rebuilt.user = "bblp"
        rebuilt.password = configuration.accessCode
        rebuilt.host = host
        rebuilt.port = components.port ?? 322
        rebuilt.path = components.path.isEmpty ? "/streaming/live/1" : components.path
        rebuilt.fragment = components.fragment
        rebuilt.percentEncodedQuery = components.percentEncodedQuery
        return rebuilt.url
    }

    private static func defaultURL(configuration: PrinterConfiguration) -> URL? {
        var components = URLComponents()
        components.scheme = "rtsps"
        components.user = "bblp"
        components.password = configuration.accessCode
        components.host = sanitizedHost(configuration.host)
        components.port = 322
        components.path = "/streaming/live/1"
        return components.url
    }

    private static func sanitizedHost(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URLComponents(string: value), let parsedHost = url.host {
            value = parsedHost
        }
        if let colonIndex = value.lastIndex(of: ":") {
            value = String(value[..<colonIndex])
        }
        return value
    }
}

extension AppState: BambuMQTTClientDelegate {
    nonisolated func mqttClientDidConnect(_ client: BambuMQTTClient) {
        Task { @MainActor in
            guard self.mqttClient === client else {
                return
            }
            self.reconnectTask?.cancel()
            self.reconnectTask = nil
            self.reconnectAttempt = 0
            self.connectionState = .connected
        }
    }

    nonisolated func mqttClient(_ client: BambuMQTTClient, didReceiveReport data: Data) {
        Task { @MainActor in
            guard self.mqttClient === client else {
                return
            }
            do {
                let status = try MQTTReportParser.parse(data)
                self.apply(status: status)
            } catch {
                self.connectionState = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func mqttClient(_ client: BambuMQTTClient, didFail error: Error) {
        Task { @MainActor in
            guard self.mqttClient === client else {
                return
            }
            if error.localizedDescription.localizedCaseInsensitiveContains("authentication") {
                self.reconnectTask?.cancel()
                self.reconnectTask = nil
                self.connectionState = .authenticationFailed
            } else {
                self.connectionState = .failed(error.localizedDescription)
                self.scheduleReconnect(for: client)
            }
        }
    }

    nonisolated func mqttClientDidDisconnect(_ client: BambuMQTTClient) {
        Task { @MainActor in
            guard self.mqttClient === client else {
                return
            }
            self.connectionState = self.configuration.isComplete ? .disconnected : .notConfigured
            self.scheduleReconnect(for: client)
        }
    }
}

private final class PrintNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyIfNeeded(event: PrintNotificationEvent, status: PrinterStatus, printerName: String) {
        guard let notification = PrintStatusNotification(event: event, status: status, printerName: printerName) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = "print-status"
        content.userInfo = notification.userInfo

        let identifier = "\(notification.identifierPrefix)-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

private struct PrintStatusNotification {
    let title: String
    let body: String
    let identifierPrefix: String
    let userInfo: [AnyHashable: Any]

    init?(event: PrintNotificationEvent, status: PrinterStatus, printerName: String) {
        switch event {
        case let .activity(activity):
            self.init(activity: activity, status: status, printerName: printerName)
        case let .hmsAlert(alert):
            self.init(
                title: L10n.string("HMS Alert"),
                body: alert.detail ?? alert.title,
                identifierPrefix: "hms-alert",
                userInfo: ["alert": alert.title]
            )
        }
    }

    private init?(activity: PrinterActivity, status: PrinterStatus, printerName: String) {
        let job = Self.jobDescription(from: status)
        let title: String
        let body: String

        switch activity {
        case .printing:
            title = L10n.format("%@ started printing", printerName)
            body = job ?? L10n.string("A print job has started.")
        case .cancelled:
            title = L10n.format("%@ print cancelled", printerName)
            body = job ?? L10n.string("The current print was cancelled.")
        case .paused:
            title = L10n.format("%@ paused", printerName)
            body = job ?? L10n.string("The current print is paused.")
        case .failed:
            title = L10n.format("%@ print failed", printerName)
            body = status.alert?.detail ?? job ?? L10n.string("The current print failed.")
        case .finished:
            title = L10n.format("%@ print finished", printerName)
            body = job ?? L10n.string("The current print completed successfully.")
        case .idle, .unknown:
            return nil
        }
        self.init(
            title: title,
            body: body,
            identifierPrefix: "print-status-\(activity.rawValue)",
            userInfo: ["activity": activity.rawValue]
        )
    }

    private init(title: String, body: String, identifierPrefix: String, userInfo: [AnyHashable: Any]) {
        self.title = title
        self.body = body
        self.identifierPrefix = identifierPrefix
        self.userInfo = userInfo
    }

    private static func jobDescription(from status: PrinterStatus) -> String? {
        if let jobName = status.jobName?.trimmingCharacters(in: .whitespacesAndNewlines), !jobName.isEmpty {
            return jobName
        }
        if let subtaskName = status.subtaskName?.trimmingCharacters(in: .whitespacesAndNewlines), !subtaskName.isEmpty {
            return subtaskName
        }
        if let gcodeFile = status.gcodeFile?.trimmingCharacters(in: .whitespacesAndNewlines), !gcodeFile.isEmpty {
            return gcodeFile
        }
        return nil
    }
}
