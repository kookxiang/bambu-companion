import SwiftUI

struct MenuPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if appState.configuration.isComplete {
                        StatusSummaryView(status: appState.status, coverImageState: appState.coverImageState)
                        VideoPreviewView(url: appState.videoStreamURL)
                    } else {
                        setupPrompt
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: MenuPanelContentHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
            }
            .frame(height: scrollHeight)
            .scrollIndicators(.hidden)
            .onPreferenceChange(MenuPanelContentHeightPreferenceKey.self) { contentHeight = $0 }

            Divider()
            footer
        }
        .frame(width: 340)
        .frame(maxHeight: 760)
        .padding(16)
    }

    private var scrollHeight: CGFloat {
        min(max(contentHeight, 1), 680)
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

private struct MenuPanelContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
