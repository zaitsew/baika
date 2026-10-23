import SwiftData
import SwiftUI

@main
struct BaikaApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.accounts)
                .modelContainer(for: Story.self)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .onOpenURL { url in app.handleOpenURL(url) }
        }
    }
}
