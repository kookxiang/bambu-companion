import AVFoundation
import CryptoKit
import Network
import SwiftUI

struct NativeVideoPreviewView: View {
    let url: URL?
    @State private var errorMessage: String?
    @State private var hasVideo = false

    var body: some View {
        ZStack {
            NativeVideoLayerView(url: url, onFrame: {
                hasVideo = true
            }) { message in
                errorMessage = message
            }

            if let errorMessage {
                placeholder(icon: "video.slash", text: errorMessage)
            } else if url != nil, !hasVideo {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Connecting video...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if url == nil {
                placeholder(icon: "video.slash", text: "Video preview is unavailable.")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 191)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: url) {
            hasVideo = false
            errorMessage = nil
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
        }
    }
}

private struct NativeVideoLayerView: NSViewRepresentable {
    let url: URL?
    let onFrame: () -> Void
    let onError: (String?) -> Void

    func makeNSView(context: Context) -> VideoLayerHostView {
        let view = VideoLayerHostView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: VideoLayerHostView, context: Context) {
        context.coordinator.start(url: url, onFrame: onFrame)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    static func dismantleNSView(_ nsView: VideoLayerHostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private let onError: (String?) -> Void
        private weak var view: VideoLayerHostView?
        private var client: NativeRTSPVideoClient?
        private var currentURL: URL?

        init(onError: @escaping (String?) -> Void) {
            self.onError = onError
        }

        func attach(to view: VideoLayerHostView) {
            self.view = view
        }

        func start(url: URL?, onFrame: @escaping () -> Void) {
            guard let url else {
                stop()
                return
            }
            guard currentURL != url else {
                return
            }
            stop()
            currentURL = url
            onError(nil)
            view?.displayLayer.flushAndRemoveImage()

            guard let view else {
                return
            }
            let client = NativeRTSPVideoClient(url: url, displayLayer: view.displayLayer, onFrame: onFrame) { [weak self] message in
                DispatchQueue.main.async {
                    self?.onError(message)
                }
            }
            self.client = client
            client.start()
        }

        func stop() {
            currentURL = nil
            client?.stop()
            client = nil
        }
    }
}

private final class VideoLayerHostView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.backgroundColor = NSColor.clear.cgColor
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
    private let url: URL
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private let onError: (String) -> Void
    private let queue = DispatchQueue(label: "BambuCompanion.NativeRTSPVideoClient")
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
    private var didDisplayFrame = false
    private let onFrame: () -> Void

    init(url: URL, displayLayer: AVSampleBufferDisplayLayer, onFrame: @escaping () -> Void, onError: @escaping (String) -> Void) {
        self.url = url
        self.displayLayer = displayLayer
        self.onFrame = onFrame
        self.onError = onError
    }

    func start() {
        queue.async {
            self.connect()
        }
    }

    func stop() {
        queue.async {
            self.connection?.cancel()
            self.connection = nil
            self.receiveBuffer.removeAll(keepingCapacity: false)
            self.fuBuffer.removeAll(keepingCapacity: false)
            self.currentAccessUnit.removeAll(keepingCapacity: false)
        }
    }

    private func connect() {
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
        handleH264Payload(Data(packet[offset...]), marker: marker)
    }

    private func handleH264Payload(_ payload: Data, marker: Bool) {
        guard let first = payload.first else { return }
        let type = first & 0x1F
        switch type {
        case 1...23:
            handleNALUnit(payload, marker: marker)
        case 24:
            handleSTAPA(payload.dropFirst(), marker: marker)
        case 28:
            handleFUA(payload, marker: marker)
        default:
            break
        }
    }

    private func handleSTAPA(_ payload: Data.SubSequence, marker: Bool) {
        var offset = payload.startIndex
        while payload.distance(from: offset, to: payload.endIndex) >= 2 {
            let size = Int(payload[offset]) << 8 | Int(payload[payload.index(after: offset)])
            offset = payload.index(offset, offsetBy: 2)
            guard payload.distance(from: offset, to: payload.endIndex) >= size else { return }
            let end = payload.index(offset, offsetBy: size)
            handleNALUnit(Data(payload[offset..<end]), marker: false)
            offset = end
        }
        if marker {
            enqueueCurrentAccessUnit()
        }
    }

    private func handleFUA(_ payload: Data, marker: Bool) {
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
            handleNALUnit(fuBuffer, marker: marker)
            fuBuffer.removeAll(keepingCapacity: true)
        }
    }

    private func handleNALUnit(_ nalUnit: Data, marker: Bool) {
        guard let first = nalUnit.first else { return }
        switch first & 0x1F {
        case 7:
            sps = nalUnit
            updateFormatDescriptionIfNeeded()
        case 8:
            pps = nalUnit
            updateFormatDescriptionIfNeeded()
        case 1, 5:
            appendToCurrentAccessUnit(nalUnit)
            if marker {
                enqueueCurrentAccessUnit()
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

    private func appendToCurrentAccessUnit(_ nalUnit: Data) {
        var length = UInt32(nalUnit.count).bigEndian
        currentAccessUnit.append(Data(bytes: &length, count: 4))
        currentAccessUnit.append(nalUnit)
    }

    private func enqueueCurrentAccessUnit() {
        guard !currentAccessUnit.isEmpty else { return }
        enqueue(currentAccessUnit)
        currentAccessUnit.removeAll(keepingCapacity: true)
    }

    private func enqueue(_ sampleData: Data) {
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

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
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
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0,
           let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary?.self) {
            CFDictionarySetValue(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let layer = self?.displayLayer else { return }
            if layer.status == .failed {
                layer.flush()
            }
            if layer.isReadyForMoreMediaData {
                layer.enqueue(sampleBuffer)
                if self?.didDisplayFrame == false {
                    self?.didDisplayFrame = true
                    self?.onFrame()
                }
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
        onError(message)
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
