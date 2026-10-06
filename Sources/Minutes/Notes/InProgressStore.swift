import Foundation

/// What a session records about itself when it starts, so it can be finished after a crash.
struct SessionInfo: Codable, Sendable {
    let id: UUID
    let startDate: Date
    var event: EventInfo?
    let preferences: Preferences
}

/// One meeting's crash-safe working folder: ~/Library/Application Support/Minutes/InProgress/<id>/
///
/// - `session.json`: `SessionInfo`
/// - `segments.jsonl`: one `TranscriptSegment` per line, appended as chunks are transcribed
/// - `system.wav` (for speaker separation) and `mic.wav` (only when audio is kept)
/// - `chunks/`: chunk WAVs not yet transcribed
/// - `meeting.json`: a finished meeting waiting for a writable notes folder
///
/// The folder is deleted once the note is saved or the meeting discarded.
struct InProgressStore: Sendable {
    static let root = AppPaths.supportFolder.appendingPathComponent("InProgress", isDirectory: true)

    let folder: URL

    var systemTrack: URL { folder.appendingPathComponent("system.wav") }
    var micTrack: URL { folder.appendingPathComponent("mic.wav") }
    var chunkFolder: URL { folder.appendingPathComponent("chunks", isDirectory: true) }
    private var infoURL: URL { folder.appendingPathComponent("session.json") }
    private var segmentsURL: URL { folder.appendingPathComponent("segments.jsonl") }
    private var meetingURL: URL { folder.appendingPathComponent("meeting.json") }

    static func create(_ info: SessionInfo) throws -> InProgressStore {
        let store = InProgressStore(folder: root.appendingPathComponent(info.id.uuidString, isDirectory: true))
        try FileManager.default.createDirectory(at: store.chunkFolder, withIntermediateDirectories: true)
        try store.saveInfo(info)
        FileManager.default.createFile(atPath: store.segmentsURL.path, contents: nil)
        return store
    }

    /// Every in-progress folder left on disk, oldest first.
    static func all() -> [InProgressStore] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return folders.filter(\.hasDirectoryPath)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(InProgressStore.init(folder:))
    }

    func info() -> SessionInfo? {
        try? Self.decoder.decode(SessionInfo.self, from: Data(contentsOf: infoURL))
    }

    func saveInfo(_ info: SessionInfo) throws {
        try Self.encoder.encode(info).write(to: infoURL, options: .atomic)
    }

    func appendSegment(_ segment: TranscriptSegment) throws {
        var line = try Self.encoder.encode(segment)
        line.append(UInt8(ascii: "\n"))
        let handle = try FileHandle(forWritingTo: segmentsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Segments transcribed so far. A line cut short by a crash is skipped.
    func segments() -> [TranscriptSegment] {
        guard let data = try? Data(contentsOf: segmentsURL) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? Self.decoder.decode(TranscriptSegment.self, from: $0) }
    }

    /// Chunk WAVs that were recorded but not transcribed, in recording order.
    func pendingChunks() -> [AudioChunk] {
        let files = (try? FileManager.default.contentsOfDirectory(at: chunkFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.compactMap { url -> AudioChunk? in
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard parts.count == 2, let source = AudioSource(rawValue: String(parts[0])), let milliseconds = Double(parts[1]),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
            let duration = Double(max(size - WavFormat.headerSize, 0) / 2) / Double(WavFormat.sampleRate)
            return AudioChunk(source: source, start: milliseconds / 1000, duration: duration, url: url)
        }.sorted { $0.start < $1.start }
    }

    static func chunkFileName(source: AudioSource, start: TimeInterval) -> String {
        "\(source.rawValue)-\(Int((start * 1000).rounded())).wav"
    }

    func saveFinishedMeeting(_ meeting: Meeting) throws {
        try Self.encoder.encode(meeting).write(to: meetingURL, options: .atomic)
    }

    func finishedMeeting() -> Meeting? {
        try? Self.decoder.decode(Meeting.self, from: Data(contentsOf: meetingURL))
    }

    func delete() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
