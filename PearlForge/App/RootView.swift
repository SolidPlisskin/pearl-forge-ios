import SwiftUI

/// The three tabs: record a new thought, revisit saved ones, and set up keys
/// and voice.
struct RootView: View {
    enum Tab: Hashable {
        case create, history, settings
    }

    @State private var settings = SettingsModel()
    @State private var tab = Tab.create

    var body: some View {
        TabView(selection: $tab) {
            CreateView(settings: settings, openSettings: { tab = .settings })
                .tabItem { Label("Create", systemImage: "mic") }
                .tag(Tab.create)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(Tab.history)
            SettingsView(model: settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    RootView()
}
