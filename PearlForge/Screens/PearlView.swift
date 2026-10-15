import SwiftUI
import UIKit

/// One pearl: listen to it, share it, edit its text and regenerate the audio,
/// or delete it.
struct PearlView: View {
    let entryID: String
    let pearlID: UUID
    let library: RecordingLibrary
    let settings: SettingsModel
    let player: AudioPlayback

    @State private var text = ""
    @State private var didLoadText = false
    @State private var confirmingDelete = false
    @State private var actionError: String?
    @FocusState private var editing: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let entry = library.entry(entryID), let pearl = entry.pearl(pearlID) {
            content(entry, pearl, savedText: entry.pearlTexts[pearlID] ?? "")
        } else {
            ContentUnavailableView("This pearl was deleted", systemImage: "trash")
        }
    }

    private func content(_ entry: RecordingEntry, _ pearl: Pearl, savedText: String) -> some View {
        let isBusy = library.forging[entryID] != nil
        let isEdited = text.trimmingCharacters(in: .whitespacesAndNewlines)
            != savedText.trimmingCharacters(in: .whitespacesAndNewlines)

        return Form {
            Section {
                LabeledContent("Mode", value: pearl.mode.title)
                if let notes = pearl.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your request")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(notes)
                    }
                }
                LabeledContent("Forged", value: pearl.created.formatted(date: .abbreviated, time: .shortened))
                if let model = pearl.refinedBy, model != PipelineConfig.refinementModel {
                    LabeledContent("Refined by", value: model)
                }
            }

            Section {
                if let step = library.forging[entryID] {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(step.progressLabel)
                    }
                } else if let audioFile = pearl.audioFile {
                    AudioItemRow(title: "Play pearl \(pearl.number)", key: pearl.id.uuidString,
                                 fileExtension: (audioFile as NSString).pathExtension, player: player) {
                        try await library.audioData(audioFile, in: entryID)
                    }
                    Button {
                        Task { await share(audioFile, entry: entry, pearl: pearl) }
                    } label: {
                        Label("Share audio", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Speak it in your voice") {
                        Task { await respeak(savedText) }
                    }
                }
            } header: {
                Text("In your voice")
            } footer: {
                if let error = library.forgeErrors[entryID] ?? actionError {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .focused($editing)
                    .disabled(isBusy)
                if isEdited {
                    Button("Save edits & regenerate audio") {
                        editing = false
                        Task { await respeak(text) }
                    }
                    .disabled(isBusy)
                    Button("Undo edits") {
                        text = savedText
                    }
                } else {
                    ShareLink(item: savedText) {
                        Label("Share text", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Refined text")
            } footer: {
                Text("If anything's off, fix it here, then regenerate the audio.")
            }

            Section {
                Button("Delete this pearl", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(isBusy)
            }
        }
        .navigationTitle("Pearl \(pearl.number)")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }
            }
        }
        .onAppear {
            if !didLoadText {
                text = savedText
                didLoadText = true
            }
        }
        .confirmationDialog("Delete pearl \(pearl.number)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete pearl", role: .destructive) {
                Task {
                    do {
                        if player.loadedKey == pearl.id.uuidString { player.unload() }
                        try await library.deletePearl(pearl.id, from: entryID)
                        dismiss()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Its text and audio will be deleted. Your original recording and other pearls stay.")
        }
    }

    private func respeak(_ newText: String) async {
        if let audio = await library.respeak(pearlID, in: entryID, text: newText,
                                             voiceID: settings.selectedVoiceID) {
            text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            player.load(audio, key: pearlID.uuidString)
            player.play()
        }
    }

    private func share(_ audioFile: String, entry: RecordingEntry, pearl: Pearl) async {
        actionError = nil
        do {
            let audio = try await library.audioData(audioFile, in: entryID)
            let url = try RecordingFiles.shareCopy(of: audio, title: entry.meta.title, pearlNumber: pearl.number)
            presentShareSheet(for: url)
        } catch {
            actionError = "Couldn't prepare the audio: \(error.localizedDescription)"
        }
    }

    /// Shows the system share sheet for a file.
    private func presentShareSheet(for url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              var top = scene.keyWindow?.rootViewController
        else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }
}
