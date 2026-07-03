import SwiftUI

struct MenuPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if appState.configuration.isComplete {
                StatusSummaryView(status: appState.status)
                VideoPlaceholderView()
            } else {
                setupPrompt
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: appState.menuBarSymbolName)
                .font(.system(size: 24))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.configuration.resolvedDisplayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(appState.connectionState.title)
                    .font(.caption)
                    .foregroundStyle(connectionColor)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up your printer")
                .font(.subheadline.bold())
            Text("Enter the printer IP, serial number, and LAN access code to start monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button {
                appState.reconnectIfConfigured()
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
            .disabled(!appState.configuration.isComplete)

            Spacer()

            Button {
                appState.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private var connectionColor: Color {
        switch appState.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .authenticationFailed, .failed:
            return .red
        default:
            return .secondary
        }
    }
}
