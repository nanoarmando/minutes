import Foundation

/// Automatic tags (design D11, tag-clients-from-meeting-context): client tags from the attendees' email domains,
/// named by the model, and topic tags, in one call that reuses the tags already in the notes folder. Manual tags,
/// recorded in the sidecar, always survive re-tagging.
struct TagService: Sendable {
    static let batchCharacters = 48_000
    private static let maxTopics = 3

    /// Client tags (`client/…`) and topic tags already used in the notes folder, offered for reuse.
    let existingTags: [String]
    let detectClients: Bool
    let topicTags: Bool
    /// "Your email addresses", lowercased.
    let userEmails: [String]
    let glossary: [GlossaryEntry]
    /// Nil when no provider is configured: no automatic tags.
    let service: SummaryService?

    /// Recomputes the automatic tags of a note and writes manual + automatic tags into its front matter.
    /// When the model call fails, client domains are still tagged from the domain itself, the tags are written,
    /// and the error is rethrown so the caller can record it.
    func retag(note: URL, id: UUID) async throws {
        let document = try String(contentsOf: note, encoding: .utf8)
        let transcript = NoteFile.transcriptSection(of: document)
        let writer = NoteWriter(folder: note.deletingLastPathComponent())
        let sidecar = writer.readSidecar(id: id)
        let context = MeetingContext.forNote(
            note, id: id, document: document, userEmails: userEmails,
            knownClients: existingTags.filter { $0.hasPrefix("client/") }, glossary: glossary
        )

        var clients: [String] = []
        var topics: [String] = []
        var failure: Error?
        if let service, detectClients || topicTags, !transcript.isEmpty {
            do {
                (clients, topics) = try await modelTags(transcript: transcript, context: context, service: service)
            } catch {
                failure = error
            }
        }
        if service != nil, detectClients, clients.isEmpty {
            clients = context.clientDomains.map(ClientDomains.fallbackTag)
        }
        let manual = sidecar?.manualTags ?? []
        try writer.setTags(of: note, id: id, tags: Self.unique(manual + clients + topics), manual: manual)
        if let failure { throw failure }
    }

    private func modelTags(transcript: String, context: MeetingContext, service: SummaryService) async throws -> (clients: [String], topics: [String]) {
        let reply = try await service.client.complete(
            system: prompt(language: context.language, context: context),
            user: context.message(transcript: Self.excerpt(transcript)), maxTokens: 300
        )
        struct Reply: Decodable { var clients: [String]?; var topics: [String]? }
        guard let parsed = ChatClient.decodeJSON(Reply.self, from: reply) else { return ([], []) }
        let named = Self.unique((parsed.clients ?? []).map { Self.slug($0.replacingOccurrences(of: "client/", with: "")) })
            .filter { !$0.isEmpty && !ClientDomains.isOwn($0, ownDomains: context.userOrganization) }
        let clients = detectClients ? Self.guarded(named, context: context).prefix(ClientDomains.maxClients).map { "client/" + $0 } : []
        let topics = topicTags
            ? Self.unique((parsed.topics ?? []).map(Self.slug)).filter { !$0.isEmpty && !$0.hasPrefix("client") }.prefix(Self.maxTopics)
            : []
        return (Array(clients), Array(topics))
    }

    /// With client domains, the model's name for each domain (in order) must relate to the domain or the title;
    /// otherwise, such as a misheard name reused from an old tag, the domain-derived name is used.
    private static func guarded(_ named: [String], context: MeetingContext) -> [String] {
        guard !context.clientDomains.isEmpty else { return named }
        let titleWords = slug(context.title).split(separator: "-").map(String.init).filter { $0.count >= 3 }
        return context.clientDomains.enumerated().map { index, domain in
            let label = slug(String(domain.split(separator: ".").first ?? "")).replacingOccurrences(of: "-", with: "")
            let fallback = String(ClientDomains.fallbackTag(for: domain).dropFirst("client/".count))
            guard index < named.count else { return fallback }
            let candidate = named[index]
            let tokens = [candidate.replacingOccurrences(of: "-", with: "")] + candidate.split(separator: "-").map(String.init).filter { $0.count >= 3 }
            let evidence = [label] + titleWords
            let related = tokens.contains { token in evidence.contains { $0.contains(token) || token.contains($0) } }
            return related ? candidate : fallback
        }
    }

    private func prompt(language: MeetingLanguage?, context: MeetingContext) -> String {
        let existingClients = existingTags.filter { $0.hasPrefix("client/") }
        let existingTopics = existingTags.filter { !$0.hasPrefix("client/") }
        var lines = [
            "You tag meeting transcripts. Reply with only a JSON object: {\"clients\": [...], \"topics\": [...]}.",
            "The message starts with what is known about the meeting (title, attendees, client domains, the user's organization, known clients, glossary, instructions), then the transcript.",
        ]
        if detectClients {
            let rule = context.clientDomains.isEmpty
                ? """
                    There are no client domains: identify the external companies or organizations the meeting is with, \
                    or discusses as a client of the user, from the meeting title and the transcript (at most \(ClientDomains.maxClients)). \
                    Do not list tools or vendors mentioned in passing. For an internal meeting, return an empty list.
                    """
                : """
                    Return exactly one client per client domain listed, in the same order. Name each one by comparing \
                    the domain with the meeting title: the title's spelling wins over the domain's (for example \
                    "DrGreenlife - Followup" and "drgreenlife.com" → "DrGreenlife"). The title and the domains take \
                    precedence over the transcript, which is automatic and can misspell names.
                    """
            lines.append("""
                "clients": \(rule) Never return the user's organization. Reuse an existing client tag below only when it \
                names the same company as the title or the domain (for example "HB" or "Hemisphere" for \
                "client/hemisphere-brands"); a tag spelled differently from that evidence must not replace it. Use the \
                glossary and the known clients to correct misheard names. Otherwise return the client's name.
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

extension TagService {
    /// Lowercase without accents, for loose text comparisons.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
