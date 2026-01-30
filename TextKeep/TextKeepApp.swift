import SwiftUI

@main
struct TextKeepApp: App {
    @State private var hasSeenWelcome = false
    @StateObject private var updateChecker = UpdateChecker()

    // Alert state for update notifications
    @State private var showUpdateAlert = false
    @State private var updateAlertTitle = ""
    @State private var updateAlertMessage = ""
    @State private var showDownloadButton = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenWelcome {
                    ContentView(
                        updateChecker: updateChecker,
                        onUpdateCheckComplete: handleUpdateCheckResult
                    )
                } else {
                    WelcomeView(hasSeenWelcome: $hasSeenWelcome)
                }
            }
            .alert(updateAlertTitle, isPresented: $showUpdateAlert) {
                if showDownloadButton {
                    Button("Download") {
                        updateChecker.openDownloadPage()
                    }
                    Button("Later", role: .cancel) { }
                } else {
                    Button("OK", role: .cancel) { }
                }
            } message: {
                Text(updateAlertMessage)
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
                            .applicationVersion: Bundle.main.appVersion,
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

                Button("Check for Updates...") {
                    Task {
                        await updateChecker.checkForUpdates()
                        handleUpdateCheckResult()
                    }
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(updateChecker.isChecking)
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
        let helpView = HelpView(
            updateChecker: updateChecker,
            onUpdateCheckComplete: handleUpdateCheckResult
        )
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

    private func handleUpdateCheckResult() {
        if updateChecker.lastCheckFailed {
            // Error occurred
            updateAlertTitle = "Unable to Check for Updates"
            updateAlertMessage = updateChecker.errorMessage.isEmpty ?
                "Please check your internet connection and try again." :
                updateChecker.errorMessage
            showDownloadButton = false
            showUpdateAlert = true
        } else if updateChecker.updateAvailable {
            // Update available
            updateAlertTitle = "Update Available"
            updateAlertMessage = "Version \(updateChecker.latestVersion) is now available. You're currently using version \(updateChecker.getCurrentVersion())."
            showDownloadButton = true
            showUpdateAlert = true
        } else {
            // Up to date
            updateAlertTitle = "You're Up to Date"
            updateAlertMessage = "TextKeep \(updateChecker.getCurrentVersion()) is the latest version."
            showDownloadButton = false
            showUpdateAlert = true
        }
    }
}
