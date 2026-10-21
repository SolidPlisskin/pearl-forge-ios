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

/// State behind the Settings screen: the ElevenLabs key, the account's voices,
/// and the chosen voice. The key lives in the Keychain; the voice choice isn't
/// secret, so it lives in UserDefaults. AI polishing keys are in PolishersModel.
@MainActor
@Observable
final class SettingsModel {
    static let voiceIDKey = "selectedVoiceID"
    static let voiceNameKey = "selectedVoiceName"

    private(set) var elevenLabsStatus: KeyStatus
    private(set) var voices: [Voice] = []
    /// Your ElevenLabs plan's credits this month, when the key may read them.
    private(set) var credits: VoiceCredits?

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
        selectedVoiceID = UserDefaults.standard.string(forKey: Self.voiceIDKey) ?? ""
        selectedVoiceName = UserDefaults.standard.string(forKey: Self.voiceNameKey) ?? ""
    }

    /// Checks the saved key if it hasn't been checked yet this launch.
    func checkSavedKeys() async {
        if elevenLabsStatus == .saved {
            await loadVoices()
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
        credits = nil
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

    /// Reads how many credits your plan has left. Quietly leaves them unknown
    /// if the key isn't allowed to read your account.
    func refreshCredits() async {
        guard let key = KeychainStore.read(.elevenLabsKey) else {
            credits = nil
            return
        }
        credits = try? await ElevenLabsClient(apiKey: key).credits()
    }

    private func refreshSelectedVoiceName() {
        if let voice = voices.first(where: { $0.id == selectedVoiceID }) {
            selectedVoiceName = voice.name
        }
    }
}
