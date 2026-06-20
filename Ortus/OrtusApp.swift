import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var focusManager: FocusManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let focusManager else { return .terminateNow }
        // Block quit only while focus is genuinely active. After an emergency end,
        // Slack is already unblocked, so there's no reason to trap the app open.
        if focusManager.isInFocus {
            return .terminateCancel
        }
        return .terminateNow
    }
}

@main
struct OrtusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var focusManager = FocusManager()
    @StateObject private var slackService = SlackService()
    @StateObject private var claudeCodeService = ClaudeCodeService()
    @StateObject private var slackOAuthService = SlackOAuthService()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(focusManager)
                .environmentObject(slackService)
                .environmentObject(claudeCodeService)
                .environmentObject(slackOAuthService)
                .onAppear {
                    appDelegate.focusManager = focusManager
                    // Inject SlackService here (not in App.init) — the StateObject
                    // backing store isn't ready until a view installs it.
                    focusManager.slackService = slackService
                }
        } label: {
            // SF Symbol "sunrise" is the HIG-correct menu-bar glyph: it auto-tints
            // for light/dark menu bars and inverts on selection, and it's literally
            // a sunrise — on-brand for Ortus. The custom sunmark lives in-app, in
            // the app icon, and on the website.
            Image(systemName: focusManager.isInFocus ? "sunrise.fill" : "sunrise")
        }
        .menuBarExtraStyle(.window)
    }
}
