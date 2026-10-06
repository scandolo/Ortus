import AppKit
import OrtusCore

@MainActor
final class WebsiteBlockingService: ObservableObject {
    @Published private(set) var connectedBrowsers: [String] = []
    @Published private(set) var connectionSummary = ""
    struct SupportedBrowser: Identifiable {
        let id: String
        let name: String
        let page: String
    }
    var availableBrowsers: [SupportedBrowser] {
        [SupportedBrowser(id: "company.thebrowser.Browser", name: "Arc", page: "arc://extensions"),
         .init(id: "com.google.Chrome", name: "Chrome", page: "chrome://extensions"),
         .init(id: "com.microsoft.edgemac", name: "Edge", page: "edge://extensions"),
         .init(id: "com.brave.Browser", name: "Brave", page: "brave://extensions")]
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }
    @Published private(set) var error: String?
    @Published private(set) var enforcementError: String?
    @Published private(set) var setupError: String?
    let preview = BuildProfile.isPreview
    private let instanceID = UUID().uuidString
    private let startedAt = Date().timeIntervalSince1970
    var directory: URL { BrowserPaths.directory(preview: preview) }
    // A normal sibling folder is selectable in Chromium's Load unpacked panel.
    // Keep that path stable when replacing or rebuilding the signed app bundle.
    var extensionDirectory: URL? {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(preview ? "Ortus Preview Browser" : "Ortus Browser", isDirectory: true)
    }
    var hostName: String { preview ? "com.ortus.browser.preview" : "com.ortus.browser" }

    func publish(sessions: [FocusSession], now: Date = Date()) {
        do {
            try BrowserPaths.prepare(directory)
            try BrowserPaths.write(BrowserPolicy(sessions: sessions, now: now, appearance: BuildProfile.appearance, appName: BuildProfile.name), to: directory.appendingPathComponent("policy.json"))
            error = nil
        } catch { self.error = "Website rules could not be saved: \(error.localizedDescription)" }
        refreshConnections(now: now)
    }

    func publishPresence(now: Date = Date()) {
        do {
            let folder = directory.appendingPathComponent("presence")
            try BrowserPaths.prepare(folder)
            try BrowserPaths.write(BrowserPresence(appName: BuildProfile.name, appearance: BuildProfile.appearance, startedAt: startedAt, updatedAt: now.timeIntervalSince1970), to: folder.appendingPathComponent(instanceID + ".json"))
        } catch { self.error = "Ortus could not update browser readiness. Try reopening the app." }
        refreshConnections(now: now)
    }

    func refreshConnections(now: Date = Date()) {
        let folder = directory.appendingPathComponent("clients", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let clients = urls.compactMap { url -> BrowserClient? in
            guard let data = try? Data(contentsOf: url), let client = try? JSONDecoder().decode(BrowserClient.self, from: data),
                  now.timeIntervalSince1970 - client.updatedAt < 15, client.updatedAt <= now.timeIntervalSince1970 + 5 else { return nil }
            return client
        }
        let ready = clients.filter { $0.state == "ready" }
        connectedBrowsers = Array(Set(ready.map(\.browser))).sorted()
        connectionSummary = connectedBrowsers.map { name in
            let count = ready.filter { $0.browser == name }.count
            return "\(name) · \(count) profile\(count == 1 ? "" : "s")"
        }.joined(separator: ", ")
        enforcementError = clients.contains { $0.state == "error" } ? "A browser could not apply your rules. Open its Ortus extension and reconnect." : nil
    }

    /// User-level registration only. Re-running updates the executable path after moving a build.
    func registerCompanion() {
        do {
            guard let extensionDirectory, let bundledExtension = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true),
                  let bundle = Bundle.main.executableURL?.deletingLastPathComponent(),
                  let data = try? Data(contentsOf: bundledExtension.appendingPathComponent("identity.json")),
                  let identity = try JSONSerialization.jsonObject(with: data) as? [String: String], let id = identity["id"] else {
                throw NSError(domain: "Ortus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Rebuild Ortus with the bundled browser companion."])
            }
            let bridge = bundle.appendingPathComponent("OrtusBrowserBridge")
            guard FileManager.default.isExecutableFile(atPath: bridge.path) else {
                throw NSError(domain: "Ortus", code: 2, userInfo: [NSLocalizedDescriptionKey: "The browser connection helper is missing."])
            }
            let files = FileManager.default
            if files.fileExists(atPath: extensionDirectory.path),
               !(try files.contentsOfDirectory(atPath: extensionDirectory.path)).isEmpty {
                let existingData = try Data(contentsOf: extensionDirectory.appendingPathComponent("identity.json"))
                let existing = try JSONSerialization.jsonObject(with: existingData) as? [String: String]
                guard existing?["id"] == id else {
                    throw NSError(domain: "Ortus", code: 3, userInfo: [NSLocalizedDescriptionKey: "A different folder already uses the browser companion's name."])
                }
            }
            try files.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
            for item in try files.contentsOfDirectory(at: bundledExtension, includingPropertiesForKeys: [.isRegularFileKey]) {
                guard try item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let destination = extensionDirectory.appendingPathComponent(item.lastPathComponent)
                let contents = try Data(contentsOf: item)
                if (try? Data(contentsOf: destination)) != contents {
                    try contents.write(to: destination, options: [.atomic])
                }
            }
            let manifest: [String: Any] = ["name": hostName, "description": "Ortus focus rules", "path": bridge.path,
                                          "type": "stdio", "allowed_origins": ["chrome-extension://\(id)/"]]
            let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            for path in ["Google/Chrome", "Arc/User Data", "Microsoft Edge", "BraveSoftware/Brave-Browser", "Chromium"] {
                let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/\(path)/NativeMessagingHosts")
                try BrowserPaths.prepare(folder)
                try json.write(to: folder.appendingPathComponent(hostName + ".json"), options: [.atomic])
            }
            setupError = nil
        } catch { setupError = "Browser setup: \(error.localizedDescription)" }
    }

    func openExtensionsPage(browserID: String) {
        guard let choice = availableBrowsers.first(where: { $0.id == browserID }),
              let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.id),
              let target = URL(string: choice.page) else {
            setupError = "Choose an installed supported browser: Arc, Chrome, Edge or Brave. Safari and Firefox are not supported."
            return
        }
        NSWorkspace.shared.open([target], withApplicationAt: browser, configuration: .init()) { _, error in
            if error != nil {
                Task { @MainActor in self.setupError = "Paste \(target.absoluteString) in \(choice.name), then choose Load unpacked." }
            }
        }
    }

    func revealCompanion() {
        registerCompanion()
        if setupError == nil, let extensionDirectory { NSWorkspace.shared.activateFileViewerSelecting([extensionDirectory]) }
    }
}
