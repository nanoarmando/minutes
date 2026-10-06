import Foundation
import NaturalLanguage

/// The dominant language of a transcript, detected on the Mac. Small models often ignore "write in the language of
/// the transcript", so prompts name the language explicitly when it can be detected.
struct MeetingLanguage: Sendable {
    /// ISO code, for example "es".
    let code: String
    /// English name, for example "Spanish".
    let name: String

    /// Nil when the recognizer cannot decide.
    init?(of transcript: String) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(transcript.prefix(20_000)))
        guard let language = recognizer.dominantLanguage, language != .undetermined,
              let englishName = Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue) else { return nil }
        code = language.rawValue
        name = englishName
    }

    /// The language as named in prompts: "Spanish (es)".
    var label: String { "\(name) (\(code))" }

    /// The summary instruction for both prompts, or the generic one when the language is unknown.
    static func summaryInstruction(_ language: MeetingLanguage?) -> String {
        guard let language else { return "Write the notes in the language of the transcript." }
        return "Write the whole summary in \(language.label), including the section headings: translate the headings into \(language.name)."
    }

    /// "in Spanish (es)" or "in the language of the meeting".
    static func phrase(_ language: MeetingLanguage?) -> String {
        language.map { "in \($0.label)" } ?? "in the language of the meeting"
    }
}
