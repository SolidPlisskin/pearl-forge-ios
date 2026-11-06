import PhotosUI
import SwiftUI

/// The ElevenLabs and fal.ai keys (kept in the Keychain), the voice to speak
/// in, the picture of your avatar and what makes video pearls, and where
/// recordings are saved.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    let library: RecordingLibrary

    @State private var choosingFolder = false
    @State private var storageMessage: String?
    @State private var pickedAvatar: PhotosPickerItem?
    @State private var avatarError: String?

    var body: some View {
        NavigationStack {
            Form {
                keysSection
                voiceSection
                avatarSection
                storageSection
            }
            .navigationTitle("Settings")
            .task { await model.checkSavedKeys() }
            .onChange(of: pickedAvatar) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return }
                        try model.setAvatarPicture(data)
                        avatarError = nil
                    } catch {
                        avatarError = error.localizedDescription
                    }
                    pickedAvatar = nil
                }
            }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                guard case .success(let folder) = result else { return }
                Task {
                    do {
                        let unmoved = try await library.useFolder(folder)
                        if !unmoved.isEmpty {
                            storageMessage = "\(unmoved.count) recording(s) couldn't be moved and stayed on this iPhone (On My iPhone › Pearl Forge › Recordings in the Files app)."
                        }
                    } catch {
                        storageMessage = error.localizedDescription
                    }
                }
            }
            .alert("Storage", isPresented: Binding(get: { storageMessage != nil },
                                                   set: { if !$0 { storageMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storageMessage ?? "")
            }
        }
    }

    private var avatarSection: some View {
        Section {
            if let data = model.avatarPicture, let image = UIImage(data: data) {
                HStack(spacing: 14) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Your avatar")
                }
                PhotosPicker("Choose a different picture…", selection: $pickedAvatar, matching: .images)
                Button("Remove picture", role: .destructive) {
                    model.removeAvatarPicture()
                }
            } else {
                PhotosPicker("Choose a picture of your avatar…", selection: $pickedAvatar, matching: .images)
            }
            videoModelPicker
        } header: {
            Text("Video avatar")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let avatarError {
                    Text(avatarError).foregroundStyle(.red)
                }
                Text(videoFooter)
            }
        }
    }

    private var videoModelPicker: some View {
        NavigationLink {
            VideoModelList(selection: $model.videoModelID)
        } label: {
            LabeledContent("Make videos with", value: model.videoModel.name)
        }
    }

    private var videoFooter: String {
        let picture = "For Make video on a pearl: this picture is animated to speak the pearl in your voice. Use a clear, front-facing still of your ElevenLabs avatar: open it in ElevenLabs Avatars, then save its picture to Photos (or take a screenshot and crop it)."
        let video = model.videoModel
        guard video.isFal else {
            return picture + " Making videos with ElevenLabs needs its Pro plan or higher; on any paid plan you can make them in ElevenLabs and use Add video instead."
        }
        var line = picture + " \(video.name) on fal.ai makes them, paid from your fal.ai balance."
        if model.falStatus == .notSet {
            line += " Add your fal.ai key above first."
        }
        return line + " Pearl Forge asks fal.ai to delete the uploaded picture and audio after a day, and the finished video after a week; your copy stays with the pearl."
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Saved in", value: library.locationName)
            if library.isMoving {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Moving your recordings…")
                }
            } else {
                Button(library.isUsingFolder ? "Choose a different folder…" : "Save to iCloud Drive…") {
                    choosingFolder = true
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let problem = library.storageProblem {
                    Text(problem).foregroundStyle(.red)
                }
                if !library.isUsingFolder {
                    Text("Your recordings are on this iPhone. Tap above, choose iCloud Drive, and tap Open: Pearl Forge will keep them in a “Pearl Forge” folder there, moving the ones you already have.")
                } else if library.isInICloudDrive {
                    Text("Your recordings are in iCloud Drive, also in the Files app on your iPhone and Mac. Your iPhone keeps only what it has room for and downloads a recording again when you play it.")
                } else {
                    Text("Your recordings are in this folder. Recordings move along if you choose a different one.")
                }
            }
        }
    }

    private var keysSection: some View {
        Section {
            NavigationLink {
                KeyEditorView(target: .init(
                    title: "ElevenLabs key",
                    keysPageLabel: "Get your key at elevenlabs.io",
                    keysPage: URL(string: "https://elevenlabs.io/app/settings/api-keys")!,
                    isSaved: model.elevenLabsStatus != .notSet,
                    save: { key, _ in if let key { try model.saveElevenLabsKey(key) } },
                    remove: model.removeElevenLabsKey))
            } label: {
                KeyStatusRow(title: "ElevenLabs", subtitle: "Transcribing and your voice", status: model.elevenLabsStatus)
            }
            if case .failed = model.elevenLabsStatus {
                Button("Check again") {
                    Task { await model.loadVoices() }
                }
            }
            NavigationLink {
                KeyEditorView(target: .init(
                    title: "fal.ai key",
                    keysPageLabel: "Get your key at fal.ai (the API preset is enough)",
                    keysPage: URL(string: "https://fal.ai/dashboard/keys")!,
                    isSaved: model.falStatus != .notSet,
                    save: { key, _ in if let key { try model.saveFalKey(key) } },
                    remove: model.removeFalKey))
            } label: {
                KeyStatusRow(title: "fal.ai", subtitle: falSubtitle, status: model.falStatus)
            }
            if case .failed = model.falStatus {
                Button("Check fal.ai again") {
                    Task { await model.checkFalKey() }
                }
            }
        } header: {
            Text("API keys")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if case .failed(let message) = model.elevenLabsStatus {
                    Text(message).foregroundStyle(.red)
                }
                if case .failed(let message) = model.falStatus {
                    Text(message).foregroundStyle(.red)
                }
                Text("Kept in this iPhone's Keychain: never in the app's code, and never copied off this phone. Keys for the AI that polishes your thoughts are in the AI tab.")
            }
        }
    }

    private var falSubtitle: String {
        if let balance = model.falBalance {
            return "Videos of your avatar · \(balance.dollars) left"
        }
        return "Videos of your avatar"
    }

    private var voiceSection: some View {
        Section {
            switch model.elevenLabsStatus {
            case .notSet:
                Text("Add your ElevenLabs key to choose a voice.")
                    .foregroundStyle(.secondary)
            case .saved, .checking:
                Text("Loading your voices…")
                    .foregroundStyle(.secondary)
            case .failed:
                Text("Your voices couldn't be loaded. Check your ElevenLabs key above.")
                    .foregroundStyle(.secondary)
            case .works:
                if model.voices.isEmpty {
                    Text("This ElevenLabs account has no voices yet.")
                        .foregroundStyle(.secondary)
                } else {
                    voicePicker
                    Button("Refresh voices") {
                        Task { await model.loadVoices() }
                    }
                }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Pearl Forge reads your refined thoughts back in this voice. Voices you made yourself are listed first.")
        }
    }

    private var voicePicker: some View {
        let own = model.voices.filter(\.isOwn)
        let library = model.voices.filter { !$0.isOwn }
        return Picker("Your voice", selection: $model.selectedVoiceID) {
            if !own.isEmpty {
                Section("Your voices") {
                    ForEach(own) { Text($0.name).tag($0.id) }
                }
            }
            if !library.isEmpty {
                Section("ElevenLabs library") {
                    ForEach(library) { Text($0.name).tag($0.id) }
                }
            }
        }
        .pickerStyle(.navigationLink)
    }
}

/// The models that can make videos, with what each costs.
private struct VideoModelList: View {
    @Binding var selection: String

    var body: some View {
        Form {
            Section {
                ForEach(VideoModel.fal) { row($0) }
            } header: {
                Text("fal.ai: pay per video")
            } footer: {
                Text("fal.ai's prices for each minute of speech; a video is as long as its pearl. Try a short pearl first to see which you like.")
            }
            Section {
                row(VideoModel.elevenLabs)
            } header: {
                Text("ElevenLabs")
            }
        }
        .navigationTitle("Make videos with")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ video: VideoModel) -> some View {
        Button {
            selection = video.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.name)
                        .foregroundStyle(Color.primary)
                    Text("\(video.priceLine). \(video.strength).")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                if selection == video.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Chosen")
                }
            }
        }
    }
}

#Preview {
    SettingsView(model: SettingsModel(), library: RecordingLibrary())
}
