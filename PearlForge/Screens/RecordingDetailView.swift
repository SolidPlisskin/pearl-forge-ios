import SwiftUI

/// One recording: your original voice note and transcript, its topics, every
/// pearl forged from it, and reading found for it.
struct RecordingDetailView: View {
    let entryID: String
    let library: RecordingLibrary
    let settings: SettingsModel
    let polishers: PolishersModel

    @State private var player = AudioPlayback()
    @State private var showingForgeSheet = false
    @State private var showingTranscript = false
    @State private var editingTopics = false
    @State private var opened: WebPage?

    var body: some View {
        if let entry = library.entry(entryID) {
            content(entry)
        } else {
            ContentUnavailableView("This recording was deleted", systemImage: "trash")
        }
    }

    private func content(_ entry: RecordingEntry) -> some View {
        Form {
            Section {
                Text(entry.meta.title.isEmpty ? "Untitled thought" : entry.meta.title)
                    .font(.headline)
                Text(entry.meta.created.formatted(date: .complete, time: .shortened))
                    .foregroundStyle(.secondary)
                if let gist = entry.meta.gist, !gist.isEmpty {
                    Text(gist)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }

            topicsSection(entry)

            if let playing = nowPlayingPearl(in: entry) {
                Section("Now playing · Pearl \(playing.number)") {
                    PlayerRow(player: player)
                }
            }

            Section("Your original recording") {
                if let original = entry.meta.originalFile {
                    AudioItemRow(title: "Play what you said", key: "original",
                                 fileExtension: (original as NSString).pathExtension, player: player) {
                        try await library.audioData(original, in: entry.id)
                    }
                }
                DisclosureGroup("What you said", isExpanded: $showingTranscript) {
                    Text(entry.transcript)
                        .textSelection(.enabled)
                }
            }

            Section {
                if let step = library.forging[entry.id] {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(step.progressLabel)
                    }
                }
                ForEach(entry.pearlsNewestFirst) { pearl in
                    NavigationLink {
                        PearlView(entryID: entry.id, pearlID: pearl.id, library: library,
                                  settings: settings, polishers: polishers, player: player)
                    } label: {
                        PearlRow(pearl: pearl, text: entry.pearlTexts[pearl.id] ?? "", polishers: polishers)
                    }
                }
                Button {
                    showingForgeSheet = true
                } label: {
                    Label("Forge a new pearl", systemImage: "sparkles")
                }
                .disabled(library.forging[entry.id] != nil || settings.selectedVoiceID.isEmpty
                          || polishers.readyProviders.isEmpty)
            } header: {
                Text("Pearls")
            } footer: {
                if let error = library.forgeErrors[entry.id] {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Each pearl is a fresh run of your original words through the forge. Your recording itself is never changed.")
                }
            }

            readingSection(entry)
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await library.setFavorite(!entry.meta.favorite, for: entry.id) }
                } label: {
                    Image(systemName: entry.meta.favorite ? "star.fill" : "star")
                }
                .accessibilityLabel(entry.meta.favorite ? "Remove from favorites" : "Add to favorites")
            }
        }
        .sheet(isPresented: $editingTopics) {
            TopicEditor(entryID: entry.id, current: entry.meta.categories ?? [], library: library)
        }
        .sheet(item: $opened) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showingForgeSheet) {
            ForgeSheet(initialMode: entry.pearlsNewestFirst.first?.mode ?? .clean, polishers: polishers) { mode, notes, polisher in
                Task {
                    if let result = await library.forgeNewPearl(for: entry.id, mode: mode, notes: notes,
                                                                polisher: polisher, voiceID: settings.selectedVoiceID) {
                        player.load(result.1, key: result.0.id.uuidString)
                        player.play()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func topicsSection(_ entry: RecordingEntry) -> some View {
        Section {
            if library.sorting.contains(entry.id) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Sorting into topics…")
                }
            } else if let topics = entry.meta.categories, !topics.isEmpty {
                TopicChips(topics: topics)
                    .padding(.vertical, 4)
            } else {
                Text(entry.meta.categories == nil ? "Not sorted into topics yet." : "No topics.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Edit topics") { editingTopics = true }
                if let choice = polishers.activeChoice {
                    Spacer()
                    Button(entry.meta.categories == nil ? "Sort automatically" : "Sort again") {
                        Task { await library.sortIntoTopics(entry.id, with: choice) }
                    }
                }
            }
            .buttonStyle(.borderless)
            .disabled(library.sorting.contains(entry.id))
        } header: {
            Text("Topics")
        } footer: {
            if let error = library.sortErrors[entry.id] {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func readingSection(_ entry: RecordingEntry) -> some View {
        let isSearching = library.findingReferences.contains(entry.id)
        Section {
            ForEach(entry.meta.references) { reference in
                Button {
                    if let url = URL(string: reference.url) { opened = WebPage(url: url) }
                } label: {
                    ReferenceRow(reference: reference)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await library.deleteReference(reference.id, from: entry.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if isSearching {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching PubMed and the web… this can take a minute or two.")
                }
            } else {
                Button {
                    Task { await library.findReferences(for: entry.id, claudeModel: claudeModel) }
                } label: {
                    Label(entry.meta.references.isEmpty ? "Find reading" : "Find more reading", systemImage: "books.vertical")
                }
                .disabled(polishers.status[.anthropic] == .notSet)
            }
        } header: {
            Text("Reading")
        } footer: {
            if let error = library.referenceErrors[entry.id] {
                Text(error).foregroundStyle(.red)
            } else if polishers.status[.anthropic] == .notSet {
                Text("Finding reading uses Claude's web search. Add your Claude key in the AI tab.")
            } else if let notice = library.referenceNotices[entry.id] {
                Text(notice)
            } else if entry.meta.references.isEmpty {
                Text("Searches PubMed for peer-reviewed research and the web for essays, articles and blog posts related to this thought. Everything found is also kept in the Reading tab.")
            }
        }
    }

    /// The Claude model chosen for finding reading in the AI tab.
    private var claudeModel: String {
        polishers.readingModel
    }

    /// The pearl loaded in the player, if any (not the original recording).
    private func nowPlayingPearl(in entry: RecordingEntry) -> Pearl? {
        guard let key = player.loadedKey, let id = UUID(uuidString: key) else { return nil }
        return entry.pearl(id)
    }
}

/// A pearl in the list: its number, mode and AI, your request, and how it
/// starts.
private struct PearlRow: View {
    let pearl: Pearl
    let text: String
    let polishers: PolishersModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Pearl \(pearl.number) · \(pearl.mode.title)")
                .font(.headline)
            if let by = polishedBy(pearl, polishers: polishers) {
                Text(by)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notes = pearl.notes, !notes.isEmpty {
                Text("“\(notes)”")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(text)
                .font(.subheadline)
                .lineLimit(2)
            Text(pearl.created.formatted(date: .abbreviated, time: .shortened)
                 + (pearl.audioFile == nil ? " · no audio yet" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// "Claude · Claude Opus 5.5" for a pearl, when known.
@MainActor
func polishedBy(_ pearl: Pearl, polishers: PolishersModel) -> String? {
    guard let model = pearl.refinedBy else { return nil }
    guard let provider = pearl.polisher.flatMap(PolisherProvider.init(rawValue:)) else { return model }
    return "\(provider.name) · \(polishers.modelName(model, for: provider))"
}
