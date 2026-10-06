import Foundation

enum UpdateClientError: LocalizedError {
    case rejected(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .rejected(let message), .failed(let message): message
        }
    }
}

/// Minutes' own GitHub releases: the latest one, and its disk image.
struct UpdateClient: Sendable {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/nanoarmando/minutes/releases/latest")!

    /// Ephemeral and cacheless, never `URLSession.shared`: no cookies, no cache, the download is the only copy.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private static let chunkSize = 256 * 1024

    /// `nil` when nothing is published yet: GitHub answers 404 for a repository without releases.
    func latestRelease() async throws -> UpdateRelease? {
        var request = URLRequest(url: Self.latestReleaseURL)
        // GitHub rejects a request without a user agent and serves an older format without the Accept header.
        request.setValue("Minutes", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        try Self.requireSuccess(response, body: data)
        do {
            return try JSONDecoder().decode(UpdateRelease.self, from: data)
        } catch {
            throw UpdateClientError.failed("GitHub's answer could not be read.")
        }
    }

    /// Written chunk by chunk so progress is visible; a failed or cancelled download deletes the partial file.
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.setValue("Minutes", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await Self.session.bytes(for: request)
        try Self.requireSuccess(response, body: nil)

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw UpdateClientError.failed("The download could not be saved.")
        }
        do {
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            let expected = response.expectedContentLength
            var buffer = Data()
            buffer.reserveCapacity(Self.chunkSize)
            var written: Int64 = 0
            for try await byte in bytes {
                buffer.append(byte)
                guard buffer.count >= Self.chunkSize else { continue }
                try Task.checkCancellation()
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 { progress(Double(written) / Double(expected)) }
            }
            try Task.checkCancellation()
            try handle.write(contentsOf: buffer)
            progress(1)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private static func requireSuccess(_ response: URLResponse, body: Data?) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        // GitHub explains a rate limit (403/429) in the body; that beats a bare status code.
        struct Message: Decodable { let message: String }
        if let body, let error = try? JSONDecoder().decode(Message.self, from: body) {
            throw UpdateClientError.rejected(error.message)
        }
        throw UpdateClientError.failed("GitHub answered with HTTP \(http.statusCode).")
    }
}
