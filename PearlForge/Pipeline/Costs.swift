import Foundation

/// What Claude calls used, as the API reports it, for working out what they
/// cost.
struct ClaudeUsage: Codable, Equatable {
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0
    var webSearches = 0

    /// Adds one response's "usage".
    mutating func add(_ usage: [String: Any]?) {
        guard let usage else { return }
        input += usage["input_tokens"] as? Int ?? 0
        cacheWrite += usage["cache_creation_input_tokens"] as? Int ?? 0
        cacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
        output += usage["output_tokens"] as? Int ?? 0
        webSearches += (usage["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int ?? 0
    }
}

/// Anthropic's list prices in dollars per million tokens, from
/// platform.claude.com/docs/en/about-claude/pricing (October 2026).
struct ClaudePrice {
    let input: Double
    /// Writing to the 5-minute prompt cache.
    let cacheWrite: Double
    let cacheRead: Double
    let output: Double

    /// Web search is $10 per 1,000 searches, on top of the tokens it reads.
    static let perWebSearch = 0.01

    static let byModel: [String: ClaudePrice] = [
        "claude-opus-5-5": ClaudePrice(input: 4, cacheWrite: 5, cacheRead: 0.20, output: 20),
        "claude-sonnet-5-5": ClaudePrice(input: 2, cacheWrite: 2.50, cacheRead: 0.10, output: 10),
        "claude-fable-5-1": ClaudePrice(input: 10, cacheWrite: 12.50, cacheRead: 0.25, output: 50),
    ]

    func cost(of usage: ClaudeUsage) -> Double {
        let tokens = Double(usage.input) * input + Double(usage.cacheWrite) * cacheWrite
            + Double(usage.cacheRead) * cacheRead + Double(usage.output) * output
        return tokens / 1_000_000 + Double(usage.webSearches) * Self.perWebSearch
    }
}

/// Your ElevenLabs plan's credits. Speaking with Multilingual v2 uses one
/// credit per character.
struct VoiceCredits: Equatable {
    let tier: String
    let used: Int
    let limit: Int
    let resets: Date?

    var remaining: Int { max(0, limit - used) }

    /// Roughly what 1,000 credits are worth on this plan: its monthly price
    /// over its monthly credits (elevenlabs.io/pricing, October 2026). Nil on
    /// the free plan, where credits cost nothing.
    var dollarsPerThousand: Double? { Self.dollarsPerThousand(tier: tier) }

    static func dollarsPerThousand(tier: String?) -> Double? {
        let tier = tier?.lowercased() ?? ""
        if tier.hasPrefix("free") { return nil }
        if tier.hasPrefix("starter") { return 0.20 }                       // $6 for 30,000
        if ["pro", "scale", "business"].contains(where: tier.hasPrefix) { return 0.165 } // $99 for 600,000
        return 0.18                                                        // Creator: $22 for 121,000
    }
}

/// What a lecture should cost, worked out before anything is spent.
struct LectureEstimate: Equatable {
    /// Claude's research and writing. A range, because how much it reads
    /// varies from topic to topic.
    let claudeLow: Double
    let claudeHigh: Double
    /// The middle of the range before it was adjusted by past lectures. Saved
    /// with the lecture so later estimates can learn how far off it was.
    let claudeBase: Double
    /// ElevenLabs credits for speaking it: one per character.
    let credits: Int
    /// What those credits are worth on your plan.
    let voiceDollars: Double?
    /// How many of your past lectures adjusted the Claude estimate.
    let learnedFrom: Int

    var totalLow: Double { claudeLow + (voiceDollars ?? 0) }
    var totalHigh: Double { claudeHigh + (voiceDollars ?? 0) }

    /// Typical Claude usage for a lecture of a given length, from live runs
    /// with Claude Sonnet 5.5 (October 2026): a 5-minute lecture researched on
    /// PubMed alone used 11,000 tokens written to the cache, 12,000 read back
    /// and 3,600 out ($0.07); a 10-minute one with 5 web searches used 43,500,
    /// 31,000 and 6,100 ($0.22). Each web search adds what it read; the
    /// writing (and the thinking behind it) grows with the length.
    static func typicalUsage(minutes: Int) -> ClaudeUsage {
        let searches = Double(LectureLength.webSearches(minutes: minutes)) * 0.6
        let scriptTokens = Double(LectureLength.words(minutes: minutes)) * 1.4
        return ClaudeUsage(input: 50,
                           cacheWrite: Int(7_000 + searches * 6_500 + scriptTokens * 1.5),
                           cacheRead: Int(9_000 + searches * 4_500),
                           output: Int(1_000 + scriptTokens * 2.4),
                           webSearches: Int(searches.rounded()))
    }

    /// The estimate for a lecture. `pastRatios` are past lectures' actual
    /// Claude cost over their unadjusted estimate, newest first; they nudge
    /// this estimate toward what your lectures really cost.
    static func make(minutes: Int, model: String, credits: VoiceCredits?, pastRatios: [Double]) -> LectureEstimate? {
        guard let price = ClaudePrice.byModel[model] else { return nil }
        let base = price.cost(of: typicalUsage(minutes: minutes))
        let recent = pastRatios.prefix(5).sorted()
        let factor = recent.isEmpty ? 1 : min(4, max(0.25, recent[recent.count / 2]))
        let middle = base * factor
        // Wide until a few real lectures have shown how far off it runs.
        let (low, high) = recent.count >= 2 ? (0.75, 1.3) : (0.5, 1.5)
        let characters = LectureLength.characters(minutes: minutes)
        let rate = credits.map(\.dollarsPerThousand) ?? VoiceCredits.dollarsPerThousand(tier: nil)
        return LectureEstimate(claudeLow: middle * low, claudeHigh: middle * high, claudeBase: base,
                               credits: characters, voiceDollars: rate.map { Double(characters) / 1000 * $0 },
                               learnedFrom: recent.count)
    }
}

extension Double {
    /// "$0.27", "$1.60", or "under 1¢".
    var dollars: String {
        self < 0.01 ? "under 1¢" : formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

/// "$0.20–0.45", or a single amount when both ends round the same.
func dollarRange(_ low: Double, _ high: Double) -> String {
    let lowText = low.dollars, highText = high.dollars
    guard lowText != highText else { return lowText }
    return lowText + "–" + highText.replacingOccurrences(of: "$", with: "")
}
