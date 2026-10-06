import AppKit
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", initial: .init(.r, modifiers: [.command, .shift]))
}

/// Composition root: owns the long-lived services, the current recording and the stopped meetings still shown in
/// the menu, turns session events into
/// observable state, and routes navigation between the menu, the Meetings window and Settings.
@MainActor @Observable
final class AppEnvironment {
    enum Status: Equatable {
        case idle
        case recording(since: Date)
        case startFailed(String)
    }

    /// A meeting whose capture has stopped: processing in the background, or finished and shown in the menu.
    struct StoppedMeeting: Identifiable {
        enum Phase: Equatable {
            case processing(ProcessingStep)
            case finished(FinishResult)
        }

        let session: RecordingSession
        /// The calendar event title, or the start time when there is no event.
        let name: String
        var phase: Phase
        var id: UUID { session.id }
    }

    enum SettingsTab: Hashable { case general, calendar, transcription, summaries, tags, integrations }

    private(set) var preferences = Preferences.load()
    private(set) var status = Status.idle {
        didSet { callDetector?.setRecording(isRecording) }
    }
    /// In stop order. Saved and waiting-for-folder entries are removed when the next recording starts.
    private(set) var stopped: [StoppedMeeting] = []
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
    let glossary = GlossaryStore()
    @ObservationIgnored private var dictionary: NotesDictionary?
    @ObservationIgnored private var callDetector: CallDetector?
    /// Set by a scene view, which is where SwiftUI exposes the window actions.
    @ObservationIgnored var openWindow: ((String) -> Void)?
    @ObservationIgnored var openSettingsWindow: (() -> Void)?
    /// The current recording, also while it is starting or stopping.
    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var currentEvent: EventInfo?
    /// The calendar occurrence the current recording was started for from a notification.
    @ObservationIgnored private var currentOccurrence: String?
    /// Set while the current recording's capture is stopping, so a second caller waits for it.
    @ObservationIgnored private var stopping: Task<RecordingSession, Never>?
    @ObservationIgnored private var retagTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?

    init() {
        noteIndex = NoteIndex(folder: Preferences.load().notesFolder)
        let (modelStates, modelStateSink) = AsyncStream.makeStream(of: ParakeetEngine.ModelState.self)
        parakeet = ParakeetEngine { modelStateSink.yield($0) }
        calendar = CalendarService(preferences: Preferences.load())
        calendar.isRecording = { [weak self] in self?.isRecording ?? false }
        dictionary = NotesDictionary(index: noteIndex, summaryTypes: summaryTypes, glossary: glossary)
        AgentIntegrations.updateInstalled(notesFolder: preferences.notesFolder)
        updates.isAppBusy = { [weak self] in self?.isBusy ?? false }
        updates.start()
        observeWindowsForDock()
        callDetector = CallDetector { [weak self] event in
            Task { @MainActor in self?.suggest(for: event) }
        }
        callDetector?.setEnabled(preferences.suggestOnCallDetected)
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
        isRecording || stopped.contains { if case .processing = $0.phase { true } else { false } }
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
        MeetingProcessor(
            parakeet: parakeet, keychain: keychain, summaryType: summaryTypes.defaultType,
            knownClients: knownClients, glossary: glossary.entries
        )
    }

    private var tagService: TagService {
        TagService(
            existingTags: existingTags, detectClients: preferences.detectClients,
            topicTags: preferences.topicTags, userEmails: preferences.userEmails, glossary: glossary.entries,
            service: summaryService
        )
    }

    private var knownClients: [String] {
        existingTags.filter { $0.hasPrefix("client/") }
    }

    /// The context sent with a saved note's summary and tagging requests.
    func meetingContext(for note: NoteSummary, document: String) -> MeetingContext {
        MeetingContext.forNote(
            note.url, id: note.id, document: document, userEmails: preferences.userEmails,
            knownClients: knownClients, glossary: glossary.entries
        )
    }

    func updatePreferences(_ update: (inout Preferences) -> Void) {
        let previousFolder = preferences.notesFolder
        update(&preferences)
        preferences.save()
        calendar.preferences = preferences
        callDetector?.setEnabled(preferences.suggestOnCallDetected)
        noteIndex.setFolder(preferences.notesFolder)
        if preferences.notesFolder != previousFolder {
            AgentIntegrations.updateInstalled(notesFolder: preferences.notesFolder)
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
    /// The policy becomes regular before activating: an activation while still an accessory app is not recorded in
    /// the app switcher's order, which left Minutes last in ⌘Tab even while its window was in use.
    private func bringToFront(_ identifier: String) {
        Self.setActivationPolicy(.regular)
        NSApp.activate()
        DispatchQueue.main.async {
            NSApp.activate()
            NSApp.windows.first { $0.identifier?.rawValue.contains(identifier) == true }?.makeKeyAndOrderFront(nil)
        }
    }

    /// Minutes is a menu bar app (LSUIElement); while the Meetings, Settings or About window is open it becomes a
    /// regular app so its icon shows in the Dock and the app switcher, and returns to accessory when the last closes.
    /// The policy depends only on whether such a window is open (visible or minimized), never on focus: changing it
    /// when Minutes merely loses focus would move it to the end of the app switcher.
    private func observeWindowsForDock() {
        let center = NotificationCenter.default
        // A window becoming key means one is open: this signal may only promote.
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if Self.isAppWindowOpen { Self.setActivationPolicy(.regular) }
            }
        }
        // Demote only after a window closes, on the next run loop turn, once it is gone.
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                if !Self.isAppWindowOpen { Self.setActivationPolicy(.accessory) }
            }
        }
    }

    private static var isAppWindowOpen: Bool {
        NSApp.windows.contains { window in
            guard window.isVisible || window.isMiniaturized, let identifier = window.identifier?.rawValue else { return false }
            return ["meetings", "about", "Settings"].contains { identifier.contains($0) }
        }
    }

    private static func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    // MARK: - Recording

    /// Start when idle, stop when recording: the menu button and the global shortcut both call this.
    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    /// `event` comes from a start suggestion; otherwise the calendar is looked up once capture has started.
    /// Earlier meetings keep processing; their saved confirmations leave the menu.
    func startRecording(event: EventInfo? = nil, occurrence: String? = nil) {
        guard session == nil else { return }
        let session = RecordingSession(preferences: preferences, processor: processor)
        self.session = session
        currentEvent = event
        currentOccurrence = occurrence
        elapsed = 0
        stopped.removeAll {
            switch $0.phase {
            case .finished(.saved), .finished(.waitingForFolder): true
            default: false
            }
        }
        Task {
            consume(session.events, id: session.id)
            do {
                let startDate = Date()
                try await session.start(event: event)
                if event == nil, let found = calendar.event(at: startDate) {
                    currentEvent = found
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
        Task { await stopCurrent()?.process() }
    }

    /// "Stop & record next": stops the current recording, which is processed in the background, and records
    /// `event` once the previous capture is down. Does nothing when the current recording is already that event.
    func stopAndRecordNext(event: EventInfo, occurrence: String) {
        if isRecording, currentOccurrence == occurrence || (currentOccurrence == nil && currentEvent == event) { return }
        Task {
            if let previous = await stopCurrent() {
                Task { await previous.process() }
            }
            startRecording(event: event, occurrence: occurrence)
        }
    }

    /// Stops capture of the current recording and moves it to `stopped`; returns it for processing. A caller that
    /// arrives during a stop waits for it and gets nil, since the first caller processes the session.
    private func stopCurrent() async -> RecordingSession? {
        if let stopping {
            _ = await stopping.value
            return nil
        }
        guard isRecording, let session, case .recording(let since) = status else { return nil }
        let name = currentEvent?.title ?? since.formatted(date: .omitted, time: .shortened)
        // The cleanup runs inside the task, so waiters resume only after `session` is cleared.
        let task = Task {
            await session.stopCapture()
            stopped.append(StoppedMeeting(session: session, name: name, phase: .processing(.transcribing)))
            self.session = nil
            currentEvent = nil
            currentOccurrence = nil
            status = .idle
            micLevel = 0
            systemLevel = 0
            stopping = nil
            return session
        }
        stopping = task
        return await task.value
    }

    /// Suggests starting when a call is detected and nothing is recorded, and stopping when the call
    /// seems to have ended during a recording. Never starts or stops by itself.
    private func suggest(for event: CallDetector.Event) {
        guard preferences.suggestOnCallDetected else { return }
        switch event {
        case .callStarted(let appName) where !isRecording:
            MeetingNotifications.postCallStarted(appName: appName)
        case .callEnded where isRecording:
            MeetingNotifications.postCallEnded()
        default:
            break
        }
    }

    /// Deletes the current recording. The confirmation dialog is shown by the caller.
    func discardRecording() {
        guard let session else { return }
        Task { await session.discard() }
    }

    /// Retries a stopped meeting whose processing failed (for example after the model download failed).
    func retryProcessing(id: UUID) {
        guard let index = stopped.firstIndex(where: { $0.id == id }), case .finished(.failed) = stopped[index].phase else { return }
        let session = stopped[index].session
        stopped[index].phase = .processing(.transcribing)
        Task {
            _ = try? await parakeet.prepare()
            await session.retry()
        }
    }

    /// Deletes a stopped meeting whose processing failed. The confirmation dialog is shown by the caller.
    func discardStopped(id: UUID) {
        guard let meeting = stopped.first(where: { $0.id == id }) else { return }
        Task { await meeting.session.discard() }
    }

    func downloadModel() {
        Task { _ = try? await parakeet.prepare() }
    }

    /// Called by the Quit handler while recording: stops and saves, or discards, and returns when done. Meetings
    /// already processing in the background are recovered at the next launch.
    func endRecordingForQuit(save: Bool) async {
        if save {
            await stopCurrent()?.process()
        } else {
            await session?.discard()
        }
    }

    /// Levels and elapsed time count only for the current recording; state goes to the recording or its stopped entry.
    private func consume(_ events: AsyncStream<RecordingSession.Event>, id: UUID) {
        Task {
            for await event in events {
                switch event {
                case .levels(let mic, let system) where id == session?.id:
                    micLevel = mic
                    systemLevel = system
                case .elapsed(let seconds) where id == session?.id:
                    elapsed = seconds
                case .state(let state):
                    apply(state, id: id)
                default:
                    break
                }
            }
        }
    }

    private func apply(_ state: RecordingSession.State, id: UUID) {
        if id == session?.id {
            switch state {
            case .recording(let since):
                status = .recording(since: since)
            case .discarded:
                status = .idle
                session = nil
                currentEvent = nil
                currentOccurrence = nil
            case .processing, .finished:
                break  // the stopped entry, created once capture is down, tracks processing
            }
            return
        }
        guard let index = stopped.firstIndex(where: { $0.id == id }) else { return }
        switch state {
        case .processing(let step):
            stopped[index].phase = .processing(step)
        case .finished(let result):
            stopped[index].phase = .finished(result)
            if case .waitingForFolder = result { meetingsWaitingForFolder += 1 }
            if case .saved(let note) = result { didSave(note) }
        case .discarded:
            stopped.remove(at: index)
        case .recording:
            break
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
        let id = store.folder.lastPathComponent
        // A meeting waiting for a folder is finished by its session and left to recovery.
        return id == session?.id.uuidString || stopped.contains {
            if case .finished(.waitingForFolder) = $0.phase { false } else { $0.id.uuidString == id }
        }
    }
}
