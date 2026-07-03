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
}
