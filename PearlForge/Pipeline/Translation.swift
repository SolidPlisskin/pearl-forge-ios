import Foundation

/// A language your voice can speak.
struct SpeechLanguage: Hashable, Identifiable, Codable {
    let code: String
    let name: String

    var id: String { code }
}

/// The languages ElevenLabs' Multilingual v2 voice model speaks, the model
/// Pearl Forge uses for your voice.
enum SpeechLanguages {
    static let all: [SpeechLanguage] = [
        ("ar", "Arabic"), ("bg", "Bulgarian"), ("zh", "Chinese (Mandarin)"), ("hr", "Croatian"), ("cs", "Czech"),
        ("da", "Danish"), ("nl", "Dutch"), ("en", "English"), ("fil", "Filipino"), ("fi", "Finnish"),
        ("fr", "French"), ("de", "German"), ("el", "Greek"), ("hi", "Hindi"), ("id", "Indonesian"),
        ("it", "Italian"), ("ja", "Japanese"), ("ko", "Korean"), ("ms", "Malay"), ("pl", "Polish"),
        ("pt", "Portuguese"), ("ro", "Romanian"), ("ru", "Russian"), ("sk", "Slovak"), ("es", "Spanish"),
        ("sv", "Swedish"), ("ta", "Tamil"), ("tr", "Turkish"), ("uk", "Ukrainian"),
    ].map { SpeechLanguage(code: $0.0, name: $0.1) }

    static func named(_ code: String?) -> SpeechLanguage? {
        all.first { $0.code == code }
    }

    /// The request added to a pearl's instructions to have it written in
    /// another language. It reads like the request you'd type yourself.
    static func request(for language: SpeechLanguage) -> String {
        "Say it in \(language.name), the way a native speaker would."
    }
}

/// Faithful translation of text you typed, for speaking it in your voice
/// without polishing it first.
enum TranslationPrompt {
    static func system(for language: SpeechLanguage) -> String {
        """
        Translate the user's text into \(language.name). It will be read aloud in the user's own cloned voice, so it must sound like them speaking \(language.name) naturally.

        - Keep the meaning exactly. Don't add, drop, soften or strengthen anything; keep any uncertainty or hedging, the first person, and the user's tone and register.
        - Prefer the phrasing a native \(language.name) speaker would actually use over a word-for-word rendering.
        - Keep names of people and places as they are.
        - If the text is already in \(language.name), return it unchanged.

        Output only the translation: no quotation marks, notes, alternatives or pronunciation guides.
        """
    }
}

extension Forge {
    /// Translates text into a language with the chosen AI, keeping its meaning.
    static func translate(_ text: String, to language: SpeechLanguage,
                          with choice: PolisherChoice) async throws -> Refinement {
        guard let key = KeychainStore.read(choice.provider.credential) else {
            throw PipelineError(message: "Add your \(choice.provider.name) key in the AI tab first.")
        }
        let system = TranslationPrompt.system(for: language)
        let reply: Completion
        switch choice.provider {
        case .anthropic:
            reply = try await AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
                .complete(system: system, user: text, model: choice.model, failure: "Translation failed")
        case .openai, .gemini, .openrouter:
            reply = try await OpenAICompatibleClient(provider: choice.provider, apiKey: key)
                .complete(system: system, user: text, model: choice.model, failure: "Translation failed")
        }
        if reply.stopReason == "refusal" {
            throw PipelineError(message: "\(choice.provider.name) declined to translate this.")
        }
        if reply.wasCutOff {
            throw PipelineError(message: "The translation was cut off before the end. Try a shorter text.")
        }
        guard !reply.text.isEmpty else {
            throw PipelineError(message: "The translation came back empty. Please try again.")
        }
        return Refinement(text: reply.text, provider: choice.provider, model: reply.model)
    }
}
