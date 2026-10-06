import SwiftUI
import ServiceManagement
import OrtusCore

class AppDelegate: NSObject, NSApplicationDelegate {
    var focusManager: FocusManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Analytics.start()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        Analytics.capture("app_launched", ["version": version])
        enableLaunchAtLoginByDefault()
    }

    /// Launch at login is on by default. Register once on first run; after that
    /// we never touch it again, so a user who turns it off in Settings stays off.
    private func enableLaunchAtLoginByDefault() {
        guard Bundle.main.object(forInfoDictionaryKey: "OrtusPreviewBuild") as? Bool != true else { return }
        let key = "didSetDefaultLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let focusManager = focusManager ?? FocusManager.current else { return .terminateNow }
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
    @StateObject private var updateService = UpdateService()
    @StateObject private var router = PanelRouter()

    private var panel: some View { panel() }

    private func panel(tab: Int = 0, height: CGFloat? = nil, state: String? = nil, router: PanelRouter? = nil) -> some View {
        ContentView(initialTab: tab, fixedHeight: height)
            .environment(\.snapshotState, state)
            .environmentObject(router ?? self.router)
            .environmentObject(focusManager)
            .environmentObject(slackService)
            .environmentObject(claudeCodeService)
            .environmentObject(slackOAuthService)
            .environmentObject(updateService)
            .onAppear {
                appDelegate.focusManager = focusManager
                // Inject SlackService here (not in App.init) — the StateObject
                // backing store isn't ready until a view installs it.
                focusManager.slackService = slackService
            }
    }

    var body: some Scene {
        MenuBarExtra {
            panel
        } label: {
            Image(systemName: focusManager.isInFocus ? "sunrise.fill" : "sunrise")
                #if DEBUG
                .onAppear(perform: openDebugWindowIfRequested)
                #endif
        }
        .menuBarExtraStyle(.window)
    }

    #if DEBUG
    /// Screenshot harness: launch with ORTUS_DEBUG_WINDOW=1 to also show the panel
    /// in a regular window that UI scripting and screencapture can reach.
    private func openDebugWindowIfRequested() {
        SnapshotHarness.runIfRequested(focusManager: focusManager) { tab, height, state in
            let modal: PanelModal? = switch state {
            case "browser-setup": .browserSetup
            case "slack-setup": .slackSetup
            case "mode-editor": .modeEditor(FocusMode(name: focusManager.nextCustomModeName, blocked: focusManager.manualSelection)) { _ in }
            default: nil
            }
            return AnyView(panel(tab: tab, height: height, state: state, router: PanelRouter(modal: modal)))
        }
        guard ProcessInfo.processInfo.environment["ORTUS_DEBUG_WINDOW"] != nil else { return }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ortus (debug)"
        window.contentView = NSHostingView(rootView: panel)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    #endif
}
