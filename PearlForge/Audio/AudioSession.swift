import AVFoundation

/// Switches the app's audio setup between recording and listening.
enum AudioSession {
    /// Recording from the microphone. Pearl Forge keeps recording with the
    /// screen locked.
    static func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    /// The listening setup, without taking over other apps' sound yet:
    /// Pearl Forge's audio and videos then play wherever you pick, the
    /// iPhone's speaker included, even in silent mode. Set at launch and
    /// after each recording.
    static func prepareForPlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    /// Listening back: plays through AirPods, the car, or the speaker, keeps
    /// playing with the screen locked, and isn't silenced by the ring switch.
    static func activateForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }
}
