import Foundation

/// The lecture lengths on offer, and what each one means in words, ElevenLabs
/// credits and searches.
enum LectureLength {
    static let options = [3, 5, 10, 15, 20]
    static let standard = 10

    /// Spoken English runs at about 150 words a minute.
    static func words(minutes: Int) -> Int { minutes * 150 }

    /// The longest a lecture should run: 10% over.
    static func maxWords(minutes: Int) -> Int { words(minutes: minutes) * 11 / 10 }

    /// ElevenLabs credits for speaking it, one per character. Lectures run
    /// about six characters a word (counting spaces and punctuation), and in
    /// live tests Claude wrote up to its 10% allowance, so about 1,000 a
    /// minute.
    static func characters(minutes: Int) -> Int { minutes * 1_000 }

    /// How many web searches Claude may run. Longer lectures cover more
    /// ground; PubMed searches are free and come on top.
    static func webSearches(minutes: Int) -> Int {
        switch minutes {
        case ..<5: return 4
        case ..<10: return 5
        case ..<15: return 7
        case ..<20: return 8
        default: return 10
        }
    }

    /// The offered length closest to the one asked for.
    static func nearest(to minutes: Int) -> Int {
        options.min { abs($0 - minutes) < abs($1 - minutes) } ?? standard
    }
}

/// "Give a lecture on the science of sleep", spotted in what you said or typed.
struct LectureRequest: Equatable {
    var topic: String
    /// The length you asked for ("a five-minute lecture"), if you said one.
    var minutes: Int?

    /// The request in `text`, when the text starts by asking for a lecture:
    /// "Give a lecture on…", "Can you give me a 5-minute lecture about…",
    /// "Lecture me on…". A thought that merely mentions a lecture isn't one.
    static func parse(_ text: String) -> LectureRequest? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range) else { return nil }
        func group(_ name: String) -> String? {
            Range(match.range(withName: name), in: text).map { String(text[$0]) }
        }
        var topic = group("topic") ?? group("topic2") ?? ""
        var minutes = group("length").flatMap(number) ?? group("size").map(sizeMinutes)

        // "…on jazz for about ten minutes": the length said at the end.
        let topicRange = NSRange(topic.startIndex..., in: topic)
        if let tail = trailingLength.firstMatch(in: topic, range: topicRange),
           let digits = Range(tail.range(withName: "length"), in: topic).flatMap({ number(String(topic[$0])) }),
           let whole = Range(tail.range, in: topic) {
            minutes = digits
            topic.removeSubrange(whole)
        }
        topic = topic.replacingOccurrences(of: #"^(?:(?:uh|um|er|erm|like|so)\b[\s,]*)+"#, with: "",
                                           options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—.!?…\"“”").union(.whitespacesAndNewlines))
        // "Give a lecture on" with nothing after it isn't a request yet.
        let prepositions: Set = ["on", "about", "regarding", "covering", "concerning", "explaining", "into", "of", "for"]
        guard topic.count >= 2, !prepositions.contains(topic.lowercased()) else { return nil }
        return LectureRequest(topic: topic, minutes: minutes)
    }

    private static let lead = #"""
        ^\s*(?:(?:hey|hi|ok|okay|so|um|uh|er|erm|well|alright|all\s+right|right|now)[\s,]+)*
        (?:pearl(?:\s+forge)?[\s,:]+)?(?:please[\s,]+)?
        """#

    private static let lengthWords = "one|two|three|four|five|six|seven|eight|nine|ten|twelve|fifteen|twenty|thirty"

    private static let pattern = try! NSRegularExpression(pattern: lead + #"""
        (?:
          (?:
            (?:(?:can|could|would|will)\s+you\s+(?:please\s+)?)?
            (?:give|do|make|write|prepare|create|deliver|record|play|read)\s+(?:(?:me|us)\s+)?
            | i\s*(?:want|need|would\s+like|['’]?d\s+like)\s+(?:to\s+hear\s+)?
          )
          (?:a|an|the)?\s*
          (?:(?<length>\d{1,2}|\#(lengthWords))[\s-]*min(?:ute)?s?(?:[\s-]+long)?\s+
            |(?<size>short|quick|brief|little|long|longer|full|detailed|in[\s-]depth|deep)\s+)?
          lecture\b
          (?:[\s,:;\-–—]+(?:on|about|regarding|covering|concerning|explaining|into|of|for)\b)?
          [\s,:;\-–—]*(?<topic>\S.*?)
        | lecture\s+(?:me|us)\s+(?:on|about)\s+(?<topic2>\S.*?)
        )
        [\s.!?…]*$
        """#, options: [.caseInsensitive, .dotMatchesLineSeparators, .allowCommentsAndWhitespace])

    private static let trailingLength = try! NSRegularExpression(pattern: #"""
        [\s,;\-–—]+(?:(?:for|lasting|taking|that['’]?s|that\s+is|of)\s+)?(?:(?:about|around|roughly|maybe)\s+)?
        (?<length>\d{1,2}|\#(lengthWords))[\s-]*min(?:ute)?s?(?:\s+long)?$
        """#, options: [.caseInsensitive, .allowCommentsAndWhitespace])

    private static func number(_ text: String) -> Int? {
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
                     "nine": 9, "ten": 10, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30]
        let value = Int(text) ?? words[text.lowercased()]
        return value.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func sizeMinutes(_ size: String) -> Int {
        ["short", "quick", "brief", "little"].contains(size.lowercased()) ? 5 : 20
    }
}

/// Instructions for researching and writing a lecture.
enum LecturePrompt {
    static func system(minutes: Int, language: SpeechLanguage?) -> String {
        let languageRule = language.map {
            "- Write the lecture in \($0.name), the way a native speaker would, even when your sources are in other languages."
        } ?? "- Write the lecture in the language the request is in."
        return """
        You are Pearl Forge's lecture writer. Someone asked for a lecture on a topic. Research it, then write the lecture. It will be read aloud in their own cloned voice, so it should sound like them giving a clear, engaging talk.

        Research first, as much as you need to get the substance right:
        - Use pubmed_search when the topic touches on anything researchers study: health, medicine, the body, the mind, emotions, relationships, parenting, behaviour, learning, sleep or nutrition. Read the abstracts, and give more weight to systematic reviews, meta-analyses and large studies than to single small ones.
        - Use web search for background, history, context and the current state of understanding. Prefer universities, established publications, government and professional bodies, and respected writers over SEO content, product pages and forums.

        Then write the lecture and call write_lecture exactly once.

        The lecture:
        - About \(LectureLength.words(minutes: minutes)) words, which is about \(minutes) minutes spoken, and no more than \(LectureLength.maxWords(minutes: minutes)) words.
        - Written for the ear: plain, natural spoken sentences. No headings, lists, bullet points, tables, emoji, markdown, URLs or citation markers. Write numbers, dates and units the way they're said aloud.
        - Shaped like a good talk: open with why the topic matters, say briefly where you're going, take the main ideas in a sensible order with concrete examples, and close with a short recap of the key points.
        - Accurate and honest: every factual claim must come from your research. Say plainly where evidence is mixed, early or disputed, and never overstate certainty. Name sources in passing where it helps ("a 2019 review of 30 studies found…", "according to the CDC…"). Never invent studies, numbers, quotes or sources.
        - Spoken as the person giving the talk, in the first person where it's natural, but never invent experiences, credentials or stories for them.
        - Educational rather than personal advice. For health, legal or money topics, explain what's known and mention once that individual situations differ.
        \(languageRule)

        In write_lecture, list the sources the lecture actually draws on, using only items from your search results, with their exact URLs.
        """
    }

    static func user(topic: String) -> String {
        "Give a lecture on: \(topic)"
    }

    static let writeTool: [String: Any] = [
        "name": "write_lecture",
        "description": "Hand over the finished lecture. Call this exactly once, after researching.",
        "strict": true,
        "input_schema": [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "summary", "script", "sources"],
            "properties": [
                "title": ["type": "string", "description": "A short title for the lecture, at most eight words."],
                "summary": ["type": "string", "description": "One sentence on what the lecture covers."],
                "script": ["type": "string",
                           "description": "The whole lecture exactly as it should be spoken, with paragraphs separated by blank lines."],
                "sources": [
                    "type": "array",
                    "items": ResearchLoop.sourceSchema(noteDescription: "One sentence on what the lecture uses from this source."),
                ],
            ],
        ],
    ]
}

/// A researched lecture, ready to speak.
struct WrittenLecture {
    let title: String
    let summary: String
    let script: String
    /// The sources it draws on, each one checked against the search results.
    let references: [Reference]
    /// Sources Claude named that couldn't be matched to a search result.
    let unverified: Int
    let usage: ClaudeUsage
    /// The model that wrote it.
    let model: String
    /// What Claude charged, from the usage it reported; nil for a model whose
    /// prices Pearl Forge doesn't know.
    var cost: Double? { ClaudePrice.byModel[model].map { $0.cost(of: usage) } }
}

/// Researches a topic with Claude (the web and PubMed) and writes a lecture
/// about it, with its sources.
struct LectureWriter {
    let apiKey: String
    let workspaceID: String?
    let model: String

    func write(topic: String, minutes: Int, language: SpeechLanguage?,
               onProgress: (@MainActor (ResearchProgress) -> Void)? = nil) async throws -> WrittenLecture {
        let loop = ResearchLoop(apiKey: apiKey, workspaceID: workspaceID, model: model,
                                system: LecturePrompt.system(minutes: minutes, language: language),
                                finishTool: LecturePrompt.writeTool,
                                maxWebSearches: LectureLength.webSearches(minutes: minutes), maxSteps: 16,
                                failure: "The lecture failed",
                                nudge: "Please write the lecture now and call write_lecture with it.",
                                onProgress: onProgress)
        let outcome: ResearchLoop.Outcome
        do {
            outcome = try await loop.run(user: LecturePrompt.user(topic: topic))
        } catch let stop as ResearchLoop.Stop {
            let message = switch stop {
            case .refusal: "Claude declined to research this topic."
            case .cutOff: "The lecture ran longer than Claude can write in one go. Try a shorter length."
            case .unfinished: "Claude stopped before writing the lecture. Please try again."
            case .tooManySteps: "The research took too many steps. Please try again."
            }
            throw PipelineError(message: message)
        }
        func field(_ key: String) -> String {
            (outcome.input[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let script = Self.forSpeaking(field("script"))
        guard script.count >= 200 else {
            throw PipelineError(message: "The lecture came back empty. Please try again.")
        }
        let checked = ReferenceFinder.verify(outcome.input["sources"] as? [[String: Any]] ?? [],
                                             seenURLs: outcome.seenURLs, papers: outcome.papers)
        let title = field("title")
        return WrittenLecture(title: title.isEmpty ? topic.prefix(1).uppercased() + topic.dropFirst() : title,
                              summary: field("summary"), script: script, references: checked.references,
                              unverified: checked.unverified, usage: outcome.usage, model: outcome.answeredBy)
    }

    /// Drops any markdown that slipped in (headings, bold), which would
    /// otherwise be read out or trip up the voice.
    static func forSpeaking(_ script: String) -> String {
        script.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Forge {
    /// Researches and writes a lecture with the given Claude model.
    static func writeLecture(topic: String, minutes: Int, language: SpeechLanguage?, model: String,
                             onProgress: (@MainActor (ResearchProgress) -> Void)? = nil) async throws -> WrittenLecture {
        guard let key = KeychainStore.read(.anthropicKey) else {
            throw PipelineError(message: "Lectures are researched with Claude's web search. Add your Claude key in the AI tab first.")
        }
        return try await LectureWriter(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID), model: model)
            .write(topic: topic, minutes: minutes, language: language, onProgress: onProgress)
    }
}
