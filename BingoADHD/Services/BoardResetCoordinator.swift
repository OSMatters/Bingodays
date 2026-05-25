import Foundation

struct BoardResetResult {
    let didReset: Bool
    let clearedCompletedTaskCount: Int

    static let noReset = BoardResetResult(
        didReset: false,
        clearedCompletedTaskCount: 0
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
        source: String = "unknown"
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
            var fullBoard = Self.expandedBoardCache(from: board, maxGridSize: maxGridSize)
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
        var activeBoardClearedCompletedTaskCount = 0

        for index in namedBoards.indices {
            let board = namedBoards[index]
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
                Self.boardHasStaleCompletedTasks(board, referenceDate: now, calendar: calendar)
            debugLog(
                "apply.inspect source=\(source) board=\(index) mode=\(board.taskResetMode.rawValue) " +
                "customMinutes=\(board.customResetMinutes?.description ?? "nil") " +
                "usesCustomResetTime=\(usesCustomResetTime) customResetDue=\(customResetDue) " +
                "alreadyAppliedToday=\(alreadyAppliedToday) shouldApplyBySchedule=\(shouldApplyBySchedule) " +
                "staleForce=\(shouldForceApplyForStaleCompletion) " +
                "completedCount=\(Self.completedTaskCount(in: board)) lastApplied=\(board.lastTaskResetAppliedAt?.description ?? "nil")"
            )

            if !shouldApplyBySchedule && !shouldForceApplyForStaleCompletion {
                skippedCount += 1
                continue
            }
            if shouldForceApplyForStaleCompletion {
                staleForceCount += 1
            }

            let clearedCompletedCount = Self.completedTaskCount(in: board)
            let transformedBoard = Self.transformedBoardSnapshotForResetMode(
                board.board,
                mode: board.taskResetMode,
                referenceDate: now
            )

            namedBoards[index].board = transformedBoard
            namedBoards[index].lastTaskResetAppliedAt = now
            namedBoards[index].updatedAt = now
            if board.id == activeBoardID {
                activeBoardClearedCompletedTaskCount = clearedCompletedCount
            }
            hasAnyUpdate = true
            appliedCount += 1
        }

        guard hasAnyUpdate else {
            debugToast("no reset applied, skipped=\(skippedCount)")
            return .noReset
        }

        debugToast("reset applied=\(appliedCount), staleForce=\(staleForceCount), skipped=\(skippedCount)")
        return BoardResetResult(
            didReset: true,
            clearedCompletedTaskCount: activeBoardClearedCompletedTaskCount
        )
    }

    private mutating func hasPendingCustomTimeReset(at now: Date, calendar: Calendar = .current) -> Bool {
        for board in namedBoards {
            if shouldApplyCustomReset(for: board, now: now, calendar: calendar) {
                return true
            }
        }
        return false
    }

    private func boardUsesCustomResetTime(_ board: BingoBoardStore.NamedBoard) -> Bool {
        board.customResetMinutes != nil &&
        (board.taskResetMode == .resetStatusNextDay || board.taskResetMode == .customResetStatusTime)
    }

    private mutating func shouldApplyCustomReset(
        for board: BingoBoardStore.NamedBoard,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard boardUsesCustomResetTime(board) else { return false }
        let clampedMinutes = min(max(board.customResetMinutes ?? 0, 0), 23 * 60 + 59)
        let startOfDay = calendar.startOfDay(for: now)
        guard let triggerTime = calendar.date(byAdding: .minute, value: clampedMinutes, to: startOfDay) else {
            return false
        }
        let didHitByTime = now >= triggerTime
        let didHitByLastApplied: Bool = {
            guard let lastApplied = board.lastTaskResetAppliedAt else { return true }
            return lastApplied < triggerTime
        }()
        let shouldApply = didHitByTime && didHitByLastApplied

        #if DEBUG
        if debugConfiguration.showCustomResetToast {
            showCustomResetDebugToast(
                boardName: board.name,
                triggerTime: triggerTime,
                didHit: shouldApply,
                now: now
            )
        }
        #endif

        return shouldApply
    }

    private mutating func debugLog(_ message: String) {
        #if DEBUG
        debugLogs.append(message)
        #else
        _ = message
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

    private static func completedTaskCount(in board: BingoBoardStore.NamedBoard) -> Int {
        let fullBoard = expandedBoardCache(from: board.board, maxGridSize: BingoViewModel.maxGridSize)
        return fullBoard.flatMap(\.self).filter { $0.isCompleted && $0.hasStoredTask }.count
    }

    private static func boardHasStaleCompletedTasks(
        _ board: BingoBoardStore.NamedBoard,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let fullBoard = expandedBoardCache(from: board.board, maxGridSize: BingoViewModel.maxGridSize)

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

    private static func transformedBoardSnapshotForResetMode(
        _ board: SavedBoard,
        mode: BoardTaskResetMode,
        referenceDate: Date
    ) -> SavedBoard {
        let maxGridSize = BingoViewModel.maxGridSize
        var fullBoard: [[BingoCell]]

        switch mode {
        case .resetStatusNextDay, .customResetStatusTime:
            fullBoard = expandedBoardCache(from: board, maxGridSize: maxGridSize)
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
            fullBoard = uniqueEmptyGrid(size: maxGridSize)
        case .keepTaskStatus:
            fullBoard = expandedBoardCache(from: board, maxGridSize: maxGridSize)
        }

        let gridSize = min(max(board.gridSize, 2), maxGridSize)
        let visibleCells: [[BingoCell]] = (0..<gridSize).map { row in
            (0..<gridSize).map { col in
                fullBoard[row][col].projectedForDisplay(on: referenceDate)
            }
        }

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

    private static func expandedBoardCache(from board: SavedBoard, maxGridSize: Int) -> [[BingoCell]] {
        var expanded = uniqueEmptyGrid(size: maxGridSize)

        if let fullBoardCells = board.fullBoardCells, !fullBoardCells.isEmpty {
            for row in 0..<min(fullBoardCells.count, maxGridSize) {
                for col in 0..<min(fullBoardCells[row].count, maxGridSize) {
                    expanded[row][col] = fullBoardCells[row][col]
                }
            }
            return expanded
        }

        for row in 0..<min(board.cells.count, maxGridSize) {
            for col in 0..<min(board.cells[row].count, maxGridSize) {
                expanded[row][col] = board.cells[row][col]
            }
        }

        return expanded
    }

    private static func uniqueEmptyGrid(size: Int) -> [[BingoCell]] {
        (0..<size).map { _ in
            (0..<size).map { _ in BingoCell() }
        }
    }
}
