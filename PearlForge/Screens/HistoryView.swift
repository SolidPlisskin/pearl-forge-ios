import SwiftUI

/// Every saved recording, newest first, with search and favorites.
struct HistoryView: View {
    let library: RecordingLibrary
    let settings: SettingsModel
    let polishers: PolishersModel
    let openTab: (AppTab) -> Void

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
            .overlay {
                if library.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No recordings yet", systemImage: "clock")
                    } description: {
                        Text("Every thought you refine is saved here: the original recording and each pearl you forge from it.")
                    }
                } else if shown.isEmpty && !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if shown.isEmpty {
                    ContentUnavailableView("No favorites yet", systemImage: "star",
                                           description: Text("Swipe right on a recording to make it a favorite."))
                }
            }
            .navigationTitle("History")
            .searchable(text: $search, prompt: "Search your thoughts")
            .refreshable { await library.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        Image(systemName: favoritesOnly ? "star.fill" : "star")
                    }
                    .accessibilityLabel(favoritesOnly ? "Show all recordings" : "Show favorites only")
                }
            }
            .navigationDestination(for: String.self) { id in
                RecordingDetailView(entryID: id, library: library, settings: settings, polishers: polishers)
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

    private func matches(_ entry: RecordingEntry, _ query: String) -> Bool {
        ([entry.meta.title, entry.transcript] + Array(entry.pearlTexts.values))
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
        entry.meta.pearls.count == 1 ? "1 pearl" : "\(entry.meta.pearls.count) pearls"
    }
}

#Preview {
    HistoryView(library: RecordingLibrary(), settings: SettingsModel(), polishers: PolishersModel(), openTab: { _ in })
}
