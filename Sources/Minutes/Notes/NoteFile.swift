import Foundation

/// The Markdown note format: YAML front matter, a summary section between markers and the transcript.
///
///     ---
///     minutes_id: 7F3C…
///     title: "Client kickoff"
///     …
///     ---
///     # Client kickoff
///
///     ## Summary
///     <!-- minutes:summary:start -->
///     …
///     <!-- minutes:summary:end -->
///
///     ## Transcript
///     **[00:00:42] Speaker 1:** …
enum NoteFile {
    static let summaryStart = "<!-- minutes:summary:start -->"
    static let summaryEnd = "<!-- minutes:summary:end -->"
    private static let summaryHeading = "## Summary"
    private static let transcriptHeading = "## Transcript"

    /// Parsed front matter. Scalars keep their unquoted text; lists come from flow (`[a, b]`) or block form.
    struct FrontMatter: Sendable {
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
    }

    static func render(_ meeting: Meeting, audioPath: String?) -> String {
        var fields: [(String, String)] = [
            ("minutes_id", meeting.id.uuidString),
            ("title", quoted(meeting.title)),
            ("date", iso8601(meeting.date)),
            ("duration", String(Int(meeting.duration.rounded()))),
            ("speakers", flowList(meeting.speakers)),
            ("tags", tagsValue(meeting.tags)),
            ("summary_type", meeting.summary.typeID ?? ""),
            ("transcription", meeting.transcription),
            ("summary_model", meeting.summary.model ?? ""),
            ("recovered", String(meeting.recovered)),
        ]
        if let audioPath { fields.append(("audio", audioPath)) }
        if let event = meeting.event {
            if !event.calendar.isEmpty { fields.append(("calendar", quoted(event.calendar))) }
            if !event.attendees.isEmpty { fields.append(("attendees", flowList(event.attendees))) }
            if let link = event.meetingLink, !link.isEmpty { fields.append(("meeting_link", link)) }
        }
        let frontMatter = fields.map { $1.hasPrefix("\n") ? "\($0):\($1)" : "\($0): \($1)" }.joined(separator: "\n")
        let transcript = meeting.lines.map { "**[\(Timecode.string($0.start))] \($0.speaker):** \($0.text)" }
        return """
            ---
            \(frontMatter)
            ---
            # \(meeting.title)

            \(summaryHeading)
            \(summaryStart)
            \(meeting.summary.sectionBody)
            \(summaryEnd)

            \(transcriptHeading)
            \(transcript.joined(separator: "\n\n"))

            """
    }

    /// Replaces only the summary section. Falls back to the "## Summary" heading when the markers were removed.
    static func replacingSummary(in document: String, with body: String) -> String {
        let block = "\(summaryStart)\n\(body)\n\(summaryEnd)"
        if let start = document.range(of: summaryStart),
           let end = document.range(of: summaryEnd, range: start.upperBound..<document.endIndex) {
            return document.replacingCharacters(in: start.lowerBound..<end.upperBound, with: block)
        }
        guard let heading = document.range(of: "\n\(summaryHeading)\n") else {
            return document + "\n\(summaryHeading)\n\(block)\n"
        }
        let sectionEnd = document.range(of: "\n## ", range: heading.upperBound..<document.endIndex)?.lowerBound ?? document.endIndex
        return document.replacingCharacters(in: heading.upperBound..<sectionEnd, with: block + "\n")
    }

    /// Sets scalar front matter keys, replacing existing lines or adding them before the closing delimiter.
    static func settingFrontMatter(_ values: [(String, String)], in document: String) -> String {
        var lines = document.components(separatedBy: "\n")
        guard lines.first == "---", let closing = lines.dropFirst().firstIndex(of: "---") else { return document }
        var insertAt = closing
        for (key, value) in values {
            let line = "\(key): \(value)"
            if let index = lines[1..<insertAt].firstIndex(where: { $0.hasPrefix("\(key):") }) {
                lines[index] = line
            } else {
                lines.insert(line, at: insertAt)
                insertAt += 1
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Replaces the `title` front matter value and the body's first `# ` heading; no heading is added when missing.
    static func settingTitle(_ title: String, in document: String) -> String {
        var lines = settingFrontMatter([("title", quoted(title))], in: document).components(separatedBy: "\n")
        let bodyStart = lines.first == "---" ? (lines.dropFirst().firstIndex(of: "---") ?? 0) + 1 : 0
        if let heading = lines[bodyStart...].firstIndex(where: { $0.hasPrefix("# ") }) {
            lines[heading] = "# " + title
        }
        return lines.joined(separator: "\n")
    }

    /// Replaces the `tags` list (Obsidian block form) in the front matter.
    static func settingTags(_ tags: [String], in document: String) -> String {
        var lines = document.components(separatedBy: "\n")
        guard lines.first == "---", var closing = lines.dropFirst().firstIndex(of: "---") else { return document }
        if let start = lines[1..<closing].firstIndex(where: { $0.hasPrefix("tags:") }) {
            var end = start + 1
            while end < closing, lines[end].hasPrefix(" ") || lines[end].hasPrefix("-") { end += 1 }
            lines.removeSubrange(start..<end)
            closing -= end - start
        }
        lines.insert("tags:" + (tags.isEmpty ? " []" : tagsValue(tags)), at: closing)
        return lines.joined(separator: "\n")
    }

    private static func tagsValue(_ tags: [String]) -> String {
        tags.isEmpty ? "[]" : "\n" + tags.map { "  - \(quoted($0))" }.joined(separator: "\n")
    }

    static func frontMatter(of text: String) -> FrontMatter? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var result = FrontMatter()
        var currentListKey: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { return result }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let key = currentListKey, trimmed.hasPrefix("- ") {
                result.lists[key, default: []].append(unquoted(String(trimmed.dropFirst(2))))
                continue
            }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            currentListKey = value.isEmpty ? key : nil
            if value.hasPrefix("[") && value.hasSuffix("]") {
                result.lists[key] = value.dropFirst().dropLast().split(separator: ",")
                    .map { unquoted($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
            } else if !value.isEmpty {
                result.scalars[key] = unquoted(value)
            }
        }
        return nil
    }

    /// The text after "## Transcript", used to summarize again from the Markdown (it keeps user corrections).
    static func transcriptSection(of document: String) -> String {
        guard let heading = document.range(of: "\n\(transcriptHeading)\n") else { return "" }
        return document[heading.upperBound...].replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text between the summary markers.
    static func summarySection(of document: String) -> String {
        guard let start = document.range(of: summaryStart),
              let end = document.range(of: summaryEnd, range: start.upperBound..<document.endIndex) else { return "" }
        return document[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Formatting

    static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// A local calendar day written as "yyyy-MM-dd".
    static func parseDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    static func parseISO8601(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    /// JSON string escaping is valid YAML; slashes stay unescaped so tags read `client/acme`, not `client\/acme`.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()

    private static func quoted(_ text: String) -> String {
        String(decoding: (try? encoder.encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
    }

    private static func flowList(_ items: [String]) -> String {
        "[" + items.map(quoted).joined(separator: ", ") + "]"
    }

    private static func unquoted(_ text: String) -> String {
        if text.hasPrefix("\""), let decoded = try? JSONDecoder().decode(String.self, from: Data(text.utf8)) { return decoded }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") { return String(text.dropFirst().dropLast()) }
        return text
    }
}
