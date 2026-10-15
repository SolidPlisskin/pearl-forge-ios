import SwiftUI
import UniformTypeIdentifiers

/// Record a thought, pick how much refinement, and hear it back in your voice.
struct CreateView: View {
    let settings: SettingsModel
    let openSettings: () -> Void

    @State private var model = CreateModel()
    @State private var importing = false
    @State private var confirmingDiscard = false
    @FocusState private var editingRefined: Bool

    /// Both keys saved and a voice chosen.
    private var isReady: Bool {
        settings.elevenLabsStatus != .notSet
            && settings.anthropicStatus != .notSet
            && !settings.selectedVoiceID.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isReady {
                    setupSection
                }
                if model.folder == nil {
                    recorderSection
                    if model.source != nil {
                        modeSection
                        actionSection
                    } else if let error = model.errorMessage {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
                if let transcript = model.transcript {
                    Section("What you said") {
                        Text(transcript)
                            .textSelection(.enabled)
                    }
                }
                if model.folder != nil {
                    refinedSection
                    voiceSection
                }
            }
            .navigationTitle("Pearl Forge")
            .toolbar {
                if model.folder != nil && !model.isBusy {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New recording", systemImage: "plus") {
                            model.startNew()
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingRefined = false }
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
            Label("Add your ElevenLabs and Anthropic keys and pick your voice before your first recording.",
                  systemImage: "key")
            Button("Open Settings", action: openSettings)
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
            Picker("Refinement", selection: $model.mode) {
                ForEach(RefinementMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isBusy)
        } header: {
            Text("How much refinement?")
        } footer: {
            Text(sentence(model.mode.subtitle))
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
                    Task { await model.refineAndSpeak(voiceID: settings.selectedVoiceID) }
                } label: {
                    Text(model.errorMessage == nil ? "Refine & speak" : "Try again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isReady)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } footer: {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            } else if isReady && !settings.selectedVoiceName.isEmpty {
                Text("Speaking as \(settings.selectedVoiceName).")
            }
        }
    }

    private var refinedSection: some View {
        Section {
            TextEditor(text: $model.refinedText)
                .frame(minHeight: 180)
                .focused($editingRefined)
                .disabled(model.isBusy)
        } header: {
            if let mode = model.refinedMode {
                Text("Refined · \(mode.title)")
            } else {
                Text("Refined")
            }
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
            } else if let outputURL = model.outputURL {
                PlayerRow(player: model.player)
                if model.hasUnspokenEdits {
                    Button("Regenerate audio from your edits") {
                        editingRefined = false
                        Task { await model.regenerateAudio(voiceID: settings.selectedVoiceID) }
                    }
                }
                ShareLink(item: outputURL) {
                    Label("Share audio", systemImage: "square.and.arrow.up")
                }
            } else if model.errorMessage != nil {
                Button("Try again") {
                    Task { await model.refineAndSpeak(voiceID: settings.selectedVoiceID) }
                }
            }
        } header: {
            Text("In your voice")
        } footer: {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            } else if let folder = model.folder {
                Text("Saved in Files › On My iPhone › Pearl Forge › Recordings › \(folder.lastPathComponent)")
            }
        }
    }

    // MARK: Helpers

    private func sentence(_ phrase: String) -> String {
        phrase.prefix(1).uppercased() + phrase.dropFirst() + "."
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
    CreateView(settings: SettingsModel(), openSettings: {})
}
