import Foundation

/// Swaps the app bundle for a downloaded update once the app has quit.
public enum UpdateInstaller {
    /// A bash script that waits for `pid` to exit, swaps `source` in at `target`, reopens
    /// `target` with `relaunch` and deletes `work`. It gives up without touching anything
    /// if the app is still running after about a minute (a focus session blocks quitting).
    public static func script(target: URL, source: URL, work: URL, pid: Int32, relaunch: String = "open") -> String {
        """
        #!/bin/bash
        TARGET=\(quoted(target.path))
        SRC=\(quoted(source.path))
        WORK=\(quoted(work.path))
        for _ in $(seq 1 300); do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.2
        done
        # If Ortus is still running, the quit was blocked — abort without touching it.
        if kill -0 \(pid) 2>/dev/null; then
            rm -rf "$WORK"
            exit 0
        fi
        rm -rf "$TARGET"
        mv "$SRC" "$TARGET"
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        \(relaunch) "$TARGET"
        rm -rf "$WORK"
        """
    }

    static func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
}
