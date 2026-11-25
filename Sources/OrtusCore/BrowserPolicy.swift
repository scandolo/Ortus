import Foundation

public struct BrowserRule: Codable, Equatable, Sendable {
    public var domain: String
    public var expiresAt: Double
    public init(domain: String, expiresAt: Double) { self.domain = domain; self.expiresAt = expiresAt }
}

public struct BrowserPolicy: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var generatedAt: Double
    public var heartbeatExpiresAt: Double
    public var rules: [BrowserRule]
    public var appName: String?
    public var browserName: String?
    /// Copy style for the blocked page: nil for standard, "genz" for the easter egg.
    public var tone: String?
    public init(sessions: [FocusSession], now: Date, appName: String? = nil, tone: String? = nil) {
        self.appName = appName; self.tone = tone
        generatedAt = now.timeIntervalSince1970
        heartbeatExpiresAt = generatedAt + 20
        var expirations: [String: Double] = [:]
        for session in sessions where session.end > now {
            for input in session.blocked.websites {
                guard let domain = try? WebsiteDomain.normalize(input) else { continue }
                expirations[domain] = max(expirations[domain] ?? 0, session.end.timeIntervalSince1970)
            }
        }
        rules = expirations.map { BrowserRule(domain: $0.key, expiresAt: $0.value) }.sorted { $0.domain < $1.domain }
    }
    public func effective(at now: Date) -> Self {
        var result = self
        let timestamp = now.timeIntervalSince1970
        guard schemaVersion == 1, generatedAt <= timestamp + 5, heartbeatExpiresAt > timestamp,
              heartbeatExpiresAt <= generatedAt + 30 else { result.rules = []; return result }
        result.rules = rules.filter { $0.expiresAt > timestamp && (try? WebsiteDomain.normalize($0.domain)) == $0.domain }
        return result
    }
}

public struct BrowserClient: Codable, Sendable {
    public var id: String
    public var browser: String
    public var updatedAt: Double
    public var state: String?
    /// The browser app that launched the bridge, and whether the extension may run in incognito.
    public var bundleID: String?
    public var incognito: Bool?
    /// The extension that connected, so Ortus can open its Details page.
    public var extensionID: String?
    public init(id: String, browser: String, updatedAt: Double, state: String = "connecting", bundleID: String? = nil, incognito: Bool? = nil, extensionID: String? = nil) {
        self.id = id; self.browser = browser; self.updatedAt = updatedAt; self.state = state
        self.bundleID = bundleID; self.incognito = incognito; self.extensionID = extensionID
    }
}

/// During a website session, a browser that has used Ortus must keep the extension on.
/// Without it, the browser gets a warning, then a countdown, then it is closed.
public struct BrowserGuard: Sendable {
    /// Quiet time first: covers a browser launching and the helper restarting after an update.
    public static let warnAfter: TimeInterval = 10
    public static let countdown: TimeInterval = 60
    public enum Step: Equatable, Sendable { case warn, close }
    private var since: [Int32: Date] = [:]
    private var warned: Set<Int32> = []
    public init() {}

    /// `unprotected` holds the browser processes running without a working extension.
    /// A process that recovers or quits is forgotten, so a reopened browser starts over.
    public mutating func update(unprotected: Set<Int32>, now: Date) -> [Int32: Step] {
        since = since.filter { unprotected.contains($0.key) }
        warned.formIntersection(unprotected)
        var steps: [Int32: Step] = [:]
        for pid in unprotected {
            let start = since[pid] ?? now
            since[pid] = start
            if now >= start + Self.warnAfter + Self.countdown { steps[pid] = .close }
            else if now >= start + Self.warnAfter, warned.insert(pid).inserted { steps[pid] = .warn }
        }
        return steps
    }

    /// When a warned browser will close.
    public func closesAt(_ pid: Int32) -> Date? {
        guard warned.contains(pid), let start = since[pid] else { return nil }
        return start + Self.warnAfter + Self.countdown
    }
}

public enum BrowserPaths {
    public static func directory(preview: Bool) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/\(preview ? "Ortus Preview" : "Ortus")/Browser", isDirectory: true)
    }
    public static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// How the Mac app recognizes the companion extension.
public enum BrowserCompanion {
    /// Chrome Web Store id for Ortus · Website blocking.
    /// The unpacked build's id is different; it comes from the manifest key.
    /// Keep this equal to `storeID` in BrowserExtension/identity.json.
    public static let storeExtensionID = "lheanmgemlbnpeonkdbbinmankaineao"

    public static func storeListingURL(extensionID: String = storeExtensionID) -> URL {
        URL(string: "https://chromewebstore.google.com/detail/\(extensionID)")
            ?? URL(string: "https://chromewebstore.google.com/detail/\(storeExtensionID)")!
    }

    /// The id in the origin Chromium passes the native host: `chrome-extension://<32 letters a-p>/`.
    public static func extensionID(fromOrigin origin: String) -> String? {
        guard origin.hasPrefix("chrome-extension://") else { return nil }
        let id = origin.dropFirst("chrome-extension://".count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return id.count == 32 && id.allSatisfy({ ("a"..."p").contains($0) }) ? id : nil
    }

    /// Browsers whose extension is connected but not allowed in incognito, with no profile
    /// that is, mapped to that extension's id. Ortus closes these during focus, and the fix
    /// is one switch on the extension's Details page.
    public static func incognitoOff(_ clients: [BrowserClient]) -> [String: String] {
        let protected = Set(clients.filter { $0.incognito != false }.compactMap(\.bundleID))
        var result: [String: String] = [:]
        for client in clients where client.incognito == false {
            guard let bundleID = client.bundleID, !protected.contains(bundleID), result[bundleID] == nil else { continue }
            result[bundleID] = client.extensionID ?? storeExtensionID
        }
        return result
    }

    /// Chromium only launches the native host for these origins.
    /// Pass the unpacked id and, when present, the store id. Duplicates and blanks are dropped.
    public static func allowedOrigins(unpackedID: String, storeID: String?) -> [String] {
        var ids = [unpackedID]
        if let storeID, !storeID.isEmpty, storeID != unpackedID { ids.append(storeID) }
        return ids.map { "chrome-extension://\($0)/" }
    }
}

public enum NativeMessage {
    public static let maximumBytes = 65_536
    public static func frame(_ data: Data) -> Data {
        var size = UInt32(data.count).littleEndian
        var result = withUnsafeBytes(of: &size) { Data($0) }
        result.append(data)
        return result
    }
    public static func length(_ header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let value = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
        return value > 0 && value <= maximumBytes ? Int(value) : nil
    }
}
