import Foundation

struct RemoteFileInfo: Equatable {
    let size: Int64?
}

final class FTPSDownloader {
    enum DownloaderError: LocalizedError {
        case curlFailed(Int32, String)
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .curlFailed(let code, let output):
                return "FTPS request failed (\(code)): \(output)"
            case .invalidURL:
                return "Invalid FTPS URL"
            }
        }
    }

    func stat(host: String, accessCode: String, remotePath: String) async throws -> RemoteFileInfo? {
        do {
            let output = try await runCurl(arguments: [
                "--silent",
                "--show-error",
                "--insecure",
                "--ftp-ssl-reqd",
                "--user", "bblp:\(accessCode)",
                "--head",
                ftpsURL(host: host, remotePath: remotePath)
            ])
            return RemoteFileInfo(size: parseContentLength(from: output))
        } catch {
            if error.localizedDescription.contains("550") {
                return nil
            }
            throw error
        }
    }

    func download(host: String, accessCode: String, remotePath: String, destination: URL) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try await runCurl(arguments: [
            "--silent",
            "--show-error",
            "--fail",
            "--insecure",
            "--ftp-ssl-reqd",
            "--user", "bblp:\(accessCode)",
            "--output", destination.path,
            ftpsURL(host: host, remotePath: remotePath)
        ])
    }

    private func ftpsURL(host: String, remotePath: String) -> String {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedPath = remotePath.split(separator: "/").map { component in
            String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
        }.joined(separator: "/")
        return "ftps://\(cleanHost):990/\(encodedPath)"
    }

    private func parseContentLength(from output: String) -> Int64? {
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, parts[0].localizedCaseInsensitiveCompare("Content-Length") == .orderedSame {
                return Int64(parts[1])
            }
        }
        return nil
    }

    private func runCurl(arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw DownloaderError.curlFailed(process.terminationStatus, output)
            }
            return output
        }.value
    }
}

