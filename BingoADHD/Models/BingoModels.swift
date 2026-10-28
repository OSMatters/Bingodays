
import Foundation

struct TaskRecurrenceRule: Codable, Equatable {
    enum Kind: String, Codable, Equatable, CaseIterable {
        case none
        case daily
        case weekly
        case monthlyDay
        case everyNDays
    }

    static let defaultDayInterval = 2
    static let maxDayInterval = 30

    var kind: Kind
    var interval: Int
    var weekdays: Set<Int>
    var monthDay: Int?
    var anchorDate: Date?

    private enum CodingKeys: String, CodingKey {
        case kind
        case interval
        case weekdays
        case monthDay
        case anchorDate
    }

    init(
        kind: Kind,
        interval: Int = 1,
        weekdays: Set<Int> = [],
        monthDay: Int? = nil,
        anchorDate: Date? = nil
    ) {
        self.kind = kind
        self.interval = Self.normalizedInterval(interval, kind: kind)
        self.weekdays = Set(weekdays.filter { (1...7).contains($0) })
        self.monthDay = Self.normalizedMonthDay(monthDay)
        self.anchorDate = anchorDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(interval, forKey: .interval)
        try container.encode(weekdays.sorted(), forKey: .weekdays)
        try container.encodeIfPresent(monthDay, forKey: .monthDay)
        try container.encodeIfPresent(anchorDate, forKey: .anchorDate)
    }

    static func normalizedInterval(_ value: Int, kind: Kind) -> Int {
        switch kind {
        case .everyNDays:
            return min(max(value, 2), maxDayInterval)
        default:
            return max(value, 1)
        }
    }

    static func normalizedMonthDay(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return min(max(value, 1), 31)
    }

    func normalized(defaultWeekday: Int, defaultMonthDay: Int, defaultAnchorDate: Date) -> TaskRecurrenceRule {
        switch kind {
        case .none:
            return TaskRecurrenceRule(kind: .none, anchorDate: anchorDate)
        case .daily:
            return TaskRecurrenceRule(kind: .daily, anchorDate: anchorDate)
        case .weekly:
            let resolvedWeekdays = weekdays.isEmpty ? [defaultWeekday] : weekdays
            return TaskRecurrenceRule(kind: .weekly, weekdays: resolvedWeekdays, anchorDate: anchorDate)
        case .monthlyDay:
            return TaskRecurrenceRule(
                kind: .monthlyDay,
                monthDay: monthDay ?? defaultMonthDay,
                anchorDate: anchorDate
            )
        case .everyNDays:
            return TaskRecurrenceRule(
                kind: .everyNDays,
                interval: interval,
                anchorDate: anchorDate ?? defaultAnchorDate
            )
        }
    }

    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        if kind != .none,
           let anchorDate,
           calendar.startOfDay(for: date) < calendar.startOfDay(for: anchorDate) {
            return false
        }

        switch kind {
        case .none:
            guard let anchorDate else { return true }
            return calendar.isDate(anchorDate, inSameDayAs: date)
        case .daily:
            return true
        case .weekly:
            let weekday = calendar.component(.weekday, from: date)
            return weekdays.contains(weekday)
        case .monthlyDay:
            guard let monthDay else { return true }
            return calendar.component(.day, from: date) == monthDay
        case .everyNDays:
            guard let anchorDate else { return true }
            let start = calendar.startOfDay(for: anchorDate)
            let current = calendar.startOfDay(for: date)
            guard let dayDelta = calendar.dateComponents([.day], from: start, to: current).day,
                  dayDelta >= 0 else {
                return false
            }
            return dayDelta % interval == 0
        }
    }

    func nextActiveDate(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        var startOfReferenceDay = calendar.startOfDay(for: date)
        if kind != .none,
           let anchorDate {
            startOfReferenceDay = max(startOfReferenceDay, calendar.startOfDay(for: anchorDate))
        }

        switch kind {
        case .none:
            guard let anchorDate else { return startOfReferenceDay }
            let anchorDay = calendar.startOfDay(for: anchorDate)
            return anchorDay >= startOfReferenceDay ? anchorDay : nil

        case .daily:
            return startOfReferenceDay

        case .weekly:
            guard !weekdays.isEmpty else { return nil }
            for offset in 0...7 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: startOfReferenceDay) else {
                    continue
                }
                if weekdays.contains(calendar.component(.weekday, from: candidate)) {
                    return candidate
                }
            }
            return nil

        case .monthlyDay:
            guard let monthDay else { return nil }
            let baseComponents = calendar.dateComponents([.year, .month], from: startOfReferenceDay)
            for monthOffset in 0...24 {
                guard let monthStart = calendar.date(from: baseComponents),
                      let candidateMonth = calendar.date(byAdding: .month, value: monthOffset, to: monthStart) else {
                    continue
                }
                var candidateComponents = calendar.dateComponents([.year, .month], from: candidateMonth)
                candidateComponents.day = monthDay
                guard let candidate = calendar.date(from: candidateComponents),
                      calendar.component(.day, from: candidate) == monthDay,
                      candidate >= startOfReferenceDay else {
                    continue
                }
                return candidate
            }
            return nil

        case .everyNDays:
            guard let anchorDate else { return startOfReferenceDay }
            let anchorDay = calendar.startOfDay(for: anchorDate)
            guard startOfReferenceDay >= anchorDay else { return anchorDay }
            guard let dayDelta = calendar.dateComponents([.day], from: anchorDay, to: startOfReferenceDay).day else {
                return nil
            }
            let remainder = dayDelta % interval
            let daysUntilNext = remainder == 0 ? 0 : interval - remainder
            return calendar.date(byAdding: .day, value: daysUntilNext, to: startOfReferenceDay)
        }
    }
}

struct BingoCell: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var residentTaskText: String?
    var residentWeekdays: Set<Int>
    var oneTimeVisibleDate: Date?
    var recurrenceRule: TaskRecurrenceRule?
    var startVisibleAt: Date?
    var endVisibleAt: Date?
    // Legacy persisted field kept only so older boards decode and migrate cleanly.
    var usesRecurringTimeWindow: Bool
    var startReminderEnabled: Bool
    var startReminderOffsetMinutes: Int
    var startVisibleMonth: Int?
    var startVisibleDay: Int?
    var isTaskHidden: Bool
    var isDisplayOnlyInactive: Bool
    var isCompleted: Bool
    // For repeating tasks this is the saved setting; the lock applies only while
    // the current occurrence is available and incomplete.
    var isForced: Bool
    var countdownEndsAt: Date?
    var countdownPausedRemainingSeconds: Int?
    var estimatedDurationMinutes: Int?
    var completionStreakCount: Int
    var lastCompletedAt: Date?
    var lastVisibilityWindowTimeoutAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case residentTaskText
        case residentWeekdays
        case oneTimeVisibleDate
        case recurrenceRule
        case startVisibleAt
        case endVisibleAt
        case usesRecurringTimeWindow
        case startReminderEnabled
        case startReminderOffsetMinutes
        case startVisibleMonth
        case startVisibleDay
        case isTaskHidden
        case isCompleted
        case isForced
        case countdownEndsAt
        case countdownPausedRemainingSeconds
        case estimatedDurationMinutes
        case completionStreakCount
        case lastCompletedAt
        case lastVisibilityWindowTimeoutAt
    }

    init(
        id: UUID = UUID(),
        text: String = "",
        residentTaskText: String? = nil,
        residentWeekdays: Set<Int> = [],
        oneTimeVisibleDate: Date? = nil,
        recurrenceRule: TaskRecurrenceRule? = nil,
        startVisibleAt: Date? = nil,
        endVisibleAt: Date? = nil,
        usesRecurringTimeWindow: Bool = false,
        startReminderEnabled: Bool = false,
        startReminderOffsetMinutes: Int = Self.defaultStartReminderOffsetMinutes,
        startVisibleMonth: Int? = nil,
        startVisibleDay: Int? = nil,
        isTaskHidden: Bool = false,
        isDisplayOnlyInactive: Bool = false,
        isCompleted: Bool = false,
        isForced: Bool = false,
        countdownEndsAt: Date? = nil,
        countdownPausedRemainingSeconds: Int? = nil,
        estimatedDurationMinutes: Int? = nil,
        completionStreakCount: Int = 0,
        lastCompletedAt: Date? = nil,
        lastVisibilityWindowTimeoutAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.residentTaskText = residentTaskText
        self.residentWeekdays = residentWeekdays
        self.oneTimeVisibleDate = oneTimeVisibleDate
        self.recurrenceRule = recurrenceRule
        self.startVisibleAt = startVisibleAt
        self.endVisibleAt = endVisibleAt
        self.usesRecurringTimeWindow = usesRecurringTimeWindow
        self.startReminderEnabled = startReminderEnabled
        self.startReminderOffsetMinutes = Self.normalizedStartReminderOffsetMinutes(startReminderOffsetMinutes)
        self.startVisibleMonth = startVisibleMonth
        self.startVisibleDay = startVisibleDay
        self.isTaskHidden = isTaskHidden
        self.isDisplayOnlyInactive = isDisplayOnlyInactive
        self.isCompleted = isCompleted
        self.isForced = isForced
        self.countdownEndsAt = countdownEndsAt
        self.countdownPausedRemainingSeconds = countdownPausedRemainingSeconds
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.completionStreakCount = max(completionStreakCount, 0)
        self.lastCompletedAt = lastCompletedAt
        self.lastVisibilityWindowTimeoutAt = lastVisibilityWindowTimeoutAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        residentTaskText = try container.decodeIfPresent(String.self, forKey: .residentTaskText)
        residentWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .residentWeekdays) ?? []
        oneTimeVisibleDate = try container.decodeIfPresent(Date.self, forKey: .oneTimeVisibleDate)
        recurrenceRule = try container.decodeIfPresent(TaskRecurrenceRule.self, forKey: .recurrenceRule)
        startVisibleAt = try container.decodeIfPresent(Date.self, forKey: .startVisibleAt)
        endVisibleAt = try container.decodeIfPresent(Date.self, forKey: .endVisibleAt)
        usesRecurringTimeWindow = try container.decodeIfPresent(Bool.self, forKey: .usesRecurringTimeWindow) ?? false
        startReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .startReminderEnabled) ?? false
        startReminderOffsetMinutes = Self.normalizedStartReminderOffsetMinutes(
            try container.decodeIfPresent(Int.self, forKey: .startReminderOffsetMinutes)
        )
        startVisibleMonth = try container.decodeIfPresent(Int.self, forKey: .startVisibleMonth)
        startVisibleDay = try container.decodeIfPresent(Int.self, forKey: .startVisibleDay)
        isTaskHidden = try container.decodeIfPresent(Bool.self, forKey: .isTaskHidden) ?? false
        isDisplayOnlyInactive = false
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        isForced = try container.decodeIfPresent(Bool.self, forKey: .isForced) ?? false
        countdownEndsAt = try container.decodeIfPresent(Date.self, forKey: .countdownEndsAt)
        countdownPausedRemainingSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownPausedRemainingSeconds)
        estimatedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedDurationMinutes)
        completionStreakCount = try container.decodeIfPresent(Int.self, forKey: .completionStreakCount) ?? 0
        lastCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletedAt)
        lastVisibilityWindowTimeoutAt = try container.decodeIfPresent(Date.self, forKey: .lastVisibilityWindowTimeoutAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(residentTaskText, forKey: .residentTaskText)
        try container.encode(residentWeekdays.sorted(), forKey: .residentWeekdays)
        try container.encodeIfPresent(oneTimeVisibleDate, forKey: .oneTimeVisibleDate)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encodeIfPresent(startVisibleAt, forKey: .startVisibleAt)
        try container.encodeIfPresent(endVisibleAt, forKey: .endVisibleAt)
        try container.encode(usesRecurringTimeWindow, forKey: .usesRecurringTimeWindow)
        try container.encode(startReminderEnabled, forKey: .startReminderEnabled)
        try container.encode(startReminderOffsetMinutes, forKey: .startReminderOffsetMinutes)
        try container.encodeIfPresent(startVisibleMonth, forKey: .startVisibleMonth)
        try container.encodeIfPresent(startVisibleDay, forKey: .startVisibleDay)
        try container.encode(isTaskHidden, forKey: .isTaskHidden)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(isForced, forKey: .isForced)
        try container.encodeIfPresent(countdownEndsAt, forKey: .countdownEndsAt)
        try container.encodeIfPresent(countdownPausedRemainingSeconds, forKey: .countdownPausedRemainingSeconds)
        try container.encodeIfPresent(estimatedDurationMinutes, forKey: .estimatedDurationMinutes)
        try container.encode(completionStreakCount, forKey: .completionStreakCount)
        try container.encodeIfPresent(lastCompletedAt, forKey: .lastCompletedAt)
        try container.encodeIfPresent(lastVisibilityWindowTimeoutAt, forKey: .lastVisibilityWindowTimeoutAt)
    }

    var hasVisibilityWindow: Bool {
        hasStartVisibilityDate || hasEndVisibilityDate
    }

    static let defaultStartReminderOffsetMinutes = 5
    static let allowedStartReminderOffsetMinutes = [5, 10, 30]

    static func normalizedStartReminderOffsetMinutes(_ value: Int?) -> Int {
        guard let value else { return defaultStartReminderOffsetMinutes }
        return allowedStartReminderOffsetMinutes.contains(value) ? value : defaultStartReminderOffsetMinutes
    }

    @discardableResult
    mutating func removeUnsupportedRepeatingTiming() -> Bool {
        let original = self
        let hasRuleBasedRepeat = recurrenceRule.map { $0.kind != .none } ?? false
        let hasLegacyWeeklyRepeat = recurrenceRule == nil &&
            !residentWeekdays.isEmpty &&
            !(residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard hasRuleBasedRepeat || hasLegacyWeeklyRepeat else { return false }

        if var rule = recurrenceRule,
           rule.kind == .everyNDays,
           rule.anchorDate == nil,
           let startVisibleAt {
            rule.anchorDate = startVisibleAt
            recurrenceRule = rule
        }

        startVisibleAt = nil
        endVisibleAt = nil
        startVisibleMonth = nil
        startVisibleDay = nil
        usesRecurringTimeWindow = false
        startReminderEnabled = false
        countdownEndsAt = nil
        countdownPausedRemainingSeconds = nil
        estimatedDurationMinutes = nil
        lastVisibilityWindowTimeoutAt = nil
        return self != original
    }

    func isVisibilityWindowActive(on date: Date, calendar: Calendar = .current) -> Bool {
        isStartVisibilityReached(on: date, calendar: calendar) && !isEndVisibilityReached(on: date)
    }

    func isVisibilityWindowInactive(on date: Date, calendar: Calendar = .current) -> Bool {
        // UX rule: only "before start" should be grey/inactive.
        // After end time, task enters timeout flow instead of staying grey.
        hasVisibilityWindow && !isStartVisibilityReached(on: date, calendar: calendar)
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasStoredTask: Bool {
        !storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var storedTaskText: String {
        let recurring = residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !recurring.isEmpty {
            return recurring
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasResidentSchedule: Bool {
        guard let recurrenceRule = effectiveRecurrenceRule else { return false }
        switch recurrenceRule.kind {
        case .weekly:
            return !recurrenceRule.weekdays.isEmpty
        case .monthlyDay, .everyNDays:
            return true
        case .none, .daily:
            return false
        }
    }

    var hasPlannedSchedule: Bool {
        hasStoredTask && (effectiveRecurrenceRule != nil || hasStartVisibilityDate || hasEndVisibilityDate)
    }

    var hasRepeatingSchedule: Bool {
        guard let recurrenceRule = effectiveRecurrenceRule else { return false }
        return recurrenceRule.kind != .none
    }

    var diagnosticTaskRuleKind: String {
        if let recurrenceRule {
            return recurrenceRule.kind.rawValue
        }
        if !residentWeekdays.isEmpty {
            return "legacy_weekly"
        }
        if oneTimeVisibleDate != nil || startVisibleAt != nil || endVisibleAt != nil {
            return "single_scheduled"
        }
        return "single"
    }

    var isOneTimeTask: Bool {
        if let recurrenceRule {
            return recurrenceRule.kind == .none && hasStoredTask
        }
        return oneTimeVisibleDate != nil && !(residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var effectiveRecurrenceRule: TaskRecurrenceRule? {
        guard hasStoredTask else { return nil }
        if let recurrenceRule {
            return recurrenceRule.normalized(
                defaultWeekday: Calendar.current.component(.weekday, from: startVisibleAt ?? Date()),
                defaultMonthDay: Calendar.current.component(.day, from: startVisibleAt ?? Date()),
                defaultAnchorDate: startVisibleAt ?? Date()
            )
        }

        if let oneTimeVisibleDate,
           !(residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            return TaskRecurrenceRule(kind: .none, anchorDate: oneTimeVisibleDate)
        }

        let residentText = residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !residentText.isEmpty, !residentWeekdays.isEmpty {
            return TaskRecurrenceRule(kind: .weekly, weekdays: residentWeekdays)
        }

        return nil
    }

    var hasStartVisibilityDate: Bool {
        guard !hasRepeatingSchedule else { return false }
        return startVisibleAt != nil || (startVisibleMonth != nil && startVisibleDay != nil)
    }

    func isStartVisibilityReached(on date: Date, calendar: Calendar = .current) -> Bool {
        if hasRepeatingSchedule { return true }

        if let startVisibleAt {
            return date >= startVisibleAt
        }
        guard let startVisibleMonth, let startVisibleDay else { return true }
        guard (1...12).contains(startVisibleMonth), (1...31).contains(startVisibleDay) else { return true }

        let currentYear = calendar.component(.year, from: date)
        var components = DateComponents()
        components.year = currentYear
        components.month = startVisibleMonth
        components.day = startVisibleDay
        guard let threshold = calendar.date(from: components) else { return true }

        return date >= calendar.startOfDay(for: threshold)
    }

    var hasEndVisibilityDate: Bool {
        guard !hasRepeatingSchedule else { return false }
        return endVisibleAt != nil
    }

    func isEndVisibilityReached(on date: Date, calendar: Calendar = .current) -> Bool {
        if hasRepeatingSchedule { return false }

        guard let endVisibleAt else { return false }
        return date >= endVisibleAt
    }

    func occurrenceStartVisibleAt(on date: Date, calendar: Calendar = .current) -> Date? {
        hasRepeatingSchedule ? nil : startVisibleAt
    }

    func occurrenceEndVisibleAt(on date: Date, calendar: Calendar = .current) -> Date? {
        hasRepeatingSchedule ? nil : endVisibleAt
    }

    func isResidentActive(on date: Date, calendar: Calendar = .current) -> Bool {
        // A single task with an explicit availability window stays actionable for
        // the whole window. Its legacy one-time anchor only identifies the task;
        // it must not impose a second one-day lifetime.
        if isOneTimeTask, hasVisibilityWindow {
            return true
        }
        guard let recurrenceRule = effectiveRecurrenceRule else { return true }
        return recurrenceRule.isActive(on: date, calendar: calendar)
    }

    func isCurrentlyTappable(on date: Date, calendar: Calendar = .current) -> Bool {
        guard hasStoredTask else { return false }
        guard !isVisibilityWindowInactive(on: date, calendar: calendar) else { return false }
        guard !isEndVisibilityReached(on: date) else { return false }
        guard isResidentActive(on: date, calendar: calendar) else { return false }
        return true
    }

    func completionApplies(on date: Date, calendar: Calendar = .current) -> Bool {
        // Completion lifetime is owned by the board reset rule. Recurring-task projection
        // must not introduce a second, implicit midnight reset boundary.
        isCompleted
    }

    func countdownAppliesToCurrentOccurrence(on date: Date, calendar: Calendar = .current) -> Bool {
        guard canUseTaskCountdown else { return false }
        guard let countdownEndsAt else { return false }
        guard let recurrenceRule = effectiveRecurrenceRule,
              recurrenceRule.kind != .none else {
            return true
        }
        guard let estimatedDurationMinutes, estimatedDurationMinutes > 0 else { return false }
        let countdownStartedAt = countdownEndsAt.addingTimeInterval(Double(-estimatedDurationMinutes * 60))
        return calendar.isDate(countdownStartedAt, inSameDayAs: date)
    }

    func shouldStartCountdownForCurrentOccurrence(on date: Date, calendar: Calendar = .current) -> Bool {
        guard canUseTaskCountdown else { return false }
        guard hasStoredTask else { return false }
        guard let estimatedDurationMinutes, estimatedDurationMinutes > 0 else { return false }
        guard (countdownPausedRemainingSeconds ?? 0) <= 0 else { return false }
        guard isResidentActive(on: date, calendar: calendar) else { return false }
        guard isVisibilityWindowActive(on: date, calendar: calendar) else { return false }
        guard !completionApplies(on: date, calendar: calendar) else { return false }
        guard countdownEndsAt == nil || !countdownAppliesToCurrentOccurrence(on: date, calendar: calendar) else {
            return false
        }
        return true
    }

    func countdownDeadlineForCurrentOccurrence(
        startingAt date: Date,
        maxCountdownMinutes: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard canUseTaskCountdown else { return nil }
        guard let estimatedDurationMinutes, estimatedDurationMinutes > 0 else { return nil }
        let clampedMinutes = min(max(estimatedDurationMinutes, 1), maxCountdownMinutes)
        let countdownDeadline = date.addingTimeInterval(Double(clampedMinutes * 60))
        guard let endDeadline = occurrenceEndVisibleAt(on: date, calendar: calendar),
              endDeadline > date else {
            return countdownDeadline
        }
        return min(countdownDeadline, endDeadline)
    }

    var canUseTaskCountdown: Bool {
        hasStoredTask && !hasRepeatingSchedule
    }

    var canManuallySetTaskCountdown: Bool {
        canUseTaskCountdown && startVisibleAt == nil && endVisibleAt == nil
    }

    func nextResidentActiveDate(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        guard let recurrenceRule = effectiveRecurrenceRule else { return nil }
        return recurrenceRule.nextActiveDate(onOrAfter: date, calendar: calendar)
    }

    func projectedForDisplay(on date: Date, calendar: Calendar = .current) -> BingoCell {
        var projected = self
        if isVisibilityWindowInactive(on: date, calendar: calendar) {
            projected.text = storedTaskText
            projected.isCompleted = false
            projected.isTaskHidden = false
            projected.isDisplayOnlyInactive = true
            projected.isForced = false
            projected.countdownEndsAt = nil
            return projected
        }

        let activeToday: Bool
        if effectiveRecurrenceRule != nil {
            activeToday = isResidentActive(on: date, calendar: calendar)
            let completionAppliesToday = completionApplies(on: date, calendar: calendar)
            projected.text = storedTaskText
            projected.isCompleted = activeToday ? completionAppliesToday : false
            projected.isTaskHidden = activeToday && completionAppliesToday ? isTaskHidden : false
            projected.isDisplayOnlyInactive = !activeToday
            projected.countdownEndsAt = activeToday && countdownAppliesToCurrentOccurrence(on: date, calendar: calendar) ? countdownEndsAt : nil
            return projected
        } else {
            projected.text = storedTaskText
            projected.isDisplayOnlyInactive = false
            // Keep countdown visible/active for regular tasks.
            return projected
        }
    }
}
enum BingoLine: Hashable, Codable {
    case row(Int)
    case column(Int)
    case diagonalMain
    case diagonalAnti
}

struct SavedBoard: Codable, Equatable {
    let gridSize: Int
    let cells: [[BingoCell]]
    let completedLines: Set<BingoLine>
    let fullBoardCells: [[BingoCell]]?

    private enum CodingKeys: String, CodingKey {
        case gridSize
        case cells
        case completedLines
        case fullBoardCells
    }

    init(gridSize: Int, cells: [[BingoCell]], completedLines: Set<BingoLine>, fullBoardCells: [[BingoCell]]? = nil) {
        self.gridSize = gridSize
        self.cells = cells
        self.completedLines = completedLines
        self.fullBoardCells = fullBoardCells
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gridSize = try container.decode(Int.self, forKey: .gridSize)
        cells = try container.decode([[BingoCell]].self, forKey: .cells)
        completedLines = Set(try container.decode([BingoLine].self, forKey: .completedLines))
        fullBoardCells = try container.decodeIfPresent([[BingoCell]].self, forKey: .fullBoardCells)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gridSize, forKey: .gridSize)
        try container.encode(cells, forKey: .cells)
        try container.encode(completedLines.sorted(by: Self.isOrderedBefore), forKey: .completedLines)
        try container.encodeIfPresent(fullBoardCells, forKey: .fullBoardCells)
    }

    private static func isOrderedBefore(_ lhs: BingoLine, _ rhs: BingoLine) -> Bool {
        let lhsOrder = stableOrder(for: lhs)
        let rhsOrder = stableOrder(for: rhs)
        if lhsOrder.kind != rhsOrder.kind { return lhsOrder.kind < rhsOrder.kind }
        return lhsOrder.index < rhsOrder.index
    }

    private static func stableOrder(for line: BingoLine) -> (kind: Int, index: Int) {
        switch line {
        case .row(let index): return (0, index)
        case .column(let index): return (1, index)
        case .diagonalMain: return (2, 0)
        case .diagonalAnti: return (3, 0)
        }
    }
}

struct BingoDiaryEntry: Identifiable, Codable, Equatable {
    let id: String
    let date: Date
    let board: SavedBoard
    let allTasksCompleted: Bool
    let completedTaskCounts: [String: Int]
    let completedTaskCountsAreAuthoritative: Bool

    init(
        id: String,
        date: Date,
        board: SavedBoard,
        allTasksCompleted: Bool,
        completedTaskCounts: [String: Int] = [:],
        completedTaskCountsAreAuthoritative: Bool = true
    ) {
        self.id = id
        self.date = date
        self.board = board
        self.allTasksCompleted = allTasksCompleted
        self.completedTaskCounts = completedTaskCounts
        self.completedTaskCountsAreAuthoritative = completedTaskCountsAreAuthoritative
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case board
        case allTasksCompleted
        case completedTaskCounts
        case completedTaskCountsAreAuthoritative
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        board = try container.decode(SavedBoard.self, forKey: .board)
        allTasksCompleted = try container.decode(Bool.self, forKey: .allTasksCompleted)
        completedTaskCounts = try container.decodeIfPresent([String: Int].self, forKey: .completedTaskCounts) ?? [:]
        completedTaskCountsAreAuthoritative = try container.decodeIfPresent(
            Bool.self,
            forKey: .completedTaskCountsAreAuthoritative
        ) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(board, forKey: .board)
        try container.encode(allTasksCompleted, forKey: .allTasksCompleted)
        try container.encode(completedTaskCounts, forKey: .completedTaskCounts)
        try container.encode(completedTaskCountsAreAuthoritative, forKey: .completedTaskCountsAreAuthoritative)
    }
}

struct DailyRewardState: Codable, Equatable {
    var dateKey: String
    var rewardedCellIDs: Set<UUID>
    var peakCompletedLineCount: Int
    var fullBoardRewardGranted: Bool
    /// When a completion is undone after some of its points were already spent,
    /// only the amount that could actually be deducted is restored if the user
    /// completes that same source again. The keys are stable source identifiers
    /// so a board switch cannot restore a different board's reward.
    var taskReversalCredits: [String: Int]
    var lineReversalCredits: [String: Int]
    var fullBoardReversalCredits: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case dateKey
        case rewardedCellIDs
        case peakCompletedLineCount
        case fullBoardRewardGranted
        case taskReversalCredits
        case lineReversalCredits
        case fullBoardReversalCredits
    }

    init(
        dateKey: String,
        rewardedCellIDs: Set<UUID> = [],
        peakCompletedLineCount: Int = 0,
        fullBoardRewardGranted: Bool = false,
        taskReversalCredits: [String: Int] = [:],
        lineReversalCredits: [String: Int] = [:],
        fullBoardReversalCredits: [String: Int] = [:]
    ) {
        self.dateKey = dateKey
        self.rewardedCellIDs = rewardedCellIDs
        self.peakCompletedLineCount = peakCompletedLineCount
        self.fullBoardRewardGranted = fullBoardRewardGranted
        self.taskReversalCredits = taskReversalCredits
        self.lineReversalCredits = lineReversalCredits
        self.fullBoardReversalCredits = fullBoardReversalCredits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try container.decode(String.self, forKey: .dateKey)
        rewardedCellIDs = Set(try container.decodeIfPresent([UUID].self, forKey: .rewardedCellIDs) ?? [])
        peakCompletedLineCount = try container.decodeIfPresent(Int.self, forKey: .peakCompletedLineCount) ?? 0
        fullBoardRewardGranted = try container.decodeIfPresent(Bool.self, forKey: .fullBoardRewardGranted) ?? false
        taskReversalCredits = try container.decodeIfPresent([String: Int].self, forKey: .taskReversalCredits) ?? [:]
        lineReversalCredits = try container.decodeIfPresent([String: Int].self, forKey: .lineReversalCredits) ?? [:]
        fullBoardReversalCredits = try container.decodeIfPresent([String: Int].self, forKey: .fullBoardReversalCredits) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dateKey, forKey: .dateKey)
        try container.encode(
            rewardedCellIDs.sorted { $0.uuidString < $1.uuidString },
            forKey: .rewardedCellIDs
        )
        try container.encode(peakCompletedLineCount, forKey: .peakCompletedLineCount)
        try container.encode(fullBoardRewardGranted, forKey: .fullBoardRewardGranted)
        try container.encode(taskReversalCredits, forKey: .taskReversalCredits)
        try container.encode(lineReversalCredits, forKey: .lineReversalCredits)
        try container.encode(fullBoardReversalCredits, forKey: .fullBoardReversalCredits)
    }
}

struct MyTaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var startAt: Date?
    var endAt: Date?
    var startMonth: Int?
    var startDay: Int?
    /// The task-library definition only. Runtime completion and countdown state
    /// remain owned by the board cell that is created from this task.
    var recurrenceRule: TaskRecurrenceRule?

    init(
        id: UUID = UUID(),
        text: String = "",
        startAt: Date? = nil,
        endAt: Date? = nil,
        startMonth: Int? = nil,
        startDay: Int? = nil,
        recurrenceRule: TaskRecurrenceRule? = nil
    ) {
        self.id = id
        self.text = text
        self.startAt = startAt
        self.endAt = endAt
        self.startMonth = startMonth
        self.startDay = startDay
        self.recurrenceRule = recurrenceRule
        normalizeVisibilityWindow()
    }

    init(from decoder: Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let legacyText = try? singleValueContainer.decode(String.self) {
            id = UUID()
            text = legacyText
            startAt = nil
            endAt = nil
            startMonth = nil
            startDay = nil
            recurrenceRule = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        startAt = try container.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try container.decodeIfPresent(Date.self, forKey: .endAt)
        startMonth = try container.decodeIfPresent(Int.self, forKey: .startMonth)
        startDay = try container.decodeIfPresent(Int.self, forKey: .startDay)
        recurrenceRule = try container.decodeIfPresent(TaskRecurrenceRule.self, forKey: .recurrenceRule)
        normalizeVisibilityWindow()
    }

    mutating func normalizeStartDate() {
        normalizeVisibilityWindow()
    }

    mutating func normalizeVisibilityWindow() {
        if let startAt {
            let components = Calendar.current.dateComponents([.month, .day], from: startAt)
            startMonth = components.month
            startDay = components.day
        } else {
            guard let startMonth, let startDay else {
                self.startMonth = nil
                self.startDay = nil
                return
            }

            guard (1...12).contains(startMonth), (1...31).contains(startDay) else {
                self.startMonth = nil
                self.startDay = nil
                return
            }
        }

        if let startAt, let endAt, endAt <= startAt {
            self.endAt = nil
        }
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasStartDate: Bool {
        startAt != nil || (startMonth != nil && startDay != nil)
    }

    var hasEndDate: Bool {
        endAt != nil
    }

    func isStartDateReached(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        if let startAt {
            return date >= startAt
        }
        guard let startMonth, let startDay else { return true }
        guard (1...12).contains(startMonth), (1...31).contains(startDay) else { return true }

        let currentYear = calendar.component(.year, from: date)
        var components = DateComponents()
        components.year = currentYear
        components.month = startMonth
        components.day = startDay
        guard let threshold = calendar.date(from: components) else { return true }

        return date >= calendar.startOfDay(for: threshold)
    }

    func isEndDateReached(on date: Date = .now) -> Bool {
        guard let endAt else { return false }
        return date >= endAt
    }
}

struct MyTaskGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var tasks: [MyTaskItem]

    init(id: UUID = UUID(), name: String = "", tasks: [MyTaskItem] = []) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
}

struct MyTasksLibrary: Codable, Equatable {
    var tasks: [MyTaskItem]
    var groups: [MyTaskGroup]

    init(tasks: [MyTaskItem] = [], groups: [MyTaskGroup] = []) {
        self.tasks = tasks
        self.groups = groups
    }
}

struct TaskHistoryRecord: Identifiable, Codable, Equatable {
    let key: String
    var text: String
    var startAt: Date?
    var endAt: Date?
    var startMonth: Int?
    var startDay: Int?
    var recurrenceRule: TaskRecurrenceRule?
    var sourceTaskID: UUID?
    var lastEditedAt: Date

    var id: String { key }

    init(
        key: String,
        text: String,
        startAt: Date? = nil,
        endAt: Date? = nil,
        startMonth: Int? = nil,
        startDay: Int? = nil,
        recurrenceRule: TaskRecurrenceRule? = nil,
        sourceTaskID: UUID? = nil,
        lastEditedAt: Date = .now
    ) {
        self.key = key
        self.text = text
        self.startAt = startAt
        self.endAt = endAt
        self.startMonth = startMonth
        self.startDay = startDay
        self.recurrenceRule = recurrenceRule
        self.sourceTaskID = sourceTaskID
        self.lastEditedAt = lastEditedAt
        normalizeVisibilityWindow()
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func normalizeStartDate() {
        normalizeVisibilityWindow()
    }

    mutating func normalizeVisibilityWindow() {
        if let startAt {
            let components = Calendar.current.dateComponents([.month, .day], from: startAt)
            startMonth = components.month
            startDay = components.day
        } else {
            guard let startMonth, let startDay else {
                self.startMonth = nil
                self.startDay = nil
                return
            }

            guard (1...12).contains(startMonth), (1...31).contains(startDay) else {
                self.startMonth = nil
                self.startDay = nil
                return
            }

            var components = DateComponents()
            components.year = 2000
            components.month = startMonth
            components.day = startDay
            guard Calendar.current.date(from: components) != nil else {
                self.startMonth = nil
                self.startDay = nil
                return
            }
        }

        if let startAt, let endAt, endAt <= startAt {
            self.endAt = nil
        }
    }
}

/// A durable, task-name scoped completion total. This is intentionally separate
/// from `TaskHistoryRecord`, which powers the task library and carries schedule
/// metadata that must never be restored onto a newly added board cell.
struct TaskCompletionHistoryRecord: Identifiable, Codable, Equatable {
    let key: String
    var completionCount: Int
    var lastArchivedAt: Date

    var id: String { key }

    init(key: String, completionCount: Int, lastArchivedAt: Date = .now) {
        self.key = key
        self.completionCount = max(completionCount, 0)
        self.lastArchivedAt = lastArchivedAt
    }
}

struct CustomReward: Identifiable, Codable, Equatable {
    static let currentCardStyleVersion = 2

    let id: UUID
    var title: String
    var requiredPoints: Int
    var emoji: String
    var themeImageName: String?
    var cardStyleVersion: Int
    var redemptionCount: Int
    var totalSpentPoints: Int
    var isArchived: Bool

    var isLegacyCardStyle: Bool {
        cardStyleVersion < Self.currentCardStyleVersion
    }

    var displayEmoji: String {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmoji.first.map(String.init) ?? "😊"
    }

    init(
        id: UUID = UUID(),
        title: String,
        requiredPoints: Int,
        emoji: String = "😊",
        themeImageName: String? = nil,
        cardStyleVersion: Int = CustomReward.currentCardStyleVersion,
        redemptionCount: Int = 0,
        totalSpentPoints: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.requiredPoints = requiredPoints
        self.emoji = emoji
        self.themeImageName = themeImageName
        self.cardStyleVersion = cardStyleVersion
        self.redemptionCount = redemptionCount
        self.totalSpentPoints = totalSpentPoints
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case requiredPoints
        case emoji
        case themeImageName
        case cardStyleVersion
        case redemptionCount
        case totalSpentPoints
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        requiredPoints = try container.decode(Int.self, forKey: .requiredPoints)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "😊"
        themeImageName = try container.decodeIfPresent(String.self, forKey: .themeImageName)
        cardStyleVersion = try container.decodeIfPresent(Int.self, forKey: .cardStyleVersion) ?? 1
        redemptionCount = try container.decodeIfPresent(Int.self, forKey: .redemptionCount) ?? 0
        totalSpentPoints = try container.decodeIfPresent(Int.self, forKey: .totalSpentPoints) ?? 0
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

struct PointRedemptionRecord: Identifiable, Codable, Equatable {
    enum ItemKind: String, Codable {
        case sticker
        case customReward
        case blindBoxTicket
    }

    let id: UUID
    let itemKind: ItemKind
    let title: String
    let points: Int
    let redeemedAt: Date
    let imageName: String?
    let emoji: String?
    let itemReferenceID: String?
    var revokedAt: Date?

    var isActive: Bool { revokedAt == nil }

    init(
        id: UUID = UUID(),
        itemKind: ItemKind,
        title: String,
        points: Int,
        redeemedAt: Date = .now,
        imageName: String? = nil,
        emoji: String? = nil,
        itemReferenceID: String? = nil,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.itemKind = itemKind
        self.title = title
        self.points = points
        self.redeemedAt = redeemedAt
        self.imageName = imageName
        self.emoji = emoji
        self.itemReferenceID = itemReferenceID
        self.revokedAt = revokedAt
    }

    static func stickerReferenceID(_ kind: StickerKind) -> String {
        "sticker:\(kind.rawValue)"
    }

    static func customRewardReferenceID(_ rewardID: UUID) -> String {
        "reward:\(rewardID.uuidString.lowercased())"
    }

    static func blindBoxTicketReferenceID(_ exchangeID: UUID) -> String {
        "blind-box-ticket:\(exchangeID.uuidString.lowercased())"
    }

    var referencedStickerKind: StickerKind? {
        guard let itemReferenceID,
              itemReferenceID.hasPrefix("sticker:") else { return nil }
        return StickerKind(rawValue: String(itemReferenceID.dropFirst("sticker:".count)))
    }

    var referencedCustomRewardID: UUID? {
        guard let itemReferenceID,
              itemReferenceID.hasPrefix("reward:") else { return nil }
        return UUID(uuidString: String(itemReferenceID.dropFirst("reward:".count)))
    }

    var referencedBlindBoxTicketExchangeID: UUID? {
        guard let itemReferenceID,
              itemReferenceID.hasPrefix("blind-box-ticket:") else { return nil }
        return UUID(uuidString: String(itemReferenceID.dropFirst("blind-box-ticket:".count)))
    }

    func linked(to itemReferenceID: String) -> PointRedemptionRecord {
        PointRedemptionRecord(
            id: id,
            itemKind: itemKind,
            title: title,
            points: points,
            redeemedAt: redeemedAt,
            imageName: imageName,
            emoji: emoji,
            itemReferenceID: itemReferenceID,
            revokedAt: revokedAt
        )
    }
}

enum StickerKind: String, CaseIterable, Codable, Identifiable {
    case cowCat
    case cowCatStar
    case orangeCat
    case pomeranian
    case dachshund
    case toyPoodle
    case yorkshire
    case akita
    case goldenRetriever
    case ragdollCat
    case ragdollCatStar
    case maineCoon
    case alaskanMalamute
    case chineseVillageDog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cowCat: return L10n.tr("Cow Cat", zhHans: "奶牛猫", ja: "白黒猫")
        case .cowCatStar: return L10n.tr("Cow Cat (Star)", zhHans: "奶牛猫（星星）", zhHant: "奶牛貓（星星）", ja: "白黒猫（スター）")
        case .orangeCat: return L10n.tr("Orange Cat", zhHans: "橘猫", ja: "茶トラ猫")
        case .pomeranian: return L10n.tr("Pomeranian", zhHans: "博美", ja: "ポメラニアン")
        case .dachshund: return L10n.tr("Dachshund", zhHans: "腊肠狗", ja: "ダックスフンド")
        case .toyPoodle: return L10n.tr("Toy Poodle", zhHans: "泰迪", ja: "トイプードル")
        case .yorkshire: return L10n.tr("Yorkshire", zhHans: "约克夏", ja: "ヨークシャー")
        case .akita: return L10n.tr("Akita", zhHans: "秋田", ja: "秋田犬")
        case .goldenRetriever: return L10n.tr("Golden Retriever", zhHans: "金毛", ja: "ゴールデンレトリバー")
        case .ragdollCat: return L10n.tr("Ragdoll Cat", zhHans: "布偶猫", ja: "ラグドール")
        case .ragdollCatStar: return L10n.tr("Ragdoll Cat (Star)", zhHans: "布偶猫（星星）", zhHant: "布偶貓（星星）", ja: "ラグドール（スター）")
        case .maineCoon: return L10n.tr("Maine Coon", zhHans: "缅因猫", ja: "メインクーン")
        case .alaskanMalamute: return L10n.tr("Alaskan Malamute", zhHans: "阿拉斯加", ja: "アラスカンマラミュート")
        case .chineseVillageDog: return L10n.tr("Chinese Village Dog", zhHans: "中华田园犬", ja: "中華田園犬")
        }
    }

    var redemptionHistoryTitle: String {
        switch self {
        case .cowCatStar:
            return StickerKind.cowCat.title
        case .ragdollCatStar:
            return StickerKind.ragdollCat.title
        default:
            return title
        }
    }

    var unlockedImageName: String {
        switch self {
        case .cowCat: return "CowCatSticker"
        case .cowCatStar: return "CowCatStarSticker"
        case .orangeCat: return "OrangeCatSticker"
        case .pomeranian: return "PomeranianSticker"
        case .dachshund: return "DachshundSticker"
        case .toyPoodle: return "ToyPoodleSticker"
        case .yorkshire: return "YorkshireSticker"
        case .akita: return "AkitaSticker"
        case .goldenRetriever: return "GoldenRetrieverSticker"
        case .ragdollCat: return "RagdollCatSticker"
        case .ragdollCatStar: return "RagdollCatStarSticker"
        case .maineCoon: return "MaineCoonSticker"
        case .alaskanMalamute: return "AlaskanMalamuteSticker"
        case .chineseVillageDog: return "ChineseVillageDogSticker"
        }
    }

    var lockedImageName: String {
        switch self {
        case .cowCat: return "sticker_pets_01_none"
        case .cowCatStar: return "CowCatStarStickerLocked"
        case .orangeCat: return "OrangeCatStickerLocked"
        case .pomeranian: return "sticker_pets_04_none"
        case .dachshund: return "DachshundStickerLocked"
        case .toyPoodle: return "ToyPoodleStickerLocked"
        case .yorkshire: return "YorkshireStickerLocked"
        case .akita: return "sticker_pets_01_none"
        case .goldenRetriever: return "GoldenRetrieverStickerLocked"
        case .ragdollCat: return "MaineCoonStickerLocked"
        case .ragdollCatStar: return "RagdollCatStarStickerLocked"
        case .maineCoon: return "MaineCoonStickerLocked"
        case .alaskanMalamute: return "AlaskanMalamuteStickerLocked"
        case .chineseVillageDog: return "ChineseVillageDogStickerLocked"
        }
    }

    var requiredPoints: Int {
        15
    }

    var homeDisplayWidth: CGFloat {
        switch self {
        case .cowCat:
            return 86
        case .cowCatStar:
            return 94
        case .ragdollCat, .maineCoon, .alaskanMalamute, .goldenRetriever, .chineseVillageDog:
            return 100
        case .ragdollCatStar:
            return 102
        default:
            return 92
        }
    }

    var defaultPlacement: (xRatio: Double, yRatio: Double) {
        switch self {
        case .cowCat:
            return (0.22, 0.24)
        case .cowCatStar:
            return (0.34, 0.84)
        case .orangeCat:
            return (0.48, 0.18)
        case .pomeranian:
            return (0.78, 0.24)
        case .dachshund:
            return (0.18, 0.46)
        case .toyPoodle:
            return (0.82, 0.48)
        case .yorkshire:
            return (0.22, 0.70)
        case .akita:
            return (0.50, 0.74)
        case .goldenRetriever:
            return (0.78, 0.70)
        case .ragdollCat:
            return (0.50, 0.30)
        case .ragdollCatStar:
            return (0.66, 0.84)
        case .maineCoon:
            return (0.34, 0.56)
        case .alaskanMalamute:
            return (0.66, 0.56)
        case .chineseVillageDog:
            return (0.50, 0.88)
        }
    }
}

private enum HomeStickerContent: Equatable {
    case legacy(StickerKind)
    // This model is shared with the Widget target, which deliberately does
    // not link Blind Box domain types. Persist the stable catalog identifier
    // as a String at this boundary.
    case blindBox(id: String, assetName: String)

    var stableIdentifier: String {
        switch self {
        case .legacy(let kind):
            return "legacy:\(kind.rawValue)"
        case .blindBox(let id, _):
            return "blind-box:\(id)"
        }
    }

    var assetName: String {
        switch self {
        case .legacy(let kind):
            return kind.unlockedImageName
        case .blindBox(_, let assetName):
            return assetName
        }
    }

    var displayWidth: CGFloat {
        switch self {
        case .legacy(let kind):
            return kind.homeDisplayWidth
        case .blindBox:
            return 96
        }
    }
}

struct HomeStickerPlacement: Identifiable, Codable, Equatable {
    let id: UUID
    private var content: HomeStickerContent
    var xRatio: Double
    var yRatio: Double
    var scale: Double

    var legacyKind: StickerKind? {
        guard case .legacy(let kind) = content else { return nil }
        return kind
    }

    var blindBoxStickerID: String? {
        guard case .blindBox(let id, _) = content else { return nil }
        return id
    }

    var stableContentIdentifier: String { content.stableIdentifier }
    var artworkName: String { content.assetName }
    var homeDisplayWidth: CGFloat { content.displayWidth }

    init(id: UUID = UUID(), kind: StickerKind, xRatio: Double, yRatio: Double, scale: Double = 1.0) {
        self.init(
            id: id,
            content: .legacy(kind),
            xRatio: xRatio,
            yRatio: yRatio,
            scale: scale
        )
    }

    init(
        id: UUID = UUID(),
        blindBoxStickerID: String,
        assetName: String,
        xRatio: Double,
        yRatio: Double,
        scale: Double = 1.0
    ) {
        self.init(
            id: id,
            content: .blindBox(id: blindBoxStickerID, assetName: assetName),
            xRatio: xRatio,
            yRatio: yRatio,
            scale: scale
        )
    }

    private init(
        id: UUID,
        content: HomeStickerContent,
        xRatio: Double,
        yRatio: Double,
        scale: Double
    ) {
        self.id = id
        self.content = content
        self.xRatio = xRatio
        self.yRatio = yRatio
        self.scale = scale
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case blindBoxStickerID
        case blindBoxAssetName
        case xRatio
        case yRatio
        case scale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let xRatio = try container.decode(Double.self, forKey: .xRatio)
        let yRatio = try container.decode(Double.self, forKey: .yRatio)
        let scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0

        if let blindBoxStickerID = try container.decodeIfPresent(String.self, forKey: .blindBoxStickerID) {
            self.init(
                id: id,
                content: .blindBox(
                    id: blindBoxStickerID,
                    assetName: try container.decodeIfPresent(String.self, forKey: .blindBoxAssetName)
                        ?? "sticker_\(blindBoxStickerID)"
                ),
                xRatio: xRatio,
                yRatio: yRatio,
                scale: scale
            )
            return
        }

        self.init(
            id: id,
            content: .legacy(try container.decode(StickerKind.self, forKey: .kind)),
            xRatio: xRatio,
            yRatio: yRatio,
            scale: scale
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(xRatio, forKey: .xRatio)
        try container.encode(yRatio, forKey: .yRatio)
        try container.encode(scale, forKey: .scale)
        switch content {
        case .legacy(let kind):
            try container.encode(kind, forKey: .kind)
        case .blindBox(let id, let assetName):
            try container.encode(id, forKey: .blindBoxStickerID)
            try container.encode(assetName, forKey: .blindBoxAssetName)
        }
    }

    func replacing(
        xRatio: Double? = nil,
        yRatio: Double? = nil,
        scale: Double? = nil
    ) -> HomeStickerPlacement {
        HomeStickerPlacement(
            id: id,
            content: content,
            xRatio: xRatio ?? self.xRatio,
            yRatio: yRatio ?? self.yRatio,
            scale: scale ?? self.scale
        )
    }

    func normalized() -> HomeStickerPlacement {
        replacing(
            xRatio: Self.clamp(xRatio, min: 0.02, max: 0.98, fallback: 0.5),
            yRatio: Self.clamp(yRatio, min: 0.02, max: 1.08, fallback: 0.5),
            scale: Self.clamp(scale, min: 0.5, max: 1.6, fallback: 1.0)
        )
    }

    private static func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}

enum AppSettings {
    static let languageKey = "app_language_v1"
    static let hapticsEnabledKey = "haptics_enabled"
    static let soundEffectsEnabledKey = "sound_effects_enabled"
    static let themeKey = "theme_color"
    static let homeBackgroundKey = "home_background_v1"
    static let meSkinKey = "me_skin_v1"
    static let homeSkinNewBadgeVersionKey = "home_skin_new_badge_version_v1"
    static let homeSkinNewBadgeTapCountKey = "home_skin_new_badge_tap_count_v1"
    static let newBadgeExistingUserKey = "new_badge_existing_user_v1"
    static let meSettingsNewBadgeTapCountKey = "me_settings_new_badge_tap_count_v1"
    static let reminderNewBadgeTapCountKey = "reminder_new_badge_tap_count_v1"
    static let hasSeenOnboardingKey = "has_seen_onboarding_v2"
    static let commonTasksKey = "common_tasks"
    static let boardCountdownKey = "board_countdown_v1"
    static let totalPointsKey = "total_points_v2"
    static let lifetimePointsKey = "lifetime_points_v1"
    static let dailyRewardStateKey = "daily_reward_state_v1"
    static let redeemedStickersKey = "redeemed_stickers_v1"
    static let redeemedStickerOrderKey = "redeemed_sticker_order_v1"
    static let stickerInventoryCountsKey = "sticker_inventory_counts_v1"
    static let blindBoxLocalStateKey = "blind_box_local_state_v1"
    static let blindBoxCatalogReleaseKey = "blind_box_catalog_release_v1"
    static let hasSeenBlindBoxNewBadgeKey = "has_seen_blind_box_new_badge_v1"
    static let homeStickerPlacementsKey = "home_sticker_placements_v1"
    static let customRewardsKey = "custom_rewards_v1"
    static let pointRedemptionHistoryKey = "point_redemption_history_v1"
    static let pointRedemptionLedgerInitializedKey = "point_redemption_ledger_initialized_v1"
    static let rewardEmojiHistoryKey = "reward_emoji_history_v1"
    static let taskHistoryKey = "task_history_v1"
    static let taskCompletionHistoryKey = "task_completion_history_v1"
    static let taskCompletionHistoryMigrationVersionKey = "task_completion_history_migration_version_v1"
    static let lastAppUpdateCheckAtKey = "last_app_update_check_at_v1"
    static let lastPromptedUpdateVersionKey = "last_prompted_update_version_v1"
    static let skippedUpdateVersionKey = "skipped_update_version_v1"
    static let cachedUpdateInfoKey = "cached_app_update_info_v1"
    static let hasRatedAppReviewPromptKey = "has_rated_app_review_prompt_v1"
    static let hasDismissedSettingsReviewBannerKey = "has_dismissed_settings_review_banner_v1"
    static let appReviewPromptStageKey = "app_review_prompt_stage_v1"
    static let appReviewPromptCooldownUntilKey = "app_review_prompt_cooldown_until_v1"
    static let appReviewPromptLifetimeShownCountKey = "app_review_prompt_lifetime_shown_count_v1"
    static let appReviewPromptLastShownDayKey = "app_review_prompt_last_shown_day_v1"
    static let firstStepGuideStateKey = "first_step_guide_state_v1"
    static let firstStepGuideMilestoneKey = "first_step_guide_milestone_v1"
    static let hasAcknowledgedBoardEditHintKey = "has_acknowledged_board_edit_hint_v1"
    static let hasInteractedWithBoardPanelKey = "has_interacted_with_board_panel_v1"
    static let hasVisitedPremiumPaywallWithoutPurchaseKey = "has_visited_premium_paywall_without_purchase_v1"
    static let hasLegacyLimitedTimeDiscountExposureKey = "has_legacy_limited_time_discount_exposure_v1"
    static let limitedTimeDiscountStartedAtKey = "limited_time_discount_started_at_v1"
    static let limitedTimeDiscountCampaignIDKey = "limited_time_discount_campaign_id_v1"
    static let maxCommonTasks = 8
    static let maxTaskGroups = 3
    static let maxTasksPerGroup = 5
    static let maxTaskLength = 20
    static let maxRewardTitleLength = 16
    static let maxFreeCustomRewards = 3
    static let freeHistoryTasksVisibleCount = 10

    static var isHapticsEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: hapticsEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: hapticsEnabledKey)
    }

    static var isSoundEffectsEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: soundEffectsEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: soundEffectsEnabledKey)
    }
}

/// Portrait background artwork that can be applied to the Home tab. The raw
/// values intentionally match the asset names so the setting stays stable
/// across future UI reorganisations.
enum HomeBackgroundOption: String, CaseIterable, Codable, Identifiable {
    case none
    case halloween01 = "bg_11"
    case halloween02 = "bg_12"
    case pattern01 = "bg_01"
    case pattern02 = "bg_02"
    case pattern03 = "bg_03"
    case pattern04 = "bg_04"
    case pattern05 = "bg_05"
    case pattern06 = "bg_06"
    case pattern07 = "bg_07"
    case pattern08 = "bg_08"
    case pattern09 = "bg_09"
    case pattern10 = "bg_10"

    var id: String { rawValue }

    var imageName: String? {
        self == .none ? nil : "BackgroundSkin_\(rawValue)"
    }

    /// Backgrounds whose artwork is dark enough that the native tab bar's
    /// unselected icons need a light treatment to remain readable.
    var isDarkTone: Bool {
        switch self {
        case .pattern05, .pattern06, .halloween01, .halloween02:
            return true
        default:
            return false
        }
    }

    var isHalloweenLimited: Bool {
        switch self {
        case .halloween01, .halloween02:
            return true
        default:
            return false
        }
    }

    var isPremiumOnly: Bool {
        switch self {
        case .pattern08, .pattern09, .pattern10:
            return true
        default:
            return false
        }
    }

    var badgeTitle: String? {
        switch self {
        case .halloween01, .halloween02:
            return "🎃"
        case .pattern08, .pattern09, .pattern10:
            return "PRO"
        default:
            return nil
        }
    }
}
