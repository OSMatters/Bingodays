import SwiftUI
import Combine

class BingoViewModel: ObservableObject {
    static let maxGridSize = 5
    static let maxTaskLength = 20
    static let maxCountdownMinutes = 24 * 60

    @Published var cells: [[BingoCell]]
    @Published var gridSize: Int
    @Published var completedLines: Set<BingoLine> = []
    @Published var newlyCompletedLines: [BingoLine] = []
    @Published var showCelebration: Bool = false
    @Published var totalPoints: Int
    @Published var expiredCountdownMessage: String?
    @Published var boardCountdownEndsAt: Date?
    @Published var showBoardCompletionAnimation = false
    @Published var dailyResetNoticeID = 0
    private var fullBoardCells: [[BingoCell]]
    private var lifetimePoints: Int
    private var dailyRewardState: DailyRewardState

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
            self.fullBoardCells = Self.expandedBoardCache(from: saved)
            self.gridSize = saved.gridSize
            self.fullBoardCells = self.fullBoardCells.map { row in
                row.map { cell in
                    var sanitizedCell = cell
                    sanitizedCell.countdownEndsAt = nil
                    return sanitizedCell
                }
            }
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
            self.gridSize = 4
            self.cells = Self.createEmptyGrid(size: 4)
            self.fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
            self.syncFullBoardCacheFromVisibleCells()
            BingoBoardStore.saveBoard(
                SavedBoard(gridSize: 4, cells: self.cells, completedLines: [], fullBoardCells: self.fullBoardCells)
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
        syncDiarySnapshot()
    }

    static func createEmptyGrid(size: Int) -> [[BingoCell]] {
        (0..<size).map { _ in
            (0..<size).map { _ in BingoCell() }
        }
    }

    func toggleComplete(row: Int, col: Int) {
        guard row < cells.count, col < cells[row].count else { return }
        guard !cells[row][col].isEmpty else { return }
        guard !isLocked(row: row, col: col) else { return }
        let wasBoardFullyCompleted = isBoardFullyCompleted
        cells[row][col].isCompleted.toggle()
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
        save()
    }

    func updateTask(row: Int, col: Int, text: String, isForced: Bool, residentWeekdays: Set<Int>) {
        guard row < cells.count, col < cells[row].count else { return }
        let limitedText = String(text.prefix(Self.maxTaskLength))
        let trimmedText = limitedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWeekdays: Set<Int> = trimmedText.isEmpty ? [] : residentWeekdays

        cells[row][col].residentWeekdays = normalizedWeekdays
        cells[row][col].residentTaskText = normalizedWeekdays.isEmpty ? nil : limitedText
        cells[row][col].text = normalizedWeekdays.isEmpty ? limitedText : normalizedDisplayText(for: cells[row][col], referenceDate: .now)
        cells[row][col].isForced = !trimmedText.isEmpty && isForced
        cells[row][col].countdownEndsAt = nil

        if trimmedText.isEmpty {
            cells[row][col].isCompleted = false
            cells[row][col].isForced = false
            cells[row][col].countdownEndsAt = nil
            cells[row][col].residentTaskText = nil
            cells[row][col].residentWeekdays = []
        }
        syncFullBoardCacheFromVisibleCells()
        cells = visibleCells(from: fullBoardCells, size: gridSize)
        checkBingo()
        if !isBoardFullyCompleted {
            showBoardCompletionAnimation = false
        }
        settleRewardsIfNeeded()
        save()
    }

    func clearTask(row: Int, col: Int) {
        updateTask(row: row, col: col, text: "", isForced: false, residentWeekdays: [])
    }

    @discardableResult
    func deleteCell(row: Int, col: Int) -> BingoCell? {
        guard row < cells.count, col < cells[row].count else { return nil }
        let deletedCell = cells[row][col]
        guard !deletedCell.isEmpty else { return nil }

        cells[row][col] = BingoCell()
        refreshBoardState(
            shouldCelebrateNewLines: false
        )
        return deletedCell
    }

    func restoreCell(_ cell: BingoCell, row: Int, col: Int) {
        guard row < cells.count, col < cells[row].count else { return }
        cells[row][col] = cell.projectedForDisplay(on: .now)
        refreshBoardState(
            shouldCelebrateNewLines: false
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
            cells[position.row][position.col].isCompleted = false
            cells[position.row][position.col].isForced = false
            cells[position.row][position.col].countdownEndsAt = nil
        }

        syncFullBoardCacheFromVisibleCells()
        checkBingo()
        settleRewardsIfNeeded()
        save()
        return true
    }

    func resizeGrid(to newSize: Int) {
        guard newSize >= 2 && newSize <= Self.maxGridSize else { return }
        syncFullBoardCacheFromVisibleCells()
        gridSize = newSize
        cells = visibleCells(from: fullBoardCells, size: newSize)
        completedLines = []
        boardCountdownEndsAt = nil
        showBoardCompletionAnimation = false
        checkBingo()
        settleRewardsIfNeeded()
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
        save()
    }

    func setBoardCountdown(totalMinutes: Int?) {
        guard let totalMinutes else {
            boardCountdownEndsAt = nil
            save()
            return
        }

        let clampedMinutes = min(max(totalMinutes, 1), Self.maxCountdownMinutes)
        boardCountdownEndsAt = Date().addingTimeInterval(Double(clampedMinutes * 60))
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

    private func refreshBoardState(shouldCelebrateNewLines: Bool) {
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
        settleRewardsIfNeeded()
        save()
    }

    private func save(persistDiary: Bool = true, savedAt: Date = .now) {
        let board = SavedBoard(gridSize: gridSize, cells: cells, completedLines: completedLines, fullBoardCells: fullBoardCells)
        BingoBoardStore.saveBoard(board, savedAt: savedAt)
        BingoBoardStore.saveBoardCountdownEndsAt(boardCountdownEndsAt)
        if persistDiary {
            BingoDiaryStore.save(board: board, on: savedAt)
        }
        PointsStore.saveTotalPoints(totalPoints)
        PointsStore.saveLifetimePoints(lifetimePoints)
        PointsStore.saveDailyRewardState(dailyRewardState)
    }

    func processExpiredCountdowns(now: Date = Date()) {
        guard let deadline = boardCountdownEndsAt, deadline <= now else { return }

        cells = Self.createEmptyGrid(size: gridSize)
        fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
        completedLines = []
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
        boardCountdownEndsAt = nil
        save()
        expiredCountdownMessage = L10n.expiredCountdownMessage
    }

    func processDailyCompletionReset(now: Date = Date()) {
        guard boardCountdownEndsAt == nil else { return }
        guard let lastSavedAt = BingoBoardStore.loadBoardLastSavedAt() else {
            BingoBoardStore.saveBoardLastSavedAt(now)
            return
        }

        let calendar = Calendar.current
        guard !calendar.isDate(lastSavedAt, inSameDayAs: now) else { return }

        let hadCompletedTasks = fullBoardCells
            .flatMap { $0 }
            .contains { $0.isCompleted && !$0.isEmpty }
        let hadCompletedLines = !completedLines.isEmpty

        fullBoardCells = fullBoardCells.map { row in
            row.map { cell in
                var updated = cell
                updated.isCompleted = false
                updated.countdownEndsAt = nil
                return updated
            }
        }
        cells = visibleCells(from: fullBoardCells, size: gridSize)
        completedLines = []
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
        dailyRewardState = Self.emptyDailyRewardState(for: now)

        save(
            persistDiary: false,
            savedAt: now
        )

        if hadCompletedTasks || hadCompletedLines {
            dailyResetNoticeID += 1
        }
    }

    func clearExpiredCountdownMessage() {
        expiredCountdownMessage = nil
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

    private func visibleCells(from cache: [[BingoCell]], size: Int) -> [[BingoCell]] {
        Self.projectVisibleCells(from: cache, size: size, referenceDate: .now)
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

    private func settleRewardsIfNeeded(on date: Date = .now) {
        resetDailyRewardStateIfNeeded(for: date)

        let completedCellIDs = Set(
            cells
                .flatMap { $0 }
                .filter { $0.isCompleted && !$0.isEmpty }
                .map(\.id)
        )
        let newRewardedCellIDs = completedCellIDs.subtracting(dailyRewardState.rewardedCellIDs)
        let newlyCompletedLineCount = max(completedLines.count - dailyRewardState.peakCompletedLineCount, 0)
        let shouldGrantFullBoardReward = isBoardFullyCompleted && !dailyRewardState.fullBoardRewardGranted

        let pointsEarned = newRewardedCellIDs.count + (newlyCompletedLineCount * 5) + (shouldGrantFullBoardReward ? 10 : 0)
        guard pointsEarned > 0 || !newRewardedCellIDs.isEmpty || newlyCompletedLineCount > 0 || shouldGrantFullBoardReward else {
            return
        }

        if pointsEarned > 0 {
            totalPoints += pointsEarned
            lifetimePoints += pointsEarned
        }

        dailyRewardState.rewardedCellIDs.formUnion(newRewardedCellIDs)
        dailyRewardState.peakCompletedLineCount = max(dailyRewardState.peakCompletedLineCount, completedLines.count)
        if shouldGrantFullBoardReward {
            dailyRewardState.fullBoardRewardGranted = true
        }
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

        let rewardedCellIDs = Set(
            currentCells
                .flatMap { $0 }
                .filter { $0.isCompleted && !$0.isEmpty }
                .map(\.id)
        )
        return DailyRewardState(
            dateKey: todayKey,
            rewardedCellIDs: rewardedCellIDs,
            peakCompletedLineCount: currentCompletedLines.count,
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
