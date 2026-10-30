import SwiftUI
import ServiceManagement
@preconcurrency import UserNotifications
import OrtusCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var focusManager: FocusManager?
    var router: PanelRouter?
    /// Set in OrtusApp.init, before anything writes preferences.
    static var isFreshInstall = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Analytics.start()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        Analytics.capture("app_launched", ["version": version])
        enableLaunchAtLoginByDefault()
        if Self.isFreshInstall { openWelcomePage() }
        // Notification Center needs a bundle; a bare `swift run` binary has none.
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
    }

    /// Clicking the update notification opens the panel on Settings, where the update button is.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        completionHandler()
        guard identifier == UpdateService.notificationID else { return }
        Task { @MainActor in
            router?.requestedTab = 3
            Self.openPanel()
        }
    }

    /// MenuBarExtra has no API to open its panel, so click Ortus's menu bar button
    /// unless the panel is already showing (a click would close it).
    private static func openPanel() {
        let statusWindows = NSApp.windows.filter { $0.className == "NSStatusBarWindow" }
        guard !NSApp.windows.contains(where: { $0.isVisible && !statusWindows.contains($0) && $0.className.contains("MenuBarExtra") }) else { return }
        func button(in view: NSView?) -> NSStatusBarButton? {
            guard let view else { return nil }
            return view as? NSStatusBarButton ?? view.subviews.lazy.compactMap { button(in: $0) }.first
        }
        statusWindows.lazy.compactMap { button(in: $0.contentView) }.first?.performClick(nil)
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
        Self.skipFocusIntroForExistingUsers()
    }

    /// People who used Ortus before the first-session explainer already know the lock.
    /// Runs once, so a fresh install still sees it on its first Start, even after relaunching.
    private static func skipFocusIntroForExistingUsers() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "checkedFocusIntro") else { return }
        defaults.set(true, forKey: "checkedFocusIntro")
        if !AppDelegate.isFreshInstall { defaults.set(true, forKey: "didStartFocusSession") }
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
                claudeCodeService.focusContext = { [weak focusManager] in focusManager?.chatContext() }
            }
    }

    var body: some Scene {
        MenuBarExtra {
            panel
        } label: {
            menuBarIcon
                .onAppear {
                    // The label appears at launch; the panel only when first opened.
                    appDelegate.router = router
                    updateService.startBackgroundChecks(focusManager)
                }
                #if DEBUG
                .onAppear(perform: openDebugWindowIfRequested)
                #endif
        }
        .menuBarExtraStyle(.window)
    }

    /// During focus, the icon plus a countdown, like the system Clock timer.
    @ViewBuilder private var menuBarIcon: some View {
        if let closing = focusManager.websites.closingBrowser {
            // Redrawn each second by menuBarClock, like the focus countdown.
            let time = FocusView.formatDuration(max(0, closing.closesAt.timeIntervalSince(menuBarClock.now)))
            Image(nsImage: Self.countdownImage("\(closing.name) \(time)", symbol: "exclamationmark.triangle.fill",
                                               description: "\(closing.name) closes in \(time)"))
        } else if focusManager.isInFocus, let end = focusManager.focusEndTime {
            Image(nsImage: Self.countdownImage(FocusView.formatDuration(max(0, end.timeIntervalSince(menuBarClock.now)))))
        } else if BuildProfile.isPreview {
            Image(nsImage: Self.countdownImage(nil, symbol: focusManager.isInFocus ? "sunrise.fill" : "sunrise", description: "Ortus Preview"))
        } else {
            Image(systemName: focusManager.isInFocus ? "sunrise.fill" : "sunrise")
        }
    }

    /// The menu bar drops font modifiers from a label's Text, so proportional digits
    /// would nudge every item to its left each second. Render it as one template image
    /// instead (the label shows only its first Image) to keep monospaced digits.
    private static func countdownImage(_ time: String?, symbol: String = "sunrise.fill", description: String? = nil) -> NSImage {
        let renderer = ImageRenderer(content: HStack(spacing: 4) {
            Image(systemName: symbol)
            if let time { Text(time).monospacedDigit() }
            // A preview is marked so it can't be mistaken for the installed release.
            if BuildProfile.isPreview { Text("P").fontWeight(.bold) }
        }.font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize)))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = description ?? "\(BuildProfile.name), \(time ?? "") left"
        return image
    }

    #if DEBUG
    /// Screenshot harness: launch with ORTUS_DEBUG_WINDOW=1 to also show the panel
    /// in a regular window that UI scripting and screencapture can reach.
    private func openDebugWindowIfRequested() {
        // The panel snapshots don't include the menu bar icon, so save it separately.
        if let directory = ProcessInfo.processInfo.environment["ORTUS_SNAPSHOT_DIR"] {
            for (name, image) in [("menubar-idle", Self.countdownImage(nil, symbol: "sunrise")), ("menubar-focus", Self.countdownImage("47:25"))] {
                guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            }
        }
        SnapshotHarness.runIfRequested(focusManager: focusManager) { tab, height, state in
            let modal: PanelModal? = switch state {
            case "browser-setup": .browserSetup
            case "slack-setup": .slackSetup
            case "chat-setup": .chatSetup
            case "chat-intro": .chatIntro
            case "focus-intro": .focusIntro(selection: focusManager.manualSelection, minutes: 90) {}
            case "mode-editor": .modeEditor(FocusMode(name: focusManager.nextCustomModeName, blocked: focusManager.manualSelection)) { _ in }
            case "end-focus-early": .endFocusEarly
            default: nil
            }
            switch state {
            case "up-to-date": updateService.pinForSnapshot(.upToDate)
            case "update-available": updateService.pinForSnapshot(.available(version: "1.2.0"))
            default: break
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
