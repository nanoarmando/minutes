import Foundation

/// One meeting from start to saved note.
///
/// Threading: the capture objects deliver samples on their own queues straight into `AsyncStream`s; one task
/// per source cuts chunks, one worker transcribes them, and the main actor only receives coarse `Event`s
/// (state changes, levels at 10 Hz, elapsed time once per second).
actor RecordingSession {
    enum State: Sendable, Equatable {
        case recording(since: Date)
        case processing(ProcessingStep)
        case finished(FinishResult)
        case discarded
    }

    enum Event: Sendable {
        case state(State)
        case levels(mic: Float, system: Float)
        case elapsed(TimeInterval)
    }

    enum StartError: LocalizedError {
        case permissionMissing(Permission)

        var errorDescription: String? {
            switch self {
            case .permissionMissing(let permission):
                "Minutes needs the \(permission.name) permission to record. Allow it in System Settings and try again."
            }
        }
    }

    nonisolated let id = UUID()
    nonisolated let events: AsyncStream<Event>
    private let eventSink: AsyncStream<Event>.Continuation
    private let preferences: Preferences
    private let processor: MeetingProcessor
    private let levels = LevelMeter()

    private var store: InProgressStore?
    private var systemTap: SystemAudioTap?
    private var mic: MicRecorder?
    private var sampleSinks: [AsyncStream<SampleBuffer>.Continuation] = []
    private var chunkSink: AsyncStream<AudioChunk>.Continuation?
    private var captureTasks: [Task<Void, Never>] = []
    private var transcriptionWorker: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var isCapturing = false

    init(preferences: Preferences, processor: MeetingProcessor) {
        self.preferences = preferences
        self.processor = processor
        (events, eventSink) = AsyncStream.makeStream(of: Event.self)
    }

    /// `event` is the calendar event the recording belongs to when it is already known (started from a
    /// suggestion); otherwise the caller may add one later with `setEvent(_:)`.
    func start(event: EventInfo? = nil) async throws {
        guard !isCapturing, store == nil else { return }
        for permission in [Permission.microphone, .systemAudio] where !permission.isGranted {
            guard await permission.request() else { throw StartError.permissionMissing(permission) }
        }

        let startDate = Date()
        let store = try InProgressStore.create(SessionInfo(id: id, startDate: startDate, event: event, preferences: preferences))
        self.store = store
        let clockStart = ContinuousClock.now
        let (chunks, chunkSink) = AsyncStream.makeStream(of: AudioChunk.self)
        self.chunkSink = chunkSink

        let (systemSamples, systemSink) = AsyncStream.makeStream(of: SampleBuffer.self)
        let (micSamples, micSink) = AsyncStream.makeStream(of: SampleBuffer.self)
        sampleSinks = [systemSink, micSink]
        let levels = levels
        captureTasks = [
            Task { await ChunkRecorder.record(source: .system, samples: systemSamples, startedAt: clockStart, chunkFolder: store.chunkFolder, fullTrack: store.systemTrack, levels: levels, chunks: chunkSink) },
            Task { await ChunkRecorder.record(source: .mic, samples: micSamples, startedAt: clockStart, chunkFolder: store.chunkFolder, fullTrack: preferences.keepAudio ? store.micTrack : nil, levels: levels, chunks: chunkSink) },
        ]

        do {
            let systemTap = SystemAudioTap { systemSink.yield(SampleBuffer(samples: $0)) }
            try systemTap.start()
            self.systemTap = systemTap
            // A microphone that fails mid-meeting (no input left) ends that track; the rest keeps recording.
            let mic = MicRecorder(onSamples: { micSink.yield(SampleBuffer(samples: $0)) }, onFailure: { _ in micSink.finish() })
            try mic.start()
            self.mic = mic
        } catch {
            await stopCapture()
            store.delete()
            self.store = nil
            throw error
        }
        isCapturing = true

        let processor = processor
        let preferences = preferences
        transcriptionWorker = Task {
            for await chunk in chunks {
                // On failure (model still downloading or unavailable) the chunk stays on disk for the finish step.
                try? await processor.transcribe(chunk, store: store, preferences: preferences)
            }
        }
        startTicker(clockStart: clockStart)
        eventSink.yield(.state(.recording(since: startDate)))

    }

    /// Stops capture, finishes the transcript and saves the note. Returns when the note is saved or kept.
    func stop() async {
        guard isCapturing, let store else { return }
        eventSink.yield(.state(.processing(.transcribing)))
        await stopCapture()
        await transcriptionWorker?.value
        await finish(store)
    }

    /// Finishes again after a failure (for example once the on-device model download succeeds).
    func retry() async {
        guard !isCapturing, let store else { return }
        await finish(store)
    }

    /// Stops capture and deletes all audio and partial transcript without creating a note.
    func discard() async {
        await stopCapture()
        transcriptionWorker?.cancel()
        await transcriptionWorker?.value
        store?.delete()
        store = nil
        eventSink.yield(.state(.discarded))
        eventSink.finish()
    }

    private func finish(_ store: InProgressStore) async {
        let eventSink = eventSink
        let result = await processor.finish(store: store, recovered: false, notesFolder: Preferences.load().notesFolder) { step in
            eventSink.yield(.state(.processing(step)))
        }
        eventSink.yield(.state(.finished(result)))
        if case .failed = result { return }
        self.store = nil
        eventSink.finish()
    }

    private func stopCapture() async {
        isCapturing = false
        ticker?.cancel()
        systemTap?.stop()
        mic?.stop()
        systemTap = nil
        mic = nil
        sampleSinks.forEach { $0.finish() }
        for task in captureTasks { await task.value }
        captureTasks = []
        chunkSink?.finish()
    }

    private func startTicker(clockStart: ContinuousClock.Instant) {
        let levels = levels
        let eventSink = eventSink
        ticker = Task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                eventSink.yield(.levels(mic: levels.level(.mic), system: levels.level(.system)))
                tick += 1
                if tick % 10 == 0 { eventSink.yield(.elapsed((ContinuousClock.now - clockStart) / .seconds(1))) }
            }
        }
    }

    /// Records the calendar event found after capture started, so a recovered meeting keeps it too.
    func setEvent(_ event: EventInfo) {
        guard let store, var info = store.info() else { return }
        info.event = event
        try? store.saveInfo(info)
    }
}
