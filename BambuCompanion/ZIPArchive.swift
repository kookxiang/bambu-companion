import Compression
import Foundation

struct ZIPArchive {
    enum ArchiveError: Error {
        case invalidArchive
        case fileNotFound(String)
        case unsupportedCompression(UInt16)
        case decompressionFailed
    }

    private let data: Data
    private let entries: [String: Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try ZIPArchive.readEntries(from: data)
    }

    func data(named name: String) throws -> Data {
        guard let entry = entries[name] else {
            throw ArchiveError.fileNotFound(name)
        }
        let compressed = data[entry.dataRange]
        switch entry.compressionMethod {
        case 0:
            return Data(compressed)
        case 8:
            return try inflate(deflated: Data(compressed), uncompressedSize: entry.uncompressedSize)
        default:
            throw ArchiveError.unsupportedCompression(entry.compressionMethod)
        }
    }

    private func inflate(deflated: Data, uncompressedSize: Int) throws -> Data {
        var output = Data(count: uncompressedSize)
        let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
            deflated.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    uncompressedSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    deflated.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == uncompressedSize else {
            throw ArchiveError.decompressionFailed
        }
        return output
    }

    private static func readEntries(from data: Data) throws -> [String: Entry] {
        guard let endOfCentralDirectory = findEndOfCentralDirectory(in: data) else {
            throw ArchiveError.invalidArchive
        }
        let entryCount = Int(data.uint16LE(at: endOfCentralDirectory + 10))
        var offset = Int(data.uint32LE(at: endOfCentralDirectory + 16))
        var entries: [String: Entry] = [:]

        for _ in 0..<entryCount {
            guard data.uint32LE(at: offset) == 0x02014B50 else {
                throw ArchiveError.invalidArchive
            }
            let compressionMethod = data.uint16LE(at: offset + 10)
            let compressedSize = Int(data.uint32LE(at: offset + 20))
            let uncompressedSize = Int(data.uint32LE(at: offset + 24))
            let filenameLength = Int(data.uint16LE(at: offset + 28))
            let extraLength = Int(data.uint16LE(at: offset + 30))
            let commentLength = Int(data.uint16LE(at: offset + 32))
            let localHeaderOffset = Int(data.uint32LE(at: offset + 42))
            let filenameStart = offset + 46
            let filenameEnd = filenameStart + filenameLength
            guard filenameEnd <= data.count,
                  let filename = String(data: data[filenameStart..<filenameEnd], encoding: .utf8) else {
                throw ArchiveError.invalidArchive
            }

            guard data.uint32LE(at: localHeaderOffset) == 0x04034B50 else {
                throw ArchiveError.invalidArchive
            }
            let localFilenameLength = Int(data.uint16LE(at: localHeaderOffset + 26))
            let localExtraLength = Int(data.uint16LE(at: localHeaderOffset + 28))
            let dataStart = localHeaderOffset + 30 + localFilenameLength + localExtraLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= data.count else {
                throw ArchiveError.invalidArchive
            }

            entries[filename] = Entry(
                compressionMethod: compressionMethod,
                dataRange: dataStart..<dataEnd,
                uncompressedSize: uncompressedSize
            )
            offset = filenameEnd + extraLength + commentLength
        }
        return entries
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else {
            return nil
        }
        let lowerBound = max(0, data.count - 65_557)
        var index = data.count - 22
        while index >= lowerBound {
            if data.uint32LE(at: index) == 0x06054B50 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private struct Entry {
        let compressionMethod: UInt16
        let dataRange: Range<Int>
        let uncompressedSize: Int
    }
}

extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
        UInt32(self[offset + 1]) << 8 |
        UInt32(self[offset + 2]) << 16 |
        UInt32(self[offset + 3]) << 24
    }
}
