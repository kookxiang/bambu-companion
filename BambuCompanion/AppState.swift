import Foundation
import SwiftUI

@MainActor
final class AppState: NSObject, ObservableObject {
    @Published private(set) var configuration: PrinterConfiguration
    @Published private(set) var connectionState: ConnectionState = .notConfigured
    @Published private(set) var status: PrinterStatus = .empty
    @Published var isShowingSettings = false

    private let configurationStore: PrinterConfigurationStore
    private var mqttClient: BambuMQTTClient?

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
        status = .empty

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
        connectionState = configuration.isComplete ? .disconnected : .notConfigured
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
                self.status = try MQTTReportParser.parse(data)
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
