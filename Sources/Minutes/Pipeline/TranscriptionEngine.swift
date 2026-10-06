import Foundation

enum AudioSource: String, Codable, Sendable {
    case mic, system
}

/// A finished chunk WAV waiting for transcription. `start` is the offset from the start of the meeting.
struct AudioChunk: Sendable {
    let source: AudioSource
    let start: TimeInterval
    let duration: TimeInterval
    let url: URL

    var end: TimeInterval { start + duration }
}

/// Text recognized in one chunk, placed at the chunk's offset in the meeting.
struct TranscriptSegment: Codable, Sendable {
    let source: AudioSource
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    var isGap = false
}

protocol TranscriptionEngine: Sendable {
    /// Recorded in the note's front matter (`transcription:`).
    var identifier: String { get }
    func transcribe(_ chunk: URL) async throws -> String
}

enum Timecode {
    /// "HH:MM:SS" for an offset from the start of the meeting.
    static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

extension TranscriptSegment {
    static func gap(for chunk: AudioChunk) -> TranscriptSegment {
        TranscriptSegment(
            source: chunk.source, start: chunk.start, end: chunk.end,
            text: "[\(Timecode.string(chunk.start))–\(Timecode.string(chunk.end)) transcription unavailable]",
            isGap: true
        )
    }
}
