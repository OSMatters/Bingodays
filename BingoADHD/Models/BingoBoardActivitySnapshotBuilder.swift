import CryptoKit
import Foundation

/// Read-only projection. Never writes resets, completion history, or rewards.
enum BingoBoardActivitySnapshotBuilder {
    static func make(board: BingoBoardStore.NamedBoard, now: Date) -> BingoBoardActivitySnapshot {
        let board = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(board, now: now)
        let size = min(max(board.board.gridSize, 2), BoardEngine.maxGridSize)
        let full = BoardEngine.expandedBoardCache(from: board.board)
        let visible = BoardEngine.projectVisibleCells(from: full, size: size, referenceDate: now)
        let lines = BoardEngine.completedLines(in: visible, size: size)
        let hasForcedTask = visible.flatMap { $0 }.contains {
            $0.isForced && !$0.isCompleted && !$0.isEmpty && $0.isCurrentlyTappable(on: now)
        }
        let cells = (0..<size).flatMap { row in
            (0..<size).map { col in
                let cell = visible[row][col]
                let locked = hasForcedTask && !(cell.isForced && !cell.isCompleted && cell.isCurrentlyTappable(on: now))
                let inBingo = lines.contains(.row(row)) || lines.contains(.column(col)) ||
                    (row == col && lines.contains(.diagonalMain)) ||
                    (row + col == size - 1 && lines.contains(.diagonalAnti))
                return BingoBoardActivitySnapshot.Cell(
                    id: cell.id,
                    text: cell.isEmpty ? "" : cell.text,
                    version: version(cell: full[row][col], board: board, now: now),
                    completed: cell.isCompleted,
                    inBingo: inBingo,
                    enabled: !cell.isEmpty && !locked && (cell.isCompleted || full[row][col].isCurrentlyTappable(on: now))
                )
            }
        }
        return BingoBoardActivitySnapshot(gridSize: size, theme: AppTheme.current.rawValue, cells: cells)
    }

    /// Use a stable digest, not Swift's per-process randomized Hasher. Include the
    /// reset/occurrence anchor so an old button can't complete a new occurrence.
    static func version(cell: BingoCell, board: BingoBoardStore.NamedBoard, now: Date) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = (try? encoder.encode(cell)) ?? Data()
        // A projected reset uses `now` as its applied timestamp. Use the stable
        // schedule boundary instead, so rendering and tapping minutes apart agree.
        let resetAnchor = BoardResetRuleEngine.nextScheduledResetTime(for: board, after: now)
            ?? board.lastTaskResetAppliedAt
        data.append(Data([
            board.taskResetMode.rawValue,
            resetAnchor?.timeIntervalSince1970.description ?? "",
            cell.occurrenceStartVisibleAt(on: now)?.timeIntervalSince1970.description ?? "",
            cell.occurrenceEndVisibleAt(on: now)?.timeIntervalSince1970.description ?? ""
        ].joined(separator: "|").utf8))
        return Data(SHA256.hash(data: data).prefix(12)).base64EncodedString()
    }

    static func staleDate(board: BingoBoardStore.NamedBoard, now: Date) -> Date? {
        let cells = BoardEngine.expandedBoardCache(from: board.board).flatMap { $0 }
        var dates = cells.flatMap { cell in
            [cell.countdownEndsAt, cell.occurrenceStartVisibleAt(on: now), cell.occurrenceEndVisibleAt(on: now)]
                .compactMap { $0 }.filter { $0 > now }
        }
        if let reset = BoardResetRuleEngine.nextScheduledResetTime(for: board, after: now) {
            dates.append(reset)
        }
        return dates.min()
    }
}
