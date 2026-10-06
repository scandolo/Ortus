import Foundation

public enum WebsiteDomain {
    public enum Invalid: LocalizedError {
        case domain
        public var errorDescription: String? { "Enter a website such as linkedin.com or a full https:// URL." }
    }

    /// Store host names only. Never interpret input as a regex, shell command, or script.
    public static func normalize(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("*"), !trimmed.contains("\\"),
              !trimmed.contains(where: { $0.isWhitespace }) else { throw Invalid.domain }
        let value = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, var host = url.host(percentEncoded: false)?.lowercased() else { throw Invalid.domain }
        if host.hasSuffix(".") { host.removeLast() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }), !labels.allSatisfy({ Int($0) != nil }) else { throw Invalid.domain }
        return host
    }

    public static func matches(host: String, domain: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || host.hasSuffix("." + domain)
    }
}

public struct BlockedApplication: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
    public static let slack = Self(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    public static func isBlockable(_ id: String) -> Bool {
        !id.hasPrefix("com.ortus.") && !["com.apple.finder", "com.apple.systempreferences", "com.apple.loginwindow"].contains(id)
    }
}

public struct BlockSelection: Codable, Equatable, Sendable {
    public var websites: [String]
    public var applications: [BlockedApplication]
    public init(websites: [String] = [], applications: [BlockedApplication] = []) {
        self.websites = Array(Set(websites.compactMap { try? WebsiteDomain.normalize($0) })).sorted()
        var seen = Set<String>()
        self.applications = applications.filter { BlockedApplication.isBlockable($0.bundleID) && seen.insert($0.bundleID).inserted }
            .sorted { $0.bundleID < $1.bundleID }
    }
    public static let standard = Self(websites: ["mail.google.com", "gmail.com", "linkedin.com", "slack.com"], applications: [.slack])
    public static let slackOnly = Self(applications: [.slack])
    public var websiteCount: Int {
        Set(websites.map { ["gmail.com", "mail.google.com"].contains($0) ? "Gmail" : $0 }).count
    }
    public var isEmpty: Bool { websites.isEmpty && applications.isEmpty }
    public var blocksSlack: Bool { applications.contains { $0.bundleID == BlockedApplication.slack.bundleID } }
    public func contains(_ preset: BlockingPreset) -> Bool {
        preset.selection.websites.contains(where: websites.contains) || preset.selection.applications.contains { app in applications.contains { $0.id == app.id } }
    }
    public func fullyContains(_ preset: BlockingPreset) -> Bool {
        preset.selection.websites.allSatisfy(websites.contains) && preset.selection.applications.allSatisfy { app in applications.contains { $0.id == app.id } }
    }
    public func detail(for preset: BlockingPreset) -> String {
        guard contains(preset), !fullyContains(preset) else { return preset.detail }
        if preset.id == "slack" {
            return blocksSlack ? "Desktop app only · website stays open" : "Website only · desktop app stays open"
        }
        return preset.selection.websites.filter(websites.contains).joined(separator: ", ") + " only"
    }
    public mutating func set(_ preset: BlockingPreset, enabled: Bool) {
        if enabled { self = .union([self, preset.selection]) }
        else {
            websites.removeAll { preset.selection.websites.contains($0) }
            applications.removeAll { app in preset.selection.applications.contains { $0.id == app.id } }
        }
    }
    public static func union(_ selections: [Self]) -> Self {
        Self(websites: selections.flatMap(\.websites), applications: selections.flatMap(\.applications))
    }
    public var summary: String {
        var names: [String] = []
        for domain in websites {
            let name = switch domain {
            case "gmail.com", "mail.google.com": websites.contains("gmail.com") && websites.contains("mail.google.com") ? "Gmail" : domain
            case "linkedin.com": "LinkedIn"
            case "slack.com": blocksSlack ? "Slack" : "Slack website"
            default: domain
            }
            if !names.contains(name) { names.append(name) }
        }
        for app in applications {
            let name = app.id == BlockedApplication.slack.id && !websites.contains("slack.com") ? "Slack app" : app.name
            if !names.contains(name) { names.append(name) }
        }
        return names.isEmpty ? "Nothing selected" : names.joined(separator: " · ")
    }
}

public struct BlockingPreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let selection: BlockSelection
    public static let all: [Self] = [
        .init(id: "gmail", title: "Gmail", detail: "Mail websites · other Google services stay open", symbol: "envelope", selection: .init(websites: ["mail.google.com", "gmail.com"])),
        .init(id: "linkedin", title: "LinkedIn", detail: "Website and its subdomains", symbol: "person.2", selection: .init(websites: ["linkedin.com"])),
        .init(id: "slack", title: "Slack", detail: "Desktop app and website", symbol: "bubble.left.and.bubble.right", selection: .init(websites: ["slack.com"], applications: [.slack]))
    ]
}
