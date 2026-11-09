import PhotosUI
import SwiftUI
import UIKit

/// One pearl: listen to it, share it, turn it into a video of your avatar,
/// edit its text and regenerate the audio, or delete it.
struct PearlView: View {
    let entryID: String
    let pearlID: UUID
    let library: RecordingLibrary
    let settings: SettingsModel
    let polishers: PolishersModel
    let player: AudioPlayback

    @State private var text = ""
    @State private var didLoadText = false
    @State private var confirmingDelete = false
    @State private var actionError: String?
    @State private var videoQuote: String?
    /// The model the quote was worked out for.
    @State private var quotedModel: VideoModel?
    @State private var pickedVideo: PhotosPickerItem?
    @State private var importingVideo = false
    @State private var playingVideo: PlayingVideo?
    @State private var videoActionError: String?
    @FocusState private var editing: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let entry = library.entry(entryID), let pearl = entry.pearl(pearlID) {
            content(entry, pearl, savedText: entry.pearlTexts[pearlID] ?? "")
        } else {
            ContentUnavailableView("This pearl was deleted", systemImage: "trash")
        }
    }

    private func content(_ entry: RecordingEntry, _ pearl: Pearl, savedText: String) -> some View {
        let isBusy = library.forging[entryID] != nil
        let isEdited = text.trimmingCharacters(in: .whitespacesAndNewlines)
            != savedText.trimmingCharacters(in: .whitespacesAndNewlines)

        return Form {
            Section {
                LabeledContent("Mode", value: pearl.mode.title)
                if let language = entry.otherLanguage(of: pearl) {
                    LabeledContent("Language", value: language)
                }
                if let notes = pearl.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your request")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(notes)
                    }
                }
                LabeledContent("Forged", value: pearl.created.formatted(date: .abbreviated, time: .shortened))
                if let by = polishedBy(pearl, polishers: polishers) {
                    LabeledContent("Polished by", value: by)
                }
            }

            Section {
                if let step = library.forging[entryID] {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(step.progressLabel)
                    }
                } else if let audioFile = pearl.audioFile {
                    AudioItemRow(title: "Play pearl \(pearl.number)", key: pearl.id.uuidString,
                                 fileExtension: (audioFile as NSString).pathExtension, player: player) {
                        try await library.audioData(audioFile, in: entryID)
                    }
                    Button {
                        Task { await share(audioFile, entry: entry, pearl: pearl) }
                    } label: {
                        Label("Share audio", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Speak it in your voice") {
                        Task { await respeak(savedText) }
                    }
                }
            } header: {
                Text("In your voice")
            } footer: {
                if let error = library.forgeErrors[entryID] ?? actionError {
                    Text(error).foregroundStyle(.red)
                }
            }

            videoSection(entry, pearl, isBusy: isBusy)

            if let language = entry.otherLanguage(of: pearl) {
                englishSection(pearl, language: language, isEdited: isEdited)
            }

            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .focused($editing)
                    .disabled(isBusy)
                if isEdited {
                    Button("Save edits & regenerate audio") {
                        editing = false
                        Task { await respeak(text) }
                    }
                    .disabled(isBusy)
                    Button("Undo edits") {
                        text = savedText
                    }
                } else {
                    ShareLink(item: savedText) {
                        Label("Share text", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text(entry.otherLanguage(of: pearl).map { "Refined text · \($0)" } ?? "Refined text")
            } footer: {
                Text("If anything's off, fix it here, then regenerate the audio.")
            }

            Section {
                Button("Delete this pearl", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(isBusy)
            }
        }
        .navigationTitle("Pearl \(pearl.number)")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }
            }
        }
        .task {
            if settings.videoModel.isFal {
                if settings.falStatus == .saved { await settings.checkFalKey() }
            } else if settings.credits == nil {
                await settings.refreshCredits()
            }
        }
        .onChange(of: pickedVideo) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                        try await library.addVideo(from: movie.url, to: pearlID, in: entryID)
                        try? FileManager.default.removeItem(at: movie.url)
                        videoActionError = nil
                    }
                } catch {
                    videoActionError = "Couldn't add that video: \(error.localizedDescription)"
                }
                pickedVideo = nil
            }
        }
        .fileImporter(isPresented: $importingVideo, allowedContentTypes: [.movie]) { result in
            guard case .success(let url) = result else { return }
            Task {
                do {
                    try await library.addVideo(from: url, to: pearlID, in: entryID)
                    videoActionError = nil
                } catch {
                    videoActionError = "Couldn't add that video: \(error.localizedDescription)"
                }
            }
        }
        .confirmationDialog("Make a video of pearl \(pearl.number)?",
                            isPresented: Binding(get: { videoQuote != nil }, set: { if !$0 { videoQuote = nil } }),
                            titleVisibility: .visible) {
            Button("Make video") {
                guard let picture = settings.avatarPicture, let model = quotedModel else { return }
                Task { await library.makeVideo(of: pearlID, in: entryID, picture: picture, with: model) }
            }
        } message: {
            Text(videoQuote ?? "")
        }
        .fullScreenCover(item: $playingVideo) { video in
            VideoPlayerScreen(video: video)
        }
        .onAppear {
            if !didLoadText {
                text = savedText
                didLoadText = true
            }
        }
        .confirmationDialog("Delete pearl \(pearl.number)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete pearl", role: .destructive) {
                Task {
                    do {
                        if player.loadedKey == pearl.id.uuidString { player.unload() }
                        try await library.deletePearl(pearl.id, from: entryID)
                        dismiss()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Its text and audio will be deleted. Your original recording and other pearls stay.")
        }
    }

    // MARK: English

    /// What a pearl in another language says, in English.
    private func englishSection(_ pearl: Pearl, language: String, isEdited: Bool) -> some View {
        Section {
            if library.translating.contains(pearlID) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Writing it in English…")
                }
            } else if let english = pearl.english {
                Text(english)
                    .textSelection(.enabled)
            } else if let choice = polishers.activeChoice {
                Button {
                    Task { await library.addEnglish(to: pearlID, in: entryID, with: choice) }
                } label: {
                    Label("Show it in English", systemImage: "character.bubble")
                }
                .disabled(isEdited)
            } else {
                Text("Choose an AI in the AI tab to see this pearl in English.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("In English")
        } footer: {
            if let error = library.translationErrors[pearlID] {
                Text(error).foregroundStyle(.red)
            } else if pearl.english != nil {
                Text("What this pearl says in \(language), translated back so you can follow it. Your pearl itself isn't changed.")
            } else if let choice = polishers.activeChoice {
                Text("\(polishers.label(for: choice)) translates this \(language) pearl back into English so you know what it says. It's saved with the pearl; a short pearl costs about a cent.")
            }
        }
    }

    // MARK: Video

    private func videoSection(_ entry: RecordingEntry, _ pearl: Pearl, isBusy: Bool) -> some View {
        let working = library.videoWork[pearlID]
        let model = settings.videoModel
        let planAllows = model.isFal ? settings.falStatus != .notSet
                                     : AvatarVideo.planAllowsApp(tier: settings.credits?.tier) != false
        return Section {
            if let working {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(working)
                }
            } else {
                if pearl.videoFile != nil {
                    Button {
                        Task { await playVideo() }
                    } label: {
                        HStack(spacing: 14) {
                            VideoStill(entryID: entryID, pearl: pearl, library: library, width: 72, height: 96)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Play video")
                                    .foregroundStyle(.primary)
                                if let seconds = pearl.videoSeconds {
                                    Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if entry.otherLanguage(of: pearl) != nil {
                                    Text(pearl.english == nil ? "Shows the \(entry.otherLanguage(of: pearl) ?? "") text as you watch"
                                                              : "Shows what you're saying in English as you watch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await shareVideo() }
                    } label: {
                        Label("Share video", systemImage: "square.and.arrow.up")
                    }
                }
                if pearl.videoGenerationID != nil {
                    Button {
                        Task { await library.collectVideo(of: pearlID, in: entryID) }
                    } label: {
                        Label("Collect your video from \(pearl.videoModel == nil ? "ElevenLabs" : "fal.ai")",
                              systemImage: "arrow.down.circle")
                    }
                } else if pearl.audioFile != nil {
                    Button {
                        Task { await quoteVideo(pearl) }
                    } label: {
                        Label(pearl.videoFile == nil ? "Make video" : "Make a new video",
                              systemImage: "person.crop.rectangle")
                    }
                    .disabled(isBusy || settings.avatarPicture == nil || !planAllows)
                }
                PhotosPicker(selection: $pickedVideo, matching: .videos) {
                    Label(pearl.videoFile == nil ? "Add video from Photos" : "Replace with a video from Photos",
                          systemImage: "photo.on.rectangle")
                }
                Button {
                    importingVideo = true
                } label: {
                    Label(pearl.videoFile == nil ? "Add video from Files" : "Replace with a video from Files",
                          systemImage: "folder")
                }
                if pearl.videoFile != nil {
                    Button("Remove video", role: .destructive) {
                        Task {
                            do {
                                try await library.removeVideo(of: pearlID, in: entryID)
                            } catch {
                                videoActionError = error.localizedDescription
                            }
                        }
                    }
                }
            }
        } header: {
            Text("As a video")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let error = library.videoErrors[pearlID] ?? videoActionError {
                    Text(error).foregroundStyle(.red)
                }
                if working == nil && pearl.videoFile == nil {
                    if settings.avatarPicture == nil {
                        Text("To make videos here, choose a picture of your avatar in Settings › Video avatar. Or make the video in ElevenLabs Avatars (Share audio sends it this pearl's speech), save it, and add it here.")
                    } else if !planAllows && model.isFal {
                        Text("To make videos with \(model.name), add your fal.ai key in Settings › API keys.")
                    } else if !planAllows {
                        Text(AvatarVideo.needsProMessage + " Or choose a fal.ai model in Settings › Video avatar. Share audio sends ElevenLabs this pearl's speech.")
                    } else {
                        Text("Make video sends your avatar picture and this pearl's audio to \(model.isFal ? "fal.ai (\(model.name))" : "ElevenLabs"), which makes a video of your avatar speaking it. You'll see what it should cost first. To use a different model, go to Settings › Video avatar.")
                    }
                }
                if pearl.videoGenerationID == nil {
                    if let credits = pearl.videoCredits {
                        Text("Making this video used \(credits.formatted()) ElevenLabs credits.")
                    } else if let endpoint = pearl.videoModel, let cost = pearl.videoCost {
                        Text("Made by \(VideoModel.name(ofEndpoint: endpoint)) on fal.ai for about \(cost.dollars).")
                    }
                }
            }
        }
    }

    /// Works out what a video of this pearl should cost, then asks.
    private func quoteVideo(_ pearl: Pearl) async {
        videoActionError = nil
        guard let audioFile = pearl.audioFile,
              let audio = try? await library.audioData(audioFile, in: entryID),
              let seconds = AvatarVideo.seconds(of: audio)
        else {
            videoActionError = "This pearl's audio couldn't be loaded."
            return
        }
        let length = Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
        let model = settings.videoModel
        if model.isFal {
            await settings.refreshFalBalance()
            quoteFalVideo(model, seconds: seconds, length: length)
            return
        }
        var lines: [String] = []
        if let rate = AvatarVideo.creditsPerSecond(from: library.entries.flatMap(\.meta.pearls)) {
            let credits = Int((rate * seconds).rounded())
            var line = "This pearl runs \(length). Judging by your last videos, it should use about \(credits.formatted()) credits"
            if let dollars = settings.credits?.dollarsPerThousand {
                line += " (about \((Double(credits) / 1000 * dollars).dollars) of your plan)"
            }
            lines.append(line + ".")
        } else {
            lines.append("This pearl runs \(length). ElevenLabs doesn't publish what these videos cost, so Pearl Forge will measure this one and estimate the next ones from it. A short pearl is a good first try.")
        }
        if let credits = settings.credits {
            lines.append("You have \(credits.remaining.formatted()) credits left this month.")
        }
        lines.append("It takes a few minutes. Keep Pearl Forge open; if you leave, come back to this pearl to collect the video.")
        quotedModel = model
        videoQuote = lines.joined(separator: "\n\n")
    }

    private func quoteFalVideo(_ model: VideoModel, seconds: Double, length: String) {
        if let longest = model.maxSeconds, seconds > longest {
            let limit = Duration.seconds(longest).formatted(.time(pattern: .minuteSecond))
            videoActionError = "\(model.name) takes pearls up to \(limit), and this one runs \(length). Choose another model in Settings › Video avatar."
            return
        }
        var lines: [String] = []
        if let cost = model.cost(seconds: seconds), let rate = model.dollarsPerSecond {
            lines.append("This pearl runs \(length). With \(model.name) it should cost about \(cost.dollars) (fal.ai charges \(rate.formatted(.currency(code: "USD").precision(.fractionLength(2...4)))) a second).")
        }
        if let balance = settings.falBalance {
            lines.append("Your fal.ai balance is \(balance.dollars).")
        }
        lines.append("It takes a few minutes. Keep Pearl Forge open; if you leave, come back to this pearl to collect the video.")
        quotedModel = model
        videoQuote = lines.joined(separator: "\n\n")
    }

    private func playVideo() async {
        videoActionError = nil
        do {
            player.pause()
            playingVideo = try await PlayingVideo.load(pearlID, in: entryID, library: library)
        } catch {
            videoActionError = "Couldn't open the video: \(error.localizedDescription)"
        }
    }

    private func shareVideo() async {
        videoActionError = nil
        do {
            presentShareSheet(for: try await library.videoCopy(of: pearlID, in: entryID))
        } catch {
            videoActionError = "Couldn't prepare the video: \(error.localizedDescription)"
        }
    }

    private func respeak(_ newText: String) async {
        if let audio = await library.respeak(pearlID, in: entryID, text: newText,
                                             voiceID: settings.selectedVoiceID) {
            text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            player.load(audio, key: pearlID.uuidString)
            player.play()
            // Edited text loses its English version; write a fresh one.
            if let choice = polishers.activeChoice {
                await library.addEnglishIfMissing(to: pearlID, in: entryID, with: choice)
            }
        }
    }

    private func share(_ audioFile: String, entry: RecordingEntry, pearl: Pearl) async {
        actionError = nil
        do {
            let audio = try await library.audioData(audioFile, in: entryID)
            let url = try RecordingFiles.shareCopy(of: audio, title: entry.meta.title, pearlNumber: pearl.number)
            presentShareSheet(for: url)
        } catch {
            actionError = "Couldn't prepare the audio: \(error.localizedDescription)"
        }
    }

    /// Shows the system share sheet for a file.
    private func presentShareSheet(for url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              var top = scene.keyWindow?.rootViewController
        else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }
}

/// A video picked from Photos, copied somewhere Pearl Forge can read it.
private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.temporaryDirectory.appending(path: UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
