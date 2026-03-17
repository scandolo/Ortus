import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class FocusManager: ObservableObject {
    @Published var isInFocus = false
    @Published var schedules: [FocusSchedule] = []
    @Published var focusEndTime: Date?
    @Published var currentSessionName: String?
    @Published var isEmergencyEnded = false
    @Published var originalFocusEndTime: Date?
    @Published var isInGracePeriod = false
    @Published var gracePeriodEndTime: Date?

    @AppStorage("relaunchSlackOnEnd") var relaunchSlackOnEnd = false
    @AppStorage("showNotifications") var showNotifications = true
    @AppStorage("lastEmergencyEndTimestamp") var lastEmergencyEndTimestamp: Double = 0
    @AppStorage("developerModeEnabled") var developerModeEnabled = false

    private nonisolated static let slackBundleID = "com.tinyspeck.slackmacgap"
    private nonisolated static let gracePeriodDuration: TimeInterval = 30
    private var scheduleTimer: Timer?
    private var launchObserver: NSObjectProtocol?
    private var gracePeriodTimer: Timer?

    // MARK: - Emergency End

    var canUseEmergencyEnd: Bool {
        guard lastEmergencyEndTimestamp > 0 else { return true }
        let lastUsed = Date(timeIntervalSince1970: lastEmergencyEndTimestamp)
        return Date().timeIntervalSince(lastUsed) > 7 * 24 * 3600
    }

    var nextEmergencyAvailableDate: Date? {
        guard lastEmergencyEndTimestamp > 0 else { return nil }
        let lastUsed = Date(timeIntervalSince1970: lastEmergencyEndTimestamp)
        let next = lastUsed.addingTimeInterval(7 * 24 * 3600)
        return next > Date() ? next : nil
    }

    init() {
        schedules = ScheduleStore.load()
        requestNotificationPermission()
        startScheduleEvaluation()
    }

    deinit {
        scheduleTimer?.invalidate()
        gracePeriodTimer?.invalidate()
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    // MARK: - Schedule Management

    func addSchedule(_ schedule: FocusSchedule) {
        schedules.append(schedule)
        ScheduleStore.save(schedules)
    }

    func updateSchedule(_ schedule: FocusSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
            ScheduleStore.save(schedules)
        }
    }

    func deleteSchedule(_ schedule: FocusSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        ScheduleStore.save(schedules)
    }

    // MARK: - Focus Session Control

    func startFocusSession(name: String = "Manual Focus", duration: TimeInterval? = nil) {
        guard !isInFocus else { return }
        isInFocus = true
        isEmergencyEnded = false
        originalFocusEndTime = nil
        currentSessionName = name

        if let duration {
            focusEndTime = Date().addingTimeInterval(duration)
        }

        killSlack()
        startMonitoringLaunches()

        // Grace period only for manual sessions — scheduled ones are expected
        if name == "Manual Focus" {
            startGracePeriod()
        }

        if showNotifications {
            sendNotification(title: "Focus Mode Active", body: "Slack has been blocked. Stay focused!")
        }
    }

    func revertFocusSession() {
        guard isInFocus, isInGracePeriod else { return }
        cancelGracePeriod()
        isInFocus = false
        focusEndTime = nil
        currentSessionName = nil
        stopMonitoringLaunches()

        if showNotifications {
            sendNotification(title: "Focus Reverted", body: "Focus session cancelled. You can reopen Slack when ready.")
        }
    }

    private func startGracePeriod() {
        isInGracePeriod = true
        gracePeriodEndTime = Date().addingTimeInterval(Self.gracePeriodDuration)
        gracePeriodTimer = Timer.scheduledTimer(withTimeInterval: Self.gracePeriodDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.endGracePeriod()
            }
        }
    }

    private func endGracePeriod() {
        isInGracePeriod = false
        gracePeriodEndTime = nil
        gracePeriodTimer?.invalidate()
        gracePeriodTimer = nil
    }

    private func cancelGracePeriod() {
        gracePeriodTimer?.invalidate()
        gracePeriodTimer = nil
        isInGracePeriod = false
        gracePeriodEndTime = nil
    }

    func endFocusSession() {
        guard isInFocus else { return }
        cancelGracePeriod()
        isInFocus = false
        isEmergencyEnded = false
        originalFocusEndTime = nil
        focusEndTime = nil
        currentSessionName = nil
        stopMonitoringLaunches()

        if relaunchSlackOnEnd {
            launchSlack()
        }

        if showNotifications {
            sendNotification(title: "Focus Mode Ended", body: "Slack is available again.")
        }
    }

    func emergencyEndFocusSession() {
        guard isInFocus else { return }
        cancelGracePeriod()

        lastEmergencyEndTimestamp = Date().timeIntervalSince1970
        isEmergencyEnded = true
        originalFocusEndTime = focusEndTime
        isInFocus = false
        focusEndTime = nil
        currentSessionName = nil
        // Keep launch monitoring active — Slack stays blocked until natural end

        if showNotifications {
            sendNotification(title: "Emergency End", body: "Focus UI ended. Slack remains blocked until the scheduled end time.")
        }
    }

    // MARK: - Schedule Evaluation

    private func startScheduleEvaluation() {
        evaluateSchedules()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateSchedules()
            }
        }
    }

    private func evaluateSchedules() {
        let now = Date()

        // Clean up emergency-ended state once the original end time has passed
        if isEmergencyEnded, let originalEnd = originalFocusEndTime, now >= originalEnd {
            isEmergencyEnded = false
            originalFocusEndTime = nil
            stopMonitoringLaunches()
            if relaunchSlackOnEnd {
                launchSlack()
            }
            if showNotifications {
                sendNotification(title: "Focus Period Over", body: "Slack is available again.")
            }
            return
        }

        let anyScheduleActive = schedules.contains { $0.isActiveNow(date: now) }

        if anyScheduleActive && !isInFocus && !isEmergencyEnded {
            let activeSchedule = schedules.first { $0.isActiveNow(date: now) }
            focusEndTime = activeSchedule?.nextEndTime(from: now)
            startFocusSession(name: activeSchedule?.name ?? "Scheduled Focus")
        } else if !anyScheduleActive && isInFocus && currentSessionName != "Manual Focus" {
            endFocusSession()
        }

        // Check manual session timeout
        if isInFocus, let endTime = focusEndTime, currentSessionName == "Manual Focus", Date() >= endTime {
            endFocusSession()
        }
    }

    // MARK: - Slack Process Management

    private func killSlack() {
        let slackApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Self.slackBundleID
        }
        for app in slackApps {
            if !app.terminate() {
                app.forceTerminate()
            }
        }
    }

    private func launchSlack() {
        if let slackURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.slackBundleID) {
            NSWorkspace.shared.openApplication(at: slackURL, configuration: .init())
        }
    }

    private func startMonitoringLaunches() {
        stopMonitoringLaunches()
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.slackBundleID else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isInFocus || self.isEmergencyEnded else { return }
                try? await Task.sleep(for: .milliseconds(500))
                if !app.terminate() {
                    app.forceTerminate()
                }
                if self.showNotifications {
                    self.sendNotification(title: "Slack Blocked", body: "Focus mode is active. Slack cannot be opened.")
                }
            }
        }
    }

    private func stopMonitoringLaunches() {
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            launchObserver = nil
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
