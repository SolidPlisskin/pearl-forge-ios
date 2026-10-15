import SwiftUI

/// Paste in, replace, or remove one service's API key. A saved key is never
/// shown again, only replaced.
struct KeyEditorView: View {
    /// What the key is for and how to save it.
    struct Target {
        let title: String
        let keysPageLabel: String
        let keysPage: URL
        /// Claude keys can belong to an organization that needs a workspace ID.
        var usesWorkspace = false
        let isSaved: Bool
        /// Saves a newly typed key (nil keeps the current one) and workspace.
        let save: (_ key: String?, _ workspaceID: String) throws -> Void
        let remove: () -> Void
    }

    let target: Target

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var workspaceID = ""
    @State private var savedWorkspaceID = ""
    @State private var saveError: String?
    @State private var confirmingRemove = false

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedWorkspaceID: String {
        workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        if !trimmedKey.isEmpty { return true }
        // A saved Claude key can have just its workspace changed.
        return target.usesWorkspace && target.isSaved && trimmedWorkspaceID != savedWorkspaceID
    }

    var body: some View {
        Form {
            Section {
                SecureField(target.isSaved ? "Paste a new key to replace it" : "Paste your key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if canSave { save() } }
            } header: {
                Text("API key")
            } footer: {
                Link(target.keysPageLabel, destination: target.keysPage)
            }

            if target.usesWorkspace {
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

            if target.isSaved {
                Section {
                    Button("Remove key", role: .destructive) {
                        confirmingRemove = true
                    }
                }
            }
        }
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .onAppear {
            if target.usesWorkspace {
                savedWorkspaceID = KeychainStore.read(.anthropicWorkspaceID) ?? ""
                workspaceID = savedWorkspaceID
            }
        }
        .confirmationDialog("Remove this key from your iPhone?", isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button("Remove key", role: .destructive) {
                target.remove()
                dismiss()
            }
        } message: {
            Text("You'll need to paste it in again to use this service, and most services only show a key once.")
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
            try target.save(trimmedKey.isEmpty ? nil : trimmedKey, trimmedWorkspaceID)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// A key's name and whether it's saved and working.
struct KeyStatusRow: View {
    let title: String
    var subtitle: String?
    let status: KeyStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
