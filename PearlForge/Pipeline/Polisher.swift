import Foundation

/// The AI services that can polish a transcript.
enum PolisherProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openai
    case gemini
    case openrouter

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        case .gemini: return "Gemini"
        case .openrouter: return "OpenRouter"
        }
    }

    var company: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google"
        case .openrouter: return "Hundreds of models, one key"
        }
    }

    var credential: Credential {
        switch self {
        case .anthropic: return .anthropicKey
        case .openai: return .openAIKey
        case .gemini: return .geminiKey
        case .openrouter: return .openRouterKey
        }
    }

    var keysPageLabel: String {
        switch self {
        case .anthropic: return "Get your key at console.anthropic.com"
        case .openai: return "Get your key at platform.openai.com"
        case .gemini: return "Get your key at aistudio.google.com"
        case .openrouter: return "Get your key at openrouter.ai"
        }
    }

    var keysPage: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .openrouter: return URL(string: "https://openrouter.ai/settings/keys")!
        }
    }

    /// The service's OpenAI-compatible endpoint (Claude uses its own API).
    var compatibleBase: URL {
        switch self {
        case .anthropic: return PipelineConfig.anthropicBase
        case .openai: return URL(string: "https://api.openai.com/v1")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        case .openrouter: return URL(string: "https://openrouter.ai/api/v1")!
        }
    }

    /// The model used until you choose one.
    var defaultModel: String? {
        self == .anthropic ? PipelineConfig.refinementModel : nil
    }

    /// One line about the service for its setup page.
    var about: String {
        switch self {
        case .anthropic:
            return "Claude is what Pearl Forge was designed around. It's the default."
        case .openai:
            return "OpenAI's models, billed to your OpenAI API account (separate from a ChatGPT subscription)."
        case .gemini:
            return "Google's models, billed to your Google AI Studio account. AI Studio has a free tier."
        case .openrouter:
            return "One key and one bill for models from many companies, including Claude, GPT, Gemini, Llama, Mistral, DeepSeek and Grok."
        }
    }
}

/// A service and one of its models: who polishes a pearl.
struct PolisherChoice: Hashable {
    let provider: PolisherProvider
    let model: String
}

/// A model a service offers.
struct AIModel: Identifiable, Hashable {
    let id: String
    let name: String
    let created: Date?
}

/// The polished text, and which service and model actually wrote it (the
/// model can differ from the one requested when Anthropic's fallback
/// stepped in).
struct Refinement {
    let text: String
    let provider: PolisherProvider
    let model: String
}

extension Refinement {
    /// Removes a leading <think>…</think> block some open models put before
    /// their answer.
    static func strippingThinking(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<think>"), let end = text.range(of: "</think>") {
            text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
