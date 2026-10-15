import Foundation

/// The details saved alongside each recording as meta.json. Keys match the
/// Pinokio build's meta.json, plus `refined_by`.
struct RecordingMeta: Codable {
    var title: String
    var created: Date
    var mode: RefinementMode
    var voiceID: String
    var originalFile: String?
    var outputFile: String?
    var favorite: Bool
    /// The model that wrote the refinement; differs from the requested model
    /// only when Anthropic's fallback stepped in.
    var refinedBy: String?

    enum CodingKeys: String, CodingKey {
        case title, created, mode, favorite
        case voiceID = "voice_id"
        case originalFile = "original_file"
        case outputFile = "output_file"
        case refinedBy = "refined_by"
    }

    /// The first line of the refined text, as the Pinokio build titled them.
    static func title(for refined: String) -> String {
        String((refined.split(separator: "\n").first ?? "").prefix(80))
    }
}

/// Each recording is saved in its own folder under Documents/Recordings, which
/// the Files app shows as On My iPhone › Pearl Forge › Recordings:
///
///     2026-10-15_143012_I_think_theres_a_decent/
///     ├── original.m4a               the unmodified recording
///     ├── original_transcript.txt    what you actually said
///     ├── refined_transcript.txt     the refined version
///     ├── pearl_forge_output.mp3     the refined version in your voice
///     └── meta.json
enum RecordingStore {
    static let originalTranscriptName = "original_transcript.txt"
    static let refinedTranscriptName = "refined_transcript.txt"
    static let outputName = "pearl_forge_output.mp3"
    static let metaName = "meta.json"

    static var recordingsDirectory: URL {
        URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    /// Creates the folder for a new recording, named from its date and the
    /// first words of the refined text.
    static func createFolder(created: Date, refined: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let name = "\(formatter.string(from: created))_\(slug(refined))"
        let folder = recordingsDirectory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
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

    static func writeMeta(_ meta: RecordingMeta, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(meta).write(to: folder.appending(path: metaName), options: .atomic)
    }

    static func readMeta(in folder: URL) throws -> RecordingMeta {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingMeta.self, from: Data(contentsOf: folder.appending(path: metaName)))
    }

    static func updateMeta(in folder: URL, _ change: (inout RecordingMeta) -> Void) throws {
        var meta = try readMeta(in: folder)
        change(&meta)
        try writeMeta(meta, in: folder)
    }
}
