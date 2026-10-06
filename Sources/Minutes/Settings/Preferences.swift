import Foundation

/// User settings, stored as one JSON value in UserDefaults. API keys are not here; they live in the Keychain.
/// A copy is snapshotted into each in-progress session so a recovered meeting uses the settings it started with.
struct Preferences: Codable, Sendable, Equatable {
    enum Engine: String, Codable, Sendable { case parakeet, api }

    var notesFolder = URL.documentsDirectory.appendingPathComponent("Minutes", isDirectory: true)
    var fileNamePattern = "{date} {time} {title}"
    var keepAudio = false
    var suggestOnCallDetected = true
    var useCalendar = false
    var suggestRecording = true
    /// Stored as unfollowed identifiers so calendars added later are followed by default.
    var unfollowedCalendars: Set<String> = []

    var engine = Engine.parakeet
    var transcriptionBaseURL = "https://api.openai.com/v1"
    var transcriptionModel = "whisper-1"
    var speakerSeparation = true

    var summaryBaseURL = ""
    var summaryModel = ""
    var autoSummarize = true
    var detectClients = true
    var topicTags = true
    /// The addresses the user joins meetings with, lowercased; they tell the user's organization from clients.
    var userEmails: [String] = []

    private static let key = "preferences"

    /// Stored values are laid over the defaults, so a key added in a later version does not reset the rest.
    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(stored) { $1 }),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: merged) else { return Preferences() }
        return preferences
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    func transcriptionEndpoint(keychain: KeychainStore) -> ProviderEndpoint {
        ProviderEndpoint(baseURL: transcriptionBaseURL, apiKey: keychain.read(.transcription), model: transcriptionModel)
    }

    func summaryEndpoint(keychain: KeychainStore) -> ProviderEndpoint {
        ProviderEndpoint(baseURL: summaryBaseURL, apiKey: keychain.read(.summary), model: summaryModel)
    }
}

enum AppPaths {
    /// ~/Library/Application Support/Minutes
    static let supportFolder = URL.applicationSupportDirectory.appendingPathComponent("Minutes", isDirectory: true)
}
