import AVFoundation
import Observation

/// Plays one piece of audio at a time, with play/pause and seeking.
@MainActor
@Observable
final class AudioPlayback {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Identifies what's loaded (for example a pearl's id), so a screen with
    /// several recordings knows which one the controls belong to.
    private(set) var loadedKey: String?

    /// Called when the audio plays through to the end (not when paused).
    @ObservationIgnored var onFinish: (() -> Void)?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    /// Loads audio data; `fileExtension` ("mp3", "m4a") helps identify it.
    func load(_ data: Data, fileExtension: String = "mp3", key: String? = nil) {
        unload()
        let hint = fileExtension == "m4a" ? AVFileType.m4a.rawValue : AVFileType.mp3.rawValue
        player = try? AVAudioPlayer(data: data, fileTypeHint: hint)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        loadedKey = key
    }

    func unload() {
        pause()
        player = nil
        currentTime = 0
        duration = 0
        loadedKey = nil
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard let player else { return }
        try? AudioSession.activateForPlayback()
        player.play()
        isPlaying = true
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled, let self, let player = self.player {
                self.currentTime = player.currentTime
                // The player stops by itself at the end of the file.
                if !player.isPlaying {
                    self.isPlaying = false
                    self.onFinish?()
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTask?.cancel()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }
}
