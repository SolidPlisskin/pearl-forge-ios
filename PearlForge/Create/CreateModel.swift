import AVFoundation
import Observation
import UIKit

/// Drives the Create screen: record (or import) a voice note, then transcribe
/// it, refine it, save it, and speak it back in your voice. A failed step can
/// be retried without repeating the steps before it.
@MainActor
@Observable
final class CreateModel {
    enum Step: Equatable {
        case transcribing, refining, speaking

        var progressLabel: String {
            switch self {
            case .transcribing: return "Transcribing…"
            case .refining: return "Refining (keeping your meaning)…"
            case .speaking: return "Speaking it back in your voice…"
            }
        }
    }

    private static let modeKey = "refinementMode"
    private static let pendingRecordingURL = URL.temporaryDirectory.appending(path: "pending-recording.m4a")

    let recorder = VoiceRecorder()
    let player = AudioPlayback()

    var mode: RefinementMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    /// The voice note waiting to be processed, recorded or imported.
    private(set) var source: URL?
    private(set) var sourceDuration: TimeInterval?
    private(set) var step: Step?
    private(set) var errorMessage: String?
    private(set) var microphoneDenied = false

    private(set) var transcript: String?
    /// The refined text, editable before regenerating the audio.
    var refinedText = ""
    private(set) var refinedMode: RefinementMode?
    /// Where this recording is saved; set once the refinement is done.
    private(set) var folder: URL?
    private(set) var outputURL: URL?
    /// The text the current audio was made from.
    private var spokenText: String?

    init() {
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(RefinementMode.init) ?? .clean
    }

    var isBusy: Bool { step != nil }

    /// True once you've edited the refined text since the audio was made.
    var hasUnspokenEdits: Bool {
        guard let spokenText else { return false }
        return refinedText.trimmingCharacters(in: .whitespacesAndNewlines) != spokenText
    }

    // MARK: Recording

    func startRecording() async {
        guard await VoiceRecorder.requestPermission() else {
            microphoneDenied = true
            return
        }
        microphoneDenied = false
        startNew()
        do {
            try recorder.start(to: Self.pendingRecordingURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        let duration = recorder.stop()
        guard duration >= 1 else {
            errorMessage = "That recording was too short. Hold on a little longer next time."
            return
        }
        source = Self.pendingRecordingURL
        sourceDuration = duration
    }

    /// Uses an existing audio file (from Voice Memos, Files, …) instead of a
    /// new recording.
    func importRecording(from url: URL) {
        startNew()
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let copy = URL.temporaryDirectory.appending(path: "imported-recording.\(ext)")
        do {
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: url, to: copy)
            source = copy
            sourceDuration = (try? AVAudioPlayer(contentsOf: copy))?.duration
        } catch {
            errorMessage = "Couldn't open that file: \(error.localizedDescription)"
        }
    }

    /// Clears the screen for a new voice note. Anything already refined is
    /// saved in its folder, so nothing is lost.
    func startNew() {
        player.unload()
        source = nil
        sourceDuration = nil
        errorMessage = nil
        transcript = nil
        refinedText = ""
        refinedMode = nil
        folder = nil
        outputURL = nil
        spokenText = nil
    }

    // MARK: Pipeline

    /// Runs whichever steps haven't succeeded yet: transcribe, refine (and
    /// save), then speak.
    func refineAndSpeak(voiceID: String) async {
        guard let source, step == nil else { return }
        errorMessage = nil
        // Give the requests time to finish if the phone is locked mid-way.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Refine and speak")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        do {
            let eleven = try elevenLabs()
            if transcript == nil {
                step = .transcribing
                transcript = try await eleven.transcribe(audioAt: source)
            }
            if folder == nil, let transcript {
                step = .refining
                let refinement = try await anthropic().refine(transcript, mode: mode)
                try save(transcript: transcript, refinement: refinement, source: source, voiceID: voiceID)
            }
            step = .speaking
            try await speak(voiceID: voiceID, using: eleven)
        } catch {
            errorMessage = error.localizedDescription
        }
        step = nil
    }

    /// Re-speaks the (edited) refined text and replaces the saved audio.
    func regenerateAudio(voiceID: String) async {
        guard folder != nil, step == nil else { return }
        errorMessage = nil
        step = .speaking
        do {
            try await speak(voiceID: voiceID, using: try elevenLabs())
        } catch {
            errorMessage = error.localizedDescription
        }
        step = nil
    }

    private func save(transcript: String, refinement: Refinement, source: URL, voiceID: String) throws {
        let created = Date()
        let folder = try RecordingStore.createFolder(created: created, refined: refinement.text)
        let originalName = "original.\(source.pathExtension)"
        var originalFile: String? = originalName
        do {
            try FileManager.default.copyItem(at: source, to: folder.appending(path: originalName))
        } catch {
            originalFile = nil
        }
        try transcript.write(to: folder.appending(path: RecordingStore.originalTranscriptName),
                             atomically: true, encoding: .utf8)
        try refinement.text.write(to: folder.appending(path: RecordingStore.refinedTranscriptName),
                                  atomically: true, encoding: .utf8)
        try RecordingStore.writeMeta(RecordingMeta(title: RecordingMeta.title(for: refinement.text),
                                                   created: created,
                                                   mode: mode,
                                                   voiceID: voiceID,
                                                   originalFile: originalFile,
                                                   outputFile: nil,
                                                   favorite: false,
                                                   refinedBy: refinement.model),
                                     in: folder)
        self.folder = folder
        refinedText = refinement.text
        refinedMode = mode
    }

    /// Saves the current refined text, speaks it, and plays the result.
    private func speak(voiceID: String, using eleven: ElevenLabsClient) async throws {
        guard let folder else { return }
        let text = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PipelineError(message: "There's no text to turn into speech.")
        }
        try text.write(to: folder.appending(path: RecordingStore.refinedTranscriptName),
                       atomically: true, encoding: .utf8)

        player.unload()
        let audio = try await eleven.synthesize(text, voiceID: voiceID)
        let url = folder.appending(path: RecordingStore.outputName)
        try audio.write(to: url, options: .atomic)
        try RecordingStore.updateMeta(in: folder) { meta in
            meta.title = RecordingMeta.title(for: text)
            meta.voiceID = voiceID
            meta.outputFile = RecordingStore.outputName
        }
        spokenText = text
        outputURL = url
        player.load(url)
        player.play()
    }

    private func elevenLabs() throws -> ElevenLabsClient {
        guard let key = KeychainStore.read(.elevenLabsKey) else {
            throw PipelineError(message: "Add your ElevenLabs key in Settings first.")
        }
        return ElevenLabsClient(apiKey: key)
    }

    private func anthropic() throws -> AnthropicClient {
        guard let key = KeychainStore.read(.anthropicKey) else {
            throw PipelineError(message: "Add your Anthropic key in Settings first.")
        }
        return AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
    }
}
