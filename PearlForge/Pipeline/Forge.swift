import Foundation

/// The steps a voice note goes through, for progress messages.
enum ForgeStep: Equatable {
    case transcribing, refining, translating, researching, speaking

    var progressLabel: String {
        switch self {
        case .transcribing: return "Transcribing…"
        case .refining: return "Refining (keeping your meaning)…"
        case .translating: return "Translating (keeping your meaning)…"
        case .researching: return "Researching and writing your lecture…"
        case .speaking: return "Speaking it back in your voice…"
        }
    }
}

/// The three cloud calls, using the keys saved in the Keychain.
enum Forge {
    static func transcribe(_ audio: URL) async throws -> String {
        try await elevenLabs().transcribe(audioAt: audio)
    }

    /// Polishes the transcript with the chosen AI, using the Pinokio build's
    /// instructions for the mode plus any notes you gave.
    static func refine(_ transcript: String, mode: RefinementMode, notes: String?,
                       with choice: PolisherChoice) async throws -> Refinement {
        guard !transcript.isEmpty else {
            throw PipelineError(message: "The transcript for this recording couldn't be loaded. Pull down on History to refresh, then try again.")
        }
        let system = RefinementPrompts.system(for: mode, notes: notes)
        guard let key = KeychainStore.read(choice.provider.credential) else {
            throw PipelineError(message: "Add your \(choice.provider.name) key in the AI tab first.")
        }
        switch choice.provider {
        case .anthropic:
            return try await AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
                .refine(transcript, system: system, model: choice.model)
        case .openai, .gemini, .openrouter:
            return try await OpenAICompatibleClient(provider: choice.provider, apiKey: key)
                .refine(transcript, system: system, model: choice.model)
        }
    }

    static func speak(_ text: String, voiceID: String) async throws -> Data {
        try await elevenLabs().synthesize(text, voiceID: voiceID)
    }

    static func elevenLabs() throws -> ElevenLabsClient {
        guard let key = KeychainStore.read(.elevenLabsKey) else {
            throw PipelineError(message: "Add your ElevenLabs key in Settings first.")
        }
        return ElevenLabsClient(apiKey: key)
    }
}
