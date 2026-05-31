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
}
