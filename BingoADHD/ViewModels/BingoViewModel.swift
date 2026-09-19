import SwiftUI
import Combine

class BingoViewModel: ObservableObject {
    typealias BingoCelebrationDismissScheduler = (TimeInterval, @escaping () -> Void) -> Void

    enum CompletionHistoryInheritance {
        case inheritExistingCount
        case startAtZero
    }

    /// A transient, user-initiated completion effect. This deliberately lives apart from the
    /// persisted board state so an animation can never delay, replay, or undo a task mutation.
    struct TaskCompletionMotion: Identifiable, Equatable {
        enum Kind: Equatable {
            case singleTask
            case bingo
        }

        struct CellCoordinate: Hashable, Equatable {
            let row: Int
            let col: Int
        }

        let id: UUID
        let kind: Kind
        let triggeringCell: CellCoordinate
        let bingoCells: Set<CellCoordinate>

        init(
            id: UUID = UUID(),
            kind: Kind,
            triggeringCell: CellCoordinate,
            bingoCells: Set<CellCoordinate> = []
        ) {
            self.id = id
            self.kind = kind
            self.triggeringCell = triggeringCell
            self.bingoCells = bingoCells
        }
    }

    static let maxGridSize = BoardEngine.maxGridSize
    static let defaultInitialGridSize = 3
    static let maxTaskLength = 20
    static let maxCountdownMinutes = 30 * 24 * 60
    private static let bingoCelebrationDuration: TimeInterval = 2.5

    struct ExpiredTaskEvent: Identifiable, Equatable {
        let id: UUID
        let cellID: UUID
        let row: Int
        let col: Int
        let taskText: String
        let expiredAt: Date
        let expiredByCountdown: Bool
        let expiredByVisibilityWindow: Bool
        let allowsPostpone: Bool
        let taskDefinition: BingoCell?
        let boardID: UUID?

        init(
            id: UUID = UUID(),
            cellID: UUID,
            row: Int,
            col: Int,
            taskText: String,
            expiredAt: Date,
            expiredByCountdown: Bool,
            expiredByVisibilityWindow: Bool,
            allowsPostpone: Bool,
            taskDefinition: BingoCell? = nil,
            boardID: UUID? = nil
        ) {
            self.id = id
            self.cellID = cellID
            self.row = row
            self.col = col
            self.taskText = taskText
            self.expiredAt = expiredAt
            self.expiredByCountdown = expiredByCountdown
            self.expiredByVisibilityWindow = expiredByVisibilityWindow
            self.allowsPostpone = allowsPostpone
            self.taskDefinition = taskDefinition
            self.boardID = boardID
        }
    }

    enum ExpiredTaskResolution {
        case markAsCompleted
        case abandon
        case postpone(minutes: Int)
    }

    struct ExpiredBoardCountdownEvent: Identifiable, Equatable {
        let id: UUID
        let expiredAt: Date

        init(id: UUID = UUID(), expiredAt: Date) {
            self.id = id
            self.expiredAt = expiredAt
        }
    }

    enum ExpiredBoardCountdownResolution {
        case markAsCompleted
        case abandon
        case postpone(minutes: Int)
    }

    struct ScheduledTaskReplacementEvent: Identifiable, Equatable {
        let id: UUID
        let cellID: UUID
        let row: Int
        let col: Int
        let currentTaskText: String
        let presetTaskText: String

        init(
            id: UUID = UUID(),
            cellID: UUID,
            row: Int,
            col: Int,
            currentTaskText: String,
            presetTaskText: String
        ) {
            self.id = id
            self.cellID = cellID
            self.row = row
            self.col = col
            self.currentTaskText = currentTaskText
            self.presetTaskText = presetTaskText
        }
    }

    enum ScheduledTaskReplacementResolution {
        case replaceWithPreset
        case keepCurrentTask
    }

    @Published var cells: [[BingoCell]]
    @Published var gridSize: Int
    @Published var completedLines: Set<BingoLine> = []
    @Published var newlyCompletedLines: [BingoLine] = []
    @Published var showCelebration: Bool = false
    @Published var totalPoints: Int
    @Published var boardCountdownEndsAt: Date?
    @Published var expiredTaskEvent: ExpiredTaskEvent?
    @Published var expiredBoardCountdownEvent: ExpiredBoardCountdownEvent?
    @Published var scheduledTaskReplacementEvent: ScheduledTaskReplacementEvent?
    @Published private(set) var boardCompletionAnimationID: UUID?
    @Published private(set) var taskCompletionMotion: TaskCompletionMotion?
    @Published var dailyResetNoticeID = 0
    private var fullBoardCells: [[BingoCell]]
    private var lifetimePoints: Int
    private var dailyRewardState: DailyRewardState
    private let persistenceDependencies: BingoViewModelPersistenceDependencies
    private let bingoCelebrationDismissScheduler: BingoCelebrationDismissScheduler
    private let completionHistoryCountProvider: (String) -> Int
    /// Completion effects are transient presentation state. Keep later task effects pending
    /// instead of letting a fast second tap replace an in-flight Bingo celebration.
    private var pendingTaskCompletionMotions: [TaskCompletionMotion] = []
    private var bingoCelebrationGeneration: UInt = 0
    private var ignoredScheduledReplacementCellIDs = Set<UUID>()

    var showBoardCompletionAnimation: Bool {
        boardCompletionAnimationID != nil
    }

    /// Read-only lookup used by task editors to preview the count that will be
    /// restored on save. Looking up history must never create a completion.
    func completionHistoryCount(for taskText: String) -> Int {
        completionHistoryCountProvider(taskText)
    }

    init(
        persistenceDependencies: BingoViewModelPersistenceDependencies = .live,
        completionHistoryCountProvider: ((String) -> Int)? = nil,
        bingoCelebrationDismissScheduler: @escaping BingoCelebrationDismissScheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                action()
            }
        }
    ) {
        _ = BingoViewModelPersistence.recoverPendingTransactionIfNeeded(
            dependencies: persistenceDependencies
        )
        self.persistenceDependencies = persistenceDependencies
        self.bingoCelebrationDismissScheduler = bingoCelebrationDismissScheduler
        self.completionHistoryCountProvider = completionHistoryCountProvider ?? {
            TaskCompletionHistoryRuleEngine.completionCount(
                for: $0,
                in: persistenceDependencies.completionHistoryRepository.loadCompletionHistory()
            )
        }
        self.totalPoints = 0
        self.lifetimePoints = 0
        self.dailyRewardState = DailyRewardState(dateKey: PointsStore.dateKey(for: .now))
        self.boardCountdownEndsAt = persistenceDependencies.boardRepository.loadBoardCountdownEndsAt()
        self.boardCompletionAnimationID = nil
        let now = Date()
        var existingSavedAt: Date?
        var didMigrateUnsupportedRecurringTiming = false
        if let saved = persistenceDependencies.boardRepository.loadBoard() {
            existingSavedAt = persistenceDependencies.boardRepository.loadBoardLastSavedAt()
            let savedAt = existingSavedAt ?? now
            let normalizedGridSize = min(max(saved.gridSize, 2), Self.maxGridSize)
            var expandedCache = BoardEngine.expandedBoardCache(from: saved)
            for row in expandedCache.indices {
                for col in expandedCache[row].indices {
                    didMigrateUnsupportedRecurringTiming =
                        expandedCache[row][col].removeUnsupportedRepeatingTiming() ||
                        didMigrateUnsupportedRecurringTiming
                }
            }
            Self.normalizeForceFlagsInBoardCache(&expandedCache, referenceDate: now)
            self.fullBoardCells = expandedCache
            self.gridSize = normalizedGridSize
            self.cells = BoardEngine.projectVisibleCells(
                from: self.fullBoardCells,
                size: normalizedGridSize,
                referenceDate: now
            )
            let didNormalizeGridSize = normalizedGridSize != saved.gridSize
            self.completedLines = didMigrateUnsupportedRecurringTiming || didNormalizeGridSize
                ? BoardEngine.completedLines(in: self.cells, size: normalizedGridSize)
                : saved.completedLines
            let normalizedBoard = SavedBoard(
                gridSize: normalizedGridSize,
                cells: self.cells,
                completedLines: self.completedLines,
                fullBoardCells: self.fullBoardCells
            )
            if normalizedBoard != saved {
                BoardStateCommitter.saveActiveBoardState(
                    board: normalizedBoard,
                    countdownEndsAt: self.boardCountdownEndsAt,
                    savedAt: savedAt,
                    associatedBoardID: persistenceDependencies.boardRepository.loadActiveNamedBoardID(),
                    repository: persistenceDependencies.boardRepository,
                    reloadWidgets: true
                )
            }
        } else {
            self.gridSize = Self.defaultInitialGridSize
            self.cells = Self.createEmptyGrid(size: Self.defaultInitialGridSize)
            self.fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
            self.syncFullBoardCacheFromVisibleCells()
            BoardStateCommitter.saveActiveBoardState(
                board: SavedBoard(
                    gridSize: Self.defaultInitialGridSize,
                    cells: self.cells,
                    completedLines: [],
                    fullBoardCells: self.fullBoardCells
                ),
                countdownEndsAt: self.boardCountdownEndsAt,
                savedAt: now,
                associatedBoardID: nil,
                repository: persistenceDependencies.boardRepository,
                reloadWidgets: true
            )
        }
        let persistedPoints = persistenceDependencies.pointsRepository.loadPersistenceSnapshot()
        self.totalPoints = persistedPoints.totalPoints ?? calculateBoardScore()
        self.lifetimePoints = persistedPoints.lifetimePoints ?? self.totalPoints
        self.dailyRewardState = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: now,
            boardLastSavedAt: existingSavedAt,
            currentCells: self.cells,
            currentCompletedLines: self.completedLines,
            isBoardFullyCompleted: self.isBoardFullyCompleted,
            savedDailyRewardState: persistedPoints.dailyRewardState
        )
        if didMigrateUnsupportedRecurringTiming {
            self.dailyRewardState = BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: self.cells,
                completedLines: self.completedLines,
                isBoardFullyCompleted: self.isBoardFullyCompleted
            )
            persistenceDependencies.pointsRepository.saveDailyRewardState(self.dailyRewardState)
        }
        reconcileCompletionHistoryCounts()
        repairDuplicateCellIDsIfNeeded(referenceDate: now)
    }

    static func createEmptyGrid(size: Int) -> [[BingoCell]] {
        BoardEngine.createEmptyGrid(size: size)
    }

    static func createDefaultSavedBoard() -> SavedBoard {
        let initialGridSize = defaultInitialGridSize
        let visibleCells = createEmptyGrid(size: initialGridSize)
        let fullBoardCells = createEmptyGrid(size: maxGridSize)
        return SavedBoard(
            gridSize: initialGridSize,
            cells: visibleCells,
            completedLines: [],
            fullBoardCells: fullBoardCells
        )
    }

    func toggleComplete(row: Int, col: Int, referenceDate: Date = Date()) {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }

        refreshExternalPersistenceBeforeTaskToggle(referenceDate: referenceDate)
        guard canToggleComplete(row: row, col: col, referenceDate: referenceDate) else { return }
        let persistedPointsBeforeToggle = persistenceDependencies.pointsRepository.loadPersistenceSnapshot()
        let previousCells = cells
        let previousCompletedLines = completedLines
        let wasBoardFullyCompleted = isBoardFullyCompleted
        let isNowCompleted = !cells[row][col].isCompleted
        let toggledCellID = String(cells[row][col].id.uuidString.prefix(8))
        DiagnosticLogStore.recordUserAction(
            "points.task_toggle_begin",
            details: [
                "cell_id": toggledCellID,
                "position": "\(row),\(col)",
                "direction": isNowCompleted ? "complete" : "undo",
                "memory_total": "\(totalPoints)",
                "memory_lifetime": "\(lifetimePoints)",
                "persisted_total": persistedPointsBeforeToggle.totalPoints.map { "\($0)" } ?? "nil",
                "persisted_lifetime": persistedPointsBeforeToggle.lifetimePoints.map { "\($0)" } ?? "nil",
                "icloud_enabled": "\(NativeICloudPreferences.isEnabled)"
            ]
        )
        let diaryTaskText = cells[row][col].storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedHistory = TaskCompletionHistoryRuleEngine.recordsByApplyingCompletionDelta(
            taskText: diaryTaskText,
            delta: isNowCompleted ? 1 : -1,
            to: persistenceDependencies.completionHistoryRepository.loadCompletionHistory(),
            at: referenceDate
        )
        let synchronizedCompletionCount = TaskCompletionHistoryRuleEngine.completionCount(
            for: diaryTaskText,
            in: updatedHistory
        )
        cells[row][col].isCompleted = isNowCompleted
        if isNowCompleted {
            registerCompletionIfNeeded(row: row, col: col, now: referenceDate)
            // Force completion should only block until this task is completed once.
            cells[row][col].isForced = false
            cells[row][col].countdownEndsAt = nil
            cells[row][col].countdownPausedRemainingSeconds = nil
            cells[row][col].estimatedDurationMinutes = nil
            if expiredTaskEvent?.cellID == cells[row][col].id {
                expiredTaskEvent = nil
            }
        } else {
            cells[row][col].isTaskHidden = false
            if cells[row][col].completionStreakCount > 0 {
                cells[row][col].completionStreakCount -= 1
            }
            if cells[row][col].completionStreakCount <= 0 {
                cells[row][col].completionStreakCount = 0
            }
            cells[row][col].countdownEndsAt = nil
            cells[row][col].countdownPausedRemainingSeconds = nil
            cells[row][col].estimatedDurationMinutes = nil
            // Allow complete -> cancel -> complete on the same day to be counted again.
            cells[row][col].lastCompletedAt = nil
        }
        syncFullBoardCacheFromVisibleCells()
        synchronizeCompletionHistoryCount(
            for: diaryTaskText,
            count: synchronizedCompletionCount,
            referenceDate: referenceDate
        )
        checkBingo()
        let isBoardNowFullyCompleted = isBoardFullyCompleted
        let newlyCompletedLines = completedLines.subtracting(previousCompletedLines)
        if !wasBoardFullyCompleted && isBoardNowFullyCompleted {
            presentBoardCompletionAnimation()
        } else if !isBoardNowFullyCompleted {
            dismissBoardCompletionAnimation()
        }
        updateTaskCompletionMotion(
            taskIsNowCompleted: isNowCompleted,
            triggeringCell: TaskCompletionMotion.CellCoordinate(row: row, col: col),
            newlyCompletedLines: newlyCompletedLines,
            isBoardNowFullyCompleted: isBoardNowFullyCompleted
        )
        trackBingoCompletionIfNeeded(
            wasBoardFullyCompleted: wasBoardFullyCompleted,
            isBoardNowFullyCompleted: isBoardNowFullyCompleted
        )
        settleTaskToggleRewards(
            on: referenceDate,
            previousCells: previousCells,
            previousCompletedLines: previousCompletedLines,
            previousIsBoardFullyCompleted: wasBoardFullyCompleted,
            taskIsNowCompleted: isNowCompleted
        )
        DiagnosticLogStore.recordStateChange(
            "points.task_toggle_settled",
            details: [
                "cell_id": toggledCellID,
                "direction": isNowCompleted ? "complete" : "undo",
                "memory_total": "\(totalPoints)",
                "memory_lifetime": "\(lifetimePoints)",
                "line_count_before": "\(previousCompletedLines.count)",
                "line_count_after": "\(completedLines.count)",
                "full_board_before": "\(wasBoardFullyCompleted)",
                "full_board_after": "\(isBoardNowFullyCompleted)"
            ]
        )
        let commitResult = saveWithExplicitDiaryDelta(
            task: diaryTaskText,
            delta: isNowCompleted ? 1 : -1,
            completionHistoryDelta: isNowCompleted ? 1 : -1
        )
        // A successful transaction has already read back the points ledger. Only
        // read it again when persisting failed, where the observed disk state is
        // useful for diagnostics.
        let persistedPointsAfterToggle = commitResult.savedPoints
            ? nil
            : persistenceDependencies.pointsRepository.loadPersistenceSnapshot()
        let persistenceDetails = [
            "cell_id": toggledCellID,
            "saved_board": "\(commitResult.savedBoard)",
            "saved_points": "\(commitResult.savedPoints)",
            "failed_board": "\(commitResult.failedToSaveBoard)",
            "failed_transaction": "\(commitResult.failedToSaveTransaction)",
            "memory_total": "\(totalPoints)",
            "persisted_total": persistedPointsAfterToggle?.totalPoints.map { "\($0)" }
                ?? (commitResult.savedPoints ? "\(totalPoints)" : "nil"),
            "persisted_lifetime": persistedPointsAfterToggle?.lifetimePoints.map { "\($0)" }
                ?? (commitResult.savedPoints ? "\(lifetimePoints)" : "nil")
        ]
        if commitResult.failedToSaveBoard || commitResult.failedToSaveTransaction || !commitResult.savedPoints {
            DiagnosticLogStore.recordWarning(
                "points.task_toggle_persistence_failed",
                details: persistenceDetails
            )
        } else {
            DiagnosticLogStore.recordStateChange(
                "points.task_toggle_persisted",
                details: persistenceDetails
            )
        }
    }

    @discardableResult
    func updateTask(
        row: Int,
        col: Int,
        text: String,
        isForced: Bool,
        residentWeekdays: Set<Int>,
        isOneTimeTask: Bool = false,
        recurrenceRule: TaskRecurrenceRule? = nil,
        estimatedDurationMinutes: Int? = nil,
        startVisibleAt: Date? = nil,
        endVisibleAt: Date? = nil,
        startReminderEnabled: Bool = false,
        startReminderOffsetMinutes: Int = BingoCell.defaultStartReminderOffsetMinutes,
        completionHistoryInheritance: CompletionHistoryInheritance = .inheritExistingCount,
        editSource: String = "task_editor"
    ) -> Bool {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        return persistenceDependencies.boardRepository.withTaskEditLock {
            guard row >= 0, col >= 0, row < cells.count, col < cells[row].count else { return false }
            let editingCellID = cells[row][col].id
            if persistenceDependencies.transactionRepository.loadPendingTransaction() != nil {
                _ = BingoViewModelPersistence.recoverPendingTransactionIfNeeded(dependencies: persistenceDependencies)
                guard persistenceDependencies.transactionRepository.loadPendingTransaction() == nil else {
                    DiagnosticLogStore.recordWarning("task_edit.blocked_by_pending_transaction")
                    return false
                }
            }
            let expectedBoard = persistenceDependencies.boardRepository.loadBoard()
            let expectedBoardID = persistenceDependencies.boardRepository.loadActiveNamedBoardID()
            if let expectedBoard,
               !BingoBoardStore.hasMatchingCellIdentity(persistenceSnapshot().board, expectedBoard) {
                DiagnosticLogStore.recordWarning("task_edit.board_changed")
                return false
            }
            refreshExternalPersistenceBeforeTaskToggle(referenceDate: .now)
            guard row < cells.count, col < cells[row].count, cells[row][col].id == editingCellID else { return false }
            let previousCell = cells[row][col]
            let editResult = TaskEditRuleEngine.apply(
                TaskEditRuleInput(
                    previousCell: previousCell,
                    text: text,
                    isForced: isForced,
                    residentWeekdays: residentWeekdays,
                    isOneTimeTask: isOneTimeTask,
                    recurrenceRule: recurrenceRule,
                    estimatedDurationMinutes: estimatedDurationMinutes,
                    startVisibleAt: startVisibleAt,
                    endVisibleAt: endVisibleAt,
                    startReminderEnabled: startReminderEnabled,
                    startReminderOffsetMinutes: startReminderOffsetMinutes,
                    referenceDate: Date(),
                    calendar: .current,
                    maxTaskLength: Self.maxTaskLength,
                    maxCountdownMinutes: Self.maxCountdownMinutes
                )
            )
            var updatedCell = editResult.cell
            let diagnosticBoardID = persistenceDependencies.boardRepository.loadActiveNamedBoardID()
                .map { String($0.uuidString.prefix(8)) } ?? "none"
            let diagnosticCellID = String(previousCell.id.uuidString.prefix(8))
            let editDiagnosticDetails = [
                "operation_id": UUID().uuidString,
                "board_id": diagnosticBoardID,
                "cell_id": diagnosticCellID,
                "position": "\(row),\(col)",
                "previous_rule": previousCell.diagnosticTaskRuleKind,
                "updated_rule": updatedCell.diagnosticTaskRuleKind,
                "previous_completed": "\(previousCell.isCompleted)",
                "updated_completed": "\(updatedCell.isCompleted)",
                "is_empty": "\(editResult.isEmpty)",
                "source": editSource,
                "submitted_rule": recurrenceRule?.kind.rawValue ?? (residentWeekdays.isEmpty ? "single" : "legacy_weekly")
            ]
            DiagnosticLogStore.recordUserAction(
                "task_edit.save_requested",
                details: editDiagnosticDetails
            )
            let previousHistoryKey = TaskCompletionHistoryRuleEngine.normalizedKey(
                for: previousCell.storedTaskText
            )
            let updatedHistoryKey = TaskCompletionHistoryRuleEngine.normalizedKey(
                for: updatedCell.storedTaskText
            )
            let replacedOrRemovedTask = previousHistoryKey != nil && previousHistoryKey != updatedHistoryKey
            if replacedOrRemovedTask,
               !TaskCompletionHistoryStore.archive(previousCell) {
                DiagnosticLogStore.recordWarning(
                    "task_completion_history.archive_failed",
                    details: editDiagnosticDetails.merging(["source": "task_edit"]) { current, _ in current }
                )
                return false
            }
            switch completionHistoryInheritance {
            case .inheritExistingCount:
                // Restore only the count. `TaskEditRuleEngine` remains solely
                // responsible for completion state, timers, force mode, and dates.
                updatedCell.completionStreakCount = TaskCompletionHistoryRuleEngine.inheritedCompletionCount(
                    previousTaskText: previousCell.storedTaskText,
                    // `TaskEditRuleEngine` already clears this value when a
                    // schedule or task identity changes. Preserve that decision;
                    // history is only a source for a newly named task.
                    previousCompletionCount: updatedCell.completionStreakCount,
                    updatedTaskText: updatedCell.storedTaskText,
                    availableHistoryCount: completionHistoryCount(for: updatedCell.storedTaskText)
                )
            case .startAtZero:
                // System-owned seed tasks are not continuations of a user's task.
                // They must remain distinguishable from a modified board during
                // iCloud merge and redundant-starter cleanup.
                updatedCell.completionStreakCount = 0
                updatedCell.lastCompletedAt = nil
            }

            let editedCache = boardCacheByApplyingEditedCell(updatedCell, row: row, col: col)
            let editedVisibleCells = visibleCells(from: editedCache, size: gridSize)
            let editedBoard = SavedBoard(
                gridSize: gridSize,
                cells: editedVisibleCells,
                completedLines: BoardEngine.completedLines(in: editedVisibleCells, size: gridSize),
                fullBoardCells: editedCache
            )
            // A failed configuration write must never enter the replayable points journal.
            guard persistenceDependencies.boardRepository.saveTaskEditBoard(
                editedBoard, expected: expectedBoard, boardID: expectedBoardID, savedAt: .now,
                explicitlyEditedCellIDs: [updatedCell.id]
            ) else {
                DiagnosticLogStore.recordWarning("task_edit.configuration_save_failed", details: editDiagnosticDetails)
                return false
            }
            DiagnosticLogStore.recordStateChange("task_edit.configuration_saved", details: editDiagnosticDetails)

            if expiredTaskEvent?.cellID == previousCell.id,
               (editResult.isEmpty ||
                !TaskRulePersistenceGuard.matchesTaskDefinition(previousCell, updatedCell) ||
                previousCell.countdownEndsAt != updatedCell.countdownEndsAt ||
                previousCell.countdownPausedRemainingSeconds != updatedCell.countdownPausedRemainingSeconds) {
                expiredTaskEvent = nil
            }
            if editResult.isEmpty {
                if expiredTaskEvent?.cellID == updatedCell.id {
                    expiredTaskEvent = nil
                }
                if scheduledTaskReplacementEvent?.cellID == updatedCell.id {
                    scheduledTaskReplacementEvent = nil
                }
            }

            fullBoardCells = editedCache
            ignoredScheduledReplacementCellIDs.remove(updatedCell.id)
            cells = visibleCells(from: fullBoardCells, size: gridSize)
            checkBingo()
            if !isBoardFullyCompleted {
                dismissBoardCompletionAnimation()
            }
            settleRewardsIfNeeded(mode: .preserveAccumulatedPoints)

            if !editResult.isEmpty {
                TaskHistoryStore.upsert(
                    task: MyTaskItem(
                        text: editResult.normalizedTaskText,
                        startAt: editResult.normalizedStartVisibleAt,
                        endAt: editResult.normalizedEndVisibleAt,
                        recurrenceRule: editResult.cell.recurrenceRule
                    )
                )
            } else if let previousTask = BingoTaskBoardHelpers.taskItem(from: previousCell, maxLength: Self.maxTaskLength) {
                TaskHistoryStore.upsert(task: previousTask)
            }
            var commitResult = save()
            commitResult.savedBoard = true
            if !commitResult.reloadedWidgets {
                persistenceDependencies.boardRepository.reloadWidgetTimelines()
                commitResult.reloadedWidgets = true
            }
            let persistedCell = persistenceDependencies.boardRepository.loadBoard()
                .map { BoardEngine.expandedBoardCache(from: $0) }
                .flatMap { boardCells in
                    boardCells.lazy.flatMap { $0 }.first(where: { $0.id == updatedCell.id })
                }
            let persistenceDetails = editDiagnosticDetails.merging([
                "saved_board": "\(commitResult.savedBoard)",
                "saved_points": "\(commitResult.savedPoints)",
                "failed_board": "\(commitResult.failedToSaveBoard)",
                "failed_transaction": "\(commitResult.failedToSaveTransaction)",
                "persisted_cell_found": "\(persistedCell != nil)",
                "persisted_rule": persistedCell?.diagnosticTaskRuleKind ?? "missing"
            ]) { current, _ in current }
            if commitResult.savedBoard,
               !commitResult.failedToSaveBoard,
               !commitResult.failedToSaveTransaction,
               persistedCell?.diagnosticTaskRuleKind == updatedCell.diagnosticTaskRuleKind {
                DiagnosticLogStore.recordStateChange(
                    "task_edit.save_persisted",
                    details: persistenceDetails
                )
            } else {
                DiagnosticLogStore.recordWarning(
                    "task_edit.save_persistence_failed",
                    details: persistenceDetails
                )
            }
            // Configuration is already durable; the existing journal recovers ancillary writes.
            return true
        }
    }

    func clearTask(row: Int, col: Int) {
        updateTask(row: row, col: col, text: "", isForced: false, residentWeekdays: [], isOneTimeTask: false)
    }

    func remainingTaskCountdownMinutes(row: Int, col: Int, referenceDate: Date = Date()) -> Int? {
        guard let editingCell = editingCell(row: row, col: col) else { return nil }
        if let deadline = editingCell.countdownEndsAt {
            let remainingSeconds = max(deadline.timeIntervalSince(referenceDate), 0)
            let remainingMinutes = Int(ceil(remainingSeconds / 60))
            return max(remainingMinutes, 1)
        }
        if let pausedSeconds = editingCell.countdownPausedRemainingSeconds, pausedSeconds > 0 {
            return max(Int(ceil(Double(pausedSeconds) / 60)), 1)
        }
        return editingCell.estimatedDurationMinutes
    }

    func canSetTaskCountdown(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        guard let editingCell = editingCell(row: row, col: col) else { return false }
        return editingCell.canManuallySetTaskCountdown && !editingCell.completionApplies(on: referenceDate)
    }

    func hasTaskCountdown(row: Int, col: Int) -> Bool {
        guard let editingCell = editingCell(row: row, col: col) else { return false }
        return editingCell.estimatedDurationMinutes != nil ||
            editingCell.countdownEndsAt != nil ||
            editingCell.countdownPausedRemainingSeconds != nil
    }

    func isTaskCountdownPaused(row: Int, col: Int) -> Bool {
        guard let editingCell = editingCell(row: row, col: col) else { return false }
        return (editingCell.countdownPausedRemainingSeconds ?? 0) > 0
    }

    func canPauseOrResumeTaskCountdown(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        guard let editingCell = editingCell(row: row, col: col) else { return false }
        if (editingCell.countdownPausedRemainingSeconds ?? 0) > 0 {
            return editingCell.canUseTaskCountdown &&
                editingCell.isCurrentlyTappable(on: referenceDate) &&
                !editingCell.completionApplies(on: referenceDate)
        }
        guard let deadline = editingCell.countdownEndsAt else { return false }
        return deadline > referenceDate &&
            editingCell.canUseTaskCountdown &&
            editingCell.isCurrentlyTappable(on: referenceDate) &&
            !editingCell.completionApplies(on: referenceDate)
    }

    @discardableResult
    func setTaskCountdown(row: Int, col: Int, minutes: Int?, referenceDate: Date = Date()) -> Bool {
        applyTaskCountdownAction(
            .set(minutes: minutes),
            row: row,
            col: col,
            referenceDate: referenceDate
        )
    }

    @discardableResult
    func pauseTaskCountdown(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        applyTaskCountdownAction(
            .pause,
            row: row,
            col: col,
            referenceDate: referenceDate
        )
    }

    @discardableResult
    func resumeTaskCountdown(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        applyTaskCountdownAction(
            .resume,
            row: row,
            col: col,
            referenceDate: referenceDate
        )
    }

    @discardableResult
    func cancelTaskCountdown(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        setTaskCountdown(row: row, col: col, minutes: nil, referenceDate: referenceDate)
    }

    private func applyTaskCountdownAction(
        _ action: TaskCountdownRuleAction,
        row: Int,
        col: Int,
        referenceDate: Date
    ) -> Bool {
        guard row >= 0, col >= 0 else { return false }
        guard row < min(gridSize, fullBoardCells.count),
              col < min(gridSize, fullBoardCells[row].count) else {
            return false
        }
        guard let updatedCell = TaskCountdownRuleEngine.apply(
            TaskCountdownRuleInput(
                cell: fullBoardCells[row][col],
                action: action,
                referenceDate: referenceDate,
                calendar: .current,
                maxCountdownMinutes: Self.maxCountdownMinutes
            )
        ) else {
            return false
        }

        fullBoardCells[row][col] = updatedCell
        cells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: gridSize,
            referenceDate: referenceDate
        )
        if action.clearsExpiredTaskEventWhenStopped,
           expiredTaskEvent?.cellID == updatedCell.id,
           updatedCell.countdownEndsAt == nil {
            expiredTaskEvent = nil
        }
        save(persistDiary: false, savedAt: referenceDate)
        return true
    }

    func isTaskCurrentlyTappable(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        guard row >= 0, col >= 0 else { return false }
        guard let sourceCell = editingCell(row: row, col: col) else { return false }
        return sourceCell.isCurrentlyTappable(on: referenceDate)
    }

    func canToggleComplete(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        guard row >= 0, col >= 0 else { return false }
        guard row < cells.count, col < cells[row].count else { return false }
        guard !cells[row][col].isEmpty else { return false }
        guard !isLocked(row: row, col: col) else { return false }
        if cells[row][col].isCompleted {
            return true
        }
        return isTaskCurrentlyTappable(row: row, col: col, referenceDate: referenceDate)
    }

    func visibleCell(row: Int, col: Int, matching cellID: UUID? = nil) -> BingoCell? {
        BoardEngine.cell(in: cells, row: row, col: col, matching: cellID)
    }

    func editingCell(row: Int, col: Int) -> BingoCell? {
        guard row >= 0, col >= 0 else { return nil }
        guard row < min(gridSize, fullBoardCells.count),
              col < min(gridSize, fullBoardCells[row].count) else { return nil }
        return fullBoardCells[row][col]
    }

    func toggleTaskHidden(row: Int, col: Int) {
        _ = applyVisibleCellMutation(.toggleTaskHidden, row: row, col: col)
    }

    @discardableResult
    func deleteCell(row: Int, col: Int) -> BingoCell? {
        applyVisibleCellMutation(.delete, row: row, col: col)
    }

    func restoreCell(_ cell: BingoCell, row: Int, col: Int) {
        _ = applyVisibleCellMutation(.restore(cell), row: row, col: col)
    }

    @discardableResult
    private func applyVisibleCellMutation(
        _ action: VisibleCellMutationAction,
        row: Int,
        col: Int,
        referenceDate: Date = .now
    ) -> BingoCell? {
        guard row >= 0, col >= 0,
              row < cells.count,
              col < cells[row].count else {
            return nil
        }

        let previousCell = cells[row][col]
        let actionIsLocked = action.respectsForcedTaskLock && isLocked(row: row, col: col)
        guard let updatedCell = VisibleCellMutationRuleEngine.apply(
            VisibleCellMutationRuleInput(
                currentCell: previousCell,
                action: action,
                isLocked: actionIsLocked,
                referenceDate: referenceDate,
                calendar: .current
            )
        ) else {
            return nil
        }

        if case .delete = action,
           let deletedTask = BingoTaskBoardHelpers.taskItem(
               from: previousCell,
               maxLength: Self.maxTaskLength
           ) {
            TaskHistoryStore.upsert(task: deletedTask)
        }
        if case .delete = action,
           !TaskCompletionHistoryStore.archive(previousCell) {
            DiagnosticLogStore.recordWarning(
                "task_completion_history.archive_failed",
                details: ["source": "cell_delete"]
            )
            return nil
        }

        cells[row][col] = updatedCell
        if action.requiresBoardStateRefresh {
            refreshBoardState(
                shouldCelebrateNewLines: false,
                rewardSettlementMode: .preserveAccumulatedPoints
            )
        } else {
            syncFullBoardCacheFromVisibleCells()
            save()
        }
        return previousCell
    }

    func moveCell(from source: (row: Int, col: Int), to destination: (row: Int, col: Int)) {
        let forcedPositions = activeForcedPositions
        let hasActiveForcedTask = !forcedPositions.isEmpty
        guard let updatedCells = BoardCellMoveRuleEngine.apply(
            BoardCellMoveRuleInput(
                cells: cells,
                source: source,
                destination: destination,
                isSourceLocked: hasActiveForcedTask && !forcedPositions.contains(
                    Position(row: source.row, col: source.col)
                ),
                isDestinationLocked: hasActiveForcedTask && !forcedPositions.contains(
                    Position(row: destination.row, col: destination.col)
                )
            )
        ) else {
            return
        }

        cells = updatedCells
        refreshBoardState(
            shouldCelebrateNewLines: false,
            rewardSettlementMode: .preserveAccumulatedPoints
        )
    }

    func currentTaskPoolTasks() -> [String] {
        let slots = taskPoolSlots(maxSize: Self.maxGridSize)
        return slots.compactMap { slot in
            guard slot.row < fullBoardCells.count, slot.col < fullBoardCells[slot.row].count else { return nil }
            let text = fullBoardCells[slot.row][slot.col].storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    func currentBoardTasksInRowMajor(size: Int? = nil) -> [MyTaskItem?] {
        let resolvedSize = min(max(size ?? gridSize, 2), Self.maxGridSize)
        let totalSlots = resolvedSize * resolvedSize

        return (0..<totalSlots).map { index in
            let row = index / resolvedSize
            let col = index % resolvedSize
            guard row < fullBoardCells.count, col < fullBoardCells[row].count else { return nil }

            let cell = fullBoardCells[row][col]
            let text = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            return MyTaskItem(
                text: text,
                startAt: cell.startVisibleAt,
                endAt: cell.endVisibleAt,
                startMonth: cell.startVisibleMonth,
                startDay: cell.startVisibleDay,
                recurrenceRule: cell.recurrenceRule
            )
        }
    }

    func currentBoardCellsInRowMajor(size: Int? = nil) -> [BingoCell?] {
        let resolvedSize = min(max(size ?? gridSize, 2), Self.maxGridSize)
        let totalSlots = resolvedSize * resolvedSize

        return (0..<totalSlots).map { index in
            let row = index / resolvedSize
            let col = index % resolvedSize
            guard row < fullBoardCells.count, col < fullBoardCells[row].count else { return nil }
            let cell = fullBoardCells[row][col]
            return cell.hasStoredTask ? cell : nil
        }
    }

    func makeQuickEditBoardContext() -> QuickEditBoardContext {
        QuickEditBoardContext(
            boardID: persistenceDependencies.boardRepository.loadActiveNamedBoardID(),
            board: makeSavedBoardSnapshot()
        )
    }

    func isQuickEditBoardContextCurrent(_ context: QuickEditBoardContext) -> Bool {
        let boardID = persistenceDependencies.boardRepository.loadActiveNamedBoardID()
        return context.matches(persistenceDependencies.boardRepository.loadBoard(), boardID: boardID) &&
            context.matches(makeSavedBoardSnapshot(), boardID: boardID)
    }

    @discardableResult
    func applyBoardOrderedCells(
        _ orderedCells: [BingoCell?], targetGridSize: Int,
        explicitlyEditedCellIDs: Set<UUID> = [],
        editingContext: QuickEditBoardContext? = nil
    ) -> Bool {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        return persistenceDependencies.boardRepository.withTaskEditLock {
            applyBoardOrderedCellsUnderLock(orderedCells, targetGridSize: targetGridSize,
                explicitlyEditedCellIDs: explicitlyEditedCellIDs, editingContext: editingContext)
        }
    }

    private func applyBoardOrderedCellsUnderLock(
        _ orderedCells: [BingoCell?], targetGridSize: Int,
        explicitlyEditedCellIDs: Set<UUID>, editingContext: QuickEditBoardContext?
    ) -> Bool {
        if persistenceDependencies.transactionRepository.loadPendingTransaction() != nil {
            _ = BingoViewModelPersistence.recoverPendingTransactionIfNeeded(dependencies: persistenceDependencies)
            guard persistenceDependencies.transactionRepository.loadPendingTransaction() == nil else {
                DiagnosticLogStore.recordWarning("task_rule.bulk_blocked_by_pending_transaction")
                return false
            }
        }
        let referenceDate = Date()
        let expectedBoard = persistenceDependencies.boardRepository.loadBoard()
        let boardID = persistenceDependencies.boardRepository.loadActiveNamedBoardID()
        if let editingContext,
           (!editingContext.matches(expectedBoard, boardID: boardID) ||
            !editingContext.matches(makeSavedBoardSnapshot(), boardID: boardID)) {
            DiagnosticLogStore.recordWarning("task_rule.quick_edit_context_changed", details: [
                "original_board_id": editingContext.boardID?.uuidString ?? "none",
                "current_board_id": boardID?.uuidString ?? "none"
            ])
            return false
        }
        let ruleResult = BoardOrderedCellsRuleEngine.apply(
            BoardOrderedCellsRuleInput(
                orderedCells: orderedCells,
                targetGridSize: targetGridSize,
                minimumGridSize: 2,
                maximumGridSize: Self.maxGridSize,
                maxTaskLength: Self.maxTaskLength,
                referenceDate: referenceDate,
                calendar: .current
            )
        )
        let proposedBoard = SavedBoard(
            gridSize: ruleResult.gridSize,
            cells: BoardEngine.projectVisibleCells(from: ruleResult.fullBoardCells, size: ruleResult.gridSize, referenceDate: referenceDate),
            completedLines: [], fullBoardCells: ruleResult.fullBoardCells
        )
        let blocked = TaskRulePersistenceGuard.downgradedCellIDs(from: expectedBoard, to: proposedBoard)
            .subtracting(explicitlyEditedCellIDs)
        guard blocked.isEmpty else {
            DiagnosticLogStore.recordWarning("task_rule.downgrade_blocked", details: [
                "source": "quick_edit_apply", "board_id": boardID?.uuidString ?? "none",
                "count": String(blocked.count)
            ])
            return false
        }
        // Quick edit can replace or remove several cells at once. Archiving the
        // outgoing snapshot is idempotent (max count per normalized name), and
        // leaves all board/points rules untouched.
        guard TaskCompletionHistoryStore.archive(cells: fullBoardCells.flatMap { $0 }, at: referenceDate) else {
            DiagnosticLogStore.recordWarning(
                "task_completion_history.archive_failed",
                details: ["source": "quick_edit"]
            )
            return false
        }
        TaskHistoryStore.upsertBoardTasks(ruleResult.appliedTasks)

        var restoredFullBoardCells = ruleResult.fullBoardCells
        for row in restoredFullBoardCells.indices {
            for col in restoredFullBoardCells[row].indices {
                let taskText = restoredFullBoardCells[row][col].storedTaskText
                guard TaskCompletionHistoryRuleEngine.normalizedKey(for: taskText) != nil else { continue }
                restoredFullBoardCells[row][col].completionStreakCount = TaskCompletionHistoryStore.completionCount(
                    for: taskText
                )
            }
        }

        let configuredVisibleCells = BoardEngine.projectVisibleCells(
            from: restoredFullBoardCells, size: ruleResult.gridSize, referenceDate: referenceDate
        )
        let configuration = SavedBoard(
            gridSize: ruleResult.gridSize,
            cells: configuredVisibleCells,
            completedLines: BoardEngine.completedLines(in: configuredVisibleCells, size: ruleResult.gridSize),
            fullBoardCells: restoredFullBoardCells
        )
        guard persistenceDependencies.boardRepository.saveTaskEditBoard(
            configuration, expected: expectedBoard, boardID: boardID, savedAt: referenceDate,
            explicitlyEditedCellIDs: explicitlyEditedCellIDs
        ) else {
            DiagnosticLogStore.recordWarning("task_rule.bulk_save_failed", details: [
                "source": "quick_edit", "board_id": boardID?.uuidString ?? "none"
            ])
            return false
        }
        let beforeCells = expectedBoard.map { BoardEngine.expandedBoardCache(from: $0).flatMap { $0 } } ?? []
        let afterCells = restoredFullBoardCells.flatMap { $0 }
        for cell in afterCells where cell.hasStoredTask {
            let previous = beforeCells.first { $0.id == cell.id && $0.hasStoredTask }
            guard previous == nil || previous?.diagnosticTaskRuleKind != cell.diagnosticTaskRuleKind else { continue }
            DiagnosticLogStore.recordStateChange("task_rule.cell_saved", details: [
                "source": "quick_edit", "board_id": boardID?.uuidString ?? "none",
                "cell_id": cell.id.uuidString,
                "before_rule": previous?.diagnosticTaskRuleKind ?? "new",
                "after_rule": cell.diagnosticTaskRuleKind
            ])
        }
        DiagnosticLogStore.recordStateChange("task_rule.bulk_saved", details: [
            "source": "quick_edit", "board_id": boardID?.uuidString ?? "none",
            "before_tasks": String(beforeCells.filter(\.hasStoredTask).count),
            "after_tasks": String(afterCells.filter(\.hasStoredTask).count),
            "before_repeating": String(beforeCells.filter(\.hasRepeatingSchedule).count),
            "after_repeating": String(afterCells.filter(\.hasRepeatingSchedule).count),
            "explicit_edits": String(explicitlyEditedCellIDs.count), "readback_verified": "true"
        ])
        fullBoardCells = restoredFullBoardCells
        gridSize = ruleResult.gridSize
        cells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: gridSize,
            referenceDate: referenceDate
        )
        dismissBoardCompletionAnimation()
        dismissTaskCompletionMotion()
        boardCountdownEndsAt = nil
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil
        checkBingo(shouldCelebrateNewLines: false)
        settleRewardsIfNeeded(on: referenceDate, mode: .preserveAccumulatedPoints)
        save(savedAt: referenceDate)
        return true
    }

    func resizeGrid(to newSize: Int) {
        guard newSize >= 2 && newSize <= Self.maxGridSize else { return }
        let referenceDate = Date()
        syncFullBoardCacheFromVisibleCells()
        gridSize = newSize
        cells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: newSize,
            referenceDate: referenceDate
        )
        boardCountdownEndsAt = nil
        dismissBoardCompletionAnimation()
        dismissTaskCompletionMotion()
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil
        checkBingo(shouldCelebrateNewLines: false)
        settleRewardsIfNeeded(on: referenceDate, mode: .preserveAccumulatedPoints)
        save(savedAt: referenceDate)
    }

    @discardableResult
    func resetBoard() -> Bool {
        guard TaskCompletionHistoryStore.archive(cells: fullBoardCells.flatMap { $0 }) else {
            DiagnosticLogStore.recordWarning(
                "task_completion_history.archive_failed",
                details: ["source": "board_reset"]
            )
            return false
        }
        cells = Self.createEmptyGrid(size: gridSize)
        fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
        completedLines = []
        invalidateBingoCelebration()
        dismissBoardCompletionAnimation()
        dismissTaskCompletionMotion()
        boardCountdownEndsAt = nil
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil
        settleRewardsIfNeeded(mode: .preserveAccumulatedPoints)
        save()
        return true
    }

    func makeSavedBoardSnapshot() -> SavedBoard {
        persistenceSnapshot().board
    }

    func makePointsPersistenceSnapshot() -> PointsPersistenceSnapshot {
        PointsPersistenceSnapshot(
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState
        )
    }

    func applySavedBoardSnapshot(
        _ savedBoard: SavedBoard,
        countdownEndsAt: Date?,
        referenceDate: Date = .now,
        reloadPersistedPoints: Bool = false,
        persist: Bool = true
    ) {
        let historyReconciledBoard = TaskCompletionHistoryRuleEngine.boardByReconcilingCompletionHistory(
            savedBoard,
            records: persistenceDependencies.completionHistoryRepository.loadCompletionHistory()
        )
        let timingNormalizedBoard = BoardEngine.removingUnsupportedRecurringTiming(
            from: historyReconciledBoard,
            referenceDate: referenceDate
        )
        let normalizedGridSize = min(max(timingNormalizedBoard.gridSize, 2), Self.maxGridSize)
        var expandedCache = BoardEngine.expandedBoardCache(from: timingNormalizedBoard)
        Self.normalizeForceFlagsInBoardCache(&expandedCache, referenceDate: referenceDate)

        fullBoardCells = expandedCache
        gridSize = normalizedGridSize
        cells = BoardEngine.projectVisibleCells(
            from: expandedCache,
            size: normalizedGridSize,
            referenceDate: referenceDate
        )
        dismissBoardCompletionAnimation()
        dismissTaskCompletionMotion()
        boardCountdownEndsAt = countdownEndsAt
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil

        checkBingo(shouldCelebrateNewLines: false)
        repairDuplicateCellIDsIfNeeded(referenceDate: referenceDate)
        if reloadPersistedPoints {
            reloadPersistedPointsState(referenceDate: referenceDate)
        } else {
            dailyRewardState = BingoRewardSettlement.dailyRewardSnapshot(
                for: referenceDate,
                cells: cells,
                completedLines: completedLines,
                isBoardFullyCompleted: isBoardFullyCompleted
            )
        }
        if persist {
            save(persistDiary: false, savedAt: referenceDate)
        }
    }

    func setBoardCountdown(totalMinutes: Int?) {
        guard let totalMinutes else {
            setBoardCountdownEndsAt(nil)
            return
        }

        let clampedMinutes = min(max(totalMinutes, 1), Self.maxCountdownMinutes)
        setBoardCountdownEndsAt(Date().addingTimeInterval(Double(clampedMinutes * 60)))
    }

    func setBoardCountdownEndsAt(_ endsAt: Date?) {
        boardCountdownEndsAt = endsAt
        expiredBoardCountdownEvent = nil
        save()
    }

    func shuffleBoard() {
        let fixedPositions = bingoLinePositions
        let movablePositions = cells.enumerated().flatMap { row, rowCells in
            rowCells.enumerated().compactMap { entry -> Position? in
                let position = Position(row: row, col: entry.offset)
                return fixedPositions.contains(position) || !canMoveSlot(entry.element) ? nil : position
            }
        }
        let shuffledTaskCells = movablePositions
            .map { cells[$0.row][$0.col] }
            .filter { !$0.isEmpty }
            .shuffled()

        var newCells = cells
        let shuffledTaskPositions = Array(movablePositions.shuffled().prefix(shuffledTaskCells.count))
        let taskPositionSet = Set(shuffledTaskPositions)

        for (index, position) in shuffledTaskPositions.enumerated() {
            newCells[position.row][position.col] = shuffledTaskCells[index]
        }

        for position in movablePositions where !taskPositionSet.contains(position) {
            newCells[position.row][position.col] = BingoCell()
        }

        cells = newCells
        refreshBoardState(
            shouldCelebrateNewLines: false,
            rewardSettlementMode: .preserveAccumulatedPoints
        )
    }

    func dismissBoardCompletionAnimation() {
        guard boardCompletionAnimationID != nil else { return }
        boardCompletionAnimationID = nil
    }

    @discardableResult
    func dismissBoardCompletionAnimation(id: UUID) -> Bool {
        guard boardCompletionAnimationID == id else { return false }
        dismissBoardCompletionAnimation()
        return true
    }

    private func presentBoardCompletionAnimation() {
        boardCompletionAnimationID = UUID()
    }

    func dismissTaskCompletionMotion(id: UUID? = nil) {
        guard let taskCompletionMotion else { return }
        guard id == nil || taskCompletionMotion.id == id else { return }
        self.taskCompletionMotion = nil

        // An explicit identifier comes from a completed presentation. A nil identifier comes
        // from a structural board mutation (switch, reset, resize), where stale effects must
        // never carry across to the new board.
        if id == nil {
            pendingTaskCompletionMotions.removeAll()
        } else {
            presentNextPendingTaskCompletionMotionIfNeeded()
        }
    }

    private func updateTaskCompletionMotion(
        taskIsNowCompleted: Bool,
        triggeringCell: TaskCompletionMotion.CellCoordinate,
        newlyCompletedLines: Set<BingoLine>,
        isBoardNowFullyCompleted: Bool
    ) {
        guard taskIsNowCompleted else {
            // An undo only invalidates a celebration that actually contains this card. Before
            // this guard, undoing any unrelated task would remove an in-flight 4×4 Bingo and
            // make the PAG sequence look as if it had stopped partway through.
            guard let activeMotion = taskCompletionMotion,
                  activeMotion.triggeringCell == triggeringCell
                    || activeMotion.bingoCells.contains(triggeringCell) else {
                return
            }
            dismissTaskCompletionMotion()
            return
        }

        // A full-board completion owns the presentation. Do not layer the single-task or Bingo
        // effects underneath its dedicated screen.
        guard !isBoardNowFullyCompleted else {
            dismissTaskCompletionMotion()
            return
        }

        if newlyCompletedLines.isEmpty {
            presentTaskCompletionMotion(TaskCompletionMotion(
                kind: .singleTask,
                triggeringCell: triggeringCell
            ))
            return
        }

        presentTaskCompletionMotion(TaskCompletionMotion(
            kind: .bingo,
            triggeringCell: triggeringCell,
            bingoCells: cellCoordinates(in: newlyCompletedLines)
        ))
    }

    private func presentTaskCompletionMotion(_ newMotion: TaskCompletionMotion) {
        guard let currentMotion = taskCompletionMotion else {
            taskCompletionMotion = newMotion
            return
        }

        switch (currentMotion.kind, newMotion.kind) {
        case (.bingo, .bingo):
            // Do not restart the delayed top-level reveal. Retaining the original ID keeps its
            // task alive while newly completed 4×4 line cells join the background effect.
            taskCompletionMotion = TaskCompletionMotion(
                id: currentMotion.id,
                kind: .bingo,
                triggeringCell: currentMotion.triggeringCell,
                bingoCells: currentMotion.bingoCells.union(newMotion.bingoCells)
            )

        case (.bingo, .singleTask), (.singleTask, .singleTask):
            // Preserve the user's feedback, but never let it cover an active effect.
            pendingTaskCompletionMotions.append(newMotion)

        case (.singleTask, .bingo):
            // Bingo has higher presentation priority. Any already queued ordinary task effects
            // remain queued and will resume after the Bingo sequence finishes.
            taskCompletionMotion = newMotion
        }
    }

    private func presentNextPendingTaskCompletionMotionIfNeeded() {
        guard taskCompletionMotion == nil, !pendingTaskCompletionMotions.isEmpty else { return }
        taskCompletionMotion = pendingTaskCompletionMotions.removeFirst()
    }

    private func cellCoordinates(in lines: Set<BingoLine>) -> Set<TaskCompletionMotion.CellCoordinate> {
        var coordinates = Set<TaskCompletionMotion.CellCoordinate>()

        for line in lines {
            switch line {
            case .row(let row):
                for col in 0..<gridSize {
                    coordinates.insert(TaskCompletionMotion.CellCoordinate(row: row, col: col))
                }
            case .column(let col):
                for row in 0..<gridSize {
                    coordinates.insert(TaskCompletionMotion.CellCoordinate(row: row, col: col))
                }
            case .diagonalMain:
                for index in 0..<gridSize {
                    coordinates.insert(TaskCompletionMotion.CellCoordinate(row: index, col: index))
                }
            case .diagonalAnti:
                for row in 0..<gridSize {
                    coordinates.insert(TaskCompletionMotion.CellCoordinate(row: row, col: gridSize - 1 - row))
                }
            }
        }

        return coordinates
    }

    func isInCompletedLine(row: Int, col: Int) -> Bool {
        for line in completedLines {
            switch line {
            case .row(let r): if r == row { return true }
            case .column(let c): if c == col { return true }
            case .diagonalMain: if row == col { return true }
            case .diagonalAnti: if row + col == gridSize - 1 { return true }
            }
        }
        return false
    }

    func isLocked(row: Int, col: Int) -> Bool {
        guard !activeForcedPositions.isEmpty else { return false }
        return !activeForcedPositions.contains(Position(row: row, col: col))
    }

    private struct Position: Hashable {
        let row: Int
        let col: Int
    }

    private struct RewardTransitionState {
        let cells: [[BingoCell]]
        let completedLines: Set<BingoLine>
        let isBoardFullyCompleted: Bool
    }

    private var activeForcedPositions: Set<Position> {
        var positions: Set<Position> = []

        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                if cell.isForced && !cell.isCompleted && !cell.isEmpty && cell.isCurrentlyTappable(on: Date()) {
                    positions.insert(Position(row: row, col: col))
                }
            }
        }

        return positions
    }

    private var bingoLinePositions: Set<Position> {
        var positions: Set<Position> = []

        for line in completedLines {
            switch line {
            case .row(let row):
                for col in 0..<gridSize {
                    positions.insert(Position(row: row, col: col))
                }
            case .column(let col):
                for row in 0..<gridSize {
                    positions.insert(Position(row: row, col: col))
                }
            case .diagonalMain:
                for index in 0..<gridSize {
                    positions.insert(Position(row: index, col: index))
                }
            case .diagonalAnti:
                for row in 0..<gridSize {
                    positions.insert(Position(row: row, col: gridSize - 1 - row))
                }
            }
        }

        return positions
    }

    private func checkBingo(shouldCelebrateNewLines: Bool = true) {
        let currentLines = BoardEngine.completedLines(in: cells, size: gridSize)
        let newLines = currentLines.subtracting(completedLines)
        if !newLines.isEmpty && shouldCelebrateNewLines {
            presentBingoCelebration(for: newLines)
        } else if !shouldCelebrateNewLines {
            invalidateBingoCelebration()
        }
        completedLines = currentLines
    }

    private func presentBingoCelebration(for lines: Set<BingoLine>) {
        bingoCelebrationGeneration &+= 1
        let generation = bingoCelebrationGeneration
        newlyCompletedLines = Array(lines)
        showCelebration = true

        bingoCelebrationDismissScheduler(Self.bingoCelebrationDuration) { [weak self] in
            guard let self, self.bingoCelebrationGeneration == generation else { return }
            self.dismissBingoCelebration()
        }
    }

    private func invalidateBingoCelebration() {
        bingoCelebrationGeneration &+= 1
        dismissBingoCelebration()
    }

    private func dismissBingoCelebration() {
        if showCelebration {
            showCelebration = false
        }
        if !newlyCompletedLines.isEmpty {
            newlyCompletedLines = []
        }
    }

    private func refreshBoardState(
        shouldCelebrateNewLines: Bool,
        shouldPresentBoardCompletionAnimation: Bool? = nil,
        rewardSettlementMode: BingoRewardSettlementMode = .normal,
        rewardTransition: RewardTransitionState? = nil,
        rewardSettlementDate: Date? = nil
    ) {
        // Keep this as the single board-state commit path: cache sync, bingo detection, rewards, and persistence must stay ordered.
        let shouldPresentBoardCompletionAnimation = shouldPresentBoardCompletionAnimation ?? shouldCelebrateNewLines
        let wasBoardFullyCompleted = isBoardFullyCompleted
        syncFullBoardCacheFromVisibleCells()
        checkBingo(shouldCelebrateNewLines: shouldCelebrateNewLines)
        let isBoardNowFullyCompleted = isBoardFullyCompleted

        if shouldPresentBoardCompletionAnimation && !wasBoardFullyCompleted && isBoardNowFullyCompleted {
            presentBoardCompletionAnimation()
        } else if !isBoardNowFullyCompleted || !shouldPresentBoardCompletionAnimation {
            dismissBoardCompletionAnimation()
        }

        trackBingoCompletionIfNeeded(
            wasBoardFullyCompleted: wasBoardFullyCompleted,
            isBoardNowFullyCompleted: isBoardNowFullyCompleted
        )
        if let rewardTransition {
            settleBoardTransitionRewards(
                on: rewardSettlementDate ?? .now,
                previous: rewardTransition
            )
        } else {
            settleRewardsIfNeeded(mode: rewardSettlementMode)
        }
        save()
    }

    @discardableResult
    private func save(
        persistDiary: Bool = true,
        savedAt: Date = .now
    ) -> BingoViewModelPersistenceCommitResult {
        BingoViewModelPersistence.save(
            persistenceSnapshot(),
            persistDiary: persistDiary,
            savedAt: savedAt,
            dependencies: persistenceDependencies
        )
    }

    @discardableResult
    private func saveWithExplicitDiaryDelta(
        task: String,
        delta: Int,
        completionHistoryDelta: Int = 0,
        savedAt: Date = .now
    ) -> BingoViewModelPersistenceCommitResult {
        BingoViewModelPersistence.saveWithExplicitDiaryDelta(
            persistenceSnapshot(),
            task: task,
            delta: delta,
            completionHistoryDelta: completionHistoryDelta,
            savedAt: savedAt,
            dependencies: persistenceDependencies
        )
    }

    func processExpiredCountdowns(now: Date = Date()) {
        guard let deadline = BoardEngine.expiredBoardCountdownDeadline(boardCountdownEndsAt, now: now) else { return }
        guard expiredBoardCountdownEvent == nil else { return }

        expiredBoardCountdownEvent = ExpiredBoardCountdownEvent(expiredAt: deadline)
    }

    func processExpiredTaskCountdowns(now: Date = Date()) {
        guard expiredTaskEvent == nil, expiredBoardCountdownEvent == nil else { return }

        // Emit one prompt at a time so timeout resolution cannot race with another expired task or board countdown.
        guard let candidate = BoardEngine.expiredTaskCandidate(in: cells, now: now) else { return }
        expiredTaskEvent = ExpiredTaskEvent(
            cellID: candidate.cellID,
            row: candidate.row,
            col: candidate.col,
            taskText: candidate.taskText,
            expiredAt: candidate.expiredAt,
            expiredByCountdown: candidate.expiredByCountdown,
            expiredByVisibilityWindow: candidate.expiredByVisibilityWindow,
            allowsPostpone: candidate.allowsPostpone,
            taskDefinition: candidate.taskDefinition,
            boardID: persistenceDependencies.boardRepository.loadActiveNamedBoardID()
        )
    }

    @discardableResult
    func refreshVisibilityWindowsIfNeeded(now: Date = Date()) -> Bool {
        // Visibility windows are evaluated against the full board cache, then projected into the current grid size.
        var updatedCache = fullBoardCells
        var didMutateCache = false

        for row in 0..<min(gridSize, updatedCache.count) {
            for col in 0..<min(gridSize, updatedCache[row].count) {
                var cell = updatedCache[row][col]
                let trimmedTask = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTask.isEmpty else { continue }
                guard cell.shouldStartCountdownForCurrentOccurrence(on: now) else {
                    continue
                }

                cell.countdownEndsAt = cell.countdownDeadlineForCurrentOccurrence(
                    startingAt: now,
                    maxCountdownMinutes: Self.maxCountdownMinutes
                )
                cell.countdownPausedRemainingSeconds = nil
                updatedCache[row][col] = cell
                didMutateCache = true
            }
        }

        if didMutateCache {
            fullBoardCells = updatedCache
        }

        let projectedCells = BoardEngine.projectVisibleCells(from: fullBoardCells, size: gridSize, referenceDate: now)
        if projectedCells == cells {
            return didMutateCache
        }

        cells = projectedCells
        checkBingo(shouldCelebrateNewLines: false)
        if !isBoardFullyCompleted {
            dismissBoardCompletionAnimation()
        }
        settleRewardsIfNeeded(on: now, mode: .preserveAccumulatedPoints)
        save(persistDiary: false, savedAt: now)
        return true
    }

    func processScheduledTaskReplacementConflicts(now: Date = Date()) {
        guard scheduledTaskReplacementEvent == nil else { return }
        guard expiredTaskEvent == nil, expiredBoardCountdownEvent == nil else { return }

        // Scheduled replacements pause on conflicts so the user decides whether today's custom text or the preset wins.
        guard let candidate = BoardEngine.scheduledTaskReplacementCandidate(
            in: fullBoardCells,
            size: gridSize,
            ignoredCellIDs: ignoredScheduledReplacementCellIDs,
            now: now
        ) else { return }

        scheduledTaskReplacementEvent = ScheduledTaskReplacementEvent(
            cellID: candidate.cellID,
            row: candidate.row,
            col: candidate.col,
            currentTaskText: candidate.currentTaskText,
            presetTaskText: candidate.presetTaskText
        )
    }

    func requiresLiveCountdownTicks(now: Date = Date()) -> Bool {
        if expiredTaskEvent != nil || expiredBoardCountdownEvent != nil {
            return true
        }
        if let boardCountdownEndsAt, boardCountdownEndsAt > now {
            return true
        }
        return BoardEngine.hasActiveCountdownDisplay(in: cells, size: gridSize, now: now)
    }

    func nextTimeSensitiveUpdateDate(now: Date = Date()) -> Date? {
        var nextDate = BoardEngine.nextTimeSensitiveUpdateDate(
            in: fullBoardCells,
            size: gridSize,
            now: now
        )
        if let boardCountdownEndsAt {
            let candidate = boardCountdownEndsAt <= now ? now : boardCountdownEndsAt
            nextDate = nextDate.map { min($0, candidate) } ?? candidate
        }
        return nextDate
    }

    private func boardEngineExpiredTaskCandidate(from event: ExpiredTaskEvent) -> BoardEngine.ExpiredTaskCandidate {
        BoardEngine.ExpiredTaskCandidate(
            cellID: event.cellID,
            row: event.row,
            col: event.col,
            taskText: event.taskText,
            expiredAt: event.expiredAt,
            expiredByCountdown: event.expiredByCountdown,
            expiredByVisibilityWindow: event.expiredByVisibilityWindow,
            allowsPostpone: event.allowsPostpone,
            taskDefinition: event.taskDefinition
        )
    }

    private func boardEngineExpiredTaskResolution(
        for resolution: ExpiredTaskResolution
    ) -> BoardEngine.ExpiredTaskResolution {
        switch resolution {
        case .markAsCompleted:
            return .markAsCompleted
        case .abandon:
            return .abandon
        case .postpone(let minutes):
            return .postpone(minutes: minutes)
        }
    }

    private func boardEngineExpiredBoardCountdownResolution(
        for resolution: ExpiredBoardCountdownResolution
    ) -> BoardEngine.ExpiredBoardCountdownResolution {
        switch resolution {
        case .markAsCompleted:
            return .markAsCompleted
        case .abandon:
            return .abandon
        case .postpone(let minutes):
            return .postpone(minutes: minutes)
        }
    }

    func resolveExpiredTask(_ resolution: ExpiredTaskResolution, now: Date = Date()) -> String? {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        var message: String?
        let handled = persistenceDependencies.boardRepository.withTaskEditLock {
            message = resolveExpiredTaskUnderLock(resolution, now: now)
            return true
        }
        return handled ? message : L10n.tr(
            "Could not update this task. Please try again.",
            zhHans: "任务更新未成功，请重试。", zhHant: "任務更新未成功，請重試。",
            ja: "タスクを更新できませんでした。もう一度お試しください。"
        )
    }

    private func resolveExpiredTaskUnderLock(_ resolution: ExpiredTaskResolution, now: Date) -> String? {
        guard let event = expiredTaskEvent else { return nil }
        let candidate = boardEngineExpiredTaskCandidate(from: event)
        let persistedBoard = persistenceDependencies.boardRepository.loadBoard()
        let persistedCell = persistedBoard
            .map { BoardEngine.expandedBoardCache(from: $0).flatMap { $0 } }
            .flatMap { $0.first { $0.id == event.cellID } }
        guard event.boardID == persistenceDependencies.boardRepository.loadActiveNamedBoardID(),
              let persistedBoard,
              TaskRulePersistenceGuard.matchesStoredTasks(makeSavedBoardSnapshot(), persistedBoard),
              let currentCell = cells.flatMap({ $0 }).first(where: { $0.id == event.cellID }),
              let persistedCell,
              BoardEngine.isCurrentExpiredTask(currentCell, candidate: candidate, now: now),
              BoardEngine.isCurrentExpiredTask(persistedCell, candidate: candidate, now: now) else {
            expiredTaskEvent = nil
            DiagnosticLogStore.recordWarning("task_rule.stale_timeout_rejected", details: [
                "cell_id": event.cellID.uuidString,
                "board_id": event.boardID?.uuidString ?? "none"
            ])
            return L10n.tr(
                "This task has changed. The old timeout action was not applied.",
                zhHans: "任务已更新，未执行旧的超时操作。",
                zhHant: "任務已更新，未執行舊的逾時操作。",
                ja: "タスクが更新されたため、以前のタイムアウト操作は適用されませんでした。"
            )
        }

        if case .abandon = resolution,
           !TaskCompletionHistoryStore.archive(currentCell, at: now) {
            DiagnosticLogStore.recordWarning(
                "task_completion_history.archive_failed",
                details: ["source": "expired_task_abandon"]
            )
            return L10n.tr(
                "Could not save this task's completion history. Please try again.",
                zhHans: "任务完成历史保存失败，请重试。",
                zhHant: "任務完成歷史儲存失敗，請重試。",
                ja: "タスクの完了履歴を保存できませんでした。もう一度お試しください。"
            )
        }

        let rewardTransition = RewardTransitionState(
            cells: cells,
            completedLines: completedLines,
            isBoardFullyCompleted: isBoardFullyCompleted
        )

        guard let result = BoardEngine.resolveExpiredTask(
            in: cells,
            candidate: boardEngineExpiredTaskCandidate(from: event),
            resolution: boardEngineExpiredTaskResolution(for: resolution),
            now: now,
            maxCountdownMinutes: Self.maxCountdownMinutes
        ) else {
            expiredTaskEvent = nil
            return L10n.tr(
                "This timed-out task changed before it could be updated. Please try again.",
                zhHans: "该超时任务已发生变化，请刷新后重试。",
                zhHant: "該逾時任務已發生變化，請重新整理後再試。",
                ja: "タイムアウトしたタスクが変更されました。更新してもう一度お試しください。"
            )
        }

        expiredTaskEvent = nil
        if let unfinishedTaskText = result.unfinishedTimeoutTaskText {
            BingoTimeoutStore.recordUnfinishedTimeout(task: unfinishedTaskText, on: now)
        }
        cells = result.cells
        switch resolution {
        case .markAsCompleted:
            refreshBoardState(
                // Timeout completion used to route only through the legacy confetti
                // celebration. Keep that path disabled and create the same PAG-backed
                // motion state used when a person taps a task card.
                shouldCelebrateNewLines: false,
                shouldPresentBoardCompletionAnimation: true,
                rewardTransition: rewardTransition,
                rewardSettlementDate: now
            )
            updateTaskCompletionMotion(
                taskIsNowCompleted: true,
                triggeringCell: TaskCompletionMotion.CellCoordinate(row: event.row, col: event.col),
                newlyCompletedLines: completedLines.subtracting(rewardTransition.completedLines),
                isBoardNowFullyCompleted: isBoardFullyCompleted
            )
            return L10n.taskMarkedCompletedSuccess

        case .abandon:
            refreshBoardState(shouldCelebrateNewLines: false)
            return L10n.taskAbandonedSuccess

        case .postpone(let minutes):
            let clampedMinutes = result.clampedPostponeMinutes ?? min(max(minutes, 1), Self.maxCountdownMinutes)
            refreshBoardState(shouldCelebrateNewLines: false)
            return L10n.taskPostponedSuccess(clampedMinutes)
        }
    }

    func resolveScheduledTaskReplacement(
        _ resolution: ScheduledTaskReplacementResolution,
        now: Date = Date()
    ) -> String? {
        guard let event = scheduledTaskReplacementEvent else { return nil }
        defer {
            scheduledTaskReplacementEvent = nil
        }

        let position = resolveScheduledTaskReplacementPosition(for: event)
        guard let position else { return nil }
        let row = position.row
        let col = position.col
        guard row < fullBoardCells.count, col < fullBoardCells[row].count else { return nil }

        var cell = fullBoardCells[row][col]
        let currentText = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let presetText = (cell.residentTaskText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentText.isEmpty, !presetText.isEmpty, currentText != presetText else {
            return nil
        }

        switch resolution {
        case .replaceWithPreset:
            guard TaskCompletionHistoryStore.archive(cell, at: now) else {
                DiagnosticLogStore.recordWarning(
                    "task_completion_history.archive_failed",
                    details: ["source": "scheduled_task_replace"]
                )
                return L10n.tr(
                    "Could not save this task's completion history. Please try again.",
                    zhHans: "任务完成历史保存失败，请重试。",
                    zhHant: "任務完成歷史儲存失敗，請重試。",
                    ja: "タスクの完了履歴を保存できませんでした。もう一度お試しください。"
                )
            }
            cell.text = presetText
            cell.isCompleted = false
            cell.isTaskHidden = false
            cell.countdownEndsAt = nil
            cell.isForced = false
            cell.startVisibleMonth = nil
            cell.startVisibleDay = nil
            cell.residentTaskText = nil
            cell.recurrenceRule = nil
            cell.completionStreakCount = TaskCompletionHistoryStore.completionCount(for: presetText)
            cell.lastCompletedAt = nil
            fullBoardCells[row][col] = cell
            ignoredScheduledReplacementCellIDs.remove(cell.id)
            cells = visibleCells(from: fullBoardCells, size: gridSize)
            checkBingo(shouldCelebrateNewLines: false)
            settleRewardsIfNeeded(mode: .preserveAccumulatedPoints)
            save(persistDiary: false, savedAt: now)
            return L10n.tr("Task replaced with preset.", zhHans: "已替换为预设任务", zhHant: "已替換為預設任務")

        case .keepCurrentTask:
            cell.startVisibleMonth = nil
            cell.startVisibleDay = nil
            cell.residentTaskText = nil
            cell.recurrenceRule = nil
            cell.isForced = false
            fullBoardCells[row][col] = cell
            ignoredScheduledReplacementCellIDs.insert(cell.id)
            cells = visibleCells(from: fullBoardCells, size: gridSize)
            save(persistDiary: false, savedAt: now)
            return L10n.tr("Kept current task.", zhHans: "已保留当前任务", zhHant: "已保留目前任務")
        }
    }

    func dismissScheduledTaskReplacementPrompt() {
        guard let event = scheduledTaskReplacementEvent else { return }
        ignoredScheduledReplacementCellIDs.insert(event.cellID)
        scheduledTaskReplacementEvent = nil
    }

    private func resolveScheduledTaskReplacementPosition(for event: ScheduledTaskReplacementEvent) -> Position? {
        if event.row >= 0,
           event.col >= 0,
           event.row < fullBoardCells.count,
           event.col < fullBoardCells[event.row].count,
           fullBoardCells[event.row][event.col].id == event.cellID {
            return Position(row: event.row, col: event.col)
        }

        for row in fullBoardCells.indices {
            for col in fullBoardCells[row].indices where fullBoardCells[row][col].id == event.cellID {
                return Position(row: row, col: col)
            }
        }
        return nil
    }

    func resolveExpiredBoardCountdown(_ resolution: ExpiredBoardCountdownResolution, now: Date = Date()) -> String? {
        guard expiredBoardCountdownEvent != nil else { return nil }
        defer {
            expiredBoardCountdownEvent = nil
        }

        let rewardTransition = RewardTransitionState(
            cells: cells,
            completedLines: completedLines,
            isBoardFullyCompleted: isBoardFullyCompleted
        )

        let result = BoardEngine.resolveExpiredBoardCountdown(
            in: cells,
            resolution: boardEngineExpiredBoardCountdownResolution(for: resolution),
            now: now,
            maxCountdownMinutes: Self.maxCountdownMinutes
        )
        if result.cells != cells {
            cells = result.cells
        }
        boardCountdownEndsAt = result.boardCountdownEndsAt

        switch resolution {
        case .markAsCompleted:
            expiredTaskEvent = nil
            refreshBoardState(
                shouldCelebrateNewLines: true,
                rewardTransition: rewardTransition,
                rewardSettlementDate: now
            )
            return L10n.boardMarkedCompletedSuccess

        case .abandon:
            save()
            return L10n.boardCountdownCanceledSuccess

        case .postpone(let minutes):
            let clampedMinutes = result.clampedPostponeMinutes ?? min(max(minutes, 1), Self.maxCountdownMinutes)
            save()
            return L10n.boardCountdownPostponedSuccess(clampedMinutes)
        }
    }

    func applyForegroundCleanup() {
        invalidateBingoCelebration()
        dismissBoardCompletionAnimation()
    }

    func finalizePostResetState(
        now: Date = .now,
        didBoardCountdownExist: Bool,
        clearedCompletedTaskCount: Int
    ) {
        _ = didBoardCountdownExist
        applyDailyHousekeeping(now: now)
        settleRewardsIfNeeded(on: now)
        save(persistDiary: false, savedAt: now)
        syncDiarySnapshot()
        notifyDailyResetApplied(clearedCount: clearedCompletedTaskCount)
    }

    private func applyDailyHousekeeping(now: Date) {
        completedLines = []
        invalidateBingoCelebration()
        dismissBoardCompletionAnimation()
        dailyRewardState = BingoRewardSettlement.emptyDailyRewardState(for: now)
    }

    private func notifyDailyResetApplied(clearedCount: Int) {
        guard clearedCount > 0 else { return }
        dailyResetNoticeID += 1
    }

    @discardableResult
    private func syncDiarySnapshot() -> BingoViewModelPersistenceCommitResult {
        BingoViewModelPersistence.syncDiarySnapshot(
            persistenceSnapshot(),
            dependencies: persistenceDependencies
        )
    }

    private func persistenceSnapshot() -> BingoViewModelPersistenceSnapshot {
        BingoViewModelPersistenceSnapshot(
            board: SavedBoard(
                gridSize: gridSize,
                cells: cells,
                completedLines: completedLines,
                fullBoardCells: fullBoardCells
            ),
            boardCountdownEndsAt: boardCountdownEndsAt,
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState
        )
    }

    private func calculateBoardScore() -> Int {
        BoardEngine.boardScore(cells: cells, completedLines: completedLines)
    }

    private var isBoardFullyCompleted: Bool {
        BoardEngine.isBoardFullyCompleted(cells)
    }

    private func syncFullBoardCacheFromVisibleCells() {
        for row in 0..<min(gridSize, fullBoardCells.count, cells.count) {
            for col in 0..<min(gridSize, fullBoardCells[row].count, cells[row].count) {
                fullBoardCells[row][col] = cells[row][col]
            }
        }
    }

    private func boardCacheByApplyingEditedCell(
        _ editedCell: BingoCell,
        row: Int,
        col: Int
    ) -> [[BingoCell]] {
        var updatedCache = fullBoardCells
        for visibleRow in 0..<min(gridSize, updatedCache.count, cells.count) {
            for visibleCol in 0..<min(gridSize, updatedCache[visibleRow].count, cells[visibleRow].count) {
                updatedCache[visibleRow][visibleCol] = cells[visibleRow][visibleCol]
            }
        }
        guard row < updatedCache.count, col < updatedCache[row].count else {
            return updatedCache
        }
        updatedCache[row][col] = editedCell

        if editedCell.isForced {
            // Keep force mode deterministic across visible and cached grid sizes.
            for cacheRow in updatedCache.indices {
                for cacheCol in updatedCache[cacheRow].indices where !(cacheRow == row && cacheCol == col) {
                    updatedCache[cacheRow][cacheCol].isForced = false
                }
            }
        }
        return updatedCache
    }

    private func registerCompletionIfNeeded(row: Int, col: Int, now: Date) {
        guard row < cells.count, col < cells[row].count else { return }
        guard !cells[row][col].isEmpty else { return }

        cells[row][col].completionStreakCount += 1
        cells[row][col].lastCompletedAt = now
    }

    /// Every active cell with the same canonical task name displays the same
    /// name-scoped lifetime total, while its completion state remains local.
    private func synchronizeCompletionHistoryCount(
        for taskText: String,
        count: Int,
        referenceDate: Date
    ) {
        guard let key = TaskCompletionHistoryRuleEngine.normalizedKey(for: taskText) else { return }
        for row in fullBoardCells.indices {
            for col in fullBoardCells[row].indices where
                TaskCompletionHistoryRuleEngine.normalizedKey(for: fullBoardCells[row][col].storedTaskText) == key {
                fullBoardCells[row][col].completionStreakCount = count
            }
        }
        cells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: gridSize,
            referenceDate: referenceDate
        )
    }

    private func reconcileCompletionHistoryCounts() {
        let records = persistenceDependencies.completionHistoryRepository.loadCompletionHistory()
        let reconciledBoard = TaskCompletionHistoryRuleEngine.boardByReconcilingCompletionHistory(
            SavedBoard(
                gridSize: gridSize,
                cells: cells,
                completedLines: completedLines,
                fullBoardCells: fullBoardCells
            ),
            records: records
        )
        fullBoardCells = reconciledBoard.fullBoardCells ?? BoardEngine.expandedBoardCache(from: reconciledBoard)
        cells = BoardEngine.projectVisibleCells(from: fullBoardCells, size: gridSize, referenceDate: .now)
    }

    private func visibleCells(from cache: [[BingoCell]], size: Int) -> [[BingoCell]] {
        BoardEngine.projectVisibleCells(from: cache, size: size, referenceDate: .now)
    }

    private func repairDuplicateCellIDsIfNeeded(referenceDate: Date = .now) {
        var seenIDs = Set<UUID>()
        var didRepair = false

        for row in fullBoardCells.indices {
            for col in fullBoardCells[row].indices {
                let current = fullBoardCells[row][col]
                if seenIDs.insert(current.id).inserted {
                    continue
                }
                fullBoardCells[row][col] = remintedCell(current)
                didRepair = true
            }
        }

        guard didRepair else { return }
        cells = BoardEngine.projectVisibleCells(from: fullBoardCells, size: gridSize, referenceDate: referenceDate)
        save(persistDiary: false, savedAt: referenceDate)
    }

    private func remintedCell(_ cell: BingoCell) -> BingoCell {
        BingoCell(
            id: UUID(),
            text: cell.text,
            residentTaskText: cell.residentTaskText,
            residentWeekdays: cell.residentWeekdays,
            oneTimeVisibleDate: cell.oneTimeVisibleDate,
            recurrenceRule: cell.recurrenceRule,
            startVisibleAt: cell.startVisibleAt,
            endVisibleAt: cell.endVisibleAt,
            usesRecurringTimeWindow: cell.usesRecurringTimeWindow,
            startReminderEnabled: cell.startReminderEnabled,
            startReminderOffsetMinutes: cell.startReminderOffsetMinutes,
            startVisibleMonth: cell.startVisibleMonth,
            startVisibleDay: cell.startVisibleDay,
            isTaskHidden: cell.isTaskHidden,
            isCompleted: cell.isCompleted,
            isForced: cell.isForced,
            countdownEndsAt: cell.countdownEndsAt,
            countdownPausedRemainingSeconds: cell.countdownPausedRemainingSeconds,
            estimatedDurationMinutes: cell.estimatedDurationMinutes,
            completionStreakCount: cell.completionStreakCount,
            lastCompletedAt: cell.lastCompletedAt,
            lastVisibilityWindowTimeoutAt: cell.lastVisibilityWindowTimeoutAt
        )
    }

    private func taskPoolSlots(maxSize: Int) -> [Position] {
        guard maxSize > 0 else { return [] }

        var slots: [Position] = []
        slots.reserveCapacity(maxSize * maxSize)

        for size in 1...maxSize {
            let edge = size - 1
            for row in 0..<size {
                for col in 0..<size where row == edge || col == edge {
                    slots.append(Position(row: row, col: col))
                }
            }
        }

        return slots
    }

    private func canMoveSlot(_ cell: BingoCell) -> Bool {
        !cell.hasResidentSchedule
    }

    private func settleRewardsIfNeeded(
        on date: Date = .now,
        mode: BingoRewardSettlementMode = .normal
    ) {
        // Reward settlement is pure; only this wrapper mutates published point state and persists it through save().
        let output = BingoRewardSettlement.settle(
            input: BingoRewardSettlementInput(
                date: date,
                cells: cells,
                completedLines: completedLines,
                isBoardFullyCompleted: isBoardFullyCompleted,
                totalPoints: totalPoints,
                lifetimePoints: lifetimePoints,
                dailyRewardState: dailyRewardState
            ),
            mode: mode
        )
        totalPoints = output.totalPoints
        lifetimePoints = output.lifetimePoints
        dailyRewardState = output.dailyRewardState
    }

    private func settleTaskToggleRewards(
        on date: Date,
        previousCells: [[BingoCell]],
        previousCompletedLines: Set<BingoLine>,
        previousIsBoardFullyCompleted: Bool,
        taskIsNowCompleted: Bool
    ) {
        let output = BingoRewardSettlement.settleTaskToggle(
            date: date,
            previousCells: previousCells,
            previousCompletedLines: previousCompletedLines,
            previousIsBoardFullyCompleted: previousIsBoardFullyCompleted,
            currentCells: cells,
            currentCompletedLines: completedLines,
            currentIsBoardFullyCompleted: isBoardFullyCompleted,
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState,
            taskIsNowCompleted: taskIsNowCompleted
        )
        totalPoints = output.totalPoints
        lifetimePoints = output.lifetimePoints
        dailyRewardState = output.dailyRewardState
    }

    private func settleBoardTransitionRewards(
        on date: Date,
        previous: RewardTransitionState
    ) {
        let output = BingoRewardSettlement.settleBoardTransition(
            date: date,
            previousCells: previous.cells,
            previousCompletedLines: previous.completedLines,
            previousIsBoardFullyCompleted: previous.isBoardFullyCompleted,
            currentCells: cells,
            currentCompletedLines: completedLines,
            currentIsBoardFullyCompleted: isBoardFullyCompleted,
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState
        )
        totalPoints = output.totalPoints
        lifetimePoints = output.lifetimePoints
        dailyRewardState = output.dailyRewardState
    }

    private func reloadPersistedPointsState(referenceDate: Date) {
        let persistedPoints = persistenceDependencies.pointsRepository.loadPersistenceSnapshot()

        if let persistedTotalPoints = persistedPoints.totalPoints {
            totalPoints = persistedTotalPoints
        }

        if let persistedLifetimePoints = persistedPoints.lifetimePoints {
            lifetimePoints = persistedLifetimePoints
        } else if let persistedTotalPoints = persistedPoints.totalPoints {
            lifetimePoints = persistedTotalPoints
        }

        dailyRewardState = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: referenceDate,
            boardLastSavedAt: referenceDate,
            currentCells: cells,
            currentCompletedLines: completedLines,
            isBoardFullyCompleted: isBoardFullyCompleted,
            savedDailyRewardState: persistedPoints.dailyRewardState
        )
    }

    /// Widget and iCloud writes land in the shared stores outside this view model's
    /// memory. Rebase before a user tap so an older on-screen total can never write
    /// over newer persisted points (for example, after a WidgetKit completion).
    private func refreshExternalPersistenceBeforeTaskToggle(referenceDate: Date) {
        let persistedPoints = persistenceDependencies.pointsRepository.loadPersistenceSnapshot()
        let hasPersistedPointChange = persistedPoints.totalPoints != totalPoints ||
            persistedPoints.lifetimePoints != lifetimePoints ||
            persistedPoints.dailyRewardState != dailyRewardState

        guard let persistedBoard = persistenceDependencies.boardRepository.loadBoard() else {
            if hasPersistedPointChange {
                reloadPersistedPointsState(referenceDate: referenceDate)
            }
            return
        }

        let localBoard = BingoBoardStore.normalizedBoardForPersistence(
            persistenceSnapshot().board,
            referenceDate: referenceDate
        )
        guard BingoBoardStore.hasMatchingCellIdentity(localBoard, persistedBoard) else {
            // A board selection change is owned by ContentView/BoardManagementStore.
            // Do not reinterpret a tap at the same coordinates on a different board.
            return
        }

        if persistedBoard != localBoard {
            applySavedBoardSnapshot(
                persistedBoard,
                countdownEndsAt: persistenceDependencies.boardRepository.loadBoardCountdownEndsAt(),
                referenceDate: referenceDate,
                reloadPersistedPoints: true,
                persist: false
            )
        } else if hasPersistedPointChange {
            reloadPersistedPointsState(referenceDate: referenceDate)
        }
    }

    private static func normalizeForceFlagsInBoardCache(
        _ cache: inout [[BingoCell]],
        referenceDate: Date
    ) {
        var forcedPositions: [(row: Int, col: Int)] = []

        for row in cache.indices {
            for col in cache[row].indices {
                guard cache[row][col].isForced else { continue }

                if !cache[row][col].hasStoredTask || cache[row][col].isCompleted {
                    cache[row][col].isForced = false
                    continue
                }

                forcedPositions.append((row, col))
            }
        }

        guard forcedPositions.count > 1 else { return }

        let keepPosition = forcedPositions.first {
            let projected = cache[$0.row][$0.col].projectedForDisplay(on: referenceDate)
            return !projected.isEmpty
        } ?? forcedPositions[0]

        for position in forcedPositions where !(position.row == keepPosition.row && position.col == keepPosition.col) {
            cache[position.row][position.col].isForced = false
        }
    }

    private func trackBingoCompletionIfNeeded(
        wasBoardFullyCompleted: Bool,
        isBoardNowFullyCompleted: Bool
    ) {
        guard !wasBoardFullyCompleted, isBoardNowFullyCompleted else { return }

        let filledTaskCount = cells
            .flatMap { $0 }
            .filter { !$0.isEmpty }
            .count

        AnalyticsService.logBingoCompleted(
            boardSize: gridSize,
            completedLineCount: completedLines.count,
            filledTaskCount: filledTaskCount
        )
    }
}
