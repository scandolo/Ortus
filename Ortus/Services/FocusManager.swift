import AppKit
import Combine
import SwiftUI
@preconcurrency import UserNotifications
import OrtusCore

@MainActor
final class FocusManager: ObservableObject {
    static weak var current: FocusManager?
    @Published private(set) var isInFocus = false
    @Published private(set) var schedules: [FocusSchedule] = []
    @Published private(set) var focusStartTime: Date?
    @Published private(set) var focusEndTime: Date?
    @Published private(set) var currentSessionName: String?
    @Published private(set) var isEmergencyEnded = false
    @Published private(set) var originalFocusEndTime: Date?
    @Published private(set) var isInGracePeriod = false
    @Published private(set) var gracePeriodEndTime: Date?
    @Published private(set) var activeSelection = BlockSelection()
    @Published private(set) var activeScheduleIDs: Set<UUID> = []
    @Published var manualSelection: BlockSelection = .standard {
        didSet { if let data = try? JSONEncoder().encode(manualSelection) { UserDefaults.standard.set(data, forKey: "manualBlockSelection") } }
    }
    /// Optional user-built modes. Built-in modes live in `FocusMode.builtIn`.
    @Published var customModes: [FocusMode] = [] {
        didSet { if let data = try? JSONEncoder().encode(customModes) { UserDefaults.standard.set(data, forKey: "customFocusModes") } }
    }
    @Published var blockingError: String?
    @Published var completionMessage: String?
    let websites = WebsiteBlockingService()
    private lazy var engine = FocusEngineLock(directory: websites.directory)
    private let apps = ApplicationBlocker()
    private var timeline = FocusTimeline()
    private var timer: Timer?
    private var lastPublish = Date.distantPast
    private var lastSlackEnd: Date?
    private var slackStatusApplied = false

    // Keep the old preference key so existing users retain their choice.
    @AppStorage("relaunchSlackOnEnd") var relaunchSlackOnEnd = false
    @AppStorage("showNotifications") var showNotifications = true
    @AppStorage("lastEmergencyEndTimestamp") var lastEmergencyEndTimestamp: Double = 0
    @AppStorage("developerModeEnabled") var developerModeEnabled = false
    @AppStorage("emergencyScheduleSuppressUntil") var emergencyScheduleSuppressUntil: Double = 0
    @AppStorage("slackStatusEnabled") var slackStatusEnabled = true
    @AppStorage("slackStatusText") var slackStatusText = "Ortus mode"
    @AppStorage("slackStatusEmoji") var slackStatusEmoji = ":no_entry_sign:"
    @AppStorage("slackDndEnabled") var slackDndEnabled = true
    var slackService: SlackService? { didSet { applySlackStatusForFocus() } }

    var canUseEmergencyEnd: Bool {
        guard lastEmergencyEndTimestamp > 0 else { return true }
        return !Calendar.current.isDate(Date(timeIntervalSince1970: lastEmergencyEndTimestamp), equalTo: Date(), toGranularity: .weekOfYear)
    }
    var nextEmergencyAvailableDate: Date? {
        guard !canUseEmergencyEnd, let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else { return nil }
        return Calendar.current.date(byAdding: .weekOfYear, value: 1, to: start)
    }

    init() {
        Self.current = self
        schedules = ScheduleStore.load()
        if let data = UserDefaults.standard.data(forKey: "manualBlockSelection"), let selection = try? JSONDecoder().decode(BlockSelection.self, from: data) { manualSelection = selection }
        if let data = UserDefaults.standard.data(forKey: "activeFocusTimeline"), let saved = try? JSONDecoder().decode(FocusTimeline.self, from: data) { timeline = saved }
        if emergencyScheduleSuppressUntil > Date().timeIntervalSince1970 {
            timeline.suppressedUntil = Date(timeIntervalSince1970: emergencyScheduleSuppressUntil)
        }
        if let data = UserDefaults.standard.data(forKey: "customFocusModes"), let saved = try? JSONDecoder().decode([FocusMode].self, from: data) { customModes = saved }
        migrateToModesIfNeeded()
        websites.registerCompanion()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Modes

    var modes: [FocusMode] { FocusMode.builtIn + customModes }
    func mode(for selection: BlockSelection) -> FocusMode? { FocusMode.matching(selection, in: modes) }
    var nextCustomModeName: String {
        var n = customModes.count + 1
        while customModes.contains(where: { $0.name == "Custom \(n)" }) { n += 1 }
        return "Custom \(n)"
    }

    /// Saves a custom mode. Anything that used the mode's previous targets follows the edit.
    func saveMode(_ mode: FocusMode) {
        guard !mode.isBuiltIn, !mode.blocked.isEmpty else { return }
        let previous = customModes.first { $0.id == mode.id }
        if let index = customModes.firstIndex(where: { $0.id == mode.id }) { customModes[index] = mode } else { customModes.append(mode) }
        guard let previous, previous.blocked != mode.blocked else { return }
        if manualSelection == previous.blocked { manualSelection = mode.blocked }
        for schedule in schedules where schedule.blocked == previous.blocked {
            var updated = schedule; updated.blocked = mode.blocked; updateSchedule(updated)
        }
    }
    func deleteMode(_ mode: FocusMode) {
        customModes.removeAll { $0.id == mode.id }
        if manualSelection == mode.blocked { manualSelection = FocusMode.social.blocked }
    }

    /// One-time move to modes: new sessions default to Social, and any schedule whose
    /// targets match no built-in mode keeps them as a named custom mode.
    private func migrateToModesIfNeeded() {
        let key = "focusModesMigrated"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        for schedule in schedules where !schedule.blocked.isEmpty && mode(for: schedule.blocked) == nil {
            customModes.append(FocusMode(name: nextCustomModeName, blocked: schedule.blocked))
        }
        manualSelection = FocusMode.social.blocked
    }

    func addSchedule(_ schedule: FocusSchedule) {
        guard schedule.hasValidTimeRange, !schedule.blocked.isEmpty else { return }
        schedules.append(schedule); ScheduleStore.save(schedules); refresh()
        Analytics.capture("schedule_added", ["days_count": schedule.days.count])
    }
    func updateSchedule(_ schedule: FocusSchedule) {
        guard !activeScheduleIDs.contains(schedule.id), schedule.hasValidTimeRange, !schedule.blocked.isEmpty,
              let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule; ScheduleStore.save(schedules); refresh()
    }
    func deleteSchedule(_ schedule: FocusSchedule) {
        guard !activeScheduleIDs.contains(schedule.id) else { return }
        schedules.removeAll { $0.id == schedule.id }; ScheduleStore.save(schedules); refresh()
    }
    func activeScheduleEndTime(for scheduleID: UUID) -> Date? {
        timeline.sessions.first { $0.scheduleID == scheduleID }?.end
    }
    private func acquireEngine() -> Bool {
        if engine.isHeld { return true }
        guard engine.acquire() else {
            blockingError = "Another Ortus app has an active session. Finish that session before starting one here."
            return false
        }
        blockingError = nil
        return true
    }

    func startFocusSession(name: String = "Focus", duration: TimeInterval? = nil) {
        guard !isInFocus, !manualSelection.isEmpty, acquireEngine() else { return }
        completionMessage = nil
        timeline.beginManual(at: Date(), duration: duration ?? 3600, blocked: manualSelection)
        refresh(forcePublish: true)
        Analytics.capture("focus_started", ["scheduled": false])
    }
    func revertFocusSession() {
        guard isInGracePeriod else { return }
        timeline.revertManual(at: Date())
        refresh(forcePublish: true)
        completionMessage = "Focus cancelled. Your apps and websites are available."
        Analytics.capture("focus_reverted")
    }
    func skipGracePeriod() {
        guard isInGracePeriod else { return }
        timeline.skipGracePeriod()
        refresh(forcePublish: true)
    }
    func endFocusSession() {
        timeline.endEarly(at: Date())
        refresh(forcePublish: true)
    }
    func emergencyEndFocusSession() {
        guard isInFocus, canUseEmergencyEnd else { return }
        lastEmergencyEndTimestamp = Date().timeIntervalSince1970
        originalFocusEndTime = timeline.end
        timeline.endEarly(at: Date())
        apps.finish(relaunch: true)
        refresh(forcePublish: true)
        completionMessage = "Focus ended early. Your apps and websites are available."
        Analytics.capture("focus_emergency_ended")
    }
    func extendFocus(by seconds: TimeInterval) {
        timeline.extend(by: seconds)
        refresh(forcePublish: true)
    }

    private func refresh(forcePublish: Bool = false) {
        let now = Date()
        timeline.reconcile(at: now, schedules: schedules)
        if !timeline.sessions.isEmpty && !acquireEngine() {
            // A schedule waiting for another controller has not started. Re-evaluate
            // its current saved choices each tick instead of keeping a stale draft.
            timeline.sessions.removeAll { $0.scheduleID != nil }
        } else if timeline.sessions.isEmpty && blockingError != nil && acquireEngine() {
            engine.release()
        }
        let effective = engine.isHeld ? timeline : FocusTimeline()
        if timeline.sessions.isEmpty, engine.isHeld {
            websites.publish(sessions: [], now: now)
            engine.release()
        }
        let selection = effective.selection
        let wasActive = isInFocus
        let previousEnd = focusEndTime
        let changed = activeSelection != selection || focusEndTime != effective.end || isInFocus != !effective.sessions.isEmpty
        if activeSelection != selection { activeSelection = selection }
        if isInFocus != !effective.sessions.isEmpty { isInFocus = !effective.sessions.isEmpty }
        let start = effective.sessions.map(\.start).min()
        if focusStartTime != start { focusStartTime = start }
        if focusEndTime != effective.end { focusEndTime = effective.end }
        let name = effective.sessions.map(\.name).joined(separator: " + ")
        if currentSessionName != name { currentSessionName = name }
        let ids = Set(effective.sessions.compactMap(\.scheduleID))
        if activeScheduleIDs != ids { activeScheduleIDs = ids }
        let grace = effective.sessions.compactMap(\.graceEnd).filter { $0 > now }.max()
        if gracePeriodEndTime != grace { gracePeriodEndTime = grace }
        // A scheduled session cannot be cancelled by a manual session's grace period.
        let inGrace = gracePeriodEndTime != nil && activeScheduleIDs.isEmpty
        if isInGracePeriod != inGrace { isInGracePeriod = inGrace }
        emergencyScheduleSuppressUntil = timeline.suppressedUntil?.timeIntervalSince1970 ?? 0
        isEmergencyEnded = timeline.suppressedUntil.map { $0 > now } ?? false
        apps.update(selection.applications)
        if wasActive && !isInFocus {
            apps.finish(relaunch: relaunchSlackOnEnd)
            clearSlackStatusForFocus()
            completionMessage = "Focus complete. Your apps and websites are available again."
            sendNotification(title: "Focus complete", body: "Your apps and websites are available again.")
        } else if !wasActive && isInFocus {
            sendNotification(title: "Focus active", body: selection.summary)
        }
        if selection.blocksSlack {
            if !slackStatusApplied || previousEnd != focusEndTime { applySlackStatusForFocus() }
        } else { clearSlackStatusForFocus() }
        if changed || forcePublish || now.timeIntervalSince(lastPublish) >= 5 {
            if engine.isHeld { websites.publish(sessions: effective.sessions, now: now) }
            websites.publishPresence(now: now)
            if let data = try? JSONEncoder().encode(timeline) { UserDefaults.standard.set(data, forKey: "activeFocusTimeline") }
            lastPublish = now
        } else {
            websites.refreshConnections(now: now)
        }
    }

    private func applySlackStatusForFocus() {
        guard activeSelection.blocksSlack, let slackService, slackService.isConnected else { return }
        guard !slackStatusApplied || lastSlackEnd != focusEndTime else { return }
        slackStatusApplied = true; lastSlackEnd = focusEndTime
        let status = slackStatusEnabled; let text = slackStatusText; let emoji = slackStatusEmoji
        let end = focusEndTime; let dnd = slackDndEnabled
        let minutes = end.map { max(1, Int(ceil($0.timeIntervalSinceNow / 60))) }
        Task {
            if status { try? await slackService.setStatus(text: text, emoji: emoji, expiration: end) }
            if dnd, let minutes { try? await slackService.setSnooze(minutes: minutes) }
        }
    }
    private func clearSlackStatusForFocus() {
        guard slackStatusApplied, let slackService else { return }
        slackStatusApplied = false; lastSlackEnd = nil
        let dnd = slackDndEnabled
        Task {
            try? await slackService.clearStatus()
            if dnd { try? await slackService.endSnooze() }
        }
    }
    private func sendNotification(title: String, body: String) {
        guard showNotifications, Bundle.main.bundleIdentifier != nil else { return }
        Task {
            // Never interrupt a scheduled session with an unexpected permission prompt.
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
