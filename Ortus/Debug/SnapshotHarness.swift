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
/// Debug builds only. Launch with ORTUS_SNAPSHOT_DIR=/path to render every panel
/// state offscreen to PNG files and quit. Works with the screen locked and never
/// touches the menu bar.
@MainActor
enum SnapshotHarness {
    static func runIfRequested(focusManager: FocusManager, panel: @escaping (_ tab: Int, _ height: CGFloat, _ state: String?) -> AnyView) {
        guard let path = ProcessInfo.processInfo.environment["ORTUS_SNAPSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        /// `act` runs on the drawn panel before the picture, to show what an event does.
        func render(_ name: String, tab: Int, height: CGFloat = 560, state: String? = nil, dark: Bool = false, act: (@MainActor (NSWindow) async -> Void)? = nil) async {
            let hosting = NSHostingView(rootView: panel(tab, height, state))
            hosting.frame = NSRect(x: 0, y: 0, width: 420, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = hosting
            try? await Task.sleep(for: .milliseconds(900))
            if let act { await act(window); try? await Task.sleep(for: .milliseconds(600)) }
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
            window.contentView = nil
        }

        /// A change as it animates: one view, changed once, captured at each time in ms.
        func renderFrames(_ name: String, tab: Int, state: String? = nil, frames: [Int], change: () -> Void) async {
            let hosting = NSHostingView(rootView: panel(tab, 560, state))
            hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            try? await Task.sleep(for: .milliseconds(900))
            change()
            var elapsed = 0
            for (index, time) in frames.enumerated() {
                try? await Task.sleep(for: .milliseconds(time - elapsed))
                elapsed = time
                hosting.layoutSubtreeIfNeeded()
                guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name)-\(index + 1).png"))
            }
            window.contentView = nil
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            await render("focus-idle", tab: 0)
            // The panel ignores macOS dark mode: this must match focus-idle.
            await render("focus-idle-dark", tab: 0, dark: true)
            await render("focus-ready", tab: 0, state: "browser-connected")
            await render("focus-no-browser", tab: 0, state: "no-browser")
            await render("focus-intro", tab: 0, state: "focus-intro")
            await render("focus-modes", tab: 0, height: 760, state: "modes")
            await render("mode-editor", tab: 0, height: 760, state: "mode-editor")
            await render("browser-setup", tab: 0, state: "browser-setup")
            await render("browser-setup-folder", tab: 0, height: 760, state: "browser-setup-folder")
            await render("browser-setup-folder-error", tab: 0, height: 760, state: "browser-setup-folder-error")
            await render("schedule", tab: 1)
            await render("schedule-editor", tab: 1, height: 860, state: "new-schedule")
            // Modes and schedules. A copy of Socials, as older versions could save one.
            await render("schedule-modes", tab: 1, height: 860, state: "schedule-modes")
            let copy = FocusMode(name: "Socials copy", blocked: FocusMode.social.blocked)
            focusManager.customModes.append(copy)
            await render("focus-modes-duplicate", tab: 0, height: 760, state: "modes")
            focusManager.customModes.removeAll { $0.id == copy.id }
            // A custom mode chosen on the Focus tab, opened to edit and to delete.
            let deepWork = FocusMode(name: "Deep work", blocked: .union([FocusMode.messages.blocked, .init(websites: ["x.com", "twitter.com"])]))
            let manual = focusManager.manualSelection
            focusManager.customModes.append(deepWork)
            focusManager.manualSelection = deepWork.blocked
            await render("mode-edit", tab: 0, height: 760, state: "mode-edit")
            await render("mode-delete", tab: 0, state: "mode-delete")
            focusManager.manualSelection = manual
            focusManager.customModes.removeAll { $0.id == deepWork.id }
            // A schedule that's on next to the default one, which is off. It starts in three
            // hours, so it never starts a session while rendering.
            let hour = (Calendar.current.component(.hour, from: .now) + 3) % 24
            let writing = FocusSchedule(name: "Writing", days: Set(Weekday.allCases), startHour: hour, endHour: (hour + 2) % 24, blocked: FocusMode.social.blocked)
            focusManager.addSchedule(writing)
            await render("schedule-on-off", tab: 1)
            focusManager.deleteSchedule(writing)
            // Typing in the start time, then Return or a click on the panel's edge: the outline goes.
            func typeInStartTime(then leave: (@MainActor (NSWindow) -> Void)? = nil) -> @MainActor (NSWindow) async -> Void {
                { window in
                    @MainActor func fields(_ view: NSView) -> [NSTextField] { ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(fields) }
                    guard let field = window.contentView.map(fields)?.first(where: { $0.stringValue.contains(":") }) else { return }
                    window.makeFirstResponder(field)
                    try? await Task.sleep(for: .milliseconds(400))
                    leave?(window)
                }
            }
            let uptime = { ProcessInfo.processInfo.systemUptime }
            await render("schedule-time-focused", tab: 1, height: 860, state: "new-schedule", act: typeInStartTime())
            await render("schedule-time-return", tab: 1, height: 860, state: "new-schedule", act: typeInStartTime { window in
                window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: uptime(), windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
            })
            await render("schedule-time-click-away", tab: 1, height: 860, state: "new-schedule", act: typeInStartTime { window in
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    NSApp.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 6, y: window.frame.height - 160), modifierFlags: [], timestamp: uptime(), windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                }
            })
            await render("chat", tab: 2, state: "empty")
            await render("chat-intro", tab: 2, state: "chat-intro")
            await render("chat-no-agent", tab: 2, state: "chat-no-agent")
            await render("agent-setup-missing", tab: 2, state: "agent-setup-missing")
            await render("agent-setup-checking", tab: 2, state: "agent-setup-checking")
            await render("agent-setup-error", tab: 2, state: "agent-setup-error")
            await render("agent-setup-installing", tab: 2, state: "agent-setup-installing")
            await render("agent-setup-install-failed", tab: 2, state: "agent-setup-install-failed")
            await render("agent-setup-sign-in", tab: 2, state: "agent-setup-sign-in")
            await render("agent-setup-waiting", tab: 2, state: "agent-setup-waiting")
            await render("agent-setup-ready", tab: 2, state: "agent-setup-ready")
            await render("codex-setup-missing", tab: 2, state: "codex-setup-missing")
            await render("codex-setup-installing", tab: 2, state: "codex-setup-installing")
            await render("codex-setup-sign-in", tab: 2, state: "codex-setup-sign-in")
            await render("codex-setup-ready", tab: 2, state: "codex-setup-ready")
            await render("chat-signed-out", tab: 2, state: "chat-signed-out")
            await render("chat-intro-no-agent", tab: 2, state: "chat-intro-no-agent")
            await render("chat-answer", tab: 2, state: "chat-answer")
            await render("chat-prose", tab: 2, height: 760, state: "chat-prose")
            await render("chat-steps",tab: 2, height: 760, state: "chat-steps")
            await render("chat-email", tab: 2, state: "chat-email")
            await render("chat-code", tab: 2, state: "chat-code")
            await render("chat-working", tab: 2, state: "chat-working")
            await render("chat-compose", tab: 2, state: "chat-compose")
            await render("chat-compose-email", tab: 2, state: "chat-compose-email")
            await render("chat-compose-sent", tab: 2, state: "chat-compose-sent")
            await render("chat-compose-failed", tab: 2, state: "chat-compose-failed")
            await render("chat-draft", tab: 2, state: "chat-draft")
            await render("chat-send-hover", tab: 2, state: "chat-send-hover")
            await render("chat-feedback", tab: 2, height: 760, state: "chat-feedback")
            await render("chat-feedback-copy", tab: 2, height: 760, state: "chat-feedback-copy")
            await render("settings", tab: 3)
            await render("settings-dark", tab: 3, dark: true)
            await render("settings-agent-missing", tab: 3, state: "chat-no-agent")
            await render("settings-experimental", tab: 3, height: 760, state: "settings-experimental")
            await render("settings-codex", tab: 3, height: 760, state: "settings-codex")
            await render("settings-up-to-date", tab: 3, height: 760, state: "up-to-date")
            await render("settings-update-available", tab: 3, height: 760, state: "update-available")
            await render("settings-update-unverified", tab: 3, height: 760, state: "update-unverified")
            await render("chat-setup", tab: 3, state: "chat-setup")
            await render("chat-setup-small", tab: 3, height: 320, state: "chat-setup")
            await render("slack-setup", tab: 3, height: 760, state: "slack-setup")
            if !focusManager.isInFocus, ProcessInfo.processInfo.environment["ORTUS_SNAPSHOT_SESSION"] != nil {
                focusManager.startFocusSession(name: "Focus", duration: 3600)
                await render("focus-grace", tab: 0)
                try? await Task.sleep(for: .seconds(31))
                await render("focus-active", tab: 0)
                await render("focus-active-connected", tab: 0, state: "browser-connected")
                await render("settings-focus", tab: 3, height: 760)
                await render("end-focus-early", tab: 3, state: "end-focus-early")
                await render("focus-closing-browser", tab: 0, state: "closing-browser")
                await render("chat-answer-locked", tab: 2, state: "chat-answer")
                await render("chat-compose-locked", tab: 2, state: "chat-compose")
                await render("schedule-locked", tab: 1)
                // +15 min as it rolls, ending where it settles. Last, so the states above
                // keep the one-hour session.
                await renderFrames("focus-extending", tab: 0, state: "browser-connected", frames: [80, 220, 1200]) {
                    focusManager.extendFocus(by: 15 * 60)
                }
            }
            exit(0)
        }
    }
}
#endif
