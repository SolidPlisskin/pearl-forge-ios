import SwiftUI

/// The ElevenLabs key (kept in the Keychain), the voice to speak in, and
/// where recordings are saved.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    let library: RecordingLibrary

    @State private var choosingFolder = false
    @State private var storageMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                keysSection
                voiceSection
                storageSection
            }
            .navigationTitle("Settings")
            .task { await model.checkSavedKeys() }
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
        } header: {
            Text("API key")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if case .failed(let message) = model.elevenLabsStatus {
                    Text(message).foregroundStyle(.red)
                }
                Text("Kept in this iPhone's Keychain: never in the app's code, and never copied off this phone. Keys for the AI that polishes your thoughts are in the AI tab.")
            }
        }
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

#Preview {
    SettingsView(model: SettingsModel(), library: RecordingLibrary())
}
