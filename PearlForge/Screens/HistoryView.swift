import SwiftUI

/// Every saved recording, newest first, with search and favorites, or
/// gathered by topic.
struct HistoryView: View {
    enum Mode: String, CaseIterable {
        case recordings = "Recordings"
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

    private var shown: [RecordingEntry] {
        library.entries.filter { entry in
            (!favoritesOnly || entry.meta.favorite) && (search.isEmpty || matches(entry, search))
        }
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

                if mode == .topics {
                    topicsContent
                } else {
                    recordingsContent
                }
            }
            .overlay {
                if library.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No recordings yet", systemImage: "clock")
                    } description: {
                        Text("Every thought you refine is saved here: the original recording and each pearl you forge from it.")
                    }
                } else if mode == .recordings && shown.isEmpty && !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if mode == .recordings && shown.isEmpty {
                    ContentUnavailableView("No favorites yet", systemImage: "star",
                                           description: Text("Swipe right on a recording to make it a favorite."))
                }
            }
            .navigationTitle("History")
            .searchable(text: $search, prompt: mode == .topics ? "Search topics" : "Search your thoughts")
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
                ForEach(shown) { entry in
                    NavigationLink(value: entry.id) {
                        HistoryRow(entry: entry)
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
        ([entry.meta.title, entry.transcript, entry.meta.gist ?? ""] + (entry.meta.categories ?? []) + Array(entry.pearlTexts.values))
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// A recording in the list: its title, when it was made, and how many pearls.
private struct HistoryRow: View {
    let entry: RecordingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.meta.title.isEmpty ? "Untitled thought" : entry.meta.title)
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
        }
        .padding(.vertical, 2)
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

#Preview {
    HistoryView(library: RecordingLibrary(), settings: SettingsModel(), polishers: PolishersModel(), openTab: { _ in })
}
