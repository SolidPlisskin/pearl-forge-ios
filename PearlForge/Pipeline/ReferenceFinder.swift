import Foundation

/// Finds reading related to a recording (research papers from PubMed, and
/// essays, articles and blog posts from the web) using Claude with web search.
/// Every reference is checked against the actual search results, so a title
/// or link the AI made up is never saved.
struct ReferenceFinder {
    let apiKey: String
    let workspaceID: String?
    let model: String

    /// Models that support web search with dynamic filtering; others use the
    /// basic version.
    private static let dynamicSearchModels: Set<String> = [
        "claude-fable-5-1", "claude-fable-5", "claude-opus-5-5", "claude-opus-5",
        "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5-5", "claude-sonnet-5", "claude-sonnet-4-6",
    ]

    private static let maxSteps = 12
    private static let maxReferences = 10

    struct Result {
        let references: [Reference]
        /// How many suggestions were dropped because they couldn't be matched
        /// to a real search result.
        let unverified: Int
    }

    func find(transcript: String, gist: String?, categories: [String]) async throws -> Result {
        var messages: [[String: Any]] = [["role": "user", "content": Self.userMessage(transcript, gist: gist, categories: categories)]]
        var seenURLs: [String: String] = [:]
        var papers: [String: PubMedPaper] = [:]
        var nudged = false

        for _ in 0..<Self.maxSteps {
            let response = try await send(messages)
            let content = response["content"] as? [[String: Any]] ?? []
            Self.collectURLs(in: content, into: &seenURLs)

            switch response["stop_reason"] as? String {
            case "pause_turn":
                // A long search paused; send the turn back unchanged to resume.
                messages.append(["role": "assistant", "content": content])

            case "tool_use":
                let calls = content.filter { $0["type"] as? String == "tool_use" }
                if let save = calls.first(where: { $0["name"] as? String == "save_references" }) {
                    return Self.verify(save["input"], seenURLs: seenURLs, papers: papers)
                }
                var results: [[String: Any]] = []
                for call in calls {
                    results.append(await run(call, papers: &papers))
                }
                messages.append(["role": "assistant", "content": content])
                messages.append(["role": "user", "content": results])

            case "end_turn" where !nudged:
                // It stopped without saving; ask once more.
                nudged = true
                messages.append(["role": "assistant", "content": content])
                messages.append(["role": "user", "content": "Please call save_references now with the references you found (an empty list is fine)."])

            case "refusal":
                throw PipelineError(message: "Claude declined to search for this recording.")
            case "max_tokens":
                throw PipelineError(message: "The search ran too long. Please try again.")
            default:
                throw PipelineError(message: "The search finished without saving any references. Please try again.")
            }
        }
        throw PipelineError(message: "The search took too many steps. Please try again.")
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
            "system": Self.system,
            "messages": messages,
            "tools": [Self.webSearchTool(for: model), Self.pubMedTool, Self.saveTool],
        ]
        if AnthropicClient.fallbackModels.contains(model) {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        if AnthropicClient.adaptiveThinkingModels.contains(model) {
            body["thinking"] = ["type": "adaptive"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await PipelineHTTP.send(request, failure: "Finding references failed")
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PipelineError(message: "Finding references failed: the reply couldn't be read.")
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

    // MARK: Checking the results

    /// Keeps only references that match a real search result. PubMed papers
    /// get their details from PubMed itself.
    static func verify(_ input: Any?, seenURLs: [String: String], papers: [String: PubMedPaper]) -> Result {
        let suggested = (input as? [String: Any])?["references"] as? [[String: Any]] ?? []
        var kept: [Reference] = []
        var keptURLs = Set<String>()
        var unverified = 0

        for item in suggested {
            func field(_ key: String) -> String {
                (item[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let url = field("url")
            let pmid = [field("pmid"), pubMedID(in: url)].first { !$0.isEmpty && papers[$0] != nil } ?? ""

            var reference: Reference
            if let paper = papers[pmid] {
                reference = Reference(id: UUID(), title: paper.title.isEmpty ? field("title") : paper.title,
                                      url: paper.url, source: paper.journal.isEmpty ? "PubMed" : paper.journal,
                                      kind: .research, year: paper.year.isEmpty ? nil : paper.year,
                                      authors: paper.authorLine.isEmpty ? nil : paper.authorLine,
                                      note: field("note"), pmid: paper.pmid, found: Date())
            } else if let normalized = normalize(url), let found = seenURLs[normalized] {
                // Saved with the address exactly as the search found it.
                reference = Reference(id: UUID(), title: field("title"), url: found, source: field("source"),
                                      kind: Reference.Kind(rawValue: field("kind")) ?? .other,
                                      year: field("year").isEmpty ? nil : field("year"),
                                      authors: field("authors").isEmpty ? nil : field("authors"),
                                      note: field("note"), pmid: nil, found: Date())
            } else {
                unverified += 1
                continue
            }
            if reference.title.isEmpty { reference.title = reference.source }
            guard let key = normalize(reference.url), keptURLs.insert(key).inserted else { continue }
            kept.append(reference)
        }
        return Result(references: Array(kept.prefix(maxReferences)), unverified: unverified)
    }

    /// Every URL that appeared in web search or fetch results, keyed by its
    /// normalized form.
    static func collectURLs(in value: Any, into urls: inout [String: String]) {
        if let list = value as? [Any] {
            for item in list { collectURLs(in: item, into: &urls) }
        } else if let object = value as? [String: Any] {
            let resultTypes: Set<String> = ["web_search_result", "web_search_result_location", "web_fetch_result"]
            if let type = object["type"] as? String, resultTypes.contains(type),
               let url = object["url"] as? String, let normalized = normalize(url), urls[normalized] == nil {
                urls[normalized] = url
            }
            for (_, child) in object { collectURLs(in: child, into: &urls) }
        }
    }

    /// A URL reduced to host, path and query, so small differences
    /// (http/https, "www.", a trailing slash, a #section) still match.
    static func normalize(_ string: String) -> String? {
        guard var components = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        components.fragment = nil
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        let query = components.percentEncodedQuery.map { "?" + $0 } ?? ""
        return bareHost + path + query
    }

    /// "12345678" from a pubmed.ncbi.nlm.nih.gov link.
    static func pubMedID(in url: String) -> String {
        guard let components = URLComponents(string: url), components.host?.contains("pubmed.ncbi.nlm.nih.gov") == true
        else { return "" }
        return components.path.split(separator: "/").first { $0.allSatisfy(\.isNumber) }.map(String.init) ?? ""
    }

    // MARK: Prompt and tools

    static let system = """
    You are Pearl Forge's research assistant. The speaker recorded a voice note while thinking out loud, and you are given what they said. Find reading that would help them think further about the ideas in it.

    - Peer-reviewed research: use pubmed_search when the thought touches on something researchers study, such as relationships, parenting, emotions, behaviour, health, sleep, learning or work. Read the abstracts and keep only papers that are genuinely on point.
    - Essays, long-form articles and thoughtful blog posts: use web search. Prefer substantive, reputable sources (established publications, universities, respected writers) over listicles, SEO content, product pages and forums.
    - Aim for 3 to 8 items in total, with a mix of kinds when good ones exist. A few strong items beat a long list. If nothing good exists, save an empty list.
    - Never invent a source, title, author or URL. Only save items that appeared in your search results, with their exact URL.
    - For each item, write a short note on what it says that relates to the speaker's thought, in plain language. Describe the source; don't give advice and don't add opinions of your own.

    When you're done, call save_references exactly once.
    """

    static func userMessage(_ transcript: String, gist: String?, categories: [String]) -> String {
        var message = "What I said:\n\n\(transcript)"
        if !categories.isEmpty { message += "\n\nTopics: \(categories.joined(separator: ", "))" }
        if let gist, !gist.isEmpty { message += "\nIn short: \(gist)" }
        return message
    }

    static func webSearchTool(for model: String) -> [String: Any] {
        ["type": dynamicSearchModels.contains(model) ? "web_search_20260209" : "web_search_20250305",
         "name": "web_search",
         "max_uses": 6]
    }

    static let pubMedTool: [String: Any] = [
        "name": "pubmed_search",
        "description": "Search PubMed, the US National Library of Medicine's database of peer-reviewed biomedical and life-sciences research (including psychology, psychiatry, child development, relationships and health). Returns titles, journals, years and abstracts. Call this whenever the thought touches on something researchers study. Use PubMed search terms, not a sentence: a few key terms joined with AND/OR.",
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

    static let saveTool: [String: Any] = [
        "name": "save_references",
        "description": "Save the references you chose for the speaker. Call this exactly once, after searching. Include only items that appeared in your web search or pubmed_search results, with their exact URL.",
        "strict": true,
        "input_schema": [
            "type": "object",
            "additionalProperties": false,
            "required": ["references"],
            "properties": [
                "references": [
                    "type": "array",
                    "items": [
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
                            "note": ["type": "string",
                                     "description": "One or two sentences on what this source says that relates to the speaker's thought."],
                        ],
                    ],
                ],
            ],
        ],
    ]
}

extension Forge {
    /// Finds reading related to a recording, using the Claude model chosen in
    /// the AI tab.
    static func findReferences(for entry: RecordingEntry, claudeModel: String) async throws -> ReferenceFinder.Result {
        guard let key = KeychainStore.read(.anthropicKey) else {
            throw PipelineError(message: "Finding references uses Claude's web search. Add your Claude key in the AI tab first.")
        }
        guard !entry.transcript.isEmpty else {
            throw PipelineError(message: "This recording's transcript couldn't be loaded.")
        }
        return try await ReferenceFinder(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID), model: claudeModel)
            .find(transcript: entry.transcript, gist: entry.meta.gist, categories: entry.meta.categories ?? [])
    }
}
