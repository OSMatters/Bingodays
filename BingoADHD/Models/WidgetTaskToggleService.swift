import Foundation

enum WidgetTaskToggleService {
    private static let maxGridSize = BoardEngine.maxGridSize

    private struct Position: Hashable {
        let row: Int
        let col: Int
    }

    static func toggled(
        board namedBoard: BingoBoardStore.NamedBoard,
        row: Int,
        col: Int,
        now: Date
    ) -> BingoBoardStore.NamedBoard? {
        let preparedBoard = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(namedBoard, now: now)
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

        let diaryTaskText = fullBoard[row][col].storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)

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

        let updatedVisibleCells = BoardEngine.projectVisibleCells(from: fullBoard, size: gridSize, referenceDate: now)
        let completedLines = BoardEngine.completedLines(in: updatedVisibleCells, size: gridSize)
        let updatedSavedBoard = SavedBoard(
            gridSize: gridSize,
            cells: updatedVisibleCells,
            completedLines: completedLines,
            fullBoardCells: fullBoard
        )

        settleRewards(
            previousBoard: preparedBoard.board,
            updatedBoard: updatedSavedBoard,
            boardLastSavedAt: preparedBoard.updatedAt,
            now: now
        )
        BingoDiaryStore.applyExplicitTaskDelta(
            task: diaryTaskText,
            delta: isNowCompleted ? 1 : -1,
            board: updatedSavedBoard,
            on: now
        )

        var updatedNamedBoard = preparedBoard
        updatedNamedBoard.board = updatedSavedBoard
        updatedNamedBoard.lastTaskResetAppliedAt = now
        updatedNamedBoard.updatedAt = now
        return updatedNamedBoard
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
        let calendar = Calendar.current
        if let lastCompletedAt = cell.lastCompletedAt,
           calendar.isDate(lastCompletedAt, inSameDayAs: now) {
            cell.lastCompletedAt = now
            return
        }

        cell.completionStreakCount += 1
        cell.lastCompletedAt = now
    }

    private static func settleRewards(
        previousBoard: SavedBoard,
        updatedBoard: SavedBoard,
        boardLastSavedAt: Date,
        now: Date
    ) {
        let previousCells = previousBoard.cells
        let previousCompletedLines = previousBoard.completedLines
        let initialTotalPoints = PointsStore.loadTotalPoints() ?? BoardEngine.boardScore(
            cells: previousCells,
            completedLines: previousCompletedLines
        )
        let initialLifetimePoints = PointsStore.loadLifetimePoints() ?? initialTotalPoints
        let initialDailyRewardState = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: now,
            boardLastSavedAt: boardLastSavedAt,
            currentCells: previousCells,
            currentCompletedLines: previousCompletedLines,
            isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(previousCells),
            savedDailyRewardState: PointsStore.loadDailyRewardState()
        )

        let output = BingoRewardSettlement.settle(
            input: BingoRewardSettlementInput(
                date: now,
                cells: updatedBoard.cells,
                completedLines: updatedBoard.completedLines,
                isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(updatedBoard.cells),
                totalPoints: initialTotalPoints,
                lifetimePoints: initialLifetimePoints,
                dailyRewardState: initialDailyRewardState
            ),
            mode: .normal
        )

        PointsStore.saveTotalPoints(output.totalPoints)
        PointsStore.saveLifetimePoints(output.lifetimePoints)
        PointsStore.saveDailyRewardState(output.dailyRewardState)
        PointRedemptionReconciler.reconcilePersistedRedemptionsIfNeeded(totalPoints: output.totalPoints)
    }
}
