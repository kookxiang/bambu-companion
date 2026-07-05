import Foundation

struct HMSErrorCatalog {
    static let shared = HMSErrorCatalog()

    private let localizedTables: [String: [String: String]]

    init(resourceDirectoryURL: URL? = nil) {
        let directoryURL = resourceDirectoryURL ?? Self.findResourceDirectory()
        localizedTables = Self.loadLocalizedTables(from: directoryURL)
    }

    func text(forRawCode rawCode: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String? {
        let normalizedCode = rawCode.replacingOccurrences(of: "_", with: "").uppercased()
        for language in Self.languageCandidates(from: preferredLanguages) {
            if let text = localizedTables[language]?[normalizedCode] {
                return text
            }
        }
        return nil
    }

    private static func findResourceDirectory() -> URL? {
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in bundles {
            if let url = bundle.url(forResource: "HMSResources", withExtension: nil) {
                return url
            }
        }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("HMSResources", isDirectory: true)
        return FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil
    }

    private static func loadLocalizedTables(from directoryURL: URL?) -> [String: [String: String]] {
        guard let directoryURL,
              let resourceURLs = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
              ) else {
            return [:]
        }

        var tables: [String: [String: String]] = [:]
        for url in resourceURLs where url.lastPathComponent.hasPrefix("hms_") && url.pathExtension == "json" {
            let filename = url.deletingPathExtension().lastPathComponent
            guard let language = languageCode(fromHMSFilename: filename),
                  let table = loadTable(from: url, language: language) else {
                continue
            }
            tables[language, default: [:]].merge(table) { current, _ in current }
        }
        return tables
    }

    private static func languageCode(fromHMSFilename filename: String) -> String? {
        guard filename.hasPrefix("hms_"), !filename.hasPrefix("hms_action_") else {
            return nil
        }
        let parts = filename.split(separator: "_")
        guard parts.count >= 3 else {
            return nil
        }
        return normalizedLanguageCode(String(parts[1]))
    }

    private static func loadTable(from url: URL, language: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let dataObject = root["data"] as? [String: Any],
              let deviceHMS = dataObject["device_hms"] as? [String: Any],
              let entries = deviceHMS[language] as? [[String: Any]] else {
            return nil
        }

        var table: [String: String] = [:]
        for entry in entries {
            guard let ecode = entry["ecode"] as? String,
                  let intro = entry["intro"] as? String,
                  !ecode.isEmpty,
                  !intro.isEmpty else {
                continue
            }
            table[ecode.uppercased()] = intro
        }
        return table
    }

    private static func languageCandidates(from preferredLanguages: [String]) -> [String] {
        var candidates: [String] = []
        for language in preferredLanguages {
            let normalized = normalizedLanguageCode(language)
            if !candidates.contains(normalized) {
                candidates.append(normalized)
            }
        }
        if !candidates.contains("en") {
            candidates.append("en")
        }
        return candidates
    }

    private static func normalizedLanguageCode(_ language: String) -> String {
        let lowercased = language.replacingOccurrences(of: "_", with: "-").lowercased()
        if lowercased == "zh-hans" || lowercased.hasPrefix("zh-hans-") || lowercased == "zh-cn" {
            return "zh-cn"
        }
        return String(lowercased.split(separator: "-").first ?? "en")
    }
}
