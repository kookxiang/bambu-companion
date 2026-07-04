import AVFoundation
import CryptoKit
import Network
import OSLog
import SwiftUI
import AppKit

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
    @Environment(\.dismiss) private var dismiss
    private let staleFrameCheckTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var cornerRadius: CGFloat {
        showFloatingButton ? 8 : FloatingVideoWindowController.cornerRadius
    }
    private var effectiveURL: URL? {
        showFloatingButton && floatingVideoWindowController.isShowing ? nil : url
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

            if showFloatingButton && floatingVideoWindowController.isShowing {
                floatingPlaceholder
            } else if let errorMessage = streamState.errorMessage {
                placeholder(icon: "video.slash", text: errorMessage)
            } else if effectiveURL != nil, !streamState.hasVideo {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Connecting video...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if url == nil {
                placeholder(icon: "video.slash", text: L10n.string("Video preview is unavailable."))
            }

            if streamState.isWaitingForFrame && effectiveURL != nil && streamState.errorMessage == nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            }

            if effectiveURL != nil {
                VStack {
                    HStack(spacing: 8) {
                        if !showFloatingButton {
                            floatingCloseButton
                        }
                        videoReconnectButton
                        if streamState.hasVideo && showFloatingButton && !floatingVideoWindowController.isShowing {
                            openFloatingButton
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(controlPadding)
                .opacity(isHoveringFloatingWindow ? 1 : 0)
                .animation(.easeOut(duration: 0.16), value: isHoveringFloatingWindow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: showFloatingButton ? 191 : nil)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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

    private var floatingPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "pip.enter")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Showing in Picture in Picture")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            FloatingVideoWindowController.shared.dismiss()
        }
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
            systemName: "rectangle.on.rectangle",
            accessibilityLabel: L10n.string("Open Floating Video")
        ) {
            guard url != nil else {
                return
            }
            let presentingWindow = NSApp.keyWindow
            FloatingVideoWindowController.shared.toggle(url: url)
            dismiss()
            presentingWindow?.close()
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

@MainActor
private final class VideoStreamState: ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasVideo = false
    @Published private(set) var isWaitingForFrame = false
    private var lastFrameTime: Date?
    private var didRequestAutomaticReconnect = false

    func setHasVideo() {
        if !hasVideo {
            hasVideo = true
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
        let shouldWait = hasVideo && elapsed > 1
        if isWaitingForFrame != shouldWait {
            isWaitingForFrame = shouldWait
        }
        guard elapsed >= 15, !didRequestAutomaticReconnect else {
            return false
        }
        didRequestAutomaticReconnect = true
        return true
    }
}

private struct FloatingVideoStreamView: View {
    let url: URL?

    var body: some View {
        NativeVideoStreamSurface(
            url: url,
            showFloatingButton: false
        )
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 360, minHeight: 200)
            .onAppear {
                if url == nil {
                    FloatingVideoWindowController.shared.dismiss()
                }
            }
    }
}

@MainActor
private final class FloatingVideoWindowController: ObservableObject {
    static let shared = FloatingVideoWindowController()
    static let cornerRadius: CGFloat = 28

    @Published private(set) var isShowing = false
    @Published private(set) var videoReconnectGeneration = 0

    private var panel: NSPanel?
    private var delegate: FloatingVideoWindowDelegate?
    private let defaultSize = NSSize(width: 640, height: 360)
    private let defaultScreenMargin: CGFloat = 28

    @MainActor func toggle(url: URL?) {
        guard let url else {
            dismiss()
            return
        }
        if let panel, panel.isVisible {
            panel.close()
            isShowing = false
            return
        }
        show(url: url)
    }

    @MainActor func show(url: URL) {
        if let panel {
            if let host = panel.contentViewController as? NSHostingController<FloatingVideoStreamView> {
                host.rootView = FloatingVideoStreamView(url: url)
            } else {
                let controller = NSHostingController(
                    rootView: FloatingVideoStreamView(url: url)
                )
                controller.view.autoresizingMask = [.width, .height]
                panel.contentViewController = controller
            }
            panel.contentViewController?.view.frame = panel.contentView?.bounds ?? .zero
            panel.makeKeyAndOrderFront(nil)
            panel.deminiaturize(nil)
            isShowing = true
            return
        }

        let panel = makePanel()
        let controller = NSHostingController(
            rootView: FloatingVideoStreamView(url: url)
        )
        controller.view.autoresizingMask = [.width, .height]
        panel.contentViewController = controller
        panel.setFrame(defaultPanelFrame(), display: false)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        isShowing = true
    }

    @MainActor func dismiss() {
        isShowing = false
        panel?.close()
    }

    @MainActor func reconnectVideo() {
        videoReconnectGeneration += 1
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = Self.cornerRadius
        panel.contentView?.layer?.masksToBounds = true
        panel.contentView?.layer?.cornerCurve = .continuous

        let panelDelegate = FloatingVideoWindowDelegate { [weak self] in
            self?.panel = nil
            self?.delegate = nil
            self?.isShowing = false
        }
        panel.delegate = panelDelegate
        delegate = panelDelegate
        panel.contentView?.autoresizesSubviews = true
        return panel
    }

    private func defaultPanelFrame() -> NSRect {
        let visibleFrame = defaultScreen().visibleFrame
        let x = max(
            visibleFrame.minX + defaultScreenMargin,
            visibleFrame.maxX - defaultSize.width - defaultScreenMargin
        )
        let y = visibleFrame.minY + defaultScreenMargin
        return NSRect(origin: NSPoint(x: x, y: y), size: defaultSize)
    }

    private func defaultScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class FloatingVideoWindowDelegate: NSObject, NSWindowDelegate {
    private let snapMargin: CGFloat = 28
    private let snapThreshold: CGFloat = 72
    private let onClose: () -> Void
    private var pendingSnapWorkItem: DispatchWorkItem?
    private var isSnapping = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        pendingSnapWorkItem?.cancel()
        onClose()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isSnapping,
              let window = notification.object as? NSWindow else {
            return
        }
        pendingSnapWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak window] in
            guard let self,
                  let window else {
                return
            }
            self.snapWindowIfNeeded(window)
        }
        pendingSnapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func snapWindowIfNeeded(_ window: NSWindow) {
        guard let snappedFrame = snappedFrame(for: window) else {
            return
        }
        isSnapping = true
        window.setFrame(snappedFrame, display: true, animate: true)
        isSnapping = false
    }

    private func snappedFrame(for window: NSWindow) -> NSRect? {
        let frame = window.frame
        let visibleFrame = (window.screen ?? screen(containing: frame) ?? NSScreen.main)?.visibleFrame
        guard let visibleFrame else {
            return nil
        }

        let leftX = visibleFrame.minX + snapMargin
        let rightX = visibleFrame.maxX - frame.width - snapMargin
        let bottomY = visibleFrame.minY + snapMargin
        let topY = visibleFrame.maxY - frame.height - snapMargin

        let horizontalSnap: CGFloat?
        if abs(frame.minX - leftX) <= snapThreshold {
            horizontalSnap = leftX
        } else if abs(frame.minX - rightX) <= snapThreshold {
            horizontalSnap = rightX
        } else {
            horizontalSnap = nil
        }

        let verticalSnap: CGFloat?
        if abs(frame.minY - bottomY) <= snapThreshold {
            verticalSnap = bottomY
        } else if abs(frame.minY - topY) <= snapThreshold {
            verticalSnap = topY
        } else {
            verticalSnap = nil
        }

        guard let x = horizontalSnap,
              let y = verticalSnap else {
            return nil
        }
        let snappedFrame = NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
        return snappedFrame == frame ? nil : snappedFrame
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
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

    final class Coordinator {
        private let onError: (String?) -> Void
        private weak var view: VideoLayerHostView?
        private var client: NativeRTSPVideoClient?
        private var currentURL: URL?
        private var currentReconnectID = 0
        private var desiredURL: URL?
        private var desiredReconnectID = 0
        private var desiredOnFrame: (() -> Void)?
        private var isWindowVisible = true

        init(onError: @escaping (String?) -> Void) {
            self.onError = onError
        }

        func attach(to view: VideoLayerHostView) {
            self.view = view
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
            } else {
                currentURL = nil
                stopStream()
            }
        }

        private func startDesiredStreamIfNeeded() {
            guard isWindowVisible else {
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
                onFrame: onFrame
            ) { [weak self] message in
                DispatchQueue.main.async {
                    self?.onError(message)
                }
            }
            self.client = client
            client.start()
        }

        func stop() {
            desiredURL = nil
            desiredOnFrame = nil
            currentURL = nil
            stopStream()
        }

        private func stopStream() {
            client?.stop()
            client = nil
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
        displayLayer.frame = bounds
    }
}

private final class NativeRTSPVideoClient {
    private static let logger = Logger(subsystem: "com.kookxiang.bambuCompanion", category: "VideoStream")

    private let url: URL
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private let onError: (String) -> Void
    private let queue = DispatchQueue(label: "BambuCompanion.NativeRTSPVideoClient")
    private let enqueueQueue = DispatchQueue(label: "BambuCompanion.NativeRTSPVideoClient.enqueue")
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var cseq = 1
    private var session: String?
    private var digestChallenge: DigestChallenge?
    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var fuBuffer = Data()
    private var currentAccessUnit = Data()
    private var currentAccessUnitTimestamp: UInt32?
    private var firstRTPTimestamp: UInt32?
    private var didDisplayFrame = false
    private var pendingSampleBuffer: CMSampleBuffer?
    private var isDisplayFrameScheduled = false
    private var isStopped = false
    private let onFrame: () -> Void

    init(
        url: URL,
        displayLayer: AVSampleBufferDisplayLayer,
        onFrame: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.url = url
        self.displayLayer = displayLayer
        self.onFrame = onFrame
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
            self.connection?.cancel()
            self.connection = nil
            self.receiveBuffer.removeAll(keepingCapacity: false)
            self.fuBuffer.removeAll(keepingCapacity: false)
            self.currentAccessUnit.removeAll(keepingCapacity: false)
            self.currentAccessUnitTimestamp = nil
            self.firstRTPTimestamp = nil
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
            fail("Video stream URL is invalid.")
            return
        }

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

        pendingResponses[requestCSeq] = PendingResponse(cseq: requestCSeq, completion: completion)
        let data = Data(lines.joined(separator: "\r\n").utf8)
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.queue.async {
                    self?.fail("Video request failed: \(error.localizedDescription)")
                }
            }
        })
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.parseIncomingData()
                }
                if let error {
                    self.fail("Video receive failed: \(error.localizedDescription)")
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
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &parameterSetPointers,
                    parameterSetSizes: &parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDescription
                )
            }
        }
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
        onError("\(message) (\(url.absoluteString))")
        connection?.cancel()
        connection = nil
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

    init(sdp: String) {
        var control: String?
        var parameterSets: [Data] = []
        for line in sdp.components(separatedBy: .newlines) {
            if line.hasPrefix("a=control:") {
                control = String(line.dropFirst("a=control:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if line.hasPrefix("a=fmtp:"),
               let range = line.range(of: "sprop-parameter-sets=") {
                let value = line[range.upperBound...]
                    .split(separator: ";", maxSplits: 1)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                parameterSets = value?
                    .split(separator: ",")
                    .compactMap { Data(base64Encoded: String($0)) } ?? []
            }
        }
        self.control = control == "*" ? nil : control
        self.sps = parameterSets.first
        self.pps = parameterSets.dropFirst().first
    }
}

private func md5(_ value: String) -> String {
    Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}
