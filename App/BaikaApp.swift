import SwiftData
import SwiftUI

@main
struct BaikaApp: App {
    @State private var app = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.accounts)
                .modelContainer(app.container)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .onOpenURL { url in app.handleOpenURL(url) }
        }
    }
}
