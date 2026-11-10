import SwiftUI

@main
struct PearlForgeApp: App {
    init() {
        // Without this, videos follow the silent switch: muted on the
        // speaker, while AirPods still hear them.
        AudioSession.prepareForPlayback()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
