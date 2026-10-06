import Foundation

/// Turns the user's plain-language instructions into word replacements for a transcript
/// (improve-meeting-understanding D5). The model only maps words and phrases that exist in the transcript.
struct CorrectionService: Sendable {
    private static let maxCandidates = 400

    let service: SummaryService

    func replacements(instructions: String, transcript: String, context: MeetingContext) async throws -> [GlossaryEntry] {
        let candidates = Self.candidates(in: transcript)
        let system = """
            You correct names in an automatic meeting transcript, following the user's instructions.
            Reply with only a JSON object: {"replacements": [{"from": "...", "to": "..."}]}.
            Each "from" must be copied exactly from the candidate list (words and phrases that appear in the transcript); \
            "to" is the correct spelling. Prefer whole phrases (for example "Doctor Grim") over single words, and include \
            every variant the instructions cover (for example "doctor Greenman" too). Return only the replacements the \
            instructions imply; when they imply none (for example they only add context), return an empty list. Never \
            rewrite sentences.
            """
        let user = context.block + "\n\nInstructions from the user:\n" + instructions
            + "\n\nCandidate words and phrases from the transcript:\n" + candidates.joined(separator: "\n")
        let reply = try await service.client.complete(system: system, user: user, maxTokens: 2_000)
        struct Reply: Decodable {
            struct Replacement: Decodable { var from: String; var to: String }
            var replacements: [Replacement]?
        }
        guard let parsed = ChatClient.decodeJSON(Reply.self, from: reply) else { throw ProviderError.emptyResponse }
        let words = TagService.fold(transcript)
        var seen = Set<String>()
        return (parsed.replacements ?? []).filter { replacement in
            let from = replacement.from.trimmingCharacters(in: .whitespaces)
            return !from.isEmpty && from != replacement.to && words.contains(TagService.fold(from))
                && seen.insert(from.lowercased()).inserted
        }.map { GlossaryEntry(from: $0.from.trimmingCharacters(in: .whitespaces), to: $0.to) }
    }

    /// Distinct capitalized words, and two- and three-word phrases containing one, most frequent first.
    static func candidates(in transcript: String) -> [String] {
        var counts: [String: Int] = [:]
        for line in transcript.components(separatedBy: "\n") {
            let text = line.replacing(#/^\[[\d:]+\] [^:]+: /#, with: "")
            let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            for index in words.indices {
                for length in 1...3 where index + length <= words.count {
                    let phrase = words[index..<index + length]
                    guard phrase.contains(where: { $0.first?.isUppercase == true && $0.count > 1 }) else { continue }
                    counts[phrase.joined(separator: " "), default: 0] += 1
                }
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(maxCandidates).map(\.key)
    }
}
