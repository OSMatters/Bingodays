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
    private var fullBoardCells: [[BingoCell]]

    init() {
        self.totalPoints = 0
        self.boardCountdownEndsAt = BingoBoardStore.loadBoardCountdownEndsAt()
        if let saved = BingoBoardStore.loadBoard() {
            self.fullBoardCells = Self.expandedBoardCache(from: saved)
            self.gridSize = saved.gridSize
            self.cells = saved.cells.map { row in
                row.map { cell in
                    var sanitizedCell = cell
                    sanitizedCell.countdownEndsAt = nil
                    return sanitizedCell
                }
            }
            self.fullBoardCells = self.fullBoardCells.map { row in
                row.map { cell in
                    var sanitizedCell = cell
                    sanitizedCell.countdownEndsAt = nil
                    return sanitizedCell
                }
            }
            self.completedLines = saved.completedLines
            BingoBoardStore.saveBoard(SavedBoard(gridSize: saved.gridSize, cells: self.cells, completedLines: self.completedLines, fullBoardCells: self.fullBoardCells))
        } else {
            self.gridSize = 4
            self.cells = Self.createEmptyGrid(size: 4)
            self.fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
            self.syncFullBoardCacheFromVisibleCells()
            BingoBoardStore.saveBoard(SavedBoard(gridSize: 4, cells: self.cells, completedLines: [], fullBoardCells: self.fullBoardCells))
        }
        self.totalPoints = PointsStore.loadTotalPoints() ?? calculateBoardScore()
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
        let previousScore = calculateBoardScore()
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
        save(scoreDelta: calculateBoardScore() - previousScore)
    }

    func updateTask(row: Int, col: Int, text: String, isForced: Bool) {
        guard row < cells.count, col < cells[row].count else { return }
        let previousScore = calculateBoardScore()
        let limitedText = String(text.prefix(Self.maxTaskLength))
        cells[row][col].text = limitedText
        cells[row][col].isForced = !limitedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isForced
        cells[row][col].countdownEndsAt = nil
        if limitedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cells[row][col].isCompleted = false
            cells[row][col].isForced = false
            cells[row][col].countdownEndsAt = nil
        }
        syncFullBoardCacheFromVisibleCells()
        checkBingo()
        if !isBoardFullyCompleted {
            showBoardCompletionAnimation = false
        }
        save(scoreDelta: calculateBoardScore() - previousScore)
    }

    func clearTask(row: Int, col: Int) {
        updateTask(row: row, col: col, text: "", isForced: false)
    }

    @discardableResult
    func applyTasksToEmptyCells(_ tasks: [String]) -> Bool {
        let previousScore = calculateBoardScore()
        let sanitizedTasks = tasks
            .map { String($0.prefix(Self.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sanitizedTasks.isEmpty else { return true }

        let emptyPositions = cells.enumerated().flatMap { row, rowCells in
            rowCells.enumerated().compactMap { entry -> Position? in
                let position = Position(row: row, col: entry.offset)
                return entry.element.isEmpty ? position : nil
            }
        }

        guard emptyPositions.count >= sanitizedTasks.count else { return false }

        for (position, task) in zip(emptyPositions, sanitizedTasks) {
            cells[position.row][position.col].text = task
            cells[position.row][position.col].isCompleted = false
            cells[position.row][position.col].isForced = false
            cells[position.row][position.col].countdownEndsAt = nil
        }

        syncFullBoardCacheFromVisibleCells()
        checkBingo()
        save(scoreDelta: calculateBoardScore() - previousScore)
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
        save(scoreDelta: 0)
    }

    func resetBoard() {
        cells = Self.createEmptyGrid(size: gridSize)
        fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
        completedLines = []
        newlyCompletedLines = []
        showCelebration = false
        showBoardCompletionAnimation = false
        boardCountdownEndsAt = nil
        save(scoreDelta: 0)
    }

    func setBoardCountdown(totalMinutes: Int?) {
        guard let totalMinutes else {
            boardCountdownEndsAt = nil
            save(scoreDelta: 0)
            return
        }

        let clampedMinutes = min(max(totalMinutes, 1), Self.maxCountdownMinutes)
        boardCountdownEndsAt = Date().addingTimeInterval(Double(clampedMinutes * 60))
        save(scoreDelta: 0)
    }

    func shuffleBoard() {
        let previousScore = calculateBoardScore()
        let fixedPositions = bingoLinePositions
        let movablePositions = cells.enumerated().flatMap { row, rowCells in
            rowCells.enumerated().compactMap { entry -> Position? in
                let position = Position(row: row, col: entry.offset)
                return fixedPositions.contains(position) ? nil : position
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
        syncFullBoardCacheFromVisibleCells()
        completedLines = []
        newlyCompletedLines = []
        showBoardCompletionAnimation = false
        checkBingo()
        save(scoreDelta: calculateBoardScore() - previousScore)
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

    private func checkBingo() {
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
        if !newLines.isEmpty {
            newlyCompletedLines = Array(newLines)
            showCelebration = true
            if AppSettings.isHapticsEnabled {
                AppHaptics.emphasis()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.showCelebration = false
                self?.newlyCompletedLines = []
            }
        }
        completedLines = currentLines
    }

    private func save(scoreDelta: Int) {
        let board = SavedBoard(gridSize: gridSize, cells: cells, completedLines: completedLines, fullBoardCells: fullBoardCells)
        BingoBoardStore.saveBoard(board)
        BingoBoardStore.saveBoardCountdownEndsAt(boardCountdownEndsAt)
        BingoDiaryStore.save(board: board)
        totalPoints = max(totalPoints + scoreDelta, 0)
        PointsStore.saveTotalPoints(totalPoints)
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
        save(scoreDelta: 0)
        expiredCountdownMessage = L10n.expiredCountdownMessage
    }

    func clearExpiredCountdownMessage() {
        expiredCountdownMessage = nil
    }

    private func syncDiarySnapshot() {
        let board = SavedBoard(gridSize: gridSize, cells: cells, completedLines: completedLines, fullBoardCells: fullBoardCells)
        BingoDiaryStore.save(board: board)
        PointsStore.saveTotalPoints(totalPoints)
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
        (0..<size).map { row in
            (0..<size).map { col in
                if row < cache.count, col < cache[row].count {
                    return cache[row][col]
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
}
