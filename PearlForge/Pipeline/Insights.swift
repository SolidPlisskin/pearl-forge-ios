import Foundation

/// What a recording is about: its broad topics and a one-line gist.
struct RecordingInsights: Equatable {
    let categories: [String]
    let gist: String
}

/// Sorts recordings into topics such as "Relationships" or "Work & Career",
/// reusing the topics you already have so related thoughts gather together.
enum TopicSorter {
    /// Topics offered to the AI as a starting vocabulary.
    static let starterTopics = [
        "Relationships", "Work & Career", "Parenting & Family", "Friendship",
        "Health & Body", "Mind & Emotions", "Money", "Creativity",
        "Learning & Ideas", "Philosophy & Meaning", "Faith & Spirituality",
        "Personal Growth", "Technology", "Society & Politics",
    ]

    static let maxTopics = 3

    static func system(existing: [String]) -> String {
        let known = existing.isEmpty ? starterTopics : existing + starterTopics.filter { starter in
            !existing.contains { $0.caseInsensitiveCompare(starter) == .orderedSame }
        }
        return """
        You sort a person's voice notes into broad life topics so that related thoughts can be found together later. You are given the verbatim transcript of one voice note.

        Choose 1 to \(maxTopics) topics that the note is substantially about. Prefer these topics, spelled exactly as written, whenever one fits:
        \(known.map { "- \($0)" }.joined(separator: "\n"))
        Only create a new topic if none of these fits; keep a new one broad, in Title Case, and at most three words.

        Also write a gist: one sentence, in the first person, saying what the speaker is thinking about. Keep their uncertainty (if they say "maybe" or "I'm not sure", so does the gist). At most 25 words.

        Reply with only this JSON and nothing else:
        {"categories": ["Topic"], "gist": "I'm wondering whether..."}
        """
    }

    /// Reads the AI's reply, matching topics to the existing spelling.
    static func parse(_ reply: String, existing: [String]) throws -> RecordingInsights {
        struct Raw: Decodable {
            let categories: [String]?
            let gist: String?
        }
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let raw = try? JSONDecoder().decode(Raw.self, from: Data(reply[start...end].utf8))
        else {
            throw PipelineError(message: "The topics came back in an unexpected format. Please try again.")
        }
        let known = existing + starterTopics
        var categories: [String] = []
        for name in raw.categories ?? [] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let canonical = known.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
            if !categories.contains(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) {
                categories.append(canonical)
            }
        }
        guard !categories.isEmpty else {
            throw PipelineError(message: "No topics came back. Please try again.")
        }
        return RecordingInsights(categories: Array(categories.prefix(maxTopics)),
                                 gist: (raw.gist ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension Forge {
    /// Sorts a transcript into topics using the chosen AI.
    static func sortIntoTopics(_ transcript: String, existing: [String],
                               with choice: PolisherChoice) async throws -> RecordingInsights {
        guard !transcript.isEmpty else {
            throw PipelineError(message: "This recording's transcript couldn't be loaded.")
        }
        guard let key = KeychainStore.read(choice.provider.credential) else {
            throw PipelineError(message: "Add your \(choice.provider.name) key in the AI tab first.")
        }
        let system = TopicSorter.system(existing: existing)
        let reply: Completion
        switch choice.provider {
        case .anthropic:
            reply = try await AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
                .complete(system: system, user: transcript, model: choice.model, failure: "Sorting into topics failed")
        case .openai, .gemini, .openrouter:
            reply = try await OpenAICompatibleClient(provider: choice.provider, apiKey: key)
                .complete(system: system, user: transcript, model: choice.model, failure: "Sorting into topics failed")
        }
        if reply.stopReason == "refusal" {
            throw PipelineError(message: "\(choice.provider.name) declined to sort this recording.")
        }
        return try TopicSorter.parse(reply.text, existing: existing)
    }
}
