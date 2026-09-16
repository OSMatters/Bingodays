import Foundation

struct BoardResetResult {
    let didReset: Bool
    let didResetActiveBoard: Bool
    let clearedCompletedTaskCount: Int
    let removedCompletedSingleTaskCount: Int

    static let noReset = BoardResetResult(
        didReset: false,
        didResetActiveBoard: false,
        clearedCompletedTaskCount: 0,
        removedCompletedSingleTaskCount: 0
    )
}

struct BoardResetDebugConfiguration {
    let simulateNextDayReset: Bool
    let prepareStreakTest: Bool
    let showCustomResetToast: Bool
}

struct BoardResetCoordinator {
    private(set) var namedBoards: [BingoBoardStore.NamedBoard]
    private(set) var lastEvaluationDateKey: String
    private(set) var hasAppliedDebugSimulatedResetThisLaunch: Bool
    private(set) var lastCustomResetDebugToastKey: String
    private(set) var debugLogs: [String] = []
    private(set) var resetDebugToasts: [String] = []
    private(set) var customResetDebugToasts: [String] = []

    private let selectedBoardID: UUID?
    private let debugConfiguration: BoardResetDebugConfiguration

    init(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        lastEvaluationDateKey: String,
        hasAppliedDebugSimulatedResetThisLaunch: Bool,
        lastCustomResetDebugToastKey: String,
        debugConfiguration: BoardResetDebugConfiguration
    ) {
        self.namedBoards = namedBoards
        self.selectedBoardID = selectedBoardID
        self.lastEvaluationDateKey = lastEvaluationDateKey
        self.hasAppliedDebugSimulatedResetThisLaunch = hasAppliedDebugSimulatedResetThisLaunch
        self.lastCustomResetDebugToastKey = lastCustomResetDebugToastKey
        self.debugConfiguration = debugConfiguration
    }

    mutating func evaluate(
        now: Date = .now,
        force: Bool = false,
        source: String = "unknown",
        prepareBoardsForReset: (() -> [BingoBoardStore.NamedBoard])? = nil
    ) -> BoardResetResult {
        debugLog(
            "evaluate.enter source=\(source) force=\(force) day=\(PointsStore.dateKey(for: now)) " +
            "lastEval=\(lastEvaluationDateKey) boards=\(namedBoards.count) " +
            "simulateFlag=\(debugConfiguration.simulateNextDayReset) simulatedThisLaunch=\(hasAppliedDebugSimulatedResetThisLaunch)"
        )
        guard !namedBoards.isEmpty else {
            debugToast("no boards")
            return .noReset
        }

        let dayKey = PointsStore.dateKey(for: now)
        let hasPendingCustomReset = hasPendingCustomTimeReset(at: now)
        if !force, dayKey == lastEvaluationDateKey, !hasPendingCustomReset {
            #if DEBUG
            if debugConfiguration.simulateNextDayReset,
               !hasAppliedDebugSimulatedResetThisLaunch {
                debugToast("same-day gate -> trigger simulate")
                return forceApplyForDebug(now: now) ?? .noReset
            }
            #endif
            if source != "ticker" {
                debugToast("skip by same-day gate (\(dayKey))")
            } else {
                debugLog("evaluate.skip source=ticker same-day gate day=\(dayKey)")
            }
            return .noReset
        }

        debugToast("evaluate day=\(dayKey), force=\(force)")
        lastEvaluationDateKey = dayKey
        if let prepareBoardsForReset {
            namedBoards = prepareBoardsForReset()
        }
        return applyBoardTaskResetRules(now: now, source: source)
    }

    mutating func forceApplyForDebug(now: Date) -> BoardResetResult? {
        #if DEBUG
        guard debugConfiguration.simulateNextDayReset else {
            debugLog("simulate.skip reason=flag_off")
            return nil
        }
        guard !hasAppliedDebugSimulatedResetThisLaunch else {
            debugToast("simulate skipped: already applied in this launch")
            return nil
        }
        guard !namedBoards.isEmpty else {
            debugToast("simulate skipped: no boards loaded")
            return nil
        }

        debugToast("simulate next-day reset")
        hasAppliedDebugSimulatedResetThisLaunch = true
        let calendar = Calendar.current
        let simulatedPreviousDay = calendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)

        if debugConfiguration.prepareStreakTest {
            let shiftedCount = backdateCompletionDatesForDebug(
                to: simulatedPreviousDay,
                referenceDate: now
            )
            debugToast("simulate streak-ready shifted=\(shiftedCount)")
        }

        for index in namedBoards.indices {
            namedBoards[index].lastTaskResetAppliedAt = simulatedPreviousDay
        }

        lastEvaluationDateKey = ""
        return evaluate(now: now, force: true, source: "simulate")
        #else
        _ = now
        return nil
        #endif
    }

    private mutating func backdateCompletionDatesForDebug(
        to simulatedPreviousDay: Date,
        referenceDate: Date
    ) -> Int {
        #if DEBUG
        let maxGridSize = BingoViewModel.maxGridSize
        var shiftedCount = 0

        for index in namedBoards.indices {
            let board = namedBoards[index].board
            var fullBoard = BoardEngine.expandedBoardCache(from: board, maxSize: maxGridSize)
            var didUpdateBoard = false

            for row in fullBoard.indices {
                for col in fullBoard[row].indices {
                    guard fullBoard[row][col].hasStoredTask else { continue }
                    let shouldBackdate =
                        fullBoard[row][col].isCompleted ||
                        fullBoard[row][col].completionStreakCount > 0 ||
                        fullBoard[row][col].lastCompletedAt != nil
                    guard shouldBackdate else { continue }
                    fullBoard[row][col].lastCompletedAt = simulatedPreviousDay
                    shiftedCount += 1
                    didUpdateBoard = true
                }
            }

            guard didUpdateBoard else { continue }
            let gridSize = min(max(board.gridSize, 2), maxGridSize)
            let visibleCells: [[BingoCell]] = (0..<gridSize).map { row in
                (0..<gridSize).map { col in
                    fullBoard[row][col].projectedForDisplay(on: referenceDate)
                }
            }
            namedBoards[index].board = SavedBoard(
                gridSize: gridSize,
                cells: visibleCells,
                completedLines: board.completedLines,
                fullBoardCells: fullBoard
            )
        }

        return shiftedCount
        #else
        _ = simulatedPreviousDay
        _ = referenceDate
        return 0
        #endif
    }

    private mutating func applyBoardTaskResetRules(now: Date, source: String) -> BoardResetResult {
        guard !namedBoards.isEmpty else { return .noReset }

        let calendar = Calendar.current
        let activeBoardID = selectedBoardID ?? namedBoards.first?.id
        var hasAnyUpdate = false
        var appliedCount = 0
        var skippedCount = 0
        var staleForceCount = 0
        var didResetActiveBoard = false
        var activeBoardClearedCompletedTaskCount = 0
        var activeBoardRemovedCompletedSingleTaskCount = 0

        for index in namedBoards.indices {
            let board = namedBoards[index]
            let resetEvaluation = BoardResetRuleEngine.pendingResetEvaluation(
                for: board,
                now: now,
                calendar: calendar
            )
            showCustomResetDebugToastIfNeeded(
                board: board,
                now: now,
                calendar: calendar,
                didHit: resetEvaluation.customResetDue
            )
            debugLog(
                "apply.inspect source=\(source) board=\(index) mode=\(board.taskResetMode.rawValue) " +
                "customMinutes=\(board.customResetMinutes?.description ?? "nil") " +
                "usesCustomResetTime=\(resetEvaluation.usesCustomResetTime) customResetDue=\(resetEvaluation.customResetDue) " +
                "alreadyAppliedToday=\(resetEvaluation.alreadyAppliedToday) shouldApplyBySchedule=\(resetEvaluation.shouldApplyBySchedule) " +
                "staleForce=\(resetEvaluation.shouldForceApplyForStaleCompletion) " +
                "completedCount=\(BoardResetRuleEngine.completedTaskCount(in: board)) lastApplied=\(board.lastTaskResetAppliedAt?.description ?? "nil")"
            )

            if !resetEvaluation.shouldApply {
                skippedCount += 1
                continue
            }
            if resetEvaluation.shouldForceApplyForStaleCompletion {
                staleForceCount += 1
            }

            guard TaskCompletionHistoryStore.archiveTasksRemovedByReset(from: board, at: now) else {
                // Keep this board untouched so the next lifecycle evaluation can
                // retry without losing a completion count.
                debugLog("apply.skip_history_save_failed source=\(source) board=\(index)")
                DiagnosticLogStore.recordWarning(
                    "board_reset.history_archive_failed",
                    details: [
                        "board_id": String(board.id.uuidString.prefix(8)),
                        "source": source,
                        "mode": board.taskResetMode.rawValue
                    ]
                )
                continue
            }

            let taskCells = BoardEngine.expandedBoardCache(from: board.board)
                .flatMap { $0 }
                .filter(\.hasStoredTask)
            var preservedTaskCount = 0
            var removedTaskCount = 0
            var resetCompletionTaskCount = 0
            var removedCompletedSingleTaskCount = 0
            for cell in taskCells {
                let action = TaskLifecycleRuleEngine.dailySettlementAction(
                    for: cell,
                    mode: board.taskResetMode
                )
                switch action {
                case .preserve:
                    preservedTaskCount += 1
                case .remove:
                    DiagnosticLogStore.recordStateChange("board_reset.task_removal_evaluated", details: [
                        "board_id": String(board.id.uuidString.prefix(8)),
                        "cell_id": String(cell.id.uuidString.prefix(8)),
                        "rule": cell.diagnosticTaskRuleKind,
                        "completed": String(cell.isCompleted),
                        "mode": board.taskResetMode.rawValue,
                        "source": source,
                        "custom_minutes": board.customResetMinutes.map(String.init) ?? "0",
                        "timezone": TimeZone.current.identifier,
                        "previous_reset": board.lastTaskResetAppliedAt.map { String($0.timeIntervalSince1970) } ?? "none",
                        "evaluated_at": String(now.timeIntervalSince1970)
                    ])
                    removedTaskCount += 1
                    if cell.isCompleted, !cell.hasRepeatingSchedule {
                        removedCompletedSingleTaskCount += 1
                    }
                case .resetCompletion:
                    resetCompletionTaskCount += 1
                }
            }
            let clearedCompletedCount = BoardResetRuleEngine.completedTaskCount(in: board)
            let transformedBoard = BoardResetRuleEngine.transformedBoardSnapshotForResetMode(
                board.board,
                mode: board.taskResetMode,
                referenceDate: now
            )

            namedBoards[index].board = transformedBoard
            namedBoards[index].countdownEndsAt = nil
            namedBoards[index].lastTaskResetAppliedAt = now
            namedBoards[index].updatedAt = now
            if board.id == activeBoardID {
                didResetActiveBoard = true
                activeBoardClearedCompletedTaskCount = clearedCompletedCount
                activeBoardRemovedCompletedSingleTaskCount = removedCompletedSingleTaskCount
            }
            hasAnyUpdate = true
            appliedCount += 1
            DiagnosticLogStore.recordStateChange(
                "board_reset.applied",
                details: [
                    "board_id": String(board.id.uuidString.prefix(8)),
                    "source": source,
                    "mode": board.taskResetMode.rawValue,
                    "custom_minutes": board.customResetMinutes.map(String.init) ?? "none",
                    "task_count": "\(taskCells.count)",
                    "completed_before": "\(clearedCompletedCount)",
                    "preserved": "\(preservedTaskCount)",
                    "removed": "\(removedTaskCount)",
                    "removed_completed_single": "\(removedCompletedSingleTaskCount)",
                    "reset_completion": "\(resetCompletionTaskCount)",
                    "stale_force": "\(resetEvaluation.shouldForceApplyForStaleCompletion)"
                ]
            )
        }

        guard hasAnyUpdate else {
            debugToast("no reset applied, skipped=\(skippedCount)")
            return .noReset
        }

        debugToast("reset applied=\(appliedCount), staleForce=\(staleForceCount), skipped=\(skippedCount)")
        return BoardResetResult(
            didReset: true,
            didResetActiveBoard: didResetActiveBoard,
            clearedCompletedTaskCount: activeBoardClearedCompletedTaskCount,
            removedCompletedSingleTaskCount: activeBoardRemovedCompletedSingleTaskCount
        )
    }

    private mutating func hasPendingCustomTimeReset(at now: Date, calendar: Calendar = .current) -> Bool {
        for board in namedBoards {
            if BoardResetRuleEngine.pendingResetEvaluation(for: board, now: now, calendar: calendar).customResetDue {
                return true
            }
        }
        return false
    }

    private mutating func debugLog(_ message: String) {
        #if DEBUG
        debugLogs.append(message)
        #else
        _ = message
        #endif
    }

    private mutating func showCustomResetDebugToastIfNeeded(
        board: BingoBoardStore.NamedBoard,
        now: Date,
        calendar: Calendar,
        didHit: Bool
    ) {
        #if DEBUG
        guard debugConfiguration.showCustomResetToast else { return }
        guard let triggerTime = BoardResetRuleEngine.customResetTriggerTime(
            for: board,
            now: now,
            calendar: calendar
        ) else { return }
        showCustomResetDebugToast(
            boardName: board.name,
            triggerTime: triggerTime,
            didHit: didHit,
            now: now
        )
        #else
        _ = board
        _ = now
        _ = calendar
        _ = didHit
        #endif
    }

    private mutating func debugToast(_ message: String) {
        #if DEBUG
        debugLogs.append(message)
        guard debugConfiguration.simulateNextDayReset else { return }
        resetDebugToasts.append(message)
        #else
        _ = message
        #endif
    }

    private mutating func showCustomResetDebugToast(
        boardName: String,
        triggerTime: Date,
        didHit: Bool,
        now: Date
    ) {
        #if DEBUG
        guard debugConfiguration.showCustomResetToast else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        let trigger = formatter.string(from: triggerTime)
        let current = formatter.string(from: now)
        let hit = didHit ? "YES" : "NO"
        let key = "\(boardName)|\(trigger)|\(current)|\(hit)|\(PointsStore.dateKey(for: now))"
        guard key != lastCustomResetDebugToastKey else { return }
        lastCustomResetDebugToastKey = key
        customResetDebugToasts.append("DEBUG custom reset [\(boardName)] trigger \(trigger), now \(current), hit=\(hit)")
        #else
        _ = boardName
        _ = triggerTime
        _ = didHit
        _ = now
        #endif
    }

}
