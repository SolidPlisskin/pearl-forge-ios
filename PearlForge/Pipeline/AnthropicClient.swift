import Foundation

/// Anthropic calls: the model list and the meaning-preserving refinement.
struct AnthropicClient {
    let apiKey: String
    /// Sent as "anthropic-workspace-id" when the key is organization-scoped.
    let workspaceID: String?

    /// Models whose safety checks can hand a declined request to Anthropic's
    /// recommended fallback model.
    private static let fallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-fable-5", "claude-mythos-5-1",
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    /// Models that think only when asked; newer ones think by default.
    private static let adaptiveThinkingModels = ["claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-6"]

    /// Your account's Claude models, newest first. Listing models is free; no
    /// tokens are spent, so this doubles as the key check.
    func listModels() async throws -> [AIModel] {
        var components = URLComponents(url: PipelineConfig.anthropicBase.appendingPathComponent("models"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
        var request = URLRequest(url: components.url!, timeoutInterval: 60)
        applyHeaders(to: &request)
        let data = try await PipelineHTTP.send(request, failure: "Your Anthropic key didn't work")

        struct List: Decodable {
            struct Item: Decodable {
                let id: String
                let displayName: String?
                let createdAt: String?
            }
            let data: [Item]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        return (try decoder.decode(List.self, from: data).data ?? [])
            .map { AIModel(id: $0.id, name: $0.displayName ?? $0.id, created: $0.createdAt.flatMap(iso.date)) }
            .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }

    /// Improves how clearly the transcript is expressed without changing what
    /// it says, following the given polishing instructions.
    func refine(_ transcript: String, system: String, model: String) async throws -> Refinement {
        var request = URLRequest(url: PipelineConfig.anthropicBase.appendingPathComponent("messages"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let usesFallback = Self.fallbackModels.contains(model)
        if usesFallback {
            // If a safety check declines the request, Anthropic re-runs it on
            // its recommended fallback model instead of returning a refusal.
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }

        struct Body: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            struct Thinking: Encodable { let type: String }
            let model: String
            let maxTokens: Int
            let system: String
            let messages: [Message]
            let fallbacks: String?
            let thinking: Thinking?
        }
        // On current models leaving out `thinking` runs adaptive thinking,
        // which helps with the careful meaning-preservation judgement; older
        // ones are asked for it. Only the visible text is read back out.
        let body = Body(model: model,
                        maxTokens: PipelineConfig.refinementMaxTokens,
                        system: system,
                        messages: [.init(role: "user", content: transcript)],
                        fallbacks: usesFallback ? "default" : nil,
                        thinking: Self.adaptiveThinkingModels.contains(model) ? .init(type: "adaptive") : nil)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let data = try await PipelineHTTP.send(request, failure: "Refinement failed")

        struct Response: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let model: String?
            let content: [Block]?
            let stopReason: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)

        if response.stopReason == "refusal" {
            throw PipelineError(message: "Claude declined to refine this recording. Try again, or try a different mode.")
        }
        // A cut-off refinement would silently drop the end of your thought.
        if response.stopReason == "max_tokens" {
            throw PipelineError(message: "The refined version was cut off before the end. The recording may be too long for one pass; try Summarize or a shorter recording.")
        }
        let text = (response.content ?? [])
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PipelineError(message: "The refinement came back empty. Please try again.")
        }
        return Refinement(text: text, provider: .anthropic, model: response.model ?? model)
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(PipelineConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if let workspaceID, !workspaceID.isEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }
    }
}
