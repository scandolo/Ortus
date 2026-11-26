import Foundation
import OrtusCore

struct UsageAnalyticsTests {
    func onlyAUUIDLinksAWebsiteVisitor() {
        expect(UsageAnalytics.websiteVisitorID("01A21827-C1E0-73E8-A05C-D86C030E1FD3") == "01a21827-c1e0-73e8-a05c-d86c030e1fd3")
        for invalid in [nil, "", "someone@example.com", "01a21827", "../../etc", "01a21827-c1e0-73e8-a05c-d86c030e1fd3&x=1"] {
            expect(UsageAnalytics.websiteVisitorID(invalid) == nil)
        }
    }

    func activeDayIsReportedOncePerCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        let morning = ISO8601DateFormatter().date(from: "2026-11-26T07:00:00Z")!
        expect(UsageAnalytics.newActiveDay(lastReported: nil, now: morning, calendar: calendar) == "2026-11-26")
        expect(UsageAnalytics.newActiveDay(lastReported: "2026-11-26", now: morning.addingTimeInterval(10 * 3600), calendar: calendar) == nil)
        // 23:30 UTC is already the next day in Rome.
        expect(UsageAnalytics.newActiveDay(lastReported: "2026-11-26", now: morning.addingTimeInterval(16.5 * 3600), calendar: calendar) == "2026-11-27")
    }

    func focusDescribesKindModeAndSizeWithoutNames() {
        let start = ISO8601DateFormatter().date(from: "2026-11-26T09:00:00Z")!
        let manual = FocusSession(name: "Focus", start: start, end: start.addingTimeInterval(3600), blocked: FocusMode.social.blocked)
        let focus = UsageAnalytics.focus([manual], modes: FocusMode.builtIn)!
        expect(focus.kind == "manual" && focus.mode == "social" && focus.plannedMinutes == 60)
        expect(focus.appsCount == FocusMode.social.blocked.applications.count && focus.sitesCount == FocusMode.social.blocked.websites.count)
        expect(focus.minutes(until: start.addingTimeInterval(25 * 60)) == 25)
        expect(focus.properties.keys.sorted() == ["apps_count", "kind", "mode", "planned_minutes", "sites_count"])

        let custom = BlockSelection(websites: ["example.com"])
        let scheduled = FocusSession(scheduleID: UUID(), name: "Mornings", start: start.addingTimeInterval(1800), end: start.addingTimeInterval(4 * 3600), blocked: custom)
        let both = UsageAnalytics.focus([manual, scheduled], modes: FocusMode.builtIn)!
        expect(both.kind == "both" && both.mode == "custom" && both.plannedMinutes == 240 && both.start == start)
        expect(UsageAnalytics.focus([scheduled], modes: FocusMode.builtIn)!.kind == "scheduled")
        expect(UsageAnalytics.focus([], modes: FocusMode.builtIn) == nil)
    }
}
