import SwiftUI

/// A play button for one piece of saved audio. Tapping it fetches the audio
/// (downloading it from iCloud if needed) and plays it; while it's the one
/// loaded, the full player controls take its place.
struct AudioItemRow: View {
    let title: String
    let key: String
    var fileExtension = "mp3"
    let player: AudioPlayback
    let load: () async throws -> Data

    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        if player.loadedKey == key {
            PlayerRow(player: player)
        } else {
            Button {
                Task { await start() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(.primary)
                        if isLoading {
                            Text("Loading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let loadError {
                            Text(loadError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .padding(.vertical, 4)
        }
    }

    private func start() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let data = try await load()
            player.load(data, fileExtension: fileExtension, key: key)
            player.play()
        } catch {
            loadError = "Couldn't load it: \(error.localizedDescription)"
        }
    }
}
