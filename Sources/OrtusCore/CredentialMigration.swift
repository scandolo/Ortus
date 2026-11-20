import Darwin
import Foundation

/// Moves `~/Library/Application Support/Ortus/credentials.json` into the login
/// keychain without dropping a value that is still only on disk.
///
/// The file is shared by the release and the preview (the old store had one
/// path). The release is the copy users actually run, so only a team-signed
/// release may delete it, and only after every value reads back. A preview may
/// copy into its own keychain first; it must leave the file for the release.
public enum LegacyCredentialFile {
    public static let releaseBundleID = "com.ortusmode.app"
    public static let previewBundleID = "com.ortusmode.preview"

    public enum Contents: Equatable, Sendable {
        case missing
        case unreadable
        /// Parsed object. Empty means the file was `{}` or blank, so there is
        /// nothing left to keep.
        case values([String: String])
    }

    /// What a migration must write, and the value that has to read back before
    /// the file may be removed. A value already in the keychain wins: a save
    /// that landed there is newer than the file.
    public struct Plan: Equatable, Sendable {
        public var writes: [String: String]
        public var expected: [String: String]
    }

    public static func readsSharedFile(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == releaseBundleID || bundleIdentifier == previewBundleID
    }

    /// Ad-hoc and preview builds leave the file. They can create a keychain
    /// item the signed release is not allowed to replace, and deleting the file
    /// first would strand the token.
    public static func mayRemoveSharedFile(bundleIdentifier: String?, teamSigned: Bool) -> Bool {
        teamSigned && bundleIdentifier == releaseBundleID
    }

    public static func plan(file: [String: String], keychain: [String: String]) -> Plan {
        var writes: [String: String] = [:]
        var expected: [String: String] = [:]
        for (key, value) in file {
            if let existing = keychain[key] {
                expected[key] = existing
            } else {
                writes[key] = value
                expected[key] = value
            }
        }
        return Plan(writes: writes, expected: expected)
    }

    public static func read(_ url: URL) -> Contents {
        var info = stat()
        let status = url.path.withCString { lstat($0, &info) }
        if status != 0 { return .missing }
        // A symlink could point at something we must not wipe.
        guard isRegularFile(info.st_mode) else { return .unreadable }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        if data.isEmpty { return .values([:]) }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreadable }
        var values: [String: String] = [:]
        for (key, value) in raw {
            guard let string = value as? String else { return .unreadable }
            values[key] = string
        }
        return .values(values)
    }

    /// Copies the file into the keychain. Returns whether the file was removed.
    /// `store` is asked only for keys the keychain does not already have: a
    /// value already there is newer, and replacing the item would drop it if
    /// the write failed halfway. Removal happens only after `load` returns
    /// each expected value.
    ///
    /// `ignoring` is the set of accounts the user has deleted. A signed release
    /// strips those from the file. Anyone else leaves them on disk (the release
    /// may still need them) and does not copy them back into the keychain.
    @discardableResult
    public static func migrate(
        fileAt url: URL,
        bundleIdentifier: String?,
        teamSigned: Bool,
        load: (String) -> String?,
        store: (String, String) throws -> Void,
        ignoring: Set<String> = []
    ) -> Bool {
        guard readsSharedFile(bundleIdentifier: bundleIdentifier) else { return false }
        let mayRemove = mayRemoveSharedFile(bundleIdentifier: bundleIdentifier, teamSigned: teamSigned)
        if mayRemove {
            for key in ignoring { _ = removeKey(key, from: url) }
        }
        guard case .values(let file) = read(url) else { return false }
        if file.isEmpty {
            guard mayRemove else { return false }
            return secureDelete(url)
        }
        let pending = file.filter { !ignoring.contains($0.key) }
        // Ignored keys still in the file (a preview must not delete them) mean
        // this process cannot remove the file, or it would take the release's copy.
        guard !pending.isEmpty else { return false }
        var existing: [String: String] = [:]
        for key in pending.keys {
            if let value = load(key) { existing[key] = value }
        }
        let plan = plan(file: pending, keychain: existing)
        // Only missing keys are written. Replacing an item that is already in
        // the keychain would delete the newer value before the new item exists.
        for (key, value) in plan.writes {
            do { try store(key, value) } catch { return false }
        }
        for (key, expected) in plan.expected where load(key) != expected { return false }
        guard mayRemove, pending.count == file.count else { return false }
        return secureDelete(url)
    }

    /// Drops one key. Removes the file when it is the last one. Does nothing
    /// when the file is missing or not entirely strings, so a parse failure
    /// cannot throw away a token we failed to read.
    @discardableResult
    public static func removeKey(_ key: String, from url: URL) -> Bool {
        guard case .values(var values) = read(url), values.removeValue(forKey: key) != nil else { return false }
        if values.isEmpty { return secureDelete(url) }
        return replace(values, at: url)
    }

    /// Overwrites a regular file, then unlinks it. Symlinks are left alone,
    /// including whatever they point at.
    @discardableResult
    public static func secureDelete(_ url: URL) -> Bool {
        let path = url.path
        var info = stat()
        let status = path.withCString { lstat($0, &info) }
        guard status == 0, isRegularFile(info.st_mode) else { return false }
        if info.st_size > 0, let fd = openForUpdate(path) {
            overwrite(fd, length: Int(info.st_size))
            close(fd)
        }
        return path.withCString { unlink($0) } == 0
    }

    // MARK: - File bytes

    private static func replace(_ values: [String: String], at url: URL) -> Bool {
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return false }
        let path = url.path
        var info = stat()
        let status = path.withCString { lstat($0, &info) }
        guard status == 0, isRegularFile(info.st_mode), let fd = openForUpdate(path) else { return false }
        defer { close(fd) }
        let oldSize = Int(info.st_size)
        var payload = data
        if oldSize > data.count { payload.append(Data(count: oldSize - data.count)) }
        guard writeAll(fd, payload), ftruncate(fd, off_t(data.count)) == 0, fsync(fd) == 0 else { return false }
        path.withCString { _ = chmod($0, mode_t(0o600)) }
        return true
    }

    private static func isRegularFile(_ mode: mode_t) -> Bool {
        (Int(mode) & Int(S_IFMT)) == Int(S_IFREG)
    }

    private static func openForUpdate(_ path: String) -> Int32? {
        let fd = open(path, O_RDWR | O_NOFOLLOW, 0o600)
        return fd >= 0 ? fd : nil
    }

    /// Random bytes, then zeros. A crash between them still leaves nothing readable.
    private static func overwrite(_ fd: Int32, length: Int) {
        guard length > 0 else { return }
        var generator = SystemRandomNumberGenerator()
        var random = Data(count: length)
        random.withUnsafeMutableBytes { buffer in
            guard let bytes = buffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<buffer.count {
                bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
            }
        }
        if writeAll(fd, random), lseek(fd, 0, SEEK_SET) == 0 {
            _ = fsync(fd)
            _ = writeAll(fd, Data(count: length))
            _ = fsync(fd)
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var offset = 0
        let total = data.count
        while offset < total {
            let wrote = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return write(fd, base.advanced(by: offset), total - offset)
            }
            if wrote <= 0 { return false }
            offset += wrote
        }
        return true
    }
}
