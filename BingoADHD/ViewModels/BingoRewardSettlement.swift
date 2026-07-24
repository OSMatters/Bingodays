import Foundation

enum BingoRewardSettlementMode {
    case normal
    case preserveAccumulatedPoints
}

struct BingoRewardSettlementInput {
    var date: Date
    var cells: [[BingoCell]]
    var completedLines: Set<BingoLine>
    var isBoardFullyCompleted: Bool
    var totalPoints: Int
    var lifetimePoints: Int
    var dailyRewardState: DailyRewardState
}

struct BingoRewardSettlementOutput {
    var totalPoints: Int
    var lifetimePoints: Int
    var dailyRewardState: DailyRewardState
}

enum BingoRewardSettlement {
    static func settle(
        input: BingoRewardSettlementInput,
        mode: BingoRewardSettlementMode
    ) -> BingoRewardSettlementOutput {
        // `DailyRewardState` is a local anti-duplication cache, not an account
        // ledger. A repair, board switch, widget recovery, or cloud projection can
        // legitimately rebuild it from a completed board. Treating that rebuild as
        // a reward event re-awards the whole board (for example +27) without any
        // user action. Only an explicit before/after completion transition may
        // change the durable point counters.
        _ = mode
        var dailyRewardState = rewardStateResetIfNeeded(input.dailyRewardState, for: input.date)

        let completedCellIDs = Set(
            input.cells
                .flatMap { $0 }
                .filter { $0.isCompleted && !$0.isEmpty }
                .map(\.id)
        )
        let newLineCount = input.completedLines.count
        let newFullBoardRewardGranted = input.isBoardFullyCompleted

        dailyRewardState.rewardedCellIDs = completedCellIDs
        dailyRewardState.peakCompletedLineCount = newLineCount
        dailyRewardState.fullBoardRewardGranted = newFullBoardRewardGranted

        return BingoRewardSettlementOutput(
            totalPoints: input.totalPoints,
            lifetimePoints: input.lifetimePoints,
            dailyRewardState: dailyRewardState
        )
    }

    /// A completion tap has an unambiguous before/after board state. Settle from that
    /// transition instead of a persisted daily ledger, which may temporarily lag a
    /// remote projection or a WidgetKit write. This keeps one task tap to one point
    /// movement (plus any line/full-board bonus) even while another device is syncing.
    static func settleTaskToggle(
        date: Date,
        previousCells: [[BingoCell]],
        previousCompletedLines: Set<BingoLine>,
        previousIsBoardFullyCompleted: Bool,
        currentCells: [[BingoCell]],
        currentCompletedLines: Set<BingoLine>,
        currentIsBoardFullyCompleted: Bool,
        totalPoints: Int,
        lifetimePoints: Int,
        dailyRewardState: DailyRewardState,
        taskIsNowCompleted: Bool? = nil
    ) -> BingoRewardSettlementOutput {
        let rawTaskDelta = completedTaskCount(in: currentCells) - completedTaskCount(in: previousCells)
        let taskDelta: Int
        if let taskIsNowCompleted {
            taskDelta = taskIsNowCompleted ? 1 : -1
        } else {
            taskDelta = rawTaskDelta
        }

        let rawLineDelta = currentCompletedLines.count - previousCompletedLines.count
        let lineDelta: Int
        if taskIsNowCompleted == true {
            // A completion can create lines but can never revoke them. If an
            // imported/stale board cache says otherwise, preserve the user's tap.
            lineDelta = max(rawLineDelta, 0)
        } else if taskIsNowCompleted == false {
            // Symmetrically, an undo can revoke lines but can never create them.
            lineDelta = min(rawLineDelta, 0)
        } else {
            lineDelta = rawLineDelta
        }

        let rawFullBoardDelta = (currentIsBoardFullyCompleted ? 1 : 0) -
            (previousIsBoardFullyCompleted ? 1 : 0)
        let fullBoardDelta: Int
        if taskIsNowCompleted == true {
            fullBoardDelta = max(rawFullBoardDelta, 0)
        } else if taskIsNowCompleted == false {
            fullBoardDelta = min(rawFullBoardDelta, 0)
        } else {
            fullBoardDelta = rawFullBoardDelta
        }

        let delta = taskDelta + (lineDelta * 5) + (fullBoardDelta * 10)
        let currentDailyRewardState = dailyRewardSnapshot(
            for: date,
            cells: currentCells,
            completedLines: currentCompletedLines,
            isBoardFullyCompleted: currentIsBoardFullyCompleted
        )

        return BingoRewardSettlementOutput(
            totalPoints: max(totalPoints + delta, 0),
            lifetimePoints: lifetimePoints + max(delta, 0),
            dailyRewardState: currentDailyRewardState
        )
    }

    /// System actions such as an expired countdown can complete more than one
    /// task at once. They still carry a concrete before/after board transition,
    /// so settle that transition directly rather than reconstructing points from a
    /// daily cache.
    static func settleBoardTransition(
        date: Date,
        previousCells: [[BingoCell]],
        previousCompletedLines: Set<BingoLine>,
        previousIsBoardFullyCompleted: Bool,
        currentCells: [[BingoCell]],
        currentCompletedLines: Set<BingoLine>,
        currentIsBoardFullyCompleted: Bool,
        totalPoints: Int,
        lifetimePoints: Int,
        dailyRewardState: DailyRewardState
    ) -> BingoRewardSettlementOutput {
        settleTaskToggle(
            date: date,
            previousCells: previousCells,
            previousCompletedLines: previousCompletedLines,
            previousIsBoardFullyCompleted: previousIsBoardFullyCompleted,
            currentCells: currentCells,
            currentCompletedLines: currentCompletedLines,
            currentIsBoardFullyCompleted: currentIsBoardFullyCompleted,
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState,
            taskIsNowCompleted: nil
        )
    }

    static func initialDailyRewardState(
        referenceDate: Date,
        boardLastSavedAt: Date?,
        currentCells: [[BingoCell]],
        currentCompletedLines: Set<BingoLine>,
        isBoardFullyCompleted: Bool,
        savedDailyRewardState: DailyRewardState? = PointsStore.loadDailyRewardState()
    ) -> DailyRewardState {
        let todayKey = PointsStore.dateKey(for: referenceDate)
        if let savedState = savedDailyRewardState,
           savedState.dateKey == todayKey,
           isRewardState(
                savedState,
                compatibleWith: currentCells,
                completedLines: currentCompletedLines,
                isBoardFullyCompleted: isBoardFullyCompleted
           ) {
            return savedState
        }

        let calendar = Calendar.current
        let shouldSeedFromCurrentBoard: Bool
        if let boardLastSavedAt {
            shouldSeedFromCurrentBoard = calendar.isDate(boardLastSavedAt, inSameDayAs: referenceDate)
        } else {
            shouldSeedFromCurrentBoard = false
        }

        guard shouldSeedFromCurrentBoard else {
            return emptyDailyRewardState(for: referenceDate)
        }

        return dailyRewardSnapshot(
            for: referenceDate,
            cells: currentCells,
            completedLines: currentCompletedLines,
            isBoardFullyCompleted: isBoardFullyCompleted
        )
    }

    static func dailyRewardSnapshot(
        for date: Date,
        cells: [[BingoCell]],
        completedLines: Set<BingoLine>,
        isBoardFullyCompleted: Bool
    ) -> DailyRewardState {
        let rewardedCellIDs = Set(
            cells
                .flatMap { $0 }
                .filter { $0.isCompleted && !$0.isEmpty }
                .map(\.id)
        )

        return DailyRewardState(
            dateKey: PointsStore.dateKey(for: date),
            rewardedCellIDs: rewardedCellIDs,
            peakCompletedLineCount: completedLines.count,
            fullBoardRewardGranted: isBoardFullyCompleted
        )
    }

    static func emptyDailyRewardState(for date: Date) -> DailyRewardState {
        DailyRewardState(dateKey: PointsStore.dateKey(for: date))
    }

    private static func isRewardState(
        _ state: DailyRewardState,
        compatibleWith cells: [[BingoCell]],
        completedLines: Set<BingoLine>,
        isBoardFullyCompleted: Bool
    ) -> Bool {
        let completedCellIDs = Set(
            cells
                .flatMap { $0 }
                .filter { $0.isCompleted && !$0.isEmpty }
                .map(\.id)
        )
        return state.rewardedCellIDs == completedCellIDs &&
            state.peakCompletedLineCount == completedLines.count &&
            state.fullBoardRewardGranted == isBoardFullyCompleted
    }

    private static func rewardStateResetIfNeeded(
        _ state: DailyRewardState,
        for date: Date
    ) -> DailyRewardState {
        let dateKey = PointsStore.dateKey(for: date)
        guard state.dateKey != dateKey else { return state }
        return emptyDailyRewardState(for: date)
    }

    private static func completedTaskCount(in cells: [[BingoCell]]) -> Int {
        cells
            .flatMap { $0 }
            .filter { $0.isCompleted && !$0.isEmpty }
            .count
    }
}
