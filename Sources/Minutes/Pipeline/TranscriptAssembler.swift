// Speaker assignment and line merging are adapted from Muesli (https://github.com/Muesli-HQ/muesli),
// native/MuesliNative/Sources/MuesliNativeApp/TranscriptFormatter.swift
// Copyright (c) 2026 Pranav Hari. MIT License; see THIRD_PARTY_NOTICES.md.

import Foundation

/// One line of the final transcript.
struct TranscriptLine: Codable, Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var speaker: String
    var text: String
}

/// Turns the per-chunk segments of both sources into labelled, ordered transcript lines:
/// echo filter → "You" / "Speaker N" / "Others" labels → merge of close lines from the same speaker.
enum TranscriptAssembler {
    static let you = "You"
    static let others = "Others"
    private static let mergeGap: TimeInterval = 2
    private static let nearestSpeakerGap: TimeInterval = 2
    private static let echoTimeOverlap = 0.5
    private static let echoWordOverlap = 0.6

    /// `speakerTurns` is nil when speaker separation is off or failed; remote lines are then labelled "Others".
    static func assemble(segments: [TranscriptSegment], speakerTurns: [SpeakerTurn]?) -> [TranscriptLine] {
        let system = segments.filter { $0.source == .system }
        let mic = segments.filter { $0.source == .mic && !isEcho($0, of: system) }

        var lines = mic.map { TranscriptLine(start: $0.start, end: $0.end, speaker: you, text: $0.text) }
        lines += system.map { segment in
            let speaker = speakerTurns.flatMap { speakerID(for: segment, in: $0) }
            return TranscriptLine(start: segment.start, end: segment.end, speaker: speaker ?? others, text: segment.text)
        }
        lines.sort { $0.start < $1.start }
        return merge(numberingSpeakers(lines, turnIDs: Set(speakerTurns?.map(\.speakerID) ?? [])))
    }

    /// Distinct speakers in order of first appearance, as written in the front matter.
    static func speakers(in lines: [TranscriptLine]) -> [String] {
        var seen = Set<String>()
        return lines.map(\.speaker).filter { seen.insert($0).inserted }
    }

    // MARK: - Echo filter

    /// A microphone segment is the speakers' echo when at least half of it overlaps remote speech and most of
    /// its words appear in that remote speech.
    private static func isEcho(_ segment: TranscriptSegment, of system: [TranscriptSegment]) -> Bool {
        guard !segment.isGap else { return false }
        let overlapping = system.filter { !$0.isGap && $0.start < segment.end && $0.end > segment.start }
        let duration = max(segment.end - segment.start, 0.1)
        let overlap = overlapping.reduce(0) { $0 + min($1.end, segment.end) - max($1.start, segment.start) }
        guard overlap / duration >= echoTimeOverlap else { return false }

        let micWords = words(segment.text)
        guard !micWords.isEmpty else { return false }
        let systemWords = Set(overlapping.flatMap { words($0.text) })
        let shared = micWords.filter(systemWords.contains).count
        return Double(shared) / Double(micWords.count) >= echoWordOverlap
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Speakers

    /// The speaker with the largest time overlap, else the nearest one within 2 s.
    private static func speakerID(for segment: TranscriptSegment, in turns: [SpeakerTurn]) -> String? {
        let ids = Set(turns.map(\.speakerID))
        if ids.count == 1 { return ids.first }
        let end = max(segment.end, segment.start + 0.1)
        let best = turns.map { ($0.speakerID, min(end, $0.end) - max(segment.start, $0.start)) }.max { $0.1 < $1.1 }
        if let best, best.1 > 0 { return best.0 }

        let midpoint = (segment.start + end) / 2
        func distance(_ turn: SpeakerTurn) -> TimeInterval { max(turn.start - midpoint, midpoint - turn.end, 0) }
        guard let nearest = turns.min(by: { distance($0) < distance($1) }), distance(nearest) <= nearestSpeakerGap else {
            return nil
        }
        return nearest.speakerID
    }

    /// Replaces raw diarizer ids with "Speaker 1", "Speaker 2"… in order of first appearance in the transcript.
    private static func numberingSpeakers(_ lines: [TranscriptLine], turnIDs: Set<String>) -> [TranscriptLine] {
        var labels: [String: String] = [:]
        return lines.map { line in
            guard turnIDs.contains(line.speaker), line.speaker != you else { return line }
            var labelled = line
            if labels[line.speaker] == nil { labels[line.speaker] = "Speaker \(labels.count + 1)" }
            labelled.speaker = labels[line.speaker]!
            return labelled
        }
    }

    // MARK: - Merge

    private static func merge(_ lines: [TranscriptLine]) -> [TranscriptLine] {
        var merged: [TranscriptLine] = []
        for line in lines {
            if var last = merged.last, last.speaker == line.speaker, line.start - last.end <= mergeGap {
                last.text += " " + line.text
                last.end = max(last.end, line.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(line)
            }
        }
        return merged
    }
}
