import Foundation

/// How far Claude's research has got: how many searches so far, and the
/// latest one.
struct ResearchProgress: Equatable {
    var webSearches = 0
    var pubMedSearches = 0
    var latestQuery: String?

    var searches: Int { webSearches + pubMedSearches }
}

/// A conversation in which Claude searches the web and PubMed until it calls
/// the finishing tool (save_references, write_lecture, …). Every address that
/// came back from a search is kept, so the sources Claude names can be checked
/// against them, and what the calls used is added up so their cost is known.
struct ResearchLoop {
    let apiKey: String
    let workspaceID: String?
    let model: String
    let system: String
    let finishTool: [String: Any]
    var maxWebSearches = 6
    var maxSteps = 12
    /// Starts the message of a failed request: "Finding references failed: …".
    var failure = "The search failed"
    /// Sent once if Claude stops without calling the finishing tool.
    var nudge: String?
    var onProgress: (@MainActor (ResearchProgress) -> Void)?

    /// How the conversation ended when Claude didn't call the finishing tool.
    enum Stop: Error {
        case refusal, cutOff, unfinished, tooManySteps
    }

    struct Outcome {
        /// What Claude passed to the finishing tool.
        let input: [String: Any]
        let seenURLs: [String: String]
        let papers: [String: PubMedPaper]
        let usage: ClaudeUsage
        /// The model that answered; differs from the one asked for only when
        /// Anthropic's fallback stepped in.
        let answeredBy: String
    }

    private var finishName: String { finishTool["name"] as? String ?? "" }

    func run(user: String) async throws -> Outcome {
        var messages: [[String: Any]] = [["role": "user", "content": user]]
        var seenURLs: [String: String] = [:]
        var papers: [String: PubMedPaper] = [:]
        var usage = ClaudeUsage()
        var progress = ResearchProgress()
        var answeredBy = model
        var nudged = false

        for _ in 0..<maxSteps {
            let response = try await send(messages)
            usage.add(response["usage"] as? [String: Any])
            if let model = response["model"] as? String { answeredBy = model }
            let content = response["content"] as? [[String: Any]] ?? []
            ReferenceFinder.collectURLs(in: content, into: &seenURLs)
            for block in content where block["type"] as? String == "server_tool_use" {
                progress.webSearches += 1
                progress.latestQuery = (block["input"] as? [String: Any])?["query"] as? String ?? progress.latestQuery
            }

            switch response["stop_reason"] as? String {
            case "pause_turn":
                // A long search paused; send the turn back unchanged to resume.
                messages.append(["role": "assistant", "content": content])

            case "tool_use":
                let calls = content.filter { $0["type"] as? String == "tool_use" }
                if let finish = calls.first(where: { $0["name"] as? String == finishName }) {
                    return Outcome(input: finish["input"] as? [String: Any] ?? [:], seenURLs: seenURLs,
                                   papers: papers, usage: usage, answeredBy: answeredBy)
                }
                var results: [[String: Any]] = []
                for call in calls {
                    if let query = (call["input"] as? [String: Any])?["query"] as? String {
                        progress.pubMedSearches += 1
                        progress.latestQuery = query
                    }
                    results.append(await run(call, papers: &papers))
                }
                messages.append(["role": "assistant", "content": content])
                messages.append(["role": "user", "content": results])

            case "end_turn" where !nudged:
                // It stopped without finishing; ask once more.
                nudged = true
                messages.append(["role": "assistant", "content": content])
                messages.append(["role": "user", "content": nudge ?? "Please call \(finishName) now."])

            case "refusal":
                throw Stop.refusal
            case "max_tokens":
                throw Stop.cutOff
            default:
                throw Stop.unfinished
            }
            await onProgress?(progress)
        }
        throw Stop.tooManySteps
    }

    // MARK: Request

    private func send(_ messages: [[String: Any]]) async throws -> [String: Any] {
        var request = URLRequest(url: PipelineConfig.anthropicBase.appendingPathComponent("messages"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        let client = AnthropicClient(apiKey: apiKey, workspaceID: workspaceID)
        client.applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": PipelineConfig.refinementMaxTokens,
            "system": system,
            "messages": messages,
            "tools": [Self.webSearchTool(maxUses: maxWebSearches), Self.pubMedTool, finishTool],
            // Each step resends the earlier search results; caching them makes
            // those repeats much cheaper.
            "cache_control": ["type": "ephemeral"],
        ]
        if AnthropicClient.fallbackModels.contains(model) {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        if AnthropicClient.adaptiveThinkingModels.contains(model) {
            body["thinking"] = ["type": "adaptive"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await PipelineHTTP.send(request, failure: failure)
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PipelineError(message: "\(failure): the reply couldn't be read.")
        }
        return response
    }

    /// Runs one of Pearl Forge's own tools and returns its result block.
    private func run(_ call: [String: Any], papers: inout [String: PubMedPaper]) async -> [String: Any] {
        let id = call["id"] as? String ?? ""
        let input = call["input"] as? [String: Any] ?? [:]
        guard call["name"] as? String == "pubmed_search", let query = input["query"] as? String, !query.isEmpty else {
            return ["type": "tool_result", "tool_use_id": id, "is_error": true,
                    "content": "Unknown tool or missing query."]
        }
        do {
            let found = try await PubMedClient.search(query, maxResults: input["max_results"] as? Int ?? 6)
            for paper in found { papers[paper.pmid] = paper }
            let summary: [[String: Any]] = found.map { paper in
                ["pmid": paper.pmid, "url": paper.url, "title": paper.title, "journal": paper.journal,
                 "year": paper.year, "authors": paper.authorLine, "abstract": String(paper.abstract.prefix(1200))]
            }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: summary), as: UTF8.self)
            return ["type": "tool_result", "tool_use_id": id,
                    "content": found.isEmpty ? "No PubMed results for that query. Try broader or different terms." : json]
        } catch {
            return ["type": "tool_result", "tool_use_id": id, "is_error": true, "content": error.localizedDescription]
        }
    }

    // MARK: Tools

    /// The basic web search tool. The filtered version (web_search_20260209)
    /// runs searches inside code, and in live tests some of the results Claude
    /// read never came back as checkable search results, so every reference
    /// failed verification. The basic version always returns them.
    static func webSearchTool(maxUses: Int) -> [String: Any] {
        ["type": "web_search_20250305", "name": "web_search", "max_uses": maxUses]
    }

    static let pubMedTool: [String: Any] = [
        "name": "pubmed_search",
        "description": "Search PubMed, the US National Library of Medicine's database of peer-reviewed biomedical and life-sciences research (including psychology, psychiatry, child development, relationships and health). Returns titles, journals, years and abstracts. Call this whenever the subject touches on something researchers study. Use PubMed search terms, not a sentence: a few key terms joined with AND/OR.",
        "input_schema": [
            "type": "object",
            "properties": [
                "query": ["type": "string",
                          "description": "PubMed query, for example: (emotional numbing OR desensitization) AND moral development"],
                "max_results": ["type": "integer", "description": "How many papers to return, 1 to 10. Default 6."],
            ],
            "required": ["query"],
        ],
    ]

    /// The fields of one source, shared by save_references and write_lecture.
    static func sourceSchema(noteDescription: String) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "url", "source", "kind", "year", "authors", "pmid", "note"],
            "properties": [
                "title": ["type": "string"],
                "url": ["type": "string",
                        "description": "The exact URL from the search results. For PubMed papers: https://pubmed.ncbi.nlm.nih.gov/<PMID>/"],
                "source": ["type": "string", "description": "The site, publication or journal."],
                "kind": ["type": "string", "enum": Reference.Kind.allCases.map(\.rawValue)],
                "year": ["type": "string", "description": "Year published, or empty if unknown."],
                "authors": ["type": "string", "description": "Authors, or empty if unknown."],
                "pmid": ["type": "string", "description": "The PubMed ID for papers from pubmed_search; otherwise empty."],
                "note": ["type": "string", "description": noteDescription],
            ],
        ]
    }
}
