import AVFoundation
import Observation

/// Plays one audio file with play/pause and seeking.
@MainActor
@Observable
final class AudioPlayback {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    func load(_ url: URL) {
        unload()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func unload() {
        pause()
        player = nil
        currentTime = 0
        duration = 0
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
