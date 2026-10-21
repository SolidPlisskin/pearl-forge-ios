import AVFoundation
import Observation
import UIKit

/// Drives the Create screen: record (or import) a voice note, or type some
/// text; then transcribe it, refine and/or translate it, save it, and speak
/// its first pearl in your voice. If what you said asks for a lecture ("give a
/// lecture on…"), it plans one instead and shows what it will cost before
/// anything is spent. A failed step can be retried without repeating the
/// steps before it.
@MainActor
@Observable
final class CreateModel {
    enum Input: String, CaseIterable {
        case record = "Record"
        case type = "Type"
    }

    /// A lecture you asked for, waiting for you to confirm it.
    struct LecturePlan: Equatable {
        var topic: String
        var minutes: Int
        var model: String
    }

    /// The Claude models offered for lectures; both search the web and
    /// PubMed. Sonnet 5.5 costs about half as much.
    static let lectureModels = ["claude-sonnet-5-5", "claude-opus-5-5"]

    static func lectureModelName(_ id: String) -> String {
        ["claude-sonnet-5-5": "Claude Sonnet 5.5", "claude-opus-5-5": "Claude Opus 5.5"][id] ?? id
    }

    private static let modeKey = "refinementMode"
    private static let typedModeKey = "typedRefinementMode"
    private static let lectureModelKey = "lecture.model"
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

    /// The lecture you asked for, once what you said has been understood.
    var lecture: LecturePlan?
    /// Set when you chose to treat a lecture request as an ordinary thought.
    private var ignoresLectureRequest = false
    private(set) var researchProgress: ResearchProgress?
    /// A finished lecture's details and the sources it draws on.
    private(set) var lectureInfo: LectureInfo?
    private(set) var lectureSources: [Reference] = []
    /// Sources Claude named that couldn't be confirmed, so weren't kept.
    private(set) var unconfirmedSources = 0

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
        lecture = nil
        ignoresLectureRequest = false
        researchProgress = nil
        lectureInfo = nil
        lectureSources = []
        unconfirmedSources = 0
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
            if recordingID == nil, let transcript, !ignoresLectureRequest,
               let request = LectureRequest.parse(transcript) {
                // Asked for a lecture: show the plan and its cost first.
                lecture = LecturePlan(topic: request.topic,
                                      minutes: request.minutes.map(LectureLength.nearest) ?? LectureLength.standard,
                                      model: Self.savedLectureModel)
                step = nil
                return
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

    // MARK: Lectures

    private static var savedLectureModel: String {
        UserDefaults.standard.string(forKey: lectureModelKey).flatMap { lectureModels.contains($0) ? $0 : nil }
            ?? lectureModels[0]
    }

    /// Researches and writes the planned lecture, saves it with its sources,
    /// and speaks it in your voice. `estimate` is the unadjusted Claude
    /// estimate shown beforehand, saved so later estimates can learn from it.
    func giveLecture(voiceID: String, topicSorter: PolisherChoice?, library: RecordingLibrary,
                     estimate: Double?, voiceRate: Double?) async {
        guard let plan = lecture, step == nil else { return }
        let topic = plan.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else {
            errorMessage = "Say or type what the lecture should be about."
            return
        }
        errorMessage = nil
        UserDefaults.standard.set(plan.model, forKey: Self.lectureModelKey)
        // Research takes a few minutes; keep the screen on so the phone
        // doesn't lock and pause it.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Give a lecture")
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }

        do {
            if recordingID == nil {
                step = .researching
                researchProgress = ResearchProgress()
                let written = try await Forge.writeLecture(topic: topic, minutes: plan.minutes, language: language,
                                                           model: plan.model) { @MainActor [weak self] progress in
                    self?.researchProgress = progress
                }
                let info = LectureInfo(topic: topic, minutes: plan.minutes, model: written.model,
                                       language: language?.code, summary: written.summary.isEmpty ? nil : written.summary,
                                       claudeCost: written.cost, estimatedClaudeCost: estimate,
                                       webSearches: written.usage.webSearches, characters: written.script.count,
                                       dollarsPerThousandCredits: voiceRate)
                let (entry, pearl) = try await library.createLecture(
                    sourceAudio: input == .record ? source : nil, request: transcript ?? topic,
                    lecture: written, info: info, voiceID: voiceID)
                recordingID = entry.id
                pearlID = pearl.id
                refinedText = written.script
                refinedMode = .lecture
                lectureInfo = info
                lectureSources = written.references
                unconfirmedSources = written.unverified
                // Sort it into your topics so it plays alongside related thoughts.
                if let topicSorter {
                    Task { await library.sortIntoTopics(entry.id, with: topicSorter) }
                }
            }
            researchProgress = nil
            step = .speaking
            try await speak(voiceID: voiceID, library: library)
        } catch {
            errorMessage = error.localizedDescription
        }
        researchProgress = nil
        step = nil
    }

    /// Treats a lecture request as an ordinary thought and refines and speaks
    /// it as usual.
    func speakInsteadOfLecture(voiceID: String, polisher: PolisherChoice?, library: RecordingLibrary) async {
        ignoresLectureRequest = true
        lecture = nil
        await refineAndSpeak(voiceID: voiceID, polisher: polisher, library: library)
    }

    /// Goes back to editing the text you typed.
    func editTypedText() {
        lecture = nil
        transcript = nil
        errorMessage = nil
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
        let title = library.entry(recordingID)?.meta.title ?? RecordingFiles.title(for: text)
        shareURL = try? RecordingFiles.shareCopy(of: audio, title: title, pearlNumber: 1)
        player.load(audio, key: pearlID.uuidString)
        player.play()
    }
}
