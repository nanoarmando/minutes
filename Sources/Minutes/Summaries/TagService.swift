import Foundation

/// Automatic tags (design D11): one model call detects client and topic tags from the transcript, reusing the
/// tags already in the notes folder. Manual tags, recorded in the sidecar, always survive re-tagging.
struct TagService: Sendable {
    static let batchCharacters = 48_000
    private static let maxClients = 2
    private static let maxTopics = 3

    /// Client tags (`client/…`) and topic tags already used in the notes folder, offered for reuse.
    let existingTags: [String]
    let detectClients: Bool
    let topicTags: Bool
    /// Nil when no provider is configured: no automatic tags.
    let service: SummaryService?

    /// Recomputes the automatic tags of a note and writes manual + automatic tags into its front matter.
    /// A failed call (or no provider, or both switches off) leaves the note with its manual tags only.
    func retag(note: URL, id: UUID) async throws {
        let document = try String(contentsOf: note, encoding: .utf8)
        let transcript = NoteFile.transcriptSection(of: document)
        var automatic: [String] = []
        if let service, detectClients || topicTags, !transcript.isEmpty {
            automatic = (try? await modelTags(transcript: transcript, service: service)) ?? []
        }
        let writer = NoteWriter(folder: note.deletingLastPathComponent())
        let manual = writer.readSidecar(id: id)?.manualTags ?? []
        try writer.setTags(of: note, id: id, tags: Self.unique(manual + automatic), manual: manual)
    }

    private func modelTags(transcript: String, service: SummaryService) async throws -> [String] {
        let reply = try await service.client.complete(system: prompt(language: MeetingLanguage(of: transcript)), user: Self.excerpt(transcript), maxTokens: 300)
        struct Reply: Decodable { var clients: [String]?; var topics: [String]? }
        guard let parsed = ChatClient.decodeJSON(Reply.self, from: reply) else { return [] }
        let clients = detectClients
            ? Self.unique((parsed.clients ?? []).map { "client/" + Self.slug($0.replacingOccurrences(of: "client/", with: "")) })
                .filter { $0 != "client/" }.prefix(Self.maxClients)
            : []
        let topics = topicTags
            ? Self.unique((parsed.topics ?? []).map(Self.slug)).filter { !$0.isEmpty && !$0.hasPrefix("client") }.prefix(Self.maxTopics)
            : []
        return Array(clients) + Array(topics)
    }

    private func prompt(language: MeetingLanguage?) -> String {
        let existingClients = existingTags.filter { $0.hasPrefix("client/") }
        let existingTopics = existingTags.filter { !$0.hasPrefix("client/") }
        var lines = [
            "You tag meeting transcripts. Reply with only a JSON object: {\"clients\": [...], \"topics\": [...]}.",
        ]
        if detectClients {
            lines.append("""
                "clients": the external companies or organizations the meeting is with, or discusses as a client of the \
                user (at most \(Self.maxClients)). Do not list the user's own company, tools or vendors mentioned in passing. \
                For an internal meeting, return an empty list. When a client already has a tag below, return that exact \
                tag, even if the transcript uses another name or an abbreviation (for example "Hemisphere" or "HB" → \
                "client/hemisphere-brands"); otherwise return the client's name.
                Existing client tags: \(existingClients.isEmpty ? "none" : existingClients.joined(separator: ", "))
                """)
        } else {
            lines.append("\"clients\" must be an empty list.")
        }
        if topicTags {
            lines.append("""
                "topics": at most \(Self.maxTopics) short topic tags for the main subjects, \(MeetingLanguage.phrase(language)), \
                lowercase and hyphenated (for example "budget", "checkout-redesign"). Reuse an existing topic tag whenever \
                one fits the same topic.
                Existing topic tags: \(existingTopics.isEmpty ? "none" : existingTopics.joined(separator: ", "))
                """)
        } else {
            lines.append("\"topics\" must be an empty list.")
        }
        return lines.joined(separator: "\n")
    }

    /// The whole transcript when it fits the budget, otherwise evenly spaced excerpts covering the meeting.
    private static func excerpt(_ transcript: String) -> String {
        guard transcript.count > batchCharacters else { return transcript }
        let pieces = 8, length = batchCharacters / pieces, step = (transcript.count - length) / (pieces - 1)
        return (0..<pieces).map { index in
            let start = transcript.index(transcript.startIndex, offsetBy: index * step)
            return "[…] " + transcript[start...].prefix(length)
        }.joined(separator: "\n")
    }

    /// Lowercase, accents removed, words joined by hyphens: "Hemisphere Brands" → "hemisphere-brands".
    static func slug(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
    }

    private static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }
    }
}
