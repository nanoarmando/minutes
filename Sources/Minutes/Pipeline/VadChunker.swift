import FluidAudio
import Foundation

/// Decides where to cut the audio of one source into chunks for transcription: at a natural pause once a chunk
/// is 3 s long, at the next quiet window after 5 s, and unconditionally at 12 s. It also tracks whether the
/// current chunk contains speech, so silent chunks are never transcribed (the silence gate).
///
/// Uses Silero VAD through FluidAudio; when the VAD model cannot be loaded it falls back to an energy gate.
final class VadChunker {
    static let windowSize = VadManager.chunkSize  // 4096 samples, 256 ms
    private static let minChunk: TimeInterval = 3
    private static let targetChunk: TimeInterval = 5
    private static let maxChunk: TimeInterval = 12
    private static let energySpeechThreshold: Float = 0.01

    private let vad: VadManager?
    private var streamState = VadStreamState.initial()
    private(set) var chunkHasSpeech = false

    init(vad: VadManager?) {
        self.vad = vad
    }

    /// Feeds one window of the current chunk and returns whether the chunk should be cut after it.
    func process(window: [Float], chunkDuration: TimeInterval) async -> Bool {
        var inSpeech: Bool
        var pauseStarted = false
        if let vad, let result = try? await vad.processStreamingChunk(window, state: streamState) {
            streamState = result.state
            inSpeech = result.state.triggered
            pauseStarted = result.event?.isEnd == true
            if result.event?.isStart == true { inSpeech = true }
        } else {
            inSpeech = Self.rms(window) > Self.energySpeechThreshold
        }
        if inSpeech || pauseStarted { chunkHasSpeech = true }

        if chunkDuration >= Self.maxChunk { return true }
        guard chunkDuration >= Self.minChunk else { return false }
        if pauseStarted { return true }
        return chunkDuration >= Self.targetChunk && !inSpeech
    }

    func startNextChunk() {
        chunkHasSpeech = false
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    /// Loads the Silero VAD model once per launch (downloaded by FluidAudio on first use).
    static func loadVad() async -> VadManager? {
        await VadCache.shared.manager()
    }
}

private actor VadCache {
    static let shared = VadCache()
    private var cached: VadManager?

    func manager() async -> VadManager? {
        if let cached { return cached }
        cached = try? await VadManager()
        return cached
    }
}
