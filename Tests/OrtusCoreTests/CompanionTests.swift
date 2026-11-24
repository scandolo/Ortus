import Foundation
import OrtusCore

struct CompanionTests {
    private let files = FileManager.default
    private let bridge = URL(fileURLWithPath: "/Applications/Ortus.app/Contents/MacOS/OrtusBrowserBridge")
    private let origins = ["chrome-extension://unpacked/", "chrome-extension://store/"]

    private func write(_ text: String, to url: URL) throws {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
    private func manifest(_ browser: String, in support: URL) -> [String: Any]? {
        let url = support.appendingPathComponent("\(browser)/NativeMessagingHosts/com.ortus.browser.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
    /// Temporary folders only: nothing lands in ~/Library.
    private func withScratch(_ body: (URL, (URL) throws -> Void) throws -> Void) throws {
        let root = files.temporaryDirectory.appendingPathComponent("OrtusCompanionChecks-\(UUID().uuidString)", isDirectory: true)
        var locked: [URL] = []
        defer {
            for url in locked { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
            try? files.removeItem(at: root)
        }
        try body(root) { url in
            try files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
            locked.append(url)
            expect(!files.isWritableFile(atPath: url.path)) // as root nothing is read-only, so the cases below would prove nothing
        }
    }
    private func bundledExtension(in root: URL) throws -> URL {
        let bundled = root.appendingPathComponent("Ortus.app/Contents/Resources/BrowserExtension", isDirectory: true)
        try write(#"{"id":"unpacked","storeID":"store"}"#, to: bundled.appendingPathComponent("identity.json"))
        try write("new", to: bundled.appendingPathComponent("background.js"))
        return bundled
    }

    /// The extension must reach the app even when the Load unpacked folder beside the app can't be updated:
    /// another macOS user owns it, a non-admin account can't create it, or the app runs from the DMG.
    func hostManifestsDoNotWaitForTheUnpackedFolder() throws {
        try withScratch { root, lock in
            let bundled = try bundledExtension(in: root)
            let otherUser = root.appendingPathComponent("A/Ortus Browser", isDirectory: true)
            try write(#"{"id":"unpacked","storeID":"store"}"#, to: otherUser.appendingPathComponent("identity.json"))
            try write("old", to: otherUser.appendingPathComponent("background.js"))
            try lock(otherUser)
            let readOnlyParent = root.appendingPathComponent("B", isDirectory: true)
            try files.createDirectory(at: readOnlyParent, withIntermediateDirectories: true)
            try lock(readOnlyParent)
            let taken = root.appendingPathComponent("C/Ortus Browser", isDirectory: true)
            try write(#"{"id":"someone-else"}"#, to: taken.appendingPathComponent("identity.json"))

            for (index, folder) in [otherUser, readOnlyParent.appendingPathComponent("Ortus Browser", isDirectory: true), taken].enumerated() {
                let support = root.appendingPathComponent("Support \(index)", isDirectory: true)
                let result = CompanionRegistration.register(hostName: "com.ortus.browser", bridge: bridge, unpackedID: "unpacked", storeID: "store",
                                                            bundledExtension: bundled, unpackedFolder: folder, applicationSupport: support)
                expect(result.manifests == nil)
                expect(result.folder != nil)
                for browser in CompanionRegistration.browserFolders {
                    expect(manifest(browser, in: support)?["path"] as? String == bridge.path)
                    expect(manifest(browser, in: support)?["allowed_origins"] as? [String] == origins)
                }
            }
            expect(read(otherUser.appendingPathComponent("background.js")) == "old")
            expect(read(taken.appendingPathComponent("identity.json")) == #"{"id":"someone-else"}"#) // someone else's folder stays as it was
        }
    }

    /// A writable folder gets the bundled files, and each launch points the manifest at the running app's bridge.
    func registrationCopiesTheExtensionAndFollowsAMovedApp() throws {
        try withScratch { root, _ in
            let bundled = try bundledExtension(in: root)
            let folder = root.appendingPathComponent("Applications/Ortus Browser", isDirectory: true)
            let support = root.appendingPathComponent("Support", isDirectory: true)
            let fromDMG = URL(fileURLWithPath: "/Volumes/Ortus/Ortus.app/Contents/MacOS/OrtusBrowserBridge")
            for path in [fromDMG, bridge] {
                let result = CompanionRegistration.register(hostName: "com.ortus.browser", bridge: path, unpackedID: "unpacked", storeID: "store",
                                                            bundledExtension: bundled, unpackedFolder: folder, applicationSupport: support)
                expect(result.manifests == nil && result.folder == nil)
                expect(CompanionRegistration.browserFolders.allSatisfy { manifest($0, in: support)?["path"] as? String == path.path })
            }
            expect(read(folder.appendingPathComponent("background.js")) == "new")
            expect(read(folder.appendingPathComponent("identity.json")) == #"{"id":"unpacked","storeID":"store"}"#)
        }
    }
}
