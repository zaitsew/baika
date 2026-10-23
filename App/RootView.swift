import SwiftUI

/// Perform, Library, Talk, Settings. Only the Library works signed out.
struct RootView: View {
    @Environment(AppModel.self) private var app

    enum RootTab: Hashable { case perform, library, talk, settings }

    @State private var selection: RootTab = RootView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Perform", systemImage: "theatermasks", value: RootTab.perform) {
                if app.isSignedIn {
                    PerformView()
                } else {
                    SignInGate(openLibrary: { selection = .library })
                }
            }
            Tab("Library", systemImage: "books.vertical", value: RootTab.library) {
                LibraryView()
            }
            Tab("Talk", systemImage: "waveform.circle", value: RootTab.talk) {
                TalkPlaceholderView()
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                SettingsView()
            }
        }
        .tint(Theme.amber)
    }

    /// A debug build can open on a given tab (`BAIKA_TAB=library`), for screenshots.
    private static var initialTab: RootTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["BAIKA_TAB"] {
        case "library": return .library
        case "talk": return .talk
        case "settings": return .settings
        default: return .perform
        }
        #else
        return .perform
        #endif
    }
}
