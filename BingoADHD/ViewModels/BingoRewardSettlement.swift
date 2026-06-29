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
        // Settlement compares today's board snapshot with the last rewarded snapshot so repeated saves stay idempotent.
        var totalPoints = input.totalPoints
        var lifetimePoints = input.lifetimePoints
        var dailyRewardState = rewardStateResetIfNeeded(input.dailyRewardState, for: input.date)

        let completedCellIDs = Set(
            input.cells
                .flatMap { $0 }
                .filter { $0.isCompleted && !$0.isEmpty }
                .map(\.id)
        )
        let newLineCount = input.completedLines.count
        let newFullBoardRewardGranted = input.isBoardFullyCompleted

        let previousPoints = dailyRewardState.rewardedCellIDs.count
            + (dailyRewardState.peakCompletedLineCount * 5)
            + (dailyRewardState.fullBoardRewardGranted ? 10 : 0)
        let currentBoardPoints = completedCellIDs.count
            + (newLineCount * 5)
            + (newFullBoardRewardGranted ? 10 : 0)

        if mode == .normal {
            let delta = currentBoardPoints - previousPoints
            if delta != 0 {
                totalPoints = max(totalPoints + delta, 0)
                if delta > 0 {
                    lifetimePoints += delta
                }
            }
        }

        dailyRewardState.rewardedCellIDs = completedCellIDs
        dailyRewardState.peakCompletedLineCount = newLineCount
        dailyRewardState.fullBoardRewardGranted = newFullBoardRewardGranted

        return BingoRewardSettlementOutput(
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState
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
           isRewardState(savedState, compatibleWith: currentCells) {
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
        compatibleWith cells: [[BingoCell]]
    ) -> Bool {
        guard !state.rewardedCellIDs.isEmpty else { return true }
        let currentCellIDs = Set(cells.flatMap { $0 }.map(\.id))
        return state.rewardedCellIDs.isSubset(of: currentCellIDs)
    }

    private static func rewardStateResetIfNeeded(
        _ state: DailyRewardState,
        for date: Date
    ) -> DailyRewardState {
        let dateKey = PointsStore.dateKey(for: date)
        guard state.dateKey != dateKey else { return state }
        return emptyDailyRewardState(for: date)
    }
}
