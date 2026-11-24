import Foundation

/// User-level registration of the browser companion. Re-running updates the bridge path after moving a build.
public enum CompanionRegistration {
    /// Chromium browsers that read user-level native messaging hosts, under Application Support.
    public static let browserFolders = ["Google/Chrome", "Arc/User Data", "Microsoft Edge", "BraveSoftware/Brave-Browser", "Chromium"]

    public static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// Writes the host manifest for every browser, then copies the bundled extension to `unpackedFolder`
    /// (for Load unpacked). The manifests are what let any installed extension reach the app, so they come
    /// first and never wait on the folder, which can't be written when another macOS user owns it, a
    /// non-admin account can't create it, or the app runs from the DMG. Returns each step's error.
    public static func register(hostName: String, bridge: URL, unpackedID: String, storeID: String?,
                                bundledExtension: URL, unpackedFolder: URL,
                                applicationSupport: URL = applicationSupport) -> (manifests: Error?, folder: Error?) {
        var manifests: Error?, folder: Error?
        do {
            try writeManifests(hostName: hostName, bridge: bridge, origins: BrowserCompanion.allowedOrigins(unpackedID: unpackedID, storeID: storeID), applicationSupport: applicationSupport)
        } catch { manifests = error }
        do { try copyExtension(from: bundledExtension, to: unpackedFolder, unpackedID: unpackedID) } catch { folder = error }
        return (manifests, folder)
    }

    /// One browser's folder failing doesn't stop the others.
    static func writeManifests(hostName: String, bridge: URL, origins: [String], applicationSupport: URL) throws {
        let manifest: [String: Any] = ["name": hostName, "description": "Ortus focus rules", "path": bridge.path,
                                      "type": "stdio", "allowed_origins": origins]
        let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        var firstError: Error?
        for path in browserFolders {
            do {
                let folder = applicationSupport.appendingPathComponent("\(path)/NativeMessagingHosts", isDirectory: true)
                try BrowserPaths.prepare(folder)
                try json.write(to: folder.appendingPathComponent(hostName + ".json"), options: [.atomic])
            } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    static func copyExtension(from bundled: URL, to folder: URL, unpackedID: String) throws {
        let files = FileManager.default
        if files.fileExists(atPath: folder.path), !(try files.contentsOfDirectory(atPath: folder.path)).isEmpty {
            let existingData = try Data(contentsOf: folder.appendingPathComponent("identity.json"))
            let existing = try JSONSerialization.jsonObject(with: existingData) as? [String: String]
            guard existing?["id"] == unpackedID else {
                throw NSError(domain: "Ortus", code: 3, userInfo: [NSLocalizedDescriptionKey: "A different folder already uses the browser companion's name."])
            }
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in try files.contentsOfDirectory(at: bundled, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard try item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let destination = folder.appendingPathComponent(item.lastPathComponent)
            let contents = try Data(contentsOf: item)
            if (try? Data(contentsOf: destination)) != contents {
                try contents.write(to: destination, options: [.atomic])
            }
        }
    }
}
