import SwiftUI

/// Every reference found for your recordings: research papers, essays,
/// articles and blog posts, filterable by kind and topic.
struct ReadingView: View {
    let library: RecordingLibrary

    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case research = "Research"
        case writing = "Articles & essays"

        var id: String { rawValue }

        func includes(_ kind: Reference.Kind) -> Bool {
            switch self {
            case .all: return true
            case .research: return kind == .research
            case .writing: return kind != .research
            }
        }
    }

    @State private var kind = KindFilter.all
    @State private var topic: String?
    @State private var search = ""
    @State private var opened: WebPage?

    private var shown: [(reference: Reference, entry: RecordingEntry)] {
        library.allReferences.filter { item in
            kind.includes(item.reference.kind)
                && (topic == nil || item.entry.meta.categories?.contains(topic!) == true)
                && (search.isEmpty || matches(item.reference, search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Kind", selection: $kind) {
                    ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                ForEach(shown, id: \.reference.id) { item in
                    Button {
                        if let url = URL(string: item.reference.url) { opened = WebPage(url: url) }
                    } label: {
                        ReferenceRow(reference: item.reference, fromTitle: item.entry.meta.title)
                    }
                    .contextMenu {
                        if let url = URL(string: item.reference.url) {
                            ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
                            Button {
                                UIPasteboard.general.url = url
                            } label: {
                                Label("Copy link", systemImage: "doc.on.doc")
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await library.deleteReference(item.reference.id, from: item.entry.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if library.allReferences.isEmpty {
                    ContentUnavailableView {
                        Label("No reading yet", systemImage: "books.vertical")
                    } description: {
                        Text("Open a recording in History and tap Find reading. Pearl Forge searches PubMed and the web for research, essays and articles related to your thought, and keeps them here.")
                    }
                } else if shown.isEmpty && !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if shown.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Try a different filter."))
                }
            }
            .navigationTitle("Reading")
            .searchable(text: $search, prompt: "Search your reading")
            .refreshable { await library.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Topic", selection: $topic) {
                            Text("All topics").tag(String?.none)
                            ForEach(library.topicNames, id: \.self) { name in
                                Text(name).tag(String?.some(name))
                            }
                        }
                    } label: {
                        Label(topic ?? "Topic", systemImage: topic == nil
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel(topic.map { "Filtered to \($0)" } ?? "Filter by topic")
                }
            }
            .sheet(item: $opened) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
        }
    }

    private func matches(_ reference: Reference, _ query: String) -> Bool {
        [reference.title, reference.source, reference.note, reference.authors ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

#Preview {
    ReadingView(library: RecordingLibrary())
}
