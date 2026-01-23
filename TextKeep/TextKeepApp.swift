import SwiftUI

@main
struct TextKeepApp: App {
    @State private var hasSeenWelcome = false

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
        .commands {
            // Replace default About menu
            CommandGroup(replacing: .appInfo) {
                Button("About TextKeep") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "TextKeep",
                            .applicationVersion: "1.3.2",
                            .version: "",
                            .credits: NSAttributedString(
                                string: "© 2026 Proofbound\nproofbound.com",
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 11),
                                    .foregroundColor: NSColor.secondaryLabelColor
                                ]
                            )
                        ]
                    )
                }
            }

            // Add Help menu command
            CommandGroup(replacing: .help) {
                Button("TextKeep Help") {
                    openHelpWindow()
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }

    private func openHelpWindow() {
        let helpView = HelpView()
        let hostingController = NSHostingController(rootView: helpView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "TextKeep Help"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 700))
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Keep window in memory
        NSApp.activate(ignoringOtherApps: true)
    }
}
