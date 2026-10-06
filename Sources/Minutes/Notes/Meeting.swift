import Foundation

/// A finished meeting, ready to be written as a note. Also stored as `meeting.json` in its in-progress folder
/// while the notes folder is unavailable.
struct Meeting: Codable, Sendable {
    let id: UUID
    var title: String
    let date: Date
    let duration: TimeInterval
    var lines: [TranscriptLine]
    var tags: [String] = []
    /// Engine identifier written as `transcription:` in the front matter.
    var transcription: String
    var recovered: Bool
    var summary: SummaryOutcome
    /// True when the system track carried no signal: only the microphone was recorded.
    var systemAudioSilent = false
    /// The calendar event in progress when the recording started.
    var event: EventInfo?

    var speakers: [String] { TranscriptAssembler.speakers(in: lines) }
}

/// The result of the latest summary attempt.
struct SummaryOutcome: Codable, Sendable {
    var text: String?
    var typeID: String?
    var model: String?
    var error: String?
    var date = Date()

    static let notGenerated = SummaryOutcome()

    /// The Markdown placed between the summary markers.
    var sectionBody: String {
        if let text { return text }
        if let error { return "_The summary could not be generated: \(error)_" }
        return "_The summary was not generated. Configure a summary provider and summarize this meeting from the Meetings window._"
    }
}

/// The JSON sidecar in `<notes folder>/.minutes/<id>.json`. The Markdown note is complete without it.
struct Sidecar: Codable, Sendable {
    struct SummaryRecord: Codable, Sendable {
        var typeID: String?
        var model: String?
        var date: Date
        var error: String?
    }

    var id: UUID
    var segments: [TranscriptLine]
    var summaries: [SummaryRecord]
    /// Tags the user added by hand; re-tagging keeps them.
    var manualTags: [String]? = nil
    /// The calendar event, kept for client detection when re-tagging.
    var event: EventInfo? = nil
    var tagging: TaggingState? = nil
}

/// Whether automatic tagging still has to run for a note (pending until an attempt succeeds) and why it last failed.
struct TaggingState: Codable, Sendable, Equatable {
    var pending: Bool
    var lastError: String?
}
