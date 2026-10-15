import SwiftUI

/// Choose how to forge another pearl from a recording: the mode, which AI
/// polishes it, and anything you want different this time.
struct ForgeSheet: View {
    let polishers: PolishersModel
    let onForge: (RefinementMode, String?, PolisherChoice) -> Void

    @State private var mode: RefinementMode
    @State private var provider: PolisherProvider
    @State private var notes = ""
    @Environment(\.dismiss) private var dismiss

    init(initialMode: RefinementMode, polishers: PolishersModel,
         onForge: @escaping (RefinementMode, String?, PolisherChoice) -> Void) {
        _mode = State(initialValue: initialMode)
        _provider = State(initialValue: polishers.activeChoice?.provider
                          ?? polishers.readyProviders.first ?? .anthropic)
        self.polishers = polishers
        self.onForge = onForge
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Refinement", selection: $mode) {
                        ForEach(RefinementMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How much refinement?")
                } footer: {
                    Text(mode.subtitleSentence)
                }

                Section {
                    Picker("Polish with", selection: $provider) {
                        ForEach(polishers.readyProviders) { provider in
                            if let choice = polishers.choice(for: provider) {
                                Text(polishers.label(for: choice)).tag(provider)
                            }
                        }
                    }
                } footer: {
                    Text("Change models for each service in the AI tab.")
                }

                Section {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Anything to change this time?")
                } footer: {
                    Text("For example: “keep the bridge analogy”, “make it under a minute”, or “drop the tangent about work”. Leave it blank to use the mode as is. Your original recording is always the starting point.")
                }
            }
            .navigationTitle("Forge a new pearl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Forge") {
                        guard let choice = polishers.choice(for: provider) else { return }
                        let request = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        onForge(mode, request.isEmpty ? nil : request, choice)
                        dismiss()
                    }
                    .disabled(polishers.choice(for: provider) == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ForgeSheet(initialMode: .tighten, polishers: PolishersModel()) { _, _, _ in }
}
