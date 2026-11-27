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
         .init(id: "company.thebrowser.dia", name: "Dia", page: "dia://extensions"),
         .init(id: "com.google.Chrome", name: "Chrome", page: "chrome://extensions"),
         .init(id: "com.microsoft.edgemac", name: "Edge", page: "edge://extensions"),
         .init(id: "com.brave.Browser", name: "Brave", page: "brave://extensions")]
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }
    /// The next browser Ortus will close because its extension is off. `incognitoOff`: the
    /// extension is on but not allowed in incognito, so one switch on its Details page fixes it.
    struct ClosingBrowser: Equatable { let name: String; let closesAt: Date; var bundleID = ""; var incognitoOff = false }
    @Published private(set) var closingBrowser: ClosingBrowser?
    private var browserGuard = BrowserGuard()
    /// Browsers with a working extension right now, by bundle ID.
    private var protectedBrowsers: Set<String> = []
    /// Browsers whose extension is connected but not allowed in incognito, mapped to its id.
    private var incognitoOff: [String: String] = [:]
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
            try BrowserPaths.write(BrowserPolicy(sessions: sessions, now: now, appName: BuildProfile.name,
                                                    tone: UserDefaults.standard.bool(forKey: "genZMode") ? "genz" : nil), to: directory.appendingPathComponent("policy.json"))
            error = nil
        } catch { self.error = "Website rules could not be saved: \(error.localizedDescription)" }
        refreshConnections(now: now)
    }

    func publishPresence(now: Date = Date()) {
        do {
            let folder = directory.appendingPathComponent("presence")
            try BrowserPaths.prepare(folder)
            try BrowserPaths.write(BrowserPresence(appName: BuildProfile.name, startedAt: startedAt, updatedAt: now.timeIntervalSince1970), to: folder.appendingPathComponent(instanceID + ".json"))
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
        // A connected extension that fails to apply rules is Ortus's problem, not a reason to close the browser.
        protectedBrowsers = Set(clients.filter { $0.incognito != false }.compactMap(\.bundleID))
        incognitoOff = BrowserCompanion.incognitoOff(clients)
        let guarded = Set(UserDefaults.standard.stringArray(forKey: "guardedBrowsers") ?? [])
        let seen = guarded.union(ready.compactMap(\.bundleID))
        if seen != guarded { UserDefaults.standard.set(seen.sorted(), forKey: "guardedBrowsers") }
        connectedBrowsers = Array(Set(ready.map(\.browser))).sorted()
        connectionSummary = connectedBrowsers.map { name in
            let count = ready.filter { $0.browser == name }.count
            return "\(name) · \(count) profile\(count == 1 ? "" : "s")"
        }.joined(separator: ", ")
        enforcementError = clients.contains { $0.state == "error" } ? "A browser could not apply your rules. Open its Ortus extension and reconnect." : nil
    }

    /// During a website session, a browser that has used Ortus before must keep the extension on
    /// (and allowed in incognito). Otherwise it gets a warning tab, a countdown, then a normal quit.
    func guardBrowsers(active: Bool, now: Date = Date()) {
        let guarded = Set(UserDefaults.standard.stringArray(forKey: "guardedBrowsers") ?? [])
        let browsers = !active ? [] : NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier, !app.isTerminated else { return false }
            return guarded.contains(id) && !protectedBrowsers.contains(id)
        }
        let steps = browserGuard.update(unprotected: Set(browsers.map(\.processIdentifier)), now: now)
        var next: ClosingBrowser?
        for app in browsers {
            let name = app.localizedName ?? "Your browser"
            guard let closesAt = browserGuard.closesAt(app.processIdentifier) else { continue }
            switch steps[app.processIdentifier] {
            case .warn:
                // `defaults write <bundle id> webBase http://localhost:8765` tests the page before it's deployed.
                let site = UserDefaults.standard.string(forKey: "webBase") ?? "https://ortusmode.com"
                guard var page = URLComponents(string: site + "/extension-off") else { break }
                page.queryItems = [URLQueryItem(name: "browser", value: name), URLQueryItem(name: "closes", value: String(Int(closesAt.timeIntervalSince1970)))]
                // The page then says exactly what's wrong, and its button asks Ortus to open the setting.
                if let id = app.bundleIdentifier, let extensionID = incognitoOff[id], let scheme = AppDelegate.urlScheme {
                    page.queryItems? += [URLQueryItem(name: "reason", value: "incognito"), URLQueryItem(name: "app", value: id),
                                         URLQueryItem(name: "scheme", value: scheme), URLQueryItem(name: "ext", value: extensionID)]
                }
                if let url = page.url, let browser = app.bundleURL {
                    NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: .init(), completionHandler: nil)
                }
            case .close: app.terminate()
            case nil: break
            }
            if next.map({ closesAt < $0.closesAt }) ?? true {
                let id = app.bundleIdentifier ?? ""
                next = ClosingBrowser(name: name, closesAt: closesAt, bundleID: id, incognitoOff: incognitoOff[id] != nil)
            }
        }
        if closingBrowser != next { closingBrowser = next }
    }

    /// Why the Load unpacked folder couldn't be updated. Only a folder install needs it, so it shows on Show folder.
    private var folderError: String?

    /// User-level registration only. Re-running updates the executable path after moving a build.
    func registerCompanion() {
        folderError = nil
        do {
            guard let extensionDirectory, let bundledExtension = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true),
                  let bundle = Bundle.main.executableURL?.deletingLastPathComponent(),
                  let identity = readBundledIdentity(), let id = identity["id"] else {
                throw NSError(domain: "Ortus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Rebuild Ortus with the bundled browser companion."])
            }
            let bridge = bundle.appendingPathComponent("OrtusBrowserBridge")
            guard FileManager.default.isExecutableFile(atPath: bridge.path) else {
                throw NSError(domain: "Ortus", code: 2, userInfo: [NSLocalizedDescriptionKey: "The browser connection helper is missing."])
            }
            // The unpacked build (manifest key) and the Chrome Web Store build have different ids.
            let result = CompanionRegistration.register(hostName: hostName, bridge: bridge, unpackedID: id, storeID: identity["storeID"],
                                                        bundledExtension: bundledExtension, unpackedFolder: extensionDirectory)
            folderError = result.folder.map { Self.folderMessage($0.localizedDescription, folder: extensionDirectory.lastPathComponent, preview: preview) }
            if let error = result.manifests { throw error }
            setupError = nil
        } catch { setupError = "Browser setup: \(error.localizedDescription)" }
    }

    /// A preview connects only to its own folder, so only the release can point at the store instead.
    static func folderMessage(_ reason: String, folder: String, preview: Bool) -> String {
        "Load unpacked can't use the “\(folder)” folder: \(reason)" + (preview ? "" : " Add Ortus from the Chrome Web Store instead.")
    }

    #if DEBUG
    /// The snapshot harness shows the message a folder owned by another macOS user gives.
    func pinFolderErrorForSnapshot() {
        guard let folder = extensionDirectory else { return }
        let reason = CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: folder.appendingPathComponent("background.js").path]).localizedDescription
        setupError = Self.folderMessage(reason, folder: folder.lastPathComponent, preview: preview)
    }
    #endif

    /// The published listing. Uses the bundled store id when the app has one, so the
    /// button and the native host allow the same extension.
    var storeListing: URL {
        let id = readBundledIdentity()?["storeID"] ?? ""
        return BrowserCompanion.storeListingURL(extensionID: id.isEmpty ? BrowserCompanion.storeExtensionID : id)
    }

    private func readBundledIdentity() -> [String: String]? {
        guard let url = Bundle.main.resourceURL?
                .appendingPathComponent("BrowserExtension", isDirectory: true)
                .appendingPathComponent("identity.json"),
              let data = try? Data(contentsOf: url),
              let identity = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              identity["id"] != nil else { return nil }
        return identity
    }

    /// Opens the Chrome Web Store listing in a detected browser, or the default browser
    /// when none of the supported ones is installed.
    func openStoreListing(browserID: String?) {
        let listing = storeListing
        setupError = nil
        guard let browserID,
              let choice = availableBrowsers.first(where: { $0.id == browserID }),
              let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.id) else {
            if availableBrowsers.isEmpty {
                setupError = "Choose an installed supported browser: Arc, Dia, Chrome, Edge or Brave. Safari and Firefox are not supported."
            }
            NSWorkspace.shared.open(listing)
            return
        }
        let name = choice.name
        // NSWorkspace calls this on a background queue. Without @Sendable, the Xcode 16 SDK
        // makes the closure MainActor-isolated and Swift 6 traps on entry (v1.1.0 crash).
        NSWorkspace.shared.open([listing], withApplicationAt: browser, configuration: .init()) { @Sendable _, error in
            if error != nil {
                Task { @MainActor in self.setupError = "Open the Chrome Web Store in \(name) and add Ortus." }
            }
        }
    }

    /// Opens the Ortus extension's Details page, where Allow in Incognito is, in that browser.
    /// Reached from the warning page's button (through the URL scheme) and the panel.
    func openIncognitoSetting(browserID: String) {
        guard let choice = availableBrowsers.first(where: { $0.id == browserID }),
              let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.id),
              let target = URL(string: "\(choice.page)/?id=\(incognitoOff[browserID] ?? BrowserCompanion.storeExtensionID)") else { return }
        NSWorkspace.shared.open([target], withApplicationAt: browser, configuration: .init(), completionHandler: nil)
    }

    func openExtensionsPage(browserID: String) {
        setupError = nil
        guard let choice = availableBrowsers.first(where: { $0.id == browserID }),
              let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.id),
              let target = URL(string: choice.page) else {
            setupError = "Choose an installed supported browser: Arc, Dia, Chrome, Edge or Brave. Safari and Firefox are not supported."
            return
        }
        let name = choice.name
        // NSWorkspace calls this on a background queue. Without @Sendable, the Xcode 16 SDK
        // makes the closure MainActor-isolated and Swift 6 traps on entry (v1.1.0 crash).
        NSWorkspace.shared.open([target], withApplicationAt: browser, configuration: .init()) { @Sendable _, error in
            if error != nil {
                Task { @MainActor in self.setupError = "Paste \(target.absoluteString) in \(name), then choose Load unpacked." }
            }
        }
    }

    func revealCompanion() {
        registerCompanion()
        guard setupError == nil else { return }
        if let folderError { setupError = folderError }
        else if let extensionDirectory { NSWorkspace.shared.activateFileViewerSelecting([extensionDirectory]) }
    }
}
