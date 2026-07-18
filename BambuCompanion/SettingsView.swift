import SwiftUI

struct SettingsView: View {
    private enum FocusedField: Hashable {
        case serialNumber
        case accessCode
    }

    @EnvironmentObject private var appState: AppState
    @State private var draft = PrinterConfiguration(displayName: "", host: "", serialNumber: "", accessCode: "")
    @State private var message: String?
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        Form {
            Section {
                TextField("Printer name", text: $draft.displayName)
                TextField("Printer IP / Host", text: $draft.host)
                focusRevealingField(
                    "Serial number",
                    text: $draft.serialNumber,
                    field: .serialNumber
                )
                focusRevealingField(
                    "LAN access code",
                    text: $draft.accessCode,
                    field: .accessCode
                )
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

    @ViewBuilder
    private func focusRevealingField(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        field: FocusedField
    ) -> some View {
        let isFocused = focusedField == field

        ZStack {
            TextField(title, text: text)
                .focused($focusedField, equals: field)
                .opacity(isFocused ? 1 : 0)

            SecureField(title, text: text)
                .allowsHitTesting(false)
                .focusable(false)
                .opacity(isFocused ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
    }

    private func saveAndReconnect() {
        do {
            try appState.save(configuration: draft)
            message = L10n.string("Saved. Reconnecting...")
        } catch {
            message = error.localizedDescription
        }
    }

    private func testConnection() {
        do {
            try appState.save(configuration: draft)
            appState.reconnectIfConfigured()
            message = L10n.string("Connecting...")
        } catch {
            message = error.localizedDescription
        }
    }
}
