import SwiftUI
import UniformTypeIdentifiers

/// Record a thought (or type something), pick how much refinement and which
/// language, and hear it in your voice.
struct CreateView: View {
    let settings: SettingsModel
    let polishers: PolishersModel
    let library: RecordingLibrary
    let openTab: (AppTab) -> Void

    @State private var model = CreateModel()
    @State private var importing = false
    @State private var confirmingDiscard = false
    @FocusState private var editingRefined: Bool
    @FocusState private var editingTyped: Bool

    /// ElevenLabs set up with a voice chosen.
    private var hasVoice: Bool {
        settings.elevenLabsStatus != .notSet && !settings.selectedVoiceID.isEmpty
    }

    /// Everything needed to refine and speak a recording.
    private var isReady: Bool {
        hasVoice && polishers.activeChoice != nil
    }

    /// Everything needed for what's set up right now (typed text spoken as
    /// written needs no AI).
    private var canGo: Bool {
        hasVoice && (!model.needsAI || polishers.activeChoice != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isReady {
                    setupSection
                }
                if !model.hasResult {
                    if !model.recorder.isRecording && model.source == nil && model.transcript == nil {
                        inputPicker
                    }
                    if model.input == .record {
                        recorderSection
                    } else {
                        typeSection
                    }
                    if model.hasInput {
                        modeSection
                        actionSection
                    } else if let error = model.errorMessage {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
                if let transcript = model.transcript, model.input == .record || (model.hasResult && transcript != model.refinedText) {
                    Section(model.input == .type ? "What you wrote" : "What you said") {
                        Text(transcript)
                            .textSelection(.enabled)
                    }
                }
                if model.hasResult {
                    refinedSection
                    voiceSection
                }
            }
            .navigationTitle("Pearl Forge")
            .toolbar {
                if model.hasResult && !model.isBusy {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New", systemImage: "plus") {
                            model.startNew()
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        editingRefined = false
                        editingTyped = false
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    model.importRecording(from: url)
                }
            }
            .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard,
                                titleVisibility: .visible) {
                Button("Discard and record again", role: .destructive) {
                    Task { await model.startRecording() }
                }
            } message: {
                Text("It hasn't been refined or saved yet.")
            }
        }
    }

    // MARK: Sections

    private var setupSection: some View {
        Section {
            if !hasVoice {
                Label("Add your ElevenLabs key and pick your voice in Settings.", systemImage: "key")
                Button("Open Settings") { openTab(.settings) }
            }
            if polishers.activeChoice == nil {
                Label("Choose the AI that polishes your thoughts in the AI tab.", systemImage: "sparkles")
                Button("Open the AI tab") { openTab(.ai) }
            }
        }
    }

    private var inputPicker: some View {
        Section {
            Picker("Input", selection: $model.input) {
                ForEach(CreateModel.Input.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var typeSection: some View {
        Section {
            TextEditor(text: $model.typedText)
                .frame(minHeight: 140)
                .focused($editingTyped)
                .disabled(model.isBusy)
                .overlay(alignment: .topLeading) {
                    if model.typedText.isEmpty {
                        Text("Type or paste what you want to say…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("What you want to say")
        } footer: {
            Text("Spoken in your voice. Pick a language below to translate it first.")
        }
    }

    private var recorderSection: some View {
        Section {
            VStack(spacing: 14) {
                if model.recorder.isRecording {
                    Text(timeString(model.recorder.elapsed))
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .monospacedDigit()
                    LevelMeter(level: model.recorder.level)
                    Button {
                        model.stopRecording()
                    } label: {
                        RecordButtonFace(isRecording: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop recording")
                    Text("Tap to stop")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if model.source != nil {
                    Label(readyLabel, systemImage: "waveform")
                        .font(.headline)
                    Button("Record again") {
                        confirmingDiscard = true
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy)
                } else {
                    Button {
                        Task { await model.startRecording() }
                    } label: {
                        RecordButtonFace(isRecording: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Record")
                    Text("Tap to record")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Import a recording instead") {
                        importing = true
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }

                if model.microphoneDenied {
                    VStack(spacing: 6) {
                        Text("Pearl Forge needs microphone access to record.")
                            .font(.subheadline)
                        Button("Allow in the Settings app") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    }
                    .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var readyLabel: String {
        if let duration = model.sourceDuration {
            return "Voice note ready · \(timeString(duration))"
        }
        return "Voice note ready"
    }

    private var modeSection: some View {
        Section {
            if model.input == .record {
                Picker("Refinement", selection: $model.mode) {
                    ForEach(RefinementMode.polishingModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Picker("Polish", selection: $model.typedMode) {
                    ForEach([RefinementMode.asWritten] + RefinementMode.polishingModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            Picker("Speak in", selection: $model.language) {
                Text(model.input == .type ? "The language I wrote in" : "The language I spoke in").tag(SpeechLanguage?.none)
                ForEach(SpeechLanguages.all) { language in
                    Text(language.name).tag(SpeechLanguage?.some(language))
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text(model.input == .record ? "How much refinement?" : "Options")
        } footer: {
            Text(modeFooter)
        }
        .disabled(model.isBusy)
    }

    private var modeFooter: String {
        var text = model.activeMode.subtitleSentence
        if let language = model.language {
            text += " Then spoken in \(language.name), in your voice."
        }
        return text
    }

    private var actionTitle: String {
        if model.errorMessage != nil { return "Try again" }
        switch (model.input, model.language != nil) {
        case (.record, false): return "Refine & speak"
        case (.record, true): return "Refine, translate & speak"
        case (.type, true): return "Translate & speak"
        case (.type, false): return model.typedMode == .asWritten ? "Speak in my voice" : "Polish & speak"
        }
    }

    private var actionSection: some View {
        Section {
            if let step = model.step {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(step.progressLabel)
                }
            } else {
                Button {
                    editingTyped = false
                    Task { await refineAndSpeak() }
                } label: {
                    Text(actionTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canGo)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } footer: {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            } else if canGo {
                Text(actionFooter)
            }
        }
    }

    private var actionFooter: String {
        let voice = settings.selectedVoiceName.isEmpty ? "your voice" : settings.selectedVoiceName
        guard model.needsAI, let choice = polishers.activeChoice else {
            return "Speaking as \(voice), exactly as written."
        }
        let verb = model.activeMode == .asWritten ? "Translating" : "Polishing"
        return "\(verb) with \(polishers.label(for: choice)), speaking as \(voice)."
    }

    private var refinedSection: some View {
        Section {
            TextEditor(text: $model.refinedText)
                .frame(minHeight: 180)
                .focused($editingRefined)
                .disabled(model.isBusy)
        } header: {
            Text(refinedHeader)
        } footer: {
            Text("If anything's off, fix it here, then regenerate the audio.")
        }
    }

    private var voiceSection: some View {
        Section {
            if let step = model.step {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(step.progressLabel)
                }
            } else if model.player.loadedKey != nil {
                PlayerRow(player: model.player)
                if model.hasUnspokenEdits {
                    Button("Regenerate audio from your edits") {
                        editingRefined = false
                        Task { await model.regenerateAudio(voiceID: settings.selectedVoiceID, library: library) }
                    }
                }
                if let shareURL = model.shareURL {
                    ShareLink(item: shareURL) {
                        Label("Share audio", systemImage: "square.and.arrow.up")
                    }
                }
            } else if model.errorMessage != nil {
                Button("Try again") {
                    Task { await refineAndSpeak() }
                }
            }
        } header: {
            Text("In your voice")
        } footer: {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                Text("Saved as pearl 1 in History (\(library.locationName)). Open it there to forge more versions, with any AI.")
            }
        }
    }

    private var refinedHeader: String {
        let mode = model.refinedMode ?? model.activeMode
        let language = model.language.map { " · In \($0.name)" } ?? ""
        switch mode {
        case .asWritten: return model.language == nil ? "As written" : "Translated" + language
        default: return "Refined · \(mode.title)" + language
        }
    }

    private func refineAndSpeak() async {
        await model.refineAndSpeak(voiceID: settings.selectedVoiceID, polisher: polishers.activeChoice, library: library)
    }
}

/// "1:05" style minutes and seconds.
func timeString(_ seconds: TimeInterval) -> String {
    Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
}

/// The big round record / stop button.
private struct RecordButtonFace: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.red)
                .frame(width: 88, height: 88)
                .shadow(color: .red.opacity(0.3), radius: 8, y: 3)
            if isRecording {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white)
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Circle())
    }
}

/// A bar that moves with your voice, so you can see the mic is hearing you.
private struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.red)
                        .frame(width: geometry.size.width * level)
                }
        }
        .frame(width: 220, height: 6)
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

/// Play/pause, a scrubber, and the elapsed and total time.
struct PlayerRow: View {
    let player: AudioPlayback

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            VStack(spacing: 2) {
                Slider(value: Binding(get: { player.currentTime },
                                      set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 0.1))
                HStack {
                    Text(timeString(player.currentTime))
                    Spacer()
                    Text(timeString(player.duration))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CreateView(settings: SettingsModel(), polishers: PolishersModel(), library: RecordingLibrary(), openTab: { _ in })
}
