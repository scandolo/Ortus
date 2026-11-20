import Foundation

/// Moving the old `credentials.json` into the keychain without losing a token.
public enum CredentialMigration {
    /// Copies each file value the keychain doesn't have yet, then checks every key
    /// reads back. A value already in the keychain wins: it was saved later.
    /// Returns true only when the file is safe to delete.
    public static func copy(_ file: [String: String],
                            load: (String) -> String?,
                            store: (String, String) throws -> Void) -> Bool {
        for (key, value) in file where load(key) == nil {
            do { try store(key, value) } catch { return false }
        }
        return file.keys.allSatisfy { load($0) != nil }
    }
}
