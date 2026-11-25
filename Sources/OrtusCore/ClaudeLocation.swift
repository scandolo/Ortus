import Foundation

/// Where Claude Code is on this Mac.
public enum ClaudeLocation {
    /// True when `path` is an absolute path to a file this user can run. A symlink counts
    /// by its target: the native installer's `~/.local/bin/claude` is one. A folder doesn't
    /// count, even though folders carry the execute bit.
    public static func isRunnable(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/")
            && fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && fileManager.isExecutableFile(atPath: path)
    }
}
