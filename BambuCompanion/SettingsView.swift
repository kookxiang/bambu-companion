import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = PrinterConfiguration(displayName: "", host: "", serialNumber: "", accessCode: "")
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Printer name", text: $draft.displayName)
                TextField("Printer IP / Host", text: $draft.host)
                TextField("Serial number", text: $draft.serialNumber)
                SecureField("LAN access code", text: $draft.accessCode)
            } header: {
                Text("Printer")
            }

            Section {
                HStack {
                    Button {
                        saveAndReconnect()
                    } label: {
                        Label("Save", systemImage: "checkmark.circle")
                    }
                    .keyboardShortcut(.defaultAction)

                    Button {
                        testConnection()
                    } label: {
                        Label("Test Connection", systemImage: "network")
                    }
                    .disabled(!draft.isComplete)

                    Spacer()
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("The access code is stored in Keychain. The app connects to MQTT over TLS on port 8883 and subscribes to device/{serial}/report.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 440)
        .onAppear {
            draft = appState.configuration
        }
    }

    private func saveAndReconnect() {
        do {
            try appState.save(configuration: draft)
            message = "Saved. Reconnecting..."
        } catch {
            message = error.localizedDescription
        }
    }

    private func testConnection() {
        do {
            try appState.save(configuration: draft)
            appState.reconnectIfConfigured()
            message = "Connecting..."
        } catch {
            message = error.localizedDescription
        }
    }
}
