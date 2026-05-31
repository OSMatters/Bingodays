import Foundation

enum BoardEngine {
    static let maxGridSize = 5

    struct ExpiredTaskCandidate: Equatable {
        let cellID: UUID
        let row: Int
        let col: Int
        let taskText: String
        let expiredAt: Date
    }

    struct ScheduledTaskReplacementCandidate: Equatable {
        let cellID: UUID
        let row: Int
        let col: Int
        let currentTaskText: String
        let presetTaskText: String
    }

    static func createEmptyGrid(size: Int) -> [[BingoCell]] {
        (0..<size).map { _ in
            (0..<size).map { _ in BingoCell() }
        }
    }

    static func expandedBoardCache(from board: SavedBoard, maxSize: Int = maxGridSize) -> [[BingoCell]] {
        var cache = createEmptyGrid(size: maxSize)
        let source = board.fullBoardCells ?? board.cells
        let maxRows = min(source.count, maxSize)

        for row in 0..<maxRows {
            let maxCols = min(source[row].count, maxSize)
            for col in 0..<maxCols {
                cache[row][col] = source[row][col]
            }
        }

        return cache
    }

    static func projectVisibleCells(
        from cache: [[BingoCell]],
        size: Int,
        referenceDate: Date
    ) -> [[BingoCell]] {
        (0..<size).map { row in
            (0..<size).map { col in
                if row < cache.count, col < cache[row].count {
                    return cache[row][col].projectedForDisplay(on: referenceDate)
                }
                return BingoCell()
            }
        }
    }

    static func completedLines(in cells: [[BingoCell]], size: Int) -> Set<BingoLine> {
        var currentLines: Set<BingoLine> = []

        for row in 0..<size where row < cells.count {
            let rowCells = Array(cells[row].prefix(size))
            if rowCells.count == size && rowCells.allSatisfy({ $0.isCompleted && !$0.isEmpty }) {
                currentLines.insert(.row(row))
            }
        }

        for col in 0..<size {
            var allCompleted = true
            for row in 0..<size {
                guard row < cells.count, col < cells[row].count,
                      cells[row][col].isCompleted, !cells[row][col].isEmpty else {
                    allCompleted = false
                    break
                }
            }
            if allCompleted {
                currentLines.insert(.column(col))
            }
        }

        var mainDiagonalCompleted = true
        for index in 0..<size {
            guard index < cells.count, index < cells[index].count,
                  cells[index][index].isCompleted, !cells[index][index].isEmpty else {
                mainDiagonalCompleted = false
                break
            }
        }
        if mainDiagonalCompleted {
            currentLines.insert(.diagonalMain)
        }

        var antiDiagonalCompleted = true
        for index in 0..<size {
            let col = size - 1 - index
            guard index < cells.count, col < cells[index].count,
                  cells[index][col].isCompleted, !cells[index][col].isEmpty else {
                antiDiagonalCompleted = false
                break
            }
        }
        if antiDiagonalCompleted {
            currentLines.insert(.diagonalAnti)
        }

        return currentLines
    }

    static func boardScore(cells: [[BingoCell]], completedLines: Set<BingoLine>) -> Int {
        let completedTaskCount = cells
            .flatMap { $0 }
            .filter { $0.isCompleted && !$0.isEmpty }
            .count
        let allTasksCompletedBonus = isBoardFullyCompleted(cells) ? 10 : 0
        return completedTaskCount + (completedLines.count * 5) + allTasksCompletedBonus
    }

    static func isBoardFullyCompleted(_ cells: [[BingoCell]]) -> Bool {
        let allCells = cells.flatMap { $0 }
        return !allCells.isEmpty && allCells.allSatisfy { !$0.isEmpty && $0.isCompleted }
    }

    static func expiredTaskCandidate(in board: SavedBoard, now: Date) -> ExpiredTaskCandidate? {
        let size = min(max(board.gridSize, 2), maxGridSize)
        let visibleCells = projectVisibleCells(
            from: expandedBoardCache(from: board),
            size: size,
            referenceDate: now
        )
        return expiredTaskCandidate(in: visibleCells, now: now)
    }

    static func expiredTaskCandidate(in cells: [[BingoCell]], now: Date) -> ExpiredTaskCandidate? {
        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                guard let deadline = expiredTaskDeadline(for: cell, now: now) else {
                    continue
                }

                return ExpiredTaskCandidate(
                    cellID: cell.id,
                    row: row,
                    col: col,
                    taskText: cell.storedTaskText,
                    expiredAt: deadline
                )
            }
        }

        return nil
    }

    static func scheduledTaskReplacementCandidate(
        in fullBoardCells: [[BingoCell]],
        size: Int,
        ignoredCellIDs: Set<UUID>,
        now: Date
    ) -> ScheduledTaskReplacementCandidate? {
        for row in 0..<min(size, fullBoardCells.count) {
            for col in 0..<min(size, fullBoardCells[row].count) {
                let cell = fullBoardCells[row][col]
                guard cell.hasStartVisibilityDate else { continue }
                guard cell.isStartVisibilityReached(on: now) else { continue }
                guard !cell.hasResidentSchedule, !cell.isOneTimeTask else { continue }
                guard !ignoredCellIDs.contains(cell.id) else { continue }

                let currentText = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let presetText = (cell.residentTaskText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !currentText.isEmpty, !presetText.isEmpty, currentText != presetText else {
                    continue
                }

                return ScheduledTaskReplacementCandidate(
                    cellID: cell.id,
                    row: row,
                    col: col,
                    currentTaskText: currentText,
                    presetTaskText: presetText
                )
            }
        }

        return nil
    }

    private static func expiredTaskDeadline(for cell: BingoCell, now: Date) -> Date? {
        guard !cell.isEmpty, !cell.isCompleted else { return nil }

        let executionDeadline = cell.countdownEndsAt
        let visibilityWindowDeadline: Date? = {
            guard executionDeadline == nil else { return nil }
            guard let start = cell.startVisibleAt, let end = cell.endVisibleAt else { return nil }
            guard now >= start, now >= end else { return nil }
            return end
        }()

        guard let deadline = executionDeadline ?? visibilityWindowDeadline,
              deadline <= now else {
            return nil
        }
        return deadline
    }
}
