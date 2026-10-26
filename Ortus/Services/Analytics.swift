import Foundation
import PostHog

/// Thin wrapper around PostHog. The rest of the app fires plain semantic events
/// (`Analytics.capture("focus_started")`) and all analytics config lives here.
///
/// Privacy: we never capture message contents, Slack tokens, or credentials —
/// only coarse product events. Nothing is sent until the user opts in (on the
/// welcome page or in Settings); turning it off stops sending immediately.
@MainActor
enum Analytics {
    // Public client-side key — safe to ship in the binary (PostHog iOS SDK guidance).
    private static let projectApiKey = "phc_CWsCtXVbzwvSr3bTNt873npFFj8Mhhud6kS8gVNq6XAm"
    private static let host = "https://us.i.posthog.com"

    private static var isEnabled: Bool {
        !projectApiKey.hasPrefix("phc_REPLACE")
    }

    /// UserDefaults key for the user's choice. Off until they opt in.
    static let consentKey = "shareAnonymousUsage"
    private static var hasConsent: Bool { UserDefaults.standard.bool(forKey: consentKey) }
    private static var started = false

    /// Call at launch and whenever the user opts in. Does nothing without consent.
    static func start() {
        guard isEnabled, hasConsent, !started else { return }
        let config = PostHogConfig(apiKey: projectApiKey, host: host)
        PostHogSDK.shared.setup(config)
        started = true
    }

    static func setConsent(_ consent: Bool) {
        UserDefaults.standard.set(consent, forKey: consentKey)
        if consent { start(); if started { PostHogSDK.shared.optIn() } }
        else if started { PostHogSDK.shared.optOut() }
    }

    static func capture(_ event: String, _ properties: [String: Any]? = nil) {
        guard isEnabled, started, hasConsent else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
