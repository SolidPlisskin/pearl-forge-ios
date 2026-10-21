import Foundation

/// One run of a recording through the forge: a refinement (with the mode and
/// any request you gave) and that refinement spoken in your voice.
struct Pearl: Codable, Identifiable, Equatable {
    var id: UUID
    var number: Int
    var created: Date
    var mode: RefinementMode
    /// What you asked to be different for this version, if anything.
    var notes: String?
    /// The model that wrote it; differs from the requested model only when
    /// Anthropic's fallback stepped in.
    var refinedBy: String?
    /// The AI service that wrote it ("anthropic", "openai", …).
    var polisher: String?
    var voiceID: String?
    var textFile: String
    var audioFile: String?

    enum CodingKeys: String, CodingKey {
        case id, number, created, mode, notes, polisher
        case refinedBy = "refined_by"
        case voiceID = "voice_id"
        case textFile = "text_file"
        case audioFile = "audio_file"
    }

    /// "pearl-02-tighten", the start of a pearl's file names.
    static func baseName(number: Int, mode: RefinementMode) -> String {
        "pearl-\(String(format: "%02d", number))-\(mode.rawValue)"
    }
}

/// A piece of reading found for a recording: a research paper, essay,
/// article or blog post that relates to the thought.
struct Reference: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case research, article, essay, blog, book, other

        var title: String {
            switch self {
            case .research: return "Research"
            case .article: return "Article"
            case .essay: return "Essay"
            case .blog: return "Blog post"
            case .book: return "Book"
            case .other: return "Other"
            }
        }

        var symbol: String {
            switch self {
            case .research: return "graduationcap"
            case .article: return "newspaper"
            case .essay: return "text.book.closed"
            case .blog: return "text.bubble"
            case .book: return "book"
            case .other: return "link"
            }
        }
    }

    var id: UUID
    var title: String
    var url: String
    /// The site or journal: "The Atlantic", "JAMA Pediatrics".
    var source: String
    var kind: Kind
    var year: String?
    var authors: String?
    /// How it relates to the thought, in a sentence or two.
    var note: String
    /// The PubMed id, for papers found through PubMed.
    var pmid: String?
    var found: Date
}

/// What a lecture was asked for, and what it cost.
struct LectureInfo: Codable, Equatable {
    var topic: String
    /// The length asked for, in minutes.
    var minutes: Int
    /// The Claude model that researched and wrote it.
    var model: String
    /// The language it was written in, when you chose one.
    var language: String?
    /// One sentence on what it covers.
    var summary: String?
    /// What Claude charged, worked out from the usage it reported.
    var claudeCost: Double?
    /// Claude's estimate before it started (unadjusted), so later estimates
    /// can learn how far off it runs.
    var estimatedClaudeCost: Double?
    var webSearches: Int?
    /// Characters in the spoken text: the ElevenLabs credits it used.
    var characters: Int?
    /// What 1,000 credits were worth on your ElevenLabs plan at the time.
    var dollarsPerThousandCredits: Double?

    /// What speaking it cost, when your plan's rate is known.
    var voiceCost: Double? {
        guard let characters, let rate = dollarsPerThousandCredits else { return nil }
        return Double(characters) / 1000 * rate
    }

    enum CodingKeys: String, CodingKey {
        case topic, minutes, model, language, summary, characters
        case claudeCost = "claude_cost"
        case estimatedClaudeCost = "estimated_claude_cost"
        case webSearches = "web_searches"
        case dollarsPerThousandCredits = "dollars_per_thousand_credits"
    }
}

/// The details saved alongside each recording as meta.json.
struct RecordingMeta: Codable, Equatable {
    var title: String
    var created: Date
    var originalFile: String?
    var favorite: Bool
    var pearls: [Pearl]
    /// Broad topics such as "Relationships" or "Work & Career". Nil until the
    /// recording has been sorted.
    var categories: [String]?
    /// One first-person sentence summing up the thought.
    var gist: String?
    var references: [Reference]
    /// True for text you typed rather than recorded; it has no original audio.
    var typed: Bool?
    /// Set for a lecture you asked for; its pearl is the lecture itself.
    var lecture: LectureInfo?

    var isTyped: Bool { typed == true }

    init(title: String, created: Date, originalFile: String?, favorite: Bool, pearls: [Pearl],
         categories: [String]? = nil, gist: String? = nil, references: [Reference] = [], typed: Bool? = nil,
         lecture: LectureInfo? = nil) {
        self.typed = typed
        self.lecture = lecture
        self.title = title
        self.created = created
        self.originalFile = originalFile
        self.favorite = favorite
        self.pearls = pearls
        self.categories = categories
        self.gist = gist
        self.references = references
    }

    enum CodingKeys: String, CodingKey {
        case title, created, favorite, pearls, categories, gist, references, typed, lecture
        case originalFile = "original_file"
        // The first version saved one refinement per recording at the top level.
        case mode
        case voiceID = "voice_id"
        case outputFile = "output_file"
        case refinedBy = "refined_by"
    }

    /// The fixed id given to the single refinement of a first-version recording.
    static let legacyPearlID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        created = try container.decode(Date.self, forKey: .created)
        originalFile = try container.decodeIfPresent(String.self, forKey: .originalFile)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        categories = try container.decodeIfPresent([String].self, forKey: .categories)
        gist = try container.decodeIfPresent(String.self, forKey: .gist)
        references = try container.decodeIfPresent([Reference].self, forKey: .references) ?? []
        typed = try container.decodeIfPresent(Bool.self, forKey: .typed)
        lecture = try container.decodeIfPresent(LectureInfo.self, forKey: .lecture)
        if let pearls = try container.decodeIfPresent([Pearl].self, forKey: .pearls) {
            self.pearls = pearls
        } else {
            // A first-version recording: its one refinement becomes pearl 1.
            pearls = [Pearl(id: Self.legacyPearlID,
                            number: 1,
                            created: created,
                            mode: try container.decodeIfPresent(RefinementMode.self, forKey: .mode) ?? .clean,
                            notes: nil,
                            refinedBy: try container.decodeIfPresent(String.self, forKey: .refinedBy),
                            polisher: PolisherProvider.anthropic.rawValue,
                            voiceID: try container.decodeIfPresent(String.self, forKey: .voiceID),
                            textFile: "refined_transcript.txt",
                            audioFile: try container.decodeIfPresent(String.self, forKey: .outputFile))]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(created, forKey: .created)
        try container.encodeIfPresent(originalFile, forKey: .originalFile)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(pearls, forKey: .pearls)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encodeIfPresent(gist, forKey: .gist)
        try container.encode(references, forKey: .references)
        try container.encodeIfPresent(typed, forKey: .typed)
        try container.encodeIfPresent(lecture, forKey: .lecture)
    }
}

/// A saved recording with its texts. The app keeps a copy of these so History
/// opens instantly and works offline; only audio is fetched on demand.
struct RecordingEntry: Codable, Identifiable, Equatable {
    var folderName: String
    var meta: RecordingMeta
    var transcript: String
    var pearlTexts: [UUID: String]

    var id: String { folderName }

    /// Newest pearl first.
    var pearlsNewestFirst: [Pearl] {
        meta.pearls.sorted { $0.number > $1.number }
    }

    func pearl(_ id: UUID) -> Pearl? {
        meta.pearls.first { $0.id == id }
    }

    /// The newest pearl that has audio, for playing a recording in a list.
    var latestSpokenPearl: Pearl? {
        pearlsNewestFirst.first { $0.audioFile != nil }
    }

    /// The newest pearl's text, or what you said if there's no pearl yet.
    var latestText: String {
        pearlsNewestFirst.first.flatMap { pearlTexts[$0.id] } ?? transcript
    }
}

/// How a recording is laid out on disk. Each recording has its own folder:
///
///     2026-10-15_143012_I_think_theres_a_decent/
///     ├── original.m4a               the unmodified recording
///     ├── original_transcript.txt    what you actually said
///     ├── pearl-01-clean.txt         each run through the forge…
///     ├── pearl-01-clean.mp3         …and that run in your voice
///     ├── pearl-02-tighten.txt
///     ├── pearl-02-tighten.mp3
///     └── meta.json
enum RecordingFiles {
    static let originalTranscriptName = "original_transcript.txt"
    static let metaName = "meta.json"

    /// A new recording's folder name, from its date and the first words of
    /// its first refinement.
    static func folderName(created: Date, refined: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return "\(formatter.string(from: created))_\(slug(refined))"
    }

    /// The first few words, letters and digits only, joined with underscores:
    /// "I_think_theres_a_decent". A port of the Pinokio build's _slug.
    static func slug(_ text: String, words: Int = 6, maxLength: Int = 40) -> String {
        let firstWords = text.split(whereSeparator: \.isWhitespace).prefix(words).joined(separator: " ")
        let kept = firstWords.filter { $0 == " " || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let joined = kept.split(separator: " ").joined(separator: "_")
        let slug = String(joined.prefix(maxLength))
        return slug.isEmpty ? "note" : slug
    }

    /// The first line of the refined text, as the Pinokio build titled them.
    static func title(for refined: String) -> String {
        String((refined.split(separator: "\n").first ?? "").prefix(80))
    }

    static func encodeMeta(_ meta: RecordingMeta) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(meta)
    }

    static func decodeMeta(_ data: Data) throws -> RecordingMeta {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingMeta.self, from: data)
    }

    /// A temporary copy of a pearl's audio named after the recording, for
    /// sharing: "I suspect emotional desensitization… – pearl 2.mp3".
    static func shareCopy(of audio: Data, title: String, pearlNumber: Int) throws -> URL {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        let cleaned = title.components(separatedBy: unsafe).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        let name = "\(cleaned.isEmpty ? "Pearl Forge" : String(cleaned.prefix(60))) – pearl \(pearlNumber).mp3"
        let url = URL.temporaryDirectory.appending(path: name)
        try audio.write(to: url, options: .atomic)
        return url
    }
}
