import Foundation

/// File-backed credential store.
///
/// Historically this used the macOS keychain (Security framework), but an
/// unsigned / freshly-rebuilt app triggers a keychain access prompt on every
/// read until the user clicks "Always Allow" — and that ACL is tied to the app's
/// code signature, which is not stable for a scrappy self-signed distribution
/// build. To guarantee zero prompts for end users, credentials now live in a
/// plain JSON file in Application Support, readable only by the current user
/// (chmod 0600).
///
/// The type name and public API are intentionally unchanged so existing call
/// sites (`KeychainService.load/.save/.delete`) keep compiling untouched.
enum KeychainService {
    enum Key: String {
        case slackToken = "slack_token"
        case slackTeamName = "slack_team_name"
        case slackClientId = "slack_client_id"
        case slackClientSecret = "slack_client_secret"
    }

    enum KeychainError: LocalizedError {
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let reason):
                "Credential save failed: \(reason)"
            }
        }
    }

    // MARK: - Storage location

    private static let directoryURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ortus", isDirectory: true)
    }()

    private static let fileURL = directoryURL.appendingPathComponent("credentials.json")

    /// Serialize access so a concurrent save/load can't interleave a read with a
    /// partial write.
    private static let lock = NSLock()

    // MARK: - Public API

    static func save(_ value: String, for key: Key) throws {
        lock.lock()
        defer { lock.unlock() }
        var store = readStore()
        store[key.rawValue] = value
        do {
            try writeStore(store)
        } catch {
            throw KeychainError.saveFailed(error.localizedDescription)
        }
    }

    static func load(_ key: Key) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return readStore()[key.rawValue]
    }

    static func delete(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        var store = readStore()
        store.removeValue(forKey: key.rawValue)
        try? writeStore(store)
    }

    // MARK: - Helpers

    private static func readStore() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return dict
    }

    private static func writeStore(_ store: [String: String]) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let data = try JSONEncoder().encode(store)
        try data.write(to: fileURL, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
