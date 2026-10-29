import SwiftUI
import ServiceManagement
import OrtusCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var focusManager: FocusManager?
    /// Set in OrtusApp.init, before anything writes preferences.
    static var isFreshInstall = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Analytics.start()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        Analytics.capture("app_launched", ["version": version])
        enableLaunchAtLoginByDefault()
        if Self.isFreshInstall { openWelcomePage() }
    }

    /// Earlier versions turned launch at login on silently at first run. Users who updated
    /// keep that; fresh installs choose on the welcome page instead.
    private func enableLaunchAtLoginByDefault() {
        guard Bundle.main.object(forInfoDictionaryKey: "OrtusPreviewBuild") as? Bool != true else { return }
        let key = "didSetDefaultLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !Self.isFreshInstall else { return }
        try? SMAppService.mainApp.register()
    }

    /// First launch opens ortusmode.com/welcome, which hands its choices back through the
    /// app's URL scheme (ortus:// or ortus-preview://). Debug renders skip it.
    private func openWelcomePage() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORTUS_SNAPSHOT_DIR"] == nil, environment["ORTUS_DEBUG_WINDOW"] == nil else { return }
        var page = URLComponents(string: "https://ortusmode.com/welcome")!
        if let scheme = Self.urlScheme, scheme != "ortus" { page.queryItems = [URLQueryItem(name: "scheme", value: scheme)] }
        if let url = page.url { NSWorkspace.shared.open(url) }
    }

    private static var urlScheme: String? {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first
    }

    /// The welcome page sends ortus://welcome?login=1&analytics=0. Any page can open this
    /// link (after the browser asks), and it only changes these two settings.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.host == "welcome" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func choice(_ name: String) -> Bool? { items.first { $0.name == name }?.value.map { $0 == "1" } }
            if let login = choice("login") {
                try? login ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
            if let analytics = choice("analytics") { Analytics.setConsent(analytics) }
        }
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
    @StateObject private var menuBarClock = MenuBarClock()

    // Runs before the state objects above are created, so they read the copied preferences.
    init() {
        Self.migrateLegacyPreferences()
        // FocusManager sets this on its first run, and migration copies it from older builds.
        AppDelegate.isFreshInstall = UserDefaults.standard.object(forKey: "focusModesMigrated") == nil
    }

    /// Bundle IDs moved from com.ortus.* to com.ortusmode.* before the public launch.
    /// Preferences are stored per bundle ID, so copy the old ones over once.
    private static func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        let key = "didMigrateLegacyPreferences"
        guard let id = Bundle.main.bundleIdentifier, !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        let legacyID = id.replacingOccurrences(of: "com.ortusmode.", with: "com.ortus.")
        guard legacyID != id, let legacy = defaults.persistentDomain(forName: legacyID) else { return }
        // The login item belongs to the old app identity; let this one register itself.
        for (name, value) in legacy where name != "didSetDefaultLoginItem" && defaults.object(forKey: name) == nil {
            defaults.set(value, forKey: name)
        }
    }

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
            menuBarIcon
                #if DEBUG
                .onAppear(perform: openDebugWindowIfRequested)
                #endif
        }
        .menuBarExtraStyle(.window)
    }

    /// During focus, the icon plus a countdown, like the system Clock timer.
    @ViewBuilder private var menuBarIcon: some View {
        if focusManager.isInFocus, let end = focusManager.focusEndTime {
            Image(nsImage: Self.countdownImage(FocusView.formatDuration(max(0, end.timeIntervalSince(menuBarClock.now)))))
        } else {
            Image(systemName: focusManager.isInFocus ? "sunrise.fill" : "sunrise")
        }
    }

    /// The menu bar drops font modifiers from a label's Text, so proportional digits
    /// would nudge every item to its left each second. Render it as one template image
    /// instead (the label shows only its first Image) to keep monospaced digits.
    private static func countdownImage(_ time: String) -> NSImage {
        let renderer = ImageRenderer(content: HStack(spacing: 4) {
            Image(systemName: "sunrise.fill")
            Text(time).monospacedDigit()
        }.font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize)))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = "Ortus, \(time) left"
        return image
    }

    #if DEBUG
    /// Screenshot harness: launch with ORTUS_DEBUG_WINDOW=1 to also show the panel
    /// in a regular window that UI scripting and screencapture can reach.
    private func openDebugWindowIfRequested() {
        SnapshotHarness.runIfRequested(focusManager: focusManager) { tab, height, state in
            let modal: PanelModal? = switch state {
            case "browser-setup": .browserSetup
            case "slack-setup": .slackSetup
            case "chat-setup": .chatSetup
            case "chat-intro": .chatIntro
            case "focus-intro": .focusIntro {}
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

/// Ticks once a second to redraw the menu bar countdown. TimelineView and
/// Text(timerInterval:) don't update inside a MenuBarExtra label (they blank it).
@MainActor final class MenuBarClock: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }
}
