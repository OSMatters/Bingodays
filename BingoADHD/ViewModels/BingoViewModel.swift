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

        init(id: UUID = UUID(), cellID: UUID, row: Int, col: Int, taskText: String, expiredAt: Date) {
            self.id = id
            self.cellID = cellID
            self.row = row
            self.col = col
            self.taskText = taskText
            self.expiredAt = expiredAt
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
    private var ignoredScheduledReplacementCellIDs = Set<UUID>()

    init() {
        self.totalPoints = 0
        self.lifetimePoints = 0
        self.dailyRewardState = DailyRewardState(dateKey: PointsStore.dateKey(for: .now))
        self.boardCountdownEndsAt = BingoBoardStore.loadBoardCountdownEndsAt()
        let now = Date()
        var existingSavedAt: Date?
        if let saved = BingoBoardStore.loadBoard() {
            existingSavedAt = BingoBoardStore.loadBoardLastSavedAt()
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
                BingoBoardStore.saveBoard(
                    normalizedBoard,
                    savedAt: savedAt,
                    associatedBoardID: BingoBoardStore.loadActiveNamedBoardID()
                )
            }
        } else {
            self.gridSize = Self.defaultInitialGridSize
            self.cells = Self.createEmptyGrid(size: Self.defaultInitialGridSize)
            self.fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
            self.syncFullBoardCacheFromVisibleCells()
            BingoBoardStore.saveBoard(
                SavedBoard(
                    gridSize: Self.defaultInitialGridSize,
                    cells: self.cells,
                    completedLines: [],
                    fullBoardCells: self.fullBoardCells
                )
            )
        }
        self.totalPoints = PointsStore.loadTotalPoints() ?? calculateBoardScore()
        self.lifetimePoints = PointsStore.loadLifetimePoints() ?? self.totalPoints
        self.dailyRewardState = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: now,
            boardLastSavedAt: existingSavedAt,
            currentCells: self.cells,
            currentCompletedLines: self.completedLines,
            isBoardFullyCompleted: self.isBoardFullyCompleted
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

    func toggleComplete(row: Int, col: Int) {
        guard row < cells.count, col < cells[row].count else { return }
        guard !cells[row][col].isEmpty else { return }
        guard !isLocked(row: row, col: col) else { return }
        guard isTaskCurrentlyTappable(row: row, col: col) else { return }
        let wasBoardFullyCompleted = isBoardFullyCompleted
        let isNowCompleted = !cells[row][col].isCompleted
        let diaryTaskText = cells[row][col].storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        cells[row][col].isCompleted = isNowCompleted
        if isNowCompleted {
            if let deadline = cells[row][col].countdownEndsAt {
                let remaining = max(Int(deadline.timeIntervalSince(.now)), 0)
                cells[row][col].countdownPausedRemainingSeconds = remaining > 0 ? remaining : nil
            } else {
                cells[row][col].countdownPausedRemainingSeconds = nil
            }
            registerCompletionIfNeeded(row: row, col: col, now: .now)
            // Force completion should only block until this task is completed once.
            cells[row][col].isForced = false
            cells[row][col].countdownEndsAt = nil
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
            if let paused = cells[row][col].countdownPausedRemainingSeconds, paused > 0 {
                cells[row][col].countdownEndsAt = Date().addingTimeInterval(TimeInterval(paused))
            }
            cells[row][col].countdownPausedRemainingSeconds = nil
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
        settleRewardsIfNeeded()
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
        let normalizedWeekdays: Set<Int> = trimmedText.isEmpty ? [] : residentWeekdays
        let normalizedOneTimeTask = !trimmedText.isEmpty && isOneTimeTask
        let normalizedStartVisibilityAt = trimmedText.isEmpty ? nil : normalizedStartVisibility(date: startVisibleAt)
        let normalizedEndVisibilityAt = trimmedText.isEmpty ? nil : normalizedEndVisibility(date: endVisibleAt, startVisibleAt: normalizedStartVisibilityAt)
        let normalizedReminderEnabled = !trimmedText.isEmpty && !previousCell.isCompleted && normalizedStartVisibilityAt != nil && normalizedEndVisibilityAt != nil && startReminderEnabled
        let normalizedReminderOffset = BingoCell.normalizedStartReminderOffsetMinutes(startReminderOffsetMinutes)
        let usesStoredSchedule = !normalizedWeekdays.isEmpty || normalizedOneTimeTask || normalizedStartVisibilityAt != nil || normalizedEndVisibilityAt != nil
        let previousStoredTaskText = previousCell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isReplacingTaskIdentity = previousStoredTaskText != trimmedText

        cells[row][col].residentWeekdays = normalizedWeekdays
        cells[row][col].oneTimeVisibleDate = normalizedOneTimeTask ? .now : nil
        cells[row][col].startVisibleAt = normalizedStartVisibilityAt
        cells[row][col].endVisibleAt = normalizedEndVisibilityAt
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
        cells[row][col].estimatedDurationMinutes = estimatedDurationMinutes.map { min(max($0, 1), Self.maxCountdownMinutes) }

        if cells[row][col].isForced {
            // Keep force mode deterministic: only one active forced task per board.
            clearForceFlagsExcept(row: row, col: col)
        }
        if isReplacingTaskIdentity {
            cells[row][col].completionStreakCount = 0
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
            cells[row][col].startVisibleAt = nil
            cells[row][col].endVisibleAt = nil
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
        } else if let estimatedDurationMinutes,
                  !cells[row][col].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let totalMinutes = min(max(estimatedDurationMinutes, 1), Self.maxCountdownMinutes)
            if let startVisibleAt = normalizedStartVisibilityAt, startVisibleAt > .now {
                cells[row][col].countdownEndsAt = nil
            } else {
                cells[row][col].countdownEndsAt = Date().addingTimeInterval(Double(totalMinutes * 60))
            }
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
        return editingCell.estimatedDurationMinutes
    }

    func isTaskCurrentlyTappable(row: Int, col: Int, referenceDate: Date = Date()) -> Bool {
        guard row >= 0, col >= 0 else { return false }
        guard let sourceCell = editingCell(row: row, col: col) else { return false }
        return !sourceCell.isVisibilityWindowInactive(on: referenceDate)
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

            if let residentText = cell.residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !residentText.isEmpty {
                cell.residentTaskText = String(residentText.prefix(Self.maxTaskLength))
            } else {
                cell.residentTaskText = nil
            }

            cell.residentWeekdays = Set(cell.residentWeekdays.filter { (1...7).contains($0) })
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
        referenceDate: Date = .now
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
        dailyRewardState = BingoRewardSettlement.dailyRewardSnapshot(
            for: referenceDate,
            cells: cells,
            completedLines: completedLines,
            isBoardFullyCompleted: isBoardFullyCompleted
        )
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
                if cell.isForced && !cell.isCompleted && !cell.isEmpty && !cell.isVisibilityWindowInactive(on: Date()) {
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
        var currentLines: Set<BingoLine> = []
        let size = gridSize

        // Check rows
        for row in 0..<size where row < cells.count {
            let rowCells = Array(cells[row].prefix(size))
            if rowCells.count == size && rowCells.allSatisfy({ $0.isCompleted && !$0.isEmpty }) {
                currentLines.insert(.row(row))
            }
        }

        // Check columns
        for col in 0..<size {
            var allCompleted = true
            for row in 0..<size {
                guard row < cells.count, col < cells[row].count,
                      cells[row][col].isCompleted, !cells[row][col].isEmpty else {
                    allCompleted = false
                    break
                }
            }
            if allCompleted { currentLines.insert(.column(col)) }
        }

        // Check main diagonal (top-left to bottom-right)
        var diagMain = true
        for i in 0..<size {
            guard i < cells.count, i < cells[i].count,
                  cells[i][i].isCompleted, !cells[i][i].isEmpty else {
                diagMain = false; break
            }
        }
        if diagMain { currentLines.insert(.diagonalMain) }

        // Check anti-diagonal (top-right to bottom-left)
        var diagAnti = true
        for i in 0..<size {
            let col = size - 1 - i
            guard i < cells.count, col < cells[i].count,
                  cells[i][col].isCompleted, !cells[i][col].isEmpty else {
                diagAnti = false; break
            }
        }
        if diagAnti { currentLines.insert(.diagonalAnti) }

        // Detect newly completed lines
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

    private func save(persistDiary: Bool = true, savedAt: Date = .now) {
        BingoViewModelPersistence.save(
            persistenceSnapshot(),
            persistDiary: persistDiary,
            savedAt: savedAt
        )
    }

    private func saveWithExplicitDiaryDelta(
        task: String,
        delta: Int,
        savedAt: Date = .now
    ) {
        BingoViewModelPersistence.saveWithExplicitDiaryDelta(
            persistenceSnapshot(),
            task: task,
            delta: delta,
            savedAt: savedAt
        )
    }

    func processExpiredCountdowns(now: Date = Date()) {
        guard let deadline = boardCountdownEndsAt, deadline <= now else { return }
        guard expiredBoardCountdownEvent == nil else { return }

        boardCountdownEndsAt = nil
        save()
        expiredBoardCountdownEvent = ExpiredBoardCountdownEvent(expiredAt: deadline)
    }

    func processExpiredTaskCountdowns(now: Date = Date()) {
        guard expiredTaskEvent == nil, expiredBoardCountdownEvent == nil else { return }

        // Emit one prompt at a time so timeout resolution cannot race with another expired task or board countdown.
        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                guard !cell.isEmpty, !cell.isCompleted else {
                    continue
                }

                let executionDeadline = cell.countdownEndsAt
                let visibilityWindowDeadline: Date? = {
                    guard executionDeadline == nil else { return nil }
                    guard let start = cell.startVisibleAt, let end = cell.endVisibleAt else { return nil }
                    guard now >= start, now >= end else { return nil }
                    return end
                }()

                guard let deadline = executionDeadline ?? visibilityWindowDeadline,
                      deadline <= now else {
                    continue
                }

                cells[row][col].countdownEndsAt = nil
                syncFullBoardCacheFromVisibleCells()
                save()
                expiredTaskEvent = ExpiredTaskEvent(
                    cellID: cell.id,
                    row: row,
                    col: col,
                    taskText: cell.storedTaskText,
                    expiredAt: deadline
                )
                return
            }
        }
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
                guard let estimatedDurationMinutes = cell.estimatedDurationMinutes,
                      estimatedDurationMinutes > 0,
                      !cell.isCompleted,
                      cell.countdownEndsAt == nil,
                      cell.isVisibilityWindowActive(on: now) else {
                    continue
                }

                cell.countdownEndsAt = now.addingTimeInterval(Double(estimatedDurationMinutes * 60))
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
        for row in 0..<min(gridSize, fullBoardCells.count) {
            for col in 0..<min(gridSize, fullBoardCells[row].count) {
                let cell = fullBoardCells[row][col]
                guard cell.hasStartVisibilityDate else { continue }
                guard cell.isStartVisibilityReached(on: now) else { continue }
                guard !cell.hasResidentSchedule, !cell.isOneTimeTask else { continue }
                guard !ignoredScheduledReplacementCellIDs.contains(cell.id) else { continue }

                let currentText = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let presetText = (cell.residentTaskText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !currentText.isEmpty, !presetText.isEmpty else { continue }
                guard currentText != presetText else { continue }

                scheduledTaskReplacementEvent = ScheduledTaskReplacementEvent(
                    cellID: cell.id,
                    row: row,
                    col: col,
                    currentTaskText: currentText,
                    presetTaskText: presetText
                )
                return
            }
        }
    }

    func resolveExpiredTask(_ resolution: ExpiredTaskResolution, now: Date = Date()) -> String? {
        guard let event = expiredTaskEvent else { return nil }
        defer {
            expiredTaskEvent = nil
        }

        let position = resolveExpiredTaskPosition(for: event)
        guard let position else { return nil }
        let row = position.row
        let col = position.col
        guard row < cells.count, col < cells[row].count else { return nil }
        guard !cells[row][col].isEmpty else { return nil }

        switch resolution {
        case .markAsCompleted:
            let visibilityWindowExpired =
                cells[row][col].countdownEndsAt == nil &&
                cells[row][col].startVisibleAt != nil &&
                cells[row][col].endVisibleAt != nil &&
                cells[row][col].isEndVisibilityReached(on: now)

            cells[row][col].isCompleted = true
            registerCompletionIfNeeded(row: row, col: col, now: now)
            cells[row][col].countdownEndsAt = nil
            if visibilityWindowExpired {
                // User explicitly marks done at window timeout: keep completed visual state.
                cells[row][col].startVisibleAt = nil
                cells[row][col].endVisibleAt = nil
                cells[row][col].lastVisibilityWindowTimeoutAt = nil
            }
            refreshBoardState(shouldCelebrateNewLines: true)
            return L10n.taskMarkedCompletedSuccess

        case .abandon:
            BingoTimeoutStore.recordUnfinishedTimeout(task: cells[row][col].storedTaskText, on: now)
            cells[row][col] = BingoCell()
            refreshBoardState(shouldCelebrateNewLines: false)
            return L10n.taskAbandonedSuccess

        case .postpone(let minutes):
            let clampedMinutes = min(max(minutes, 1), Self.maxCountdownMinutes)
            BingoTimeoutStore.recordUnfinishedTimeout(task: event.taskText, on: now)
            // Postpone should continue as a regular countdown task, not return to inactive window state.
            cells[row][col].startVisibleAt = nil
            cells[row][col].endVisibleAt = nil
            cells[row][col].lastVisibilityWindowTimeoutAt = nil
            cells[row][col].countdownEndsAt = now.addingTimeInterval(Double(clampedMinutes * 60))
            refreshBoardState(shouldCelebrateNewLines: false)
            return L10n.taskPostponedSuccess(clampedMinutes)
        }
    }

    private func resolveExpiredTaskPosition(for event: ExpiredTaskEvent) -> Position? {
        if event.row >= 0,
           event.col >= 0,
           event.row < cells.count,
           event.col < cells[event.row].count,
           !cells[event.row][event.col].isEmpty {
            return Position(row: event.row, col: event.col)
        }

        if let idMatched = findVisiblePosition(forCellID: event.cellID),
           !cells[idMatched.row][idMatched.col].isEmpty {
            return idMatched
        }

        let normalizedTask = event.taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else { return nil }

        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                guard !cell.isEmpty, !cell.isCompleted else { continue }
                if cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedTask {
                    return Position(row: row, col: col)
                }
            }
        }
        return nil
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

        switch resolution {
        case .markAsCompleted:
            for row in cells.indices {
                for col in cells[row].indices {
                    guard !cells[row][col].isEmpty else { continue }
                    cells[row][col].isCompleted = true
                    registerCompletionIfNeeded(row: row, col: col, now: now)
                    cells[row][col].countdownEndsAt = nil
                }
            }
            boardCountdownEndsAt = nil
            expiredTaskEvent = nil
            refreshBoardState(shouldCelebrateNewLines: true)
            return L10n.boardMarkedCompletedSuccess

        case .abandon:
            boardCountdownEndsAt = nil
            save()
            return L10n.boardCountdownCanceledSuccess

        case .postpone(let minutes):
            let clampedMinutes = min(max(minutes, 1), Self.maxCountdownMinutes)
            boardCountdownEndsAt = now.addingTimeInterval(Double(clampedMinutes * 60))
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

    private func syncDiarySnapshot() {
        BingoViewModelPersistence.syncDiarySnapshot(persistenceSnapshot())
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
        let completedTaskCount = cells
            .flatMap { $0 }
            .filter { $0.isCompleted && !$0.isEmpty }
            .count

        let allCells = cells.flatMap { $0 }
        let allTilesFilledAndCompleted = !allCells.isEmpty && allCells.allSatisfy { !$0.isEmpty && $0.isCompleted }
        let allTasksCompletedBonus = allTilesFilledAndCompleted ? 10 : 0

        return completedTaskCount + (completedLines.count * 5) + allTasksCompletedBonus
    }

    private var isBoardFullyCompleted: Bool {
        let allCells = cells.flatMap { $0 }
        return !allCells.isEmpty && allCells.allSatisfy { !$0.isEmpty && $0.isCompleted }
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

    private func findVisiblePosition(forCellID cellID: UUID) -> Position? {
        for row in cells.indices {
            for col in cells[row].indices where cells[row][col].id == cellID {
                return Position(row: row, col: col)
            }
        }
        return nil
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
            startVisibleAt: cell.startVisibleAt,
            endVisibleAt: cell.endVisibleAt,
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
                dailyRewardState: dailyRewardState,
                nonRevocableConsumedPoints: BingoRewardSettlement.nonRevocableConsumedPointsTotal()
            ),
            mode: mode
        )
        totalPoints = output.totalPoints
        lifetimePoints = output.lifetimePoints
        dailyRewardState = output.dailyRewardState
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
