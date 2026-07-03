import Foundation

struct PrinterConfiguration: Equatable {
    var displayName: String
    var host: String
    var serialNumber: String
    var accessCode: String

    var isComplete: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bambu H2D" : trimmed
    }
}

final class PrinterConfigurationStore {
    private enum Keys {
        static let displayName = "printer.displayName"
        static let host = "printer.host"
        static let serialNumber = "printer.serialNumber"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func load() -> PrinterConfiguration {
        PrinterConfiguration(
            displayName: defaults.string(forKey: Keys.displayName) ?? "",
            host: defaults.string(forKey: Keys.host) ?? "",
            serialNumber: defaults.string(forKey: Keys.serialNumber) ?? "",
            accessCode: (try? keychain.readAccessCode()) ?? ""
        )
    }

    func save(_ configuration: PrinterConfiguration) throws {
        defaults.set(configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.displayName)
        defaults.set(configuration.host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.host)
        defaults.set(configuration.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.serialNumber)
        try keychain.saveAccessCode(configuration.accessCode)
    }
}
