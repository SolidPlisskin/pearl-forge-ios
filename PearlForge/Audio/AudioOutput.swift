import AVFoundation
import Observation
import UIKit

/// Where Pearl Forge's sound is playing right now ("iPhone speaker",
/// "AirPods Pro"), kept up to date as AirPods connect, the car takes over,
/// or you pick somewhere else.
@MainActor
@Observable
final class AudioOutput {
    static let shared = AudioOutput()

    private(set) var name = ""
    /// An SF Symbol for it.
    private(set) var symbol = "iphone"

    @ObservationIgnored private var watcher: Task<Void, Never>?

    private init() {
        refresh()
        watcher = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                self?.refresh()
            }
        }
    }

    func refresh() {
        let device = UIDevice.current.model
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            (name, symbol) = (device, "iphone")
            return
        }
        switch port.portType {
        case .builtInSpeaker:
            (name, symbol) = ("\(device) speaker", "iphone")
        case .builtInReceiver:
            (name, symbol) = ("\(device) earpiece", "iphone")
        case .headphones:
            (name, symbol) = ("Headphones", "headphones")
        case .airPlay:
            (name, symbol) = (port.portName, "airplayaudio")
        case .carAudio:
            (name, symbol) = (port.portName, "car.fill")
        case .HDMI:
            (name, symbol) = (port.portName, "tv")
        default:
            (name, symbol) = (port.portName, Self.symbol(forBluetooth: port.portName))
        }
    }

    private static func symbol(forBluetooth name: String) -> String {
        if name.contains("AirPods Max") { return "airpodsmax" }
        if name.contains("AirPods Pro") { return "airpodspro" }
        if name.contains("AirPods") { return "airpods" }
        return "speaker.wave.2.fill"
    }
}
