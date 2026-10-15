import SwiftUI

/// Choose which AI polishes your thoughts, and set up each service.
struct AIView: View {
    @Bindable var polishers: PolishersModel

    var body: some View {
        NavigationStack {
            Form {
                activeSection
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
                ModelPickerView(provider: provider, polishers: polishers)
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
                        polishers.selectModel(model.id, name: model.name, for: provider)
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
                            if polishers.selectedModels[provider] == model.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                }
            } footer: {
                if provider == .anthropic {
                    Text("Pearl Forge was built and tested with Claude Opus 5.5.")
                }
            }

            Section {
                TextField("Model id", text: $customID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Use this model") {
                    polishers.selectModel(customID.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
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
