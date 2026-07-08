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
