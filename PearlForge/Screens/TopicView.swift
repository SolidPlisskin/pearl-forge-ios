import Observation
import SwiftUI

/// Identifies a topic page in History's navigation.
struct TopicRoute: Hashable {
    let name: String
}

/// Plays a topic's recordings one after another, each in its newest pearl.
@MainActor
@Observable
final class TopicQueue {
    struct Item: Equatable {
        let entryID: String
        let title: String
        let audioFile: String
    }

    let player = AudioPlayback()
    private(set) var items: [Item] = []
    private(set) var index = 0
    private(set) var isLoading = false
    private(set) var loadError: String?

    @ObservationIgnored private var library: RecordingLibrary?

    var current: Item? { items.indices.contains(index) ? items[index] : nil }
    var isActive: Bool { !items.isEmpty }

    init() {
        player.onFinish = { [weak self] in
            Task { await self?.next() }
        }
    }

    func start(_ entries: [RecordingEntry], library: RecordingLibrary) async {
        self.library = library
        items = entries.compactMap { entry in
            entry.latestSpokenPearl?.audioFile.map {
                Item(entryID: entry.id, title: entry.meta.title.isEmpty ? "Untitled thought" : entry.meta.title, audioFile: $0)
            }
        }
        index = 0
        await playCurrent()
    }

    func next() async {
        guard index + 1 < items.count else {
            stop()
            return
        }
        index += 1
        await playCurrent()
    }

    func previous() async {
        guard index > 0 else { return }
        index -= 1
        await playCurrent()
    }

    func stop() {
        player.unload()
        items = []
        index = 0
    }

    private func playCurrent() async {
        guard let item = current, let library else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let data = try await library.audioData(item.audioFile, in: item.entryID)
            guard current == item else { return }
            player.load(data, fileExtension: (item.audioFile as NSString).pathExtension, key: item.entryID)
            player.play()
        } catch {
            loadError = "Couldn't load “\(item.title)”: \(error.localizedDescription)"
        }
    }
}

/// Everything you've said about one topic, oldest first, with a button to
/// play them back to back, and the reading found for them.
struct TopicView: View {
    let topic: String
    let library: RecordingLibrary

    @State private var queue = TopicQueue()
    @State private var opened: WebPage?

    private var entries: [RecordingEntry] { library.entries(inTopic: topic) }

    /// References found for this topic's recordings, without duplicates.
    private var references: [(reference: Reference, entry: RecordingEntry)] {
        var seen = Set<String>()
        return entries.reversed().flatMap { entry in entry.meta.references.map { (reference: $0, entry: entry) } }
            .filter { seen.insert(ReferenceFinder.normalize($0.reference.url) ?? $0.reference.url).inserted }
    }

    var body: some View {
        List {
            playSection

            Section {
                ForEach(entries) { entry in
                    NavigationLink(value: entry.id) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.meta.title.isEmpty ? "Untitled thought" : entry.meta.title)
                                .font(.headline)
                                .lineLimit(2)
                            if let gist = entry.meta.gist, !gist.isEmpty {
                                Text(gist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            Text(entry.meta.created.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text(entries.count == 1 ? "1 thought" : "\(entries.count) thoughts")
            } footer: {
                Text("Oldest first, so you can follow how your thinking developed.")
            }

            if !references.isEmpty {
                Section("Reading") {
                    ForEach(references, id: \.reference.id) { item in
                        Button {
                            if let url = URL(string: item.reference.url) { opened = WebPage(url: url) }
                        } label: {
                            ReferenceRow(reference: item.reference, fromTitle: item.entry.meta.title)
                        }
                    }
                }
            }
        }
        .navigationTitle(topic)
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("No recordings in this topic", systemImage: "tray")
            }
        }
        .sheet(item: $opened) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .onDisappear { queue.stop() }
    }

    @ViewBuilder
    private var playSection: some View {
        let playable = entries.filter { $0.latestSpokenPearl != nil }
        Section {
            if let item = queue.current {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(queue.index + 1) of \(queue.items.count) · \(item.title)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if queue.isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading…").foregroundStyle(.secondary)
                        }
                    } else {
                        PlayerRow(player: queue.player)
                    }
                }
                HStack {
                    Button {
                        Task { await queue.previous() }
                    } label: {
                        Label("Previous", systemImage: "backward.fill")
                    }
                    .disabled(queue.index == 0)
                    Spacer()
                    Button("Stop", role: .destructive) { queue.stop() }
                    Spacer()
                    Button {
                        Task { await queue.next() }
                    } label: {
                        Label("Next", systemImage: "forward.fill")
                    }
                    .disabled(queue.index + 1 >= queue.items.count)
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
            } else {
                Button {
                    Task { await queue.start(playable, library: library) }
                } label: {
                    Label("Play all in order", systemImage: "play.circle.fill")
                        .font(.headline)
                }
                .disabled(playable.isEmpty)
            }
        } footer: {
            if let error = queue.loadError {
                Text(error).foregroundStyle(.red)
            } else if !queue.isActive {
                Text("Plays the newest pearl of each thought, one after another, in your voice.")
            }
        }
    }
}
