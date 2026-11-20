import Foundation
import LocalAuthentication
import OrtusCore
import Security

/// Login-keychain store for the Slack token and the Slack app credentials.
///
/// This used to be the login keychain. It moved to
/// `~/Library/Application Support/Ortus/credentials.json` (mode 0600) because an
/// ad-hoc signature's designated requirement includes the cdhash: every rebuild
/// failed the item's ACL and macOS asked "Always Allow" again. Releases are
/// Developer ID signed now (team XGJ489TRXB, the same identity `UpdateVerifier`
/// checks). That signature's designated requirement does not include the cdhash,
/// so an item created by one release is readable by the next one with no dialog.
///
/// The data-protection keychain (`kSecUseDataProtectionKeychain` plus a
/// `keychain-access-groups` entitlement) would also avoid dialogs, but that
/// entitlement has to be authorized by a provisioning profile. These releases
/// are signed and notarized without one. Shipping the entitlement makes AMFI
/// refuse to launch the app on machines other than the build machine.
///
/// Ad-hoc preview builds still have no team. `build.sh` pins their designated
/// requirement to the bundle identifier so a rebuild matches the ACL. Queries
/// pass a context with interaction disallowed, so a mismatch returns an error
/// instead of a dialog. The service name is the bundle id: `com.ortusmode.app`
/// and `com.ortusmode.preview` do not see each other's items.
///
/// `load`, `save` and `delete` are unchanged.
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

    private static let lock = NSLock()

    /// Present for a Developer ID or Apple Development signature, absent for
    /// ad-hoc. The release ACL is the system's designated requirement only when
    /// this is true; that requirement is what stays stable across updates.
    private static let hasTeamSignature: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let info = info as? [String: Any] else { return false }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        return team?.isEmpty == false
    }()

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.ortusmode.unsigned"
    }

    private static var mayMutateSharedFile: Bool {
        LegacyCredentialFile.mayRemoveSharedFile(bundleIdentifier: Bundle.main.bundleIdentifier, teamSigned: hasTeamSignature)
    }

    private static let directoryURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ortus", isDirectory: true)
    }()

    private static let fileURL = directoryURL.appendingPathComponent("credentials.json")

    /// Accounts the user deleted. Migration must not copy them back out of the
    /// file. The preview cannot edit that file (it may be the release's only
    /// copy), so the set is what makes Disconnect stick there. Per bundle id,
    /// because UserDefaults is.
    private static let ignoredAccountsKey = "ortus.keychain.ignoredFileAccounts"

    private static func ignoredAccounts() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: ignoredAccountsKey) ?? [])
    }

    private static func setIgnoredAccounts(_ accounts: Set<String>) {
        if accounts.isEmpty {
            UserDefaults.standard.removeObject(forKey: ignoredAccountsKey)
        } else {
            UserDefaults.standard.set(accounts.sorted(), forKey: ignoredAccountsKey)
        }
    }

    // MARK: - Public API

    /// Copies `credentials.json` into this app's keychain. The signed release
    /// deletes the file only after the keychain reads back. Safe to call again.
    static func migrateLegacyFileIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        migrateLocked()
    }

    static func save(_ value: String, for key: Key) throws {
        lock.lock()
        defer { lock.unlock() }
        var ignored = ignoredAccounts()
        ignored.remove(key.rawValue)
        setIgnoredAccounts(ignored)
        migrateLocked()
        try write(value, account: key.rawValue)
        // The keychain now has the newest value. Drop the file's copy so a
        // later migration cannot put the previous token back. Previews do not
        // edit the file: it may still be the release's only copy.
        if mayMutateSharedFile { LegacyCredentialFile.removeKey(key.rawValue, from: fileURL) }
    }

    static func load(_ key: Key) -> String? {
        lock.lock()
        defer { lock.unlock() }
        migrateLocked()
        if let value = read(account: key.rawValue) { return value }
        // Deleted in this app. The file may still hold it for the other identity.
        if ignoredAccounts().contains(key.rawValue) { return nil }
        // The keychain write has not succeeded yet. Keep using the file so a
        // working token survives until a later launch can move it.
        guard case .values(let values) = LegacyCredentialFile.read(fileURL) else { return nil }
        return values[key.rawValue]
    }

    static func delete(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        // Not migrated first: migration would write the key back, then we would
        // delete it. The ignored set stops the next launch from restoring it
        // out of the file. The signed release also removes it from the file.
        var ignored = ignoredAccounts()
        ignored.insert(key.rawValue)
        setIgnoredAccounts(ignored)
        _ = SecItemDelete(query(account: key.rawValue) as CFDictionary)
        if mayMutateSharedFile { LegacyCredentialFile.removeKey(key.rawValue, from: fileURL) }
    }

    // MARK: - Keychain

    private static func migrateLocked() {
        LegacyCredentialFile.migrate(
            fileAt: fileURL,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            teamSigned: hasTeamSignature,
            load: { read(account: $0) },
            store: { try write($1, account: $0) },
            ignoring: ignoredAccounts()
        )
    }

    private static func query(account: String) -> [String: Any] {
        // A dialog here would be the bug we are avoiding. Failure leaves the
        // file in place, and `load` keeps reading it. The context has to live
        // as long as the query dictionary that holds it.
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context,
        ]
    }

    private static func read(account: String) -> String? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Updates the item, or adds it when it is missing. An add gets this
    /// process's designated requirement as its ACL. An update leaves the ACL
    /// alone, so a token that is already stored is never deleted in order to
    /// recreate it.
    private static func write(_ value: String, account: String) throws {
        let query = query(account: account)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
        if updated == errSecSuccess { return }
        if updated != errSecItemNotFound { throw KeychainError.saveFailed(explain(updated)) }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        // Available after the user has unlocked the Mac once, including while
        // the screen is locked, so a scheduled session can still update Slack.
        // Not the iCloud-synced classes: synchronizable is left unset, so the
        // item stays in the local login keychain.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = label(for: account)
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(explain(status)) }
    }

    private static func label(for account: String) -> String {
        switch Key(rawValue: account) {
        case .slackToken: "Ortus Slack token"
        case .slackTeamName: "Ortus Slack workspace"
        case .slackClientId: "Ortus Slack client ID"
        case .slackClientSecret: "Ortus Slack client secret"
        case nil: "Ortus credential"
        }
    }

    private static func explain(_ status: OSStatus) -> String {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "keychain error"
        return "\(text) (\(status))"
    }
}
