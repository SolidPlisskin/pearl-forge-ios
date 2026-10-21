import SwiftUI
import UniformTypeIdentifiers

/// Record a thought (or type something), pick how much refinement and which
/// language, and hear it in your voice. Say "give a lecture on…" to have a
/// topic researched and turned into a talk in your voice, with its cost shown
/// first.
struct CreateView: View {
    let settings: SettingsModel
    let polishers: PolishersModel
    let library: RecordingLibrary
    let openTab: (AppTab) -> Void

    @State private var model = CreateModel()
    @State private var importing = false
    @State private var confirmingDiscard = false
    @State private var opened: WebPage?
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
                if !model.hasResult && model.lecture != nil {
                    if model.input == .record {
                        recorderSection
                    }
                    lecturePlanSection
                    lectureCostSection
                    lectureActionSection
                    lectureAlternativesSection
                } else if !model.hasResult {
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
                if let transcript = model.transcript, model.lecture == nil || model.hasResult,
                   model.input == .record || (model.hasResult && transcript != model.refinedText) {
                    Section(model.input == .type ? "What you wrote" : "What you said") {
                        Text(transcript)
                            .textSelection(.enabled)
                    }
                }
                if model.hasResult {
                    refinedSection
                    voiceSection
                    if let info = model.lectureInfo {
                        lectureSourcesSection
                        lectureCostPaidSection(info)
                    }
                }
            }
            .navigationTitle("Pearl Forge")
            .task(id: model.lecture != nil) {
                // Know how many ElevenLabs credits are left before showing the estimate.
                if model.lecture != nil { await settings.refreshCredits() }
            }
            .sheet(item: $opened) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
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
        } footer: {
            if model.source == nil && !model.recorder.isRecording {
                Text("Tip: start with “Give a lecture on…” to have a topic researched and spoken as a talk in your voice. You'll see what it costs first.")
            }
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
        if model.input == .type && LectureRequest.parse(model.typedText) != nil { return "Plan lecture" }
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
        if model.input == .type && LectureRequest.parse(model.typedText) != nil {
            return "Shows the lecture's estimated cost before anything is spent."
        }
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
            } else if model.lectureInfo != nil {
                Text("Saved in History (\(library.locationName)) with its sources.")
            } else {
                Text("Saved as pearl 1 in History (\(library.locationName)). Open it there to forge more versions, with any AI.")
            }
        }
    }

    private var refinedHeader: String {
        if let info = model.lectureInfo {
            let language = model.language.map { " · In \($0.name)" } ?? ""
            return "Lecture · about \(info.minutes) min" + language
        }
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

    // MARK: Lectures

    private var hasClaudeKey: Bool { polishers.status[.anthropic] != .notSet }

    /// Reads and writes the planned lecture's settings.
    private func plan<Value>(_ keyPath: WritableKeyPath<CreateModel.LecturePlan, Value>,
                             _ fallback: Value) -> Binding<Value> {
        Binding(get: { model.lecture?[keyPath: keyPath] ?? fallback },
                set: { model.lecture?[keyPath: keyPath] = $0 })
    }

    private var lecturePlanSection: some View {
        Section {
            if let transcript = model.transcript {
                Text("“\(transcript)”")
                    .italic()
                    .foregroundStyle(.secondary)
            }
            TextField("Topic", text: plan(\.topic, ""), axis: .vertical)
                .lineLimit(1...4)
            Picker("Length", selection: plan(\.minutes, LectureLength.standard)) {
                ForEach(LectureLength.options, id: \.self) { minutes in
                    Text("About \(minutes) min").tag(minutes)
                }
            }
            Picker("Researched by", selection: plan(\.model, CreateModel.lectureModels[0])) {
                ForEach(CreateModel.lectureModels, id: \.self) { id in
                    Text(CreateModel.lectureModelName(id)).tag(id)
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
            Text("Lecture")
        } footer: {
            Text("Claude researches the topic on PubMed and the web, writes a talk from what it finds, and it's spoken in your voice. Every source it names is checked against the real search results.")
        }
        .disabled(model.isBusy)
    }

    private var lectureEstimate: LectureEstimate? {
        guard let plan = model.lecture else { return nil }
        return LectureEstimate.make(minutes: plan.minutes, model: plan.model, credits: settings.credits,
                                    pastRatios: library.lectureEstimateRatios(model: plan.model))
    }

    @ViewBuilder
    private var lectureCostSection: some View {
        if let plan = model.lecture, let estimate = lectureEstimate {
            Section {
                CostRow(title: "Research & writing", value: dollarRange(estimate.claudeLow, estimate.claudeHigh),
                        detail: "\(CreateModel.lectureModelName(plan.model)) · up to \(LectureLength.webSearches(minutes: plan.minutes)) web searches")
                CostRow(title: "Your voice",
                        value: estimate.voiceDollars.map { "about " + $0.dollars } ?? "free plan",
                        detail: "About \(estimate.credits.formatted()) ElevenLabs credits")
                CostRow(title: "Total", value: estimate.voiceDollars == nil
                        ? dollarRange(estimate.claudeLow, estimate.claudeHigh)
                        : dollarRange(estimate.totalLow, estimate.totalHigh),
                        detail: nil, isTotal: true)
                if let credits = settings.credits, estimate.credits > credits.remaining {
                    Label("That's more than the \(credits.remaining.formatted()) credits you have left this month. Choose a shorter lecture, or add credits at elevenlabs.io.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Estimated cost")
            } footer: {
                Text(costFooter(estimate))
            }
        }
    }

    private func costFooter(_ estimate: LectureEstimate) -> String {
        var parts: [String] = []
        if let credits = settings.credits {
            var left = "You have \(credits.remaining.formatted()) ElevenLabs credits left"
            if let resets = credits.resets {
                left += " until \(resets.formatted(.dateTime.month(.abbreviated).day()))"
            }
            parts.append(left + ".")
        }
        parts.append(estimate.learnedFrom > 0
                     ? "Adjusted to what your last \(estimate.learnedFrom == 1 ? "lecture" : "\(estimate.learnedFrom) lectures") actually cost."
                     : "Claude's part is a range because it depends on how much it needs to read.")
        parts.append("Claude bills your Anthropic account; your voice uses credits from your ElevenLabs plan, valued here at your plan's rate.")
        return parts.joined(separator: " ")
    }

    private var lectureActionSection: some View {
        Section {
            if let step = model.step {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.progressLabel)
                        if step == .researching, let progress = model.researchProgress, progress.searches > 0 {
                            Text(progressDetail(progress))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } else {
                Button {
                    Task { await giveLecture() }
                } label: {
                    Text(model.errorMessage == nil ? "Give the lecture" : "Try again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasVoice || !hasClaudeKey || model.lecture?.topic.trimmingCharacters(in: .whitespaces).isEmpty != false)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } footer: {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            } else if !hasClaudeKey {
                Text("Lectures are researched with Claude's web search. Add your Claude key in the AI tab.")
            } else if !hasVoice {
                Text("Add your ElevenLabs key and pick your voice in Settings.")
            } else if model.isBusy {
                Text("This takes a minute or two, then your voice. Pearl Forge keeps the screen on while it works; stay on this screen until it's done.")
            } else {
                Text("Takes a minute or two to research and write, then it's spoken as \(settings.selectedVoiceName.isEmpty ? "your voice" : settings.selectedVoiceName).")
            }
        }
    }

    /// "3 PubMed and 2 web searches · latest: “circadian rhythm teens”".
    private func progressDetail(_ progress: ResearchProgress) -> String {
        var counts: [String] = []
        if progress.pubMedSearches > 0 { counts.append("\(progress.pubMedSearches) PubMed") }
        if progress.webSearches > 0 { counts.append("\(progress.webSearches) web") }
        var text = counts.joined(separator: " and ") + (progress.searches == 1 ? " search" : " searches")
        if let query = progress.latestQuery { text += " · “\(query)”" }
        return text
    }

    /// For when "give a lecture…" wasn't meant as a request.
    @ViewBuilder
    private var lectureAlternativesSection: some View {
        if !model.isBusy {
            Section {
                Button(model.input == .type ? "Not a lecture: speak what I wrote" : "Not a lecture: refine what I said") {
                    Task {
                        await model.speakInsteadOfLecture(voiceID: settings.selectedVoiceID,
                                                          polisher: polishers.activeChoice, library: library)
                    }
                }
                if model.input == .type {
                    Button("Edit what I wrote") { model.editTypedText() }
                }
            }
        }
    }

    private func giveLecture() async {
        let estimate = lectureEstimate
        await model.giveLecture(voiceID: settings.selectedVoiceID, topicSorter: polishers.activeChoice, library: library,
                                estimate: estimate?.claudeBase,
                                voiceRate: settings.credits.map(\.dollarsPerThousand) ?? VoiceCredits.dollarsPerThousand(tier: nil))
    }

    private var lectureSourcesSection: some View {
        Section {
            ForEach(model.lectureSources) { reference in
                Button {
                    if let url = URL(string: reference.url) { opened = WebPage(url: url) }
                } label: {
                    ReferenceRow(reference: reference)
                }
            }
            if model.lectureSources.isEmpty {
                Text("None of the sources Claude named could be confirmed, so none were saved.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Sources")
        } footer: {
            Text(model.unconfirmedSources > 0
                 ? "Each one was checked against the actual search results; \(model.unconfirmedSources) that couldn't be confirmed were left out. They're also in the Reading tab."
                 : "Each one was checked against the actual search results. They're also in the Reading tab.")
        }
    }

    private func lectureCostPaidSection(_ info: LectureInfo) -> some View {
        Section {
            CostRow(title: "Research & writing", value: info.claudeCost?.dollars ?? "not known",
                    detail: CreateModel.lectureModelName(info.model)
                        + (info.webSearches.map { " · \($0) web search\($0 == 1 ? "" : "es")" } ?? ""))
            if let characters = info.characters {
                CostRow(title: "Your voice", value: info.voiceCost.map { "about " + $0.dollars } ?? "free plan",
                        detail: "\(characters.formatted()) ElevenLabs credits")
            }
        } header: {
            Text("What it cost")
        } footer: {
            Text("Claude's cost is worked out from the usage it reported, at Anthropic's list prices. Regenerating the audio uses the credits again.")
        }
    }
}

/// One line of a cost breakdown: what it's for, the amount, and a detail line.
struct CostRow: View {
    let title: String
    let value: String
    let detail: String?
    var isTotal = false

    var body: some View {
        LabeledContent {
            Text(value)
                .fontWeight(isTotal ? .semibold : .regular)
                .monospacedDigit()
        } label: {
            Text(title)
                .fontWeight(isTotal ? .semibold : .regular)
            if let detail {
                Text(detail)
            }
        }
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
