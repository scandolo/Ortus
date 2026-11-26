import Foundation
import PostHog
import OrtusCore

/// Thin wrapper around PostHog. The rest of the app fires plain semantic events
/// (`Analytics.capture("focus_started")`) and all analytics config lives here.
///
/// Events go to the same PostHog project (EU cloud) as ortusmode.com, so the welcome page can
/// link a person's website visit to their app usage (`linkWebsiteVisitor`).
///
/// Privacy: we never capture message contents, Slack tokens, credentials, or the names of the
/// apps and websites people block, only coarse product events and counts. Nothing is sent
/// until usage sharing is on (left ticked on the welcome page, or turned on in Settings);
/// turning it off stops sending immediately.
@MainActor
enum Analytics {
    // Public client-side key, safe to ship in the binary. Same project as the website.
    private static let projectApiKey = "phc_AJfuPPimgTTkTBAq4piciZ5HpmfViM3jCRE98R7pUEqa"
    private static let host = "https://eu.i.posthog.com"

    private static var isEnabled: Bool {
        !projectApiKey.hasPrefix("phc_REPLACE")
    }

    /// UserDefaults key for the user's choice. Off until they turn it on.
    static let consentKey = "shareAnonymousUsage"
    private static var hasConsent: Bool { UserDefaults.standard.bool(forKey: consentKey) }
    private static var started = false
    /// Whether events are being sent right now. One-time events wait for this, so they aren't
    /// marked as sent while sharing is still off (people often connect the extension first).
    static var isActive: Bool { isEnabled && started && hasConsent }
    private static var activeTimer: Timer?
    private static var lastPanelOpen = Date.distantPast

    /// Call at launch and whenever the user opts in. Does nothing without consent.
    static func start() {
        guard isEnabled, hasConsent, !started else { return }
        let config = PostHogConfig(apiKey: projectApiKey, host: host)
        // Only the events below: no automatic app lifecycle events, and no feature flag calls.
        config.captureApplicationLifecycleEvents = false
        config.preloadFeatureFlags = false
        PostHogSDK.shared.setup(config)
        // Tells previews apart, so PostHog's internal-users filter can leave them out.
        PostHogSDK.shared.register(["app_build": BuildProfile.isPreview ? "preview" : "release"])
        started = true
        reportActiveDay()
        // A menu bar app runs for days: report each day it's running, once.
        activeTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in reportActiveDay() }
        }
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

    /// The welcome page passes the visitor ID from the browser that opened it, when the person
    /// leaves usage sharing on. Using it as this install's ID links their website visit,
    /// download and onboarding to their app usage in PostHog.
    static func linkWebsiteVisitor(_ raw: String?) {
        guard isEnabled, started, hasConsent, let id = UsageAnalytics.websiteVisitorID(raw) else { return }
        let key = "analyticsLinkedVisitor"
        guard UserDefaults.standard.string(forKey: key) != id else { return }
        PostHogSDK.shared.identify(id)
        UserDefaults.standard.set(id, forKey: key)
    }

    /// `extension_connected` once per browser (by bundle ID, like com.google.Chrome) whose
    /// Ortus extension is connected, the first time it's seen with sharing on.
    static func reportConnectedBrowsers(_ browsers: Set<String>) {
        guard isActive, !browsers.isEmpty else { return }
        let key = "analyticsReportedBrowsers"
        let reported = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let new = browsers.subtracting(reported)
        guard !new.isEmpty else { return }
        for browser in new.sorted() { capture("extension_connected", ["browser": browser]) }
        UserDefaults.standard.set(reported.union(new).sorted(), forKey: key)
    }

    /// The Ortus panel opened. At most once every 30 minutes, so it reads as "looked at Ortus".
    static func panelOpened(now: Date = Date()) {
        guard now.timeIntervalSince(lastPanelOpen) >= 30 * 60 else { return }
        lastPanelOpen = now
        capture("panel_opened")
    }

    /// `app_active` once per calendar day that Ortus runs: daily and weekly active installs.
    private static func reportActiveDay(now: Date = Date()) {
        let key = "analyticsLastActiveDay"
        guard started, hasConsent, let day = UsageAnalytics.newActiveDay(lastReported: UserDefaults.standard.string(forKey: key), now: now) else { return }
        UserDefaults.standard.set(day, forKey: key)
        capture("app_active")
    }
}
