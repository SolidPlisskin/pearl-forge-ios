import SwiftUI

/// Choose how to forge another pearl from a recording: the mode, and anything
/// you want different this time.
struct ForgeSheet: View {
    let onForge: (RefinementMode, String?) -> Void

    @State private var mode: RefinementMode
    @State private var notes = ""
    @Environment(\.dismiss) private var dismiss

    init(initialMode: RefinementMode, onForge: @escaping (RefinementMode, String?) -> Void) {
        _mode = State(initialValue: initialMode)
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
                        let request = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        onForge(mode, request.isEmpty ? nil : request)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ForgeSheet(initialMode: .tighten) { _, _ in }
}
