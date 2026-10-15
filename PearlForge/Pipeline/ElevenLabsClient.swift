import Foundation
import UniformTypeIdentifiers

/// A voice on the ElevenLabs account.
struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    /// ElevenLabs' category: "cloned", "professional", "generated", "premade", …
    let category: String?

    /// Voices the account owner made (clones and designed voices), as opposed
    /// to ElevenLabs' stock library.
    var isOwn: Bool {
        ["cloned", "professional", "generated"].contains(category ?? "")
    }
}

/// ElevenLabs calls: the voice list, speech-to-text (Scribe), and
/// text-to-speech in the chosen voice.
struct ElevenLabsClient {
    let apiKey: String

    // MARK: Voices

    /// The account's voices, its own voices first, then alphabetical.
    func listVoices() async throws -> [Voice] {
        var request = URLRequest(url: PipelineConfig.elevenLabsBase.appendingPathComponent("voices"),
                                 timeoutInterval: 60)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let data = try await PipelineHTTP.send(request, failure: "Could not list your voices")

        struct Response: Decodable {
            struct RawVoice: Decodable {
                let voiceID: String?
                let name: String?
                let category: String?

                enum CodingKeys: String, CodingKey {
                    case voiceID = "voice_id"
                    case name, category
                }
            }
            let voices: [RawVoice]?
        }

        let voices = try JSONDecoder().decode(Response.self, from: data).voices ?? []
        return voices
            .compactMap { raw -> Voice? in
                guard let id = raw.voiceID, !id.isEmpty else { return nil }
                return Voice(id: id, name: raw.name ?? "(unnamed voice)", category: raw.category)
            }
            .sorted { lhs, rhs in
                if lhs.isOwn != rhs.isOwn { return lhs.isOwn }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: Speech-to-text

    /// A faithful transcript of the recording at `fileURL`.
    func transcribe(audioAt fileURL: URL) async throws -> String {
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        var form = MultipartForm()
        form.addField("model_id", PipelineConfig.transcriptionModel)
        // Keep the transcript plain: no "(laughter)" style event tags, and no
        // speaker diarisation (this is one person thinking aloud).
        form.addField("tag_audio_events", "false")
        form.addField("diarize", "false")
        form.addFile("file", filename: fileURL.lastPathComponent, mimeType: mimeType,
                     data: try Data(contentsOf: fileURL))

        var request = URLRequest(url: PipelineConfig.elevenLabsBase.appendingPathComponent("speech-to-text"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body
        let data = try await PipelineHTTP.send(request, failure: "Transcription failed")

        struct Response: Decodable { let text: String? }
        let text = (try JSONDecoder().decode(Response.self, from: data).text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PipelineError(message: "The transcription came back empty. Is the recording audible?")
        }
        return text
    }

    // MARK: Text-to-speech

    /// Speech for `text` in the given voice, as MP3 data. Long text is spoken
    /// in chunks, each told its neighbours so the delivery stays continuous.
    func synthesize(_ text: String, voiceID: String) async throws -> Data {
        guard !voiceID.isEmpty else {
            throw PipelineError(message: "No voice is selected. Pick your ElevenLabs voice in Settings first.")
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PipelineError(message: "There is no text to turn into speech.")
        }

        let url = PipelineConfig.elevenLabsBase
            .appendingPathComponent("text-to-speech")
            .appendingPathComponent(voiceID)
        let chunks = Self.splitForSpeech(text)
        var audio = Data()
        for (index, chunk) in chunks.enumerated() {
            var body = ["text": chunk, "model_id": PipelineConfig.speechModel]
            // Pass neighbouring text so prosody stays continuous across chunks.
            if index > 0 { body["previous_text"] = chunks[index - 1] }
            if index < chunks.count - 1 { body["next_text"] = chunks[index + 1] }

            var request = URLRequest(url: url, timeoutInterval: PipelineConfig.requestTimeout)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(body)
            audio.append(try await PipelineHTTP.send(request, failure: "Voice generation failed"))
        }
        return audio
    }

    /// Splits long text into chunks on paragraph, then sentence, boundaries.
    /// A straight port of the Pinokio build's _split_for_tts.
    static func splitForSpeech(_ text: String, limit: Int = PipelineConfig.speechChunkCharacters) -> [String] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var buffer = ""
        for piece in split(text, on: #"\n\s*\n"#) {
            let sentences = split(piece.trimmingCharacters(in: .whitespacesAndNewlines), on: #"(?<=[.!?])\s+"#)
            for sentence in sentences where !sentence.isEmpty {
                if buffer.count + sentence.count + 1 > limit && !buffer.isEmpty {
                    chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    buffer = ""
                }
                buffer = (buffer + " " + sentence).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !buffer.isEmpty {
                chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer = ""
            }
        }
        let nonEmpty = chunks.filter { !$0.isEmpty }
        return nonEmpty.isEmpty ? [text] : nonEmpty
    }

    /// Like Python's re.split: the pieces between matches, empty ones included.
    private static func split(_ text: String, on pattern: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var pieces: [String] = []
        var start = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            pieces.append(ns.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = match.range.location + match.range.length
        }
        pieces.append(ns.substring(from: start))
        return pieces
    }
}
