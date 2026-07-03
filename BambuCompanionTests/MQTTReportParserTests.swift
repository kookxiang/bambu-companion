import XCTest
@testable import BambuCompanion

final class MQTTReportParserTests: XCTestCase {
    func testParsesCommonPrintReportFields() throws {
        let json = """
        {
          "print": {
            "gcode_state": "RUNNING",
            "mc_percent": 42,
            "mc_remaining_time": 93,
            "gcode_file": "benchy.3mf",
            "nozzle_temper": 221.4,
            "bed_temper": 63
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.activity, .printing)
        XCTAssertEqual(status.progress, 42)
        XCTAssertEqual(status.remainingMinutes, 93)
        XCTAssertEqual(status.jobName, "benchy.3mf")
        XCTAssertEqual(status.nozzleTemperature, 221.4)
        XCTAssertEqual(status.bedTemperature, 63)
        XCTAssertNotNil(status.updatedAt)
    }

    func testMissingFieldsRemainEmpty() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"gcode_state":"IDLE"}}"#.utf8))

        XCTAssertEqual(status.activity, .idle)
        XCTAssertNil(status.progress)
        XCTAssertNil(status.remainingMinutes)
        XCTAssertNil(status.nozzleTemperature)
        XCTAssertNil(status.bedTemperature)
    }

    func testStringNumbersAreAccepted() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"mc_percent":"7","nozzle_temper":"215.5"}}"#.utf8))

        XCTAssertEqual(status.progress, 7)
        XCTAssertEqual(status.nozzleTemperature, 215.5)
    }

    func testMQTTPublishPacketExtractsPayload() throws {
        let json = Data(#"{"print":{"gcode_state":"RUNNING"}}"#.utf8)
        var publishPayload = Data()
        publishPayload.appendMQTTString("device/serial/report")
        publishPayload.append(json)

        var buffer = Data([0x30])
        buffer.appendEncodedRemainingLength(publishPayload.count)
        buffer.append(publishPayload)

        let packet = try XCTUnwrap(buffer.consumeMQTTPacket())

        XCTAssertEqual(packet.type, 0x30)
        XCTAssertEqual(packet.publishPayload, json)
    }

    func testMQTTPublishPayloadHandlesSlicedData() throws {
        let json = Data(#"{"print":{"mc_percent":12}}"#.utf8)
        var slicedPayload = Data([0xFF])
        slicedPayload.appendMQTTString("device/serial/report")
        slicedPayload.append(json)
        slicedPayload.removeFirst()

        let packet = MQTTPacket(type: 0x30, payload: slicedPayload)

        XCTAssertEqual(packet.publishPayload, json)
    }
}
