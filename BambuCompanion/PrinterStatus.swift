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
    var nozzleTemperature: Double?
    var leftNozzleTemperature: Double?
    var rightNozzleTemperature: Double?
    var bedTemperature: Double?
    var amsUnits: [AMSUnitStatus] = []
    var updatedAt: Date?

    static let empty = PrinterStatus()
}

struct AMSUnitStatus: Equatable, Identifiable {
    var id: String
    var name: String
    var slots: [AMSSlotStatus]
}

struct AMSSlotStatus: Equatable, Identifiable {
    var id: String
    var index: Int
    var material: String?
    var colorHex: String?
    var isActive: Bool = false
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
