import Foundation
import OrtusCore

struct CredentialTests {
    func migrationKeepsTheKeychainValueAndCopiesTheRest() {
        var keychain = ["slack_token": "newer"]
        let ok = CredentialMigration.copy(["slack_token": "older", "slack_client_id": "id"],
                                          load: { keychain[$0] }, store: { keychain[$0] = $1 })
        expect(ok)
        expect(keychain == ["slack_token": "newer", "slack_client_id": "id"])
    }

    func migrationKeepsTheFileWhenAWriteFails() {
        struct Failed: Error {}
        let ok = CredentialMigration.copy(["slack_token": "only-copy"], load: { _ in nil }, store: { _, _ in throw Failed() })
        expect(!ok)
    }
}
