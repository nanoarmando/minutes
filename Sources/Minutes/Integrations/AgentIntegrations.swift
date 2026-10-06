import Foundation

/// The read-only "minutes" skill installed into AI agents' user skills folders (design D10). Minutes only touches
/// a `minutes` skill folder whose SKILL.md carries `marker`.
enum AgentIntegrations {
    struct Agent: Identifiable, Sendable {
        let name: String
        /// Relative to the home folder; the agent counts as detected when it exists.
        let detectionFolder: String
        let skillsFolder: String

        var id: String { name }
        var skillFolderURL: URL { home.appendingPathComponent(skillsFolder).appendingPathComponent("minutes", isDirectory: true) }
        var skillFileURL: URL { skillFolderURL.appendingPathComponent("SKILL.md") }
    }

    enum Status: Sendable {
        case notDetected, detected, installed, conflict
    }

    static let agents = [
        Agent(name: "Claude Code", detectionFolder: ".claude", skillsFolder: ".claude/skills"),
        Agent(name: "Codex", detectionFolder: ".codex", skillsFolder: ".agents/skills"),
        Agent(name: "GitHub Copilot", detectionFolder: ".copilot", skillsFolder: ".copilot/skills"),
        Agent(name: "Gemini CLI", detectionFolder: ".gemini", skillsFolder: ".gemini/skills"),
        Agent(name: "OpenCode", detectionFolder: ".config/opencode", skillsFolder: ".config/opencode/skills"),
    ]

    static let marker = "<!-- generated-by: minutes -->"
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static func status(of agent: Agent) -> Status {
        let manager = FileManager.default
        if manager.fileExists(atPath: agent.skillFolderURL.path) {
            return isOwned(agent) ? .installed : .conflict
        }
        return manager.fileExists(atPath: home.appendingPathComponent(agent.detectionFolder).path) ? .detected : .notDetected
    }

    static func install(for agent: Agent, notesFolder: URL) throws {
        guard [.detected, .installed].contains(status(of: agent)) else { return }
        try FileManager.default.createDirectory(at: agent.skillFolderURL, withIntermediateDirectories: true)
        try Data(skill(notesFolder: notesFolder).utf8).write(to: agent.skillFileURL, options: .atomic)
    }

    static func remove(for agent: Agent) throws {
        guard isOwned(agent) else { return }
        try FileManager.default.removeItem(at: agent.skillFolderURL)
    }

    /// Re-renders every installed skill; a file is written only when its content differs.
    static func updateInstalled(notesFolder: URL) {
        let content = skill(notesFolder: notesFolder)
        for agent in agents where isOwned(agent) {
            if (try? String(contentsOf: agent.skillFileURL, encoding: .utf8)) != content {
                try? Data(content.utf8).write(to: agent.skillFileURL, options: .atomic)
            }
        }
    }

    private static func isOwned(_ agent: Agent) -> Bool {
        (try? String(contentsOf: agent.skillFileURL, encoding: .utf8))?.contains(marker) == true
    }

    static func skill(notesFolder: URL) -> String {
        let folder = notesFolder.path
        let dictionary = NotesDictionary.url(in: notesFolder).path
        return """
            ---
            name: minutes
            description: Read the user's meeting notes recorded by the Minutes app (summaries, transcripts, tags, clients). Use when the user asks about past meetings or calls, what was discussed, agreed or decided, what a client or participant said, action items or follow-ups.
            ---
            \(marker)

            # Minutes meeting notes

            The user's meetings are Markdown notes written by the Minutes app.

            - Notes folder: `\(folder)`
            - Dictionary: `\(dictionary)`

            ## Rules

            - Read only. Never create, modify, rename or delete any file or folder in the notes folder, including `.minutes/`.
            - Answer only from what the notes say. When they do not contain the answer, say so.

            ## Finding meetings

            1. Start with the dictionary. Its "Meetings" catalog lists every meeting, newest first, with date, time, title, duration, tags and file name, and its "Clients" table maps client names and aliases to tags. When the dictionary is large, search it (for example with grep for a client, tag, title word or date) instead of reading it whole.
            2. Then search the text of the `.md` notes in the notes folder for names, words and synonyms the catalog does not show, for example `grep -ril "<term>" "\(folder)" --include=*.md`.
            3. Read the matching notes. Each note has YAML front matter, a "Summary" section and a "Transcript" section; the dictionary's "Note format" section explains the keys and the speaker labels.

            ## Answering

            Cite every meeting you use with its title, date and file name, for example: Client kickoff, 2026-10-05 (`2026-10-05 0930 Client kickoff.md`).

            """
    }
}
