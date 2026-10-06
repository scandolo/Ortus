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
    public init(id: String, browser: String, updatedAt: Double, state: String = "connecting") {
        self.id = id; self.browser = browser; self.updatedAt = updatedAt; self.state = state
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
