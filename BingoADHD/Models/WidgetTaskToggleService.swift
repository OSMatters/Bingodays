import Foundation

enum WidgetTaskToggleService {
    private static let maxGridSize = BoardEngine.maxGridSize

    private struct Position: Hashable {
        let row: Int
        let col: Int
    }

    static func toggled(
        board inputBoard: BingoBoardStore.NamedBoard,
        row: Int,
        col: Int,
        now: Date,
        commitSideEffects: Bool = true
    ) -> BingoBoardStore.NamedBoard? {
        let namedBoard = BingoBoardStore.taskRuleRecoveryBoard(inputBoard)
        if namedBoard.board != inputBoard.board {
            DiagnosticLogStore.recordWarning("task_rule.widget_reset_source_recovered", details: [
                "board_id": namedBoard.id.uuidString
            ])
        }
        let preparedBoard = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(namedBoard, now: now)
        let didApplyBoardReset = preparedBoard.lastTaskResetAppliedAt != namedBoard.lastTaskResetAppliedAt
        if didApplyBoardReset,
           !TaskCompletionHistoryStore.archiveTasksRemovedByReset(from: namedBoard, at: now) {
            return nil
        }
        let gridSize = min(max(preparedBoard.board.gridSize, 0), maxGridSize)
        guard row >= 0, col >= 0, row < gridSize, col < gridSize else {
            return nil
        }

        var fullBoard = BoardEngine.expandedBoardCache(from: preparedBoard.board)
        guard row < fullBoard.count, col < fullBoard[row].count else {
            return nil
        }

        let visibleCells = BoardEngine.projectVisibleCells(from: fullBoard, size: gridSize, referenceDate: now)
        guard row < visibleCells.count, col < visibleCells[row].count else {
            return nil
        }

        let visibleCell = visibleCells[row][col]
        guard !visibleCell.isEmpty else { return nil }
        let isNowCompleted = !fullBoard[row][col].isCompleted
        guard !isNowCompleted || fullBoard[row][col].isCurrentlyTappable(on: now) else { return nil }
        guard !isLocked(row: row, col: col, in: visibleCells, referenceDate: now) else { return nil }

        guard TaskCompletionHistoryStore.ensureMigrated() else { return nil }
        let taskText = fullBoard[row][col].storedTaskText
        let historyBeforeToggle = TaskCompletionHistoryRuleEngine.recordsByArchiving(
            fullBoard.flatMap { $0 },
            into: TaskCompletionHistoryStore.load(),
            at: now
        )
        let projectedHistory = TaskCompletionHistoryRuleEngine.recordsByApplyingCompletionDelta(
            taskText: taskText,
            delta: isNowCompleted ? 1 : -1,
            to: historyBeforeToggle,
            at: now
        )
        let synchronizedCompletionCount = TaskCompletionHistoryRuleEngine.completionCount(
            for: taskText,
            in: projectedHistory
        )

        fullBoard[row][col].isCompleted = isNowCompleted
        if isNowCompleted {
            registerCompletionIfNeeded(cell: &fullBoard[row][col], now: now)
            fullBoard[row][col].isForced = false
            fullBoard[row][col].countdownEndsAt = nil
            fullBoard[row][col].countdownPausedRemainingSeconds = nil
            fullBoard[row][col].estimatedDurationMinutes = nil
        } else {
            fullBoard[row][col].isTaskHidden = false
            fullBoard[row][col].completionStreakCount = max(fullBoard[row][col].completionStreakCount - 1, 0)
            fullBoard[row][col].countdownEndsAt = nil
            fullBoard[row][col].countdownPausedRemainingSeconds = nil
            fullBoard[row][col].estimatedDurationMinutes = nil
            fullBoard[row][col].lastCompletedAt = nil
        }
        synchronizeCompletionHistoryCount(
            taskText: taskText,
            count: synchronizedCompletionCount,
            in: &fullBoard
        )

        let updatedVisibleCells = BoardEngine.projectVisibleCells(from: fullBoard, size: gridSize, referenceDate: now)
        let completedLines = BoardEngine.completedLines(in: updatedVisibleCells, size: gridSize)
        let updatedSavedBoard = SavedBoard(
            gridSize: gridSize,
            cells: updatedVisibleCells,
            completedLines: completedLines,
            fullBoardCells: fullBoard
        )

        if commitSideEffects {
            var updatedNamedBoard = preparedBoard
            updatedNamedBoard.board = updatedSavedBoard
            updatedNamedBoard.updatedAt = now
            guard commitToggleSideEffects(
                previousBoard: preparedBoard,
                updatedBoard: updatedNamedBoard,
                row: row,
                col: col,
                now: now,
                didApplyBoardReset: didApplyBoardReset,
                taskCompletionHistory: projectedHistory
            ) else { return nil }
        }

        var updatedNamedBoard = preparedBoard
        updatedNamedBoard.board = updatedSavedBoard
        updatedNamedBoard.updatedAt = now
        return updatedNamedBoard
    }

    @discardableResult
    static func commitToggleSideEffects(
        previousBoard: BingoBoardStore.NamedBoard,
        updatedBoard: BingoBoardStore.NamedBoard,
        row: Int,
        col: Int,
        now: Date,
        didApplyBoardReset: Bool,
        settlePoints: Bool = true,
        taskCompletionHistory: [TaskCompletionHistoryRecord]? = nil
    ) -> Bool {
        var diagnosticStage = "validate_cell"
        defer {
            DiagnosticLogStore.record("widget.toggle_side_effects", category: "state_change",
                level: diagnosticStage == "complete" ? .info : .warning,
                details: [
                    "board_id": String(previousBoard.id.uuidString.prefix(8)),
                    "position": "\(row),\(col)",
                    "previous_updated_at": String(previousBoard.updatedAt.timeIntervalSince1970),
                    "stage": diagnosticStage,
                    "reset_applied": String(didApplyBoardReset)
                ])
        }
        let previousCells = BoardEngine.expandedBoardCache(from: previousBoard.board)
        let updatedCells = BoardEngine.expandedBoardCache(from: updatedBoard.board)
        guard row >= 0, col >= 0,
              row < previousCells.count, col < previousCells[row].count,
              row < updatedCells.count, col < updatedCells[row].count else {
            return false
        }
        let previousCell = previousCells[row][col]
        let updatedCell = updatedCells[row][col]
        guard previousCell.id == updatedCell.id,
              previousCell.isCompleted != updatedCell.isCompleted else {
            return false
        }

        let previousPoints = settlePoints ? PointsStore.loadPersistenceSnapshot() : nil
        diagnosticStage = "points"
        if settlePoints {
            guard settleRewards(
                previousBoard: previousBoard.board,
                updatedBoard: updatedBoard.board,
                boardLastSavedAt: previousBoard.updatedAt,
                now: now,
                didApplyBoardReset: didApplyBoardReset
            ) else { return false }
        }
        diagnosticStage = "diary"
        guard BingoDiaryStore.applyExplicitTaskDelta(
            task: updatedCell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines),
            delta: updatedCell.isCompleted ? 1 : -1,
            board: updatedBoard.board,
            on: now
        ) else {
            if let previousPoints {
                _ = PointsStore.replacePersistenceSnapshot(previousPoints)
            }
            return false
        }
        let didSaveCompletionHistory: Bool
        diagnosticStage = "completion_history"
        if let taskCompletionHistory {
            didSaveCompletionHistory = TaskCompletionHistoryStore.save(taskCompletionHistory)
        } else {
            didSaveCompletionHistory = TaskCompletionHistoryStore.applyCompletionDelta(
                taskText: updatedCell.storedTaskText,
                delta: updatedCell.isCompleted ? 1 : -1,
                at: now
            )
        }
        guard didSaveCompletionHistory else {
            if let previousPoints {
                _ = PointsStore.replacePersistenceSnapshot(previousPoints)
            }
            return false
        }
        diagnosticStage = "complete"
        return true
    }

    static func cellMutation(
        previousBoard: SavedBoard,
        updatedBoard: SavedBoard,
        row: Int,
        col: Int
    ) -> WidgetTaskSyncStore.Event.CellMutation? {
        let previousCells = BoardEngine.expandedBoardCache(from: previousBoard)
        let updatedCells = BoardEngine.expandedBoardCache(from: updatedBoard)
        guard row >= 0, col >= 0,
              row < previousCells.count, col < previousCells[row].count,
              row < updatedCells.count, col < updatedCells[row].count else {
            return nil
        }
        let previousCell = previousCells[row][col]
        let updatedCell = updatedCells[row][col]
        guard previousCell.id == updatedCell.id, previousCell != updatedCell else {
            return nil
        }
        return WidgetTaskSyncStore.Event.CellMutation(
            cellID: previousCell.id,
            previousCell: previousCell,
            updatedCell: updatedCell,
            row: row,
            col: col
        )
    }

    @discardableResult
    static func reconcileRewards(for board: BingoBoardStore.NamedBoard, now: Date) -> Bool {
        let currentTotalPoints = PointsStore.loadTotalPoints() ?? 0
        let currentLifetimePoints = PointsStore.loadLifetimePoints() ?? currentTotalPoints
        let initialRewardState = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: now,
            boardLastSavedAt: board.updatedAt,
            currentCells: board.board.cells,
            currentCompletedLines: board.board.completedLines,
            isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(board.board.cells),
            savedDailyRewardState: PointsStore.loadDailyRewardState()
        )
        let output = BingoRewardSettlement.settle(
            input: BingoRewardSettlementInput(
                date: now,
                cells: board.board.cells,
                completedLines: board.board.completedLines,
                isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(board.board.cells),
                totalPoints: currentTotalPoints,
                lifetimePoints: currentLifetimePoints,
                dailyRewardState: initialRewardState
            ),
            mode: .normal
        )
        guard PointsStore.saveState(
            totalPoints: output.totalPoints,
            lifetimePoints: output.lifetimePoints,
            dailyRewardState: output.dailyRewardState
        ) else { return false }
        return true
    }

    /// Recovers the points side of an interrupted widget transaction from the
    /// event's explicit before/after cell mutation. Looking only at the already
    /// merged board would seed the daily ledger with the completed cell and then
    /// incorrectly conclude that its point had already been awarded.
    @discardableResult
    static func reconcileRewards(
        for event: WidgetTaskSyncStore.Event,
        mergedBoard: BingoBoardStore.NamedBoard,
        now: Date
    ) -> Bool {
        if let mutation = event.cellMutation,
           !WidgetTaskEventMerge.containsAppliedMutation(mutation, in: mergedBoard.board) {
            DiagnosticLogStore.recordWarning("task_rule.widget_stale_reward_replay_skipped", details: [
                "board_id": event.boardID.uuidString, "cell_id": mutation.cellID.uuidString
            ])
            return true
        }
        guard !event.didApplyBoardReset,
              let mutation = event.cellMutation,
              let position = WidgetTaskEventMerge.resolvedPosition(
                  for: mutation,
                  in: mergedBoard.board
              ) else {
            return reconcileRewards(for: mergedBoard, now: now)
        }

        var previousFullBoard = BoardEngine.expandedBoardCache(from: mergedBoard.board)
        guard position.row < previousFullBoard.count,
              position.col < previousFullBoard[position.row].count else {
            return false
        }
        previousFullBoard[position.row][position.col] = mutation.previousCell
        let gridSize = min(max(mergedBoard.board.gridSize, 2), maxGridSize)
        let previousVisibleCells = BoardEngine.projectVisibleCells(
            from: previousFullBoard,
            size: gridSize,
            referenceDate: now
        )
        var previousBoard = mergedBoard
        previousBoard.board = SavedBoard(
            gridSize: gridSize,
            cells: previousVisibleCells,
            completedLines: BoardEngine.completedLines(
                in: previousVisibleCells,
                size: gridSize
            ),
            fullBoardCells: previousFullBoard
        )

        let projected = projectedPointsSnapshot(
            previousBoard: previousBoard,
            updatedBoard: mergedBoard,
            now: now,
            didApplyBoardReset: false
        )
        guard PointsStore.replacePersistenceSnapshot(projected) else { return false }
        return true
    }

    static func projectedPointsSnapshot(
        previousBoard: BingoBoardStore.NamedBoard,
        updatedBoard: BingoBoardStore.NamedBoard,
        now: Date,
        didApplyBoardReset: Bool,
        currentPoints: PointsPersistenceSnapshot = PointsStore.loadPersistenceSnapshot()
    ) -> PointsPersistenceSnapshot {
        _ = didApplyBoardReset
        let previousCells = previousBoard.board.cells
        let previousCompletedLines = previousBoard.board.completedLines
        let initialTotalPoints = currentPoints.totalPoints ?? BoardEngine.boardScore(
            cells: previousCells,
            completedLines: previousCompletedLines
        )
        let initialLifetimePoints = currentPoints.lifetimePoints ?? initialTotalPoints

        let previousCompletedTaskCount = previousCells
            .flatMap { $0 }
            .filter { $0.isCompleted && !$0.isEmpty }
            .count
        let updatedCompletedTaskCount = updatedBoard.board.cells
            .flatMap { $0 }
            .filter { $0.isCompleted && !$0.isEmpty }
            .count
        let taskIsNowCompleted: Bool?
        if updatedCompletedTaskCount > previousCompletedTaskCount {
            taskIsNowCompleted = true
        } else if updatedCompletedTaskCount < previousCompletedTaskCount {
            taskIsNowCompleted = false
        } else {
            taskIsNowCompleted = nil
        }
        let output = BingoRewardSettlement.settleTaskToggle(
            date: now,
            previousCells: previousCells,
            previousCompletedLines: previousCompletedLines,
            previousIsBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(previousCells),
            currentCells: updatedBoard.board.cells,
            currentCompletedLines: updatedBoard.board.completedLines,
            currentIsBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(updatedBoard.board.cells),
            totalPoints: initialTotalPoints,
            lifetimePoints: initialLifetimePoints,
            dailyRewardState: currentPoints.dailyRewardState ?? BingoRewardSettlement.emptyDailyRewardState(for: now),
            taskIsNowCompleted: taskIsNowCompleted,
            minimumTotalPoints: PointRedemptionLedger.currentCommittedSpend()
        )
        return PointsPersistenceSnapshot(
            totalPoints: output.totalPoints,
            lifetimePoints: output.lifetimePoints,
            dailyRewardState: output.dailyRewardState
        )
    }

    private static func isLocked(
        row: Int,
        col: Int,
        in cells: [[BingoCell]],
        referenceDate: Date
    ) -> Bool {
        let activeForcedPositions = activeForcedPositions(in: cells, referenceDate: referenceDate)
        guard !activeForcedPositions.isEmpty else { return false }
        return !activeForcedPositions.contains(Position(row: row, col: col))
    }

    private static func activeForcedPositions(
        in cells: [[BingoCell]],
        referenceDate: Date
    ) -> Set<Position> {
        var positions: Set<Position> = []

        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                if cell.isForced && !cell.isCompleted && !cell.isEmpty && cell.isCurrentlyTappable(on: referenceDate) {
                    positions.insert(Position(row: row, col: col))
                }
            }
        }

        return positions
    }

    private static func registerCompletionIfNeeded(cell: inout BingoCell, now: Date) {
        cell.completionStreakCount += 1
        cell.lastCompletedAt = now
    }

    private static func synchronizeCompletionHistoryCount(
        taskText: String,
        count: Int,
        in cells: inout [[BingoCell]]
    ) {
        guard let key = TaskCompletionHistoryRuleEngine.normalizedKey(for: taskText) else { return }
        for row in cells.indices {
            for col in cells[row].indices where
                TaskCompletionHistoryRuleEngine.normalizedKey(for: cells[row][col].storedTaskText) == key {
                cells[row][col].completionStreakCount = count
            }
        }
    }

    private static func settleRewards(
        previousBoard: SavedBoard,
        updatedBoard: SavedBoard,
        boardLastSavedAt: Date,
        now: Date,
        didApplyBoardReset: Bool
    ) -> Bool {
        let previousNamedBoard = BingoBoardStore.NamedBoard(
            name: "",
            board: previousBoard,
            updatedAt: boardLastSavedAt
        )
        let updatedNamedBoard = BingoBoardStore.NamedBoard(
            id: previousNamedBoard.id,
            name: "",
            board: updatedBoard,
            updatedAt: now
        )
        let projected = projectedPointsSnapshot(
            previousBoard: previousNamedBoard,
            updatedBoard: updatedNamedBoard,
            now: now,
            didApplyBoardReset: didApplyBoardReset
        )
        guard let totalPoints = projected.totalPoints,
              let lifetimePoints = projected.lifetimePoints,
              let dailyRewardState = projected.dailyRewardState else { return false }
        return PointsStore.saveState(
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState
        )
    }
}
