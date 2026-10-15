import Foundation

/// Endpoints, models, and limits for Pearl Forge's three cloud calls. The
/// defaults match the Pinokio build's pipeline.py.
enum PipelineConfig {
    // ElevenLabs: speech-to-text, text-to-speech, and the voice list.
    static let elevenLabsBase = URL(string: "https://api.elevenlabs.io/v1")!
    static let transcriptionModel = "scribe_v1"
    static let speechModel = "eleven_multilingual_v2"

    // Anthropic: the refinement step.
    static let anthropicBase = URL(string: "https://api.anthropic.com/v1")!
    static let anthropicVersion = "2023-06-01"
    static let refinementModel = "claude-opus-5-5"
    static let refinementMaxTokens = 16000

    /// ElevenLabs accepts long inputs, but splitting very long text keeps each
    /// request comfortable and lets us pass neighbouring text for prosody
    /// continuity.
    static let speechChunkCharacters = 2500

    /// Long recordings take a while to transcribe and refine.
    static let requestTimeout: TimeInterval = 900
}
