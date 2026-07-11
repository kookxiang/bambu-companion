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
            "layer_num": 12,
            "total_layer_num": 180,
            "gcode_file": "benchy.3mf",
            "nozzle_temper": 221.4,
            "nozzle_target_temper": 245,
            "bed_temper": 63,
            "bed_target_temper": 70,
            "chamber_temper": 38,
            "chamber_target_temper": 45
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.activity, .printing)
        XCTAssertEqual(status.progress, 42)
        XCTAssertEqual(status.remainingMinutes, 93)
        XCTAssertEqual(status.currentLayer, 12)
        XCTAssertEqual(status.totalLayers, 180)
        XCTAssertEqual(status.jobName, "benchy.3mf")
        XCTAssertEqual(status.nozzleTemperature, 221.4)
        XCTAssertEqual(status.targetNozzleTemperature, 245)
        XCTAssertEqual(status.bedTemperature, 63)
        XCTAssertEqual(status.targetBedTemperature, 70)
        XCTAssertEqual(status.chamberTemperature, 38)
        XCTAssertEqual(status.targetChamberTemperature, 45)
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

    func testModelPreparationUsesDownloadProgress() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"gcode_state":"PREPARE","mc_percent":91,"gcode_file_prepare_percent":"37"}}"#.utf8))

        XCTAssertEqual(status.activity, .preparing)
        XCTAssertEqual(status.primaryTitle, PrinterActivity.preparing.title)
        XCTAssertEqual(status.displayedProgress, 37)
    }

    func testPrintingUsesPrintProgressAfterModelPreparation() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"gcode_state":"RUNNING","mc_percent":42,"gcode_file_prepare_percent":"100"}}"#.utf8))

        XCTAssertEqual(status.activity, .printing)
        XCTAssertEqual(status.displayedProgress, 42)
    }

    func testParsesLegacyCurrentStage() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"stg_cur":"14"}}"#.utf8))

        XCTAssertEqual(status.currentStage, PrinterStage(id: 14))
    }

    func testParsesNestedCurrentStage() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"stage":{"_id":2}}}"#.utf8))

        XCTAssertEqual(status.currentStage, PrinterStage(id: 2))
    }

    func testLegacyCurrentStageTakesPrecedenceWhenBothArePresent() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"stg_cur":14,"stage":{"_id":2}}}"#.utf8))

        XCTAssertEqual(status.currentStage, PrinterStage(id: 14))
    }

    func testIdleCurrentStageClearsIncrementalStage() throws {
        let base = try MQTTReportParser.parse(Data(#"{"print":{"gcode_state":"RUNNING","stg_cur":14}}"#.utf8))
        let update = try MQTTReportParser.parse(Data(#"{"print":{"stg_cur":255}}"#.utf8))

        XCTAssertNil(base.mergingIncrementalUpdate(update).currentStage)
    }

    func testPrimaryTitleUsesStageOnlyWhilePrinting() {
        var status = PrinterStatus()
        status.activity = .printing
        status.currentStage = PrinterStage(id: 14)

        XCTAssertEqual(status.primaryTitle, PrinterStage(id: 14).title)

        status.activity = .paused
        XCTAssertEqual(status.primaryTitle, PrinterActivity.paused.title)
    }

    func testMenuBarStageAnnouncementRequiresAnActualPrintingStageChange() {
        var previous = PrinterStatus()
        previous.activity = .printing
        previous.currentStage = PrinterStage(id: 2)
        var current = previous
        current.currentStage = PrinterStage(id: 13)

        XCTAssertEqual(
            MenuBarStageAnnouncement.title(previousStatus: previous, currentStatus: current),
            PrinterStage(id: 13).title
        )

        var initial = previous
        initial.currentStage = nil
        XCTAssertNil(MenuBarStageAnnouncement.title(previousStatus: initial, currentStatus: current))

        current.activity = .paused
        XCTAssertNil(MenuBarStageAnnouncement.title(previousStatus: previous, currentStatus: current))
    }

    func testIncrementalUpdatePreservesMissingFields() throws {
        let base = try MQTTReportParser.parse(Data(#"{"print":{"gcode_state":"IDLE","mc_percent":0,"nozzle_temper":29}}"#.utf8))
        let update = try MQTTReportParser.parse(Data(#"{"print":{"bed_temper":31}}"#.utf8))

        let merged = base.mergingIncrementalUpdate(update)

        XCTAssertEqual(merged.activity, .idle)
        XCTAssertEqual(merged.progress, 0)
        XCTAssertEqual(merged.nozzleTemperature, 29)
        XCTAssertEqual(merged.bedTemperature, 31)
    }

    func testIncrementalUpdateIgnoresUnknownActivity() throws {
        let base = try MQTTReportParser.parse(Data(#"{"print":{"gcode_state":"RUNNING","mc_percent":12}}"#.utf8))
        let update = try MQTTReportParser.parse(Data(#"{"print":{"gcode_state":"MOVING","mc_percent":13}}"#.utf8))

        let merged = base.mergingIncrementalUpdate(update)

        XCTAssertEqual(merged.activity, .printing)
        XCTAssertEqual(merged.progress, 13)
    }

    func testIncrementalUpdatePreservesAlertWhenAlertFieldsAreMissing() throws {
        let base = try MQTTReportParser.parse(Data(#"{"print":{"hms":[{"attr":402691840,"code":196609}]}}"#.utf8))
        let update = try MQTTReportParser.parse(Data(#"{"print":{"mc_percent":13}}"#.utf8))

        let merged = base.mergingIncrementalUpdate(update)

        XCTAssertEqual(merged.alert, base.alert)
    }

    func testIncrementalUpdateClearsAlertWhenHMSListIsEmpty() throws {
        let base = try MQTTReportParser.parse(Data(#"{"print":{"hms":[{"attr":402691840,"code":196609}]}}"#.utf8))
        let update = try MQTTReportParser.parse(Data(#"{"print":{"hms":[]}}"#.utf8))

        let merged = base.mergingIncrementalUpdate(update)

        XCTAssertNil(merged.alert)
    }

    func testIncrementalUpdateClearsAlertWhenPrintErrorResets() throws {
        let base = try MQTTReportParser.parse(Data(#"{"print":{"print_error":117473286}}"#.utf8))
        let update = try MQTTReportParser.parse(Data(#"{"print":{"print_error":0}}"#.utf8))

        let merged = base.mergingIncrementalUpdate(update)

        XCTAssertNil(merged.alert)
    }

    func testParsesCancelledActivity() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"gcode_state":"CANCELLED"}}"#.utf8))

        XCTAssertEqual(status.activity, .cancelled)
    }

    func testParsesFanStatus() throws {
        let json = """
        {
          "print": {
            "cooling_fan_speed": "15",
            "big_fan1_speed": "6",
            "chamber_fan_speed": "0",
            "heatbreak_fan_speed": "100"
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.fans.partCoolingPercent, 100)
        XCTAssertEqual(status.fans.auxiliaryPercent, 40)
        XCTAssertEqual(status.fans.chamberPercent, 0)
        XCTAssertEqual(status.fans.heatbreakPercent, 100)
        XCTAssertTrue(status.fans.hasAnyValue)
    }

    func testParsesAirductModeFromDeviceAirductData() throws {
        let json = """
        {
          "print": {
            "device": {
              "airduct": {
                "modeCur": 1,
                "modeList": [
                  {"modeId": 0},
                  {"modeId": 1},
                  {"modeId": 2}
                ]
              }
            }
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.airductMode, "heating")
    }

    func testParsesDualNozzleTemperatures() throws {
        let json = """
        {
          "print": {
            "device": {
              "extruder": {
                "info": [
                  {"id": 0, "temp": 16056565},
                  {"id": 1, "temp": 5767327}
                ]
              }
            },
            "nozzle_temper": 245
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.rightNozzleTemperature, 245)
        XCTAssertEqual(status.targetRightNozzleTemperature, 245)
        XCTAssertEqual(status.leftNozzleTemperature, 159)
        XCTAssertEqual(status.targetLeftNozzleTemperature, 88)
        XCTAssertEqual(status.nozzleTemperature, 245)
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

    func testParsesCameraStreamURL() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"ipcam":{"rtsp_url":"rtsp://192.168.1.50/streaming/live/1"}}}"#.utf8))

        XCTAssertEqual(status.cameraStreamURL, "rtsp://192.168.1.50/streaming/live/1")
    }

    func testVideoStreamURLBuilderUsesMQTTURLWithLANCredentials() {
        var status = BambuCompanion.PrinterStatus.empty
        status.cameraStreamURL = "rtsp://192.168.1.50/streaming/live/1"
        let configuration = PrinterConfiguration(
            displayName: "",
            host: "192.168.1.20",
            serialNumber: "SERIAL",
            accessCode: "12345678"
        )

        let url = VideoStreamURLBuilder.url(configuration: configuration, status: status)

        XCTAssertEqual(url?.absoluteString, "rtsps://bblp:12345678@192.168.1.50:322/streaming/live/1")
    }

    func testVideoStreamURLBuilderFallsBackToDefaultLANURL() {
        let configuration = PrinterConfiguration(
            displayName: "",
            host: "https://192.168.1.20:443",
            serialNumber: "SERIAL",
            accessCode: "12345678"
        )

        let url = VideoStreamURLBuilder.url(configuration: configuration, status: BambuCompanion.PrinterStatus.empty)

        XCTAssertEqual(url?.absoluteString, "rtsps://bblp:12345678@192.168.1.20:322/streaming/live/1")
    }

    func testParsesAMSUnitsFromReportedTrays() throws {
        let json = """
        {
          "print": {
            "ams": {
              "ams": [
                {
                  "id": "0",
                  "humidity": "2",
                  "humidity_raw": 41,
                  "temp": "34.5",
                  "dry_time": 125,
                  "dry_setting": {
                    "dry_temperature": 55,
                    "dry_filament": "PETG"
                  },
                  "tray": [
                    {
                      "id": "0",
                      "tray_type": "PETG",
                      "tray_color": "FFFFFFFF",
                      "remain": 63,
                      "tray_id_name": "Bambu PETG HF",
                      "tray_sub_brands": "Bambu",
                      "tag_uid": "1234567890ABCDEF",
                      "tray_info_idx": "GFG99",
                      "tray_diameter": "1.75",
                      "tray_weight": "1000",
                      "nozzle_temp_min": "230",
                      "nozzle_temp_max": "260"
                    },
                    {"id": "1", "tray_type": "PLA", "tray_color": "00FF00FF", "remain": -1},
                    {"id": "3", "tray_type": "ASA", "tray_color": "00000000", "remain": 120}
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
        XCTAssertEqual(status.amsUnits[0].temperature, 34.5)
        XCTAssertEqual(status.amsUnits[0].humidityIndex, 2)
        XCTAssertEqual(status.amsUnits[0].humidityPercent, 41)
        XCTAssertEqual(status.amsUnits[0].dryingRemainingMinutes, 125)
        XCTAssertEqual(status.amsUnits[0].dryingTemperature, 55)
        XCTAssertEqual(status.amsUnits[0].dryingFilament, "PETG")
        XCTAssertTrue(status.amsUnits[0].isDrying)
        XCTAssertEqual(status.amsUnits[0].slots.count, 3)
        XCTAssertEqual(status.amsUnits[0].slots.map(\.index), [0, 1, 3])
        XCTAssertEqual(status.amsUnits[0].slots.map(\.material), ["PETG", "PLA", "ASA"])
        XCTAssertEqual(status.amsUnits[0].slots[0].colorHex, "FFFFFF")
        XCTAssertEqual(status.amsUnits[0].slots[0].remainingPercent, 63)
        XCTAssertEqual(status.amsUnits[0].slots[0].name, "Bambu PETG HF")
        XCTAssertEqual(status.amsUnits[0].slots[0].subBrands, "Bambu")
        XCTAssertEqual(status.amsUnits[0].slots[0].tagUID, "1234567890ABCDEF")
        XCTAssertEqual(status.amsUnits[0].slots[0].trayInfoIndex, "GFG99")
        XCTAssertEqual(status.amsUnits[0].slots[0].diameter, 1.75)
        XCTAssertEqual(status.amsUnits[0].slots[0].weight, 1000)
        XCTAssertEqual(status.amsUnits[0].slots[0].remainingWeight, 630)
        XCTAssertEqual(status.amsUnits[0].slots[0].nozzleTemperatureMin, 230)
        XCTAssertEqual(status.amsUnits[0].slots[0].nozzleTemperatureMax, 260)
        XCTAssertEqual(status.amsUnits[0].slots[1].colorHex, "00FF00")
        XCTAssertNil(status.amsUnits[0].slots[1].remainingPercent)
        XCTAssertEqual(status.amsUnits[0].slots[2].colorHex, "000000")
        XCTAssertEqual(status.amsUnits[0].slots[2].remainingPercent, 100)
        XCTAssertEqual(status.amsUnits[1].name, "AMS 2")
        XCTAssertEqual(status.amsUnits[1].slots.map(\.material), ["ABS"])
        XCTAssertEqual(status.amsUnits[1].slots[0].colorHex, "FF0000")
    }

    func testParsesAMSSeriesEvenWhenItMatchesMaterial() throws {
        let json = """
        {
          "print": {
            "ams": {
              "ams": [
                {
                  "id": "0",
                  "tray": [
                    {
                      "id": "3",
                      "tray_type": "ABS",
                      "tray_sub_brands": "ABS",
                      "tray_color": "000000FF"
                    }
                  ]
                }
              ]
            }
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.amsUnits.first?.slots.first?.material, "ABS")
        XCTAssertEqual(status.amsUnits.first?.slots.first?.subBrands, "ABS")
    }

    func testParsesBambuAMSSeries() throws {
        let json = """
        {
          "print": {
            "ams": {
              "ams": [
                {
                  "id": "0",
                  "tray": [
                    {
                      "id": "0",
                      "tray_type": "PETG",
                      "tray_sub_brands": "Bambu Lab",
                      "tray_color": "FFFFFFFF"
                    }
                  ]
                }
              ]
            }
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.amsUnits.first?.slots.first?.subBrands, "Bambu Lab")
    }

    func testParsesAMSHTDisplayName() throws {
        let json = """
        {
          "print": {
            "ams": {
              "ams": [
                {
                  "id": "128",
                  "tray": [
                    {"id": "0", "tray_type": "PETG", "tray_color": "FFFFFFFF"}
                  ]
                }
              ]
            }
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.amsUnits.first?.name, "AMS HT 1")
        XCTAssertEqual(status.amsUnits.first?.slots.count, 1)
        XCTAssertEqual(status.amsUnits.first?.slots.first?.material, "PETG")
    }

    func testParsesEncodedChamberTemperatureAndPrintError() throws {
        let json = """
        {
          "print": {
            "print_error": 117473286,
            "device": {
              "bed": {
                "info": {
                  "temp": 4587580
                }
              },
              "ctc": {
                "info": {
                  "temp": 3276843
                }
              }
            }
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertEqual(status.bedTemperature, 60)
        XCTAssertEqual(status.targetBedTemperature, 70)
        XCTAssertEqual(status.chamberTemperature, 43)
        XCTAssertEqual(status.targetChamberTemperature, 50)
        XCTAssertNotEqual(status.alert?.title, "Print error")
        XCTAssertNil(status.alert?.detail)
    }

    func testParsesCancelledPrintErrorMessageAsAlertTitle() throws {
        let status = try MQTTReportParser.parse(Data(#"{"print":{"print_error":50348044}}"#.utf8))

        XCTAssertNotEqual(status.alert?.title, "Print error")
        XCTAssertNil(status.alert?.detail)
        XCTAssertTrue(
            status.alert?.title.localizedCaseInsensitiveContains("canceled") == true ||
                status.alert?.title.contains("取消") == true
        )
    }

    func testParsesHMSWarningMessageAsAlertTitle() throws {
        let json = """
        {
          "print": {
            "hms": [
              {
                "attr": 402691840,
                "code": 196609
              }
            ]
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertTrue(status.alert?.title.contains("AMS-HT") == true)
        XCTAssertNil(status.alert?.detail)
        XCTAssertEqual(status.alert?.source, .hms)
        XCTAssertEqual(
            status.alert?.wikiURL?.absoluteString,
            "https://wiki.bambulab.com/en/h2d/troubleshooting/hmscode/0700_9700_0003_0001"
        )
    }

    func testHMSErrorCatalogLoadsOfficialEnglishResources() throws {
        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BambuCompanion/HMSResources", isDirectory: true)
        let catalog = HMSErrorCatalog(resourceDirectoryURL: resourceURL)

        XCTAssertEqual(
            catalog.text(forRawCode: "1800_9700_0003_0001", preferredLanguages: ["en"]),
            "AMS-HT A chamber temperature is too high; auxiliary feeding or RFID reading is currently not allowed."
        )
        XCTAssertEqual(
            catalog.text(forRawCode: "0300_400C", preferredLanguages: ["en"]),
            "The task was canceled."
        )
    }

    func testParsesActiveAMSSlotFromTrayNow() throws {
        let json = """
        {
          "print": {
            "ams": {
              "tray_now": "5",
              "ams": [
                {
                  "id": "0",
                  "tray": [
                    {"id": "0", "tray_type": "PLA"},
                    {"id": "1", "tray_type": "PLA"}
                  ]
                },
                {
                  "id": "1",
                  "tray": [
                    {"id": "0", "tray_type": "PETG"},
                    {"id": "1", "tray_type": "ASA"}
                  ]
                }
              ]
            }
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertFalse(status.amsUnits[0].slots[1].isActive)
        XCTAssertTrue(status.amsUnits[1].slots[1].isActive)
    }

    func testParsesActiveAMSSlotFromDualNozzleSnow() throws {
        let json = """
        {
          "print": {
            "device": {
              "extruder": {
                "state": 18,
                "info": [
                  {"id": 0, "snow": 259},
                  {"id": 1, "snow": 3}
                ]
              }
            },
            "ams": {
              "ams": [
                {
                  "id": "0",
                  "tray": [
                    {"id": "0", "tray_type": "PETG"},
                    {"id": "1", "tray_type": "PLA"},
                    {"id": "2", "tray_type": "ASA"},
                    {"id": "3", "tray_type": "PETG"}
                  ]
                },
                {
                  "id": "1",
                  "tray": [
                    {"id": "0", "tray_type": "PETG"},
                    {"id": "1", "tray_type": "PLA"},
                    {"id": "2", "tray_type": "ASA"},
                    {"id": "3", "tray_type": "PETG"}
                  ]
                }
              ]
            }
          }
        }
        """

        let status = try MQTTReportParser.parse(Data(json.utf8))

        XCTAssertTrue(status.amsUnits[0].slots[3].isActive)
        XCTAssertFalse(status.amsUnits[1].slots[3].isActive)
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

    func testPrintNotificationGateOnlyNotifiesOnActivityChangesAfterFirstStatus() {
        var gate = PrintNotificationGate()

        XCTAssertFalse(gate.observe(activity: .printing))
        XCTAssertFalse(gate.observe(activity: .printing))
        XCTAssertTrue(gate.observe(activity: .paused))
        XCTAssertFalse(gate.observe(activity: .paused))
        XCTAssertTrue(gate.observe(activity: .printing))
    }

    func testPrintNotificationGateSupportsCancelledActivity() {
        var gate = PrintNotificationGate()

        XCTAssertFalse(gate.observe(activity: .printing))
        XCTAssertTrue(gate.observe(activity: .cancelled))
        XCTAssertFalse(gate.observe(activity: .cancelled))
    }

    func testPrintNotificationGateIgnoresNonEffectiveStatuses() {
        var gate = PrintNotificationGate()

        XCTAssertFalse(gate.observe(activity: .idle))
        XCTAssertFalse(gate.observe(activity: .unknown))
        XCTAssertFalse(gate.observe(activity: .printing))
        XCTAssertFalse(gate.observe(activity: .idle))
        XCTAssertFalse(gate.observe(activity: .unknown))
        XCTAssertFalse(gate.observe(activity: .printing))
        XCTAssertTrue(gate.observe(activity: .paused))
    }

    func testPrintNotificationGateResetRequiresNewBaseline() {
        var gate = PrintNotificationGate()

        XCTAssertFalse(gate.observe(activity: .printing))
        XCTAssertTrue(gate.observe(activity: .paused))

        gate.reset()

        XCTAssertFalse(gate.observe(activity: .paused))
        XCTAssertFalse(gate.observe(activity: .paused))
    }

    func testPrintNotificationGateDoesNotRepeatSameNotificationAfterNonNotifiableStatus() {
        var gate = PrintNotificationGate()

        XCTAssertFalse(gate.observe(activity: .printing))
        XCTAssertTrue(gate.observe(activity: .finished))
        XCTAssertFalse(gate.observe(activity: .idle))
        XCTAssertFalse(gate.observe(activity: .finished))
        XCTAssertFalse(gate.observe(activity: .unknown))
        XCTAssertFalse(gate.observe(activity: .finished))
        XCTAssertTrue(gate.observe(activity: .paused))
    }

    func testPrintNotificationGateNotifiesWhenHMSAlertAppears() {
        var gate = PrintNotificationGate()
        let alert = PrinterAlert(title: "AMS warning", source: .hms)

        XCTAssertEqual(gate.observe(status: PrinterStatus(activity: .printing)), [])
        XCTAssertEqual(
            gate.observe(status: PrinterStatus(activity: .printing, alert: alert)),
            [.hmsAlert(alert)]
        )
        XCTAssertEqual(gate.observe(status: PrinterStatus(activity: .printing, alert: alert)), [])
    }

    func testPrintNotificationGateNotifiesWhenHMSAlertChangesOrReappears() {
        var gate = PrintNotificationGate()
        let firstAlert = PrinterAlert(title: "First HMS warning", source: .hms)
        let secondAlert = PrinterAlert(title: "Second HMS warning", source: .hms)

        XCTAssertEqual(gate.observe(status: PrinterStatus(activity: .printing, alert: firstAlert)), [.hmsAlert(firstAlert)])
        XCTAssertEqual(gate.observe(status: PrinterStatus(activity: .printing, alert: secondAlert)), [.hmsAlert(secondAlert)])
        XCTAssertEqual(gate.observe(status: PrinterStatus(activity: .printing)), [])
        XCTAssertEqual(gate.observe(status: PrinterStatus(activity: .printing, alert: secondAlert)), [.hmsAlert(secondAlert)])
    }

    func testPrintNotificationGateIgnoresNonHMSAlerts() {
        var gate = PrintNotificationGate()
        let alert = PrinterAlert(title: "Print error", detail: "0700_8006")

        XCTAssertEqual(gate.observe(status: PrinterStatus(activity: .printing, alert: alert)), [])
    }
}
