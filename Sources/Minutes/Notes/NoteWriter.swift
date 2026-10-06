import AVFoundation
import Foundation

/// Writes notes, sidecars and kept audio into the notes folder. Every write is atomic (temporary file, then
/// rename), so an editor or sync tool never sees a half-written note.
struct NoteWriter: Sendable {
    enum WriteError: LocalizedError {
        case folderUnavailable(URL)

        var errorDescription: String? {
            switch self {
            case .folderUnavailable(let url): "The notes folder “\(url.path)” is missing or not writable."
            }
        }
    }

    let folder: URL
    var fileNamePattern = "{date} {time} {title}"

    private var hiddenFolder: URL { folder.appendingPathComponent(".minutes", isDirectory: true) }

    /// Writes the note and its sidecar and returns the note's URL. `audioTracks` (16 kHz WAVs) are mixed into one
    /// m4a next to the sidecar when given.
    func save(_ meeting: Meeting, audioTracks: [URL] = []) throws -> URL {
        try ensureFolder()
        try FileManager.default.createDirectory(at: hiddenFolder, withIntermediateDirectories: true)

        var audioPath: String?
        if !audioTracks.isEmpty {
            let name = "\(meeting.id.uuidString).m4a"
            try Self.exportM4A(mixing: audioTracks, to: hiddenFolder.appendingPathComponent(name))
            audioPath = ".minutes/\(name)"
        }
        let record = Sidecar.SummaryRecord(typeID: meeting.summary.typeID, model: meeting.summary.model, date: meeting.summary.date, error: meeting.summary.error)
        try writeSidecar(Sidecar(id: meeting.id, segments: meeting.lines, summaries: [record]))

        let url = availableURL(for: meeting)
        try Data(NoteFile.render(meeting, audioPath: audioPath).utf8).write(to: url, options: .atomic)
        return url
    }

    /// Replaces the summary section and summary metadata of an existing note, keeping every other edit.
    func updateSummary(of noteURL: URL, id: UUID, with summary: SummaryOutcome) throws {
        var document = try String(contentsOf: noteURL, encoding: .utf8)
        document = NoteFile.replacingSummary(in: document, with: summary.sectionBody)
        if summary.text != nil {
            document = NoteFile.settingFrontMatter([("summary_type", summary.typeID ?? ""), ("summary_model", summary.model ?? "")], in: document)
        }
        try Data(document.utf8).write(to: noteURL, options: .atomic)

        var sidecar = readSidecar(id: id) ?? Sidecar(id: id, segments: [], summaries: [])
        try FileManager.default.createDirectory(at: hiddenFolder, withIntermediateDirectories: true)
        sidecar.summaries.append(.init(typeID: summary.typeID, model: summary.model, date: summary.date, error: summary.error))
        try writeSidecar(sidecar)
    }

    /// Writes the note's tags and records which of them were added by hand.
    func setTags(of noteURL: URL, id: UUID, tags: [String], manual: [String]) throws {
        let document = try String(contentsOf: noteURL, encoding: .utf8)
        try Data(NoteFile.settingTags(tags, in: document).utf8).write(to: noteURL, options: .atomic)
        var sidecar = readSidecar(id: id) ?? Sidecar(id: id, segments: [], summaries: [])
        sidecar.manualTags = manual
        try FileManager.default.createDirectory(at: hiddenFolder, withIntermediateDirectories: true)
        try writeSidecar(sidecar)
    }

    func readSidecar(id: UUID) -> Sidecar? {
        let url = hiddenFolder.appendingPathComponent("\(id.uuidString).json")
        return try? Self.decoder.decode(Sidecar.self, from: Data(contentsOf: url))
    }

    private func writeSidecar(_ sidecar: Sidecar) throws {
        try Self.encoder.encode(sidecar).write(to: hiddenFolder.appendingPathComponent("\(sidecar.id.uuidString).json"), options: .atomic)
    }

    /// Creates the folder when only the folder itself is missing; a missing parent (unmounted volume) or a
    /// read-only folder is reported so the meeting can be kept until the user picks another one.
    private func ensureFolder() throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: folder.path), manager.fileExists(atPath: folder.deletingLastPathComponent().path) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        guard manager.isWritableFile(atPath: folder.path) else { throw WriteError.folderUnavailable(folder) }
    }

    private func availableURL(for meeting: Meeting) -> URL {
        let base = fileNamePattern
            .replacingOccurrences(of: "{date}", with: NoteFile.format(meeting.date, "yyyy-MM-dd"))
            .replacingOccurrences(of: "{time}", with: NoteFile.format(meeting.date, "HHmm"))
            .replacingOccurrences(of: "{title}", with: meeting.title)
        let name = Self.sanitizedFileName(base)
        var candidate = folder.appendingPathComponent("\(name).md")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(suffix).md")
            suffix += 1
        }
        return candidate
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? "Meeting" : String(cleaned.prefix(150))
    }

    /// Sums the tracks sample by sample and encodes the mix as AAC.
    private static func exportM4A(mixing tracks: [URL], to url: URL) throws {
        let sources = tracks.compactMap { try? WavWriter.readSamples(from: $0) }
        let length = sources.map(\.count).max() ?? 0
        guard length > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(WavFormat.sampleRate), channels: 1, interleaved: false) else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: WavFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
        ]
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).m4a")
        do {
            let file = try AVAudioFile(forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let blockSize = 65_536
            for blockStart in stride(from: 0, to: length, by: blockSize) {
                let count = min(blockSize, length - blockStart)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { continue }
                buffer.frameLength = AVAudioFrameCount(count)
                let channel = buffer.floatChannelData![0]
                for index in 0..<count {
                    let sum = sources.reduce(Float(0)) { total, track in
                        blockStart + index < track.count ? total + Float(track[blockStart + index]) / 32768 : total
                    }
                    channel[index] = max(-1, min(1, sum))
                }
                try file.write(from: buffer)
            }
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
