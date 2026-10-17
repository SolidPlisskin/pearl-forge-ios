import SwiftUI

/// Choose a recording's topics by hand: tick existing ones or add a new one.
struct TopicEditor: View {
    let entryID: String
    let library: RecordingLibrary

    @State private var selected: [String]
    @State private var newTopic = ""
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss

    init(entryID: String, current: [String], library: RecordingLibrary) {
        self.entryID = entryID
        self.library = library
        _selected = State(initialValue: current)
    }

    /// Your topics first, then the starter topics you haven't used yet, plus
    /// any just added here.
    private var choices: [String] {
        var names = library.topicNames
        for name in TopicSorter.starterTopics + selected
        where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(choices, id: \.self) { name in
                        Button {
                            toggle(name)
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("Selected")
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Recordings that share a topic are gathered together under Topics in History.")
                }

                Section("New topic") {
                    HStack {
                        TextField("For example: Fitness", text: $newTopic)
                            .textInputAutocapitalization(.words)
                            .onSubmit(addNewTopic)
                        Button("Add", action: addNewTopic)
                            .disabled(newTopic.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await library.setCategories(selected, for: entryID)
                                dismiss()
                            } catch {
                                saveError = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { saveError != nil },
                                                        set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func toggle(_ name: String) {
        if let index = selected.firstIndex(of: name) {
            selected.remove(at: index)
        } else {
            selected.append(name)
        }
    }

    private func addNewTopic() {
        let name = newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let existing = choices.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
        if !selected.contains(existing) { selected.append(existing) }
        newTopic = ""
    }
}
