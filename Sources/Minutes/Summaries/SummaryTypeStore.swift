import Foundation
import Observation

/// A kind of summary: its instructions are appended to the base summary prompt.
struct SummaryType: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var instructions: String
    var isBuiltIn = false
}

/// Built-in and custom summary types, persisted in ~/Library/Application Support/Minutes/summary-types.json.
/// Built-ins ship in code; editing one stores an override, so "Reset to default" just deletes the override.
@MainActor @Observable
final class SummaryTypeStore {
    nonisolated static let generalID = "general"

    private struct Stored: Codable {
        var overrides: [String: SummaryType] = [:]
        var custom: [SummaryType] = []
        var defaultTypeID = SummaryTypeStore.generalID
    }

    private var stored: Stored
    private let fileURL: URL

    init(fileURL: URL = AppPaths.supportFolder.appendingPathComponent("summary-types.json")) {
        self.fileURL = fileURL
        stored = (try? JSONDecoder().decode(Stored.self, from: Data(contentsOf: fileURL))) ?? Stored()
    }

    var types: [SummaryType] {
        Self.builtIns.map { stored.overrides[$0.id] ?? $0 } + stored.custom
    }

    var defaultType: SummaryType {
        type(id: stored.defaultTypeID) ?? types[0]
    }

    func type(id: String) -> SummaryType? {
        types.first { $0.id == id }
    }

    func isOverridden(_ id: String) -> Bool {
        stored.overrides[id] != nil
    }

    func save(_ type: SummaryType) {
        if type.isBuiltIn {
            stored.overrides[type.id] = type
        } else if let index = stored.custom.firstIndex(where: { $0.id == type.id }) {
            stored.custom[index] = type
        } else {
            stored.custom.append(type)
        }
        persist()
    }

    func addCustom(name: String, instructions: String) -> SummaryType {
        let type = SummaryType(id: UUID().uuidString.lowercased(), name: name, instructions: instructions)
        save(type)
        return type
    }

    func delete(_ id: String) {
        stored.custom.removeAll { $0.id == id }
        if stored.defaultTypeID == id { stored.defaultTypeID = Self.generalID }
        persist()
    }

    func resetToDefault(_ id: String) {
        stored.overrides[id] = nil
        persist()
    }

    func setDefault(_ id: String) {
        stored.defaultTypeID = id
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
    }

    static let builtIns: [SummaryType] = [
        SummaryType(id: generalID, name: "General", instructions: """
            Write these sections:
            ## Context
            One to three sentences: who met, about what, and the outcome.
            ## Key points
            The main topics with the concrete facts, figures, estimates and dates stated, as bullets, saying who said what.
            ## Decisions
            Each decision with its reason, as bullets.
            ## Action items
            "- [ ] Owner: task (due)" for each commitment; leave out the owner or due date only when nobody stated them.
            ## Risks and open questions
            Risks, blockers and unanswered questions, as bullets.
            """, isBuiltIn: true),
        SummaryType(id: "client-call", name: "Client call", instructions: """
            The meeting is a call with a client. Write these sections:
            ## Context
            Who the client is and the purpose of the call.
            ## Client needs and concerns
            Requirements, problems, objections and priorities the client expressed, as bullets.
            ## Agreements
            Scope, prices, dates or other commitments agreed by either side, as bullets.
            ## Open questions
            Questions that remain unanswered, as bullets.
            ## Next steps
            Follow-ups as "- [ ] Owner: task (due date)" when known.
            """, isBuiltIn: true),
        SummaryType(id: "standup", name: "Standup", instructions: """
            The meeting is a team standup. Group the content by person. For each person write:
            ### <Name>
            - Done: what they finished
            - Next: what they will do
            - Blockers: anything blocking them
            Finish with "## Follow-ups" listing anything that needs action after the standup.
            """, isBuiltIn: true),
        SummaryType(id: "one-on-one", name: "1:1", instructions: """
            The meeting is a one-on-one conversation. Write these sections:
            ## Topics
            What was discussed, as bullets.
            ## Feedback
            Feedback given in either direction.
            ## Goals and growth
            Goals, career or development points mentioned.
            ## Action items
            Commitments as "- [ ] Owner: task" for each person.
            """, isBuiltIn: true),
    ]
}
