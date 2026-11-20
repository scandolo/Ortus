import Foundation
import OrtusCore

struct CredentialTests {
    func planKeepsAKeychainValueOverTheFile() {
        let plan = LegacyCredentialFile.plan(
            file: ["slack_token": "from-file", "slack_client_id": "id"],
            keychain: ["slack_token": "from-keychain"]
        )
        expect(plan.writes == ["slack_client_id": "id"])
        expect(plan.expected["slack_token"] == "from-keychain")
        expect(plan.expected["slack_client_id"] == "id")
    }

    func onlyATeamSignedReleaseMayRemoveTheSharedFile() {
        expect(LegacyCredentialFile.mayRemoveSharedFile(bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: true))
        expect(!LegacyCredentialFile.mayRemoveSharedFile(bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: false))
        expect(!LegacyCredentialFile.mayRemoveSharedFile(bundleIdentifier: LegacyCredentialFile.previewBundleID, teamSigned: true))
        expect(!LegacyCredentialFile.mayRemoveSharedFile(bundleIdentifier: "com.ortusmode.snapshot", teamSigned: true))
        expect(LegacyCredentialFile.readsSharedFile(bundleIdentifier: LegacyCredentialFile.previewBundleID))
        expect(!LegacyCredentialFile.readsSharedFile(bundleIdentifier: "com.ortusmode.snapshot"))
        expect(!LegacyCredentialFile.readsSharedFile(bundleIdentifier: nil))
    }

    func migrationRemovesTheFileOnlyAfterAVerifiedReleaseCopy() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("credentials.json")
        let original = Data(#"{"slack_token":"old","slack_client_id":"id","extra":"keep"}"#.utf8)
        try original.write(to: url)

        // A snapshot, or any other bundle id, must not read or remove the file.
        var stored: [String: String] = ["slack_token": "new"]
        let ignored = LegacyCredentialFile.migrate(
            fileAt: url, bundleIdentifier: "com.ortusmode.snapshot", teamSigned: true,
            load: { stored[$0] }, store: { _, _ in preconditionFailure("snapshot must not write") }
        )
        expect(!ignored)
        expect(try Data(contentsOf: url) == original)

        // The preview copies keys it does not already have and leaves the file.
        var previewWrites: [String: String] = [:]
        let previewRemoved = LegacyCredentialFile.migrate(
            fileAt: url, bundleIdentifier: LegacyCredentialFile.previewBundleID, teamSigned: false,
            load: { stored[$0] },
            store: { key, value in previewWrites[key] = value; stored[key] = value }
        )
        expect(!previewRemoved)
        expect(try Data(contentsOf: url) == original)
        expect(previewWrites == ["slack_client_id": "id", "extra": "keep"])
        expect(stored["slack_token"] == "new")

        // An ad-hoc release identity is not allowed to be the one that deletes.
        let adHocRemoved = LegacyCredentialFile.migrate(
            fileAt: url, bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: false,
            load: { stored[$0] }, store: { _, _ in }
        )
        expect(!adHocRemoved)
        expect(FileManager.default.fileExists(atPath: url.path))

        // A failed write leaves the file alone, including keys already copied.
        let failed = LegacyCredentialFile.migrate(
            fileAt: url, bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: true,
            load: { stored[$0] }, store: { _, _ in throw TestError.failed }
        )
        expect(!failed)
        expect(try Data(contentsOf: url) == original)

        // A read-back that does not match leaves the file alone.
        let mismatched = LegacyCredentialFile.migrate(
            fileAt: url, bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: true,
            load: { _ in nil }, store: { _, _ in }
        )
        expect(!mismatched)
        expect(try Data(contentsOf: url) == original)

        // The signed release keeps a value already in the keychain (it does not
        // write the file's older token back) and removes the file once every
        // key reads back.
        var releaseStore = ["slack_token": "new"]
        var releaseWrites: [String: String] = [:]
        let released = LegacyCredentialFile.migrate(
            fileAt: url, bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: true,
            load: { releaseStore[$0] },
            store: { key, value in releaseWrites[key] = value; releaseStore[key] = value }
        )
        expect(released)
        expect(!FileManager.default.fileExists(atPath: url.path))
        expect(releaseWrites["slack_token"] == nil)
        expect(releaseWrites["slack_client_id"] == "id")
        expect(releaseWrites["extra"] == "keep")
        expect(releaseStore["slack_token"] == "new")

        // Anything that is not a string-to-string object stays on disk.
        let corrupt = dir.appendingPathComponent("corrupt.json")
        try Data(#"{"slack_token":"t","n":1}"#.utf8).write(to: corrupt)
        let kept = LegacyCredentialFile.migrate(
            fileAt: corrupt, bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: true,
            load: { _ in nil }, store: { _, _ in preconditionFailure("unreadable file must not be stored") }
        )
        expect(!kept)
        expect(FileManager.default.fileExists(atPath: corrupt.path))

        // An empty file has nothing to lose. Only the signed release removes it.
        let empty = dir.appendingPathComponent("empty.json")
        try Data("{}".utf8).write(to: empty)
        expect(!LegacyCredentialFile.migrate(
            fileAt: empty, bundleIdentifier: LegacyCredentialFile.previewBundleID, teamSigned: false,
            load: { _ in nil }, store: { _, _ in }
        ))
        expect(FileManager.default.fileExists(atPath: empty.path))
        expect(LegacyCredentialFile.migrate(
            fileAt: empty, bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: true,
            load: { _ in nil }, store: { _, _ in }
        ))
        expect(!FileManager.default.fileExists(atPath: empty.path))

        // Disconnect removes one key, and the file goes away with the last key.
        let two = dir.appendingPathComponent("two.json")
        try Data(#"{"slack_token":"t","slack_team_name":"Acme"}"#.utf8).write(to: two)
        expect(LegacyCredentialFile.removeKey("slack_team_name", from: two))
        guard case .values(let left) = LegacyCredentialFile.read(two) else { preconditionFailure("expected the remaining key") }
        expect(left == ["slack_token": "t"])
        expect(LegacyCredentialFile.removeKey("slack_token", from: two))
        expect(!FileManager.default.fileExists(atPath: two.path))
        expect(!LegacyCredentialFile.removeKey("slack_token", from: two))

        // Disconnect in the preview must not copy that account back, and must
        // not delete the file while the release still needs it. The signed
        // release drops the disconnected account, keeps the rest, then removes
        // the file once the rest reads back.
        let disconnected = dir.appendingPathComponent("disconnected.json")
        try Data(#"{"slack_token":"t","slack_client_id":"id"}"#.utf8).write(to: disconnected)
        var keptWrites: [String: String] = [:]
        let previewKept = LegacyCredentialFile.migrate(
            fileAt: disconnected, bundleIdentifier: LegacyCredentialFile.previewBundleID, teamSigned: false,
            load: { _ in nil }, store: { key, value in keptWrites[key] = value }, ignoring: ["slack_token"]
        )
        expect(!previewKept)
        expect(keptWrites == ["slack_client_id": "id"])
        guard case .values(let still) = LegacyCredentialFile.read(disconnected) else { preconditionFailure("preview must leave the file") }
        expect(still["slack_token"] == "t")
        var releaseKept: [String: String] = [:]
        let releaseCleared = LegacyCredentialFile.migrate(
            fileAt: disconnected, bundleIdentifier: LegacyCredentialFile.releaseBundleID, teamSigned: true,
            load: { releaseKept[$0] },
            store: { key, value in releaseKept[key] = value },
            ignoring: ["slack_token"]
        )
        expect(releaseCleared)
        expect(releaseKept["slack_token"] == nil)
        expect(releaseKept["slack_client_id"] == "id")
        expect(!FileManager.default.fileExists(atPath: disconnected.path))
    }

    func secureDeleteRemovesARegularFileAndLeavesSymlinksAlone() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let secret = dir.appendingPathComponent("secret.json")
        try Data("token".utf8).write(to: secret)
        let link = dir.appendingPathComponent("credentials.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        expect(!LegacyCredentialFile.secureDelete(link))
        expect(try Data(contentsOf: secret) == Data("token".utf8))
        // attributesOfItem follows symlinks, so check the link itself this way.
        _ = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        expect(LegacyCredentialFile.secureDelete(secret))
        expect(!FileManager.default.fileExists(atPath: secret.path))
        expect(!LegacyCredentialFile.secureDelete(secret))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ortus-credentials-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private enum TestError: Error { case failed }
}
