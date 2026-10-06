import Foundation

enum ProcessingStep: String, Sendable {
    case transcribing = "Finishing transcript"
    case separatingSpeakers = "Separating speakers"
    case summarizing = "Summarizing"
    case saving = "Saving"
}

struct SavedNote: Sendable, Equatable {
    let url: URL
    let id: UUID
    let title: String
    let systemAudioSilent: Bool
    let summaryFailed: Bool
}

/// How finishing a meeting ended.
enum FinishResult: Sendable, Equatable {
    case saved(SavedNote)
    /// The meeting is complete but kept in its in-progress folder until a writable notes folder is chosen.
    case waitingForFolder(String)
    /// Transcription could not finish (on-device model unavailable); the audio is kept for a retry.
    case failed(String)
}

/// Transcribes chunks and turns an in-progress folder into a saved note. Used by a live session after stop, by
/// "Retry", and by crash recovery at launch, so the three paths behave the same.
struct MeetingProcessor: Sendable {
    let parakeet: ParakeetEngine
    let keychain: KeychainStore
    let summaryType: SummaryType

    private static let signalThreshold: Int16 = 64

    // MARK: - Transcription

    /// Transcribes one chunk, appends its segment and deletes the chunk WAV. Throws only when the on-device
    /// model is unavailable, leaving the chunk on disk for a later attempt.
    func transcribe(_ chunk: AudioChunk, store: InProgressStore, preferences: Preferences) async throws {
        let text: String
        if preferences.engine == .api {
            let api = OpenAICompatibleSTT(endpoint: preferences.transcriptionEndpoint(keychain: keychain))
            if let hosted = try? await api.transcribe(chunk.url) {
                text = hosted
            } else if ParakeetEngine.isInstalled, let local = try? await parakeet.transcribe(chunk.url) {
                text = local
            } else {
                try store.appendSegment(.gap(for: chunk))
                try? FileManager.default.removeItem(at: chunk.url)
                return
            }
        } else {
            text = try await parakeet.transcribe(chunk.url)
        }
        if !text.isEmpty {
            try store.appendSegment(TranscriptSegment(source: chunk.source, start: chunk.start, end: chunk.end, text: text))
        }
        try? FileManager.default.removeItem(at: chunk.url)
    }

    func transcribePending(store: InProgressStore, preferences: Preferences) async throws {
        for chunk in store.pendingChunks() {
            try await transcribe(chunk, store: store, preferences: preferences)
        }
    }

    // MARK: - Finishing

    func finish(
        store: InProgressStore,
        recovered: Bool,
        notesFolder: URL,
        progress: @Sendable (ProcessingStep) -> Void
    ) async -> FinishResult {
        guard let info = store.info() else {
            store.delete()
            return .failed("The recording's session data is missing.")
        }
        let preferences = info.preferences
        if let meeting = store.finishedMeeting() {
            return save(meeting, store: store, preferences: preferences, folder: notesFolder)
        }

        progress(.transcribing)
        do {
            try await transcribePending(store: store, preferences: preferences)
        } catch {
            return .failed("Transcription could not finish: \(error.localizedDescription)")
        }

        let segments = store.segments()
        let systemAudio = (try? WavWriter.readSamples(from: store.systemTrack)) ?? []
        let systemAudioSilent = !systemAudio.contains { abs(Int32($0)) > Int32(Self.signalThreshold) }
        var speakerTurns: [SpeakerTurn]?
        if preferences.speakerSeparation, !systemAudioSilent, segments.contains(where: { $0.source == .system }) {
            progress(.separatingSpeakers)
            speakerTurns = try? await Diarizer.speakerTurns(systemAudio: systemAudio)
        }
        let lines = TranscriptAssembler.assemble(segments: segments, speakerTurns: speakerTurns)
        let duration = max(Double(systemAudio.count) / Double(WavFormat.sampleRate), segments.map(\.end).max() ?? 0)

        var meeting = Meeting(
            id: info.id, title: info.event.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? SummaryService.fallbackTitle(for: info.startDate),
            date: info.startDate, duration: duration, lines: lines,
            transcription: preferences.engine == .api ? preferences.transcriptionModel : parakeet.identifier,
            recovered: recovered, summary: .notGenerated, systemAudioSilent: systemAudioSilent, event: info.event
        )
        if let service = SummaryService(endpoint: preferences.summaryEndpoint(keychain: keychain)), !lines.isEmpty {
            progress(.summarizing)
            let transcript = SummaryService.transcriptText(lines)
            if info.event?.title.isEmpty ?? true, let title = await service.title(transcript: transcript) {
                meeting.title = title
            }
            if preferences.autoSummarize {
                meeting.summary = await Self.summarize(transcript: transcript, title: meeting.title, type: summaryType, with: service)
            }
        }

        try? store.saveFinishedMeeting(meeting)
        progress(.saving)
        return save(meeting, store: store, preferences: preferences, folder: notesFolder)
    }

    /// Summarizes and returns the outcome, with the provider's error when it fails after retries.
    static func summarize(transcript: String, title: String, type: SummaryType, with service: SummaryService) async -> SummaryOutcome {
        do {
            let text = try await service.summarize(transcript: transcript, title: title, type: type)
            return SummaryOutcome(text: text, typeID: type.id, model: service.model)
        } catch {
            return SummaryOutcome(typeID: type.id, model: service.model, error: error.localizedDescription)
        }
    }

    /// Writes the note into the current notes folder, or keeps the meeting in its in-progress folder when the
    /// notes folder is unavailable.
    private func save(_ meeting: Meeting, store: InProgressStore, preferences: Preferences, folder: URL) -> FinishResult {
        let writer = NoteWriter(folder: folder, fileNamePattern: preferences.fileNamePattern)
        let tracks = preferences.keepAudio ? [store.micTrack, store.systemTrack].filter { FileManager.default.fileExists(atPath: $0.path) } : []
        do {
            let url = try writer.save(meeting, audioTracks: tracks)
            store.delete()
            return .saved(SavedNote(url: url, id: meeting.id, title: meeting.title, systemAudioSilent: meeting.systemAudioSilent, summaryFailed: meeting.summary.error != nil))
        } catch {
            try? store.saveFinishedMeeting(meeting)
            return .waitingForFolder(error.localizedDescription)
        }
    }
}
