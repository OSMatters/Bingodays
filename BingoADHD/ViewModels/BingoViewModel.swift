import SwiftUI
import Combine

class BingoViewModel: ObservableObject {
    static let maxGridSize = BoardEngine.maxGridSize
    static let defaultInitialGridSize = 3
    static let maxTaskLength = 20
    static let maxCountdownMinutes = 30 * 24 * 60

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

        init(
            id: UUID = UUID(),
            cellID: UUID,
            row: Int,
            col: Int,
            taskText: String,
            expiredAt: Date,
            expiredByCountdown: Bool,
            expiredByVisibilityWindow: Bool,
            allowsPostpone: Bool
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
    @Published var showBoardCompletionAnimation = false
    @Published var dailyResetNoticeID = 0
    private var fullBoardCells: [[BingoCell]]
    private var lifetimePoints: Int
    private var dailyRewardState: DailyRewardState
    private let persistenceDependencies: BingoViewModelPersistenceDependencies
    private var ignoredScheduledReplacementCellIDs = Set<UUID>()

    init(persistenceDependencies: BingoViewModelPersistenceDependencies = .live) {
        self.persistenceDependencies = persistenceDependencies
        self.totalPoints = 0
        self.lifetimePoints = 0
        self.dailyRewardState = DailyRewardState(dateKey: PointsStore.dateKey(for: .now))
        self.boardCountdownEndsAt = persistenceDependencies.boardRepository.loadBoardCountdownEndsAt()
        let now = Date()
        var existingSavedAt: Date?
        if let saved = persistenceDependencies.boardRepository.loadBoard() {
            existingSavedAt = persistenceDependencies.boardRepository.loadBoardLastSavedAt()
            let savedAt = existingSavedAt ?? now
            var expandedCache = BoardEngine.expandedBoardCache(from: saved)
            Self.normalizeForceFlagsInBoardCache(&expandedCache, referenceDate: now)
            self.fullBoardCells = expandedCache
            self.gridSize = saved.gridSize
            self.cells = BoardEngine.projectVisibleCells(
                from: self.fullBoardCells,
                size: saved.gridSize,
                referenceDate: now
            )
            self.completedLines = saved.completedLines
            let normalizedBoard = SavedBoard(
                gridSize: saved.gridSize,
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
        self.totalPoints = persistenceDependencies.pointsRepository.loadTotalPoints() ?? calculateBoardScore()
        self.lifetimePoints = persistenceDependencies.pointsRepository.loadLifetimePoints() ?? self.totalPoints
        self.dailyRewardState = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: now,
            boardLastSavedAt: existingSavedAt,
            currentCells: self.cells,
            currentCompletedLines: self.completedLines,
            isBoardFullyCompleted: self.isBoardFullyCompleted,
            savedDailyRewardState: persistenceDependencies.pointsRepository.loadDailyRewardState()
        )
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
        guard canToggleComplete(row: row, col: col, referenceDate: referenceDate) else { return }
        let wasBoardFullyCompleted = isBoardFullyCompleted
        let isNowCompleted = !cells[row][col].isCompleted
        let diaryTaskText = cells[row][col].storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        checkBingo()
        let isBoardNowFullyCompleted = isBoardFullyCompleted
        if !wasBoardFullyCompleted && isBoardNowFullyCompleted {
            showBoardCompletionAnimation = true
        } else if !isBoardNowFullyCompleted {
            showBoardCompletionAnimation = false
        }
        trackBingoCompletionIfNeeded(
            wasBoardFullyCompleted: wasBoardFullyCompleted,
            isBoardNowFullyCompleted: isBoardNowFullyCompleted
        )
        settleRewardsIfNeeded(on: referenceDate)
        saveWithExplicitDiaryDelta(
            task: diaryTaskText,
            delta: isNowCompleted ? 1 : -1
        )
    }

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
        startReminderOffsetMinutes: Int = BingoCell.defaultStartReminderOffsetMinutes
    ) {
        guard row < cells.count, col < cells[row].count else { return }
        let previousCell = cells[row][col]
        let limitedText = String(text.prefix(Self.maxTaskLength))
        let trimmedText = limitedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStartVisibilityAt = trimmedText.isEmpty ? nil : normalizedStartVisibility(date: startVisibleAt)
        let normalizedEndVisibilityAt = trimmedText.isEmpty ? nil : normalizedEndVisibility(date: endVisibleAt, startVisibleAt: normalizedStartVisibilityAt)
        let recurrenceDefaultDate = normalizedStartVisibilityAt ?? Date()
        let normalizedRecurrenceRule = trimmedText.isEmpty ? nil : recurrenceRule?.normalized(
            defaultWeekday: Calendar.current.component(.weekday, from: recurrenceDefaultDate),
            defaultMonthDay: Calendar.current.component(.day, from: recurrenceDefaultDate),
            defaultAnchorDate: recurrenceDefaultDate
        )
        let normalizedWeekdays: Set<Int>
        if normalizedRecurrenceRule?.kind == .weekly {
            normalizedWeekdays = normalizedRecurrenceRule?.weekdays ?? []
        } else {
            normalizedWeekdays = trimmedText.isEmpty || normalizedRecurrenceRule != nil ? [] : residentWeekdays
        }
        let hasRepeatingSchedule = normalizedRecurrenceRule.map { $0.kind != .none } ?? !normalizedWeekdays.isEmpty
        let allowsTaskCountdown = !trimmedText.isEmpty && !hasRepeatingSchedule
        let normalizedEstimatedDurationMinutes = allowsTaskCountdown
            ? estimatedDurationMinutes.map { min(max($0, 1), Self.maxCountdownMinutes) }
            : nil
        let normalizedOneTimeTask = !trimmedText.isEmpty && (normalizedRecurrenceRule?.kind == TaskRecurrenceRule.Kind.none || (normalizedRecurrenceRule == nil && isOneTimeTask))
        let normalizedOneTimeVisibleDate = normalizedOneTimeTask
            ? (normalizedRecurrenceRule?.anchorDate ?? normalizedStartVisibilityAt ?? Date())
            : nil
        let normalizedReminderEnabled = !trimmedText.isEmpty && !previousCell.isCompleted && normalizedStartVisibilityAt != nil && normalizedEndVisibilityAt != nil && startReminderEnabled
        let normalizedReminderOffset = BingoCell.normalizedStartReminderOffsetMinutes(startReminderOffsetMinutes)
        let normalizedUsesRecurringTimeWindow: Bool
        if let recurrenceKind = normalizedRecurrenceRule?.kind {
            normalizedUsesRecurringTimeWindow = recurrenceKind != .none &&
                (normalizedStartVisibilityAt != nil || normalizedEndVisibilityAt != nil)
        } else {
            normalizedUsesRecurringTimeWindow = false
        }
        let usesStoredSchedule = normalizedRecurrenceRule != nil || !normalizedWeekdays.isEmpty || normalizedOneTimeTask || normalizedStartVisibilityAt != nil || normalizedEndVisibilityAt != nil
        let previousTaskIdentity = taskIdentity(for: previousCell)
        let updatedTaskIdentity = TaskIdentity(
            text: trimmedText,
            residentWeekdays: normalizedWeekdays,
            oneTimeVisibleDate: normalizedOneTimeVisibleDate,
            recurrenceRule: normalizedRecurrenceRule,
            startVisibleAt: normalizedStartVisibilityAt,
            endVisibleAt: normalizedEndVisibilityAt,
            usesRecurringTimeWindow: normalizedUsesRecurringTimeWindow
        )
        let didChangeTaskIdentity = previousTaskIdentity != updatedTaskIdentity

        cells[row][col].residentWeekdays = normalizedWeekdays
        cells[row][col].oneTimeVisibleDate = normalizedOneTimeVisibleDate
        cells[row][col].recurrenceRule = normalizedRecurrenceRule
        cells[row][col].startVisibleAt = normalizedStartVisibilityAt
        cells[row][col].endVisibleAt = normalizedEndVisibilityAt
        cells[row][col].usesRecurringTimeWindow = normalizedUsesRecurringTimeWindow
        cells[row][col].startReminderEnabled = normalizedReminderEnabled
        cells[row][col].startReminderOffsetMinutes = normalizedReminderOffset
        cells[row][col].startVisibleMonth = nil
        cells[row][col].startVisibleDay = nil
        cells[row][col].residentTaskText = usesStoredSchedule ? limitedText : nil
        cells[row][col].text = usesStoredSchedule ? normalizedDisplayText(for: cells[row][col], referenceDate: .now) : limitedText
        cells[row][col].isTaskHidden = false
        cells[row][col].isForced = !trimmedText.isEmpty && isForced
        cells[row][col].countdownEndsAt = nil
        cells[row][col].countdownPausedRemainingSeconds = nil
        cells[row][col].lastVisibilityWindowTimeoutAt = nil
        cells[row][col].estimatedDurationMinutes = normalizedEstimatedDurationMinutes

        if cells[row][col].isForced {
            // Keep force mode deterministic: only one active forced task per board.
            clearForceFlagsExcept(row: row, col: col)
        }
        if didChangeTaskIdentity {
            cells[row][col].completionStreakCount = 0
            cells[row][col].lastCompletedAt = nil
        }
        if previousCell.isCompleted && didChangeTaskIdentity {
            cells[row][col].isCompleted = false
            cells[row][col].isTaskHidden = false
            cells[row][col].countdownPausedRemainingSeconds = nil
            cells[row][col].lastCompletedAt = nil
        }

        if trimmedText.isEmpty {
            cells[row][col].isCompleted = false
            cells[row][col].isForced = false
            cells[row][col].countdownEndsAt = nil
            cells[row][col].countdownPausedRemainingSeconds = nil
            cells[row][col].residentTaskText = nil
            cells[row][col].residentWeekdays = []
            cells[row][col].oneTimeVisibleDate = nil
            cells[row][col].recurrenceRule = nil
            cells[row][col].startVisibleAt = nil
            cells[row][col].endVisibleAt = nil
            cells[row][col].usesRecurringTimeWindow = false
            cells[row][col].startVisibleMonth = nil
            cells[row][col].startVisibleDay = nil
            cells[row][col].estimatedDurationMinutes = nil
            cells[row][col].completionStreakCount = 0
            cells[row][col].lastCompletedAt = nil
            cells[row][col].lastVisibilityWindowTimeoutAt = nil
            if expiredTaskEvent?.cellID == cells[row][col].id {
                expiredTaskEvent = nil
            }
            if scheduledTaskReplacementEvent?.cellID == cells[row][col].id {
                scheduledTaskReplacementEvent = nil
            }
        } else if cells[row][col].shouldStartCountdownForCurrentOccurrence(on: .now) {
            cells[row][col].countdownEndsAt = cells[row][col].countdownDeadlineForCurrentOccurrence(
                startingAt: .now,
                maxCountdownMinutes: Self.maxCountdownMinutes
            )
            cells[row][col].countdownPausedRemainingSeconds = nil
        }
        syncFullBoardCacheFromVisibleCells()
        ignoredScheduledReplacementCellIDs.remove(cells[row][col].id)
        cells = visibleCells(from: fullBoardCells, size: gridSize)
        checkBingo()
        if !isBoardFullyCompleted {
            showBoardCompletionAnimation = false
        }
        let rewardMode: BingoRewardSettlementMode = trimmedText.isEmpty ? .preserveAccumulatedPoints : .normal
        settleRewardsIfNeeded(mode: rewardMode)

        if !trimmedText.isEmpty {
            TaskHistoryStore.upsert(
                task: MyTaskItem(
                    text: trimmedText,
                    startAt: normalizedStartVisibilityAt,
                    endAt: normalizedEndVisibilityAt
                )
            )
        } else if let previousTask = BingoTaskBoardHelpers.taskItem(from: previousCell, maxLength: Self.maxTaskLength) {
            TaskHistoryStore.upsert(task: previousTask)
        }
        save()
    }

    private func normalizedStartVisibility(date: Date?) -> Date? {
        date
    }

    private static func dateFromLegacyMonthDay(month: Int?, day: Int?) -> Date? {
        guard let month, let day else { return nil }
        var components = Calendar.current.dateComponents([.year], from: Date())
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

    private func normalizedEndVisibility(date: Date?, startVisibleAt: Date?) -> Date? {
        guard let date else { return nil }
        if let startVisibleAt, date <= startVisibleAt {
            return nil
        }
        return date
    }

    private struct TaskIdentity: Equatable {
        let text: String
        let residentWeekdays: Set<Int>
        let oneTimeVisibleDate: Date?
        let recurrenceRule: TaskRecurrenceRule?
        let startVisibleAt: Date?
        let endVisibleAt: Date?
        let usesRecurringTimeWindow: Bool
    }

    private func taskIdentity(for cell: BingoCell) -> TaskIdentity {
        TaskIdentity(
            text: cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines),
            residentWeekdays: cell.residentWeekdays,
            oneTimeVisibleDate: cell.oneTimeVisibleDate,
            recurrenceRule: cell.recurrenceRule,
            startVisibleAt: cell.startVisibleAt,
            endVisibleAt: cell.endVisibleAt,
            usesRecurringTimeWindow: cell.usesRecurringTimeWindow
        )
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
        guard row >= 0, col >= 0 else { return false }
        guard row < min(gridSize, fullBoardCells.count),
              col < min(gridSize, fullBoardCells[row].count) else {
            return false
        }

        var cell = fullBoardCells[row][col]
        guard cell.hasStoredTask else { return false }

        if let minutes {
            guard cell.canManuallySetTaskCountdown,
                  !cell.completionApplies(on: referenceDate) else {
                return false
            }
            cell.estimatedDurationMinutes = min(max(minutes, 1), Self.maxCountdownMinutes)
            cell.countdownEndsAt = nil
            cell.countdownPausedRemainingSeconds = nil
            if cell.shouldStartCountdownForCurrentOccurrence(on: referenceDate) {
                cell.countdownEndsAt = cell.countdownDeadlineForCurrentOccurrence(
                    startingAt: referenceDate,
                    maxCountdownMinutes: Self.maxCountdownMinutes
                )
            }
        } else {
            cell.estimatedDurationMinutes = nil
            cell.countdownEndsAt = nil
            cell.countdownPausedRemainingSeconds = nil
        }

        fullBoardCells[row][col] = cell
        cells = BoardEngine.projectVisibleCells(from: fullBoardCells, size: gridSize, referenceDate: referenceDate)
        if expiredTaskEvent?.cellID == cell.id, cell.countdownEndsAt == nil {
            expiredTaskEvent = nil
        }
        save(persistDiary: false, savedAt: referenceDate)
        return true
    }

    @discardableResult
    func pauseTaskCountdown(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        guard row >= 0, col >= 0 else { return false }
        guard row < min(gridSize, fullBoardCells.count),
              col < min(gridSize, fullBoardCells[row].count) else {
            return false
        }

        var cell = fullBoardCells[row][col]
        guard cell.canUseTaskCountdown,
              cell.isCurrentlyTappable(on: referenceDate),
              !cell.completionApplies(on: referenceDate),
              let deadline = cell.countdownEndsAt else {
            return false
        }

        let remainingSeconds = max(Int(ceil(deadline.timeIntervalSince(referenceDate))), 0)
        guard remainingSeconds > 0 else { return false }
        cell.countdownPausedRemainingSeconds = remainingSeconds
        cell.countdownEndsAt = nil

        fullBoardCells[row][col] = cell
        cells = BoardEngine.projectVisibleCells(from: fullBoardCells, size: gridSize, referenceDate: referenceDate)
        save(persistDiary: false, savedAt: referenceDate)
        return true
    }

    @discardableResult
    func resumeTaskCountdown(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        guard row >= 0, col >= 0 else { return false }
        guard row < min(gridSize, fullBoardCells.count),
              col < min(gridSize, fullBoardCells[row].count) else {
            return false
        }

        var cell = fullBoardCells[row][col]
        guard cell.canUseTaskCountdown,
              cell.isCurrentlyTappable(on: referenceDate),
              !cell.completionApplies(on: referenceDate),
              let pausedSeconds = cell.countdownPausedRemainingSeconds,
              pausedSeconds > 0 else {
            return false
        }

        let resumedDeadline = referenceDate.addingTimeInterval(Double(pausedSeconds))
        if let endDeadline = cell.occurrenceEndVisibleAt(on: referenceDate),
           endDeadline > referenceDate {
            cell.countdownEndsAt = min(resumedDeadline, endDeadline)
        } else {
            cell.countdownEndsAt = resumedDeadline
        }
        cell.countdownPausedRemainingSeconds = nil

        fullBoardCells[row][col] = cell
        cells = BoardEngine.projectVisibleCells(from: fullBoardCells, size: gridSize, referenceDate: referenceDate)
        save(persistDiary: false, savedAt: referenceDate)
        return true
    }

    @discardableResult
    func cancelTaskCountdown(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        setTaskCountdown(row: row, col: col, minutes: nil, referenceDate: referenceDate)
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

    func editingCell(row: Int, col: Int) -> BingoCell? {
        guard row >= 0, col >= 0 else { return nil }
        guard row < min(gridSize, fullBoardCells.count),
              col < min(gridSize, fullBoardCells[row].count) else { return nil }
        return fullBoardCells[row][col]
    }

    func toggleTaskHidden(row: Int, col: Int) {
        guard row < cells.count, col < cells[row].count else { return }
        guard !cells[row][col].isEmpty, cells[row][col].isCompleted else { return }
        guard !isLocked(row: row, col: col) else { return }

        cells[row][col].isTaskHidden.toggle()
        syncFullBoardCacheFromVisibleCells()
        save()
    }

    @discardableResult
    func deleteCell(row: Int, col: Int) -> BingoCell? {
        guard row < cells.count, col < cells[row].count else { return nil }
        let deletedCell = cells[row][col]
        guard !deletedCell.isEmpty else { return nil }
        if let deletedTask = BingoTaskBoardHelpers.taskItem(from: deletedCell, maxLength: Self.maxTaskLength) {
            TaskHistoryStore.upsert(task: deletedTask)
        }

        cells[row][col] = BingoCell()
        refreshBoardState(
            shouldCelebrateNewLines: false,
            rewardSettlementMode: .preserveAccumulatedPoints
        )
        return deletedCell
    }

    func restoreCell(_ cell: BingoCell, row: Int, col: Int) {
        guard row < cells.count, col < cells[row].count else { return }
        cells[row][col] = cell.projectedForDisplay(on: .now)
        refreshBoardState(
            shouldCelebrateNewLines: false,
            rewardSettlementMode: .preserveAccumulatedPoints
        )
    }

    func moveCell(from source: (row: Int, col: Int), to destination: (row: Int, col: Int)) {
        guard source.row < cells.count, source.col < cells[source.row].count else { return }
        guard destination.row < cells.count, destination.col < cells[destination.row].count else { return }
        guard source != destination else { return }
        guard !cells[source.row][source.col].isEmpty else { return }

        let sourceCell = cells[source.row][source.col]
        cells[source.row][source.col] = cells[destination.row][destination.col]
        cells[destination.row][destination.col] = sourceCell
        refreshBoardState(
            shouldCelebrateNewLines: false
        )
    }

    @discardableResult
    func applyTasksToEmptyCells(_ tasks: [String]) -> Bool {
        let sanitizedTasks = tasks
            .map { String($0.prefix(Self.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sanitizedTasks.isEmpty else { return true }

        let emptyPositions = cells.enumerated().flatMap { row, rowCells in
            rowCells.enumerated().compactMap { entry -> Position? in
                let position = Position(row: row, col: entry.offset)
                return canAcceptNewTask(entry.element) ? position : nil
            }
        }

        guard emptyPositions.count >= sanitizedTasks.count else { return false }

        for (position, task) in zip(emptyPositions, sanitizedTasks) {
            cells[position.row][position.col].text = task
            cells[position.row][position.col].residentTaskText = nil
            cells[position.row][position.col].residentWeekdays = []
            cells[position.row][position.col].oneTimeVisibleDate = nil
            cells[position.row][position.col].recurrenceRule = nil
            cells[position.row][position.col].isTaskHidden = false
            cells[position.row][position.col].isCompleted = false
            cells[position.row][position.col].isForced = false
            cells[position.row][position.col].countdownEndsAt = nil
            cells[position.row][position.col].completionStreakCount = 0
            cells[position.row][position.col].lastCompletedAt = nil
        }

        syncFullBoardCacheFromVisibleCells()
        checkBingo()
        settleRewardsIfNeeded()
        save()
        return true
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
                startDay: cell.startVisibleDay
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

    func applyTaskPool(_ tasks: [String], targetGridSize: Int) {
        let wrappedTasks = tasks.map { MyTaskItem(text: $0) }
        applyTaskPool(wrappedTasks, targetGridSize: targetGridSize)
    }

    func applyTaskPool(_ tasks: [MyTaskItem], targetGridSize: Int) {
        let sanitizedTasks = BingoTaskBoardHelpers.sanitizedTasks(tasks, maxLength: Self.maxTaskLength)
        TaskHistoryStore.upsertBoardTasks(sanitizedTasks)

        var newCache = Self.createEmptyGrid(size: Self.maxGridSize)
        let slots = taskPoolSlots(maxSize: Self.maxGridSize)

        for (slot, task) in zip(slots, sanitizedTasks) {
            guard slot.row < newCache.count, slot.col < newCache[slot.row].count else { continue }
            newCache[slot.row][slot.col] = BingoTaskBoardHelpers.cell(for: task)
        }

        fullBoardCells = newCache
        gridSize = min(max(targetGridSize, 2), Self.maxGridSize)
        cells = visibleCells(from: fullBoardCells, size: gridSize)
        completedLines = []
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
        boardCountdownEndsAt = nil
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil
        checkBingo(shouldCelebrateNewLines: false)
        settleRewardsIfNeeded(mode: .preserveAccumulatedPoints)
        save()
    }

    func applyBoardOrderedTasks(_ tasks: [MyTaskItem?], targetGridSize: Int) {
        let resolvedGridSize = min(max(targetGridSize, 2), Self.maxGridSize)
        let totalSlots = resolvedGridSize * resolvedGridSize
        let clippedTasks = Array(tasks.prefix(totalSlots))
        var newCache = Self.createEmptyGrid(size: Self.maxGridSize)
        var preservedCellsBySignature: [BingoTaskSignature: [BingoCell]] = [:]

        for row in 0..<resolvedGridSize {
            for col in 0..<resolvedGridSize {
                guard row < fullBoardCells.count, col < fullBoardCells[row].count else { continue }
                let existingCell = fullBoardCells[row][col]
                guard !existingCell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let signature = BingoTaskSignature(cell: existingCell)
                preservedCellsBySignature[signature, default: []].append(existingCell)
            }
        }

        for index in 0..<clippedTasks.count {
            guard let rawTask = clippedTasks[index],
                  let task = BingoTaskBoardHelpers.sanitizedTask(rawTask, maxLength: Self.maxTaskLength) else { continue }

            let row = index / resolvedGridSize
            let col = index % resolvedGridSize
            guard row < newCache.count, col < newCache[row].count else { continue }

            let signature = BingoTaskSignature(task: task)

            if var preservedList = preservedCellsBySignature[signature], !preservedList.isEmpty {
                var preservedCell = preservedList.removeFirst()
                preservedCellsBySignature[signature] = preservedList

                BingoTaskBoardHelpers.applyTask(task, to: &preservedCell)
                newCache[row][col] = preservedCell
            } else {
                newCache[row][col] = BingoTaskBoardHelpers.cell(for: task)
            }
        }

        let appliedTasks = BingoTaskBoardHelpers.sanitizedTasks(clippedTasks.compactMap { $0 }, maxLength: Self.maxTaskLength)
        TaskHistoryStore.upsertBoardTasks(appliedTasks)

        fullBoardCells = newCache
        gridSize = resolvedGridSize
        cells = visibleCells(from: fullBoardCells, size: gridSize)
        completedLines = []
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
        boardCountdownEndsAt = nil
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil
        checkBingo(shouldCelebrateNewLines: false)
        settleRewardsIfNeeded(mode: .preserveAccumulatedPoints)
        save()
    }

    func applyBoardOrderedCells(_ orderedCells: [BingoCell?], targetGridSize: Int) {
        let resolvedGridSize = min(max(targetGridSize, 2), Self.maxGridSize)
        let totalSlots = resolvedGridSize * resolvedGridSize
        let clippedCells = Array(orderedCells.prefix(totalSlots))
        var newCache = Self.createEmptyGrid(size: Self.maxGridSize)

        for index in 0..<clippedCells.count {
            guard var cell = clippedCells[index] else { continue }

            let storedText = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !storedText.isEmpty else { continue }

            let limitedStoredText = String(storedText.prefix(Self.maxTaskLength))
            let normalizedStartVisibilityAt = normalizedStartVisibility(
                date: cell.startVisibleAt ?? Self.dateFromLegacyMonthDay(
                    month: cell.startVisibleMonth,
                    day: cell.startVisibleDay
                )
            )
            let normalizedEndVisibilityAt = normalizedEndVisibility(
                date: cell.endVisibleAt,
                startVisibleAt: normalizedStartVisibilityAt
            )
            let recurrenceDefaultDate = normalizedStartVisibilityAt ?? Date()
            let normalizedRecurrenceRule = cell.recurrenceRule?.normalized(
                defaultWeekday: Calendar.current.component(.weekday, from: recurrenceDefaultDate),
                defaultMonthDay: Calendar.current.component(.day, from: recurrenceDefaultDate),
                defaultAnchorDate: recurrenceDefaultDate
            )

            if let residentText = cell.residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !residentText.isEmpty {
                cell.residentTaskText = String(residentText.prefix(Self.maxTaskLength))
            } else if normalizedRecurrenceRule != nil {
                cell.residentTaskText = limitedStoredText
            } else {
                cell.residentTaskText = nil
            }

            cell.residentWeekdays = Set(cell.residentWeekdays.filter { (1...7).contains($0) })
            cell.recurrenceRule = normalizedRecurrenceRule
            cell.text = limitedStoredText
            cell.startVisibleAt = normalizedStartVisibilityAt
            cell.endVisibleAt = normalizedEndVisibilityAt
            cell.startVisibleMonth = nil
            cell.startVisibleDay = nil
            // Force flag is only allowed via explicit task edit sheet toggle.
            cell.isForced = false

            let row = index / resolvedGridSize
            let col = index % resolvedGridSize
            guard row < newCache.count, col < newCache[row].count else { continue }
            newCache[row][col] = cell
        }

        let appliedTasks = clippedCells.compactMap { cell -> MyTaskItem? in
            guard let cell else { return nil }
            return BingoTaskBoardHelpers.taskItem(from: cell, maxLength: Self.maxTaskLength)
        }
        TaskHistoryStore.upsertBoardTasks(appliedTasks)

        fullBoardCells = newCache
        gridSize = resolvedGridSize
        cells = visibleCells(from: fullBoardCells, size: gridSize)
        completedLines = []
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
        boardCountdownEndsAt = nil
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil
        checkBingo(shouldCelebrateNewLines: false)
        settleRewardsIfNeeded(mode: .preserveAccumulatedPoints)
        save()
    }

    func resizeGrid(to newSize: Int) {
        guard newSize >= 2 && newSize <= Self.maxGridSize else { return }
        syncFullBoardCacheFromVisibleCells()
        gridSize = newSize
        cells = visibleCells(from: fullBoardCells, size: newSize)
        completedLines = []
        boardCountdownEndsAt = nil
        showBoardCompletionAnimation = false
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil
        checkBingo()
        settleRewardsIfNeeded(mode: .preserveAccumulatedPoints)
        save()
    }

    func resetBoard() {
        cells = Self.createEmptyGrid(size: gridSize)
        fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
        completedLines = []
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
        boardCountdownEndsAt = nil
        expiredTaskEvent = nil
        expiredBoardCountdownEvent = nil
        settleRewardsIfNeeded(mode: .preserveAccumulatedPoints)
        save()
    }

    func makeSavedBoardSnapshot() -> SavedBoard {
        persistenceSnapshot().board
    }

    func applySavedBoardSnapshot(
        _ savedBoard: SavedBoard,
        countdownEndsAt: Date?,
        referenceDate: Date = .now,
        reloadPersistedPoints: Bool = false
    ) {
        let normalizedGridSize = min(max(savedBoard.gridSize, 2), Self.maxGridSize)
        var expandedCache = BoardEngine.expandedBoardCache(from: savedBoard)
        Self.normalizeForceFlagsInBoardCache(&expandedCache, referenceDate: referenceDate)

        fullBoardCells = expandedCache
        gridSize = normalizedGridSize
        cells = BoardEngine.projectVisibleCells(
            from: expandedCache,
            size: normalizedGridSize,
            referenceDate: referenceDate
        )
        completedLines = savedBoard.completedLines
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
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
        save(persistDiary: false, savedAt: referenceDate)
    }

    func setBoardCountdown(totalMinutes: Int?) {
        guard let totalMinutes else {
            boardCountdownEndsAt = nil
            expiredBoardCountdownEvent = nil
            save()
            return
        }

        let clampedMinutes = min(max(totalMinutes, 1), Self.maxCountdownMinutes)
        boardCountdownEndsAt = Date().addingTimeInterval(Double(clampedMinutes * 60))
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
            shouldCelebrateNewLines: false
        )
    }

    func dismissBoardCompletionAnimation() {
        showBoardCompletionAnimation = false
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
            newlyCompletedLines = Array(newLines)
            showCelebration = true
            if AppSettings.isHapticsEnabled {
                AppHaptics.emphasis()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.showCelebration = false
                self?.newlyCompletedLines = []
            }
        } else if !shouldCelebrateNewLines {
            newlyCompletedLines = []
            showCelebration = false
        }
        completedLines = currentLines
    }

    private func refreshBoardState(
        shouldCelebrateNewLines: Bool,
        rewardSettlementMode: BingoRewardSettlementMode = .normal
    ) {
        // Keep this as the single board-state commit path: cache sync, bingo detection, rewards, and persistence must stay ordered.
        let wasBoardFullyCompleted = isBoardFullyCompleted
        syncFullBoardCacheFromVisibleCells()
        checkBingo(shouldCelebrateNewLines: shouldCelebrateNewLines)
        let isBoardNowFullyCompleted = isBoardFullyCompleted

        if shouldCelebrateNewLines && !wasBoardFullyCompleted && isBoardNowFullyCompleted {
            showBoardCompletionAnimation = true
        } else if !isBoardNowFullyCompleted || !shouldCelebrateNewLines {
            showBoardCompletionAnimation = false
        }

        trackBingoCompletionIfNeeded(
            wasBoardFullyCompleted: wasBoardFullyCompleted,
            isBoardNowFullyCompleted: isBoardNowFullyCompleted
        )
        settleRewardsIfNeeded(mode: rewardSettlementMode)
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
        savedAt: Date = .now
    ) -> BingoViewModelPersistenceCommitResult {
        BingoViewModelPersistence.saveWithExplicitDiaryDelta(
            persistenceSnapshot(),
            task: task,
            delta: delta,
            savedAt: savedAt,
            dependencies: persistenceDependencies
        )
    }

    func processExpiredCountdowns(now: Date = Date()) {
        guard let deadline = BoardEngine.expiredBoardCountdownDeadline(boardCountdownEndsAt, now: now) else { return }
        guard expiredBoardCountdownEvent == nil else { return }

        boardCountdownEndsAt = nil
        save()
        expiredBoardCountdownEvent = ExpiredBoardCountdownEvent(expiredAt: deadline)
    }

    func processExpiredTaskCountdowns(now: Date = Date()) {
        guard expiredTaskEvent == nil, expiredBoardCountdownEvent == nil else { return }

        // Emit one prompt at a time so timeout resolution cannot race with another expired task or board countdown.
        guard let candidate = BoardEngine.expiredTaskCandidate(in: cells, now: now) else { return }
        guard let updatedCells = BoardEngine.acknowledgeExpiredTaskCountdown(in: cells, candidate: candidate) else {
            return
        }

        if updatedCells != cells {
            cells = updatedCells
            syncFullBoardCacheFromVisibleCells()
            save()
        }
        expiredTaskEvent = ExpiredTaskEvent(
            cellID: candidate.cellID,
            row: candidate.row,
            col: candidate.col,
            taskText: candidate.taskText,
            expiredAt: candidate.expiredAt,
            expiredByCountdown: candidate.expiredByCountdown,
            expiredByVisibilityWindow: candidate.expiredByVisibilityWindow,
            allowsPostpone: candidate.allowsPostpone
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
            showBoardCompletionAnimation = false
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
            allowsPostpone: event.allowsPostpone
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
        guard let event = expiredTaskEvent else { return nil }
        defer {
            expiredTaskEvent = nil
        }

        guard let result = BoardEngine.resolveExpiredTask(
            in: cells,
            candidate: boardEngineExpiredTaskCandidate(from: event),
            resolution: boardEngineExpiredTaskResolution(for: resolution),
            now: now,
            maxCountdownMinutes: Self.maxCountdownMinutes
        ) else {
            return nil
        }

        if let unfinishedTaskText = result.unfinishedTimeoutTaskText {
            BingoTimeoutStore.recordUnfinishedTimeout(task: unfinishedTaskText, on: now)
        }
        cells = result.cells
        switch resolution {
        case .markAsCompleted:
            refreshBoardState(shouldCelebrateNewLines: true)
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
            cell.text = presetText
            cell.isCompleted = false
            cell.isTaskHidden = false
            cell.countdownEndsAt = nil
            cell.isForced = false
            cell.startVisibleMonth = nil
            cell.startVisibleDay = nil
            cell.residentTaskText = nil
            cell.recurrenceRule = nil
            cell.completionStreakCount = 0
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
            refreshBoardState(shouldCelebrateNewLines: true)
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
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
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
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
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

    private func clearForceFlagsExcept(row: Int, col: Int) {
        for r in cells.indices {
            for c in cells[r].indices where !(r == row && c == col) {
                cells[r][c].isForced = false
            }
        }
        for r in fullBoardCells.indices {
            for c in fullBoardCells[r].indices where !(r == row && c == col) {
                fullBoardCells[r][c].isForced = false
            }
        }
    }

    private func registerCompletionIfNeeded(row: Int, col: Int, now: Date) {
        guard row < cells.count, col < cells[row].count else { return }
        guard !cells[row][col].isEmpty else { return }

        let calendar = Calendar.current
        if let lastCompletedAt = cells[row][col].lastCompletedAt,
           calendar.isDate(lastCompletedAt, inSameDayAs: now) {
            return
        }

        cells[row][col].completionStreakCount += 1
        cells[row][col].lastCompletedAt = now
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
            estimatedDurationMinutes: cell.estimatedDurationMinutes,
            completionStreakCount: cell.completionStreakCount,
            lastCompletedAt: cell.lastCompletedAt
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

    private func normalizedDisplayText(for cell: BingoCell, referenceDate: Date) -> String {
        cell.projectedForDisplay(on: referenceDate).text
    }

    private func canAcceptNewTask(_ cell: BingoCell) -> Bool {
        !cell.hasStoredTask
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

    private func reloadPersistedPointsState(referenceDate: Date) {
        if let persistedTotalPoints = persistenceDependencies.pointsRepository.loadTotalPoints() {
            totalPoints = persistedTotalPoints
        }

        if let persistedLifetimePoints = persistenceDependencies.pointsRepository.loadLifetimePoints() {
            lifetimePoints = persistedLifetimePoints
        } else if let persistedTotalPoints = persistenceDependencies.pointsRepository.loadTotalPoints() {
            lifetimePoints = persistedTotalPoints
        }

        dailyRewardState = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: referenceDate,
            boardLastSavedAt: referenceDate,
            currentCells: cells,
            currentCompletedLines: completedLines,
            isBoardFullyCompleted: isBoardFullyCompleted,
            savedDailyRewardState: persistenceDependencies.pointsRepository.loadDailyRewardState()
        )
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
