import FluidAudio
import Foundation

/// A stretch of system audio attributed to one remote speaker.
struct SpeakerTurn: Codable, Sendable {
    let speakerID: String
    let start: TimeInterval
    let end: TimeInterval
}

/// Separates remote speakers once, after the meeting, on the full system-audio track.
/// Models are downloaded by FluidAudio on first use. Any failure is thrown and the caller falls back to "Others".
enum Diarizer {
    static func speakerTurns(systemAudio: [Int16]) async throws -> [SpeakerTurn] {
        let samples = systemAudio.map { Float($0) / 32768 }
        let models = try await DiarizerModels.downloadIfNeeded()
        // DiarizerManager is not Sendable: it is created, used and released inside this function only.
        let manager = DiarizerManager()
        manager.initialize(models: models)
        defer { manager.cleanup() }
        let result = try manager.performCompleteDiarization(samples, sampleRate: WavFormat.sampleRate)
        return result.segments.map {
            SpeakerTurn(speakerID: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
    }
}
