import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var focusManager: FocusManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let focusManager else { return .terminateNow }
        if focusManager.isInFocus || focusManager.isEmergencyEnded {
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
    @StateObject private var claudeService = ClaudeService()
    @StateObject private var slackOAuthService = SlackOAuthService()

    init() {
        // Eagerly wire up services that don't depend on view lifecycle
        _claudeService.wrappedValue.slackService = _slackService.wrappedValue
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(focusManager)
                .environmentObject(slackService)
                .environmentObject(claudeService)
                .environmentObject(slackOAuthService)
                .onAppear {
                    appDelegate.focusManager = focusManager
                }
        } label: {
            Image(systemName: focusManager.isInFocus ? "sunrise.fill" : "sunrise")
        }
        .menuBarExtraStyle(.window)
    }
}
