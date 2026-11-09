import SwiftUI

/// Identifies a pearl's page in History's navigation.
struct PearlRoute: Hashable {
    let entryID: String
    let pearlID: UUID
}

/// Every saved recording, newest first, with search and favorites; every
/// video you've made; or recordings gathered by topic.
struct HistoryView: View {
    enum Mode: String, CaseIterable {
        case recordings = "Recordings"
        case videos = "Videos"
        case topics = "Topics"
    }

    let library: RecordingLibrary
    let settings: SettingsModel
    let polishers: PolishersModel
    let openTab: (AppTab) -> Void

    @State private var mode = Mode.recordings
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var pendingDelete: RecordingEntry?
    @State private var deleteError: String?
    @State private var player = AudioPlayback()
    @State private var playingVideo: PlayingVideo?
    @State private var loadingVideo: UUID?
    @State private var videoError: String?

    private var shown: [RecordingEntry] {
        library.entries.filter { entry in
            (!favoritesOnly || entry.meta.favorite) && (search.isEmpty || matches(entry, search))
        }
    }

    /// Every pearl with a video (or one still to collect), newest first.
    private var videos: [(entry: RecordingEntry, pearl: Pearl)] {
        library.entries.flatMap { entry in entry.videoPearls.map { (entry: entry, pearl: $0) } }
            .filter { search.isEmpty || matches($0.entry, search) }
            .sorted { $0.pearl.created > $1.pearl.created }
    }

    var body: some View {
        NavigationStack {
            List {
                if let problem = library.storageProblem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                        Button("Open Settings") { openTab(.settings) }
                    }
                }
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                switch mode {
                case .recordings: recordingsContent
                case .videos: videosContent
                case .topics: topicsContent
                }
            }
            .overlay {
                if library.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No recordings yet", systemImage: "clock")
                    } description: {
                        Text("Every thought you refine is saved here: the original recording and each pearl you forge from it.")
                    }
                } else if mode == .videos && videos.isEmpty && !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if mode == .videos && videos.isEmpty {
                    ContentUnavailableView("No videos yet", systemImage: "film",
                                           description: Text("Open a pearl and choose Make video, or add one you made elsewhere. Every video shows up here."))
                } else if mode == .recordings && shown.isEmpty && !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if mode == .recordings && shown.isEmpty {
                    ContentUnavailableView("No favorites yet", systemImage: "star",
                                           description: Text("Swipe right on a recording to make it a favorite."))
                }
            }
            .navigationTitle("History")
            .searchable(text: $search, prompt: mode == .topics ? "Search topics" : "Search your thoughts, in any language")
            .refreshable { await library.refresh() }
            .toolbar {
                if mode == .recordings {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            favoritesOnly.toggle()
                        } label: {
                            Image(systemName: favoritesOnly ? "star.fill" : "star")
                        }
                        .accessibilityLabel(favoritesOnly ? "Show all recordings" : "Show favorites only")
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                RecordingDetailView(entryID: id, library: library, settings: settings, polishers: polishers)
            }
            .navigationDestination(for: TopicRoute.self) { route in
                TopicView(topic: route.name, library: library)
            }
            .navigationDestination(for: PearlRoute.self) { route in
                PearlView(entryID: route.entryID, pearlID: route.pearlID, library: library,
                          settings: settings, polishers: polishers, player: player)
            }
            .fullScreenCover(item: $playingVideo) { video in
                VideoPlayerScreen(video: video)
            }
            .alert("Couldn't play the video", isPresented: Binding(get: { videoError != nil },
                                                                    set: { if !$0 { videoError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(videoError ?? "")
            }
            .confirmationDialog("Delete this recording?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingDelete) { entry in
                Button("Delete recording and all its pearls", role: .destructive) {
                    Task {
                        do {
                            try await library.deleteRecording(entry.id)
                        } catch {
                            deleteError = error.localizedDescription
                        }
                    }
                }
            } message: { _ in
                Text("The original recording and every pearl made from it will be deleted from \(library.locationName).")
            }
            .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil },
                                                           set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    // MARK: Recordings

    @ViewBuilder
    private var recordingsContent: some View {
                englishSection
                ForEach(shown) { entry in
                    NavigationLink(value: entry.id) {
                        HistoryRow(entry: entry, library: library)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await library.setFavorite(!entry.meta.favorite, for: entry.id) }
                        } label: {
                            Label(entry.meta.favorite ? "Unfavorite" : "Favorite",
                                  systemImage: entry.meta.favorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            pendingDelete = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
    }

    /// Offers English versions for pearls in other languages made before
    /// Pearl Forge wrote them automatically.
    @ViewBuilder
    private var englishSection: some View {
        let missing = library.pearlsMissingEnglish.count
        if missing > 0 && search.isEmpty && !favoritesOnly {
            Section {
                if !library.translating.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Writing English versions…")
                    }
                } else if let choice = polishers.activeChoice {
                    Button {
                        Task { await library.addEnglishToAll(with: choice) }
                    } label: {
                        Label(missing == 1 ? "Add English to 1 pearl in another language"
                                           : "Add English to \(missing) pearls in other languages",
                              systemImage: "character.bubble")
                    }
                } else {
                    Button("Choose an AI in the AI tab to see pearls in English") { openTab(.ai) }
                }
            } footer: {
                if let error = library.translationErrors.values.first {
                    Text(error).foregroundStyle(.red)
                } else if let choice = polishers.activeChoice {
                    Text("So you can tell what pearls in other languages say. New ones get theirs automatically. Uses \(polishers.label(for: choice)), about a cent a pearl.")
                }
            }
        }
    }

    // MARK: Videos

    @ViewBuilder
    private var videosContent: some View {
        ForEach(videos, id: \.pearl.id) { item in
            NavigationLink(value: PearlRoute(entryID: item.entry.id, pearlID: item.pearl.id)) {
                VideoRow(entry: item.entry, pearl: item.pearl, library: library,
                         isLoading: loadingVideo == item.pearl.id) {
                    Task { await play(item.pearl.id, in: item.entry.id) }
                }
            }
        }
    }

    private func play(_ pearlID: UUID, in entryID: String) async {
        guard loadingVideo == nil else { return }
        loadingVideo = pearlID
        defer { loadingVideo = nil }
        do {
            player.pause()
            playingVideo = try await PlayingVideo.load(pearlID, in: entryID, library: library)
        } catch {
            videoError = error.localizedDescription
        }
    }

    // MARK: Topics

    @ViewBuilder
    private var topicsContent: some View {
        let unsorted = library.unsorted
        if !unsorted.isEmpty {
            Section {
                if !library.sorting.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Sorting into topics…")
                    }
                } else if let choice = polishers.activeChoice {
                    Button {
                        Task { await library.sortAllUnsorted(with: choice) }
                    } label: {
                        Label(unsorted.count == 1 ? "Sort 1 recording into topics" : "Sort \(unsorted.count) recordings into topics",
                              systemImage: "square.stack.3d.up")
                    }
                } else {
                    Button("Choose an AI in the AI tab to sort recordings") { openTab(.ai) }
                }
            } footer: {
                if let choice = polishers.activeChoice, library.sorting.isEmpty {
                    Text("New recordings are sorted automatically. These were made before topics existed. Uses \(polishers.label(for: choice)).")
                }
            }
        }

        let topics = library.topics.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        if library.topics.isEmpty && unsorted.isEmpty && !library.entries.isEmpty {
            Section {
                Text("No topics yet.").foregroundStyle(.secondary)
            }
        } else if !topics.isEmpty {
            Section {
                ForEach(topics, id: \.name) { topic in
                    NavigationLink(value: TopicRoute(name: topic.name)) {
                        LabeledContent(topic.name, value: topic.count == 1 ? "1 thought" : "\(topic.count) thoughts")
                    }
                }
            } footer: {
                Text("Open a topic to see everything you've said about it in order, play it all back to back, and find related reading.")
            }
        }
    }

    private func matches(_ entry: RecordingEntry, _ query: String) -> Bool {
        ([entry.meta.title, entry.displayTitle, entry.transcript, entry.meta.gist ?? ""] + (entry.meta.categories ?? [])
         + Array(entry.pearlTexts.values) + entry.meta.pearls.compactMap(\.english) + entry.otherLanguages)
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// A recording in the list: a still from its newest video (or what kind of
/// recording it is), its title in your language, when it was made, how many
/// pearls, and badges for its videos and the languages its pearls are in.
private struct HistoryRow: View {
    let entry: RecordingEntry
    let library: RecordingLibrary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if entry.meta.favorite {
                        Spacer()
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text("\(entry.meta.created.formatted(date: .abbreviated, time: .shortened)) · \(pearlCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                badges
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var tile: some View {
        if let video = entry.videoPearls.first(where: { $0.videoFile != nil }) ?? entry.videoPearls.first {
            VideoStill(entryID: entry.id, pearl: video, library: library, width: 50, height: 50)
        } else {
            Image(systemName: entry.meta.lecture != nil ? "graduationcap" : entry.meta.isTyped ? "keyboard" : "waveform")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 50, height: 50)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var badges: some View {
        let made = entry.videoPearls.filter { $0.videoFile != nil }.count
        let waiting = entry.videoPearls.filter { $0.videoGenerationID != nil }.count
        let languages = entry.otherLanguages
        if made + waiting > 0 || !languages.isEmpty {
            FlowLayout(spacing: 6) {
                if made > 0 {
                    Badge(text: made == 1 ? "Video" : "\(made) videos", symbol: "film", color: .purple)
                }
                if waiting > 0 {
                    Badge(text: waiting == 1 ? "Video to collect" : "\(waiting) videos to collect",
                          symbol: "arrow.down.circle", color: .orange)
                }
                ForEach(languages, id: \.self) { language in
                    Badge(text: language, symbol: "globe", color: .blue)
                }
            }
        }
    }

    private var pearlCount: String {
        var pearls = entry.meta.pearls.count == 1 ? "1 pearl" : "\(entry.meta.pearls.count) pearls"
        if let lecture = entry.meta.lecture {
            pearls = "Lecture · about \(lecture.minutes) min"
        } else if entry.meta.isTyped {
            pearls = "Typed · " + pearls
        }
        guard let topics = entry.meta.categories, !topics.isEmpty else { return pearls }
        return pearls + " · " + topics.joined(separator: ", ")
    }
}

/// A video in the Videos list: its still (tap to play), the recording's
/// title, the pearl and language, what it says in English, and what it cost.
private struct VideoRow: View {
    let entry: RecordingEntry
    let pearl: Pearl
    let library: RecordingLibrary
    let isLoading: Bool
    let play: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: play) {
                VideoStill(entryID: entry.id, pearl: pearl, library: library, width: 66, height: 88)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 66, height: 88)
                                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
            }
            .buttonStyle(.borderless)
            .disabled(pearl.videoFile == nil)
            .accessibilityLabel("Play video")
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let words = entry.readableText(of: pearl) {
                    Text(words)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let language = entry.otherLanguage(of: pearl) {
                    Text("In \(language). Open it to see it in English.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if library.videoWork[pearl.id] != nil {
                    Badge(text: "Being made", symbol: "hourglass", color: .orange)
                } else if pearl.videoGenerationID != nil {
                    Badge(text: "Not collected yet: open to collect", symbol: "arrow.down.circle", color: .orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// "Pearl 2 · Korean · Kling Avatar v2 Standard · $1.05 · Nov 6"
    private var detail: String {
        var parts = ["Pearl \(pearl.number)"]
        if let language = entry.otherLanguage(of: pearl) { parts.append(language) }
        if let endpoint = pearl.videoModel {
            parts.append(VideoModel.name(ofEndpoint: endpoint))
            if let cost = pearl.videoCost { parts.append(cost.dollars) }
        } else if pearl.videoCredits != nil {
            parts.append("ElevenLabs")
        }
        parts.append(pearl.created.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}

/// A small coloured label: "Video", "Korean".
struct Badge: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
        }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

#Preview {
    HistoryView(library: RecordingLibrary(), settings: SettingsModel(), polishers: PolishersModel(), openTab: { _ in })
}
