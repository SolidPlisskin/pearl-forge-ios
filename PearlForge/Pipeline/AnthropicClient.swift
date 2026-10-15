import Foundation

/// The refined text, and which model actually wrote it (it differs from the
/// requested model only when Anthropic's fallback stepped in).
struct Refinement {
    let text: String
    let model: String
}

/// Anthropic calls: the key check and the meaning-preserving refinement.
struct AnthropicClient {
    let apiKey: String
    /// Sent as "anthropic-workspace-id" when the key is organization-scoped.
    let workspaceID: String?

    /// Confirms the key works and can use the refinement model. Looking up a
    /// model is free; no tokens are spent.
    func checkAccess() async throws {
        let url = PipelineConfig.anthropicBase
            .appendingPathComponent("models")
            .appendingPathComponent(PipelineConfig.refinementModel)
        var request = URLRequest(url: url, timeoutInterval: 60)
        applyHeaders(to: &request)
        _ = try await PipelineHTTP.send(request, failure: "Your Anthropic key didn't work")
    }

    /// Improves how clearly the transcript is expressed without changing what
    /// it says, using the system prompt for `mode` plus any notes you gave.
    func refine(_ transcript: String, mode: RefinementMode, notes: String? = nil) async throws -> Refinement {
        var request = URLRequest(url: PipelineConfig.anthropicBase.appendingPathComponent("messages"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // If a safety check declines the request, Anthropic re-runs it on its
        // recommended fallback model instead of returning a refusal.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        struct Body: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let maxTokens: Int
            let system: String
            let messages: [Message]
            let fallbacks: String
        }
        // Leaving out `thinking` runs adaptive thinking by default on this
        // model, which helps with the careful meaning-preservation judgement.
        // Only the visible text block(s) are read back out.
        let body = Body(model: PipelineConfig.refinementModel,
                        maxTokens: PipelineConfig.refinementMaxTokens,
                        system: RefinementPrompts.system(for: mode, notes: notes),
                        messages: [.init(role: "user", content: transcript)],
                        fallbacks: "default")
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
        return Refinement(text: text, model: response.model ?? PipelineConfig.refinementModel)
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(PipelineConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if let workspaceID, !workspaceID.isEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }
    }
}
