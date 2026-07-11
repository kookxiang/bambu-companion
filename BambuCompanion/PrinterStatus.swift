import Foundation

enum PrinterActivity: String, Equatable {
    case idle
    case printing
    case cancelled
    case paused
    case finished
    case failed
    case unknown

    var title: String {
        switch self {
        case .idle: return L10n.string("Idle")
        case .printing: return L10n.string("Printing")
        case .cancelled: return L10n.string("Cancelled")
        case .paused: return L10n.string("Paused")
        case .finished: return L10n.string("Finished")
        case .failed: return L10n.string("Failed")
        case .unknown: return L10n.string("Unknown")
        }
    }
}

struct PrinterStage: Equatable {
    let id: Int

    var title: String {
        L10n.string(Self.titleKeys[id] ?? "Unknown stage")
    }

    private static let titleKeys: [Int: String] = [
        0: "Printing",
        1: "Auto bed leveling",
        2: "Heatbed preheating",
        3: "Vibration compensation",
        4: "Changing filament",
        5: "Paused by M400",
        6: "Paused: filament ran out",
        7: "Heating hotend",
        8: "Calibrating extrusion",
        9: "Scanning bed surface",
        10: "Inspecting first layer",
        11: "Identifying build plate",
        12: "Calibrating micro lidar",
        13: "Homing toolhead",
        14: "Cleaning nozzle tip",
        15: "Checking extruder temperature",
        16: "Paused by user",
        17: "Paused: front cover fell off",
        18: "Calibrating micro lidar",
        19: "Calibrating extrusion flow",
        20: "Paused: nozzle temperature issue",
        21: "Paused: heatbed temperature issue",
        22: "Unloading filament",
        23: "Paused: skipped step",
        24: "Loading filament",
        25: "Calibrating motor noise",
        26: "Paused: AMS disconnected",
        27: "Paused: low heatbreak fan speed",
        28: "Paused: chamber temperature issue",
        29: "Cooling chamber",
        30: "Paused by user G-code",
        31: "Motor noise calibration demo",
        32: "Paused: nozzle filament detected",
        33: "Paused: cutter issue",
        34: "Paused: first layer issue",
        35: "Paused: nozzle clog",
        36: "Checking absolute accuracy",
        37: "Calibrating absolute accuracy",
        38: "Verifying absolute accuracy",
        39: "Calibrating nozzle offset",
        40: "High-temperature bed leveling",
        41: "Checking quick release",
        42: "Checking door and cover",
        43: "Calibrating laser",
        44: "Checking platform",
        45: "Checking Birdseye camera position",
        46: "Calibrating Birdseye camera",
        47: "Bed leveling phase 1",
        48: "Bed leveling phase 2",
        49: "Heating chamber",
        50: "Cooling heatbed",
        51: "Printing calibration lines",
        52: "Checking material",
        53: "Calibrating live view camera",
        54: "Waiting for heatbed temperature",
        55: "Checking material position",
        56: "Calibrating cutter offset",
        57: "Measuring surface",
        58: "Thermal preconditioning",
        59: "Homing blade holder",
        60: "Calibrating camera offset",
        61: "Calibrating blade holder position",
        62: "Testing hotend pick and place",
        63: "Equalizing chamber temperature",
        64: "Preparing hotend",
        65: "Calibrating nozzle clumping detection",
        66: "Purifying chamber air",
        67: "Measuring rotary attachment",
        68: "Moving toolhead above purge chute",
        69: "Cooling nozzle",
        70: "Centering toolhead over heatbed",
        71: "Active arc fitting",
        72: "Detecting hotend type",
        73: "Detecting build plate alignment",
        74: "Checking heatbed surface",
        75: "Checking heatbed underside",
        76: "Pre-extrusion before printing",
        77: "Preparing AMS"
    ]
}

struct PrinterStatus: Equatable {
    var activity: PrinterActivity = .unknown
    var progress: Int?
    var jobName: String?
    var rawFile: String?
    var gcodeFile: String?
    var gcodeFileDownloaded: String?
    var subtaskName: String?
    var gcodeFilePreparePercent: Int?
    var remainingMinutes: Int?
    var currentLayer: Int?
    var totalLayers: Int?
    var currentStage: PrinterStage?
    var nozzleTemperature: Double?
    var targetNozzleTemperature: Double?
    var leftNozzleTemperature: Double?
    var targetLeftNozzleTemperature: Double?
    var rightNozzleTemperature: Double?
    var targetRightNozzleTemperature: Double?
    var bedTemperature: Double?
    var targetBedTemperature: Double?
    var chamberTemperature: Double?
    var targetChamberTemperature: Double?
    var cameraStreamURL: String?
    var alert: PrinterAlert?
    var airductMode: String?
    var fans = PrinterFanStatus()
    var amsUnits: [AMSUnitStatus] = []
    var updatedAt: Date?
    var alertUpdate: PrinterAlertUpdate = .unchanged
    var currentStageUpdate: PrinterStageUpdate = .unchanged

    var primaryTitle: String {
        if activity == .printing, let currentStage {
            return currentStage.title
        }
        return activity.title
    }

    static let empty = PrinterStatus()

    func mergingIncrementalUpdate(_ update: PrinterStatus) -> PrinterStatus {
        var merged = self
        if update.activity != .unknown {
            merged.activity = update.activity
        }
        merged.progress = update.progress ?? progress
        merged.rawFile = update.rawFile ?? rawFile
        merged.gcodeFile = update.gcodeFile ?? gcodeFile
        merged.gcodeFileDownloaded = update.gcodeFileDownloaded ?? gcodeFileDownloaded
        merged.subtaskName = update.subtaskName ?? subtaskName
        merged.gcodeFilePreparePercent = update.gcodeFilePreparePercent ?? gcodeFilePreparePercent
        merged.jobName = update.jobName ?? jobName
        merged.remainingMinutes = update.remainingMinutes ?? remainingMinutes
        merged.currentLayer = update.currentLayer ?? currentLayer
        merged.totalLayers = update.totalLayers ?? totalLayers
        switch update.currentStageUpdate {
        case .unchanged:
            break
        case .set(let currentStage):
            merged.currentStage = currentStage
        }
        merged.currentStageUpdate = .unchanged
        merged.nozzleTemperature = update.nozzleTemperature ?? nozzleTemperature
        merged.targetNozzleTemperature = update.targetNozzleTemperature ?? targetNozzleTemperature
        merged.leftNozzleTemperature = update.leftNozzleTemperature ?? leftNozzleTemperature
        merged.targetLeftNozzleTemperature = update.targetLeftNozzleTemperature ?? targetLeftNozzleTemperature
        merged.rightNozzleTemperature = update.rightNozzleTemperature ?? rightNozzleTemperature
        merged.targetRightNozzleTemperature = update.targetRightNozzleTemperature ?? targetRightNozzleTemperature
        merged.bedTemperature = update.bedTemperature ?? bedTemperature
        merged.targetBedTemperature = update.targetBedTemperature ?? targetBedTemperature
        merged.chamberTemperature = update.chamberTemperature ?? chamberTemperature
        merged.targetChamberTemperature = update.targetChamberTemperature ?? targetChamberTemperature
        merged.cameraStreamURL = update.cameraStreamURL ?? cameraStreamURL
        switch update.alertUpdate {
        case .unchanged:
            break
        case .set(let alert):
            merged.alert = alert
        }
        merged.airductMode = update.airductMode ?? airductMode
        if update.fans.hasAnyValue {
            merged.fans = update.fans
        }
        if !update.amsUnits.isEmpty {
            merged.amsUnits = update.amsUnits
        }
        merged.updatedAt = update.updatedAt ?? updatedAt
        return merged
    }
}

struct PrinterFanStatus: Equatable {
    var partCoolingPercent: Int?
    var auxiliaryPercent: Int?
    var chamberPercent: Int?
    var heatbreakPercent: Int?

    var hasAnyValue: Bool {
        partCoolingPercent != nil ||
            auxiliaryPercent != nil ||
            chamberPercent != nil ||
            heatbreakPercent != nil
    }
}

struct PrinterAlert: Equatable {
    var title: String
    var detail: String?
    var wikiURL: URL?
    var source: PrinterAlertSource = .printer
}

enum PrinterAlertSource: Equatable {
    case printer
    case hms
}

enum PrinterAlertUpdate: Equatable {
    case unchanged
    case set(PrinterAlert?)
}

enum PrinterStageUpdate: Equatable {
    case unchanged
    case set(PrinterStage?)
}

struct AMSUnitStatus: Equatable, Identifiable {
    var id: String
    var name: String
    var slots: [AMSSlotStatus]
    var temperature: Double?
    var humidityIndex: Int?
    var humidityPercent: Int?
    var dryingRemainingMinutes: Int?
    var dryingTemperature: Double?
    var dryingFilament: String?

    var isDrying: Bool {
        guard let dryingRemainingMinutes else {
            return false
        }
        return dryingRemainingMinutes > 0
    }
}

struct AMSSlotStatus: Equatable, Identifiable {
    var id: String
    var index: Int
    var material: String?
    var colorHex: String?
    var remainingPercent: Int?
    var name: String?
    var subBrands: String?
    var tagUID: String?
    var trayInfoIndex: String?
    var diameter: Double?
    var weight: Double?
    var nozzleTemperatureMin: Double?
    var nozzleTemperatureMax: Double?
    var isActive: Bool = false

    var remainingWeight: Double? {
        guard let weight, let remainingPercent else {
            return nil
        }
        return weight * Double(remainingPercent) / 100
    }
}

enum ConnectionState: Equatable {
    case notConfigured
    case disconnected
    case connecting
    case connected
    case authenticationFailed
    case failed(String)

    var title: String {
        switch self {
        case .notConfigured: return L10n.string("Not configured")
        case .disconnected: return L10n.string("Disconnected")
        case .connecting: return L10n.string("Connecting")
        case .connected: return L10n.string("Connected")
        case .authenticationFailed: return L10n.string("Authentication failed")
        case .failed(let message): return message
        }
    }
}
