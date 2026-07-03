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
        for attempt in 0..<Self.retryCount {
            for filename in candidates {
                for remotePath in ["/cache/\(filename)", "/\(filename)"] {
                    if let url = try await loadCover(from: remotePath, job: job) {
                        return url
                    }
                }
            }

            if attempt < Self.retryCount - 1 {
                try await Task.sleep(nanoseconds: Self.retryDelayNanoseconds)
            }
        }
        return nil
    }

    private func loadCover(from remotePath: String, job: CoverImageJob) async throws -> URL? {
        if let cached = cache.cachedCoverURL(for: remotePath, size: nil) {
            return cached
        }
        guard let remoteFile = try await downloader.stat(host: job.host, accessCode: job.accessCode, remotePath: remotePath) else {
            return nil
        }
        if let cached = cache.cachedCoverURL(for: remotePath, size: remoteFile.size) {
            return cached
        }
        let modelURL = try cache.modelURL(for: remotePath, size: remoteFile.size)
        if cache.cachedModelURL(for: remotePath, size: remoteFile.size) == nil {
            try await downloader.download(host: job.host, accessCode: job.accessCode, remotePath: remotePath, destination: modelURL)
        }
        return try cache.extractCover(from: modelURL, remotePath: remotePath, size: remoteFile.size)
    }
}
