import SwiftUI

enum RootTab: Hashable { case perform, library, talk, settings }

/// Perform, Library, Talk, Settings. Only the Library works signed out.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

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
                if app.isSignedIn {
                    TalkView()
                } else {
                    SignInGate(openLibrary: { selection = .library })
                }
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                SettingsView()
            }
        }
        .tint(Theme.amber)
        // A live conversation belongs to the Talk tab: leaving it, or the app, ends it. The mic
        // stays closed and the session stops costing money.
        .onChange(of: selection) { old, _ in
            if old == .talk { app.talk.end() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.talk.end(.dropped) }
        }
        .onChange(of: app.requestedTab) { _, tab in
            guard let tab else { return }
            selection = tab
            app.requestedTab = nil
        }
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
