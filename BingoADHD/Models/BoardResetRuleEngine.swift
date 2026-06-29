import Foundation

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
                return customResetDue
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
        updatedBoard.lastTaskResetAppliedAt = now
        updatedBoard.updatedAt = now
        return updatedBoard
    }

    static func boardUsesCustomResetTime(_ board: BingoBoardStore.NamedBoard) -> Bool {
        board.customResetMinutes != nil &&
            (board.taskResetMode == .resetStatusNextDay || board.taskResetMode == .customResetStatusTime)
    }

    static func customResetTriggerTime(
        for board: BingoBoardStore.NamedBoard,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard boardUsesCustomResetTime(board) else { return nil }
        let clampedMinutes = min(max(board.customResetMinutes ?? 0, 0), 23 * 60 + 59)
        let startOfDay = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .minute, value: clampedMinutes, to: startOfDay)
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
            let calendar = Calendar.current
            for row in fullBoard.indices {
                for col in fullBoard[row].indices {
                    fullBoard[row][col] = normalizedBoardCellForNextDay(
                        fullBoard[row][col],
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                }
            }
            for row in fullBoard.indices {
                for col in fullBoard[row].indices {
                    guard !fullBoard[row][col].isEmpty else { continue }
                    fullBoard[row][col].isCompleted = false
                    fullBoard[row][col].isTaskHidden = false
                    fullBoard[row][col].countdownEndsAt = nil
                    fullBoard[row][col].countdownPausedRemainingSeconds = nil
                    fullBoard[row][col].estimatedDurationMinutes = nil
                }
            }
            normalizeForceFlagsForBoardReset(&fullBoard, referenceDate: referenceDate)
        case .clearTasksNextDay:
            fullBoard = BoardEngine.expandedBoardCache(from: board)
            let calendar = Calendar.current
            for row in fullBoard.indices {
                for col in fullBoard[row].indices {
                    var cell = normalizedBoardCellForNextDay(
                        fullBoard[row][col],
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                    if !cell.hasPlannedSchedule {
                        cell = BingoCell()
                    } else {
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

    private static func normalizedBoardCellForNextDay(
        _ cell: BingoCell,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> BingoCell {
        var updated = cell

        if updated.isForced, updated.isCompleted {
            updated.isForced = false
        }

        if updated.isOneTimeTask,
           let oneTimeVisibleDate = updated.oneTimeVisibleDate,
           !calendar.isDate(oneTimeVisibleDate, inSameDayAs: referenceDate) {
            updated.text = ""
            updated.residentTaskText = nil
            updated.residentWeekdays = []
            updated.oneTimeVisibleDate = nil
            updated.recurrenceRule = nil
            updated.isTaskHidden = false
            updated.isForced = false
            updated.countdownEndsAt = nil
            updated.countdownPausedRemainingSeconds = nil
            updated.estimatedDurationMinutes = nil
            updated.completionStreakCount = 0
            updated.lastCompletedAt = nil
            updated.isCompleted = false
        }

        return updated
    }

    private static func resetCurrentCycleState(_ cell: inout BingoCell) {
        cell.isCompleted = false
        cell.isTaskHidden = false
        cell.isForced = false
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

                if !fullBoard[row][col].hasStoredTask || fullBoard[row][col].isCompleted {
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
