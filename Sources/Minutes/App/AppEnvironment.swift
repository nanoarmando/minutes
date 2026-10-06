import AppKit
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", initial: .init(.r, modifiers: [.command, .shift]))
}

/// Composition root: owns the long-lived services and the current recording, turns session events into
/// observable state, and routes navigation between the menu, the Meetings window and Settings.
@MainActor @Observable
final class AppEnvironment {
    enum Status: Equatable {
        case idle
        case recording(since: Date)
        case processing(ProcessingStep)
        case finished(FinishResult)
        case startFailed(String)
    }

    enum SettingsTab: Hashable { case general, calendar, transcription, summaries, tags, integrations }

    private(set) var preferences = Preferences.load()
    private(set) var status = Status.idle
    private(set) var micLevel: Float = 0
    private(set) var systemLevel: Float = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var modelState: ParakeetEngine.ModelState = ParakeetEngine.isInstalled ? .ready : .notInstalled
    /// Meetings that finished while the notes folder was unavailable; saved when a writable folder is chosen.
    private(set) var meetingsWaitingForFolder = 0
    /// Progress of "Re-tag all meetings" (done, total), nil when not running.
    private(set) var retagProgress: (done: Int, total: Int)?

    var selectedMeetingID: UUID?
    var settingsTab = SettingsTab.general

    let keychain = KeychainStore()
    let summaryTypes = SummaryTypeStore()
    let noteIndex: NoteIndex
    let parakeet: ParakeetEngine
    let calendar: CalendarService
    let updates = UpdateCoordinator()
    @ObservationIgnored private var dictionary: NotesDictionary?
    /// Set by a scene view, which is where SwiftUI exposes the window actions.
    @ObservationIgnored var openWindow: ((String) -> Void)?
    @ObservationIgnored var openSettingsWindow: (() -> Void)?
    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var retagTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?

    init() {
        noteIndex = NoteIndex(folder: Preferences.load().notesFolder)
        let (modelStates, modelStateSink) = AsyncStream.makeStream(of: ParakeetEngine.ModelState.self)
        parakeet = ParakeetEngine { modelStateSink.yield($0) }
        calendar = CalendarService(preferences: Preferences.load())
        calendar.isRecording = { [weak self] in self?.isRecording ?? false }
        dictionary = NotesDictionary(index: noteIndex, summaryTypes: summaryTypes)
        AgentIntegrations.updateInstalled(notesFolder: preferences.notesFolder)
        updates.isAppBusy = { [weak self] in self?.isBusy ?? false }
        updates.start()
        observeWindowsForDock()
        Task { [weak self] in
            for await state in modelStates { self?.modelState = state }
        }
        SystemAudioTap.cleanUpStaleDevices()
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in self?.toggleRecording() }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRecording() }
        }
        MeetingNotifications.requestAuthorization()
        Task {
            await finishInterruptedMeetings()
            await tagPendingNotes()
        }
    }

    var isRecording: Bool {
        if case .recording = status { true } else { false }
    }

    var isBusy: Bool {
        switch status {
        case .recording, .processing: true
        default: false
        }
    }

    /// Nil when no summary provider is configured.
    var summaryService: SummaryService? {
        SummaryService(endpoint: preferences.summaryEndpoint(keychain: keychain))
    }

    /// Every tag used in the notes folder, for suggestions and for the model prompts.
    var existingTags: [String] {
        Array(Set(noteIndex.notes.flatMap(\.tags))).sorted()
    }

    private var processor: MeetingProcessor {
        MeetingProcessor(parakeet: parakeet, keychain: keychain, summaryType: summaryTypes.defaultType)
    }

    private var tagService: TagService {
        TagService(
            existingTags: existingTags, detectClients: preferences.detectClients,
            topicTags: preferences.topicTags, userEmails: preferences.userEmails, service: summaryService
        )
    }

    func updatePreferences(_ update: (inout Preferences) -> Void) {
        let previousFolder = preferences.notesFolder
        update(&preferences)
        preferences.save()
        calendar.preferences = preferences
        noteIndex.setFolder(preferences.notesFolder)
        if preferences.notesFolder != previousFolder {
            AgentIntegrations.updateInstalled(notesFolder: preferences.notesFolder)
        updates.isAppBusy = { [weak self] in self?.isBusy ?? false }
        updates.start()
        observeWindowsForDock()
        }
        if meetingsWaitingForFolder > 0 {
            Task { await finishInterruptedMeetings() }
        }
    }

    // MARK: - Navigation

    /// Opens the Meetings window, selecting a meeting when given.
    func showMeetings(selecting id: UUID? = nil) {
        if let id { selectedMeetingID = id }
        openWindow?("meetings")
        bringToFront("meetings")
    }

    func showSettings(_ tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        openSettingsWindow?()
        bringToFront("Settings")
    }

    func showAbout() {
        openWindow?("about")
        bringToFront("about")
    }

    /// Minutes has no Dock icon (LSUIElement), so a window it opens stays behind the active app unless Minutes
    /// activates and orders the window front. SwiftUI creates the window asynchronously, hence the next run loop.
    private func bringToFront(_ identifier: String) {
        NSApp.activate()
        DispatchQueue.main.async {
            NSApp.activate()
            NSApp.windows.first { $0.identifier?.rawValue.contains(identifier) == true }?.makeKeyAndOrderFront(nil)
        }
    }

    /// Minutes is a menu bar app (LSUIElement); while the Meetings, Settings or About window is open it becomes a
    /// regular app so its icon shows in the Dock and the app switcher, and returns to accessory when the last closes.
    private func observeWindowsForDock() {
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            // Evaluated after the event, when a closing window is no longer visible.
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in Self.updateActivationPolicy() }
            }
        }
    }

    private static func updateActivationPolicy() {
        let appWindowOpen = NSApp.windows.contains { window in
            guard window.isVisible, let identifier = window.identifier?.rawValue else { return false }
            return ["meetings", "about", "Settings"].contains { identifier.contains($0) }
        }
        let policy: NSApplication.ActivationPolicy = appWindowOpen ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    // MARK: - Recording

    /// Start when idle, stop when recording: the menu button and the global shortcut both call this.
    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    /// `event` comes from a start suggestion; otherwise the calendar is looked up once capture has started.
    func startRecording(event: EventInfo? = nil) {
        guard !isBusy else { return }
        let session = RecordingSession(preferences: preferences, processor: processor)
        self.session = session
        elapsed = 0
        Task {
            consume(session.events)
            do {
                let startDate = Date()
                try await session.start(event: event)
                if event == nil, let found = calendar.event(at: startDate) {
                    await session.setEvent(found)
                }
                if preferences.engine == .parakeet, !ParakeetEngine.isInstalled {
                    downloadModel()
                }
            } catch {
                status = .startFailed(error.localizedDescription)
                self.session = nil
            }
        }
    }

    func stopRecording() {
        guard isRecording, let session else { return }
        Task { await session.stop() }
    }

    /// Deletes the current recording. The confirmation dialog is shown by the caller.
    func discardRecording() {
        guard let session else { return }
        Task { await session.discard() }
    }

    /// Retries a meeting whose transcription failed (for example after the model download failed).
    func retryProcessing() {
        guard case .finished(.failed) = status, let session else { return }
        Task {
            _ = try? await parakeet.prepare()
            await session.retry()
        }
    }

    func downloadModel() {
        Task { _ = try? await parakeet.prepare() }
    }

    /// Called by the Quit handler while recording: stops and saves, or discards, and returns when done.
    func endRecordingForQuit(save: Bool) async {
        guard let session else { return }
        if save { await session.stop() } else { await session.discard() }
    }

    private func consume(_ events: AsyncStream<RecordingSession.Event>) {
        Task {
            for await event in events {
                switch event {
                case .levels(let mic, let system):
                    micLevel = mic
                    systemLevel = system
                case .elapsed(let seconds):
                    elapsed = seconds
                case .state(let state):
                    apply(state)
                }
            }
        }
    }

    private func apply(_ state: RecordingSession.State) {
        switch state {
        case .recording(let since):
            status = .recording(since: since)
        case .processing(let step):
            status = .processing(step)
            micLevel = 0
            systemLevel = 0
        case .finished(let result):
            status = .finished(result)
            if case .waitingForFolder = result { meetingsWaitingForFolder += 1 }
            if case .failed = result { return }
            session = nil
            if case .saved(let note) = result { didSave(note) }
        case .discarded:
            status = .idle
            session = nil
        }
    }

    /// Announces a saved note and runs model tagging, which never delays saving.
    private func didSave(_ note: SavedNote, tagNow: Bool = true) {
        noteIndex.rescan()
        MeetingNotifications.postSaved(note)
        guard tagNow, summaryService != nil else { return }
        Task { await tag(url: note.url, id: note.id) }
    }

    // MARK: - Tags

    /// Re-tags one meeting; returns the error message when the tagging call failed.
    @discardableResult
    func retag(_ note: NoteSummary) async -> String? {
        await tag(url: note.url, id: note.id)
    }

    /// The one tagging path (after save, at launch, Re-tag, Re-tag all). The sidecar keeps the note pending, with
    /// the error, until an attempt succeeds, so a failure or a quit is retried at the next launch.
    @discardableResult
    private func tag(url: URL, id: UUID) async -> String? {
        let writer = NoteWriter(folder: url.deletingLastPathComponent())
        var failure: String?
        do {
            try await tagService.retag(note: url, id: id)
        } catch {
            failure = error.localizedDescription
        }
        try? writer.setTaggingState(TaggingState(pending: failure != nil, lastError: failure), id: id)
        noteIndex.rescan()
        return failure
    }

    /// Tags, once and one at a time, the notes left pending by a failure or a quit.
    private func tagPendingNotes() async {
        await noteIndex.waitForScan()
        guard summaryService != nil else { return }
        for note in noteIndex.notes {
            let writer = NoteWriter(folder: note.url.deletingLastPathComponent())
            if writer.readSidecar(id: note.id)?.tagging?.pending == true {
                await tag(url: note.url, id: note.id)
            }
        }
    }

    /// Re-tags every meeting one after another; `stopRetagging()` ends it after the current meeting.
    func retagAll() {
        guard retagProgress == nil else { return }
        let notes = noteIndex.notes
        retagProgress = (0, notes.count)
        retagTask = Task {
            for (index, note) in notes.enumerated() {
                guard !Task.isCancelled else { break }
                await tag(url: note.url, id: note.id)
                retagProgress = (index + 1, notes.count)
            }
            retagProgress = nil
            noteIndex.rescan()
        }
    }

    func stopRetagging() {
        retagTask?.cancel()
    }

    /// Adds or removes a tag by hand; added tags are recorded as manual so re-tagging keeps them.
    func setTag(_ tag: String, present: Bool, on note: NoteSummary) throws {
        let writer = NoteWriter(folder: note.url.deletingLastPathComponent())
        var manual = writer.readSidecar(id: note.id)?.manualTags ?? []
        var tags = note.tags
        tags.removeAll { $0 == tag }
        manual.removeAll { $0 == tag }
        if present {
            tags.append(tag)
            manual.append(tag)
        }
        try writer.setTags(of: note.url, id: note.id, tags: tags, manual: manual)
        noteIndex.rescan()
    }

    // MARK: - Recovery

    /// Saves every meeting left in progress by a crash, or waiting for a writable notes folder.
    private func finishInterruptedMeetings() async {
        let processor = processor
        let folder = preferences.notesFolder
        var waiting = 0
        for store in InProgressStore.all() where !isActive(store) {
            let result = await processor.finish(store: store, recovered: store.finishedMeeting() == nil, notesFolder: folder) { _ in }
            switch result {
            case .waitingForFolder: waiting += 1
            case .saved(let note): didSave(note, tagNow: false)  // tagPendingNotes() tags it next
            case .failed: break
            }
        }
        meetingsWaitingForFolder = waiting
        noteIndex.rescan()
    }

    private func isActive(_ store: InProgressStore) -> Bool {
        store.folder.lastPathComponent == session?.id.uuidString
    }
}
