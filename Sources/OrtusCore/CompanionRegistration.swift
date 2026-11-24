import Foundation

/// User-level registration of the browser companion. Re-running updates the bridge path after moving a build.
public enum CompanionRegistration {
    /// Chromium browsers that read user-level native messaging hosts, under Application Support.
    public static let browserFolders = ["Google/Chrome", "Arc/User Data", "Microsoft Edge", "BraveSoftware/Brave-Browser", "Chromium"]

    public static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// Copies the bundled extension to `unpackedFolder` (for Load unpacked) and writes the host manifest
    /// for every browser. Returns what went wrong with the manifests and with the folder.
    public static func register(hostName: String, bridge: URL, unpackedID: String, storeID: String?,
                                bundledExtension: URL, unpackedFolder: URL,
                                applicationSupport: URL = applicationSupport) -> (manifests: Error?, folder: Error?) {
        do {
            try copyExtension(from: bundledExtension, to: unpackedFolder, unpackedID: unpackedID)
            try writeManifests(hostName: hostName, bridge: bridge, origins: BrowserCompanion.allowedOrigins(unpackedID: unpackedID, storeID: storeID), applicationSupport: applicationSupport)
            return (nil, nil)
        } catch { return (error, nil) }
    }

    static func writeManifests(hostName: String, bridge: URL, origins: [String], applicationSupport: URL) throws {
        let manifest: [String: Any] = ["name": hostName, "description": "Ortus focus rules", "path": bridge.path,
                                      "type": "stdio", "allowed_origins": origins]
        let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        for path in browserFolders {
            let folder = applicationSupport.appendingPathComponent("\(path)/NativeMessagingHosts", isDirectory: true)
            try BrowserPaths.prepare(folder)
            try json.write(to: folder.appendingPathComponent(hostName + ".json"), options: [.atomic])
        }
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
