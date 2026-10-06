import Foundation
import os

/// Latest input level per source, written by the recorders and read by the session's 10 Hz ticker.
final class LevelMeter: Sendable {
    private let levels = OSAllocatedUnfairLock(initialState: [AudioSource: Float]())

    func set(_ source: AudioSource, samples: [Int16]) {
        let rms = (samples.reduce(Float(0)) { $0 + Float($1) * Float($1) } / Float(max(samples.count, 1))).squareRoot() / 32768
        let decibels = 20 * log10(max(rms, 0.000_01))
        levels.withLock { $0[source] = max(0, min(1, (decibels + 60) / 60)) }
    }

    func level(_ source: AudioSource) -> Float {
        levels.withLock { $0[source] ?? 0 }
    }
}

/// Samples as delivered by a capture object, stamped on arrival so queueing never skews timing.
struct SampleBuffer: Sendable {
    let samples: [Int16]
    let receivedAt = ContinuousClock.now
}

/// Consumes the samples of one source: writes the optional full-length track, cuts rotating chunk WAVs at
/// pauses (via `VadChunker`) and emits the chunks that contain speech.
///
/// Timing is by sample count. When a source delivers nothing for a while (a muted tap, a microphone restart),
/// silence is inserted so offsets stay aligned with the wall clock.
enum ChunkRecorder {
    private static let maxDrift = WavFormat.sampleRate / 2

    static func record(
        source: AudioSource,
        samples: AsyncStream<SampleBuffer>,
        startedAt start: ContinuousClock.Instant,
        chunkFolder: URL,
        fullTrack: URL?,
        levels: LevelMeter,
        chunks: AsyncStream<AudioChunk>.Continuation
    ) async {
        let trackWriter = fullTrack.flatMap { try? WavWriter(url: $0) }
        let chunker = VadChunker(vad: await VadChunker.loadVad())
        var chunk: [Int16] = []
        var chunkStart = 0
        var received = 0
        var scanned = 0

        func emitChunk() {
            defer {
                chunkStart += chunk.count
                chunk.removeAll(keepingCapacity: true)
                scanned = 0
                chunker.startNextChunk()
            }
            guard chunker.chunkHasSpeech, chunk.count > WavFormat.sampleRate / 4 else { return }
            let offset = Double(chunkStart) / Double(WavFormat.sampleRate)
            let url = chunkFolder.appendingPathComponent(InProgressStore.chunkFileName(source: source, start: offset))
            guard (try? WavWriter.write(chunk, to: url)) != nil else { return }
            chunks.yield(AudioChunk(source: source, start: offset, duration: Double(chunk.count) / Double(WavFormat.sampleRate), url: url))
        }

        for await delivery in samples {
            let buffer = delivery.samples
            let elapsed = (delivery.receivedAt - start) / .seconds(1)
            let expected = Int(elapsed * Double(WavFormat.sampleRate)) - buffer.count
            var incoming = buffer
            if expected - received > maxDrift {
                incoming = [Int16](repeating: 0, count: expected - received) + buffer
            }
            received += incoming.count
            levels.set(source, samples: buffer)
            try? trackWriter?.append(incoming)
            chunk.append(contentsOf: incoming)

            while chunk.count - scanned >= VadChunker.windowSize {
                let window = chunk[scanned..<(scanned + VadChunker.windowSize)].map { Float($0) / 32768 }
                scanned += VadChunker.windowSize
                let duration = Double(scanned) / Double(WavFormat.sampleRate)
                if await chunker.process(window: window, chunkDuration: duration) {
                    let remainder = Array(chunk[scanned...])
                    chunk.removeLast(chunk.count - scanned)
                    emitChunk()
                    chunk = remainder
                }
            }
        }
        if !chunk.isEmpty {
            if chunk.count > scanned {
                _ = await chunker.process(window: chunk[scanned...].map { Float($0) / 32768 }, chunkDuration: 0)
            }
            emitChunk()
        }
        try? trackWriter?.finish()
        levels.set(source, samples: [])
    }
}
