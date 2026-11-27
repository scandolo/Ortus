import Foundation

/// A Chromium browser Ortus works with: its bundle ID, its name, its folder under
/// Application Support (where it reads native messaging hosts and keeps `Local State`)
/// and its extensions page.
public struct SupportedBrowser: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let folder: String
    public let page: String

    public static let all: [SupportedBrowser] = [
        .init(id: "com.google.Chrome", name: "Chrome", folder: "Google/Chrome", page: "chrome://extensions"),
        .init(id: "company.thebrowser.dia", name: "Dia", folder: "Dia/User Data", page: "dia://extensions"),
        .init(id: "company.thebrowser.Browser", name: "Arc", folder: "Arc/User Data", page: "arc://extensions"),
        .init(id: "ai.perplexity.comet", name: "Comet", folder: "Comet", page: "chrome://extensions"),
        .init(id: "com.microsoft.edgemac", name: "Edge", folder: "Microsoft Edge", page: "edge://extensions"),
        .init(id: "com.brave.Browser", name: "Brave", folder: "BraveSoftware/Brave-Browser", page: "brave://extensions"),
        .init(id: "com.vivaldi.Vivaldi", name: "Vivaldi", folder: "Vivaldi", page: "vivaldi://extensions"),
        .init(id: "com.operasoftware.Opera", name: "Opera", folder: "com.operasoftware.Opera", page: "opera://extensions"),
    ]

    /// "Chrome, Dia, Arc, …, Vivaldi or Opera", for messages.
    public static var names: String {
        let names = all.map(\.name)
        return names.dropLast().joined(separator: ", ") + " or " + names.last!
    }

    /// How recently a browser must have run to count as one the user uses.
    public static let recent: TimeInterval = 30 * 24 * 60 * 60

    /// The installed browsers to offer the extension in: the ones the user actually uses (the
    /// default browser, one running now, or one that ran in the last 30 days), minus those already
    /// connected. Default first, then running, then most recently used. If none counts as used, every
    /// installed one is offered, so a fresh Mac still gets a button.
    public static func suggested(installed: [String], defaultBrowser: String?, running: Set<String>,
                                 lastUsed: [String: Date], connected: Set<String>, now: Date = Date()) -> [String] {
        func used(_ id: String) -> Bool {
            id == defaultBrowser || running.contains(id) || (lastUsed[id].map { now.timeIntervalSince($0) < recent } ?? false)
        }
        let inUse = installed.filter(used)
        let pool = (inUse.isEmpty ? installed : inUse).filter { !connected.contains($0) }
        func rank(_ id: String) -> (Int, Int, Double) {
            (id == defaultBrowser ? 0 : 1, running.contains(id) ? 0 : 1, -(lastUsed[id]?.timeIntervalSince1970 ?? 0))
        }
        return pool.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }
}
