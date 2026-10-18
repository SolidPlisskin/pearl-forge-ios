import AVFoundation
import Observation
import UIKit

/// Drives the Create screen: record (or import) a voice note, or type some
/// text; then transcribe it, refine and/or translate it, save it, and speak
/// its first pearl in your voice. A failed step can be retried without
/// repeating the steps before it.
@MainActor
@Observable
final class CreateModel {
    enum Input: String, CaseIterable {
        case record = "Record"
        case type = "Type"
    }

    private static let modeKey = "refinementMode"
    private static let typedModeKey = "typedRefinementMode"
    private static let pendingRecordingURL = URL.temporaryDirectory.appending(path: "pending-recording.m4a")

    let recorder = VoiceRecorder()
    let player = AudioPlayback()

    var input = Input.record

    /// How much to polish a recording.
    var mode: RefinementMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    /// Typed text, and how much to polish it ("As written" by default).
    var typedText = ""
    var typedMode: RefinementMode {
        didSet { UserDefaults.standard.set(typedMode.rawValue, forKey: Self.typedModeKey) }
    }

    /// The language to speak in; nil keeps the language you used.
    var language: SpeechLanguage?

    /// The mode in use for what's being made now.
    var activeMode: RefinementMode { input == .type ? typedMode : mode }

    /// The voice note waiting to be processed, recorded or imported.
    private(set) var source: URL?
    private(set) var sourceDuration: TimeInterval?
    private(set) var step: ForgeStep?
    private(set) var errorMessage: String?
    private(set) var microphoneDenied = false

    private(set) var transcript: String?
    /// The refined text, editable before regenerating the audio.
    var refinedText = ""
    private(set) var refinedMode: RefinementMode?
    /// The saved recording and its first pearl, once refined.
    private(set) var recordingID: String?
    private(set) var pearlID: UUID?
    /// A copy of the audio for the share sheet.
    private(set) var shareURL: URL?
    /// The text the current audio was made from.
    private var spokenText: String?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(RefinementMode.init)
        mode = saved.flatMap { RefinementMode.polishingModes.contains($0) ? $0 : nil } ?? .clean
        typedMode = UserDefaults.standard.string(forKey: Self.typedModeKey).flatMap(RefinementMode.init) ?? .asWritten
    }

    var isBusy: Bool { step != nil }
    var hasResult: Bool { recordingID != nil }

    /// There's a voice note or some typed text ready to process.
    var hasInput: Bool {
        switch input {
        case .record: return source != nil
        case .type: return !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Whether processing calls an AI at all (typed text spoken as written,
    /// in its own language, doesn't).
    var needsAI: Bool { activeMode != .asWritten || language != nil }

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
    /// saved in History, so nothing is lost.
    func startNew() {
        player.unload()
        if hasResult { typedText = "" }
        source = nil
        sourceDuration = nil
        errorMessage = nil
        transcript = nil
        refinedText = ""
        refinedMode = nil
        recordingID = nil
        pearlID = nil
        shareURL = nil
        spokenText = nil
    }

    // MARK: Pipeline

    /// Runs whichever steps haven't succeeded yet: transcribe (recordings
    /// only), refine and/or translate (and save), then speak.
    func refineAndSpeak(voiceID: String, polisher: PolisherChoice?, library: RecordingLibrary) async {
        guard hasInput, step == nil else { return }
        errorMessage = nil
        // Give the requests time to finish if the phone is locked mid-way.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Refine and speak")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        do {
            if transcript == nil {
                switch input {
                case .record:
                    guard let source else { return }
                    step = .transcribing
                    transcript = try await Forge.transcribe(source)
                case .type:
                    transcript = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if recordingID == nil, let transcript {
                let mode = activeMode
                let notes = language.map(SpeechLanguages.request)
                var refinement: Refinement?
                if needsAI {
                    guard let polisher else {
                        throw PipelineError(message: "Choose the AI that polishes your thoughts in the AI tab first.")
                    }
                    step = language != nil ? .translating : .refining
                    if mode == .asWritten, let language {
                        refinement = try await Forge.translate(transcript, to: language, with: polisher)
                    } else {
                        refinement = try await Forge.refine(transcript, mode: mode, notes: notes, with: polisher)
                    }
                }
                let (entry, pearl) = try await library.createRecording(
                    sourceAudio: input == .record ? source : nil, transcript: transcript, refinement: refinement,
                    mode: mode, notes: notes, voiceID: voiceID)
                recordingID = entry.id
                pearlID = pearl.id
                // Sort recordings into topics in the background; it doesn't hold anything up.
                if input == .record, let polisher {
                    Task { await library.sortIntoTopics(entry.id, with: polisher) }
                }
                refinedText = refinement?.text ?? transcript
                refinedMode = mode
            }
            step = .speaking
            try await speak(voiceID: voiceID, library: library)
        } catch {
            errorMessage = error.localizedDescription
        }
        step = nil
    }

    /// Re-speaks the (edited) refined text and replaces the saved audio.
    func regenerateAudio(voiceID: String, library: RecordingLibrary) async {
        guard recordingID != nil, step == nil else { return }
        errorMessage = nil
        step = .speaking
        do {
            try await speak(voiceID: voiceID, library: library)
        } catch {
            errorMessage = error.localizedDescription
        }
        step = nil
    }

    /// Saves the current refined text, speaks it, and plays the result.
    private func speak(voiceID: String, library: RecordingLibrary) async throws {
        guard let recordingID, let pearlID else { return }
        let text = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PipelineError(message: "There's no text to turn into speech.")
        }
        if library.entry(recordingID)?.pearlTexts[pearlID] != text {
            try await library.updateText(text, of: pearlID, in: recordingID)
        }
        player.unload()
        let audio = try await Forge.speak(text, voiceID: voiceID)
        try await library.setAudio(audio, of: pearlID, in: recordingID, voiceID: voiceID)
        spokenText = text
        shareURL = try? RecordingFiles.shareCopy(of: audio, title: RecordingFiles.title(for: text), pearlNumber: 1)
        player.load(audio, key: pearlID.uuidString)
        player.play()
    }
}
