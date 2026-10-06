import Foundation
import Observation

/// A name correction: what the transcription heard, and the right spelling.
struct GlossaryEntry: Codable, Sendable, Hashable, Identifiable {
    var id = UUID()
    var from: String
    var to: String

    // Stored as `{from, to}`; the id only identifies rows while editing.
    private enum CodingKeys: String, CodingKey { case from, to }

    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    /// Replaces every entry as a whole word or phrase, case-insensitively; spaces in a phrase match any whitespace.
    static func apply(_ entries: [GlossaryEntry], to text: String) -> String {
        entries.reduce(text) { text, entry in
            let words = entry.from.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty, !entry.to.isEmpty,
                  let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])", options: .caseInsensitive)
            else { return text }
            return regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: NSRegularExpression.escapedTemplate(for: entry.to)
            )
        }
    }
}

/// The glossary, persisted in ~/Library/Application Support/Minutes/glossary.json. Applied to new transcripts before
/// their note is first written, and sent as context; never applied retroactively.
@MainActor @Observable
final class GlossaryStore {
    private(set) var entries: [GlossaryEntry]
    private let fileURL: URL

    init(fileURL: URL = AppPaths.supportFolder.appendingPathComponent("glossary.json")) {
        self.fileURL = fileURL
        entries = (try? JSONDecoder().decode([GlossaryEntry].self, from: Data(contentsOf: fileURL))) ?? []
    }

    func save(_ entry: GlossaryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry } else { entries.append(entry) }
        persist()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Adds corrections; an existing `from` (case-insensitive) gets the new spelling instead of a duplicate.
    func merge(_ corrections: [GlossaryEntry]) {
        for correction in corrections {
            if let index = entries.firstIndex(where: { $0.from.caseInsensitiveCompare(correction.from) == .orderedSame }) {
                entries[index].to = correction.to
            } else {
                entries.append(GlossaryEntry(from: correction.from, to: correction.to))
            }
        }
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries.filter { !$0.from.isEmpty }).write(to: fileURL, options: .atomic)
    }
}
