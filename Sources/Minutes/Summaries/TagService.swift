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
    /// Nil when no provider is configured: no automatic tags.
    let service: SummaryService?

    /// What the tagging call knows about the meeting besides its transcript.
    private struct Context {
        var title: String
        var clientDomains: [String]
        var ownDomains: [String]
    }

    /// Recomputes the automatic tags of a note and writes manual + automatic tags into its front matter.
    /// When the model call fails, client domains are still tagged from the domain itself, the tags are written,
    /// and the error is rethrown so the caller can record it.
    func retag(note: URL, id: UUID) async throws {
        let document = try String(contentsOf: note, encoding: .utf8)
        let transcript = NoteFile.transcriptSection(of: document)
        let writer = NoteWriter(folder: note.deletingLastPathComponent())
        let sidecar = writer.readSidecar(id: id)
        let context = context(document: document, event: sidecar?.event)

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

    /// The sidecar's calendar event when there is one, else the front matter title and the attendees that are
    /// email addresses, with the domains of "Your email addresses" as the user's organization.
    private func context(document: String, event: EventInfo?) -> Context {
        let frontMatter = NoteFile.frontMatter(of: document)
        let title = frontMatter?.scalars["title"] ?? event?.title ?? ""
        let emails = event?.attendeeEmails ?? (frontMatter?.lists["attendees"] ?? []).filter { $0.contains("@") && !userEmails.contains($0.lowercased()) }
        let own = ClientDomains.ownDomains(ownDomain: event?.ownDomain, userEmails: userEmails)
        return Context(title: title, clientDomains: ClientDomains.clientDomains(attendeeEmails: emails, ownDomains: own), ownDomains: own)
    }

    private func modelTags(transcript: String, context: Context, service: SummaryService) async throws -> (clients: [String], topics: [String]) {
        let header = [
            context.title.isEmpty ? nil : "Meeting title: \(context.title)",
            context.clientDomains.isEmpty ? nil : "Client domains: \(context.clientDomains.joined(separator: ", "))",
            context.ownDomains.isEmpty ? nil : "User's organization: \(context.ownDomains.joined(separator: ", "))",
        ].compactMap { $0 }.joined(separator: "\n")
        let user = (header.isEmpty ? "" : header + "\n\nTranscript:\n") + Self.excerpt(transcript)
        let reply = try await service.client.complete(system: prompt(language: MeetingLanguage(of: transcript), context: context), user: user, maxTokens: 300)
        struct Reply: Decodable { var clients: [String]?; var topics: [String]? }
        guard let parsed = ChatClient.decodeJSON(Reply.self, from: reply) else { return ([], []) }
        let clients = detectClients
            ? Self.unique((parsed.clients ?? []).map { Self.slug($0.replacingOccurrences(of: "client/", with: "")) })
                .filter { !$0.isEmpty && !ClientDomains.isOwn($0, ownDomains: context.ownDomains) }
                .prefix(ClientDomains.maxClients).map { "client/" + $0 }
            : []
        let topics = topicTags
            ? Self.unique((parsed.topics ?? []).map(Self.slug)).filter { !$0.isEmpty && !$0.hasPrefix("client") }.prefix(Self.maxTopics)
            : []
        return (Array(clients), Array(topics))
    }

    private func prompt(language: MeetingLanguage?, context: Context) -> String {
        let existingClients = existingTags.filter { $0.hasPrefix("client/") }
        let existingTopics = existingTags.filter { !$0.hasPrefix("client/") }
        var lines = [
            "You tag meeting transcripts. Reply with only a JSON object: {\"clients\": [...], \"topics\": [...]}.",
            "The message starts with what is known about the meeting (title, client domains, the user's organization), then the transcript.",
        ]
        if detectClients {
            let rule = context.clientDomains.isEmpty
                ? """
                    There are no client domains: identify the external companies or organizations the meeting is with, \
                    or discusses as a client of the user, from the meeting title and the transcript (at most \(ClientDomains.maxClients)). \
                    Do not list tools or vendors mentioned in passing. For an internal meeting, return an empty list.
                    """
                : """
                    Return exactly one client per client domain listed, in the same order, named from the domain and \
                    the conversation (for example "drgreenlife.com" → "DrGreenlife").
                    """
            lines.append("""
                "clients": \(rule) Never return the user's organization. When a client already has a tag below, return \
                that exact tag, even if the meeting uses another name or an abbreviation (for example "Hemisphere" or "HB" → \
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
