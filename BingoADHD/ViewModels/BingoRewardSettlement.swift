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
    var taskRewardReceipts: [UUID: TaskRewardReceipt] = [:]
}

enum BingoRewardSettlement {
    static func settle(
        input: BingoRewardSettlementInput,
        mode: BingoRewardSettlementMode
    ) -> BingoRewardSettlementOutput {
        // Daily display/reversal fields are a local anti-duplication cache. The
        // optional pointSyncLedger is carried through without recording a reward.
        // A repair, board switch, widget recovery, or cloud projection can
        // legitimately rebuild it from a completed board. Treating that rebuild as
        // a reward event re-awards the whole board (for example +27) without any
        // user action. Only an explicit before/after completion transition may
        // change the durable point counters.
        _ = mode
        var dailyRewardState = rewardStateResetIfNeeded(input.dailyRewardState, for: input.date)

        let completedCellIDs = completedCellIDs(in: input.cells)

        dailyRewardState.rewardedCellIDs = completedCellIDs
        dailyRewardState.peakCompletedLineCount = max(
            dailyRewardState.peakCompletedLineCount,
            input.completedLines.count
        )
        dailyRewardState.fullBoardRewardGranted =
            dailyRewardState.fullBoardRewardGranted || input.isBoardFullyCompleted

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
        taskIsNowCompleted: Bool? = nil,
        minimumTotalPoints: Int = 0,
        syncCycleKey: String? = nil
    ) -> BingoRewardSettlementOutput {
        var currentDailyRewardState = rewardStateResetIfNeeded(dailyRewardState, for: date)
        let pointsFloor = max(minimumTotalPoints, 0)
        var updatedTotalPoints = max(totalPoints, pointsFloor)
        var updatedLifetimePoints = lifetimePoints
        var receipts: [UUID: TaskRewardReceipt] = [:]
        var syncLedger = currentDailyRewardState.pointSyncLedger
        if syncLedger?.matches(total: totalPoints, lifetime: lifetimePoints) != true {
            syncLedger = PointSyncLedger(total: totalPoints, lifetime: lifetimePoints)
        }
        let cycle = syncCycleKey ?? currentDailyRewardState.dateKey
        let previousTasks = Dictionary(previousCells.flatMap { $0 }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentTasks = Dictionary(currentCells.flatMap { $0 }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let previousCompletedCellIDs = completedCellIDs(in: previousCells)
        let currentCompletedCellIDs = completedCellIDs(in: currentCells)

        for cellID in currentCompletedCellIDs.subtracting(previousCompletedCellIDs).sorted(by: stableOrder) {
            let beforeTotal = updatedTotalPoints, beforeLifetime = updatedLifetimePoints
            let key = cellID.uuidString.lowercased()
            if let previous = previousTasks[cellID], let current = currentTasks[cellID],
               TaskCompletionRewardRules.usesCustomSettlement(previous: previous, current: current) {
                let legacyCredit = currentDailyRewardState.taskReversalCredits.removeValue(forKey: key)
                let result = TaskCompletionRewardRules.transition(
                    previous: previous, current: current, dateKey: currentDailyRewardState.dateKey,
                    availableToDeduct: max(updatedTotalPoints - pointsFloor, 0),
                    legacyReversalCredit: previous.taskRewardReceipt == nil && previous.customCompletionPoints == nil ? legacyCredit : nil
                )
                updatedTotalPoints += result.pointsDelta
                updatedLifetimePoints += result.lifetimeDelta
                receipts[cellID] = result.receipt
            } else if let restoredPoints = currentDailyRewardState.taskReversalCredits.removeValue(forKey: key) {
                updatedTotalPoints += max(restoredPoints, 0)
                updatedLifetimePoints += max(restoredPoints, 0)
            } else {
                updatedTotalPoints += 1
                updatedLifetimePoints += 1
            }
            syncLedger?.record(PointSyncLedger.taskSource(cellID, cycle: cycle), totalDelta: updatedTotalPoints - beforeTotal,
                lifetimeDelta: updatedLifetimePoints - beforeLifetime, completed: true, at: date)
        }

        for cellID in previousCompletedCellIDs.subtracting(currentCompletedCellIDs).sorted(by: stableOrder) {
            let beforeTotal = updatedTotalPoints, beforeLifetime = updatedLifetimePoints
            let key = cellID.uuidString.lowercased()
            // A system transition may remove the task entirely. Its original
            // receipt still determines the deduction; no replacement task owns it.
            var removedTask = previousTasks[cellID]
            removedTask?.isCompleted = false
            if let previous = previousTasks[cellID], let current = currentTasks[cellID] ?? removedTask,
               TaskCompletionRewardRules.usesCustomSettlement(previous: previous, current: current) {
                let result = TaskCompletionRewardRules.transition(
                    previous: previous, current: current, dateKey: currentDailyRewardState.dateKey,
                    availableToDeduct: max(updatedTotalPoints - pointsFloor, 0),
                    legacyReversalCredit: nil
                )
                updatedTotalPoints += result.pointsDelta
                receipts[cellID] = result.receipt
                currentDailyRewardState.taskReversalCredits.removeValue(forKey: key)
            } else {
                currentDailyRewardState.taskReversalCredits[key] = deduct(
                    1, from: &updatedTotalPoints, minimumTotalPoints: pointsFloor
                )
            }
            syncLedger?.record(PointSyncLedger.taskSource(cellID, cycle: cycle), totalDelta: updatedTotalPoints - beforeTotal,
                lifetimeDelta: updatedLifetimePoints - beforeLifetime, completed: false, at: date)
        }

        let restoredLines: Set<BingoLine>
        let undoneLines: Set<BingoLine>
        if taskIsNowCompleted == true {
            restoredLines = currentCompletedLines.subtracting(previousCompletedLines)
            undoneLines = []
        } else if taskIsNowCompleted == false {
            restoredLines = []
            undoneLines = previousCompletedLines.subtracting(currentCompletedLines)
        } else {
            restoredLines = currentCompletedLines.subtracting(previousCompletedLines)
            undoneLines = previousCompletedLines.subtracting(currentCompletedLines)
        }

        for line in restoredLines.sorted(by: stableLineOrder) {
            let beforeTotal = updatedTotalPoints, beforeLifetime = updatedLifetimePoints
            let key = lineRewardSourceID(line, cells: currentCells)
            if let restoredPoints = currentDailyRewardState.lineReversalCredits.removeValue(forKey: key) {
                updatedTotalPoints += max(restoredPoints, 0)
                updatedLifetimePoints += max(restoredPoints, 0)
            } else {
                updatedTotalPoints += 5
                updatedLifetimePoints += 5
            }
            syncLedger?.record(cycle + "/line/" + key, totalDelta: updatedTotalPoints - beforeTotal,
                lifetimeDelta: updatedLifetimePoints - beforeLifetime, completed: true, at: date)
        }

        for line in undoneLines.sorted(by: stableLineOrder) {
            let beforeTotal = updatedTotalPoints, beforeLifetime = updatedLifetimePoints
            let key = lineRewardSourceID(line, cells: previousCells)
            currentDailyRewardState.lineReversalCredits[key] = deduct(
                5,
                from: &updatedTotalPoints,
                minimumTotalPoints: pointsFloor
            )
            syncLedger?.record(cycle + "/line/" + key, totalDelta: updatedTotalPoints - beforeTotal,
                lifetimeDelta: updatedLifetimePoints - beforeLifetime, completed: false, at: date)
        }

        if taskIsNowCompleted != false,
           currentIsBoardFullyCompleted && !previousIsBoardFullyCompleted {
            let beforeTotal = updatedTotalPoints, beforeLifetime = updatedLifetimePoints
            let key = fullBoardRewardSourceID(cells: currentCells)
            if let restoredPoints = currentDailyRewardState.fullBoardReversalCredits.removeValue(forKey: key) {
                updatedTotalPoints += max(restoredPoints, 0)
                updatedLifetimePoints += max(restoredPoints, 0)
            } else {
                updatedTotalPoints += 10
                updatedLifetimePoints += 10
            }
            syncLedger?.record(cycle + "/full/" + key, totalDelta: updatedTotalPoints - beforeTotal,
                lifetimeDelta: updatedLifetimePoints - beforeLifetime, completed: true, at: date)
        } else if taskIsNowCompleted != true,
                  !currentIsBoardFullyCompleted && previousIsBoardFullyCompleted {
            let beforeTotal = updatedTotalPoints
            let key = fullBoardRewardSourceID(cells: previousCells)
            currentDailyRewardState.fullBoardReversalCredits[key] = deduct(
                10,
                from: &updatedTotalPoints,
                minimumTotalPoints: pointsFloor
            )
            syncLedger?.record(cycle + "/full/" + key, totalDelta: updatedTotalPoints - beforeTotal,
                lifetimeDelta: 0, completed: false, at: date)
        }

        currentDailyRewardState.pointSyncLedger = syncLedger
        currentDailyRewardState.rewardedCellIDs = currentCompletedCellIDs
        currentDailyRewardState.peakCompletedLineCount = max(
            currentDailyRewardState.peakCompletedLineCount,
            currentCompletedLines.count
        )
        currentDailyRewardState.fullBoardRewardGranted =
            currentDailyRewardState.fullBoardRewardGranted || currentIsBoardFullyCompleted

        return BingoRewardSettlementOutput(
            totalPoints: updatedTotalPoints,
            lifetimePoints: updatedLifetimePoints,
            dailyRewardState: currentDailyRewardState,
            taskRewardReceipts: receipts
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
        dailyRewardState: DailyRewardState,
        minimumTotalPoints: Int = 0,
        syncCycleKey: String? = nil
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
            taskIsNowCompleted: nil,
            minimumTotalPoints: minimumTotalPoints,
            syncCycleKey: syncCycleKey
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
        if var savedState = savedDailyRewardState,
           savedState.dateKey == todayKey {
            // The board may differ after an undo, board switch, or CloudKit
            // refresh. Preserve the reversal credits for this reward day so a
            // re-completion can only restore what was actually deducted.
            savedState.rewardedCellIDs = completedCellIDs(in: currentCells)
            savedState.peakCompletedLineCount = max(
                savedState.peakCompletedLineCount,
                currentCompletedLines.count
            )
            savedState.fullBoardRewardGranted =
                savedState.fullBoardRewardGranted || isBoardFullyCompleted
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
            var result = emptyDailyRewardState(for: referenceDate)
            result.pointSyncLedger = savedDailyRewardState?.pointSyncLedger
            return result
        }

        var result = dailyRewardSnapshot(
            for: referenceDate,
            cells: currentCells,
            completedLines: currentCompletedLines,
            isBoardFullyCompleted: isBoardFullyCompleted
        )
        result.pointSyncLedger = savedDailyRewardState?.pointSyncLedger
        return result
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

    private static func rewardStateResetIfNeeded(
        _ state: DailyRewardState,
        for date: Date
    ) -> DailyRewardState {
        let dateKey = PointsStore.dateKey(for: date)
        guard state.dateKey != dateKey else { return state }
        var result = emptyDailyRewardState(for: date)
        result.pointSyncLedger = state.pointSyncLedger
        return result
    }

    private static func completedCellIDs(in cells: [[BingoCell]]) -> Set<UUID> {
        Set(cells
            .flatMap { $0 }
            .filter { $0.isCompleted && !$0.isEmpty }
            .map(\.id))
    }

    private static func deduct(
        _ requestedPoints: Int,
        from totalPoints: inout Int,
        minimumTotalPoints: Int
    ) -> Int {
        let availablePoints = max(totalPoints - minimumTotalPoints, 0)
        let deductedPoints = min(max(requestedPoints, 0), availablePoints)
        totalPoints -= deductedPoints
        return deductedPoints
    }

    private static func stableOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private static func stableLineOrder(_ lhs: BingoLine, _ rhs: BingoLine) -> Bool {
        lineToken(lhs) < lineToken(rhs)
    }

    static func lineRewardSourceID(_ line: BingoLine, cells: [[BingoCell]]) -> String {
        "\(boardRewardSourceID(cells: cells)):line:\(lineToken(line))"
    }

    static func fullBoardRewardSourceID(cells: [[BingoCell]]) -> String {
        "\(boardRewardSourceID(cells: cells)):full"
    }

    private static func boardRewardSourceID(cells: [[BingoCell]]) -> String {
        let cellIDs = cells
            .flatMap { $0 }
            .filter { !$0.isEmpty }
            .map { $0.id.uuidString.lowercased() }
            .sorted()
            .joined(separator: ",")
        return "board:\(cellIDs)"
    }

    private static func lineToken(_ line: BingoLine) -> String {
        switch line {
        case let .row(index): return "row-\(index)"
        case let .column(index): return "column-\(index)"
        case .diagonalMain: return "diagonal-main"
        case .diagonalAnti: return "diagonal-anti"
        }
    }
}
