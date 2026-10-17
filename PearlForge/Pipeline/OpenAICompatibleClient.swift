import Foundation

/// Calls to services that speak OpenAI's chat format: OpenAI itself, Google
/// Gemini, and OpenRouter.
struct OpenAICompatibleClient {
    let provider: PolisherProvider
    let apiKey: String

    // MARK: Models

    /// The service's chat models, newest first.
    func listModels() async throws -> [AIModel] {
        var request = URLRequest(url: provider.compatibleBase.appendingPathComponent("models"), timeoutInterval: 60)
        applyHeaders(to: &request)
        let data = try await PipelineHTTP.send(request, failure: "Your \(provider.name) key didn't work")

        struct List: Decodable {
            struct Item: Decodable {
                struct Architecture: Decodable { let outputModalities: [String]? }
                let id: String
                let name: String?
                let created: Double?
                let architecture: Architecture?
            }
            let data: [Item]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode(List.self, from: data).data ?? []

        return items.compactMap { item -> AIModel? in
            // Gemini lists ids as "models/gemini-…".
            let id = item.id.hasPrefix("models/") ? String(item.id.dropFirst("models/".count)) : item.id
            guard isChatModel(id, outputs: item.architecture?.outputModalities) else { return nil }
            return AIModel(id: id, name: item.name ?? id,
                           created: item.created.map { Date(timeIntervalSince1970: $0) })
        }
        .sorted { lhs, rhs in
            switch (lhs.created, rhs.created) {
            case let (l?, r?) where l != r: return l > r
            default: return lhs.id.localizedStandardCompare(rhs.id) == .orderedDescending
            }
        }
    }

    /// Confirms the key works. OpenRouter lists its models without a key, so
    /// its key is checked separately.
    func checkKey() async throws {
        guard provider == .openrouter else {
            _ = try await listModels()
            return
        }
        var request = URLRequest(url: provider.compatibleBase.appendingPathComponent("key"), timeoutInterval: 60)
        applyHeaders(to: &request)
        _ = try await PipelineHTTP.send(request, failure: "Your OpenRouter key didn't work")
    }

    /// Leaves out models that can't write text replies (images, speech,
    /// embeddings, …), so the list is just the ones that can polish.
    private func isChatModel(_ id: String, outputs: [String]?) -> Bool {
        let lower = id.lowercased()
        switch provider {
        case .openai:
            let families = ["gpt-", "chatgpt-", "o1", "o3", "o4", "o5"]
            let excluded = ["audio", "realtime", "tts", "transcribe", "image", "search", "embedding",
                            "instruct", "moderation", "codex", "dall-e", "whisper", "computer-use",
                            "deep-research", "babbage", "davinci"]
            let datedSnapshot = lower.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
            return families.contains { lower.hasPrefix($0) }
                && !excluded.contains { lower.contains($0) }
                && !datedSnapshot
        case .gemini:
            let excluded = ["embedding", "image", "tts", "live", "audio", "veo", "imagen", "aqa"]
            return (lower.contains("gemini") || lower.contains("gemma")) && !excluded.contains { lower.contains($0) }
        case .openrouter:
            return outputs?.contains("text") ?? true
        case .anthropic:
            return true
        }
    }

    // MARK: Polishing

    /// Sends the polishing instructions and transcript, and returns the reply.
    func refine(_ transcript: String, system: String, model: String) async throws -> Refinement {
        let reply = try await complete(system: system, user: transcript, model: model,
                                       failure: "Polishing with \(provider.name) failed")
        if reply.stopReason == "refusal" {
            throw PipelineError(message: "\(provider.name) declined to polish this recording. Try again, or try a different AI.")
        }
        // A cut-off refinement would silently drop the end of your thought.
        if reply.stopReason == "length" {
            throw PipelineError(message: "The polished version was cut off before the end. The recording may be too long for this model; try Summarize, a shorter recording, or a different model.")
        }
        guard !reply.text.isEmpty else {
            throw PipelineError(message: "The polished version came back empty. Please try again.")
        }
        return Refinement(text: reply.text, provider: provider, model: reply.model)
    }

    /// One system message and one user message; returns the reply. A refusal
    /// is reported as the stop reason "refusal".
    func complete(system: String, user: String, model: String,
                  failure: String? = nil) async throws -> Completion {
        let failure = failure ?? "\(provider.name) request failed"
        var request = URLRequest(url: provider.compatibleBase.appendingPathComponent("chat/completions"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let messages: [Message]
        }
        // No length limit is sent: each model's own maximum applies, so a
        // long recording isn't cut short.
        request.httpBody = try JSONEncoder().encode(Body(model: model, messages: [
            .init(role: "system", content: system),
            .init(role: "user", content: user),
        ]))

        let data = try await PipelineHTTP.send(request, failure: failure)

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: FlexibleText?
                    let refusal: String?
                }
                let message: Message?
                let finishReason: String?
            }
            struct APIError: Decodable { let message: String? }
            let model: String?
            let choices: [Choice]?
            let error: APIError?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)

        guard let choice = response.choices?.first else {
            throw PipelineError(message: "\(failure): \(response.error?.message ?? "no reply came back.")")
        }
        let refused = choice.message?.refusal?.isEmpty == false || choice.finishReason == "content_filter"
        return Completion(text: Refinement.strippingThinking(choice.message?.content?.text ?? ""),
                          model: response.model ?? model,
                          stopReason: refused ? "refusal" : choice.finishReason)
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if provider == .openrouter {
            // Labels the usage in your OpenRouter activity list.
            request.setValue("Pearl Forge", forHTTPHeaderField: "X-Title")
        }
    }
}

/// Message text that arrives either as a plain string or as a list of parts.
struct FlexibleText: Decodable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            text = string
        } else {
            struct Part: Decodable { let text: String? }
            text = ((try? container.decode([Part].self)) ?? []).compactMap(\.text).joined()
        }
    }
}
