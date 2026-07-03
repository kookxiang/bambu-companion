import Foundation

enum MQTTReportParser {
    static func parse(_ data: Data) throws -> PrinterStatus {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            return .empty
        }
        let print = (root["print"] as? [String: Any]) ?? root

        var status = PrinterStatus()
        status.activity = activity(from: stringValue(print["gcode_state"]) ?? stringValue(print["print_status"]))
        status.progress = intValue(print["mc_percent"]) ?? intValue(print["print_progress"])
        status.rawFile = stringValue(print["file"])
        status.gcodeFile = stringValue(print["gcode_file"])
        status.gcodeFileDownloaded = stringValue(print["gcode_file_downloaded"])
        status.subtaskName = stringValue(print["subtask_name"])
        status.gcodeFilePreparePercent = intValue(print["gcode_file_prepare_percent"])
        status.jobName = status.subtaskName?.isEmpty == false ? status.subtaskName : status.gcodeFile
        status.remainingMinutes = intValue(print["mc_remaining_time"]) ?? intValue(print["remaining_time"])
        status.nozzleTemperature = doubleValue(print["nozzle_temper"]) ?? doubleValue(print["nozzle_temperature"])
        status.bedTemperature = doubleValue(print["bed_temper"]) ?? doubleValue(print["bed_temperature"])
        status.amsUnits = amsUnits(from: print)
        status.updatedAt = Date()
        return status
    }

    private static func activity(from raw: String?) -> PrinterActivity {
        guard let raw else {
            return .unknown
        }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "IDLE", "PREPARE", "SLICING":
            return .idle
        case "RUNNING", "PRINTING":
            return .printing
        case "PAUSE", "PAUSED":
            return .paused
        case "FINISH", "FINISHED", "COMPLETED":
            return .finished
        case "FAILED", "ERROR":
            return .failed
        default:
            return .unknown
        }
    }

    private static func amsUnits(from print: [String: Any]) -> [AMSUnitStatus] {
        guard let ams = print["ams"] as? [String: Any],
              let amsList = ams["ams"] as? [[String: Any]] else {
            return []
        }
        return amsList.enumerated().compactMap { amsIndex, ams in
            guard let trays = ams["tray"] as? [[String: Any]], !trays.isEmpty else {
                return nil
            }

            let rawID = stringValue(ams["id"]) ?? "\(amsIndex)"
            var trayByIndex: [Int: [String: Any]] = [:]
            for tray in trays {
                let trayIndex = intValue(tray["id"]) ?? 0
                trayByIndex[trayIndex] = tray
            }
            let slots = (0..<4).map { slotIndex in
                let tray = trayByIndex[slotIndex]
                let material = normalizedMaterial(stringValue(tray?["tray_type"]))
                let colorHex = normalizedColorHex(stringValue(tray?["tray_color"]))
                return AMSSlotStatus(
                    id: "\(rawID)-\(slotIndex)",
                    index: slotIndex,
                    material: material,
                    colorHex: colorHex
                )
            }
            let name = amsDisplayName(rawID: rawID, fallbackIndex: amsIndex)
            return AMSUnitStatus(id: rawID, name: name, slots: slots)
        }
    }

    private static func amsDisplayName(rawID: String, fallbackIndex: Int) -> String {
        guard let numericID = Int(rawID) else {
            return "AMS \(fallbackIndex + 1)"
        }
        return "AMS \(numericID + 1)"
    }

    private static func normalizedMaterial(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizedColorHex(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        guard value.rangeOfCharacter(from: allowed.inverted) == nil else {
            return nil
        }
        if value.count == 8 {
            value = String(value.prefix(6))
        }
        guard value.count == 6, value != "000000" else {
            return nil
        }
        return value.uppercased()
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }
}
