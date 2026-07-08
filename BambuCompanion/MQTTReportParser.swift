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
        status.currentLayer = intValue(print["layer_num"]) ?? intValue(print["current_layer"])
        status.totalLayers = intValue(print["total_layer_num"]) ?? intValue(print["total_layers"])
        let nozzle = nozzleTemperatures(from: print)
        status.nozzleTemperature = nozzle.current
        status.targetNozzleTemperature = nozzle.target
        let dualNozzles = dualNozzleTemperatures(from: print)
        status.leftNozzleTemperature = dualNozzles.left.current
        status.targetLeftNozzleTemperature = dualNozzles.left.target
        status.rightNozzleTemperature = dualNozzles.right.current
        status.targetRightNozzleTemperature = dualNozzles.right.target
        let bedTemperatures = bedTemperatures(from: print)
        status.bedTemperature = bedTemperatures.current
        status.targetBedTemperature = bedTemperatures.target
        let chamberTemperatures = chamberTemperatures(from: print)
        status.chamberTemperature = chamberTemperatures.current
        status.targetChamberTemperature = chamberTemperatures.target
        status.cameraStreamURL = cameraStreamURL(from: print)
        status.alert = alert(from: print)
        if containsAlertUpdate(print) {
            status.alertUpdate = .set(status.alert)
        }
        status.airductMode = airductMode(from: print)
        status.fans = fanStatus(from: print)
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
        case "CANCEL", "CANCELLED", "CANCELED", "ABORT", "ABORTED":
            return .cancelled
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

    private static func nozzleTemperatures(from print: [String: Any]) -> (current: Double?, target: Double?) {
        return (
            current: doubleValue(print["nozzle_temper"]) ?? doubleValue(print["nozzle_temperature"]),
            target: doubleValue(print["nozzle_target_temper"]) ?? doubleValue(print["target_nozzle_temperature"])
        )
    }

    private static func dualNozzleTemperatures(from print: [String: Any]) -> (left: (current: Double?, target: Double?), right: (current: Double?, target: Double?)) {
        guard let device = print["device"] as? [String: Any],
              let extruder = device["extruder"] as? [String: Any],
              let info = extruder["info"] as? [[String: Any]] else {
            return ((nil, nil), (nil, nil))
        }

        var left: (current: Double?, target: Double?) = (nil, nil)
        var right: (current: Double?, target: Double?) = (nil, nil)
        for entry in info {
            guard let id = intValue(entry["id"]),
                  let encodedTemperature = intValue(entry["temp"]) else {
                continue
            }
            let temperatures = (
                current: Double(encodedTemperature & 0xFFFF),
                target: Double((encodedTemperature >> 16) & 0xFFFF)
            )
            switch id {
            case 0:
                right = temperatures
            case 1:
                left = temperatures
            default:
                break
            }
        }
        return (left, right)
    }

    private static func bedTemperatures(from print: [String: Any]) -> (current: Double?, target: Double?) {
        if let bed = (print["device"] as? [String: Any])?["bed"] as? [String: Any],
           let info = bed["info"] as? [String: Any],
           let encodedTemperature = intValue(info["temp"]) {
            return (
                current: Double(encodedTemperature & 0xFFFF),
                target: Double((encodedTemperature >> 16) & 0xFFFF)
            )
        }
        return (
            current: doubleValue(print["bed_temper"]) ?? doubleValue(print["bed_temperature"]),
            target: doubleValue(print["bed_target_temper"]) ?? doubleValue(print["target_bed_temperature"])
        )
    }

    private static func chamberTemperatures(from print: [String: Any]) -> (current: Double?, target: Double?) {
        if let ctc = (print["device"] as? [String: Any])?["ctc"] as? [String: Any],
           let info = ctc["info"] as? [String: Any],
           let encodedTemperature = intValue(info["temp"]) {
            return (
                current: Double(encodedTemperature & 0xFFFF),
                target: Double((encodedTemperature >> 16) & 0xFFFF)
            )
        }
        return (
            current: doubleValue(print["chamber_temper"]) ?? doubleValue(print["chamber_temperature"]),
            target: doubleValue(print["chamber_target_temper"]) ?? doubleValue(print["target_chamber_temperature"])
        )
    }

    private static func fanStatus(from print: [String: Any]) -> PrinterFanStatus {
        PrinterFanStatus(
            partCoolingPercent: fanPercent(
                print["cooling_fan_speed"] ??
                    print["print_fan_speed"] ??
                    print["fan_gear"]
            ),
            auxiliaryPercent: fanPercent(
                print["big_fan1_speed"] ??
                    print["aux_part_fan_speed"] ??
                    print["auxiliary_fan_speed"]
            ),
            chamberPercent: fanPercent(
                print["chamber_fan_speed"] ??
                    print["big_fan2_speed"]
            ),
            heatbreakPercent: fanPercent(print["heatbreak_fan_speed"])
        )
    }

    private static func fanPercent(_ value: Any?) -> Int? {
        guard let rawValue = intValue(value), rawValue >= 0 else {
            return nil
        }
        if rawValue <= 15 {
            return Int((Double(rawValue) / 15 * 100).rounded())
        }
        return min(rawValue, 100)
    }

    private static func airductMode(from print: [String: Any]) -> String? {
        let airduct = (print["device"] as? [String: Any])?["airduct"] as? [String: Any]
        if let modeID = intValue(airduct?["modeCur"]) {
            switch modeID {
            case 0:
                return "cooling"
            case 1:
                return "heating"
            case 2:
                return "laser"
            default:
                return String(modeID)
            }
        }
        return normalizedMaterial(stringValue(print["airduct_mode"]))
    }

    private static func alert(from print: [String: Any]) -> PrinterAlert? {
        if let printError = intValue(print["print_error"]), printError != 0 {
            return printErrorAlert(from: printError)
        }
        if let hms = print["hms"] as? [[String: Any]], !hms.isEmpty {
            return hms.compactMap(hmsAlert(from:)).first
        }
        return nil
    }

    private static func containsAlertUpdate(_ print: [String: Any]) -> Bool {
        print.keys.contains("print_error") || print.keys.contains("hms")
    }

    private static func printErrorAlert(from printError: Int) -> PrinterAlert {
        let rawCode = rawErrorCode(printError)
        if let errorText = HMSErrorCatalog.shared.text(forRawCode: rawCode) {
            return PrinterAlert(title: errorText)
        }
        return PrinterAlert(title: "Print error", detail: formattedErrorCode(rawCode))
    }

    private static func hmsAlert(from hms: [String: Any]) -> PrinterAlert? {
        guard let code = intValue(hms["code"]), code > 0 else {
            return nil
        }
        guard let attr = intValue(hms["attr"]), attr > 0 else {
            return PrinterAlert(title: String(code))
        }

        let rawHMSCode = rawHMSCode(attr: attr, code: code)
        let hmsCode = formattedHMSCode(rawHMSCode)
        let errorText = HMSErrorCatalog.shared.text(forRawCode: rawHMSCode)
        return PrinterAlert(
            title: errorText ?? hmsCode,
            wikiURL: knownHMSWikiURL[hmsCode],
            source: .hms
        )
    }

    private static func rawHMSCode(attr: Int, code: Int) -> String {
        String(
            format: "%04X_%04X_%04X_%04X",
            attr / 0x10000,
            attr & 0xFFFF,
            code / 0x10000,
            code & 0xFFFF
        )
    }

    private static func formattedHMSCode(_ rawCode: String) -> String {
        "HMS_\(rawCode)"
    }

    private static let knownHMSWikiURL = [
        "HMS_1800_9700_0003_0001": URL(string: "https://wiki.bambulab.com/en/h2d/troubleshooting/hmscode/0700_9700_0003_0001")!
    ]

    private static func cameraStreamURL(from print: [String: Any]) -> String? {
        guard let ipcam = print["ipcam"] as? [String: Any],
              let rtspURL = normalizedMaterial(stringValue(ipcam["rtsp_url"])),
              rtspURL.localizedCaseInsensitiveCompare("disable") != .orderedSame else {
            return nil
        }
        return rtspURL
    }

    private static func amsUnits(from print: [String: Any]) -> [AMSUnitStatus] {
        guard let ams = print["ams"] as? [String: Any],
              let amsList = ams["ams"] as? [[String: Any]] else {
            return []
        }
        let activeSlot = activeAMSSlot(from: print, ams: ams)
        return amsList.enumerated().compactMap { amsIndex, ams in
            guard let trays = ams["tray"] as? [[String: Any]], !trays.isEmpty else {
                return nil
            }

            let rawID = stringValue(ams["id"]) ?? "\(amsIndex)"
            let slots = trays.enumerated()
                .map { trayPosition, tray -> (slotIndex: Int, slot: AMSSlotStatus) in
                    let slotIndex = intValue(tray["id"]) ?? trayPosition
                    let material = normalizedMaterial(stringValue(tray["tray_type"]))
                    let colorHex = normalizedColorHex(stringValue(tray["tray_color"]))
                    let remainingPercent = normalizedPercent(intValue(tray["remain"]))
                    let subBrands = normalizedSubBrands(stringValue(tray["tray_sub_brands"]), material: material)
                    let slot = AMSSlotStatus(
                        id: "\(rawID)-\(slotIndex)",
                        index: slotIndex,
                        material: material,
                        colorHex: colorHex,
                        remainingPercent: remainingPercent,
                        name: normalizedMaterial(stringValue(tray["tray_id_name"])),
                        subBrands: subBrands,
                        tagUID: normalizedMaterial(stringValue(tray["tag_uid"])),
                        trayInfoIndex: normalizedMaterial(stringValue(tray["tray_info_idx"])),
                        diameter: normalizedPositive(doubleValue(tray["tray_diameter"])),
                        weight: normalizedPositive(doubleValue(tray["tray_weight"])),
                        nozzleTemperatureMin: normalizedPositive(doubleValue(tray["nozzle_temp_min"])),
                        nozzleTemperatureMax: normalizedPositive(doubleValue(tray["nozzle_temp_max"])),
                        isActive: activeSlot?.amsID == rawID && activeSlot?.slotIndex == slotIndex
                    )
                    return (slotIndex, slot)
                }
                .sorted { $0.slotIndex < $1.slotIndex }
                .map(\.slot)
            let name = amsDisplayName(rawID: rawID, fallbackIndex: amsIndex)
            let drying = dryingStatus(from: ams)
            return AMSUnitStatus(
                id: rawID,
                name: name,
                slots: slots,
                temperature: normalizedPositive(doubleValue(ams["temp"])),
                humidityIndex: normalizedPositive(intValue(ams["humidity"])),
                humidityPercent: normalizedPercent(intValue(ams["humidity_raw"])),
                dryingRemainingMinutes: drying.remainingMinutes,
                dryingTemperature: drying.temperature,
                dryingFilament: drying.filament
            )
        }
    }

    private static func dryingStatus(from ams: [String: Any]) -> (remainingMinutes: Int?, temperature: Double?, filament: String?) {
        let drySetting = ams["dry_setting"] as? [String: Any]
        return (
            remainingMinutes: normalizedPositive(intValue(ams["dry_time"])),
            temperature: normalizedPositive(doubleValue(drySetting?["dry_temperature"])),
            filament: normalizedMaterial(stringValue(drySetting?["dry_filament"]))
        )
    }

    private static func activeAMSSlot(from print: [String: Any], ams: [String: Any]) -> (amsID: String, slotIndex: Int)? {
        if let slot = activeAMSSlotFromExtruder(print) {
            return slot
        }
        if let trayNow = intValue(ams["tray_now"]) {
            return activeAMSSlot(fromEncodedTray: trayNow)
        }
        return nil
    }

    private static func activeAMSSlotFromExtruder(_ print: [String: Any]) -> (amsID: String, slotIndex: Int)? {
        guard let extruder = (print["device"] as? [String: Any])?["extruder"] as? [String: Any],
              let info = extruder["info"] as? [[String: Any]] else {
            return nil
        }

        let activeNozzleID: Int
        if let state = intValue(extruder["state"]) {
            activeNozzleID = (state >> 4) & 0xF
        } else {
            activeNozzleID = 0
        }

        guard let activeEntry = info.first(where: { intValue($0["id"]) == activeNozzleID }),
              let snow = intValue(activeEntry["snow"]) else {
            return nil
        }

        let slotIndex = snow & 0x3
        let amsIndex = snow >> 8
        guard slotIndex < 4, amsIndex < 128 else {
            return nil
        }
        return ("\(amsIndex)", slotIndex)
    }

    private static func activeAMSSlot(fromEncodedTray trayNow: Int) -> (amsID: String, slotIndex: Int)? {
        guard trayNow >= 0, trayNow != 254, trayNow != 255 else {
            return nil
        }
        if trayNow >= 80 {
            return ("\(trayNow)", 0)
        }
        let slotIndex = trayNow & 0x3
        let amsIndex = trayNow >> 2
        return ("\(amsIndex)", slotIndex)
    }

    private static func amsDisplayName(rawID: String, fallbackIndex: Int) -> String {
        guard let numericID = Int(rawID) else {
            return "AMS \(fallbackIndex + 1)"
        }
        if numericID >= 128, numericID < 153 {
            return "AMS HT \(numericID - 127)"
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

    private static func normalizedSubBrands(_ value: String?, material: String?) -> String? {
        guard let value = normalizedMaterial(value) else {
            return nil
        }
        if let material,
           value.localizedCaseInsensitiveCompare(material) == .orderedSame {
            return nil
        }
        guard value.localizedCaseInsensitiveContains("bambu") else {
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
        guard value.count == 6 else {
            return nil
        }
        return value.uppercased()
    }

    private static func normalizedPercent(_ value: Int?) -> Int? {
        guard let value, value >= 0 else {
            return nil
        }
        return min(value, 100)
    }

    private static func normalizedPositive(_ value: Int?) -> Int? {
        guard let value, value > 0 else {
            return nil
        }
        return value
    }

    private static func normalizedPositive(_ value: Double?) -> Double? {
        guard let value, value > 0 else {
            return nil
        }
        return value
    }

    private static func rawErrorCode(_ value: Int) -> String {
        String(format: "%08X", value)
    }

    private static func formattedErrorCode(_ rawCode: String) -> String {
        let hex = rawCode.uppercased()
        guard hex.count == 8 else {
            return hex
        }
        let separator = hex.index(hex.startIndex, offsetBy: 4)
        return "\(hex[..<separator])_\(hex[separator...])"
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
