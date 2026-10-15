import AVFoundation
import Observation

/// Records a voice note to an AAC (.m4a) file, one recording at a time.
@MainActor
@Observable
final class VoiceRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Input loudness from 0 to 1, for the level meter.
    private(set) var level: Double = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?

    /// Asks for microphone access the first time; later calls return the
    /// answer the person already gave.
    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Starts recording to `url`, replacing anything already there.
    func start(to url: URL) throws {
        try AudioSession.activateForRecording()
        try? FileManager.default.removeItem(at: url)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw PipelineError(message: "Couldn't start recording. Is another app using the microphone?")
        }
        self.recorder = recorder
        isRecording = true
        elapsed = 0

        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateMeter()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        // A phone call or Siri ends the recording; what was captured is kept.
        interruptionTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                self?.stop()
            }
        }
    }

    /// Stops recording and returns the recording's length in seconds.
    @discardableResult
    func stop() -> TimeInterval {
        guard let recorder else { return 0 }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        meterTask?.cancel()
        interruptionTask?.cancel()
        isRecording = false
        level = 0
        return duration
    }

    private func updateMeter() {
        guard let recorder else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        // averagePower is in decibels, from about -160 (silence) up to 0.
        let decibels = Double(recorder.averagePower(forChannel: 0))
        level = min(1, max(0, (decibels + 50) / 50))
    }
}
