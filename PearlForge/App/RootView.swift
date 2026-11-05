import SwiftUI
import UniformTypeIdentifiers

/// The app's tabs.
enum AppTab: Hashable {
    case create, history, reading, ai, settings
}

/// Record a new thought, revisit saved ones, read what was found for them,
/// choose the AI that polishes, and set up the voice and storage.
struct RootView: View {
    @State private var settings = SettingsModel()
    @State private var polishers = PolishersModel()
    @State private var library = RecordingLibrary()
    @State private var tab = AppTab.create
    @State private var sharedAudio: URL?

    var body: some View {
        TabView(selection: $tab) {
            CreateView(settings: settings, polishers: polishers, library: library,
                       sharedAudio: $sharedAudio, openTab: { tab = $0 })
                .tabItem { Label("Create", systemImage: "mic") }
                .tag(AppTab.create)
            HistoryView(library: library, settings: settings, polishers: polishers, openTab: { tab = $0 })
                .tabItem { Label("History", systemImage: "clock") }
                .tag(AppTab.history)
            ReadingView(library: library)
                .tabItem { Label("Reading", systemImage: "books.vertical") }
                .tag(AppTab.reading)
            AIView(polishers: polishers)
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(AppTab.ai)
            SettingsView(model: settings, library: library)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onOpenURL { url in
            // A recording sent from another app with Share › Pearl Forge.
            guard url.isFileURL, UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
            else { return }
            sharedAudio = url
            tab = .create
        }
    }
}

#Preview {
    RootView()
}
