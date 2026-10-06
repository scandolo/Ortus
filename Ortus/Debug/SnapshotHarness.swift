import SwiftUI
import AppKit

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

        func render(_ name: String, tab: Int, height: CGFloat = 560, state: String? = nil, dark: Bool = false) async {
            let hosting = NSHostingView(rootView: panel(tab, height, state))
            hosting.frame = NSRect(x: 0, y: 0, width: 420, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = hosting
            try? await Task.sleep(for: .milliseconds(900))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
            window.contentView = nil
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            await render("focus-idle", tab: 0)
            await render("focus-idle-dark", tab: 0, dark: true)
            await render("focus-targets", tab: 0, height: 900, state: "targets")
            await render("focus-browser-setup", tab: 0, height: 700, state: "browser-setup")
            await render("schedule", tab: 1)
            await render("schedule-editor", tab: 1, height: 1000, state: "new-schedule")
            await render("chat", tab: 2)
            await render("settings", tab: 3)
            await render("settings-full", tab: 3, height: 900)
            await render("settings-slack-setup", tab: 3, height: 1100, state: "slack-setup")
            if !focusManager.isInFocus, ProcessInfo.processInfo.environment["ORTUS_SNAPSHOT_SESSION"] != nil {
                focusManager.startFocusSession(name: "Focus", duration: 3600)
                await render("focus-grace", tab: 0)
                try? await Task.sleep(for: .seconds(31))
                await render("focus-active", tab: 0)
                await render("focus-active-dark", tab: 0, dark: true)
            }
            exit(0)
        }
    }
}
#endif
