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

/// The details saved alongside each recording as meta.json.
struct RecordingMeta: Codable, Equatable {
    var title: String
    var created: Date
    var originalFile: String?
    var favorite: Bool
    var pearls: [Pearl]

    init(title: String, created: Date, originalFile: String?, favorite: Bool, pearls: [Pearl]) {
        self.title = title
        self.created = created
        self.originalFile = originalFile
        self.favorite = favorite
        self.pearls = pearls
    }

    enum CodingKeys: String, CodingKey {
        case title, created, favorite, pearls
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
