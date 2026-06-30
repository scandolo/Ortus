import Foundation
import PostHog

/// Thin wrapper around PostHog. The rest of the app fires plain semantic events
/// (`Analytics.capture("focus_started")`) and all analytics config lives here.
///
/// Privacy: we never capture message contents, Slack tokens, or credentials —
/// only coarse product events. Analytics is a NO-OP until a real personal
/// project key is pasted below, so the app builds and runs fine without one.
enum Analytics {
    // Public client-side key — safe to ship in the binary (PostHog iOS SDK guidance).
    private static let projectApiKey = "phc_CWsCtXVbzwvSr3bTNt873npFFj8Mhhud6kS8gVNq6XAm"
    private static let host = "https://us.i.posthog.com"

    private static var isEnabled: Bool {
        !projectApiKey.hasPrefix("phc_REPLACE")
    }

    /// Call once at app launch.
    static func start() {
        guard isEnabled else { return }
        let config = PostHogConfig(apiKey: projectApiKey, host: host)
        PostHogSDK.shared.setup(config)
    }

    static func capture(_ event: String, _ properties: [String: Any]? = nil) {
        guard isEnabled else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
