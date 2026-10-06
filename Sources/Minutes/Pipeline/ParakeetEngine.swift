import FluidAudio
import Foundation

/// On-device transcription with Parakeet TDT v3 through FluidAudio. The language is detected by the model.
///
/// The model is downloaded on first need into FluidAudio's cache
/// (~/Library/Application Support/FluidAudio/Models). Callers that transcribe while the download runs simply
/// wait; their chunks stay on disk in the in-progress folder meanwhile.
actor ParakeetEngine: TranscriptionEngine {
    enum ModelState: Sendable, Equatable {
        case notInstalled
        case downloading(Double)
        case ready
        case failed(String)
    }

    nonisolated let identifier = "parakeet-v3"
    private let onStateChange: @Sendable (ModelState) -> Void
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    init(onStateChange: @escaping @Sendable (ModelState) -> Void = { _ in }) {
        self.onStateChange = onStateChange
    }

    nonisolated static var isInstalled: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
    }

    /// Downloads (when missing) and loads the model. Concurrent callers share one load; a failed load is
    /// retried by the next call.
    @discardableResult
    func prepare() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }

        let onStateChange = onStateChange
        let task = Task {
            onStateChange(.downloading(0))
            let models = try await AsrModels.downloadAndLoad(version: .v3) { progress in
                onStateChange(.downloading(progress.fractionCompleted))
            }
            let manager = AsrManager()
            try await manager.loadModels(models)
            return manager
        }
        loading = task
        do {
            let loaded = try await task.value
            manager = loaded
            loading = nil
            onStateChange(.ready)
            return loaded
        } catch {
            loading = nil
            onStateChange(.failed(error.localizedDescription))
            throw error
        }
    }

    func transcribe(_ chunk: URL) async throws -> String {
        let manager = try await prepare()
        let samples = try WavWriter.readSamples(from: chunk).map { Float($0) / 32768 }
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deleteModel() throws {
        loading?.cancel()
        loading = nil
        manager = nil
        let directory = AsrModels.defaultCacheDirectory(for: .v3)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        onStateChange(.notInstalled)
    }
}
