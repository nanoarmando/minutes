import Foundation

/// What Minutes knows about a meeting besides its transcript, sent before the transcript in every summary, title and
/// tagging request (improve-meeting-understanding D1).
struct MeetingContext: Sendable {
    private static let maxAttendees = 20

    var title = ""
    /// "Ryan (drgreenlife.com)" or a bare name.
    var attendees: [String] = []
    var userOrganization: [String] = []
    var clientDomains: [String] = []
    var knownClients: [String] = []
    var glossary: [GlossaryEntry] = []
    var instructions: String?
    /// The summary language the user chose for the meeting ("en", "es"); nil means detect it from the transcript.
    var chosenLanguage: String?

    /// The context of a meeting from its calendar event, else the attendees listed in front matter.
    init(title: String, event: EventInfo?, frontMatterAttendees: [String] = [], userEmails: [String],
         knownClients: [String], glossary: [GlossaryEntry], instructions: String?) {
        self.title = title
        let ownDomains = ClientDomains.ownDomains(ownDomain: event?.ownDomain, userEmails: userEmails)
        let emails: [String]
        if let event {
            emails = event.attendeeEmails
            // Names and addresses are aligned per attendee (a missing address is "").
            attendees = event.attendees.enumerated().map { index, name in
                let domain = index < emails.count && emails.count == event.attendees.count ? ClientDomains.domain(of: emails[index]) : nil
                return domain.map { "\(name) (\($0))" } ?? name
            }
        } else {
            let own = Set(userEmails)
            attendees = frontMatterAttendees.filter { !own.contains($0.lowercased()) }
            emails = attendees.filter { $0.contains("@") }
        }
        attendees = Array(attendees.prefix(Self.maxAttendees))
        userOrganization = ownDomains
        clientDomains = ClientDomains.clientDomains(attendeeEmails: emails, ownDomains: ownDomains)
        self.knownClients = knownClients
        self.glossary = glossary
        self.instructions = instructions?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The context of a saved note: its sidecar event and instructions, else its front matter.
    static func forNote(_ url: URL, id: UUID, document: String, userEmails: [String], knownClients: [String], glossary: [GlossaryEntry]) -> MeetingContext {
        let sidecar = NoteWriter(folder: url.deletingLastPathComponent()).readSidecar(id: id)
        let frontMatter = NoteFile.frontMatter(of: document)
        var context = MeetingContext(
            title: frontMatter?.scalars["title"] ?? sidecar?.event?.title ?? "", event: sidecar?.event,
            frontMatterAttendees: frontMatter?.lists["attendees"] ?? [], userEmails: userEmails,
            knownClients: knownClients, glossary: glossary, instructions: sidecar?.instructions
        )
        context.chosenLanguage = sidecar?.language
        return context
    }

    /// The language the user chose for summaries, titles and topic tags; nil lets the model judge it.
    var language: MeetingLanguage? { chosenLanguage.flatMap(MeetingLanguage.init(code:)) }

    /// The block placed before the transcript; empty lines are left out.
    var block: String {
        var lines: [String] = []
        if !title.isEmpty { lines.append("Meeting title: \(title)") }
        if !attendees.isEmpty { lines.append("Attendees: \(attendees.joined(separator: ", "))") }
        if !clientDomains.isEmpty { lines.append("Client domains: \(clientDomains.joined(separator: ", "))") }
        if !userOrganization.isEmpty { lines.append("User's organization: \(userOrganization.joined(separator: ", "))") }
        if !knownClients.isEmpty { lines.append("Known clients: \(knownClients.joined(separator: ", "))") }
        if !glossary.isEmpty { lines.append("Glossary: \(glossary.map { "\($0.from) → \($0.to)" }.joined(separator: "; "))") }
        if let instructions, !instructions.isEmpty { lines.append("Instructions from the user: \(instructions)") }
        lines.append("Note: the transcript is automatic and can misspell names; write names as they appear above.")
        return lines.joined(separator: "\n")
    }

    /// The user message: context, then the transcript. The preamble is repeated after a long transcript because
    /// models (DeepSeek with reasoning in particular) otherwise drift back to English.
    func message(transcript: String, preamble: String? = nil) -> String {
        [preamble, block, "Transcript:\n" + transcript, preamble].compactMap { $0 }.joined(separator: "\n\n")
    }
}
