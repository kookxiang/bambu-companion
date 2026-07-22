import AppKit
import Sparkle
import SwiftUI

struct MenuPanelView: View {
    private static let panelSpacing: CGFloat = 16
    private static let panelPadding: CGFloat = 16
    private static let fallbackContentViewportHeight: CGFloat = 440
    private static let estimatedFixedSectionHeight: CGFloat = 40

    let updater: SPUUpdater
    let onPreferredContentHeightChange: (CGFloat) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @StateObject private var pictureInPictureState = PictureInPicturePresentationState.shared
    @State private var screenVisibleHeight: CGFloat = 0
    @State private var fixedSectionHeight: CGFloat = Self.estimatedFixedSectionHeight
    @State private var scrollableContentHeight: CGFloat?

    init(
        updater: SPUUpdater,
        onPreferredContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.updater = updater
        self.onPreferredContentHeightChange = onPreferredContentHeightChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.panelSpacing) {
            if appState.configuration.isComplete {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: pictureInPictureState.isShowing ? 0 : 16) {
                        StatusSummaryView(status: appState.status, coverImageState: appState.coverImageState)
                        VideoPreviewView(url: appState.videoStreamURL)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        ViewHeightReader { height in
                            guard height > 0,
                                  abs((scrollableContentHeight ?? 0) - height) > 0.5 else {
                                return
                            }
                            scrollableContentHeight = height
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: contentViewportHeight,
                        alignment: .topLeading
                    )
                }
                .frame(height: contentViewportHeight, alignment: .top)
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
            if appState.configuration.isComplete {
                MenuPanelHeightReporter(
                    contentHeight: panelContentHeight,
                    onChange: onPreferredContentHeightChange
                )
            }
        }
    }

    private var contentViewportHeight: CGFloat {
        guard let scrollableContentHeight else {
            return min(Self.fallbackContentViewportHeight, maximumContentHeight)
        }
        return min(scrollableContentHeight, maximumContentHeight)
    }

    private var panelContentHeight: CGFloat {
        contentViewportHeight
            + fixedSectionHeight
            + Self.panelSpacing
            + (Self.panelPadding * 2)
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
                - fixedSectionHeight
        )
    }

    private var fixedSection: some View {
        VStack(alignment: .leading, spacing: Self.panelSpacing) {
            Divider()
            footer
        }
        .background {
            ViewHeightReader { height in
                guard height > 0, abs(fixedSectionHeight - height) > 0.5 else {
                    return
                }
                fixedSectionHeight = height
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
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            openSettings()
        }
    }
}

private struct ViewHeightReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> HeightReportingView {
        let view = HeightReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: HeightReportingView, context: Context) {
        view.onChange = onChange
        view.reportHeight()
    }

    final class HeightReportingView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var lastHeight: CGFloat = 0

        override func layout() {
            super.layout()
            reportHeight()
        }

        func reportHeight() {
            let height = bounds.height
            guard height > 0, abs(lastHeight - height) > 0.5 else {
                return
            }
            lastHeight = height
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(height)
            }
        }
    }
}

private struct MenuPanelHeightReporter: NSViewRepresentable {
    let contentHeight: CGFloat
    let onChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard contentHeight > 0,
              abs(context.coordinator.lastHeight - contentHeight) > 0.5 else {
            return
        }
        context.coordinator.lastHeight = contentHeight
        DispatchQueue.main.async {
            onChange(contentHeight)
        }
    }

    final class Coordinator {
        var lastHeight: CGFloat = 0
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
