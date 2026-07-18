import SwiftUI

struct SettingsView: View {
    private enum ProtectedField: Hashable {
        case serialNumber
        case accessCode

        var showLabelKey: String {
            switch self {
            case .serialNumber: "Show serial number"
            case .accessCode: "Show LAN access code"
            }
        }

        var hideLabelKey: String {
            switch self {
            case .serialNumber: "Hide serial number"
            case .accessCode: "Hide LAN access code"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @State private var draft = PrinterConfiguration(displayName: "", host: "", serialNumber: "", accessCode: "")
    @State private var message: String?
    @State private var revealedFields: Set<ProtectedField> = []

    var body: some View {
        Form {
            Section {
                TextField("Printer name", text: $draft.displayName)
                TextField("Printer IP / Host", text: $draft.host)
                visibilityTogglingField(
                    "Serial number",
                    text: uppercaseSerialNumber,
                    field: .serialNumber
                )
                visibilityTogglingField(
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
            revealedFields.removeAll()
            draft = appState.configuration
            draft.serialNumber = draft.serialNumber.uppercased()
        }
    }

    private var uppercaseSerialNumber: Binding<String> {
        Binding(
            get: { draft.serialNumber },
            set: { draft.serialNumber = $0.uppercased() }
        )
    }

    @ViewBuilder
    private func visibilityTogglingField(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        field: ProtectedField
    ) -> some View {
        let isRevealed = revealedFields.contains(field)
        let actionLabel = L10n.string(
            isRevealed ? field.hideLabelKey : field.showLabelKey
        )

        HStack(spacing: 6) {
            if isRevealed {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }

            Button {
                if isRevealed {
                    revealedFields.remove(field)
                } else {
                    revealedFields.insert(field)
                }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(actionLabel)
            .accessibilityLabel(actionLabel)
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
