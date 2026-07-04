import Foundation

enum PrinterActivity: String, Equatable {
    case idle
    case printing
    case paused
    case finished
    case failed
    case unknown

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .printing: return "Printing"
        case .paused: return "Paused"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
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
    var amsUnits: [AMSUnitStatus] = []
    var updatedAt: Date?

    static let empty = PrinterStatus()
}

struct PrinterAlert: Equatable {
    var title: String
    var detail: String?
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
        case .notConfigured: return "Not configured"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .authenticationFailed: return "Authentication failed"
        case .failed(let message): return message
        }
    }
}
