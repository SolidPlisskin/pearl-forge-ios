import Foundation
import Observation

/// Whether a saved key has been checked against its service.
enum KeyStatus: Equatable {
    case notSet
    case saved
    case checking
    case works
    case failed(String)
}

/// State behind the Settings screen: which keys are saved and working, the
/// account's voices, and the chosen voice. Keys live in the Keychain; the voice
/// choice isn't secret, so it lives in UserDefaults.
@MainActor
@Observable
final class SettingsModel {
    static let voiceIDKey = "selectedVoiceID"
    static let voiceNameKey = "selectedVoiceName"

    private(set) var elevenLabsStatus: KeyStatus
    private(set) var anthropicStatus: KeyStatus
    private(set) var voices: [Voice] = []

    var selectedVoiceID: String {
        didSet {
            UserDefaults.standard.set(selectedVoiceID, forKey: Self.voiceIDKey)
            refreshSelectedVoiceName()
        }
    }

    /// Remembered so the chosen voice can be named even before the voice list
    /// has loaded.
    private(set) var selectedVoiceName: String {
        didSet { UserDefaults.standard.set(selectedVoiceName, forKey: Self.voiceNameKey) }
    }

    init() {
        elevenLabsStatus = KeychainStore.read(.elevenLabsKey) == nil ? .notSet : .saved
        anthropicStatus = KeychainStore.read(.anthropicKey) == nil ? .notSet : .saved
        selectedVoiceID = UserDefaults.standard.string(forKey: Self.voiceIDKey) ?? ""
        selectedVoiceName = UserDefaults.standard.string(forKey: Self.voiceNameKey) ?? ""
    }

    /// Checks any saved key that hasn't been checked yet this launch.
    func checkSavedKeys() async {
        await withTaskGroup(of: Void.self) { group in
            if elevenLabsStatus == .saved {
                group.addTask { await self.loadVoices() }
            }
            if anthropicStatus == .saved {
                group.addTask { await self.checkAnthropic() }
            }
        }
    }

    /// Re-checks both keys, e.g. after a network hiccup.
    func recheckKeys() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadVoices() }
            group.addTask { await self.checkAnthropic() }
        }
    }

    // MARK: ElevenLabs

    func saveElevenLabsKey(_ key: String) throws {
        try KeychainStore.save(key, for: .elevenLabsKey)
        elevenLabsStatus = .saved
        voices = []
        Task { await loadVoices() }
    }

    func removeElevenLabsKey() {
        KeychainStore.delete(.elevenLabsKey)
        elevenLabsStatus = .notSet
        voices = []
    }

    /// Loading the voice list doubles as the ElevenLabs key check.
    func loadVoices() async {
        guard let key = KeychainStore.read(.elevenLabsKey) else {
            elevenLabsStatus = .notSet
            return
        }
        elevenLabsStatus = .checking
        do {
            voices = try await ElevenLabsClient(apiKey: key).listVoices()
            elevenLabsStatus = .works
            // Keep the saved choice if it still exists; otherwise start on the
            // first voice, which is one of your own when you have any.
            if !voices.contains(where: { $0.id == selectedVoiceID }), let first = voices.first {
                selectedVoiceID = first.id
            } else {
                refreshSelectedVoiceName()
            }
        } catch {
            elevenLabsStatus = .failed(error.localizedDescription)
        }
    }

    private func refreshSelectedVoiceName() {
        if let voice = voices.first(where: { $0.id == selectedVoiceID }) {
            selectedVoiceName = voice.name
        }
    }

    // MARK: Anthropic

    /// Saves a newly typed key (if any) and the optional workspace ID, then
    /// re-checks access.
    func saveAnthropic(key: String?, workspaceID: String) throws {
        if let key {
            try KeychainStore.save(key, for: .anthropicKey)
        }
        if workspaceID.isEmpty {
            KeychainStore.delete(.anthropicWorkspaceID)
        } else {
            try KeychainStore.save(workspaceID, for: .anthropicWorkspaceID)
        }
        anthropicStatus = .saved
        Task { await checkAnthropic() }
    }

    func removeAnthropicKey() {
        KeychainStore.delete(.anthropicKey)
        anthropicStatus = .notSet
    }

    func checkAnthropic() async {
        guard let key = KeychainStore.read(.anthropicKey) else {
            anthropicStatus = .notSet
            return
        }
        anthropicStatus = .checking
        do {
            let client = AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
            try await client.checkAccess()
            anthropicStatus = .works
        } catch {
            anthropicStatus = .failed(error.localizedDescription)
        }
    }
}
