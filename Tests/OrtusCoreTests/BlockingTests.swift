import Foundation
import OrtusCore

struct BlockingTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func normalizesURLsAndRejectsUnsafeInput() throws {
        expect(try WebsiteDomain.normalize(" HTTPS://WWW.LinkedIn.COM/feed?x=1 ") == "www.linkedin.com")
        expect(try WebsiteDomain.normalize("mail.google.com.") == "mail.google.com")
        expect(try WebsiteDomain.normalize("https://bücher.de") == "xn--bcher-kva.de")
        for invalid in ["", "localhost", "*.google.com", "https://user:pass@example.com", "javascript:alert(1)", "127.0.0.1", "bad..com", "bad.com\nnext.com", "https://-bad.com", "https://bad.com\\@good.com"] {
            expectThrows { try WebsiteDomain.normalize(invalid) }
        }
        expect(WebsiteDomain.matches(host: "www.linkedin.com", domain: "linkedin.com"))
        expect(!WebsiteDomain.matches(host: "notlinkedin.com", domain: "linkedin.com"))
        expect(!WebsiteDomain.matches(host: "linkedin.com.evil.example", domain: "linkedin.com"))
    }

    func newAndMigratedDefaults() throws {
        let key = "Ortus.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        let firstLoad = ScheduleStore.load(defaults: defaults)
        expect(firstLoad.first?.blocked == .standard)
        expect(firstLoad.first?.isEnabled == false)
        expect(ScheduleStore.load(defaults: defaults) == firstLoad) // stable IDs across restarts
        ScheduleStore.save([], defaults: defaults)
        expect(ScheduleStore.load(defaults: defaults).isEmpty) // intentionally deleting all schedules persists
        let legacy = """
        {"id":"6CDAA593-E909-4F76-B9A1-149D3718B5D5","name":"Focus Time","days":[2],"startHour":9,"startMinute":0,"endHour":12,"endMinute":0,"isEnabled":true}
        """
        let schedule = try JSONDecoder().decode(FocusSchedule.self, from: Data(legacy.utf8))
        expect(schedule.blocked == .standard)
        let custom = try JSONDecoder().decode(FocusSchedule.self, from: Data(legacy.replacingOccurrences(of: "Focus Time", with: "Writing").utf8))
        expect(custom.blocked == .slackOnly)
        expect(try JSONDecoder().decode(FocusSchedule.self, from: JSONEncoder().encode(schedule)) == schedule)
    }

    func overnightWindowUsesStartDayAndExclusiveEnd() {
        let schedule = FocusSchedule(days: [.monday], startHour: 22, endHour: 2)
        expect(schedule.activeWindow(at: date("2026-10-06T01:00:00Z"), calendar: calendar)?.end == date("2026-10-06T02:00:00Z"))
        expect(schedule.activeWindow(at: date("2026-10-06T02:00:00Z"), calendar: calendar) == nil)
        expect(schedule.activeWindow(at: date("2026-10-05T01:00:00Z"), calendar: calendar) == nil)
        expect(FocusSchedule(startHour: 9, endHour: 9).activeWindow(at: date("2026-10-05T09:00:00Z"), calendar: calendar) == nil)
    }

    func recoversDefaultScheduleIdentityFromEarlyPreview() throws {
        let key = "Ortus.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        let now = date("2026-10-05T10:00:00Z")
        let first = FocusSession(scheduleID: UUID(), name: "Focus Time", start: now, end: now.addingTimeInterval(7200), blocked: .standard)
        let duplicate = FocusSession(scheduleID: UUID(), name: "Focus Time", start: now.addingTimeInterval(60), end: first.end, blocked: .standard)
        let manual = FocusSession(name: "Manual Focus", start: now, end: first.end, blocked: .standard)
        let old = FocusTimeline(sessions: [first, duplicate, manual])
        defaults.set(try JSONEncoder().encode(old), forKey: "activeFocusTimeline")
        let schedules = ScheduleStore.load(defaults: defaults)
        expect(schedules.first?.id == first.scheduleID)
        let repaired = try JSONDecoder().decode(FocusTimeline.self, from: defaults.data(forKey: "activeFocusTimeline")!)
        expect(repaired.sessions == [first, manual]) // preserve deadline and independent manual session
        expect(ScheduleStore.load(defaults: defaults) == schedules)
    }

    func overlappingSchedulesExpireIndependently() throws {
        let a = FocusSchedule(name: "Mail break", days: [.monday], startHour: 9, endHour: 11, blocked: .init(websites: ["mail.google.com"]))
        let b = FocusSchedule(name: "Writing", days: [.monday], startHour: 10, endHour: 12, blocked: .init(websites: ["linkedin.com"], applications: [.slack]))
        var timeline = FocusTimeline()
        timeline.reconcile(at: date("2026-10-05T09:30:00Z"), schedules: [a,b], calendar: calendar)
        expect(timeline.selection.websites == ["mail.google.com"])
        timeline.reconcile(at: date("2026-10-05T10:30:00Z"), schedules: [a,b], calendar: calendar)
        expect(timeline.selection.websites == ["linkedin.com", "mail.google.com"])
        expect(timeline.selection.blocksSlack)
        timeline.reconcile(at: date("2026-10-05T11:00:00Z"), schedules: [a,b], calendar: calendar)
        expect(timeline.selection.websites == ["linkedin.com"])
        expect(timeline.selection.blocksSlack)
        timeline.reconcile(at: date("2026-10-05T12:00:00Z"), schedules: [a,b], calendar: calendar)
        expect(timeline.sessions.isEmpty)
    }

    func manualSessionCombinesWithScheduleAndGraceOnlyCancelsManual() {
        let now = date("2026-10-05T10:00:00Z")
        let schedule = FocusSchedule(days: [.monday], blocked: .init(websites: ["linkedin.com"]))
        var timeline = FocusTimeline()
        timeline.beginManual(at: now, duration: 3600, blocked: .slackOnly)
        timeline.reconcile(at: now.addingTimeInterval(5), schedules: [schedule], calendar: calendar)
        expect(timeline.selection.blocksSlack)
        expect(timeline.selection.websites == ["linkedin.com"])
        timeline.revertManual(at: now.addingTimeInterval(10))
        expect(!timeline.selection.blocksSlack)
        expect(timeline.sessions.count == 1)
    }

    func skippingGraceLocksManualSessionWithoutChangingFocus() throws {
        let now = date("2026-10-05T10:00:00Z")
        let scheduled = FocusSession(scheduleID: UUID(), name: "Scheduled", start: now,
                                     end: now.addingTimeInterval(7200), blocked: .init(websites: ["linkedin.com"]))
        var timeline = FocusTimeline(sessions: [scheduled])
        timeline.beginManual(at: now, duration: 3600, blocked: .slackOnly)
        var expected = timeline.sessions[1]
        expect(expected.graceEnd == now.addingTimeInterval(30))
        expected.graceEnd = nil
        timeline.skipGracePeriod()
        expect(timeline.sessions == [scheduled, expected])
        timeline.revertManual(at: now.addingTimeInterval(5))
        expect(timeline.sessions == [scheduled, expected])
        timeline = try JSONDecoder().decode(FocusTimeline.self, from: JSONEncoder().encode(timeline))
        timeline.revertManual(at: now.addingTimeInterval(10))
        expect(timeline.sessions == [scheduled, expected])
    }

    func restartAndEmergencySuppressionPreserveFocusState() throws {
        let now = date("2026-10-05T10:00:00Z")
        let schedule = FocusSchedule(days: [.monday])
        var timeline = FocusTimeline()
        timeline.reconcile(at: now, schedules: [schedule], calendar: calendar)
        var edited = schedule
        edited.blocked = .slackOnly
        timeline.reconcile(at: now, schedules: [edited], calendar: calendar)
        expect(timeline.selection == .standard) // active snapshot cannot be weakened
        timeline = try JSONDecoder().decode(FocusTimeline.self, from: JSONEncoder().encode(timeline))
        expect(timeline.sessions.count == 1)
        timeline.endEarly(at: now)
        timeline.reconcile(at: now.addingTimeInterval(60), schedules: [schedule], calendar: calendar)
        expect(timeline.sessions.isEmpty)
        expect(timeline.suppressedUntil == date("2026-10-05T12:00:00Z"))
        timeline.reconcile(at: date("2026-10-12T10:00:00Z"), schedules: [schedule], calendar: calendar)
        expect(timeline.sessions.count == 1)
    }

    func browserRulesUseLongestMatchingSessionAndCrashLease() {
        let now = date("2026-10-05T10:00:00Z")
        let sessions = [60.0,120.0].map { duration in
            FocusSession(name: "Focus", start: now, end: now.addingTimeInterval(duration), blocked: .init(websites: ["linkedin.com"]))
        }
        let policy = BrowserPolicy(sessions: sessions, now: now)
        expect(policy.rules.count == 1)
        expect(policy.rules.first?.expiresAt == now.addingTimeInterval(120).timeIntervalSince1970)
        expect(policy.effective(at: now.addingTimeInterval(19)).rules.count == 1)
        expect(policy.effective(at: now.addingTimeInterval(20)).rules.isEmpty)
        var invalid = policy
        invalid.schemaVersion = 2
        expect(invalid.effective(at: now).rules.isEmpty)
        invalid = policy; invalid.heartbeatExpiresAt += 86400
        expect(invalid.effective(at: now).rules.isEmpty)
    }

    func selectionDeduplicatesAndKeepsEscapeToolsAvailable() {
        let selection = BlockSelection.union([.standard, .standard, .init(applications: [.init(bundleID: "com.ortus.preview", name: "Ortus Preview"), .init(bundleID: "com.apple.finder", name: "Finder")])])
        expect(selection == .standard)
        expect(selection.summary.contains("Gmail"))
        expect(selection.applications.count == 1)
    }


    func onlyOneAppCanOwnFocusAtATime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OrtusLockTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = FocusEngineLock(directory: directory)
        let second = FocusEngineLock(directory: directory)
        expect(first.acquire())
        expect(first.acquire()) // same owner is idempotent
        expect(!second.acquire())
        first.release()
        expect(second.acquire())
        second.release()
        expect(first.acquire())
        first.release()
    }

    func presetEditingPreservesUnrelatedTargets() {
        var selection = BlockSelection(websites: ["example.com"], applications: [.slack])
        let gmail = BlockingPreset.all.first { $0.id == "gmail" }!
        selection.set(gmail, enabled: true)
        expect(selection.websites == ["example.com", "gmail.com", "mail.google.com"])
        selection.set(gmail, enabled: false)
        expect(selection.websites == ["example.com"])
        expect(selection.blocksSlack)
    }

    func partialPresetsDescribeActualCoverage() {
        let slack = BlockingPreset.all.first { $0.id == "slack" }!
        let website = BlockSelection(websites: ["slack.com"])
        let app = BlockSelection.slackOnly
        expect(website.contains(slack) && !website.fullyContains(slack))
        expect(app.contains(slack) && !app.fullyContains(slack))
        expect(website.summary == "Slack website" && app.summary == "Slack app")
        expect(website.detail(for: slack) == "Website only · desktop app stays open")
        expect(app.detail(for: slack) == "Desktop app only · website stays open")
        expect(BlockSelection.standard.fullyContains(slack))
        expect(BlockSelection.standard.summary == "Gmail · LinkedIn · Slack")
        expect(BlockSelection(websites: ["mail.google.com"]).summary == "mail.google.com")
    }

    func builtInModesAreNamedAndRecognised() {
        expect(FocusMode.matching(FocusMode.social.blocked, in: FocusMode.builtIn)?.id == "social")
        expect(FocusMode.matching(.standard, in: FocusMode.builtIn) == nil)
        expect(FocusMode.social.blocked.summary == "Facebook · Instagram · LinkedIn · Reddit · TikTok · X")
        expect(FocusMode.messages.blocked.summary == "Gmail · Slack · WhatsApp")
        expect(BlockingPreset.all.allSatisfy { FocusMode.everything.blocked.fullyContains($0) })
        expect(FocusMode.builtIn.allSatisfy(\.isBuiltIn) && !FocusMode(name: "Mine", blocked: .slackOnly).isBuiltIn)
    }

    func nativeFramingIsLittleEndianAndBounded() {
        let data = Data("{\"hello\":true}".utf8)
        let frame = NativeMessage.frame(data)
        expect(NativeMessage.length(Data(frame.prefix(4))) == data.count)
        expect(Data(frame.dropFirst(4)) == data)
        expect(NativeMessage.length(Data([0,0,0,0])) == nil)
        expect(NativeMessage.length(Data([255,255,255,255])) == nil)
        expect(NativeMessage.length(Data([2,0])) == nil)
    }
}

// A plain Swift runner works with Apple's Command Line Tools as well as Xcode.
// The CLT-only toolchain doesn't ship XCTest or swift-testing.
private func expect(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition, "Expectation failed", file: file, line: line)
}
private func expectThrows(_ body: () throws -> String, file: StaticString = #file, line: UInt = #line) {
    do { _ = try body(); preconditionFailure("Expected invalid input to throw", file: file, line: line) } catch {}
}
@main
struct CoreChecks {
    static func main() throws {
        let checks = BlockingTests()
        try checks.normalizesURLsAndRejectsUnsafeInput()
        try checks.newAndMigratedDefaults()
        checks.overnightWindowUsesStartDayAndExclusiveEnd()
        try checks.recoversDefaultScheduleIdentityFromEarlyPreview()
        try checks.overlappingSchedulesExpireIndependently()
        checks.manualSessionCombinesWithScheduleAndGraceOnlyCancelsManual()
        try checks.skippingGraceLocksManualSessionWithoutChangingFocus()
        try checks.restartAndEmergencySuppressionPreserveFocusState()
        checks.browserRulesUseLongestMatchingSessionAndCrashLease()
        checks.selectionDeduplicatesAndKeepsEscapeToolsAvailable()
        checks.nativeFramingIsLittleEndianAndBounded()
        try checks.onlyOneAppCanOwnFocusAtATime()
        checks.presetEditingPreservesUnrelatedTargets()
        checks.partialPresetsDescribeActualCoverage()
        checks.builtInModesAreNamedAndRecognised()
        print("PASS: 15 Ortus core checks (validation, migration, stable default identity, schedules, overlap, grace skip, recovery, browser lease, framing, modes)")
    }
}
