import SwiftUI
import Combine

class BingoViewModel: ObservableObject {
    static let maxGridSize = 5
    static let defaultInitialGridSize = 3
    static let maxTaskLength = 20
    static let maxCountdownMinutes = 24 * 60

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

    private enum RewardSettlementMode {
        // Follow current board completion state (can add or revoke points).
        case normal
        // Keep accumulated points, but rebase daily state to current board.
        case preserveAccumulatedPoints
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
            var expandedCache = Self.expandedBoardCache(from: saved)
            Self.normalizeForceFlagsInBoardCache(&expandedCache, referenceDate: now)
            self.fullBoardCells = expandedCache
            self.gridSize = saved.gridSize
            self.cells = Self.projectVisibleCells(
                from: self.fullBoardCells,
                size: saved.gridSize,
                referenceDate: now
            )
            self.completedLines = saved.completedLines
            BingoBoardStore.saveBoard(
                SavedBoard(gridSize: saved.gridSize, cells: self.cells, completedLines: self.completedLines, fullBoardCells: self.fullBoardCells),
                savedAt: savedAt
            )
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
        self.dailyRewardState = Self.initialDailyRewardState(
            referenceDate: now,
            boardLastSavedAt: existingSavedAt,
            currentCells: self.cells,
            currentCompletedLines: self.completedLines,
            isBoardFullyCompleted: self.isBoardFullyCompleted
        )
        repairDuplicateCellIDsIfNeeded(referenceDate: now)
    }

    static func createEmptyGrid(size: Int) -> [[BingoCell]] {
        (0..<size).map { _ in
            (0..<size).map { _ in BingoCell() }
        }
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
        let wasBoardFullyCompleted = isBoardFullyCompleted
        let isNowCompleted = !cells[row][col].isCompleted
        let diaryTaskText = cells[row][col].storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        cells[row][col].isCompleted = isNowCompleted
        if isNowCompleted {
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
        startVisibleMonth: Int? = nil,
        startVisibleDay: Int? = nil
    ) {
        guard row < cells.count, col < cells[row].count else { return }
        let previousCell = cells[row][col]
        let limitedText = String(text.prefix(Self.maxTaskLength))
        let trimmedText = limitedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWeekdays: Set<Int> = trimmedText.isEmpty ? [] : residentWeekdays
        let normalizedOneTimeTask = !trimmedText.isEmpty && isOneTimeTask
        let normalizedStartVisibility: (month: Int?, day: Int?) = trimmedText.isEmpty
            ? (month: nil, day: nil)
            : normalizedStartVisibility(month: startVisibleMonth, day: startVisibleDay)
        let usesStoredSchedule = !normalizedWeekdays.isEmpty || normalizedOneTimeTask || normalizedStartVisibility.month != nil
        let previousStoredTaskText = previousCell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isReplacingTaskIdentity = previousStoredTaskText != trimmedText

        cells[row][col].residentWeekdays = normalizedWeekdays
        cells[row][col].oneTimeVisibleDate = normalizedOneTimeTask ? .now : nil
        cells[row][col].startVisibleMonth = normalizedStartVisibility.month
        cells[row][col].startVisibleDay = normalizedStartVisibility.day
        cells[row][col].residentTaskText = usesStoredSchedule ? limitedText : nil
        cells[row][col].text = usesStoredSchedule ? normalizedDisplayText(for: cells[row][col], referenceDate: .now) : limitedText
        cells[row][col].isTaskHidden = false
        cells[row][col].isForced = !trimmedText.isEmpty && isForced
        cells[row][col].countdownEndsAt = nil

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
            cells[row][col].residentTaskText = nil
            cells[row][col].residentWeekdays = []
            cells[row][col].oneTimeVisibleDate = nil
            cells[row][col].startVisibleMonth = nil
            cells[row][col].startVisibleDay = nil
            cells[row][col].completionStreakCount = 0
            cells[row][col].lastCompletedAt = nil
            if expiredTaskEvent?.cellID == cells[row][col].id {
                expiredTaskEvent = nil
            }
            if scheduledTaskReplacementEvent?.cellID == cells[row][col].id {
                scheduledTaskReplacementEvent = nil
            }
        } else if let estimatedDurationMinutes,
                  !cells[row][col].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let totalMinutes = min(max(estimatedDurationMinutes, 1), Self.maxCountdownMinutes)
            cells[row][col].countdownEndsAt = Date().addingTimeInterval(Double(totalMinutes * 60))
        }
        syncFullBoardCacheFromVisibleCells()
        ignoredScheduledReplacementCellIDs.remove(cells[row][col].id)
        cells = visibleCells(from: fullBoardCells, size: gridSize)
        checkBingo()
        if !isBoardFullyCompleted {
            showBoardCompletionAnimation = false
        }
        let rewardMode: RewardSettlementMode = trimmedText.isEmpty ? .preserveAccumulatedPoints : .normal
        settleRewardsIfNeeded(mode: rewardMode)

        if !trimmedText.isEmpty {
            TaskHistoryStore.upsert(
                task: MyTaskItem(
                    text: trimmedText,
                    startMonth: normalizedStartVisibility.month,
                    startDay: normalizedStartVisibility.day
                )
            )
        } else if !previousStoredTaskText.isEmpty {
            TaskHistoryStore.upsert(
                task: MyTaskItem(
                    text: previousStoredTaskText,
                    startMonth: previousCell.startVisibleMonth,
                    startDay: previousCell.startVisibleDay
                )
            )
        }
        save()
    }

    private func normalizedStartVisibility(month: Int?, day: Int?) -> (month: Int?, day: Int?) {
        guard let month, let day else { return (nil, nil) }
        guard (1...12).contains(month), (1...31).contains(day) else { return (nil, nil) }

        var components = DateComponents()
        components.year = 2000
        components.month = month
        components.day = day
        guard Calendar.current.date(from: components) != nil else { return (nil, nil) }

        return (month, day)
    }

    func clearTask(row: Int, col: Int) {
        updateTask(row: row, col: col, text: "", isForced: false, residentWeekdays: [], isOneTimeTask: false)
    }

    func remainingTaskCountdownMinutes(row: Int, col: Int, referenceDate: Date = Date()) -> Int? {
        guard let editingCell = editingCell(row: row, col: col),
              let deadline = editingCell.countdownEndsAt else { return nil }
        let remainingSeconds = max(deadline.timeIntervalSince(referenceDate), 0)
        let remainingMinutes = Int(ceil(remainingSeconds / 60))
        return max(remainingMinutes, 1)
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
        let deletedText = deletedCell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !deletedText.isEmpty {
            TaskHistoryStore.upsert(
                task: MyTaskItem(
                    text: deletedText,
                    startMonth: deletedCell.startVisibleMonth,
                    startDay: deletedCell.startVisibleDay
                )
            )
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
        let sanitizedTasks = tasks
            .compactMap { task -> MyTaskItem? in
                var sanitized = task
                sanitized.text = String(task.text.prefix(Self.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
                sanitized.normalizeStartDate()
                return sanitized.trimmedText.isEmpty ? nil : sanitized
            }
        TaskHistoryStore.upsertBoardTasks(sanitizedTasks)

        var newCache = Self.createEmptyGrid(size: Self.maxGridSize)
        let slots = taskPoolSlots(maxSize: Self.maxGridSize)

        for (slot, task) in zip(slots, sanitizedTasks) {
            guard slot.row < newCache.count, slot.col < newCache[slot.row].count else { continue }
            newCache[slot.row][slot.col] = BingoCell(
                text: task.trimmedText,
                residentTaskText: task.hasStartDate ? task.trimmedText : nil,
                startVisibleMonth: task.startMonth,
                startVisibleDay: task.startDay
            )
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
        struct TaskSignature: Hashable {
            let text: String
            let startMonth: Int?
            let startDay: Int?
        }

        let resolvedGridSize = min(max(targetGridSize, 2), Self.maxGridSize)
        let totalSlots = resolvedGridSize * resolvedGridSize
        let clippedTasks = Array(tasks.prefix(totalSlots))
        var newCache = Self.createEmptyGrid(size: Self.maxGridSize)
        var preservedCellsBySignature: [TaskSignature: [BingoCell]] = [:]

        for row in 0..<resolvedGridSize {
            for col in 0..<resolvedGridSize {
                guard row < fullBoardCells.count, col < fullBoardCells[row].count else { continue }
                let existingCell = fullBoardCells[row][col]
                let existingText = existingCell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !existingText.isEmpty else { continue }

                let signature = TaskSignature(
                    text: existingText,
                    startMonth: existingCell.startVisibleMonth,
                    startDay: existingCell.startVisibleDay
                )
                preservedCellsBySignature[signature, default: []].append(existingCell)
            }
        }

        for index in 0..<clippedTasks.count {
            guard var task = clippedTasks[index] else { continue }
            task.text = String(task.text.prefix(Self.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            task.normalizeStartDate()
            guard !task.trimmedText.isEmpty else { continue }

            let row = index / resolvedGridSize
            let col = index % resolvedGridSize
            guard row < newCache.count, col < newCache[row].count else { continue }

            let signature = TaskSignature(
                text: task.trimmedText,
                startMonth: task.startMonth,
                startDay: task.startDay
            )

            if var preservedList = preservedCellsBySignature[signature], !preservedList.isEmpty {
                var preservedCell = preservedList.removeFirst()
                preservedCellsBySignature[signature] = preservedList

                preservedCell.text = task.trimmedText
                preservedCell.residentTaskText = task.hasStartDate ? task.trimmedText : nil
                preservedCell.startVisibleMonth = task.startMonth
                preservedCell.startVisibleDay = task.startDay
                // Force flag is only allowed via explicit task edit sheet toggle.
                preservedCell.isForced = false
                newCache[row][col] = preservedCell
            } else {
                newCache[row][col] = BingoCell(
                    text: task.trimmedText,
                    residentTaskText: task.hasStartDate ? task.trimmedText : nil,
                    startVisibleMonth: task.startMonth,
                    startVisibleDay: task.startDay
                )
            }
        }

        let appliedTasks = clippedTasks.compactMap { task -> MyTaskItem? in
            guard var task else { return nil }
            task.text = String(task.text.prefix(Self.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            task.normalizeStartDate()
            return task.trimmedText.isEmpty ? nil : task
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
            let normalizedStartVisibility = normalizedStartVisibility(
                month: cell.startVisibleMonth,
                day: cell.startVisibleDay
            )

            if let residentText = cell.residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !residentText.isEmpty {
                cell.residentTaskText = String(residentText.prefix(Self.maxTaskLength))
            } else {
                cell.residentTaskText = nil
            }

            cell.residentWeekdays = Set(cell.residentWeekdays.filter { (1...7).contains($0) })
            cell.text = limitedStoredText
            cell.startVisibleMonth = normalizedStartVisibility.month
            cell.startVisibleDay = normalizedStartVisibility.day
            // Force flag is only allowed via explicit task edit sheet toggle.
            cell.isForced = false

            let row = index / resolvedGridSize
            let col = index % resolvedGridSize
            guard row < newCache.count, col < newCache[row].count else { continue }
            newCache[row][col] = cell
        }

        let appliedTasks: [MyTaskItem] = clippedCells.compactMap { cell -> MyTaskItem? in
            guard let cell else { return nil }
            let text = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MyTaskItem(
                text: text,
                startMonth: cell.startVisibleMonth,
                startDay: cell.startVisibleDay
            )
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
        SavedBoard(
            gridSize: gridSize,
            cells: cells,
            completedLines: completedLines,
            fullBoardCells: fullBoardCells
        )
    }

    func applySavedBoardSnapshot(
        _ savedBoard: SavedBoard,
        countdownEndsAt: Date?,
        referenceDate: Date = .now
    ) {
        let normalizedGridSize = min(max(savedBoard.gridSize, 2), Self.maxGridSize)
        var expandedCache = Self.expandedBoardCache(from: savedBoard)
        Self.normalizeForceFlagsInBoardCache(&expandedCache, referenceDate: referenceDate)

        fullBoardCells = expandedCache
        gridSize = normalizedGridSize
        cells = Self.projectVisibleCells(
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
        dailyRewardState = Self.dailyRewardSnapshot(
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
                if cell.isForced && !cell.isCompleted && !cell.isEmpty {
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
        rewardSettlementMode: RewardSettlementMode = .normal
    ) {
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
        let board = SavedBoard(gridSize: gridSize, cells: cells, completedLines: completedLines, fullBoardCells: fullBoardCells)
        BingoBoardStore.saveBoard(board, savedAt: savedAt)
        BingoBoardStore.saveBoardCountdownEndsAt(boardCountdownEndsAt)
        if persistDiary {
            BingoDiaryStore.save(board: board, on: savedAt)
        } else {
            BingoDiaryStore.syncBoardSnapshotWithoutCounting(board: board, on: savedAt)
        }
        PointsStore.saveTotalPoints(totalPoints)
        PointsStore.saveLifetimePoints(lifetimePoints)
        PointsStore.saveDailyRewardState(dailyRewardState)
    }

    private func saveWithExplicitDiaryDelta(
        task: String,
        delta: Int,
        savedAt: Date = .now
    ) {
        let board = SavedBoard(gridSize: gridSize, cells: cells, completedLines: completedLines, fullBoardCells: fullBoardCells)
        BingoBoardStore.saveBoard(board, savedAt: savedAt)
        BingoBoardStore.saveBoardCountdownEndsAt(boardCountdownEndsAt)
        BingoDiaryStore.applyExplicitTaskDelta(task: task, delta: delta, board: board, on: savedAt)
        PointsStore.saveTotalPoints(totalPoints)
        PointsStore.saveLifetimePoints(lifetimePoints)
        PointsStore.saveDailyRewardState(dailyRewardState)
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

        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                guard !cell.isEmpty, !cell.isCompleted, let deadline = cell.countdownEndsAt, deadline <= now else {
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

    func processScheduledTaskReplacementConflicts(now: Date = Date()) {
        guard scheduledTaskReplacementEvent == nil else { return }
        guard expiredTaskEvent == nil, expiredBoardCountdownEvent == nil else { return }

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
            cells[row][col].isCompleted = true
            registerCompletionIfNeeded(row: row, col: col, now: now)
            cells[row][col].countdownEndsAt = nil
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
            cells[row][col].countdownEndsAt = now.addingTimeInterval(Double(clampedMinutes * 60))
            syncFullBoardCacheFromVisibleCells()
            save()
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
        dailyRewardState = Self.emptyDailyRewardState(for: now)
    }

    private func notifyDailyResetApplied(clearedCount: Int) {
        guard clearedCount > 0 else { return }
        dailyResetNoticeID += 1
    }

    private func syncDiarySnapshot() {
        let board = SavedBoard(gridSize: gridSize, cells: cells, completedLines: completedLines, fullBoardCells: fullBoardCells)
        BingoDiaryStore.save(board: board)
        PointsStore.saveTotalPoints(totalPoints)
        PointsStore.saveLifetimePoints(lifetimePoints)
        PointsStore.saveDailyRewardState(dailyRewardState)
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
        Self.projectVisibleCells(from: cache, size: size, referenceDate: .now)
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
        cells = Self.projectVisibleCells(from: fullBoardCells, size: gridSize, referenceDate: referenceDate)
        save(persistDiary: false, savedAt: referenceDate)
    }

    private func remintedCell(_ cell: BingoCell) -> BingoCell {
        BingoCell(
            id: UUID(),
            text: cell.text,
            residentTaskText: cell.residentTaskText,
            residentWeekdays: cell.residentWeekdays,
            oneTimeVisibleDate: cell.oneTimeVisibleDate,
            startVisibleMonth: cell.startVisibleMonth,
            startVisibleDay: cell.startVisibleDay,
            isTaskHidden: cell.isTaskHidden,
            isCompleted: cell.isCompleted,
            isForced: cell.isForced,
            countdownEndsAt: cell.countdownEndsAt,
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
        mode: RewardSettlementMode = .normal
    ) {
        resetDailyRewardStateIfNeeded(for: date)

        let completedCellIDs = Set(
            cells
                .flatMap { $0 }
                .filter { $0.isCompleted && !$0.isEmpty }
                .map(\.id)
        )
        let newLineCount = completedLines.count
        let newFullBoardRewardGranted = isBoardFullyCompleted

        let previousPoints = dailyRewardState.rewardedCellIDs.count
            + (dailyRewardState.peakCompletedLineCount * 5)
            + (dailyRewardState.fullBoardRewardGranted ? 10 : 0)
        let currentBoardPoints = completedCellIDs.count
            + (newLineCount * 5)
            + (newFullBoardRewardGranted ? 10 : 0)

        if mode == .normal {
            // Normal interaction: checking grants points, unchecking revokes points.
            let delta = currentBoardPoints - previousPoints
            if delta != 0 {
                totalPoints = max(totalPoints + delta, 0)
                if delta > 0 {
                    lifetimePoints += delta
                }
            }
        }

        // Rebase daily reward state to current board after each settlement.
        // In preserveAccumulatedPoints mode we keep totalPoints unchanged, but reset
        // the baseline so subsequent interactions behave correctly.
        dailyRewardState.rewardedCellIDs = completedCellIDs
        dailyRewardState.peakCompletedLineCount = newLineCount
        dailyRewardState.fullBoardRewardGranted = newFullBoardRewardGranted

        let earnedTodayPoints = currentBoardPoints

        // Guardrail: totalPoints should not be below today's rewarded points.
        if totalPoints < earnedTodayPoints {
            let correction = earnedTodayPoints - totalPoints
            totalPoints = earnedTodayPoints
            lifetimePoints += correction
        }

        // Guardrail: keep points ledger consistent with non-revocable spending.
        // Sticker ownership can now be revoked when points drop, so only custom reward
        // redemptions must remain protected as irreversible spending.
        let minimumExpectedTotalPoints = nonRevocableConsumedPointsTotal() + earnedTodayPoints
        if totalPoints < minimumExpectedTotalPoints {
            let correction = minimumExpectedTotalPoints - totalPoints
            totalPoints = minimumExpectedTotalPoints
            lifetimePoints += correction
        }
    }

    private func nonRevocableConsumedPointsTotal() -> Int {
        let spentRewardPoints = RewardStore.loadRewards().reduce(0) { partial, reward in
            partial + reward.totalSpentPoints
        }
        return spentRewardPoints
    }

    private func resetDailyRewardStateIfNeeded(for date: Date) {
        let dateKey = PointsStore.dateKey(for: date)
        guard dailyRewardState.dateKey != dateKey else { return }
        dailyRewardState = Self.emptyDailyRewardState(for: date)
    }

    private static func projectVisibleCells(from cache: [[BingoCell]], size: Int, referenceDate: Date) -> [[BingoCell]] {
        (0..<size).map { row in
            (0..<size).map { col in
                if row < cache.count, col < cache[row].count {
                    return cache[row][col].projectedForDisplay(on: referenceDate)
                }
                return BingoCell()
            }
        }
    }

    private static func expandedBoardCache(from saved: SavedBoard) -> [[BingoCell]] {
        var cache = Self.createEmptyGrid(size: Self.maxGridSize)
        let source = saved.fullBoardCells ?? saved.cells
        let maxRows = min(source.count, Self.maxGridSize)

        for row in 0..<maxRows {
            let maxCols = min(source[row].count, Self.maxGridSize)
            for col in 0..<maxCols {
                cache[row][col] = source[row][col]
            }
        }

        return cache
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

    private static func initialDailyRewardState(
        referenceDate: Date,
        boardLastSavedAt: Date?,
        currentCells: [[BingoCell]],
        currentCompletedLines: Set<BingoLine>,
        isBoardFullyCompleted: Bool
    ) -> DailyRewardState {
        let todayKey = PointsStore.dateKey(for: referenceDate)
        if let savedState = PointsStore.loadDailyRewardState(),
           savedState.dateKey == todayKey {
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

    private static func dailyRewardSnapshot(
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

    private static func emptyDailyRewardState(for date: Date) -> DailyRewardState {
        DailyRewardState(dateKey: PointsStore.dateKey(for: date))
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
