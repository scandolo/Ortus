import Foundation

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func fromCalendarWeekday(_ weekday: Int) -> Weekday {
        Weekday(rawValue: weekday) ?? .monday
    }
}

struct FocusSchedule: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var days: Set<Weekday>
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String = "Focus Time", days: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday], startHour: Int = 9, startMinute: Int = 0, endHour: Int = 12, endMinute: Int = 0, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.days = days
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.isEnabled = isEnabled
    }

    var startTimeString: String {
        String(format: "%d:%02d", startHour, startMinute)
    }

    var endTimeString: String {
        String(format: "%d:%02d", endHour, endMinute)
    }

    func isActiveNow(date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        let calendar = Calendar.current
        let weekday = Weekday.fromCalendarWeekday(calendar.component(.weekday, from: date))
        guard days.contains(weekday) else { return false }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    func nextEndTime(from date: Date = Date()) -> Date? {
        guard isActiveNow(date: date) else { return nil }
        let calendar = Calendar.current
        return calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: date)
    }
}

final class ScheduleStore {
    private static let key = "focusSchedules"

    static func load() -> [FocusSchedule] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let schedules = try? JSONDecoder().decode([FocusSchedule].self, from: data) else {
            return []
        }
        return schedules
    }

    static func save(_ schedules: [FocusSchedule]) {
        if let data = try? JSONEncoder().encode(schedules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
