import Foundation

/// Shared, read-only in the widget. History before tracking began is unknown.
struct AppOpenWidgetSnapshot: Codable {
    static let storageKey = "app_open_widget_snapshot_v1"
    var trackedSince: Date
    var openedDays: [Date]
    var lastOpenedDay: Date
    var streak: Int
    var bestStreak: Int? = nil
    var milestoneDays: [String: Date]? = nil

    var unlockedThrough: Int { max(bestStreak ?? streak, streak) }

    /// Rewards appear only on the actual earned date, never as a future teaser.
    func unlockedMilestone(on day: Date, at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Int? {
        guard dayState(day, at: now, calendar: calendar) == .opened else { return nil }
        return [10, 20, 30].first { milestone in
            guard let earnedDate = milestoneDays?[String(milestone)] else { return false }
            return calendar.isDate(earnedDate, inSameDayAs: day)
        }
    }

    enum DayState { case opened, missed, today, future, unknown }

    func dayState(_ day: Date, at now: Date, calendar: Calendar = .autoupdatingCurrent) -> DayState {
        let day = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        if day > today { return .future }
        if openedDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) { return .opened }
        if day == today { return .today }
        return day >= calendar.startOfDay(for: trackedSince) ? .missed : .unknown
    }

    func hasMissedOpening(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: lastOpenedDay),
                                 to: calendar.startOfDay(for: date)).day ?? 0) > 1
    }

    func visibleStreak(at date: Date) -> Int {
        hasMissedOpening(at: date) ? 0 : streak
    }

    static func load(from defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
