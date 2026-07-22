import AppKit
import Sparkle
import SwiftUI

struct MenuPanelView: View {
    private static let panelSpacing: CGFloat = 16
    private static let panelPadding: CGFloat = 16
    private static let fallbackContentViewportHeight: CGFloat = 440
    private static let estimatedFixedSectionHeight: CGFloat = 40

    let updater: SPUUpdater

    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @StateObject private var pictureInPictureState = PictureInPicturePresentationState.shared
    @State private var screenVisibleHeight: CGFloat = 0
    @State private var fixedSectionHeight: CGFloat = Self.estimatedFixedSectionHeight

    var body: some View {
        VStack(alignment: .leading, spacing: Self.panelSpacing) {
            if appState.configuration.isComplete {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: pictureInPictureState.isShowing ? 0 : 16) {
                        StatusSummaryView(status: appState.status, coverImageState: appState.coverImageState)
                        VideoPreviewView(url: appState.videoStreamURL)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: maximumContentHeight, alignment: .top)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                setupPrompt
            }

            fixedSection
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Self.panelPadding)
        .background {
            MenuPanelScreenReader { height in
                screenVisibleHeight = height
            }
        }
        .onPreferenceChange(FixedSectionHeightPreferenceKey.self) { height in
            fixedSectionHeight = height
        }
    }

    private var maximumContentHeight: CGFloat {
        guard screenVisibleHeight > 0 else {
            return Self.fallbackContentViewportHeight
        }

        // MenuBarExtra may retain the size from its first layout pass, so the
        // scroll view must never begin with an unbounded height.
        return max(
            0,
            screenVisibleHeight
                - (Self.panelPadding * 2)
                - Self.panelSpacing
                - max(fixedSectionHeight, Self.estimatedFixedSectionHeight)
        )
    }

    private var fixedSection: some View {
        VStack(alignment: .leading, spacing: Self.panelSpacing) {
            Divider()
            footer
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FixedSectionHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
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

            CheckForUpdatesButton(updater: updater)

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

private struct FixedSectionHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MenuPanelScreenReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScreenReaderView {
        let view = ScreenReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ScreenReaderView, context: Context) {
        view.onChange = onChange
        view.reportVisibleHeight()
    }

    final class ScreenReaderView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var screenObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeScreenChanges()
            reportVisibleHeight()
        }

        func reportVisibleHeight() {
            guard let height = window?.screen?.visibleFrame.height else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(height)
            }
        }

        private func observeScreenChanges() {
            if let screenObserver {
                NotificationCenter.default.removeObserver(screenObserver)
            }
            guard let window else {
                screenObserver = nil
                return
            }
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.reportVisibleHeight()
            }
        }

        deinit {
            if let screenObserver {
                NotificationCenter.default.removeObserver(screenObserver)
            }
        }
    }
}
