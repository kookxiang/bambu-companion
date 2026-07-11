import AVFoundation
import AVKit
import Combine
import CryptoKit
import Network
import OSLog
import SwiftUI
import AppKit

enum VideoDefaultsKey {
    static let pictureInPictureEnabled = "video.pictureInPictureEnabled"
}

struct NativeVideoPreviewView: View {
    let url: URL?

    var body: some View {
        NativeVideoStreamSurface(
            url: url,
            showFloatingButton: true
        )
    }
}

private struct NativeVideoStreamSurface: View {
    let url: URL?
    let showFloatingButton: Bool

    @StateObject private var floatingVideoWindowController = FloatingVideoWindowController.shared
    @StateObject private var streamState = VideoStreamState()
    @State private var isHoveringFloatingWindow = false
    private let staleFrameCheckTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var cornerRadius: CGFloat {
        showFloatingButton ? 8 : FloatingVideoWindowController.cornerRadius
    }
    private var effectiveURL: URL? {
        url
    }
    private var controlButtonSize: CGFloat {
        showFloatingButton ? 28 : 34
    }
    private var controlIconSize: CGFloat {
        showFloatingButton ? 12 : 13
    }
    private var controlPadding: CGFloat {
        showFloatingButton ? 8 : 14
    }
    private var previewHeight: CGFloat? {
        guard showFloatingButton else {
            return nil
        }
        return floatingVideoWindowController.isShowing ? 92 : 191
    }

    var body: some View {
        ZStack {
            if let effectiveURL {
                NativeVideoLayerView(url: effectiveURL, reconnectID: floatingVideoWindowController.videoReconnectGeneration, onFrame: {
                    streamState.setHasVideo()
                }) { message in
                    streamState.setErrorMessage(message)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            if let errorMessage = streamState.errorMessage {
                placeholder(icon: "video.slash", text: errorMessage)
            } else if effectiveURL != nil, floatingVideoWindowController.isShowing {
                pictureInPicturePlaceholder
            } else if effectiveURL != nil, !streamState.hasVideo {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.string("Connecting video..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if url == nil {
                placeholder(icon: "video.slash", text: L10n.string("Video preview is unavailable."))
            }

            if streamState.isWaitingForFrame && effectiveURL != nil && streamState.errorMessage == nil && !floatingVideoWindowController.isShowing {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            }

            if effectiveURL != nil {
                VStack {
                    HStack(spacing: 8) {
                        Spacer()
                        if !showFloatingButton {
                            floatingCloseButton
                        }
                        videoReconnectButton
                        if streamState.hasVideo && showFloatingButton && !floatingVideoWindowController.isShowing {
                            openFloatingButton
                        }
                    }
                    Spacer()
                }
                .padding(controlPadding)
                .opacity(isHoveringFloatingWindow ? 1 : 0)
                .animation(.easeOut(duration: 0.16), value: isHoveringFloatingWindow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: previewHeight)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .animation(.easeInOut(duration: 0.2), value: previewHeight)
        .onHover { hovering in
            isHoveringFloatingWindow = hovering
        }
        .onChange(of: effectiveURL) {
            streamState.reset()
        }
        .onChange(of: floatingVideoWindowController.videoReconnectGeneration) {
            streamState.reset()
        }
        .onReceive(staleFrameCheckTimer) { now in
            let shouldReconnect = streamState.updateWaitingForFrame(now: now, isActive: effectiveURL != nil)
            if shouldReconnect {
                floatingVideoWindowController.reconnectVideo()
            }
        }
    }

    private var pictureInPicturePlaceholder: some View {
        Button {
            floatingVideoWindowController.dismiss()
        } label: {
            HStack(spacing: 12) {
                PictureInPicturePlaceholderIcon()
                    .frame(width: 48, height: 36)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("Playing in Picture in Picture"))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(L10n.string("Click to return Picture in Picture to this window."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(L10n.string("Return Picture in Picture to this window"))
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                floatingVideoWindowController.reconnectVideo()
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var floatingCloseButton: some View {
        floatingControlButton(
            systemName: "xmark",
            accessibilityLabel: L10n.string("Close Floating Video")
        ) {
            FloatingVideoWindowController.shared.dismiss()
        }
    }

    private var videoReconnectButton: some View {
        floatingControlButton(
            systemName: "arrow.clockwise",
            accessibilityLabel: L10n.string("Reconnect Video")
        ) {
            floatingVideoWindowController.reconnectVideo()
        }
    }

    private var openFloatingButton: some View {
        floatingControlButton(
            systemName: "pip.enter",
            accessibilityLabel: L10n.string("Open Floating Video")
        ) {
            guard url != nil else {
                return
            }
            FloatingVideoWindowController.shared.toggle(url: url)
        }
    }

    private func floatingControlButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: controlIconSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: controlButtonSize, height: controlButtonSize)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PictureInPicturePlaceholderIcon: View {
    var body: some View {
        Image(systemName: "pip.exit")
            .font(.system(size: 32, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .opacity(0.76)
    }
}

@MainActor
private final class VideoStreamState: ObservableObject {
    private static let staleFrameReconnectInterval: TimeInterval = 1

    @Published private(set) var errorMessage: String?
    @Published private(set) var hasVideo = false
    @Published private(set) var isWaitingForFrame = false
    private var lastFrameTime: Date?
    private var didRequestAutomaticReconnect = false

    func setHasVideo() {
        if !hasVideo {
            hasVideo = true
        }
        if errorMessage != nil {
            errorMessage = nil
        }
        lastFrameTime = Date()
        didRequestAutomaticReconnect = false
        if isWaitingForFrame {
            isWaitingForFrame = false
        }
    }

    func setErrorMessage(_ message: String?) {
        if errorMessage != message {
            errorMessage = message
        }
    }

    func reset() {
        hasVideo = false
        isWaitingForFrame = false
        lastFrameTime = nil
        didRequestAutomaticReconnect = false
        errorMessage = nil
    }

    func updateWaitingForFrame(now: Date, isActive: Bool) -> Bool {
        guard isActive, errorMessage == nil else {
            if isWaitingForFrame {
                isWaitingForFrame = false
            }
            didRequestAutomaticReconnect = false
            return false
        }

        guard let lastFrameTime else {
            self.lastFrameTime = now
            return false
        }

        let elapsed = now.timeIntervalSince(lastFrameTime)
        let shouldWait = hasVideo && elapsed > Self.staleFrameReconnectInterval
        if isWaitingForFrame != shouldWait {
            isWaitingForFrame = shouldWait
        }
        guard elapsed >= Self.staleFrameReconnectInterval, !didRequestAutomaticReconnect else {
            return false
        }
        didRequestAutomaticReconnect = true
        return true
    }
}

private final class FloatingVideoWindowController: ObservableObject {
    static let shared = FloatingVideoWindowController()
    static let cornerRadius: CGFloat = 8

    @Published private(set) var isShowing = false
    @Published private(set) var videoReconnectGeneration = 0

    private let defaults: UserDefaults
    private weak var activeCoordinator: NativeVideoLayerView.Coordinator?
    private var isRestoreStartPending = false
    private var didAttemptRestore = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func toggle(url: URL?) {
        guard url != nil else {
            dismiss()
            return
        }
        guard let activeCoordinator else {
            return
        }
        if isShowing {
            setPictureInPictureEnabled(false)
            activeCoordinator.stopPictureInPicture()
            isShowing = false
            return
        }
        activeCoordinator.startPictureInPicture()
    }

    func dismiss() {
        setPictureInPictureEnabled(false)
        activeCoordinator?.stopPictureInPicture()
        isShowing = false
    }

    func reconnectVideo() {
        videoReconnectGeneration += 1
    }

    func register(_ coordinator: NativeVideoLayerView.Coordinator) {
        activeCoordinator = coordinator
        isRestoreStartPending = false
        didAttemptRestore = false
    }

    func unregister(_ coordinator: NativeVideoLayerView.Coordinator) {
        guard activeCoordinator === coordinator else {
            return
        }
        activeCoordinator = nil
        isShowing = false
        isRestoreStartPending = false
        didAttemptRestore = false
    }

    func restorePictureInPictureIfNeeded() {
        guard defaults.bool(forKey: VideoDefaultsKey.pictureInPictureEnabled),
              !isShowing,
              !isRestoreStartPending,
              !didAttemptRestore,
              let activeCoordinator else {
            return
        }

        isRestoreStartPending = true
        didAttemptRestore = true
        if !activeCoordinator.startPictureInPicture(reportUnavailable: false) {
            isRestoreStartPending = false
            didAttemptRestore = false
        }
    }

    var shouldRestorePictureInPicture: Bool {
        defaults.bool(forKey: VideoDefaultsKey.pictureInPictureEnabled) &&
            !isShowing &&
            !didAttemptRestore
    }

    func pictureInPictureDidStart() {
        isRestoreStartPending = false
        isShowing = true
        setPictureInPictureEnabled(true)
    }

    func pictureInPictureDidStop(preservePreference: Bool) {
        isRestoreStartPending = false
        isShowing = false
        if !preservePreference {
            setPictureInPictureEnabled(false)
        }
    }

    func pictureInPictureDidFailToStart() {
        isRestoreStartPending = false
        isShowing = false
    }

    private func setPictureInPictureEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: VideoDefaultsKey.pictureInPictureEnabled)
    }
}

private struct NativeVideoLayerView: NSViewRepresentable {
    let url: URL?
    let reconnectID: Int
    let onFrame: () -> Void
    let onError: (String?) -> Void

    func makeNSView(context: Context) -> VideoHostContainerView {
        let containerView = VideoHostContainerView()
        containerView.onWindowVisibilityChange = { isVisible in
            context.coordinator.setWindowVisible(isVisible)
        }
        context.coordinator.attach(to: containerView.videoView)
        return containerView
    }

    func updateNSView(_ view: VideoHostContainerView, context: Context) {
        view.videoView.frame = view.bounds
        context.coordinator.start(url: url, reconnectID: reconnectID, onFrame: onFrame)
        view.layoutSubtreeIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    static func dismantleNSView(_ nsView: VideoHostContainerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
        private let onError: (String?) -> Void
        private weak var view: VideoLayerHostView?
        private var client: NativeRTSPVideoClient?
        private var pictureInPictureSource: PictureInPictureSourceWindow?
        private var pictureInPictureController: AVPictureInPictureController?
        private var pipResizeObserver: NSObjectProtocol?
        private var currentURL: URL?
        private var currentReconnectID = 0
        private var desiredURL: URL?
        private var desiredReconnectID = 0
        private var desiredOnFrame: (() -> Void)?
        private var isWindowVisible = true
        private var isPictureInPictureProtected = false
        private var isTearingDown = false
        private var needsPictureInPictureLayoutRefreshAfterNextFrame = false

        init(onError: @escaping (String?) -> Void) {
            self.onError = onError
            super.init()
        }

        func attach(to view: VideoLayerHostView) {
            self.view = view
            configurePictureInPictureIfNeeded(for: view)
            FloatingVideoWindowController.shared.register(self)
        }

        func start(url: URL?, reconnectID: Int, onFrame: @escaping () -> Void) {
            desiredURL = url
            desiredReconnectID = reconnectID
            desiredOnFrame = onFrame
            startDesiredStreamIfNeeded()
        }

        func setWindowVisible(_ isVisible: Bool) {
            guard isWindowVisible != isVisible else {
                return
            }
            isWindowVisible = isVisible
            if isVisible {
                startDesiredStreamIfNeeded()
            } else if isPictureInPictureActiveOrStarting {
                return
            } else {
                currentURL = nil
                stopStream()
            }
        }

        private func startDesiredStreamIfNeeded() {
            guard shouldKeepVideoStreamRunning else {
                currentURL = nil
                stopStream()
                return
            }
            guard let url = desiredURL, let onFrame = desiredOnFrame else {
                stop()
                return
            }
            guard currentURL != url || currentReconnectID != desiredReconnectID else {
                return
            }
            currentURL = nil
            stopStream()
            currentURL = url
            currentReconnectID = desiredReconnectID
            onError(nil)
            view?.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)

            guard let view else {
                return
            }
            let client = NativeRTSPVideoClient(
                url: url,
                displayLayer: view.displayLayer,
                onFrame: { [weak self] in
                    onFrame()
                    FloatingVideoWindowController.shared.restorePictureInPictureIfNeeded()
                    self?.refreshPictureInPictureLayoutAfterFrameIfNeeded()
                },
                onConnected: { [weak self] in
                    DispatchQueue.main.async {
                        self?.refreshPictureInPictureLayoutAfterReconnectIfNeeded()
                    }
                }
            ) { [weak self] message in
                DispatchQueue.main.async {
                    self?.onError(message)
                }
            }
            self.client = client
            refreshPictureInPictureLayoutAfterReconnectIfNeeded()
            client.start()
        }

        func stop() {
            isTearingDown = true
            stopPictureInPicture()
            desiredURL = nil
            desiredOnFrame = nil
            currentURL = nil
            stopStream()
            FloatingVideoWindowController.shared.unregister(self)
        }

        private func stopStream() {
            client?.stop()
            client = nil
        }

        private var shouldKeepVideoStreamRunning: Bool {
            isWindowVisible ||
                isPictureInPictureActiveOrStarting ||
                FloatingVideoWindowController.shared.shouldRestorePictureInPicture
        }

        private var isPictureInPictureActiveOrStarting: Bool {
            isPictureInPictureProtected || pictureInPictureController?.isPictureInPictureActive == true
        }

        private func configurePictureInPictureIfNeeded(for view: VideoLayerHostView) {
            guard pictureInPictureController == nil,
                  AVPictureInPictureController.isPictureInPictureSupported() else {
                return
            }
            let pictureInPictureSource = PictureInPictureSourceWindow()
            self.pictureInPictureSource = pictureInPictureSource
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: view.displayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: source)
            controller.delegate = self
            pictureInPictureController = controller
        }

        @discardableResult
        func startPictureInPicture(reportUnavailable: Bool = true) -> Bool {
            guard let pictureInPictureController else {
                if reportUnavailable {
                    onError(L10n.string("Picture in Picture is unavailable."))
                }
                return false
            }
            guard pictureInPictureController.isPictureInPicturePossible else {
                if reportUnavailable {
                    onError(L10n.string("Picture in Picture is not ready yet."))
                }
                return false
            }
            isPictureInPictureProtected = true
            moveDisplayLayerToPictureInPictureSource()
            pictureInPictureController.startPictureInPicture()
            return true
        }

        func stopPictureInPicture() {
            guard pictureInPictureController?.isPictureInPictureActive == true else {
                isPictureInPictureProtected = false
                restorePictureInPictureWorkaround()
                return
            }
            pictureInPictureController?.stopPictureInPicture()
        }

        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            isPictureInPictureProtected = true
            FloatingVideoWindowController.shared.pictureInPictureDidStart()
            applyPictureInPictureWorkaround()
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            isPictureInPictureProtected = false
            FloatingVideoWindowController.shared.pictureInPictureDidStop(preservePreference: isTearingDown)
            restorePictureInPictureWorkaround()
            startDesiredStreamIfNeeded()
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            isPictureInPictureProtected = false
            FloatingVideoWindowController.shared.pictureInPictureDidFailToStart()
            restorePictureInPictureWorkaround()
            startDesiredStreamIfNeeded()
            onError(error.localizedDescription)
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            setPlaying playing: Bool
        ) {
            guard let timebase = view?.displayLayer.controlTimebase else {
                return
            }
            CMTimebaseSetRate(timebase, rate: playing ? 1 : 0)
        }

        func pictureInPictureControllerTimeRangeForPlayback(
            _ pictureInPictureController: AVPictureInPictureController
        ) -> CMTimeRange {
            CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }

        func pictureInPictureControllerIsPlaybackPaused(
            _ pictureInPictureController: AVPictureInPictureController
        ) -> Bool {
            guard let timebase = view?.displayLayer.controlTimebase else {
                return false
            }
            return CMTimebaseGetRate(timebase) == 0
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            didTransitionToRenderSize newRenderSize: CMVideoDimensions
        ) {
            if pictureInPictureWindow()?.contentView == nil {
                syncPictureInPictureSourceWindow(to: NSSize(width: CGFloat(newRenderSize.width), height: CGFloat(newRenderSize.height)))
            }
            refreshPictureInPictureLayout()
            schedulePictureInPictureLayoutRefreshes(after: [0.05, 0.15])
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            skipByInterval skipInterval: CMTime,
            completion: @escaping @Sendable () -> Void
        ) {
            completion()
        }

        private func applyPictureInPictureWorkaround() {
            refreshPictureInPictureLayout()
            observePictureInPictureWindowResize()
            schedulePictureInPictureLayoutRefreshes(after: [0.05, 0.15, 0.35])
        }

        private func refreshPictureInPictureLayoutAfterReconnectIfNeeded() {
            guard isPictureInPictureActiveOrStarting else {
                needsPictureInPictureLayoutRefreshAfterNextFrame = false
                return
            }
            needsPictureInPictureLayoutRefreshAfterNextFrame = true
            moveDisplayLayerToPictureInPictureSource()
            refreshPictureInPictureLayout()
            schedulePictureInPictureLayoutRefreshes(after: [0.05, 0.15, 0.35, 0.75])
        }

        private func refreshPictureInPictureLayoutAfterFrameIfNeeded() {
            guard needsPictureInPictureLayoutRefreshAfterNextFrame else {
                return
            }
            needsPictureInPictureLayoutRefreshAfterNextFrame = false
            refreshPictureInPictureLayout()
            schedulePictureInPictureLayoutRefreshes(after: [0.05, 0.15, 0.35])
        }

        private func refreshPictureInPictureLayout() {
            guard isPictureInPictureActiveOrStarting else {
                return
            }
            syncPictureInPictureSourceWindowToPiPWindow()
            hideBrokenPictureInPictureOverlay()
        }

        private func restorePictureInPictureWorkaround() {
            if let pipResizeObserver {
                NotificationCenter.default.removeObserver(pipResizeObserver)
                self.pipResizeObserver = nil
            }
            needsPictureInPictureLayoutRefreshAfterNextFrame = false
            moveDisplayLayerToPreview()
            pictureInPictureSource?.restore()
            view?.needsLayout = true
        }

        private func observePictureInPictureWindowResize() {
            guard pipResizeObserver == nil,
                  let pipContentView = pictureInPictureWindow()?.contentView else {
                return
            }
            pipContentView.postsFrameChangedNotifications = true
            pipResizeObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: pipContentView,
                queue: .main
            ) { [weak self] _ in
                self?.refreshPictureInPictureLayout()
            }
        }

        private func syncPictureInPictureSourceWindowToPiPWindow() {
            guard let pipContentView = pictureInPictureWindow()?.contentView else {
                return
            }
            syncPictureInPictureSourceWindow(to: pipContentView.bounds.size)
        }

        private func syncPictureInPictureSourceWindow(to size: NSSize) {
            pictureInPictureSource?.resizeToPictureInPictureContentSize(size)
        }

        private func schedulePictureInPictureLayoutRefreshes(after delays: [TimeInterval]) {
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.refreshPictureInPictureLayout()
                }
            }
        }

        private func moveDisplayLayerToPictureInPictureSource() {
            guard let view, let pictureInPictureSource else {
                return
            }
            pictureInPictureSource.attach(displayLayer: view.displayLayer)
        }

        private func moveDisplayLayerToPreview() {
            guard let view else {
                return
            }
            view.attachDisplayLayer()
        }

        private func hideBrokenPictureInPictureOverlay() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let contentView = self.pictureInPictureWindow()?.contentView else {
                    return
                }
                self.walkViews(contentView) { candidate in
                    if String(describing: type(of: candidate)) == "AVPictureInPictureCALayerHostView" {
                        candidate.isHidden = true
                    }
                }
            }
        }

        private func walkViews(_ view: NSView, visit: (NSView) -> Void) {
            visit(view)
            view.subviews.forEach { walkViews($0, visit: visit) }
        }

        private func pictureInPictureWindow() -> NSWindow? {
            NSApplication.shared.windows.first {
                String(describing: type(of: $0)).contains("PIPPanel")
            }
        }
    }
}

private final class VideoHostContainerView: NSView {
    let videoView = VideoLayerHostView()
    var onWindowVisibilityChange: ((Bool) -> Void)?

    private weak var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(videoView)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.topAnchor.constraint(equalTo: topAnchor),
            videoView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeWindowObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        observedWindow = window

        guard let window else {
            onWindowVisibilityChange?(false)
            return
        }

        notifyWindowVisibility(window)
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.notifyWindowVisibility(window)
            },
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onWindowVisibilityChange?(false)
            },
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onWindowVisibilityChange?(false)
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.notifyWindowVisibility(window)
            }
        ]
    }

    private func notifyWindowVisibility(_ window: NSWindow) {
        onWindowVisibilityChange?(window.isVisible && window.occlusionState.contains(.visible))
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
        observedWindow = nil
    }
}

private final class VideoLayerHostView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.backgroundColor = NSColor.clear.cgColor
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let timebase {
            CMTimebaseSetTime(timebase, time: .zero)
            CMTimebaseSetRate(timebase, rate: 1)
            displayLayer.controlTimebase = timebase
        }
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard let layer, displayLayer.superlayer === layer else {
            return
        }
        layoutDisplayLayer(in: layer)
    }

    func attachDisplayLayer() {
        guard let layer else {
            return
        }
        displayLayer.removeFromSuperlayer()
        displayLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(displayLayer)
        needsLayout = true
        layoutSubtreeIfNeeded()
        layoutDisplayLayer(in: layer)
    }

    private func layoutDisplayLayer(in hostLayer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostLayer.bounds = bounds
        displayLayer.bounds = bounds
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}

private final class PictureInPictureSourceWindow {
    private static let defaultFrame = NSRect(x: 0, y: 0, width: 480, height: 270)

    private let videoHostView = NSView(frame: defaultFrame)

    private let window: NSPanel
    private var savedFrame: NSRect?
    private var savedAlphaValue: CGFloat?
    private weak var displayLayer: AVSampleBufferDisplayLayer?

    deinit {
        close()
    }

    init() {
        videoHostView.wantsLayer = true

        window = NSPanel(
            contentRect: Self.defaultFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = videoHostView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    }

    func show() {
        guard !window.isVisible else {
            return
        }
        window.orderFrontRegardless()
    }

    func attach(displayLayer: AVSampleBufferDisplayLayer) {
        show()
        videoHostView.wantsLayer = true
        guard let hostLayer = videoHostView.layer else {
            return
        }
        self.displayLayer = displayLayer
        displayLayer.removeFromSuperlayer()
        displayLayer.videoGravity = .resizeAspect
        hostLayer.addSublayer(displayLayer)
        hostLayer.needsDisplayOnBoundsChange = true
        displayLayer.needsDisplayOnBoundsChange = true
        resizeLayerToHostBounds()
    }

    func resizeToPictureInPictureContentSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }
        show()
        if savedFrame == nil {
            savedFrame = window.frame
            savedAlphaValue = window.alphaValue
        }

        let frame = NSRect(
            x: window.frame.origin.x,
            y: window.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true)
        window.alphaValue = 0
        videoHostView.frame = NSRect(origin: .zero, size: size)
        resizeLayerToHostBounds()
    }

    func restore() {
        if let savedFrame {
            window.setFrame(savedFrame, display: true)
            self.savedFrame = nil
        }
        window.alphaValue = savedAlphaValue ?? 0
        savedAlphaValue = nil
        displayLayer = nil
        window.orderOut(nil)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    private func resizeLayerToHostBounds() {
        guard let displayLayer else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoHostView.needsLayout = true
        videoHostView.layoutSubtreeIfNeeded()
        videoHostView.layer?.bounds = videoHostView.bounds
        displayLayer.bounds = videoHostView.bounds
        displayLayer.position = CGPoint(x: videoHostView.bounds.midX, y: videoHostView.bounds.midY)
        displayLayer.frame = videoHostView.bounds
        displayLayer.setNeedsLayout()
        displayLayer.layoutIfNeeded()
        CATransaction.commit()
    }
}

private final class NativeRTSPVideoClient {
    private static let logger = Logger(subsystem: "com.kookxiang.bambuCompanion", category: "VideoStream")
    private static let initialReconnectDelay: TimeInterval = 1
    private static let maximumReconnectDelay: TimeInterval = 30

    private let url: URL
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private let onError: (String?) -> Void
    private let queue = DispatchQueue(label: "BambuCompanion.NativeRTSPVideoClient")
    private let enqueueQueue = DispatchQueue(label: "BambuCompanion.NativeRTSPVideoClient.enqueue")
    private var connection: NWConnection?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectDelay = NativeRTSPVideoClient.initialReconnectDelay
    private var receiveBuffer = Data()
    private var cseq = 1
    private var session: String?
    private var digestChallenge: DigestChallenge?
    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var describedCurrentResolution: VideoResolution?
    private var describedVideoResolutions: [VideoResolution] = []
    private var fuBuffer = Data()
    private var currentAccessUnit = Data()
    private var currentAccessUnitTimestamp: UInt32?
    private var firstRTPTimestamp: UInt32?
    private var didDisplayFrame = false
    private var pendingSampleBuffer: CMSampleBuffer?
    private var isDisplayFrameScheduled = false
    private var isStopped = false
    private let onFrame: () -> Void
    private let onConnected: () -> Void

    init(
        url: URL,
        displayLayer: AVSampleBufferDisplayLayer,
        onFrame: @escaping () -> Void,
        onConnected: @escaping () -> Void,
        onError: @escaping (String?) -> Void
    ) {
        self.url = url
        self.displayLayer = displayLayer
        self.onFrame = onFrame
        self.onConnected = onConnected
        self.onError = onError
    }

    func start() {
        queue.async {
            Self.logger.warning("Starting video stream: \(self.streamIdentifier, privacy: .public)")
            self.isStopped = false
            self.connect()
        }
    }

    func stop() {
        queue.async {
            Self.logger.warning("Stopping video stream: \(self.streamIdentifier, privacy: .public)")
            self.isStopped = true
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.connection?.cancel()
            self.connection = nil
            self.resetConnectionState()
        }
    }

    private var streamIdentifier: String {
        let host = url.host ?? "unknown-host"
        let port = url.port.map(String.init) ?? "unknown-port"
        return "\(host):\(port)\(url.path)"
    }

    private func connect() {
        guard !isStopped else {
            return
        }
        guard let host = url.host, let port = url.port else {
            fail("Video stream URL is invalid.", shouldRetry: false)
            return
        }
        resetConnectionState()
        flushDisplayLayerForReconnect()

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in
            complete(true)
        }, queue)

        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                guard self.connection === connection else {
                    return
                }
                switch state {
                case .ready:
                    self.receiveLoop()
                    self.performHandshake()
                case .failed(let error):
                    self.fail("Video connection failed: \(error.localizedDescription)")
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func performHandshake() {
        sendRequest(method: "OPTIONS", uri: baseURI(), headers: [:]) { _ in
            self.sendDescribe(withAuthorization: false)
        }
    }

    private func sendDescribe(withAuthorization: Bool) {
        sendRequest(method: "DESCRIBE", uri: baseURI(), headers: ["Accept": "application/sdp"], authorized: withAuthorization) { response in
            if response.statusCode == 401, let header = response.headers["www-authenticate"] {
                self.digestChallenge = DigestChallenge(header: header)
                self.sendDescribe(withAuthorization: true)
                return
            }
            guard response.statusCode == 200 else {
                self.fail("Video DESCRIBE failed.")
                return
            }
            let sdp = String(data: response.body, encoding: .utf8) ?? ""
            let media = SDPVideoMedia(sdp: sdp)
            self.sps = media.sps
            self.pps = media.pps
            self.describedCurrentResolution = media.selectedResolution
            self.describedVideoResolutions = media.resolutions
            self.updateFormatDescriptionIfNeeded()
            self.sendSetup(control: media.control ?? "track1")
        }
    }

    private func sendSetup(control: String) {
        let setupURI = trackURI(control: control)
        sendRequest(
            method: "SETUP",
            uri: setupURI,
            headers: ["Transport": "RTP/AVP/TCP;unicast;interleaved=0-1"],
            authorized: true
        ) { response in
            guard response.statusCode == 200 else {
                self.fail("Video SETUP failed.")
                return
            }
            self.session = response.headers["session"]?.split(separator: ";").first.map(String.init)
            self.sendPlay()
        }
    }

    private func sendPlay() {
        var headers = ["Range": "npt=0.000-"]
        if let session {
            headers["Session"] = session
        }
        sendRequest(method: "PLAY", uri: playURI(), headers: headers, authorized: true) { response in
            guard response.statusCode == 200 else {
                self.fail("Video PLAY failed.")
                return
            }
            self.markStreamConnected()
        }
    }

    private struct PendingResponse {
        let cseq: Int
        let completion: (RTSPResponse) -> Void
    }

    private var pendingResponses: [Int: PendingResponse] = [:]

    private func sendRequest(
        method: String,
        uri: String,
        headers: [String: String],
        authorized: Bool = false,
        completion: @escaping (RTSPResponse) -> Void
    ) {
        let requestCSeq = cseq
        cseq += 1

        var lines = [
            "\(method) \(uri) RTSP/1.0",
            "CSeq: \(requestCSeq)",
            "User-Agent: BambuCompanion"
        ]
        if let session = headers["Session"] {
            lines.append("Session: \(session)")
        }
        if authorized, let authorization = authorizationHeader(method: method, uri: uri) {
            lines.append("Authorization: \(authorization)")
        }
        for (key, value) in headers where key != "Session" {
            lines.append("\(key): \(value)")
        }
        lines.append("")
        lines.append("")

        guard let connection else {
            fail("Video connection is unavailable.")
            return
        }
        pendingResponses[requestCSeq] = PendingResponse(cseq: requestCSeq, completion: completion)
        let data = Data(lines.joined(separator: "\r\n").utf8)
        connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
            if let error {
                self?.queue.async {
                    guard let self,
                          let connection,
                          self.connection === connection else {
                        return
                    }
                    self.fail("Video request failed: \(error.localizedDescription)")
                }
            }
        })
    }

    private func receiveLoop() {
        guard let connection else {
            fail("Video connection is unavailable.")
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                guard let connection,
                      self.connection === connection else {
                    return
                }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.parseIncomingData()
                }
                if let error {
                    self.fail("Video receive failed: \(error.localizedDescription)")
                    return
                }
                if isComplete {
                    self.fail("Video connection closed.")
                    return
                }
                if !isComplete {
                    self.receiveLoop()
                }
            }
        }
    }

    private func parseIncomingData() {
        while !receiveBuffer.isEmpty {
            if receiveBuffer.first == 0x24 {
                guard receiveBuffer.count >= 4 else { return }
                let channel = receiveBuffer[receiveBuffer.startIndex + 1]
                let length = Int(receiveBuffer[receiveBuffer.startIndex + 2]) << 8 | Int(receiveBuffer[receiveBuffer.startIndex + 3])
                guard receiveBuffer.count >= 4 + length else { return }
                let payloadStart = receiveBuffer.startIndex + 4
                let payloadEnd = payloadStart + length
                let payload = Data(receiveBuffer[payloadStart..<payloadEnd])
                receiveBuffer.removeSubrange(receiveBuffer.startIndex..<payloadEnd)
                if channel == 0 {
                    handleRTPPacket(payload)
                }
                continue
            }

            guard let response = nextRTSPResponse() else {
                return
            }
            if let cseq = response.cseq, let pending = pendingResponses.removeValue(forKey: cseq) {
                pending.completion(response)
            }
        }
    }

    private func nextRTSPResponse() -> RTSPResponse? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = receiveBuffer.range(of: separator) else {
            return nil
        }
        let headerEnd = headerRange.upperBound
        let headerData = receiveBuffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            receiveBuffer.removeSubrange(receiveBuffer.startIndex..<headerEnd)
            return nil
        }

        var lines = headerText.components(separatedBy: "\r\n")
        let statusLine = lines.isEmpty ? "" : lines.removeFirst()
        let statusCode = Int(statusLine.split(separator: " ").dropFirst().first ?? "") ?? 0
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        guard receiveBuffer.count >= headerEnd + contentLength else {
            return nil
        }
        let bodyEnd = headerEnd + contentLength
        let body = Data(receiveBuffer[headerEnd..<bodyEnd])
        receiveBuffer.removeSubrange(receiveBuffer.startIndex..<bodyEnd)
        return RTSPResponse(statusCode: statusCode, headers: headers, body: body)
    }

    private func handleRTPPacket(_ packet: Data) {
        guard packet.count >= 12 else { return }
        let csrcCount = Int(packet[0] & 0x0F)
        let hasExtension = (packet[0] & 0x10) != 0
        var offset = 12 + csrcCount * 4
        guard packet.count > offset else { return }
        if hasExtension {
            guard packet.count >= offset + 4 else { return }
            let extensionLength = Int(packet[offset + 2]) << 8 | Int(packet[offset + 3])
            offset += 4 + extensionLength * 4
            guard packet.count > offset else { return }
        }
        let marker = (packet[1] & 0x80) != 0
        let timestamp = UInt32(packet[4]) << 24 | UInt32(packet[5]) << 16 | UInt32(packet[6]) << 8 | UInt32(packet[7])
        handleH264Payload(Data(packet[offset...]), timestamp: timestamp, marker: marker)
    }

    private func handleH264Payload(_ payload: Data, timestamp: UInt32, marker: Bool) {
        guard let first = payload.first else { return }
        let type = first & 0x1F
        switch type {
        case 1...23:
            handleNALUnit(payload, timestamp: timestamp, marker: marker)
        case 24:
            handleSTAPA(payload.dropFirst(), timestamp: timestamp, marker: marker)
        case 28:
            handleFUA(payload, timestamp: timestamp, marker: marker)
        default:
            break
        }
    }

    private func handleSTAPA(_ payload: Data.SubSequence, timestamp: UInt32, marker: Bool) {
        var offset = payload.startIndex
        while payload.distance(from: offset, to: payload.endIndex) >= 2 {
            let size = Int(payload[offset]) << 8 | Int(payload[payload.index(after: offset)])
            offset = payload.index(offset, offsetBy: 2)
            guard payload.distance(from: offset, to: payload.endIndex) >= size else { return }
            let end = payload.index(offset, offsetBy: size)
            handleNALUnit(Data(payload[offset..<end]), timestamp: timestamp, marker: false)
            offset = end
        }
        if marker {
            enqueueCurrentAccessUnit(timestamp: timestamp)
        }
    }

    private func handleFUA(_ payload: Data, timestamp: UInt32, marker: Bool) {
        guard payload.count >= 2 else { return }
        let indicator = payload[0]
        let header = payload[1]
        let start = (header & 0x80) != 0
        let end = (header & 0x40) != 0
        let nalHeader = (indicator & 0xE0) | (header & 0x1F)

        if start {
            fuBuffer.removeAll(keepingCapacity: true)
            fuBuffer.append(nalHeader)
        }
        guard !fuBuffer.isEmpty else { return }
        fuBuffer.append(payload.dropFirst(2))
        if end {
            handleNALUnit(fuBuffer, timestamp: timestamp, marker: marker)
            fuBuffer.removeAll(keepingCapacity: true)
        }
    }

    private func handleNALUnit(_ nalUnit: Data, timestamp: UInt32, marker: Bool) {
        guard let first = nalUnit.first else { return }
        switch first & 0x1F {
        case 7:
            sps = nalUnit
            updateFormatDescriptionIfNeeded()
        case 8:
            pps = nalUnit
            updateFormatDescriptionIfNeeded()
        case 1, 5:
            appendToCurrentAccessUnit(nalUnit, timestamp: timestamp)
            if marker {
                enqueueCurrentAccessUnit(timestamp: timestamp)
            }
        default:
            break
        }
    }

    private func updateFormatDescriptionIfNeeded() {
        guard let sps, let pps else { return }
        formatDescription = makeH264FormatDescription(sps: sps, pps: pps)
    }

    private func appendToCurrentAccessUnit(_ nalUnit: Data, timestamp: UInt32) {
        if let currentAccessUnitTimestamp, currentAccessUnitTimestamp != timestamp {
            enqueueCurrentAccessUnit(timestamp: currentAccessUnitTimestamp)
        }
        currentAccessUnitTimestamp = timestamp
        var length = UInt32(nalUnit.count).bigEndian
        currentAccessUnit.append(Data(bytes: &length, count: 4))
        currentAccessUnit.append(nalUnit)
    }

    private func enqueueCurrentAccessUnit(timestamp: UInt32) {
        guard !currentAccessUnit.isEmpty else { return }
        enqueue(currentAccessUnit, timestamp: currentAccessUnitTimestamp ?? timestamp)
        currentAccessUnit.removeAll(keepingCapacity: true)
        currentAccessUnitTimestamp = nil
    }

    private func enqueue(_ sampleData: Data, timestamp: UInt32) {
        guard let formatDescription else { return }

        var blockBuffer: CMBlockBuffer?
        let status = sampleData.withUnsafeBytes { buffer in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: sampleData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: sampleData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return }
        sampleData.withUnsafeBytes { buffer in
            _ = CMBlockBufferReplaceDataBytes(with: buffer.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: sampleData.count)
        }

        if firstRTPTimestamp == nil {
            firstRTPTimestamp = timestamp
        }
        let relativeTimestamp = timestamp &- (firstRTPTimestamp ?? timestamp)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: CMTimeValue(relativeTimestamp), timescale: 90_000),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = sampleData.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else { return }
        enqueueQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSampleBuffer = sampleBuffer
            guard !self.isDisplayFrameScheduled else {
                return
            }
            self.isDisplayFrameScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingSample()
            }
        }
    }

    private func flushPendingSample() {
        guard let layer = displayLayer else {
            enqueueQueue.async { [weak self] in
                self?.pendingSampleBuffer = nil
                self?.isDisplayFrameScheduled = false
            }
            return
        }

        var sampleToRender: CMSampleBuffer?
        enqueueQueue.sync {
            sampleToRender = pendingSampleBuffer
            pendingSampleBuffer = nil
        }
        guard let sampleToRender else {
            enqueueQueue.async { [weak self] in
                self?.isDisplayFrameScheduled = false
            }
            return
        }

        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        if renderer.isReadyForMoreMediaData {
            renderer.enqueue(sampleToRender)
            onFrame()
            if !didDisplayFrame {
                didDisplayFrame = true
            }
            enqueueQueue.async { [weak self] in
                guard let self else { return }
                if pendingSampleBuffer == nil {
                    isDisplayFrameScheduled = false
                }
            }
        } else {
            enqueueQueue.async { [weak self] in
                self?.pendingSampleBuffer = sampleToRender
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.flushPendingSample()
            }
        }
    }

    private func authorizationHeader(method: String, uri: String) -> String? {
        guard let challenge = digestChallenge,
              let password = url.password(percentEncoded: false) else {
            return nil
        }
        let username = url.user(percentEncoded: false) ?? "bblp"
        let ha1 = md5("\(username):\(challenge.realm):\(password)")
        let ha2 = md5("\(method):\(uri)")
        let response = md5("\(ha1):\(challenge.nonce):\(ha2)")
        return #"Digest username="\#(username)", realm="\#(challenge.realm)", nonce="\#(challenge.nonce)", uri="\#(uri)", response="\#(response)""#
    }

    private func baseURI() -> String {
        "\(url.scheme ?? "rtsps")://\(url.host ?? ""):\(url.port ?? 322)\(url.path)"
    }

    private func playURI() -> String {
        baseURI() + "/"
    }

    private func trackURI(control: String) -> String {
        if control.hasPrefix("rtsp://") || control.hasPrefix("rtsps://") {
            return control
        }
        return playURI() + control
    }

    private func fail(_ message: String) {
        fail(message, shouldRetry: true)
    }

    private func fail(_ message: String, shouldRetry: Bool) {
        guard !isStopped else {
            return
        }
        onError("\(message) (\(url.absoluteString))")
        connection?.cancel()
        connection = nil
        pendingResponses.removeAll()
        if shouldRetry {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard !isStopped, reconnectWorkItem == nil else {
            return
        }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, Self.maximumReconnectDelay)
        Self.logger.warning("Retrying video stream in \(delay, privacy: .public) seconds: \(self.streamIdentifier, privacy: .public)")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else {
                return
            }
            self.reconnectWorkItem = nil
            self.connect()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func markStreamConnected() {
        reconnectDelay = Self.initialReconnectDelay
        flushDisplayLayerForReconnect()
        logVideoResolutions()
        onConnected()
        onError(nil)
    }

    private func flushDisplayLayerForReconnect() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopped, let displayLayer = self.displayLayer else {
                return
            }
            displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
            displayLayer.setNeedsLayout()
        }
    }

    private func logVideoResolutions() {
        let currentResolution = formatDescription.flatMap(VideoResolution.init(formatDescription:)) ?? describedCurrentResolution
        let supportedResolutions = describedVideoResolutions.isEmpty
            ? currentResolution.map { [$0] } ?? []
            : describedVideoResolutions
        let currentDescription = currentResolution?.description ?? "unknown"
        let supportedDescription = supportedResolutions.isEmpty
            ? "unknown"
            : supportedResolutions.map(\.description).joined(separator: ", ")

        Self.logger.warning(
            "Video stream connected: \(self.streamIdentifier, privacy: .public), current resolution: \(currentDescription, privacy: .public), supported resolutions: \(supportedDescription, privacy: .public)"
        )
    }

    private func resetConnectionState() {
        receiveBuffer.removeAll(keepingCapacity: false)
        pendingResponses.removeAll(keepingCapacity: false)
        cseq = 1
        session = nil
        digestChallenge = nil
        sps = nil
        pps = nil
        formatDescription = nil
        describedCurrentResolution = nil
        describedVideoResolutions = []
        fuBuffer.removeAll(keepingCapacity: false)
        currentAccessUnit.removeAll(keepingCapacity: false)
        currentAccessUnitTimestamp = nil
        firstRTPTimestamp = nil
        didDisplayFrame = false
        enqueueQueue.async { [weak self] in
            self?.pendingSampleBuffer = nil
            self?.isDisplayFrameScheduled = false
        }
    }

}

private struct RTSPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    var cseq: Int? {
        Int(headers["cseq"] ?? "")
    }
}

private struct VideoResolution: Hashable, CustomStringConvertible {
    let width: Int32
    let height: Int32

    var description: String {
        "\(width)x\(height)"
    }

    var pixelCount: Int64 {
        Int64(width) * Int64(height)
    }

    init?(width: Int32, height: Int32) {
        guard width > 0, height > 0 else {
            return nil
        }
        self.width = width
        self.height = height
    }

    init?(formatDescription: CMVideoFormatDescription) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        self.init(width: dimensions.width, height: dimensions.height)
    }

    static func uniqueSortedByQuality(_ resolutions: [VideoResolution]) -> [VideoResolution] {
        var seen: Set<VideoResolution> = []
        var result: [VideoResolution] = []
        for resolution in resolutions.sorted(by: { $0.pixelCount > $1.pixelCount }) where !seen.contains(resolution) {
            seen.insert(resolution)
            result.append(resolution)
        }
        return result
    }
}

private struct DigestChallenge {
    let realm: String
    let nonce: String

    init?(header: String) {
        guard header.localizedCaseInsensitiveContains("Digest") else {
            return nil
        }
        let values = Self.values(from: header)
        guard let realm = values["realm"], let nonce = values["nonce"] else {
            return nil
        }
        self.realm = realm
        self.nonce = nonce
    }

    private static func values(from header: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in header.replacingOccurrences(of: "Digest", with: "").split(separator: ",") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pieces[1].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            result[key] = value
        }
        return result
    }
}

private struct SDPVideoMedia {
    let control: String?
    let sps: Data?
    let pps: Data?
    let selectedResolution: VideoResolution?
    let resolutions: [VideoResolution]

    init(sdp: String) {
        var fallbackStream = Stream()
        var streams: [Stream] = []
        var currentStream: Stream?
        var didSeeMediaSection = false

        for line in sdp.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("m=") {
                if let currentStream {
                    streams.append(currentStream)
                }
                didSeeMediaSection = true
                currentStream = line.hasPrefix("m=video") ? Stream() : nil
                continue
            }

            if var stream = currentStream {
                stream.apply(line: line)
                currentStream = stream
            } else if !didSeeMediaSection {
                fallbackStream.apply(line: line)
            }
        }

        if let currentStream {
            streams.append(currentStream)
        }
        if streams.isEmpty, fallbackStream.hasMediaInfo {
            streams.append(fallbackStream)
        }

        let selected = streams.max { lhs, rhs in
            (lhs.bestResolution?.pixelCount ?? 0) < (rhs.bestResolution?.pixelCount ?? 0)
        }
        let resolutions = VideoResolution.uniqueSortedByQuality(streams.flatMap(\.resolutions))

        self.control = selected?.normalizedControl
        self.sps = selected?.sps
        self.pps = selected?.pps
        self.selectedResolution = selected?.bestResolution
        self.resolutions = resolutions
    }

    private struct Stream {
        var control: String?
        var sps: Data?
        var pps: Data?
        var resolutions: [VideoResolution] = []

        var normalizedControl: String? {
            control == "*" ? nil : control
        }

        var bestResolution: VideoResolution? {
            resolutions.max { $0.pixelCount < $1.pixelCount }
        }

        var hasMediaInfo: Bool {
            control != nil || sps != nil || pps != nil || !resolutions.isEmpty
        }

        mutating func apply(line: String) {
            if line.hasPrefix("a=control:") {
                control = String(line.dropFirst("a=control:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let resolution = Self.frameSize(from: line) {
                resolutions.append(resolution)
            }
            let parameterSets = Self.parameterSets(from: line)
            guard let parameterSPS = parameterSets.first else {
                return
            }
            sps = parameterSPS
            pps = parameterSets.dropFirst().first
            if let pps,
               let formatDescription = makeH264FormatDescription(sps: parameterSPS, pps: pps),
               let resolution = VideoResolution(formatDescription: formatDescription) {
                resolutions.append(resolution)
            }
        }

        private static func frameSize(from line: String) -> VideoResolution? {
            guard line.hasPrefix("a=framesize:") else {
                return nil
            }
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else {
                return nil
            }
            let dimensions = parts[1].split(separator: "-", maxSplits: 1)
            guard dimensions.count == 2,
                  let width = Int32(dimensions[0]),
                  let height = Int32(dimensions[1]) else {
                return nil
            }
            return VideoResolution(width: width, height: height)
        }

        private static func parameterSets(from line: String) -> [Data] {
            guard line.hasPrefix("a=fmtp:"),
                  let range = line.range(of: "sprop-parameter-sets=") else {
                return []
            }
            let value = line[range.upperBound...]
                .split(separator: ";", maxSplits: 1)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?
                .split(separator: ",")
                .compactMap { Data(base64Encoded: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) } ?? []
        }
    }
}

private func makeH264FormatDescription(sps: Data, pps: Data) -> CMVideoFormatDescription? {
    var formatDescription: CMVideoFormatDescription?
    sps.withUnsafeBytes { spsBuffer in
        pps.withUnsafeBytes { ppsBuffer in
            guard let spsBaseAddress = spsBuffer.baseAddress,
                  let ppsBaseAddress = ppsBuffer.baseAddress else {
                return
            }
            var parameterSetPointers = [
                spsBaseAddress.assumingMemoryBound(to: UInt8.self),
                ppsBaseAddress.assumingMemoryBound(to: UInt8.self)
            ]
            var parameterSetSizes = [sps.count, pps.count]
            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: 2,
                parameterSetPointers: &parameterSetPointers,
                parameterSetSizes: &parameterSetSizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &formatDescription
            )
            if status != noErr {
                formatDescription = nil
            }
        }
    }
    return formatDescription
}

private func md5(_ value: String) -> String {
    Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}
