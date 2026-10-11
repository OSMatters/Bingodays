import Foundation

enum BingoTaskBoardHelpers {
    static func taskItem(from cell: BingoCell, maxLength: Int) -> MyTaskItem? {
        let text = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return MyTaskItem(
            text: String(text.prefix(maxLength)),
            startAt: cell.startVisibleAt,
            endAt: cell.endVisibleAt,
            startMonth: cell.startVisibleMonth,
            startDay: cell.startVisibleDay,
            recurrenceRule: cell.effectiveRecurrenceRule
        )
    }
}

enum TaskTimeWindowValidationRules {
    /// Matches the editor's minimum selectable time: a newly saved task cannot
    /// begin or end before the moment it is saved.
    static func isStartTimeAllowed(_ date: Date?, now: Date) -> Bool {
        guard let date else { return true }
        return date >= now
    }

    static func isEndTimeAllowed(_ date: Date?, now: Date) -> Bool {
        guard let date else { return true }
        return date >= now
    }
}

struct TaskEditRuleInput {
    let previousCell: BingoCell
    let text: String
    let isForced: Bool
    let residentWeekdays: Set<Int>
    let isOneTimeTask: Bool
    let recurrenceRule: TaskRecurrenceRule?
    let estimatedDurationMinutes: Int?
    let startVisibleAt: Date?
    let endVisibleAt: Date?
    let startReminderEnabled: Bool
    let startReminderOffsetMinutes: Int
    let referenceDate: Date
    let calendar: Calendar
    let maxTaskLength: Int
    let maxCountdownMinutes: Int
}

struct TaskEditRuleResult {
    let cell: BingoCell
    let normalizedTaskText: String
    let normalizedStartVisibleAt: Date?
    let normalizedEndVisibleAt: Date?

    var isEmpty: Bool {
        normalizedTaskText.isEmpty
    }
}

enum TaskEditRuleEngine {
    private struct TaskIdentity: Equatable {
        let text: String
        let residentWeekdays: Set<Int>
        let oneTimeVisibleDate: Date?
        let recurrenceRule: TaskRecurrenceRule?
        let startVisibleAt: Date?
        let endVisibleAt: Date?
        let usesRecurringTimeWindow: Bool
    }

    static func apply(_ input: TaskEditRuleInput) -> TaskEditRuleResult {
        let limitedText = String(input.text.prefix(input.maxTaskLength))
        let trimmedText = limitedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedStartVisibleAt = trimmedText.isEmpty ? nil : input.startVisibleAt
        let recurrenceDefaultDate = submittedStartVisibleAt ?? input.referenceDate
        let normalizedRecurrenceRule = trimmedText.isEmpty ? nil : input.recurrenceRule?.normalized(
            defaultWeekday: input.calendar.component(.weekday, from: recurrenceDefaultDate),
            defaultMonthDay: input.calendar.component(.day, from: recurrenceDefaultDate),
            defaultAnchorDate: recurrenceDefaultDate
        )
        let normalizedWeekdays: Set<Int>
        if normalizedRecurrenceRule?.kind == .weekly {
            normalizedWeekdays = normalizedRecurrenceRule?.weekdays ?? []
        } else {
            normalizedWeekdays = trimmedText.isEmpty || normalizedRecurrenceRule != nil
                ? []
                : input.residentWeekdays
        }
        let hasRepeatingSchedule = normalizedRecurrenceRule.map { $0.kind != .none }
            ?? !normalizedWeekdays.isEmpty
        let normalizedStartVisibleAt = hasRepeatingSchedule ? nil : submittedStartVisibleAt
        let normalizedEndVisibleAt = hasRepeatingSchedule || trimmedText.isEmpty
            ? nil
            : validEndVisibleAt(input.endVisibleAt, startVisibleAt: normalizedStartVisibleAt)
        let allowsTaskCountdown = !trimmedText.isEmpty && !hasRepeatingSchedule
        let normalizedEstimatedDurationMinutes = allowsTaskCountdown
            ? input.estimatedDurationMinutes.map { min(max($0, 1), input.maxCountdownMinutes) }
            : nil
        let normalizedOneTimeTask = !trimmedText.isEmpty && (
            normalizedRecurrenceRule?.kind == TaskRecurrenceRule.Kind.none ||
                (normalizedRecurrenceRule == nil && input.isOneTimeTask)
        )
        let normalizedOneTimeVisibleDate = normalizedOneTimeTask
            ? (normalizedRecurrenceRule?.anchorDate ?? normalizedStartVisibleAt ?? input.referenceDate)
            : nil
        let normalizedReminderEnabled = !hasRepeatingSchedule &&
            !trimmedText.isEmpty &&
            !input.previousCell.isCompleted &&
            normalizedStartVisibleAt != nil &&
            normalizedEndVisibleAt != nil &&
            input.startReminderEnabled
        let normalizedReminderOffset = BingoCell.normalizedStartReminderOffsetMinutes(
            input.startReminderOffsetMinutes
        )
        let usesStoredSchedule = normalizedRecurrenceRule != nil ||
            !normalizedWeekdays.isEmpty ||
            normalizedOneTimeTask ||
            normalizedStartVisibleAt != nil ||
            normalizedEndVisibleAt != nil
        let updatedIdentity = TaskIdentity(
            text: trimmedText,
            residentWeekdays: normalizedWeekdays,
            oneTimeVisibleDate: normalizedOneTimeVisibleDate,
            recurrenceRule: normalizedRecurrenceRule,
            startVisibleAt: normalizedStartVisibleAt,
            endVisibleAt: normalizedEndVisibleAt,
            usesRecurringTimeWindow: false
        )
        let didChangeTaskIdentity = identity(for: input.previousCell) != updatedIdentity

        var updatedCell = input.previousCell
        updatedCell.residentWeekdays = normalizedWeekdays
        updatedCell.oneTimeVisibleDate = normalizedOneTimeVisibleDate
        updatedCell.recurrenceRule = normalizedRecurrenceRule
        updatedCell.startVisibleAt = normalizedStartVisibleAt
        updatedCell.endVisibleAt = normalizedEndVisibleAt
        updatedCell.usesRecurringTimeWindow = false
        updatedCell.startReminderEnabled = normalizedReminderEnabled
        updatedCell.startReminderOffsetMinutes = normalizedReminderOffset
        updatedCell.startVisibleMonth = nil
        updatedCell.startVisibleDay = nil
        updatedCell.residentTaskText = usesStoredSchedule ? limitedText : nil
        updatedCell.text = usesStoredSchedule
            ? updatedCell.projectedForDisplay(on: input.referenceDate, calendar: input.calendar).text
            : limitedText
        updatedCell.isTaskHidden = false
        updatedCell.isForced = !trimmedText.isEmpty && input.isForced
        updatedCell.countdownEndsAt = nil
        updatedCell.countdownPausedRemainingSeconds = nil
        updatedCell.lastVisibilityWindowTimeoutAt = nil
        updatedCell.estimatedDurationMinutes = normalizedEstimatedDurationMinutes

        if didChangeTaskIdentity {
            updatedCell.completionStreakCount = 0
            updatedCell.lastCompletedAt = nil
        }
        if input.previousCell.isCompleted && didChangeTaskIdentity {
            updatedCell.isCompleted = false
            updatedCell.isTaskHidden = false
            updatedCell.countdownPausedRemainingSeconds = nil
            updatedCell.lastCompletedAt = nil
        }

        if trimmedText.isEmpty {
            clearTaskOwnedState(in: &updatedCell)
        } else if updatedCell.shouldStartCountdownForCurrentOccurrence(
            on: input.referenceDate,
            calendar: input.calendar
        ) {
            updatedCell.countdownEndsAt = updatedCell.countdownDeadlineForCurrentOccurrence(
                startingAt: input.referenceDate,
                maxCountdownMinutes: input.maxCountdownMinutes,
                calendar: input.calendar
            )
            updatedCell.countdownPausedRemainingSeconds = nil
        }

        return TaskEditRuleResult(
            cell: updatedCell,
            normalizedTaskText: trimmedText,
            normalizedStartVisibleAt: normalizedStartVisibleAt,
            normalizedEndVisibleAt: normalizedEndVisibleAt
        )
    }

    private static func identity(for cell: BingoCell) -> TaskIdentity {
        TaskIdentity(
            text: cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines),
            residentWeekdays: cell.residentWeekdays,
            oneTimeVisibleDate: cell.oneTimeVisibleDate,
            recurrenceRule: cell.recurrenceRule,
            startVisibleAt: cell.startVisibleAt,
            endVisibleAt: cell.endVisibleAt,
            usesRecurringTimeWindow: cell.usesRecurringTimeWindow
        )
    }

    private static func validEndVisibleAt(_ date: Date?, startVisibleAt: Date?) -> Date? {
        guard let date else { return nil }
        if let startVisibleAt, date <= startVisibleAt {
            return nil
        }
        return date
    }

    private static func clearTaskOwnedState(in cell: inout BingoCell) {
        cell.isCompleted = false
        cell.isForced = false
        cell.countdownEndsAt = nil
        cell.countdownPausedRemainingSeconds = nil
        cell.residentTaskText = nil
        cell.residentWeekdays = []
        cell.oneTimeVisibleDate = nil
        cell.recurrenceRule = nil
        cell.startVisibleAt = nil
        cell.endVisibleAt = nil
        cell.usesRecurringTimeWindow = false
        cell.startVisibleMonth = nil
        cell.startVisibleDay = nil
        cell.estimatedDurationMinutes = nil
        cell.completionStreakCount = 0
        cell.lastCompletedAt = nil
        cell.lastVisibilityWindowTimeoutAt = nil
    }
}

enum TaskCountdownRuleAction {
    case set(minutes: Int?)
    case pause
    case resume

    var clearsExpiredTaskEventWhenStopped: Bool {
        switch self {
        case .set:
            return true
        case .pause, .resume:
            return false
        }
    }
}

struct TaskCountdownRuleInput {
    let cell: BingoCell
    let action: TaskCountdownRuleAction
    let referenceDate: Date
    let calendar: Calendar
    let maxCountdownMinutes: Int
}

enum TaskCountdownRuleEngine {
    static func apply(_ input: TaskCountdownRuleInput) -> BingoCell? {
        var cell = input.cell
        guard cell.hasStoredTask else { return nil }

        switch input.action {
        case let .set(minutes):
            if let minutes {
                guard cell.canManuallySetTaskCountdown,
                      !cell.completionApplies(on: input.referenceDate, calendar: input.calendar) else {
                    return nil
                }
                cell.estimatedDurationMinutes = min(max(minutes, 1), input.maxCountdownMinutes)
                cell.countdownEndsAt = nil
                cell.countdownPausedRemainingSeconds = nil
                if cell.shouldStartCountdownForCurrentOccurrence(
                    on: input.referenceDate,
                    calendar: input.calendar
                ) {
                    cell.countdownEndsAt = cell.countdownDeadlineForCurrentOccurrence(
                        startingAt: input.referenceDate,
                        maxCountdownMinutes: input.maxCountdownMinutes,
                        calendar: input.calendar
                    )
                }
            } else {
                cell.estimatedDurationMinutes = nil
                cell.countdownEndsAt = nil
                cell.countdownPausedRemainingSeconds = nil
            }

        case .pause:
            guard cell.canUseTaskCountdown,
                  cell.isCurrentlyTappable(on: input.referenceDate, calendar: input.calendar),
                  !cell.completionApplies(on: input.referenceDate, calendar: input.calendar),
                  let deadline = cell.countdownEndsAt else {
                return nil
            }
            let remainingSeconds = max(
                Int(ceil(deadline.timeIntervalSince(input.referenceDate))),
                0
            )
            guard remainingSeconds > 0 else { return nil }
            cell.countdownPausedRemainingSeconds = remainingSeconds
            cell.countdownEndsAt = nil

        case .resume:
            guard cell.canUseTaskCountdown,
                  cell.isCurrentlyTappable(on: input.referenceDate, calendar: input.calendar),
                  !cell.completionApplies(on: input.referenceDate, calendar: input.calendar),
                  let pausedSeconds = cell.countdownPausedRemainingSeconds,
                  pausedSeconds > 0 else {
                return nil
            }
            let resumedDeadline = input.referenceDate.addingTimeInterval(Double(pausedSeconds))
            if let endDeadline = cell.occurrenceEndVisibleAt(
                on: input.referenceDate,
                calendar: input.calendar
            ), endDeadline > input.referenceDate {
                cell.countdownEndsAt = min(resumedDeadline, endDeadline)
            } else {
                cell.countdownEndsAt = resumedDeadline
            }
            cell.countdownPausedRemainingSeconds = nil
        }

        return cell
    }
}

enum VisibleCellMutationAction {
    case toggleTaskHidden
    case delete
    case restore(BingoCell)

    var respectsForcedTaskLock: Bool {
        switch self {
        case .toggleTaskHidden:
            return true
        case .delete, .restore:
            return false
        }
    }

    var requiresBoardStateRefresh: Bool {
        switch self {
        case .toggleTaskHidden:
            return false
        case .delete, .restore:
            return true
        }
    }
}

struct VisibleCellMutationRuleInput {
    let currentCell: BingoCell
    let action: VisibleCellMutationAction
    let isLocked: Bool
    let referenceDate: Date
    let calendar: Calendar
}

enum VisibleCellMutationRuleEngine {
    static func apply(_ input: VisibleCellMutationRuleInput) -> BingoCell? {
        switch input.action {
        case .toggleTaskHidden:
            guard !input.currentCell.isEmpty,
                  input.currentCell.isCompleted,
                  !input.isLocked else {
                return nil
            }
            var updatedCell = input.currentCell
            updatedCell.isTaskHidden.toggle()
            return updatedCell

        case .delete:
            guard !input.currentCell.isEmpty else { return nil }
            return BingoCell()

        case let .restore(cell):
            return cell.projectedForDisplay(
                on: input.referenceDate,
                calendar: input.calendar
            )
        }
    }
}

struct BoardCellMoveRuleInput {
    let cells: [[BingoCell]]
    let source: (row: Int, col: Int)
    let destination: (row: Int, col: Int)
    let isSourceLocked: Bool
    let isDestinationLocked: Bool
}

enum BoardCellMoveRuleEngine {
    static func apply(_ input: BoardCellMoveRuleInput) -> [[BingoCell]]? {
        guard isValid(input.source, in: input.cells),
              isValid(input.destination, in: input.cells),
              input.source.row != input.destination.row ||
                input.source.col != input.destination.col,
              !input.isSourceLocked,
              !input.isDestinationLocked,
              !input.cells[input.source.row][input.source.col].isEmpty else {
            return nil
        }

        var updatedCells = input.cells
        let sourceCell = updatedCells[input.source.row][input.source.col]
        updatedCells[input.source.row][input.source.col] =
            updatedCells[input.destination.row][input.destination.col]
        updatedCells[input.destination.row][input.destination.col] = sourceCell
        return updatedCells
    }

    private static func isValid(
        _ position: (row: Int, col: Int),
        in cells: [[BingoCell]]
    ) -> Bool {
        position.row >= 0 &&
            position.col >= 0 &&
            position.row < cells.count &&
            position.col < cells[position.row].count
    }
}

struct BoardOrderedCellsRuleInput {
    let orderedCells: [BingoCell?]
    let targetGridSize: Int
    let minimumGridSize: Int
    let maximumGridSize: Int
    let maxTaskLength: Int
    let referenceDate: Date
    let calendar: Calendar
}

struct BoardOrderedCellsRuleResult {
    let gridSize: Int
    let fullBoardCells: [[BingoCell]]
    let appliedTasks: [MyTaskItem]
}

enum BoardOrderedCellsRuleEngine {
    static func apply(_ input: BoardOrderedCellsRuleInput) -> BoardOrderedCellsRuleResult {
        let resolvedGridSize = min(
            max(input.targetGridSize, input.minimumGridSize),
            input.maximumGridSize
        )
        let totalSlots = resolvedGridSize * resolvedGridSize
        let clippedCells = Array(input.orderedCells.prefix(totalSlots))
        var fullBoardCells = BoardEngine.createEmptyGrid(size: input.maximumGridSize)

        for index in clippedCells.indices {
            guard let rawCell = clippedCells[index],
                  let normalizedCell = normalizedCell(rawCell, input: input) else {
                continue
            }

            let row = index / resolvedGridSize
            let col = index % resolvedGridSize
            guard row < fullBoardCells.count, col < fullBoardCells[row].count else { continue }
            fullBoardCells[row][col] = normalizedCell
        }

        let appliedTasks = clippedCells.compactMap { cell -> MyTaskItem? in
            guard let cell else { return nil }
            return BingoTaskBoardHelpers.taskItem(from: cell, maxLength: input.maxTaskLength)
        }
        return BoardOrderedCellsRuleResult(
            gridSize: resolvedGridSize,
            fullBoardCells: fullBoardCells,
            appliedTasks: appliedTasks
        )
    }

    private static func normalizedCell(
        _ rawCell: BingoCell,
        input: BoardOrderedCellsRuleInput
    ) -> BingoCell? {
        var cell = rawCell
        let storedText = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storedText.isEmpty else { return nil }

        let limitedStoredText = String(storedText.prefix(input.maxTaskLength))
        let startVisibleAt = cell.startVisibleAt ?? legacyDate(
            month: cell.startVisibleMonth,
            day: cell.startVisibleDay,
            referenceDate: input.referenceDate,
            calendar: input.calendar
        )
        let endVisibleAt = validEndVisibleAt(cell.endVisibleAt, startVisibleAt: startVisibleAt)
        let recurrenceDefaultDate = startVisibleAt ?? input.referenceDate
        let recurrenceRule = cell.recurrenceRule?.normalized(
            defaultWeekday: input.calendar.component(.weekday, from: recurrenceDefaultDate),
            defaultMonthDay: input.calendar.component(.day, from: recurrenceDefaultDate),
            defaultAnchorDate: recurrenceDefaultDate
        )

        if let residentText = cell.residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !residentText.isEmpty {
            cell.residentTaskText = String(residentText.prefix(input.maxTaskLength))
        } else if recurrenceRule != nil {
            cell.residentTaskText = limitedStoredText
        } else {
            cell.residentTaskText = nil
        }

        cell.residentWeekdays = Set(cell.residentWeekdays.filter { (1...7).contains($0) })
        cell.recurrenceRule = recurrenceRule
        cell.text = limitedStoredText
        cell.startVisibleAt = startVisibleAt
        cell.endVisibleAt = endVisibleAt
        cell.startVisibleMonth = nil
        cell.startVisibleDay = nil
        cell.isForced = false
        cell.removeUnsupportedRepeatingTiming()
        return cell
    }

    private static func legacyDate(
        month: Int?,
        day: Int?,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let month, let day else { return nil }
        var components = calendar.dateComponents([.year], from: referenceDate)
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private static func validEndVisibleAt(_ date: Date?, startVisibleAt: Date?) -> Date? {
        guard let date else { return nil }
        if let startVisibleAt, date <= startVisibleAt {
            return nil
        }
        return date
    }
}
