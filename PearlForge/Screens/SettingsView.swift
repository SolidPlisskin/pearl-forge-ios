import SwiftUI

/// API keys (kept in the Keychain) and the ElevenLabs voice to speak in.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        NavigationStack {
            Form {
                keysSection
                voiceSection
            }
            .navigationTitle("Settings")
            .task { await model.checkSavedKeys() }
        }
    }

    private var keysSection: some View {
        Section {
            NavigationLink {
                KeyEditorView(service: .elevenLabs, model: model)
            } label: {
                KeyStatusRow(title: "ElevenLabs", status: model.elevenLabsStatus)
            }
            NavigationLink {
                KeyEditorView(service: .anthropic, model: model)
            } label: {
                KeyStatusRow(title: "Anthropic", status: model.anthropicStatus)
            }
            if hasFailedKey {
                Button("Check again") {
                    Task { await model.recheckKeys() }
                }
            }
        } header: {
            Text("API keys")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if case .failed(let message) = model.elevenLabsStatus {
                    Text(message).foregroundStyle(.red)
                }
                if case .failed(let message) = model.anthropicStatus {
                    Text(message).foregroundStyle(.red)
                }
                Text("Kept in this iPhone's Keychain: never in the app's code, and never copied off this phone.")
            }
        }
    }

    private var hasFailedKey: Bool {
        if case .failed = model.elevenLabsStatus { return true }
        if case .failed = model.anthropicStatus { return true }
        return false
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

/// One key's name and whether it's saved and working.
private struct KeyStatusRow: View {
    let title: String
    let status: KeyStatus

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            statusView
        }
        // Keep the divider lined up with the row title, not the status label.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .notSet:
            Text("Not set").foregroundStyle(.secondary)
        case .saved:
            Text("Saved").foregroundStyle(.secondary)
        case .checking:
            Text("Checking…").foregroundStyle(.secondary)
        case .works:
            Label("Works", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Not working", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    SettingsView(model: SettingsModel())
}
