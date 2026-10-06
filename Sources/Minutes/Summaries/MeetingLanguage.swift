import Foundation

/// The summary language the user chose for a meeting. Without one (Auto) the model judges the language from the whole
/// transcript; Minutes does not detect it, because an on-device guess was wrong more often than the model.
struct MeetingLanguage: Sendable {
    /// ISO code, for example "es".
    let code: String
    /// English name, for example "Spanish".
    let name: String

    /// A language offered in the meeting's Language menu ("en" or "es"); nil for any other code.
    init?(code: String) {
        guard let name = Self.names[code] else { return nil }
        self.code = code
        self.name = name
    }

    private static let names = ["en": "English", "es": "Spanish"]

    /// The language as named in prompts: "Spanish (es)".
    var label: String { "\(name) (\(code))" }

    /// The prompts are in English, which pulls models toward English, so Auto says so explicitly.
    private static let auto = "in the language most of the transcript is spoken in, even though these instructions are in English"

    /// The summary instruction, placed before and after the transcript.
    static func summaryInstruction(_ language: MeetingLanguage?) -> String {
        guard let language else { return "Write the whole summary, including the section headings, \(auto)." }
        return "Write the whole summary in \(language.label), including the section headings: translate the headings into \(language.name). Do not write any part of the answer in another language."
    }

    /// "in Spanish (es)" or the Auto phrase, for titles and topic tags.
    static func phrase(_ language: MeetingLanguage?) -> String {
        language.map { "in \($0.label)" } ?? auto
    }
}
