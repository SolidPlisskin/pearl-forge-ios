import SwiftUI

/// Paste in, replace, or remove one service's API key. A saved key is never
/// shown again, only replaced.
struct KeyEditorView: View {
    enum Service {
        case elevenLabs
        case anthropic

        var title: String {
            switch self {
            case .elevenLabs: return "ElevenLabs key"
            case .anthropic: return "Anthropic key"
            }
        }

        var keysPageLabel: String {
            switch self {
            case .elevenLabs: return "Get your key at elevenlabs.io"
            case .anthropic: return "Get your key at console.anthropic.com"
            }
        }

        var keysPage: URL {
            switch self {
            case .elevenLabs: return URL(string: "https://elevenlabs.io/app/settings/api-keys")!
            case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
            }
        }
    }

    let service: Service
    let model: SettingsModel

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var workspaceID = ""
    @State private var savedWorkspaceID = ""
    @State private var saveError: String?
    @State private var confirmingRemove = false

    private var isSaved: Bool {
        let status = service == .elevenLabs ? model.elevenLabsStatus : model.anthropicStatus
        return status != .notSet
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedWorkspaceID: String {
        workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        if !trimmedKey.isEmpty { return true }
        // A saved Anthropic key can have just its workspace changed.
        return service == .anthropic && isSaved && trimmedWorkspaceID != savedWorkspaceID
    }

    var body: some View {
        Form {
            Section {
                SecureField(isSaved ? "Paste a new key to replace it" : "Paste your key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if canSave { save() } }
            } header: {
                Text("API key")
            } footer: {
                Link(service.keysPageLabel, destination: service.keysPage)
            }

            if service == .anthropic {
                Section {
                    TextField("Workspace ID", text: $workspaceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Workspace (optional)")
                } footer: {
                    Text("Only needed if your key belongs to an organization that asks for a workspace. Leave it blank otherwise.")
                }
            }

            if isSaved {
                Section {
                    Button("Remove key", role: .destructive) {
                        confirmingRemove = true
                    }
                }
            }
        }
        .navigationTitle(service.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .onAppear {
            savedWorkspaceID = KeychainStore.read(.anthropicWorkspaceID) ?? ""
            workspaceID = savedWorkspaceID
        }
        .confirmationDialog("Remove this key from your iPhone?", isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button("Remove key", role: .destructive, action: remove)
        } message: {
            Text("Pearl Forge can't work without it. You'll need to paste it in again, and most services only show a key once.")
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func save() {
        do {
            switch service {
            case .elevenLabs:
                try model.saveElevenLabsKey(trimmedKey)
            case .anthropic:
                try model.saveAnthropic(key: trimmedKey.isEmpty ? nil : trimmedKey,
                                        workspaceID: trimmedWorkspaceID)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func remove() {
        switch service {
        case .elevenLabs: model.removeElevenLabsKey()
        case .anthropic: model.removeAnthropicKey()
        }
        dismiss()
    }
}
