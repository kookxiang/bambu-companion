import CryptoKit
import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

enum DurationText {
    static func remainingMinutes(_ minutes: Int?, locale: Locale = .current) -> String {
        guard let minutes else {
            return "--"
        }

        var calendar = Calendar.current
        calendar.locale = locale

        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.allowedUnits = minutes < 60 ? [.minute] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.dropLeading]

        return formatter.string(from: TimeInterval(minutes * 60)) ?? "--"
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension String {
    var sha256Hex: String {
        SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
