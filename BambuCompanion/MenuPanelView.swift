import SwiftUI

struct MenuPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @StateObject private var pictureInPictureState = PictureInPicturePresentationState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if appState.configuration.isComplete {
                VStack(alignment: .leading, spacing: pictureInPictureState.isShowing ? 0 : 16) {
                    StatusSummaryView(status: appState.status, coverImageState: appState.coverImageState)
                    VideoPreviewView(url: appState.videoStreamURL)
                }
            } else {
                setupPrompt
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up your printer")
                .font(.subheadline.bold())
            Text("Enter the printer IP, serial number, and LAN access code to start monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                openSettingsWindow()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 7, height: 7)
                Text(appState.connectionState.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showsReconnectButton {
                Button {
                    appState.reconnectIfConfigured()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .disabled(!appState.configuration.isComplete)
            }

            Spacer()

            if pictureInPictureState.isShowing {
                Button {
                    pictureInPictureState.dismiss()
                } label: {
                    Label("Return Picture in Picture to this window", systemImage: "pip.exit")
                }
                .help(L10n.string("Return Picture in Picture to this window"))
            }

            Button {
                openSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .background {
                SettingsLink {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .hidden()
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

    private var showsReconnectButton: Bool {
        guard appState.configuration.isComplete else {
            return false
        }
        switch appState.connectionState {
        case .connected, .connecting:
            return false
        default:
            return true
        }
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
