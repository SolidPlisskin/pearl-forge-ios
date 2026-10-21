import Foundation

/// Finds reading related to a recording (research papers from PubMed, and
/// essays, articles and blog posts from the web) using Claude with web search.
/// Every reference is checked against the actual search results, so a title
/// or link the AI made up is never saved.
struct ReferenceFinder {
    let apiKey: String
    let workspaceID: String?
    let model: String

    private static let maxReferences = 10

    struct Result {
        let references: [Reference]
        /// How many suggestions were dropped because they couldn't be matched
        /// to a real search result.
        let unverified: Int
    }

    func find(transcript: String, gist: String?, categories: [String]) async throws -> Result {
        let loop = ResearchLoop(apiKey: apiKey, workspaceID: workspaceID, model: model, system: Self.system,
                                finishTool: Self.saveTool, maxWebSearches: 6, maxSteps: 12,
                                failure: "Finding references failed",
                                nudge: "Please call save_references now with the references you found (an empty list is fine).")
        do {
            let outcome = try await loop.run(user: Self.userMessage(transcript, gist: gist, categories: categories))
            return Self.verify(outcome.input["references"] as? [[String: Any]] ?? [],
                               seenURLs: outcome.seenURLs, papers: outcome.papers)
        } catch let stop as ResearchLoop.Stop {
            let message = switch stop {
            case .refusal: "Claude declined to search for this recording."
            case .cutOff: "The search ran too long. Please try again."
            case .unfinished: "The search finished without saving any references. Please try again."
            case .tooManySteps: "The search took too many steps. Please try again."
            }
            throw PipelineError(message: message)
        }
    }

    // MARK: Checking the results

    /// Keeps only references that match a real search result. PubMed papers
    /// get their details from PubMed itself.
    static func verify(_ suggested: [[String: Any]], seenURLs: [String: String], papers: [String: PubMedPaper]) -> Result {
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
                    "items": ResearchLoop.sourceSchema(
                        noteDescription: "One or two sentences on what this source says that relates to the speaker's thought."),
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
