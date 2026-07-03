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
        status.jobName = stringValue(print["gcode_file"]) ?? stringValue(print["subtask_name"])
        status.remainingMinutes = intValue(print["mc_remaining_time"]) ?? intValue(print["remaining_time"])
        status.nozzleTemperature = doubleValue(print["nozzle_temper"]) ?? doubleValue(print["nozzle_temperature"])
        status.bedTemperature = doubleValue(print["bed_temper"]) ?? doubleValue(print["bed_temperature"])
        status.filamentSummary = filamentSummary(from: print)
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

    private static func filamentSummary(from print: [String: Any]) -> String? {
        guard let ams = print["ams"] as? [String: Any],
              let amsList = ams["ams"] as? [[String: Any]] else {
            return nil
        }
        let names = amsList
            .flatMap { ($0["tray"] as? [[String: Any]]) ?? [] }
            .compactMap { stringValue($0["tray_type"]) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
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
