import Foundation

enum CoverImageState: Equatable {
    case unavailable
    case loading
    case ready(URL)
    case failed(String)
}

struct CoverImageJob: Equatable {
    let host: String
    let accessCode: String
    let rawFile: String?
    let gcodeFile: String?
    let gcodeFileDownloaded: String?
    let subtaskName: String?

    var cacheKey: String? {
        let candidates = CoverImageCandidateBuilder.candidates(
            rawFile: rawFile,
            gcodeFile: gcodeFile,
            gcodeFileDownloaded: gcodeFileDownloaded,
            subtaskName: subtaskName
        )
        return candidates.first
    }
}

enum CoverImageCandidateBuilder {
    static func candidates(
        rawFile: String? = nil,
        gcodeFile: String?,
        gcodeFileDownloaded: String? = nil,
        subtaskName: String?
    ) -> [String] {
        var names: [String] = []
        appendCandidates(from: gcodeFileDownloaded, to: &names)
        appendCandidates(from: subtaskName, to: &names)
        appendCandidates(from: gcodeFile, to: &names)
        appendCandidates(from: rawFile, to: &names)
        return names.removingDuplicates()
    }

    static func candidates(gcodeFile: String?, subtaskName: String?) -> [String] {
        candidates(rawFile: nil, gcodeFile: gcodeFile, gcodeFileDownloaded: nil, subtaskName: subtaskName)
    }

    private static func appendCandidates(from value: String?, to names: inout [String]) {
        guard let value else {
            return
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("Metadata/") else {
            return
        }

        let basename = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !basename.isEmpty else {
            return
        }

        if basename.hasSuffix(".3mf") {
            names.append(basename)
        } else {
            names.append("\(basename).3mf")
            names.append("\(basename).gcode.3mf")
        }
    }
}

final class CoverImageCache {
    enum CacheError: Error {
        case missingPlateImage
    }

    let rootDirectory: URL

    init(rootDirectory: URL = CoverImageCache.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("BambuCompanion/CoverImages", isDirectory: true)
    }

    func cachedCoverURL(for remotePath: String, size: Int64?) -> URL? {
        let directory = cacheDirectory(for: remotePath, size: size)
        let coverURL = directory.appendingPathComponent("cover.png")
        return FileManager.default.fileExists(atPath: coverURL.path) ? coverURL : nil
    }

    func cachedModelURL(for remotePath: String, size: Int64?) -> URL? {
        let directory = cacheDirectory(for: remotePath, size: size)
        let modelURL = directory.appendingPathComponent("model.3mf")
        return FileManager.default.fileExists(atPath: modelURL.path) ? modelURL : nil
    }

    func modelURL(for remotePath: String, size: Int64?) throws -> URL {
        let directory = cacheDirectory(for: remotePath, size: size)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("model.3mf")
    }

    func extractCover(from modelURL: URL, remotePath: String, size: Int64?) throws -> URL {
        let data = try Data(contentsOf: modelURL)
        let archive = try ZIPArchive(data: data)
        let sliceInfo = try archive.data(named: "Metadata/slice_info.config")
        let plate = CoverImageMetadataParser.plateNumber(from: sliceInfo) ?? 1
        let imageData = try archive.data(named: "Metadata/plate_\(plate).png")
        let coverURL = cacheDirectory(for: remotePath, size: size).appendingPathComponent("cover.png")
        try FileManager.default.createDirectory(at: coverURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try imageData.write(to: coverURL, options: .atomic)
        return coverURL
    }

    private func cacheDirectory(for remotePath: String, size: Int64?) -> URL {
        let key = "\(remotePath)|\(size.map(String.init) ?? "unknown")".sha256Hex
        return rootDirectory.appendingPathComponent(key, isDirectory: true)
    }
}

enum CoverImageMetadataParser {
    static func plateNumber(from data: Data) -> Int? {
        guard let xml = String(data: data, encoding: .utf8),
              let range = xml.range(of: #"<metadata[^>]+key="index"[^>]+value="([0-9]+)""#, options: .regularExpression) else {
            return nil
        }
        let match = String(xml[range])
        guard let valueRange = match.range(of: #"value="([0-9]+)""#, options: .regularExpression) else {
            return nil
        }
        return Int(match[valueRange].dropFirst(7).dropLast())
    }
}

final class CoverImageService {
    private static let retryCount = 13
    private static let retryDelayNanoseconds: UInt64 = 5_000_000_000
    private static let fallbackDownloadLimit = 8

    private let cache: CoverImageCache
    private let downloader: FTPSDownloader

    init(cache: CoverImageCache = CoverImageCache(), downloader: FTPSDownloader = FTPSDownloader()) {
        self.cache = cache
        self.downloader = downloader
    }

    func reset() {
    }

    func loadCover(for job: CoverImageJob) async throws -> URL? {
        guard job.cacheKey != nil else {
            return nil
        }

        let candidates = CoverImageCandidateBuilder.candidates(
            rawFile: job.rawFile,
            gcodeFile: job.gcodeFile,
            gcodeFileDownloaded: job.gcodeFileDownloaded,
            subtaskName: job.subtaskName
        )
        diagnostic("cover candidates: \(candidates)")
        for attempt in 0..<Self.retryCount {
            diagnostic("cover lookup attempt \(attempt + 1)/\(Self.retryCount)")
            for filename in candidates {
                for remotePath in ["/cache/\(filename)", "/\(filename)"] {
                    if let url = try await loadCover(from: remotePath, job: job) {
                        return url
                    }
                }
            }
            if let fallbackURL = try await loadCoverFromRecentModels(job: job) {
                return fallbackURL
            }

            if attempt < Self.retryCount - 1 {
                try await Task.sleep(nanoseconds: Self.retryDelayNanoseconds)
            }
        }
        return nil
    }

    private func loadCover(from remotePath: String, job: CoverImageJob) async throws -> URL? {
        if let cached = cache.cachedCoverURL(for: remotePath, size: nil) {
            diagnostic("cover cache hit: \(remotePath)")
            return cached
        }
        diagnostic("stat cover candidate: \(remotePath)")
        let remoteFile: RemoteFileInfo?
        do {
            remoteFile = try await downloader.stat(host: job.host, accessCode: job.accessCode, remotePath: remotePath)
        } catch {
            if isMissingRemoteFileError(error) {
                diagnostic("cover candidate missing: \(remotePath)")
                return nil
            }
            diagnostic("stat failed for \(remotePath): \(error.localizedDescription); trying direct download")
            return try await downloadAndExtractCover(from: remotePath, size: nil, job: job)
        }
        guard let remoteFile else {
            diagnostic("cover candidate missing: \(remotePath)")
            return nil
        }
        if let cached = cache.cachedCoverURL(for: remotePath, size: remoteFile.size) {
            diagnostic("cover cache hit: \(remotePath) size=\(remoteFile.size.map(String.init) ?? "unknown")")
            return cached
        }
        return try await downloadAndExtractCover(from: remotePath, size: remoteFile.size, job: job)
    }

    private func loadCoverFromRecentModels(job: CoverImageJob) async throws -> URL? {
        for directory in ["/cache", "/"] {
            diagnostic("listing FTPS directory for cover fallback: \(directory)")
            let entries = try await downloader.list(host: job.host, accessCode: job.accessCode, remoteDirectory: directory)
            let modelEntries = entries
                .filter { $0.path.localizedCaseInsensitiveContains(".3mf") }
                .filter { !$0.path.contains("/Metadata/") }
                .suffix(Self.fallbackDownloadLimit)
                .reversed()

            for entry in modelEntries {
                if let cached = cache.cachedCoverURL(for: entry.path, size: entry.size) {
                    diagnostic("fallback cover cache hit: \(entry.path)")
                    return cached
                }
                do {
                    return try await downloadAndExtractCover(from: entry.path, size: entry.size, job: job, isFallback: true)
                } catch {
                    diagnostic("fallback cover extraction failed: \(entry.path): \(error.localizedDescription)")
                }
            }
        }
        return nil
    }

    private func downloadAndExtractCover(
        from remotePath: String,
        size: Int64?,
        job: CoverImageJob,
        isFallback: Bool = false
    ) async throws -> URL {
        let modelURL = try cache.modelURL(for: remotePath, size: size)
        if cache.cachedModelURL(for: remotePath, size: size) == nil {
            diagnostic("\(isFallback ? "fallback " : "")downloading model for cover: \(remotePath) size=\(size.map(String.init) ?? "unknown")")
            try await downloader.download(host: job.host, accessCode: job.accessCode, remotePath: remotePath, destination: modelURL)
        }
        let coverURL = try cache.extractCover(from: modelURL, remotePath: remotePath, size: size)
        diagnostic("\(isFallback ? "fallback " : "")cover extracted: \(remotePath)")
        return coverURL
    }

    private func diagnostic(_ message: String) {
        FileHandle.standardError.write(Data("[BambuCompanion] \(message)\n".utf8))
    }

    private func isMissingRemoteFileError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("550") || message.contains("curl: (78)") || message.contains("does not exist")
    }
}
