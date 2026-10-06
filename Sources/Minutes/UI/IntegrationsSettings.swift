import SwiftUI

/// Settings › Integrations: the read-only Minutes skill for each supported AI agent.
struct IntegrationsSettings: View {
    let environment: AppEnvironment
    @State private var statuses: [String: AgentIntegrations.Status] = [:]
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("An agent that uses the Minutes skill reads your meeting notes and may send their content to that agent's AI provider. The skill only allows reading: it tells the agent never to create, change or delete notes.")
                    .foregroundStyle(.secondary)
            }
            Section("Agents") {
                ForEach(AgentIntegrations.agents) { agent in row(agent) }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .onAppear(perform: refresh)
    }

    private func row(_ agent: AgentIntegrations.Agent) -> some View {
        let status = statuses[agent.id] ?? .notDetected
        return LabeledContent {
            HStack {
                if status == .detected {
                    Button("Install") { perform { try AgentIntegrations.install(for: agent, notesFolder: environment.preferences.notesFolder) } }
                }
                if status == .installed {
                    Button("Remove") {
                        if confirm("Remove the Minutes skill from \(agent.name)?", "Your notes are not affected.", action: "Remove") {
                            perform { try AgentIntegrations.remove(for: agent) }
                        }
                    }
                }
                if status == .installed || status == .conflict {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([agent.skillFolderURL]) }
                }
            }
        } label: {
            Text(agent.name)
            Text(description(status)).foregroundStyle(status == .conflict ? .orange : .secondary)
            Text("~/" + agent.skillsFolder + "/minutes").font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func description(_ status: AgentIntegrations.Status) -> String {
        switch status {
        case .notDetected: "Not detected"
        case .detected: "Detected"
        case .installed: "Installed"
        case .conflict: "A different “minutes” skill already exists; Minutes leaves it untouched."
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
        refresh()
    }

    private func refresh() {
        statuses = Dictionary(uniqueKeysWithValues: AgentIntegrations.agents.map { ($0.id, AgentIntegrations.status(of: $0)) })
    }
}
