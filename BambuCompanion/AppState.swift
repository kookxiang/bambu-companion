import Foundation
import SwiftUI

@MainActor
final class AppState: NSObject, ObservableObject {
    @Published private(set) var configuration: PrinterConfiguration
    @Published private(set) var connectionState: ConnectionState = .notConfigured
    @Published private(set) var status: PrinterStatus = .empty
    @Published private(set) var coverImageState: CoverImageState = .unavailable
    @Published var isShowingSettings = false

    private let configurationStore: PrinterConfigurationStore
    private let coverImageService = CoverImageService()
    private var mqttClient: BambuMQTTClient?
    private var coverImageTask: Task<Void, Never>?
    private var currentCoverJobKey: String?
    private var currentCoverAttemptKey: String?

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
        mqttClient?.disconnect()
        mqttClient = nil
        coverImageTask?.cancel()
        coverImageTask = nil
        coverImageService.reset()
        currentCoverJobKey = nil
        currentCoverAttemptKey = nil
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
        mqttClient?.disconnect()
        mqttClient = nil
        coverImageTask?.cancel()
        coverImageTask = nil
        connectionState = configuration.isComplete ? .disconnected : .notConfigured
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
            gcodeFile: status.gcodeFile,
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

extension AppState: BambuMQTTClientDelegate {
    nonisolated func mqttClientDidConnect(_ client: BambuMQTTClient) {
        Task { @MainActor in
            self.connectionState = .connected
        }
    }

    nonisolated func mqttClient(_ client: BambuMQTTClient, didReceiveReport data: Data) {
        Task { @MainActor in
            do {
                let status = try MQTTReportParser.parse(data)
                self.status = status
                self.updateCoverImageIfNeeded(for: status)
            } catch {
                self.connectionState = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func mqttClient(_ client: BambuMQTTClient, didFail error: Error) {
        Task { @MainActor in
            if error.localizedDescription.localizedCaseInsensitiveContains("authentication") {
                self.connectionState = .authenticationFailed
            } else {
                self.connectionState = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func mqttClientDidDisconnect(_ client: BambuMQTTClient) {
        Task { @MainActor in
            self.connectionState = self.configuration.isComplete ? .disconnected : .notConfigured
        }
    }
}
