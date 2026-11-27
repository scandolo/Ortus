import Foundation

/// The rules behind the app's anonymous usage events, kept here so the checks can run them.
/// The app sends events only with usage sharing on (see `Analytics` in the app target).
public enum UsageAnalytics {
    /// The website visitor ID the welcome page hands over, so one person's website visit and
    /// app usage line up. PostHog's IDs are UUIDs; anything else is ignored.
    public static func websiteVisitorID(_ raw: String?) -> String? {
        guard let raw, let uuid = UUID(uuidString: raw) else { return nil }
        return uuid.uuidString.lowercased()
    }

    /// The day to report as active, or nil when that day was already reported.
    public static func newActiveDay(lastReported: String?, now: Date, calendar: Calendar = .current) -> String? {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return day == lastReported ? nil : day
    }

    /// What a focus period looks like, without naming anything it blocks.
    public struct Focus: Equatable, Sendable {
        public var kind: String          // "manual", "scheduled", or "both" when they overlap
        public var mode: String          // a built-in mode's id, or "custom"
        public var plannedMinutes: Int
        public var appsCount: Int
        public var sitesCount: Int
        public var start: Date

        public var properties: [String: Any] {
            ["kind": kind, "mode": mode, "planned_minutes": plannedMinutes, "apps_count": appsCount, "sites_count": sitesCount]
        }
        public func minutes(until now: Date) -> Int { max(0, Int((now.timeIntervalSince(start) / 60).rounded())) }
    }

    public static func focus(_ sessions: [FocusSession], modes: [FocusMode]) -> Focus? {
        guard let start = sessions.map(\.start).min(), let end = sessions.map(\.end).max() else { return nil }
        let scheduled = sessions.contains { $0.scheduleID != nil }, manual = sessions.contains { $0.scheduleID == nil }
        let selection = BlockSelection.union(sessions.map(\.blocked))
        let mode = FocusMode.matching(selection, in: modes).flatMap { $0.isBuiltIn ? $0.id : nil } ?? "custom"
        return Focus(kind: scheduled && manual ? "both" : scheduled ? "scheduled" : "manual", mode: mode,
                     plannedMinutes: max(0, Int((end.timeIntervalSince(start) / 60).rounded())),
                     appsCount: selection.applications.count, sitesCount: selection.websites.count, start: start)
    }
}
