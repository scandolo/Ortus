import Foundation

struct SlackAppConfiguration {
    static let shared = SlackAppConfiguration(bundle: .main)

    static let userScopes = [
        "search:read",
        "channels:history",
        "groups:history",
        "im:history",
        "mpim:history",
        "users:read",
        "channels:read",
        "groups:read",
    ]

    let bundledClientID: String
    let bundledRedirectURL: String
    let callbackScheme: String

    init(bundle: Bundle) {
        bundledClientID = Self.stringValue(for: "OrtusSlackClientID", in: bundle)
        bundledRedirectURL = Self.stringValue(for: "OrtusSlackRedirectURL", in: bundle)
        callbackScheme = Self.stringValue(for: "OrtusSlackCallbackScheme", in: bundle)
    }

    var hasBundledInstallFlow: Bool {
        !bundledClientID.isEmpty && !bundledRedirectURL.isEmpty && !callbackScheme.isEmpty
    }

    var userScopesString: String {
        Self.userScopes.joined(separator: ",")
    }

    private static func stringValue(for key: String, in bundle: Bundle) -> String {
        (bundle.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
