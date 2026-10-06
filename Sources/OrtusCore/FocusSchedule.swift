import Foundation

public enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    public var id: Int { rawValue }
    public var shortName: String { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][rawValue - 1] }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct FocusSchedule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var days: Set<Weekday>
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    public var isEnabled: Bool
    public var blocked: BlockSelection

    public init(id: UUID = UUID(), name: String = "Focus Time", days: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday], startHour: Int = 9, startMinute: Int = 0, endHour: Int = 12, endMinute: Int = 0, isEnabled: Bool = true, blocked: BlockSelection = .standard) {
        self.id = id; self.name = name; self.days = days
        self.startHour = startHour; self.startMinute = startMinute
        self.endHour = endHour; self.endMinute = endMinute
        self.isEnabled = isEnabled; self.blocked = blocked
    }

    private enum CodingKeys: String, CodingKey { case id, name, days, startHour, startMinute, endHour, endMinute, isEnabled, blocked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        days = try c.decode(Set<Weekday>.self, forKey: .days)
        startHour = try c.decode(Int.self, forKey: .startHour); startMinute = try c.decode(Int.self, forKey: .startMinute)
        endHour = try c.decode(Int.self, forKey: .endHour); endMinute = try c.decode(Int.self, forKey: .endMinute)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        // Upgrade the default schedule; retain the previous Slack-only behavior of other saved schedules.
        blocked = try c.decodeIfPresent(BlockSelection.self, forKey: .blocked) ?? (name == "Focus Time" ? .standard : .slackOnly)
    }

    public var startTimeString: String { String(format: "%d:%02d", startHour, startMinute) }
    public var endTimeString: String { String(format: "%d:%02d", endHour, endMinute) }
    public var hasValidTimeRange: Bool {
        (0...23).contains(startHour) && (0...23).contains(endHour) && (0...59).contains(startMinute) && (0...59).contains(endMinute) &&
        startHour * 60 + startMinute != endHour * 60 + endMinute
    }
    public var crossesMidnight: Bool { startHour * 60 + startMinute > endHour * 60 + endMinute }

    /// Weekdays refer to the day the window starts, including overnight schedules.
    public func activeWindow(at date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard isEnabled, hasValidTimeRange else { return nil }
        let today = calendar.startOfDay(for: date)
        for offset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)), days.contains(weekday),
                  let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day),
                  let endDay = calendar.date(byAdding: .day, value: crossesMidnight ? 1 : 0, to: day),
                  let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: endDay),
                  date >= start, date < end else { continue }
            return DateInterval(start: start, end: end)
        }
        return nil
    }
    public func isActiveNow(date: Date = Date()) -> Bool { activeWindow(at: date) != nil }
    public func nextEndTime(from date: Date = Date()) -> Date? { activeWindow(at: date)?.end }
}

public enum ScheduleStore {
    public static func load(defaults: UserDefaults = .standard) -> [FocusSchedule] {
        guard let data = defaults.data(forKey: "focusSchedules") else {
            // First-run schedules are offered as drafts, never activated silently.
            var schedule = FocusSchedule(isEnabled: false)
            // Early previews didn't save the initial schedule. Reuse the active
            // snapshot's identity and repair duplicates created by those restarts.
            if let data = defaults.data(forKey: "activeFocusTimeline"),
               var timeline = try? JSONDecoder().decode(FocusTimeline.self, from: data) {
                let defaultsInFlight = timeline.sessions.filter {
                    $0.scheduleID != nil && $0.name == schedule.name && $0.blocked == schedule.blocked
                }.sorted { $0.start < $1.start }
                if let original = defaultsInFlight.first, let id = original.scheduleID {
                    schedule.id = id
                    schedule.isEnabled = true
                    let duplicates = Set(defaultsInFlight.filter { $0.id != original.id && $0.end == original.end }.map(\.id))
                    timeline.sessions.removeAll { duplicates.contains($0.id) }
                    if !duplicates.isEmpty, let repaired = try? JSONEncoder().encode(timeline) {
                        defaults.set(repaired, forKey: "activeFocusTimeline")
                    }
                }
            }
            let initial = [schedule]
            save(initial, defaults: defaults)
            return initial
        }
        // Do not silently overwrite damaged or unknown data with a new active schedule.
        return (try? JSONDecoder().decode([FocusSchedule].self, from: data)) ?? []
    }
    public static func save(_ schedules: [FocusSchedule], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(schedules) { defaults.set(data, forKey: "focusSchedules") }
    }
}
