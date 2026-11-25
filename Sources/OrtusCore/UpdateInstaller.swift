import Foundation

/// Swaps the app bundle for a downloaded update once the app has quit.
public enum UpdateInstaller {
    /// Whether this user can swap the bundle: rename it inside its folder and replace it.
    /// Not true from a non-admin account (it can't change /Applications), for an app another
    /// user installed, or when Ortus runs from the DMG.
    public static func canReplace(bundleAt bundle: URL) -> Bool {
        let files = FileManager.default
        return files.isWritableFile(atPath: bundle.deletingLastPathComponent().path) && files.isWritableFile(atPath: bundle.path)
    }

    /// A bash script that waits for `pid` to exit, swaps `source` in at `target`, reopens
    /// `target` with `relaunch` and deletes `work`. It gives up without touching anything
    /// if the app is still running after about a minute (a focus session blocks quitting).
    ///
    /// The old app moves aside in one rename before the new one moves in. If either step
    /// fails, the old app goes back, so a failed update never leaves a half-replaced Ortus.
    public static func script(target: URL, source: URL, work: URL, pid: Int32, relaunch: String = "open") -> String {
        let previous = target.deletingLastPathComponent().appendingPathComponent(".Ortus-previous-\(UUID().uuidString)")
        return """
        #!/bin/bash
        TARGET=\(quoted(target.path))
        SRC=\(quoted(source.path))
        WORK=\(quoted(work.path))
        OLD=\(quoted(previous.path))
        for _ in $(seq 1 300); do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.2
        done
        # If Ortus is still running, the quit was blocked — abort without touching it.
        if kill -0 \(pid) 2>/dev/null; then
            rm -rf "$WORK"
            exit 0
        fi
        if mv "$TARGET" "$OLD"; then
            if mv "$SRC" "$TARGET"; then
                xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
                rm -rf "$OLD"
            else
                rm -rf "$TARGET"
                mv "$OLD" "$TARGET"
            fi
        fi
        \(relaunch) "$TARGET"
        rm -rf "$WORK"
        """
    }

    static func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
}
