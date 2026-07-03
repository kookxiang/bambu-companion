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

    func testParsesCoverImageFileHints() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"file":"/data/Metadata/plate_1.gcode","gcode_file":"widget.gcode.3mf","gcode_file_downloaded":"downloaded.gcode","subtask_name":"Widget","gcode_file_prepare_percent":"100"}}"#.utf8))

        XCTAssertEqual(status.rawFile, "/data/Metadata/plate_1.gcode")
        XCTAssertEqual(status.gcodeFile, "widget.gcode.3mf")
        XCTAssertEqual(status.gcodeFileDownloaded, "downloaded.gcode")
        XCTAssertEqual(status.subtaskName, "Widget")
        XCTAssertEqual(status.gcodeFilePreparePercent, 100)
        XCTAssertEqual(status.jobName, "Widget")
    }

    func testParsesAMSUnitsIntoFourSlotRows() throws {
        let json = """
        {
          "print": {
            "ams": {
              "ams": [
                {
                  "id": "0",
                  "tray": [
                    {"id": "0", "tray_type": "PETG", "tray_color": "FFFFFFFF"},
                    {"id": "1", "tray_type": "PLA", "tray_color": "00FF00FF"},
                    {"id": "3", "tray_type": "ASA", "tray_color": "00000000"}
                  ]
                },
                {
                  "id": "1",
                  "tray": [
                    {"id": "0", "tray_type": "ABS", "tray_color": "#FF0000FF"}
                  ]
                }
              ]
            }
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.amsUnits.count, 2)
        XCTAssertEqual(status.amsUnits[0].name, "AMS 1")
        XCTAssertEqual(status.amsUnits[0].slots.count, 4)
        XCTAssertEqual(status.amsUnits[0].slots.map(\.material), ["PETG", "PLA", nil, "ASA"])
        XCTAssertEqual(status.amsUnits[0].slots[0].colorHex, "FFFFFF")
        XCTAssertEqual(status.amsUnits[0].slots[1].colorHex, "00FF00")
        XCTAssertNil(status.amsUnits[0].slots[3].colorHex)
        XCTAssertEqual(status.amsUnits[1].name, "AMS 2")
        XCTAssertEqual(status.amsUnits[1].slots.map(\.material), ["ABS", nil, nil, nil])
        XCTAssertEqual(status.amsUnits[1].slots[0].colorHex, "FF0000")
    }

    func testCoverImageCandidatesPreferSubtaskNameAndSkipMetadataRamdisk() {
        let candidates = CoverImageCandidateBuilder.candidates(
            gcodeFile: "/data/Metadata/plate_1.gcode",
            subtaskName: "Air Slides"
        )

        XCTAssertEqual(candidates, ["Air Slides.3mf", "Air Slides.gcode.3mf"])
    }

    func testCoverImageCandidatesPreferDownloadedFileWhenPresent() {
        let candidates = CoverImageCandidateBuilder.candidates(
            rawFile: "/data/Metadata/plate_2.gcode",
            gcodeFile: "/data/Metadata/plate_1.gcode",
            gcodeFileDownloaded: "Air Slides.gcode.3mf",
            subtaskName: "Air Slides"
        )

        XCTAssertEqual(candidates, ["Air Slides.gcode.3mf", "Air Slides.3mf"])
    }

    func testCoverImageMetadataParserReadsPlateIndex() throws {
        let xml = """
        <config>
          <plate>
            <metadata key="index" value="3"/>
          </plate>
        </config>
        """

        XCTAssertEqual(CoverImageMetadataParser.plateNumber(from: Data(xml.utf8)), 3)
    }

    func testFTPSDirectoryListingParserKeepsFilenamesWithSpaces() {
        let listing = """
        -rw-r--r-- 1 owner group 1234 Jul 03 22:30 0.2mm 层高, 2 层墙, 15% 填充.3mf
        -rw-r--r-- 1 owner group 99 Jul 03 22:31 Air Slides.gcode.3mf
        """

        let entries = FTPSDownloader().parseDirectoryListing(listing, remoteDirectory: "/cache")

        XCTAssertEqual(entries, [
            RemoteDirectoryEntry(path: "/cache/0.2mm 层高, 2 层墙, 15% 填充.3mf", size: 1234),
            RemoteDirectoryEntry(path: "/cache/Air Slides.gcode.3mf", size: 99)
        ])
    }

    func testZIPArchiveReadsDeflatedEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BambuCompanionZIPArchiveTests-\(UUID().uuidString)", isDirectory: true)
        let metadataDirectory = directory.appendingPathComponent("Metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        let entryURL = metadataDirectory.appendingPathComponent("slice_info.config")
        try Data("<config/>".utf8).write(to: entryURL)

        let zipURL = directory.appendingPathComponent("model.3mf")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", zipURL.path, "Metadata/slice_info.config"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let archive = try ZIPArchive(data: Data(contentsOf: zipURL))

        XCTAssertEqual(try archive.data(named: "Metadata/slice_info.config"), Data("<config/>".utf8))
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
