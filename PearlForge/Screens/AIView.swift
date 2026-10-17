import SwiftUI

/// Choose which AI polishes your thoughts, and set up each service.
struct AIView: View {
    @Bindable var polishers: PolishersModel

    var body: some View {
        NavigationStack {
            Form {
                activeSection
                readingSection
                Section {
                    ForEach(PolisherProvider.allCases) { provider in
                        NavigationLink {
                            ProviderView(provider: provider, polishers: polishers)
                        } label: {
                            KeyStatusRow(title: provider.name, subtitle: subtitle(for: provider),
                                         status: polishers.status[provider] ?? .notSet)
                        }
                    }
                } header: {
                    Text("AI services")
                } footer: {
                    Text("Each service needs its own API key and bills your account with it directly. Keys are kept in this iPhone's Keychain.")
                }
            }
            .navigationTitle("AI")
            .task { await polishers.checkSavedKeys() }
        }
    }

    @ViewBuilder
    private var readingSection: some View {
        Section {
            if polishers.status[.anthropic] == .works {
                NavigationLink {
                    ModelPickerView(provider: .anthropic, polishers: polishers, selected: polishers.readingModel,
                                    note: "Sonnet 5.5 costs about half as much per search as Opus 5.5.") { id, name in
                        polishers.selectReadingModel(id, name: name)
                    }
                } label: {
                    LabeledContent("Model", value: polishers.readingModelLabel)
                }
            } else {
                LabeledContent("Model", value: polishers.readingModelLabel)
            }
        } header: {
            Text("Finding reading")
        } footer: {
            if polishers.status[.anthropic] == .notSet {
                Text("Find reading searches the web with Claude, so it needs your Claude key, whichever AI polishes.")
            } else {
                Text("Find reading always uses Claude, because it searches the web with Claude's search tool. Each search costs roughly 5–15¢ with Sonnet 5.5, or about 25¢ with Opus 5.5, which digs a little deeper.")
            }
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        let ready = polishers.readyProviders
        Section {
            if ready.isEmpty {
                Text("Set up one of the services below to start polishing.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Polish with", selection: $polishers.active) {
                    ForEach(ready) { provider in
                        if let choice = polishers.choice(for: provider) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                Text(polishers.modelName(choice.model, for: provider))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(provider)
                        }
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } header: {
            Text("Polishing with")
        } footer: {
            Text("Every AI gets the same polishing instructions, word for word. When you forge a new pearl from History, you can pick a different AI for just that pearl and compare.")
        }
    }

    private func subtitle(for provider: PolisherProvider) -> String {
        if let model = polishers.selectedModels[provider], polishers.status[provider] != .notSet {
            return polishers.modelName(model, for: provider)
        }
        return provider.company
    }
}

/// One service: its key, which of its models to use, and whether it's the
/// default polisher.
struct ProviderView: View {
    let provider: PolisherProvider
    @Bindable var polishers: PolishersModel

    private var status: KeyStatus { polishers.status[provider] ?? .notSet }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    KeyEditorView(target: .init(
                        title: "\(provider.name) key",
                        keysPageLabel: provider.keysPageLabel,
                        keysPage: provider.keysPage,
                        usesWorkspace: provider == .anthropic,
                        isSaved: status != .notSet,
                        save: { key, workspace in try polishers.saveKey(key, workspaceID: workspace, for: provider) },
                        remove: { polishers.removeKey(for: provider) }))
                } label: {
                    KeyStatusRow(title: "API key", status: status)
                }
                if case .failed = status {
                    Button("Check again") {
                        Task { await polishers.check(provider) }
                    }
                }
            } header: {
                Text(provider.company)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if case .failed(let message) = status {
                        Text(message).foregroundStyle(.red)
                    }
                    Text(provider.about)
                    if status == .notSet {
                        Link(provider.keysPageLabel, destination: provider.keysPage)
                    }
                }
            }

            Section {
                modelRow
            } header: {
                Text("Model")
            } footer: {
                if status == .works {
                    Text("Bigger models usually keep your meaning and voice more faithfully; smaller ones are faster and cheaper.")
                }
            }

            if polishers.isReady(provider) {
                Section {
                    if polishers.active == provider, case .failed = status {
                        Label("Pearl Forge is set to polish with \(provider.name), but this key isn't working",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if polishers.active == provider {
                        Label("Pearl Forge is polishing with \(provider.name)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Polish with \(provider.name)") {
                            polishers.active = provider
                        }
                    }
                }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var modelRow: some View {
        switch status {
        case .notSet:
            Text("Add your key to see the models you can use.")
                .foregroundStyle(.secondary)
        case .saved, .checking:
            Text("Loading models…")
                .foregroundStyle(.secondary)
        case .failed:
            Text("The models couldn't be loaded. Check your key above.")
                .foregroundStyle(.secondary)
        case .works:
            NavigationLink {
                ModelPickerView(provider: provider, polishers: polishers, selected: polishers.selectedModels[provider],
                                note: provider == .anthropic ? "Pearl Forge was built and tested with Claude Opus 5.5." : nil) { id, name in
                    polishers.selectModel(id, name: name, for: provider)
                }
            } label: {
                LabeledContent("Model") {
                    if let model = polishers.selectedModels[provider] {
                        Text(polishers.modelName(model, for: provider))
                    } else {
                        Text("Choose a model").foregroundStyle(.orange)
                    }
                }
            }
            Button("Refresh models") {
                Task { await polishers.check(provider) }
            }
        }
    }
}

/// Pick one of a service's models, or type the id of one that isn't listed.
struct ModelPickerView: View {
    let provider: PolisherProvider
    let polishers: PolishersModel
    /// The model currently chosen.
    let selected: String?
    /// A line shown under the list.
    let note: String?
    let onSelect: (_ id: String, _ name: String?) -> Void

    @State private var search = ""
    @State private var customID = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [AIModel] {
        let all = polishers.models[provider] ?? []
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                ForEach(shown) { model in
                    Button {
                        onSelect(model.id, model.name)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .foregroundStyle(.primary)
                                if model.name != model.id {
                                    Text(model.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selected == model.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                }
            } footer: {
                if let note {
                    Text(note)
                }
            }

            Section {
                TextField("Model id", text: $customID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Use this model") {
                    onSelect(customID.trimmingCharacters(in: .whitespacesAndNewlines), nil)
                    dismiss()
                }
                .disabled(customID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Not in the list?")
            } footer: {
                Text("Type the exact model id from \(provider == .openrouter ? "OpenRouter" : provider.company)'s documentation.")
            }
        }
        .overlay {
            if shown.isEmpty && !search.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search models")
        .navigationTitle("\(provider.name) models")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    AIView(polishers: PolishersModel())
}
