import AVKit
import SwiftUI

/// A still from a pearl's video, with a play mark, or a film placeholder
/// while there's no still (the video is still being made, or is in iCloud).
struct VideoStill: View {
    let entryID: String
    let pearl: Pearl
    let library: RecordingLibrary
    var width: CGFloat = 54
    var height: CGFloat = 72

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.tint.opacity(0.15))
                Image(systemName: pearl.videoFile == nil ? "hourglass" : "film")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            if pearl.videoFile != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: min(width, height) * 0.38))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: "\(pearl.videoFile ?? "")#\(library.videoRevisions[pearl.id] ?? 0)") {
            image = await library.videoStill(of: pearl.id, in: entryID)
        }
        .accessibilityHidden(true)
    }
}

/// A pearl's video ready to play, with what it says in English when it's in
/// another language.
struct PlayingVideo: Identifiable {
    let url: URL
    /// The pearl's text, as spoken in the video.
    var text: String?
    /// The language it's spoken in when that isn't yours, and its English version.
    var language: String?
    var english: String?

    var id: URL { url }

    /// Copies the pearl's video out for playing (downloading it from iCloud
    /// if needed) and gathers its words.
    @MainActor
    static func load(_ pearlID: UUID, in entryID: String, library: RecordingLibrary) async throws -> PlayingVideo {
        let url = try await library.videoCopy(of: pearlID, in: entryID)
        guard let entry = library.entry(entryID), let pearl = entry.pearl(pearlID) else { return PlayingVideo(url: url) }
        return PlayingVideo(url: url, text: entry.pearlTexts[pearlID], language: entry.otherLanguage(of: pearl),
                            english: pearl.english)
    }
}

/// Plays a pearl's video full screen, with its words underneath: in English
/// for a pearl in another language (switchable to the original), so you can
/// follow what your avatar is saying.
struct VideoPlayerScreen: View {
    let video: PlayingVideo

    @State private var player: AVPlayer?
    @State private var showingOriginal = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VideoPlayer(player: player)
                if let words {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(wordsLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let language = video.language, video.english != nil {
                                    Button(showingOriginal ? "Show English" : "Show \(language)") {
                                        showingOriginal.toggle()
                                    }
                                    .font(.caption)
                                }
                            }
                            Text(words)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .frame(maxHeight: 240)
                    .background(Color(white: 0.11))
                }
            }
            .background(.black)
            .environment(\.colorScheme, .dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            let player = AVPlayer(url: video.url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }

    /// The English version unless you switched to the original; the text
    /// itself for a pearl in your language.
    private var words: String? {
        if video.language != nil, !showingOriginal { return video.english ?? video.text }
        return video.text
    }

    private var wordsLabel: String {
        guard let language = video.language else { return "What you're saying" }
        if showingOriginal || video.english == nil { return "What you're saying, in \(language)" }
        return "What you're saying, in English"
    }
}
