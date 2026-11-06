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

/// State behind the Settings screen: the ElevenLabs and fal.ai keys, the
/// account's voices, the chosen voice, and what makes videos. Keys live in the
/// Keychain; the choices aren't secret, so they live in UserDefaults. AI
/// polishing keys are in PolishersModel.
@MainActor
@Observable
final class SettingsModel {
    static let voiceIDKey = "selectedVoiceID"
    static let voiceNameKey = "selectedVoiceName"

    private(set) var elevenLabsStatus: KeyStatus
    private(set) var voices: [Voice] = []
    /// Your ElevenLabs plan's credits this month, when the key may read them.
    private(set) var credits: VoiceCredits?
    /// A picture of your ElevenLabs avatar, for making video pearls.
    private(set) var avatarPicture: Data?
    private(set) var falStatus: KeyStatus
    /// Your fal.ai balance in dollars, when the key may read it.
    private(set) var falBalance: Double?

    /// What makes videos of your avatar.
    var videoModelID: String {
        didSet { UserDefaults.standard.set(videoModelID, forKey: AvatarVideo.chosenModelKey) }
    }

    var videoModel: VideoModel { VideoModel.withID(videoModelID) }

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
        avatarPicture = AvatarVideo.picture
        falStatus = KeychainStore.read(.falKey) == nil ? .notSet : .saved
        videoModelID = VideoModel.withID(UserDefaults.standard.string(forKey: AvatarVideo.chosenModelKey)).id
    }

    /// Checks the saved keys if they haven't been checked yet this launch.
    func checkSavedKeys() async {
        if elevenLabsStatus == .saved {
            await loadVoices()
        }
        if falStatus == .saved {
            await checkFalKey()
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

    // MARK: fal.ai

    func saveFalKey(_ key: String) throws {
        try KeychainStore.save(key, for: .falKey)
        falStatus = .saved
        falBalance = nil
        Task { await checkFalKey() }
    }

    func removeFalKey() {
        KeychainStore.delete(.falKey)
        falStatus = .notSet
        falBalance = nil
    }

    /// Reading the balance doubles as the fal.ai key check.
    func checkFalKey() async {
        guard let key = KeychainStore.read(.falKey) else {
            falStatus = .notSet
            return
        }
        falStatus = .checking
        do {
            falBalance = try await FalClient(apiKey: key).balance()
            falStatus = .works
        } catch {
            falStatus = .failed(error.localizedDescription)
        }
    }

    /// Reads your fal.ai balance again. Quietly leaves it unknown if the key
    /// isn't allowed to read billing.
    func refreshFalBalance() async {
        guard let key = KeychainStore.read(.falKey) else {
            falBalance = nil
            return
        }
        falBalance = (try? await FalClient(apiKey: key).balance()) ?? nil
    }

    // MARK: Video avatar

    func setAvatarPicture(_ data: Data) throws {
        try AvatarVideo.savePicture(data)
        avatarPicture = AvatarVideo.picture
    }

    func removeAvatarPicture() {
        AvatarVideo.removePicture()
        avatarPicture = nil
    }

    private func refreshSelectedVoiceName() {
        if let voice = voices.first(where: { $0.id == selectedVoiceID }) {
            selectedVoiceName = voice.name
        }
    }
}
