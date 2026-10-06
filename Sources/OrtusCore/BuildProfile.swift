import Foundation
import Darwin

public enum BuildProfile {
    public static var isPreview: Bool { Bundle.main.object(forInfoDictionaryKey: "OrtusPreviewBuild") as? Bool == true }
    public static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Ortus" }
}

/// Only an active session holds this lock. Idle comparison windows never write
/// over another app's policy, and process exit automatically releases ownership.
public final class FocusEngineLock {
    private var descriptor: Int32 = -1
    private let url: URL
    public var isHeld: Bool { descriptor >= 0 }
    public init(directory: URL) { url = directory.appendingPathComponent("focus-engine.lock") }
    public func acquire() -> Bool {
        if isHeld { return true }
        try? BrowserPaths.prepare(url.deletingLastPathComponent())
        let fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        descriptor = fd
        return true
    }
    public func release() {
        guard isHeld else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
    deinit { release() }
}

public struct BrowserPresence: Codable, Sendable {
    public var appName: String
    public var startedAt: Double
    public var updatedAt: Double
    public init(appName: String, startedAt: Double, updatedAt: Double) {
        self.appName = appName; self.startedAt = startedAt; self.updatedAt = updatedAt
    }
}
