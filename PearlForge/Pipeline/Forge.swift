import Foundation

/// The steps a voice note goes through, for progress messages.
enum ForgeStep: Equatable {
    case transcribing, refining, speaking

    var progressLabel: String {
        switch self {
        case .transcribing: return "Transcribing…"
        case .refining: return "Refining (keeping your meaning)…"
        case .speaking: return "Speaking it back in your voice…"
        }
    }
}

/// The three cloud calls, using the keys saved in the Keychain.
enum Forge {
    static func transcribe(_ audio: URL) async throws -> String {
        try await elevenLabs().transcribe(audioAt: audio)
    }

    static func refine(_ transcript: String, mode: RefinementMode, notes: String?) async throws -> Refinement {
        guard !transcript.isEmpty else {
            throw PipelineError(message: "The transcript for this recording couldn't be loaded. Pull down on History to refresh, then try again.")
        }
        return try await anthropic().refine(transcript, mode: mode, notes: notes)
    }

    static func speak(_ text: String, voiceID: String) async throws -> Data {
        try await elevenLabs().synthesize(text, voiceID: voiceID)
    }

    private static func elevenLabs() throws -> ElevenLabsClient {
        guard let key = KeychainStore.read(.elevenLabsKey) else {
            throw PipelineError(message: "Add your ElevenLabs key in Settings first.")
        }
        return ElevenLabsClient(apiKey: key)
    }

    private static func anthropic() throws -> AnthropicClient {
        guard let key = KeychainStore.read(.anthropicKey) else {
            throw PipelineError(message: "Add your Anthropic key in Settings first.")
        }
        return AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
    }
}
