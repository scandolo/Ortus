import Foundation
import OrtusCore
import Security

/// Where the Slack token and Slack app credentials live.
///
/// A Developer ID-signed release uses the login keychain. Its keychain access is
/// tied to the team (XGJ489TRXB), which stays the same across updates, so macOS
/// never asks for permission after an update.
///
/// Ad-hoc builds (Ortus Preview, snapshots, a release built without the signing
/// secrets) use a 0600 JSON file instead. macOS ties an ad-hoc build's keychain
/// access to that exact binary, so every rebuild would ask "Allow access?" again.
/// That prompt is why the token moved to a file in the first place.
///
/// The service name is the bundle id, so release and preview never share items.
enum KeychainService {
    enum Key: String, CaseIterable {
        case slackToken = "slack_token"
        case slackTeamName = "slack_team_name"
        case slackClientId = "slack_client_id"
        case slackClientSecret = "slack_client_secret"
    }

    enum KeychainError: LocalizedError {
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let reason): "Credential save failed: \(reason)"
            }
        }
    }

    private static let lock = NSLock()
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.ortusmode.app"

    /// True for a Developer ID (or Apple Development) signature, false for ad-hoc.
    private static let usesKeychain: Bool = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return false }
        return (info[kSecCodeInfoTeamIdentifier as String] as? String)?.isEmpty == false
    }()

    private static let directoryURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ortus", isDirectory: true)
    }()

    /// The release's old file, which the signed release moves into the keychain.
    private static let legacyFileURL = directoryURL.appendingPathComponent("credentials.json")

    /// Ad-hoc builds keep a file per identity, so the release moving and deleting
    /// `credentials.json` never takes the preview's token with it.
    private static var fileURL: URL {
        bundleID == "com.ortusmode.app" ? legacyFileURL
            : directoryURL.appendingPathComponent("credentials-\(bundleID).json")
    }

    // MARK: - Public API

    /// Signed release only: copies `credentials.json` into the keychain and deletes
    /// the file once every value reads back. If anything fails, the file stays and
    /// the next launch tries again; until then `load` still reads the file.
    static func migrateLegacyFileIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard usesKeychain else { return }
        let file = readFile(legacyFileURL)
        guard !file.isEmpty else { return }
        if CredentialMigration.copy(file, load: keychainRead, store: { try keychainWrite($1, account: $0) }) {
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
    }

    static func save(_ value: String, for key: Key) throws {
        lock.lock()
        defer { lock.unlock() }
        if usesKeychain {
            try keychainWrite(value, account: key.rawValue)
            // An unmigrated file must not hand back the older value later.
            removeFromFile(key, at: legacyFileURL)
        } else {
            var store = readFile(fileURL)
            store[key.rawValue] = value
            do { try writeFile(store, to: fileURL) } catch { throw KeychainError.saveFailed(error.localizedDescription) }
        }
    }

    static func load(_ key: Key) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if usesKeychain {
            // The file only still exists if the move failed; keep the token working.
            return keychainRead(key.rawValue) ?? readFile(legacyFileURL)[key.rawValue]
        }
        return readFile(fileURL)[key.rawValue]
    }

    static func delete(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        if usesKeychain {
            SecItemDelete(query(account: key.rawValue) as CFDictionary)
            removeFromFile(key, at: legacyFileURL)
        } else {
            removeFromFile(key, at: fileURL)
        }
    }

    // MARK: - Keychain

    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: bundleID,
         kSecAttrAccount as String: account]
    }

    private static func keychainRead(_ account: String) -> String? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Updates the item, or adds it when missing. Never deletes first, so a failed
    /// write can't lose the token that's already there.
    private static func keychainWrite(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let updated = SecItemUpdate(query(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError.saveFailed(explain(updated)) }
        var add = query(account: account)
        add[kSecValueData as String] = data
        // Readable while the screen is locked, so a scheduled session can still
        // update Slack. Not synchronizable, so it stays out of iCloud Keychain.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "Ortus \(account.replacingOccurrences(of: "_", with: " "))"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(explain(status)) }
    }

    private static func explain(_ status: OSStatus) -> String {
        "\(SecCopyErrorMessageString(status, nil) as String? ?? "keychain error") (\(status))"
    }

    // MARK: - File

    private static func readFile(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private static func writeFile(_ store: [String: String], to url: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(store).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func removeFromFile(_ key: Key, at url: URL) {
        var store = readFile(url)
        guard store.removeValue(forKey: key.rawValue) != nil else { return }
        if store.isEmpty { try? FileManager.default.removeItem(at: url) } else { try? writeFile(store, to: url) }
    }
}
