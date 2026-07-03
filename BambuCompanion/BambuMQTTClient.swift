import Foundation
import Network
import Security

protocol BambuMQTTClientDelegate: AnyObject {
    func mqttClientDidConnect(_ client: BambuMQTTClient)
    func mqttClient(_ client: BambuMQTTClient, didReceiveReport data: Data)
    func mqttClient(_ client: BambuMQTTClient, didFail error: Error)
    func mqttClientDidDisconnect(_ client: BambuMQTTClient)
}

final class BambuMQTTClient {
    enum ClientError: LocalizedError {
        case invalidPacket
        case connectionRejected(UInt8)
        case connectionCancelled

        var errorDescription: String? {
            switch self {
            case .invalidPacket:
                return "Invalid MQTT packet"
            case .connectionRejected(let code):
                return code == 4 || code == 5 ? "Authentication failed" : "MQTT connection rejected: \(code)"
            case .connectionCancelled:
                return "Connection cancelled"
            }
        }
    }

    weak var delegate: BambuMQTTClientDelegate?

    private let configuration: PrinterConfiguration
    private let queue = DispatchQueue(label: "BambuCompanion.MQTT")
    private var connection: NWConnection?
    private var readBuffer = Data()
    private var pingTimer: DispatchSourceTimer?
    private var isConnected = false

    init(configuration: PrinterConfiguration) {
        self.configuration = configuration
    }

    func connect() {
        disconnect()

        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in
            complete(true)
        }, queue)

        let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        let endpoint = NWEndpoint.Host(configuration.host.trimmingCharacters(in: .whitespacesAndNewlines))
        let connection = NWConnection(host: endpoint, port: 8883, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendConnect()
                self.receiveLoop()
            case .failed(let error):
                self.delegate?.mqttClient(self, didFail: error)
            case .cancelled:
                self.delegate?.mqttClientDidDisconnect(self)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        pingTimer?.cancel()
        pingTimer = nil
        isConnected = false
        connection?.cancel()
        connection = nil
        readBuffer.removeAll()
    }

    private func sendConnect() {
        let clientID = "bambu-companion-\(UUID().uuidString.prefix(8))"
        var variableHeader = Data()
        variableHeader.appendMQTTString("MQTT")
        variableHeader.append(0x04)
        variableHeader.append(0xC2)
        variableHeader.appendUInt16(60)

        var payload = Data()
        payload.appendMQTTString(clientID)
        payload.appendMQTTString("bblp")
        payload.appendMQTTString(configuration.accessCode)

        sendPacket(type: 0x10, payload: variableHeader + payload)
    }

    private func subscribe() {
        var payload = Data()
        payload.appendUInt16(1)
        payload.appendMQTTString("device/\(configuration.serialNumber)/report")
        payload.append(0x00)
        sendPacket(type: 0x82, payload: payload)
    }

    private func sendPing() {
        sendPacket(type: 0xC0, payload: Data())
    }

    private func sendPacket(type: UInt8, payload: Data) {
        var packet = Data([type])
        packet.appendEncodedRemainingLength(payload.count)
        packet.append(payload)
        connection?.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.delegate?.mqttClient(self, didFail: error)
        })
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.readBuffer.append(data)
                self.processBuffer()
            }
            if let error {
                self.delegate?.mqttClient(self, didFail: error)
                return
            }
            if isComplete {
                self.delegate?.mqttClientDidDisconnect(self)
                return
            }
            self.receiveLoop()
        }
    }

    private func processBuffer() {
        while let packet = readBuffer.consumeMQTTPacket() {
            handle(packet: packet)
        }
    }

    private func handle(packet: MQTTPacket) {
        switch packet.type {
        case 0x20:
            guard packet.payload.count >= 2 else {
                delegate?.mqttClient(self, didFail: ClientError.invalidPacket)
                return
            }
            let returnCode = packet.payload[1]
            guard returnCode == 0 else {
                delegate?.mqttClient(self, didFail: ClientError.connectionRejected(returnCode))
                return
            }
            isConnected = true
            delegate?.mqttClientDidConnect(self)
            subscribe()
            startPingTimer()
        case 0x30, 0x32, 0x34, 0x3A:
            if let publishPayload = packet.publishPayload {
                delegate?.mqttClient(self, didReceiveReport: publishPayload)
            }
        case 0xD0, 0x90:
            break
        default:
            break
        }
    }

    private func startPingTimer() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.sendPing()
        }
        timer.resume()
        pingTimer = timer
    }
}

struct MQTTPacket {
    let type: UInt8
    let payload: Data

    var publishPayload: Data? {
        guard type & 0xF0 == 0x30, payload.count >= 2 else {
            return nil
        }
        let topicLengthIndex = payload.startIndex
        let topicLengthNextIndex = payload.index(after: topicLengthIndex)
        let topicLength = Int(payload[topicLengthIndex]) << 8 | Int(payload[topicLengthNextIndex])
        let payloadStart = 2 + topicLength + qosPacketIdentifierLength
        guard payloadStart <= payload.count else {
            return nil
        }
        let startIndex = payload.index(payload.startIndex, offsetBy: payloadStart)
        return Data(payload[startIndex...])
    }

    private var qosPacketIdentifierLength: Int {
        let qos = (type & 0x06) >> 1
        return qos == 0 ? 0 : 2
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendMQTTString(_ value: String) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count))
        append(bytes)
    }

    mutating func appendEncodedRemainingLength(_ length: Int) {
        var value = length
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 {
                byte |= 128
            }
            append(byte)
        } while value > 0
    }

    mutating func consumeMQTTPacket() -> MQTTPacket? {
        guard count >= 2 else {
            return nil
        }

        var multiplier = 1
        var value = 0
        var index = self.index(after: startIndex)
        while index < endIndex {
            let encodedByte = self[index]
            value += Int(encodedByte & 127) * multiplier
            multiplier *= 128
            formIndex(after: &index)
            if encodedByte & 128 == 0 {
                break
            }
            if multiplier > 128 * 128 * 128 {
                removeAll()
                return nil
            }
        }

        let headerLength = distance(from: startIndex, to: index)
        let packetLength = headerLength + value
        guard count >= packetLength else {
            return nil
        }

        let payloadStart = self.index(startIndex, offsetBy: headerLength)
        let payloadEnd = self.index(startIndex, offsetBy: packetLength)
        let packet = MQTTPacket(type: self[startIndex], payload: Data(self[payloadStart..<payloadEnd]))
        removeSubrange(startIndex..<payloadEnd)
        return packet
    }
}
