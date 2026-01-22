import SwiftUI

@main
struct TextKeepApp: App {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup {
            if hasSeenWelcome {
                ContentView()
            } else {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 500)
    }
}
