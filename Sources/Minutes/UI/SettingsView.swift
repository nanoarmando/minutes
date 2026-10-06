import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Settings: every change applies immediately.
struct SettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        TabView(selection: $environment.settingsTab) {
            GeneralSettings(environment: environment)
                .tabItem { Label("General", systemImage: "gearshape") }.tag(AppEnvironment.SettingsTab.general)
            CalendarSettings(environment: environment)
                .tabItem { Label("Calendar", systemImage: "calendar") }.tag(AppEnvironment.SettingsTab.calendar)
            TranscriptionSettings(environment: environment)
                .tabItem { Label("Transcription", systemImage: "waveform") }.tag(AppEnvironment.SettingsTab.transcription)
            SummariesSettings(environment: environment)
                .tabItem { Label("Summaries", systemImage: "text.badge.star") }.tag(AppEnvironment.SettingsTab.summaries)
            TagsSettings(environment: environment)
                .tabItem { Label("Tags", systemImage: "tag") }.tag(AppEnvironment.SettingsTab.tags)
            IntegrationsSettings(environment: environment)
                .tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }.tag(AppEnvironment.SettingsTab.integrations)
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 560)
    }
}

extension AppEnvironment {
    /// A binding that saves the preference on every change.
    func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { self.preferences[keyPath: keyPath] }, set: { value in self.updatePreferences { $0[keyPath: keyPath] = value } })
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let environment: AppEnvironment
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var permissionStates: [Permission: Permission.State] = [:]
    private static let recordingPermissions: [Permission] = [.microphone, .systemAudio]

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                KeyboardShortcuts.Recorder("Recording shortcut", name: .toggleRecording)
            }
            Section("Notes") {
                LabeledContent("Notes folder") {
                    HStack {
                        Text(environment.preferences.notesFolder.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                if environment.meetingsWaitingForFolder > 0 {
                    Text("\(environment.meetingsWaitingForFolder) meeting(s) are waiting for a writable notes folder.").foregroundStyle(.orange)
                }
                TextField("File name pattern", text: environment.binding(\.fileNamePattern))
                Text("Use {date}, {time} and {title}.").font(.caption).foregroundStyle(.secondary)
                Toggle("Keep audio recording", isOn: environment.binding(\.keepAudio))
                Toggle("Suggest recording when a call is detected", isOn: environment.binding(\.suggestOnCallDetected))
            }
            Section("Permissions") {
                // macOS lists Minutes in a Privacy pane only after Minutes has asked, so "Allow…" asks first.
                ForEach(Self.recordingPermissions, id: \.self) { permission in
                    LabeledContent(permission.name) {
                        HStack {
                            let state = permissionStates[permission]
                            if state == .granted {
                                Text("Allowed").foregroundStyle(.green)
                            }
                            if state == .notDetermined || state == .notGranted {
                                Button("Allow…") {
                                    Task {
                                        _ = await permission.request()
                                        refreshPermissions()
                                    }
                                }
                            }
                            if state == .denied || state == .notGranted {
                                Button("Open System Settings") { permission.openSettings() }
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: refreshPermissions)
    }

    private func refreshPermissions() {
        permissionStates = Dictionary(uniqueKeysWithValues: Self.recordingPermissions.map { ($0, $0.state) })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = environment.preferences.notesFolder
        if panel.runModal() == .OK, let url = panel.url {
            environment.updatePreferences { $0.notesFolder = url }
        }
    }
}

// MARK: - Transcription

private struct TranscriptionSettings: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: environment.binding(\.engine)) {
                    Text("On this Mac (Parakeet v3)").tag(Preferences.Engine.parakeet)
                    Text("OpenAI-compatible API").tag(Preferences.Engine.api)
                }
                LabeledContent("On-device model") {
                    HStack {
                        Text(modelDescription).foregroundStyle(.secondary)
                        switch environment.modelState {
                        case .ready: Button("Delete") { Task { try? await environment.parakeet.deleteModel() } }
                        case .downloading: ProgressView().controlSize(.small)
                        default: Button("Download") { environment.downloadModel() }
                        }
                    }
                }
            }
            if environment.preferences.engine == .api {
                Section {
                    EndpointFields(environment: environment, baseURL: \.transcriptionBaseURL, model: \.transcriptionModel, account: .transcription) {
                        _ = try await OpenAICompatibleSTT(endpoint: $0).transcribe(Self.silentClip())
                    }
                } footer: {
                    Text("Meeting audio is sent to this provider. When a request fails, the chunk is transcribed on this Mac if the model is installed.")
                }
            }
            Section {
                Toggle("Separate speakers", isOn: environment.binding(\.speakerSeparation))
            } footer: {
                Text("Use headphones when you can: with speakers, your microphone also picks up the other participants.")
            }
        }
    }

    private var modelDescription: String {
        switch environment.modelState {
        case .ready: "Installed"
        case .notInstalled: "Not downloaded"
        case .downloading(let fraction): "Downloading \(Int(fraction * 100)) %"
        case .failed(let message): "Download failed: \(message)"
        }
    }

    /// One second of silence, enough to test the transcription endpoint.
    private static func silentClip() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("minutes-test.wav")
        try WavWriter.write([Int16](repeating: 0, count: WavFormat.sampleRate), to: url)
        return url
    }
}

/// Base URL, API key (Keychain) and model of a provider, with "Test connection".
private struct EndpointFields: View {
    let environment: AppEnvironment
    let baseURL: WritableKeyPath<Preferences, String>
    let model: WritableKeyPath<Preferences, String>
    let account: KeychainStore.Account
    let test: (ProviderEndpoint) async throws -> Void
    @State private var apiKey = ""
    @State private var testResult: Result<Void, Error>?
    @State private var isTesting = false

    var body: some View {
        TextField("Base URL", text: environment.binding(baseURL))
        SecureField("API key", text: $apiKey)
            .onChange(of: apiKey) { _, key in environment.keychain.write(key, for: account) }
        TextField("Model", text: environment.binding(model))
        HStack {
            Button("Test connection") {
                isTesting = true
                testResult = nil
                let endpoint = ProviderEndpoint(baseURL: environment.preferences[keyPath: baseURL], apiKey: apiKey, model: environment.preferences[keyPath: model])
                Task {
                    do { try await test(endpoint); testResult = .success(()) } catch { testResult = .failure(error) }
                    isTesting = false
                }
            }
            .disabled(isTesting)
            if isTesting { ProgressView().controlSize(.small) }
            switch testResult {
            case .success: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failure(let error): Text(error.localizedDescription).foregroundStyle(.red).lineLimit(3)
            case nil: EmptyView()
            }
        }
        .onAppear { apiKey = environment.keychain.read(account) ?? "" }
    }
}

// MARK: - Summaries

private struct SummariesSettings: View {
    let environment: AppEnvironment
    @State private var editedTypeID = SummaryTypeStore.generalID

    private static let presets: [(name: String, baseURL: String, model: String)] = [
        ("Ollama", "http://localhost:11434/v1", "llama3.2"),
        ("DeepSeek", "https://api.deepseek.com", "deepseek-flash"),
        ("OpenAI", "https://api.openai.com/v1", "gpt-4.1-mini"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: presetBinding) {
                    ForEach(Self.presets, id: \.name) { Text($0.name).tag($0.name) }
                    Text("Custom").tag("Custom")
                }
                EndpointFields(environment: environment, baseURL: \.summaryBaseURL, model: \.summaryModel, account: .summary) {
                    _ = try await ChatClient(endpoint: $0, timeout: 60, retries: 0).complete(system: "Reply with OK.", user: "OK?", maxTokens: 64)
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Also used for titles and tags. Only transcripts, titles and summary instructions are sent, never audio.")
            }
            Section("Summaries") {
                Toggle("Summarize automatically", isOn: environment.binding(\.autoSummarize))
                Picker("Default summary type", selection: Binding(get: { environment.summaryTypes.defaultType.id }, set: { environment.summaryTypes.setDefault($0) })) {
                    ForEach(environment.summaryTypes.types) { Text($0.name).tag($0.id) }
                }
            }
            Section("Summary types") {
                Picker("Edit", selection: $editedTypeID) {
                    ForEach(environment.summaryTypes.types) { Text($0.name).tag($0.id) }
                }
                if let type = environment.summaryTypes.type(id: editedTypeID) {
                    SummaryTypeEditor(store: environment.summaryTypes, type: type) { editedTypeID = SummaryTypeStore.generalID }
                        .id(type.id)
                }
                Button("Add summary type") {
                    editedTypeID = environment.summaryTypes.addCustom(name: "New type", instructions: "").id
                }
            }
            Section {
                ForEach(environment.glossary.entries) { entry in
                    GlossaryRow(store: environment.glossary, entry: entry)
                }
                Button("Add correction") { environment.glossary.save(GlossaryEntry(from: "", to: "")) }
            } header: {
                Text("Glossary")
            } footer: {
                Text("Names the transcription gets wrong. New meetings are corrected before they are saved, and the corrections are sent with every summary and tagging request. Past transcripts are not changed.")
            }
        }
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { Self.presets.first { $0.baseURL == environment.preferences.summaryBaseURL }?.name ?? "Custom" },
            set: { name in
                guard let preset = Self.presets.first(where: { $0.name == name }) else { return }
                environment.updatePreferences {
                    $0.summaryBaseURL = preset.baseURL
                    $0.summaryModel = preset.model
                }
            }
        )
    }
}

private struct GlossaryRow: View {
    let store: GlossaryStore
    @State var entry: GlossaryEntry

    var body: some View {
        HStack {
            TextField("Heard as", text: $entry.from)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            TextField("Correct spelling", text: $entry.to)
            Button("Delete", systemImage: "trash") { store.delete(entry.id) }.labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .labelsHidden()
        .onChange(of: entry) { store.save(entry) }
    }
}

private struct SummaryTypeEditor: View {
    let store: SummaryTypeStore
    @State var type: SummaryType
    let onDelete: () -> Void

    var body: some View {
        if !type.isBuiltIn {
            TextField("Name", text: $type.name).onChange(of: type.name) { store.save(type) }
        }
        TextEditor(text: $type.instructions)
            .font(.body.monospaced())
            .frame(minHeight: 140)
            .onChange(of: type.instructions) { store.save(type) }
        HStack {
            if type.isBuiltIn {
                Button("Reset to default") {
                    store.resetToDefault(type.id)
                    if let original = store.type(id: type.id) { type = original }
                }
                .disabled(!store.isOverridden(type.id))
            } else {
                Button("Delete type", role: .destructive) {
                    store.delete(type.id)
                    onDelete()
                }
            }
        }
    }
}

// MARK: - Tags

private struct TagsSettings: View {
    let environment: AppEnvironment
    @State private var confirmsRetag = false
    /// Edited as typed and saved parsed, so the field is not rewritten while typing.
    @State private var userEmails = Preferences.load().userEmails.joined(separator: ", ")

    var body: some View {
        Form {
            Section {
                Toggle("Detect clients automatically", isOn: environment.binding(\.detectClients))
                Toggle("Add topic tags automatically", isOn: environment.binding(\.topicTags))
                TextField("Your email addresses", text: $userEmails, prompt: Text("you@company.com, you@other.com"), axis: .vertical)
                    .onChange(of: userEmails) { _, text in
                        let emails = text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                        environment.updatePreferences { $0.userEmails = emails }
                    }
                Text("The addresses you join meetings with. Minutes uses them to tell your organization from your clients.")
                    .font(.caption).foregroundStyle(.secondary)
                if let progress = environment.retagProgress {
                    HStack {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        Text("\(progress.done) of \(progress.total)").monospacedDigit()
                        Button("Stop") { environment.stopRetagging() }
                    }
                } else {
                    Button("Re-tag all meetings…") { confirmsRetag = true }
                        .disabled(environment.noteIndex.notes.isEmpty)
                }
            } footer: {
                Text("After each meeting is saved, the summary provider suggests client tags (for example client/hemisphere-brands) and topic tags, reusing the tags you already have. Re-tagging replaces automatic tags and keeps the tags you added by hand.")
            }
        }
        .confirmationDialog("Re-tag \(environment.noteIndex.notes.count) meetings?", isPresented: $confirmsRetag) {
            Button("Re-tag \(environment.noteIndex.notes.count) meetings") { environment.retagAll() }
        } message: {
            Text("Automatic tags are recomputed with the summary provider, one meeting at a time.")
        }
    }
}
