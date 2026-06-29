import Foundation

enum BoardEngine {
    static let maxGridSize = 5

    struct ExpiredTaskCandidate: Equatable {
        let cellID: UUID
        let row: Int
        let col: Int
        let taskText: String
        let expiredAt: Date
        let expiredByCountdown: Bool
        let expiredByVisibilityWindow: Bool
        let allowsPostpone: Bool
    }

    struct ScheduledTaskReplacementCandidate: Equatable {
        let cellID: UUID
        let row: Int
        let col: Int
        let currentTaskText: String
        let presetTaskText: String
    }

    enum ExpiredTaskResolution: Equatable {
        case markAsCompleted
        case abandon
        case postpone(minutes: Int)
    }

    struct ExpiredTaskResolutionResult: Equatable {
        let cells: [[BingoCell]]
        let unfinishedTimeoutTaskText: String?
        let clampedPostponeMinutes: Int?
    }

    enum ExpiredBoardCountdownResolution: Equatable {
        case markAsCompleted
        case abandon
        case postpone(minutes: Int)
    }

    struct ExpiredBoardCountdownResolutionResult: Equatable {
        let cells: [[BingoCell]]
        let boardCountdownEndsAt: Date?
        let clampedPostponeMinutes: Int?
    }

    static func createEmptyGrid(size: Int) -> [[BingoCell]] {
        (0..<size).map { _ in
            (0..<size).map { _ in BingoCell() }
        }
    }

    static func expandedBoardCache(from board: SavedBoard, maxSize: Int = maxGridSize) -> [[BingoCell]] {
        var cache = createEmptyGrid(size: maxSize)
        let source = board.fullBoardCells ?? board.cells
        let maxRows = min(source.count, maxSize)

        for row in 0..<maxRows {
            let maxCols = min(source[row].count, maxSize)
            for col in 0..<maxCols {
                cache[row][col] = source[row][col]
            }
        }

        return cache
    }

    static func projectVisibleCells(
        from cache: [[BingoCell]],
        size: Int,
        referenceDate: Date
    ) -> [[BingoCell]] {
        (0..<size).map { row in
            (0..<size).map { col in
                if row < cache.count, col < cache[row].count {
                    return cache[row][col].projectedForDisplay(on: referenceDate)
                }
                return BingoCell()
            }
        }
    }

    static func hasActiveCountdownDisplay(
        in cells: [[BingoCell]],
        size: Int,
        now: Date
    ) -> Bool {
        for row in 0..<min(size, cells.count) {
            for col in 0..<min(size, cells[row].count) {
                let cell = cells[row][col]
                guard !cell.isEmpty, !cell.isCompleted else { continue }
                if let countdownEndsAt = cell.countdownEndsAt, countdownEndsAt > now {
                    return true
                }
            }
        }
        return false
    }

    static func nextTimeSensitiveUpdateDate(
        in board: SavedBoard,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        nextTimeSensitiveUpdateDate(
            in: expandedBoardCache(from: board),
            size: min(max(board.gridSize, 2), maxGridSize),
            now: now,
            calendar: calendar
        )
    }

    static func nextTimeSensitiveUpdateDate(
        in cells: [[BingoCell]],
        size: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        var nextDate: Date?
        for row in 0..<min(size, cells.count) {
            for col in 0..<min(size, cells[row].count) {
                guard let candidate = nextTimeSensitiveUpdateDate(for: cells[row][col], now: now, calendar: calendar) else {
                    continue
                }
                nextDate = earliestDate(nextDate, candidate)
            }
        }
        return nextDate
    }

    static func completedLines(in cells: [[BingoCell]], size: Int) -> Set<BingoLine> {
        var currentLines: Set<BingoLine> = []

        for row in 0..<size where row < cells.count {
            let rowCells = Array(cells[row].prefix(size))
            if rowCells.count == size && rowCells.allSatisfy({ $0.isCompleted && !$0.isEmpty && !$0.isDisplayOnlyInactive }) {
                currentLines.insert(.row(row))
            }
        }

        for col in 0..<size {
            var allCompleted = true
            for row in 0..<size {
                guard row < cells.count, col < cells[row].count,
                      cells[row][col].isCompleted, !cells[row][col].isEmpty, !cells[row][col].isDisplayOnlyInactive else {
                    allCompleted = false
                    break
                }
            }
            if allCompleted {
                currentLines.insert(.column(col))
            }
        }

        var mainDiagonalCompleted = true
        for index in 0..<size {
            guard index < cells.count, index < cells[index].count,
                  cells[index][index].isCompleted, !cells[index][index].isEmpty, !cells[index][index].isDisplayOnlyInactive else {
                mainDiagonalCompleted = false
                break
            }
        }
        if mainDiagonalCompleted {
            currentLines.insert(.diagonalMain)
        }

        var antiDiagonalCompleted = true
        for index in 0..<size {
            let col = size - 1 - index
            guard index < cells.count, col < cells[index].count,
                  cells[index][col].isCompleted, !cells[index][col].isEmpty, !cells[index][col].isDisplayOnlyInactive else {
                antiDiagonalCompleted = false
                break
            }
        }
        if antiDiagonalCompleted {
            currentLines.insert(.diagonalAnti)
        }

        return currentLines
    }

    private static func nextTimeSensitiveUpdateDate(
        for cell: BingoCell,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard cell.hasStoredTask else { return nil }
        if cell.shouldStartCountdownForCurrentOccurrence(on: now, calendar: calendar) {
            return now
        }

        var nextDate: Date?
        if let countdownEndsAt = cell.countdownEndsAt {
            nextDate = earliestDate(nextDate, normalizedCandidateDate(countdownEndsAt, now: now))
        }

        if cell.hasRepeatingSchedule, !cell.isResidentActive(on: now, calendar: calendar) {
            if let nextActiveDate = cell.nextResidentActiveDate(onOrAfter: now, calendar: calendar) {
                nextDate = earliestDate(nextDate, normalizedCandidateDate(nextActiveDate, now: now))
            }
            return nextDate
        }

        if let startVisibleAt = cell.occurrenceStartVisibleAt(on: now, calendar: calendar),
           startVisibleAt > now {
            nextDate = earliestDate(nextDate, startVisibleAt)
        } else if let legacyStartDate = legacyStartVisibilityDate(for: cell, now: now, calendar: calendar) {
            if legacyStartDate > now {
                nextDate = earliestDate(nextDate, legacyStartDate)
            }
        }

        if let endVisibleAt = cell.occurrenceEndVisibleAt(on: now, calendar: calendar) {
            nextDate = earliestDate(nextDate, normalizedCandidateDate(endVisibleAt, now: now))
        }

        return nextDate
    }

    private static func legacyStartVisibilityDate(
        for cell: BingoCell,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard cell.startVisibleAt == nil,
              let startVisibleMonth = cell.startVisibleMonth,
              let startVisibleDay = cell.startVisibleDay,
              (1...12).contains(startVisibleMonth),
              (1...31).contains(startVisibleDay) else {
            return nil
        }

        var components = DateComponents()
        components.year = calendar.component(.year, from: now)
        components.month = startVisibleMonth
        components.day = startVisibleDay
        guard let threshold = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: threshold)
    }

    private static func normalizedCandidateDate(_ date: Date, now: Date) -> Date {
        date <= now ? now : date
    }

    private static func earliestDate(_ current: Date?, _ candidate: Date) -> Date {
        guard let current else { return candidate }
        return min(current, candidate)
    }

    static func boardScore(cells: [[BingoCell]], completedLines: Set<BingoLine>) -> Int {
        let completedTaskCount = cells
            .flatMap { $0 }
            .filter { $0.isCompleted && !$0.isEmpty && !$0.isDisplayOnlyInactive }
            .count
        let allTasksCompletedBonus = isBoardFullyCompleted(cells) ? 10 : 0
        return completedTaskCount + (completedLines.count * 5) + allTasksCompletedBonus
    }

    static func isBoardFullyCompleted(_ cells: [[BingoCell]]) -> Bool {
        let allCells = cells.flatMap { $0 }
        guard !allCells.isEmpty else { return false }
        return allCells.allSatisfy { cell in
            !cell.isEmpty && !cell.isDisplayOnlyInactive && cell.isCompleted
        }
    }

    static func expiredBoardCountdownDeadline(_ deadline: Date?, now: Date) -> Date? {
        guard let deadline, deadline <= now else { return nil }
        return deadline
    }

    static func expiredTaskCandidate(in board: SavedBoard, now: Date) -> ExpiredTaskCandidate? {
        let size = min(max(board.gridSize, 2), maxGridSize)
        let visibleCells = projectVisibleCells(
            from: expandedBoardCache(from: board),
            size: size,
            referenceDate: now
        )
        return expiredTaskCandidate(in: visibleCells, now: now)
    }

    static func expiredTaskCandidate(in cells: [[BingoCell]], now: Date) -> ExpiredTaskCandidate? {
        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                guard let deadline = expiredTaskDeadline(for: cell, now: now) else {
                    continue
                }

                return ExpiredTaskCandidate(
                    cellID: cell.id,
                    row: row,
                    col: col,
                    taskText: cell.storedTaskText,
                    expiredAt: deadline.date,
                    expiredByCountdown: deadline.expiredByCountdown,
                    expiredByVisibilityWindow: deadline.expiredByVisibilityWindow,
                    allowsPostpone: !cell.hasRepeatingSchedule
                )
            }
        }

        return nil
    }

    static func acknowledgeExpiredTaskCountdown(
        in cells: [[BingoCell]],
        candidate: ExpiredTaskCandidate
    ) -> [[BingoCell]]? {
        guard let position = expiredTaskPosition(in: cells, candidate: candidate) else { return nil }
        var updatedCells = cells
        updatedCells[position.row][position.col].countdownEndsAt = nil
        return updatedCells
    }

    static func scheduledTaskReplacementCandidate(
        in fullBoardCells: [[BingoCell]],
        size: Int,
        ignoredCellIDs: Set<UUID>,
        now: Date
    ) -> ScheduledTaskReplacementCandidate? {
        for row in 0..<min(size, fullBoardCells.count) {
            for col in 0..<min(size, fullBoardCells[row].count) {
                let cell = fullBoardCells[row][col]
                guard cell.hasStartVisibilityDate else { continue }
                guard cell.isStartVisibilityReached(on: now) else { continue }
                guard cell.recurrenceRule == nil else { continue }
                guard !cell.hasResidentSchedule, !cell.isOneTimeTask else { continue }
                guard !ignoredCellIDs.contains(cell.id) else { continue }

                let currentText = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let presetText = (cell.residentTaskText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !currentText.isEmpty, !presetText.isEmpty, currentText != presetText else {
                    continue
                }

                return ScheduledTaskReplacementCandidate(
                    cellID: cell.id,
                    row: row,
                    col: col,
                    currentTaskText: currentText,
                    presetTaskText: presetText
                )
            }
        }

        return nil
    }

    static func resolveExpiredTask(
        in cells: [[BingoCell]],
        candidate: ExpiredTaskCandidate,
        resolution: ExpiredTaskResolution,
        now: Date,
        maxCountdownMinutes: Int,
        calendar: Calendar = .current
    ) -> ExpiredTaskResolutionResult? {
        guard let position = expiredTaskPosition(in: cells, candidate: candidate) else { return nil }
        var updatedCells = cells
        var cell = updatedCells[position.row][position.col]
        guard !cell.isEmpty else { return nil }

        switch resolution {
        case .markAsCompleted:
            let visibilityWindowExpired =
                candidate.expiredByVisibilityWindow ||
                (
                    cell.occurrenceStartVisibleAt(on: now, calendar: calendar) != nil &&
                    cell.occurrenceEndVisibleAt(on: now, calendar: calendar) != nil &&
                    cell.isEndVisibilityReached(on: now, calendar: calendar)
                )

            cell.isCompleted = true
            registerCompletionIfNeeded(on: &cell, now: now, calendar: calendar)
            cell.countdownEndsAt = nil
            cell.countdownPausedRemainingSeconds = nil
            cell.estimatedDurationMinutes = nil
            if visibilityWindowExpired && !cell.hasRepeatingSchedule {
                cell.startVisibleAt = nil
                cell.endVisibleAt = nil
                cell.lastVisibilityWindowTimeoutAt = nil
            }
            updatedCells[position.row][position.col] = cell
            return ExpiredTaskResolutionResult(
                cells: updatedCells,
                unfinishedTimeoutTaskText: nil,
                clampedPostponeMinutes: nil
            )

        case .abandon:
            let unfinishedTaskText = cell.storedTaskText
            updatedCells[position.row][position.col] = BingoCell()
            return ExpiredTaskResolutionResult(
                cells: updatedCells,
                unfinishedTimeoutTaskText: unfinishedTaskText,
                clampedPostponeMinutes: nil
            )

        case .postpone(let minutes):
            guard !cell.hasRepeatingSchedule else { return nil }
            let clampedMinutes = min(max(minutes, 1), maxCountdownMinutes)
            let postponedUntil = now.addingTimeInterval(Double(clampedMinutes * 60))

            if candidate.expiredByVisibilityWindow {
                cell.endVisibleAt = postponedUntil
            }
            if candidate.expiredByCountdown || !candidate.expiredByVisibilityWindow {
                cell.countdownEndsAt = postponedUntil
            } else {
                cell.countdownEndsAt = nil
            }
            if let endVisibleAt = cell.endVisibleAt, endVisibleAt <= now {
                cell.endVisibleAt = postponedUntil
            }
            cell.lastVisibilityWindowTimeoutAt = nil
            cell.countdownPausedRemainingSeconds = nil
            updatedCells[position.row][position.col] = cell
            return ExpiredTaskResolutionResult(
                cells: updatedCells,
                unfinishedTimeoutTaskText: candidate.taskText,
                clampedPostponeMinutes: clampedMinutes
            )
        }
    }

    static func resolveExpiredBoardCountdown(
        in cells: [[BingoCell]],
        resolution: ExpiredBoardCountdownResolution,
        now: Date,
        maxCountdownMinutes: Int,
        calendar: Calendar = .current
    ) -> ExpiredBoardCountdownResolutionResult {
        var updatedCells = cells

        switch resolution {
        case .markAsCompleted:
            for row in updatedCells.indices {
                for col in updatedCells[row].indices {
                    guard !updatedCells[row][col].isEmpty else { continue }
                    updatedCells[row][col].isCompleted = true
                    registerCompletionIfNeeded(on: &updatedCells[row][col], now: now, calendar: calendar)
                    updatedCells[row][col].countdownEndsAt = nil
                    updatedCells[row][col].countdownPausedRemainingSeconds = nil
                    updatedCells[row][col].estimatedDurationMinutes = nil
                }
            }
            return ExpiredBoardCountdownResolutionResult(
                cells: updatedCells,
                boardCountdownEndsAt: nil,
                clampedPostponeMinutes: nil
            )

        case .abandon:
            return ExpiredBoardCountdownResolutionResult(
                cells: updatedCells,
                boardCountdownEndsAt: nil,
                clampedPostponeMinutes: nil
            )

        case .postpone(let minutes):
            let clampedMinutes = min(max(minutes, 1), maxCountdownMinutes)
            return ExpiredBoardCountdownResolutionResult(
                cells: updatedCells,
                boardCountdownEndsAt: now.addingTimeInterval(Double(clampedMinutes * 60)),
                clampedPostponeMinutes: clampedMinutes
            )
        }
    }

    private struct ExpiredTaskDeadline: Equatable {
        let date: Date
        let expiredByCountdown: Bool
        let expiredByVisibilityWindow: Bool
    }

    private static func expiredTaskDeadline(for cell: BingoCell, now: Date) -> ExpiredTaskDeadline? {
        guard !cell.isEmpty, !cell.isDisplayOnlyInactive, !cell.isCompleted else { return nil }

        let executionDeadline = cell.countdownEndsAt
        let visibilityWindowDeadline: Date? = {
            guard let start = cell.occurrenceStartVisibleAt(on: now),
                  let end = cell.occurrenceEndVisibleAt(on: now) else { return nil }
            guard now >= start, now >= end else { return nil }
            return end
        }()

        let deadline: Date?
        switch (executionDeadline, visibilityWindowDeadline) {
        case let (execution?, visibility?):
            deadline = min(execution, visibility)
        case let (execution?, nil):
            deadline = execution
        case let (nil, visibility?):
            deadline = visibility
        case (nil, nil):
            deadline = nil
        }

        guard let deadline,
              deadline <= now else {
            return nil
        }
        return ExpiredTaskDeadline(
            date: deadline,
            expiredByCountdown: executionDeadline.map { $0 == deadline } ?? false,
            expiredByVisibilityWindow: visibilityWindowDeadline.map { $0 == deadline } ?? false
        )
    }

    private struct Position: Equatable {
        let row: Int
        let col: Int
    }

    private static func expiredTaskPosition(
        in cells: [[BingoCell]],
        candidate: ExpiredTaskCandidate
    ) -> Position? {
        if candidate.row >= 0,
           candidate.col >= 0,
           candidate.row < cells.count,
           candidate.col < cells[candidate.row].count,
           !cells[candidate.row][candidate.col].isEmpty {
            return Position(row: candidate.row, col: candidate.col)
        }

        for row in cells.indices {
            for col in cells[row].indices where cells[row][col].id == candidate.cellID {
                if !cells[row][col].isEmpty {
                    return Position(row: row, col: col)
                }
            }
        }

        let normalizedTask = candidate.taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else { return nil }

        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                guard !cell.isEmpty, !cell.isCompleted else { continue }
                if cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedTask {
                    return Position(row: row, col: col)
                }
            }
        }
        return nil
    }

    private static func registerCompletionIfNeeded(
        on cell: inout BingoCell,
        now: Date,
        calendar: Calendar
    ) {
        guard !cell.isEmpty else { return }
        if let lastCompletedAt = cell.lastCompletedAt,
           calendar.isDate(lastCompletedAt, inSameDayAs: now) {
            return
        }

        cell.completionStreakCount += 1
        cell.lastCompletedAt = now
    }
}
