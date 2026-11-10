import AVKit
import SwiftUI

/// Where the sound is playing ("iPhone speaker", "AirPods Pro"). Tapping it
/// lists everywhere it could play instead, like Spotify's devices button:
/// this iPhone, AirPods and other Bluetooth, AirPlay speakers and TVs, the car.
struct AudioOutputButton: View {
    private var output: AudioOutput { .shared }

    var body: some View {
        Label(output.name, systemImage: output.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.tint.opacity(0.12), in: Capsule())
            .accessibilityHidden(true)
            // The system's own list of places to play, see-through over the
            // label, so tapping anywhere on it opens the list.
            .overlay { RoutePicker() }
            .onAppear { output.refresh() }
    }
}

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}
