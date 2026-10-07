import Foundation

public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var scheduleID: UUID?
    public var name: String
    public var start: Date
    public var end: Date
    public var blocked: BlockSelection
    public var graceEnd: Date?
    public init(id: UUID = UUID(), scheduleID: UUID? = nil, name: String, start: Date, end: Date, blocked: BlockSelection, graceEnd: Date? = nil) {
        self.id = id; self.scheduleID = scheduleID; self.name = name
        self.start = start; self.end = end; self.blocked = blocked; self.graceEnd = graceEnd
    }
}

/// Sessions snapshot their targets. Editing a future schedule cannot weaken a live session.
public struct FocusTimeline: Codable, Equatable, Sendable {
    public var sessions: [FocusSession] = []
    public var suppressedUntil: Date?
    public init(sessions: [FocusSession] = [], suppressedUntil: Date? = nil) {
        self.sessions = sessions; self.suppressedUntil = suppressedUntil
    }
    public var selection: BlockSelection { .union(sessions.map(\.blocked)) }
    public var end: Date? { sessions.map(\.end).max() }
    public mutating func reconcile(at now: Date, schedules: [FocusSchedule], calendar: Calendar = .current) {
        sessions.removeAll { $0.end <= now }
        if let suppressedUntil, now < suppressedUntil { return }
        suppressedUntil = nil
        for schedule in schedules where !sessions.contains(where: { $0.scheduleID == schedule.id }) {
            guard !schedule.blocked.isEmpty, let window = schedule.activeWindow(at: now, calendar: calendar) else { continue }
            sessions.append(FocusSession(scheduleID: schedule.id, name: schedule.name, start: now, end: window.end, blocked: schedule.blocked))
        }
    }
    public mutating func beginManual(at now: Date, duration: TimeInterval, blocked: BlockSelection) {
        guard duration > 0, duration <= 86400, !blocked.isEmpty else { return }
        sessions.append(FocusSession(name: "Focus", start: now, end: now.addingTimeInterval(duration), blocked: blocked, graceEnd: now.addingTimeInterval(30)))
    }
    public mutating func revertManual(at now: Date) {
        sessions.removeAll { $0.scheduleID == nil && ($0.graceEnd.map { now < $0 } ?? false) }
    }
    public mutating func skipGracePeriod() {
        for index in sessions.indices where sessions[index].scheduleID == nil {
            sessions[index].graceEnd = nil
        }
    }
    public mutating func endEarly(at now: Date) {
        suppressedUntil = end
        sessions.removeAll()
    }
    public mutating func extend(by seconds: TimeInterval) {
        guard seconds > 0 else { return }
        for index in sessions.indices { sessions[index].end = sessions[index].end.addingTimeInterval(seconds) }
    }
}
