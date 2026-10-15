import SwiftUI

/// One recording: your original voice note and transcript, and every pearl
/// forged from it, with a button to forge another.
struct RecordingDetailView: View {
    let entryID: String
    let library: RecordingLibrary
    let settings: SettingsModel

    @State private var player = AudioPlayback()
    @State private var showingForgeSheet = false
    @State private var showingTranscript = false

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
            }

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
                                  settings: settings, player: player)
                    } label: {
                        PearlRow(pearl: pearl, text: entry.pearlTexts[pearl.id] ?? "")
                    }
                }
                Button {
                    showingForgeSheet = true
                } label: {
                    Label("Forge a new pearl", systemImage: "sparkles")
                }
                .disabled(library.forging[entry.id] != nil || settings.selectedVoiceID.isEmpty)
            } header: {
                Text("Pearls")
            } footer: {
                if let error = library.forgeErrors[entry.id] {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Each pearl is a fresh run of your original words through the forge. Your recording itself is never changed.")
                }
            }
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
        .sheet(isPresented: $showingForgeSheet) {
            ForgeSheet(initialMode: entry.pearlsNewestFirst.first?.mode ?? .clean) { mode, notes in
                Task {
                    if let result = await library.forgeNewPearl(for: entry.id, mode: mode, notes: notes,
                                                                voiceID: settings.selectedVoiceID) {
                        player.load(result.1, key: result.0.id.uuidString)
                        player.play()
                    }
                }
            }
        }
    }

    /// The pearl loaded in the player, if any (not the original recording).
    private func nowPlayingPearl(in entry: RecordingEntry) -> Pearl? {
        guard let key = player.loadedKey, let id = UUID(uuidString: key) else { return nil }
        return entry.pearl(id)
    }
}

/// A pearl in the list: its number and mode, your request, and how it starts.
private struct PearlRow: View {
    let pearl: Pearl
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Pearl \(pearl.number) · \(pearl.mode.title)")
                .font(.headline)
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
