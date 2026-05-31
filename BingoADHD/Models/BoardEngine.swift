import Foundation

enum BoardEngine {
    static let maxGridSize = 5

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
}
