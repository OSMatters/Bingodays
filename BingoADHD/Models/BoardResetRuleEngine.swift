import Foundation

enum TaskLifecycleRuleEngine {
    enum DailySettlementAction {
        case preserve
        case remove
        case resetCompletion
    }

    /// A missing rule is a legacy, unspecified task definition. Preserve its
    /// pre-single-removal behavior; only an explicit single occurrence is removed.
    static func dailySettlementAction(
        for cell: BingoCell,
        mode: BoardTaskResetMode
    ) -> DailySettlementAction {
        guard cell.hasStoredTask else { return .preserve }

        switch mode {
        case .resetStatusNextDay, .customResetStatusTime:
            if cell.hasRepeatingSchedule {
                return .resetCompletion
            }
            if cell.isOneTimeTask {
                return cell.isCompleted ? .remove : .preserve
            }
            return .resetCompletion
        case .clearTasksNextDay:
            return cell.hasRepeatingSchedule ? .resetCompletion : .remove
        case .keepTaskStatus:
            return .preserve
        }
    }
}

struct BoardResetEvaluation {
    let usesCustomResetTime: Bool
    let customResetDue: Bool
    let alreadyAppliedToday: Bool
    let shouldApplyBySchedule: Bool
    let shouldForceApplyForStaleCompletion: Bool

    var shouldApply: Bool {
        shouldApplyBySchedule || shouldForceApplyForStaleCompletion
    }
}

enum BoardResetRuleEngine {
    static func pendingResetEvaluation(
        for board: BingoBoardStore.NamedBoard,
        now: Date,
        calendar: Calendar = .current
    ) -> BoardResetEvaluation {
        let usesCustomResetTime = boardUsesCustomResetTime(board)
        let customResetDue = usesCustomResetTime
            ? shouldApplyCustomReset(for: board, now: now, calendar: calendar)
            : false
        let alreadyAppliedToday: Bool = {
            guard let lastApplied = board.lastTaskResetAppliedAt else { return false }
            return calendar.isDate(lastApplied, inSameDayAs: now)
        }()
        let shouldApplyBySchedule: Bool = {
            if usesCustomResetTime {
                return customResetDue
            }
            switch board.taskResetMode {
            case .resetStatusNextDay, .clearTasksNextDay:
                return !alreadyAppliedToday
            case .customResetStatusTime:
                return usesCustomResetTime ? customResetDue : !alreadyAppliedToday
            case .keepTaskStatus:
                return false
            }
        }()
        let shouldForceApplyForStaleCompletion =
            !usesCustomResetTime &&
            board.taskResetMode == .resetStatusNextDay &&
            boardHasStaleCompletedTasks(board, referenceDate: now, calendar: calendar)

        return BoardResetEvaluation(
            usesCustomResetTime: usesCustomResetTime,
            customResetDue: customResetDue,
            alreadyAppliedToday: alreadyAppliedToday,
            shouldApplyBySchedule: shouldApplyBySchedule,
            shouldForceApplyForStaleCompletion: shouldForceApplyForStaleCompletion
        )
    }

    static func boardAfterApplyingPendingResetIfNeeded(
        _ board: BingoBoardStore.NamedBoard,
        now: Date,
        calendar: Calendar = .current
    ) -> BingoBoardStore.NamedBoard {
        let evaluation = pendingResetEvaluation(for: board, now: now, calendar: calendar)
        guard evaluation.shouldApply else { return board }

        var updatedBoard = board
        updatedBoard.board = transformedBoardSnapshotForResetMode(
            board.board,
            mode: board.taskResetMode,
            referenceDate: now
        )
        updatedBoard.countdownEndsAt = nil
        updatedBoard.lastTaskResetAppliedAt = now
        updatedBoard.updatedAt = now
        return updatedBoard
    }

    static func boardUsesCustomResetTime(_ board: BingoBoardStore.NamedBoard) -> Bool {
        normalizedCustomResetMinutes(
            board.customResetMinutes,
            mode: board.taskResetMode
        ) != nil
    }

    static func normalizedCustomResetMinutes(
        _ minutes: Int?,
        mode: BoardTaskResetMode
    ) -> Int? {
        guard mode != .keepTaskStatus, let minutes else { return nil }
        let clampedMinutes = min(max(minutes, 0), 23 * 60 + 59)
        // Custom 00:00 is behaviorally identical to the free default midnight rule.
        return clampedMinutes == 0 ? nil : clampedMinutes
    }

    static func customResetTriggerTime(
        for board: BingoBoardStore.NamedBoard,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard boardUsesCustomResetTime(board) else { return nil }
        guard let clampedMinutes = normalizedCustomResetMinutes(
            board.customResetMinutes,
            mode: board.taskResetMode
        ) else {
            return nil
        }
        let startOfDay = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .minute, value: clampedMinutes, to: startOfDay)
    }

    static func nextScheduledResetTime(
        for board: BingoBoardStore.NamedBoard,
        after now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard board.taskResetMode != .keepTaskStatus else { return nil }

        let minutes = normalizedCustomResetMinutes(
            board.customResetMinutes,
            mode: board.taskResetMode
        ) ?? 0
        let startOfDay = calendar.startOfDay(for: now)
        guard let triggerToday = calendar.date(byAdding: .minute, value: minutes, to: startOfDay) else {
            return nil
        }
        if triggerToday > now {
            return triggerToday
        }
        return calendar.date(byAdding: .day, value: 1, to: triggerToday)
            ?? triggerToday.addingTimeInterval(86_400)
    }

    static func shouldApplyCustomReset(
        for board: BingoBoardStore.NamedBoard,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let triggerTime = customResetTriggerTime(for: board, now: now, calendar: calendar) else {
            return false
        }
        guard now >= triggerTime else { return false }
        guard let lastApplied = board.lastTaskResetAppliedAt else { return true }
        return lastApplied < triggerTime
    }

    static func completedTaskCount(in board: BingoBoardStore.NamedBoard) -> Int {
        let fullBoard = BoardEngine.expandedBoardCache(from: board.board)
        return fullBoard.flatMap(\.self).filter { $0.isCompleted && $0.hasStoredTask }.count
    }

    static func boardHasStaleCompletedTasks(
        _ board: BingoBoardStore.NamedBoard,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let fullBoard = BoardEngine.expandedBoardCache(from: board.board)

        for row in fullBoard {
            for cell in row {
                guard cell.isCompleted, cell.hasStoredTask else { continue }

                if let lastCompletedAt = cell.lastCompletedAt {
                    if !calendar.isDate(lastCompletedAt, inSameDayAs: referenceDate) {
                        return true
                    }
                } else if !calendar.isDate(board.updatedAt, inSameDayAs: referenceDate) {
                    return true
                }
            }
        }

        return false
    }

    static func transformedBoardSnapshotForResetMode(
        _ board: SavedBoard,
        mode: BoardTaskResetMode,
        referenceDate: Date
    ) -> SavedBoard {
        var fullBoard: [[BingoCell]]

        switch mode {
        case .resetStatusNextDay, .customResetStatusTime:
            fullBoard = BoardEngine.expandedBoardCache(from: board)
            for row in fullBoard.indices {
                for col in fullBoard[row].indices {
                    var cell = normalizedBoardCellForNextDay(fullBoard[row][col])
                    switch TaskLifecycleRuleEngine.dailySettlementAction(for: cell, mode: mode) {
                    case .preserve:
                        clearDailyRuntimeState(&cell)
                    case .remove:
                        cell = BingoCell()
                    case .resetCompletion:
                        resetCurrentCycleState(&cell)
                    }
                    fullBoard[row][col] = cell
                }
            }
            normalizeForceFlagsForBoardReset(&fullBoard, referenceDate: referenceDate)
        case .clearTasksNextDay:
            fullBoard = BoardEngine.expandedBoardCache(from: board)
            for row in fullBoard.indices {
                for col in fullBoard[row].indices {
                    var cell = normalizedBoardCellForNextDay(fullBoard[row][col])
                    switch TaskLifecycleRuleEngine.dailySettlementAction(for: cell, mode: mode) {
                    case .preserve:
                        clearDailyRuntimeState(&cell)
                    case .remove:
                        cell = BingoCell()
                    case .resetCompletion:
                        resetCurrentCycleState(&cell)
                    }
                    fullBoard[row][col] = cell
                }
            }
            normalizeForceFlagsForBoardReset(&fullBoard, referenceDate: referenceDate)
        case .keepTaskStatus:
            fullBoard = BoardEngine.expandedBoardCache(from: board)
        }

        let gridSize = min(max(board.gridSize, 2), BoardEngine.maxGridSize)
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoard,
            size: gridSize,
            referenceDate: referenceDate
        )

        return SavedBoard(
            gridSize: gridSize,
            cells: visibleCells,
            completedLines: [],
            fullBoardCells: fullBoard
        )
    }

    private static func normalizedBoardCellForNextDay(_ cell: BingoCell) -> BingoCell {
        var updated = cell

        if updated.isForced, updated.isCompleted, !updated.hasRepeatingSchedule {
            updated.isForced = false
        }
        return updated
    }

    private static func clearDailyRuntimeState(_ cell: inout BingoCell) {
        if !cell.hasRepeatingSchedule {
            cell.isForced = false
        }
        cell.countdownEndsAt = nil
        cell.countdownPausedRemainingSeconds = nil
        cell.estimatedDurationMinutes = nil
    }

    private static func resetCurrentCycleState(_ cell: inout BingoCell) {
        cell.isCompleted = false
        cell.isTaskHidden = false
        if !cell.hasRepeatingSchedule {
            cell.isForced = false
        }
        cell.countdownEndsAt = nil
        cell.countdownPausedRemainingSeconds = nil
        cell.estimatedDurationMinutes = nil
        cell.lastVisibilityWindowTimeoutAt = nil
    }

    private static func normalizeForceFlagsForBoardReset(
        _ fullBoard: inout [[BingoCell]],
        referenceDate: Date
    ) {
        var forcedPositions: [(row: Int, col: Int)] = []

        for row in fullBoard.indices {
            for col in fullBoard[row].indices {
                guard fullBoard[row][col].isForced else { continue }

                if !fullBoard[row][col].hasStoredTask ||
                    (fullBoard[row][col].isCompleted && !fullBoard[row][col].hasRepeatingSchedule) {
                    fullBoard[row][col].isForced = false
                    continue
                }

                forcedPositions.append((row, col))
            }
        }

        guard forcedPositions.count > 1 else { return }

        let keepPosition = forcedPositions.first {
            let projected = fullBoard[$0.row][$0.col].projectedForDisplay(on: referenceDate)
            return !projected.isEmpty
        } ?? forcedPositions[0]

        for position in forcedPositions where !(position.row == keepPosition.row && position.col == keepPosition.col) {
            fullBoard[position.row][position.col].isForced = false
        }
    }
}

enum BoardRulesSaveRules {
    static func resolvedLastResetAppliedAt(
        previousMode: BoardTaskResetMode,
        previousCustomResetMinutes: Int?,
        previousLastResetAppliedAt: Date?,
        newMode: BoardTaskResetMode,
        newCustomResetMinutes: Int?,
        now: Date
    ) -> Date? {
        let previousSchedule = normalizedSchedule(
            mode: previousMode,
            customResetMinutes: previousCustomResetMinutes
        )
        let newSchedule = normalizedSchedule(
            mode: newMode,
            customResetMinutes: newCustomResetMinutes
        )
        return previousSchedule == newSchedule ? previousLastResetAppliedAt : now
    }

    private static func normalizedSchedule(
        mode: BoardTaskResetMode,
        customResetMinutes: Int?
    ) -> Schedule {
        let normalizedMode = mode == .customResetStatusTime ? .resetStatusNextDay : mode
        return Schedule(
            mode: normalizedMode,
            customResetMinutes: BoardResetRuleEngine.normalizedCustomResetMinutes(
                customResetMinutes,
                mode: normalizedMode
            )
        )
    }

    private struct Schedule: Equatable {
        let mode: BoardTaskResetMode
        let customResetMinutes: Int?
    }
}
