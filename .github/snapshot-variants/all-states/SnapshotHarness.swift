import SwiftUI
import AppKit
import OrtusCore

/// Lets the snapshot harness open a view in a specific state (an expanded editor,
/// a setup form). Always nil in normal use.
private struct SnapshotStateKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var snapshotState: String? {
        get { self[SnapshotStateKey.self] }
        set { self[SnapshotStateKey.self] = newValue }
    }
}

#if DEBUG
/// CI-only variant of the snapshot harness (.github/snapshot-variants/all-states.sh swaps it in).
/// Renders every panel state the state board maps, at 2x, by putting the app's services into
/// each state directly. Launch with ORTUS_SNAPSHOT_DIR=/path; it writes PNGs and quits.
@MainActor
enum SnapshotHarness {
    static var claude: ClaudeCodeService?
    static var slack: SlackOAuthService?
    static var updates: UpdateService?
    /// The state a stand-in Chrome extension reports, or nil for no browser.
    static var browserState: String?

    /// What a browser extension writes when it connects; the app re-reads these every second
    /// and drops any older than 15 seconds, so a loop keeps it fresh.
    static func browserClient(_ websites: WebsiteBlockingService, _ state: String?) {
        let folder = websites.directory.appendingPathComponent("clients", isDirectory: true)
        let file = folder.appendingPathComponent("snapshot-chrome.json")
        guard let state else { try? FileManager.default.removeItem(at: file); websites.refreshConnections(); return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let client = BrowserClient(id: "snapshot-chrome", browser: "Chrome", updatedAt: Date().timeIntervalSince1970, state: state)
        try? JSONEncoder().encode(client).write(to: file)
        websites.refreshConnections()
    }

    /// A stand-in `claude` where Homebrew installs it, so detection finds Claude Code.
    static func installClaudeCode() {
        for path in ["/opt/homebrew/bin/claude", NSHomeDirectory() + "/.local/bin/claude"] {
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\nexit 0\n".utf8), attributes: [.posixPermissions: 0o755]) { break }
        }
        claude?.redetect()
    }

    static func runIfRequested(focusManager: FocusManager, panel: @escaping (_ tab: Int, _ height: CGFloat, _ state: String?) -> AnyView) {
        guard let path = ProcessInfo.processInfo.environment["ORTUS_SNAPSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scale: CGFloat = 2

        func write(_ rep: NSBitmapImageRep, _ name: String) {
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }

        func bitmap(_ size: NSSize) -> NSBitmapImageRep? {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            rep?.size = size
            return rep
        }

        func render(_ name: String, tab: Int, height: CGFloat = 560, state: String? = nil, dark: Bool = false) async {
            let hosting = NSHostingView(rootView: panel(tab, height, state))
            hosting.frame = NSRect(x: 0, y: 0, width: 420, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = hosting
            try? await Task.sleep(for: .milliseconds(900))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = bitmap(hosting.bounds.size) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            write(rep, name)
            window.contentView = nil
        }

        /// Light and dark.
        func both(_ name: String, tab: Int, height: CGFloat = 560, state: String? = nil) async {
            await render(name, tab: tab, height: height, state: state)
            await render(name + "-dark", tab: tab, height: height, state: state, dark: true)
        }

        /// A menu bar image (template images are drawn black; the board tints them).
        func image(_ name: String, _ image: NSImage) {
            guard let rep = bitmap(image.size) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            write(rep, name)
        }

        func menuBarSymbol(_ name: String) -> NSImage {
            let config = NSImage.SymbolConfiguration(pointSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        }

        Task { @MainActor in
            let defaults = UserDefaults.standard
            let websites = focusManager.websites
            Task { @MainActor in
                while true {
                    if let state = SnapshotHarness.browserState { SnapshotHarness.browserClient(websites, state) }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            try? await Task.sleep(for: .seconds(1))

            // A fresh install: nothing connected, the first-run schedule drafted.
            await both("focus-idle", tab: 0)
            await both("focus-modes", tab: 0, height: 760, state: "modes")
            await both("mode-editor", tab: 0, height: 760, state: "mode-editor")
            await both("browser-setup", tab: 0, state: "browser-setup")
            await both("schedule", tab: 1)
            await both("schedule-new", tab: 1, height: 860, state: "new-schedule")
            await both("chat-missing", tab: 2, state: "empty")
            await both("settings", tab: 3)
            await both("chat-setup-missing", tab: 3, state: "chat-setup")
            await both("slack-setup", tab: 3, height: 760, state: "slack-setup")

            // Progress and errors, from the services' own messages.
            SnapshotHarness.slack?.isAuthenticating = true
            await render("slack-setup-waiting-dark", tab: 3, height: 760, state: "slack-setup", dark: true)
            SnapshotHarness.slack?.isAuthenticating = false
            SnapshotHarness.slack?.error = "No authorization code received from Slack."
            await render("slack-setup-error-dark", tab: 3, height: 760, state: "slack-setup", dark: true)
            SnapshotHarness.slack?.error = nil
            websites.setupError = "Choose an installed supported browser: Arc, Chrome, Edge or Brave. Safari and Firefox are not supported."
            await render("browser-setup-error-dark", tab: 0, state: "browser-setup", dark: true)
            websites.setupError = nil
            SnapshotHarness.updates?.state = .available(version: "1.2.0")
            await both("settings-update", tab: 3)
            SnapshotHarness.updates?.state = .downloading
            await render("settings-updating-dark", tab: 3, dark: true)
            SnapshotHarness.updates?.state = .failed("Finish your focus session before updating.")
            await render("settings-update-failed-dark", tab: 3, dark: true)
            SnapshotHarness.updates?.state = .idle

            // Gen Z mode rewrites the copy.
            defaults.set(true, forKey: "genZMode")
            await render("focus-idle-genz-dark", tab: 0, dark: true)
            await render("chat-genz-dark", tab: 2, state: "empty", dark: true)
            defaults.set(false, forKey: "genZMode")

            // Everything connected: a browser, Claude Code and Slack.
            // A browser that reports an error first, then a healthy one.
            SnapshotHarness.browserState = "error"
            SnapshotHarness.browserClient(websites, "error")
            await render("browser-setup-enforcement-dark", tab: 0, state: "browser-setup", dark: true)
            SnapshotHarness.browserState = "ready"
            SnapshotHarness.browserClient(websites, "ready")
            SnapshotHarness.installClaudeCode()
            SnapshotHarness.slack?.isConnected = true
            SnapshotHarness.slack?.teamName = "Acme"
            await both("focus-ready", tab: 0)
            await both("settings-connected", tab: 3, height: 860)
            await render("settings-slack-preview-dark", tab: 3, height: 980, state: "slack-preview", dark: true)
            await render("browser-setup-connected-dark", tab: 0, state: "browser-setup", dark: true)
            await both("chat-setup-detected", tab: 3, state: "chat-setup")
            await both("chat-intro", tab: 2, state: "chat-intro")
            await both("chat-empty", tab: 2, state: "empty")
            await both("chat-permission", tab: 2, state: "chat-permission")
            SnapshotHarness.claude?.allowedTools = ["mcp__claude_ai_Gmail__search_threads"]
            await render("chat-allowed-dark", tab: 2, state: "chat-permission", dark: true)
            SnapshotHarness.claude?.allowedTools = []
            await both("chat-draft", tab: 2, state: "chat-draft")
            SnapshotHarness.claude?.messages = [ChatMessage(role: .user, content: "Catch me up on Slack")]
            SnapshotHarness.claude?.isProcessing = true
            await both("chat-thinking", tab: 2, state: "thinking")
            SnapshotHarness.claude?.isProcessing = false
            SnapshotHarness.claude?.messages = [
                ChatMessage(role: .user, content: "Catch me up on Slack"),
                ChatMessage(role: .assistant, content: "Claude Code could not finish this request. Check your connection and Claude sign-in, then retry.", kind: .error),
            ]
            await render("chat-error-dark", tab: 2, state: "error", dark: true)
            SnapshotHarness.claude?.messages = []

            // Modes: the first-run custom mode, opened for editing.
            await render("mode-editor-existing-dark", tab: 0, height: 760, state: "mode-editor-existing", dark: true)

            // Schedules: on, overnight, locked by a running schedule, and none at all.
            if var first = focusManager.schedules.first {
                first.isEnabled = true
                focusManager.updateSchedule(first)
            }
            await both("schedule-on", tab: 1)
            focusManager.addSchedule(FocusSchedule(name: "Late session", days: [.monday, .tuesday, .wednesday, .thursday, .friday],
                                                   startHour: 22, startMinute: 0, endHour: 6, endMinute: 0, isEnabled: false,
                                                   blocked: FocusMode.messages.blocked))
            await render("schedule-two-dark", tab: 1, dark: true)
            await both("schedule-edit", tab: 1, height: 860, state: "edit-schedule")
            for schedule in focusManager.schedules { focusManager.deleteSchedule(schedule) }
            await both("schedule-empty", tab: 1)

            // The menu bar item at rest.
            image("menubar-idle", menuBarSymbol("sunrise"))

            // A schedule whose window includes now locks itself, as it would on a real Mac.
            let hour = Calendar.current.component(.hour, from: Date())
            focusManager.addSchedule(FocusSchedule(name: "Deep work", days: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday],
                                                   startHour: (hour + 23) % 24, startMinute: 0, endHour: (hour + 2) % 24, endMinute: 0,
                                                   isEnabled: true, blocked: FocusMode.social.blocked))
            try? await Task.sleep(for: .seconds(3))
            if focusManager.isInFocus {
                await both("schedule-locked", tab: 1)
                await both("focus-scheduled", tab: 0)
                await both("settings-in-focus", tab: 3, height: 760)
                await render("settings-emergency-dark", tab: 3, height: 760, state: "emergency-confirm", dark: true)
                // The once-a-week emergency end, then the week it can't be used again.
                focusManager.emergencyEndFocusSession()
                try? await Task.sleep(for: .seconds(2))
                await render("focus-after-emergency-dark", tab: 0, dark: true)
                for schedule in focusManager.schedules { focusManager.deleteSchedule(schedule) }
            }

            // A session: the 30-second grace period, then locked in.
            if !focusManager.isInFocus {
                focusManager.startFocusSession(name: "Focus", duration: 3600)
                await both("focus-grace", tab: 0)
                focusManager.skipGracePeriod()
                try? await Task.sleep(for: .seconds(2))
                await both("focus-active", tab: 0)
                image("menubar-focus", OrtusApp.countdownImage("59:58"))
                image("menubar-focus-symbol", menuBarSymbol("sunrise.fill"))
                await render("settings-emergency-used-dark", tab: 3, height: 760, dark: true)
                SnapshotHarness.updates?.state = .available(version: "1.2.0")
                await render("settings-update-in-focus-dark", tab: 3, height: 760, dark: true)
                SnapshotHarness.updates?.installsAfterFocus = true
                await render("settings-update-after-focus-dark", tab: 3, height: 760, dark: true)
                SnapshotHarness.updates?.installsAfterFocus = false
                SnapshotHarness.updates?.state = .idle
                focusManager.developerModeEnabled = true
                await render("focus-active-dev-dark", tab: 0, height: 620, dark: true)
                focusManager.developerModeEnabled = false
                await render("schedule-in-focus-dark", tab: 1, dark: true)
            }
            exit(0)
        }
    }
}
#endif
