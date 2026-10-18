import SwiftUI

/// A non-interactive neighbor page used only while the pager follows a horizontal drag.
/// It reads a persisted board snapshot and deliberately has no mutation callbacks.
struct BoardSwipePreviewView: View, Equatable {
    let savedBoard: SavedBoard
    let currentTime: Date
    let sideLength: CGFloat

    // No retained cache: changes to the snapshot, time, or size invalidate equality.
    // Drag-only updates skip this body and therefore skip the board projection.
    private struct Projection {
        let cells: [[BingoCell]]
        let completedLines: Set<BingoLine>
        let activeForcedCellIDs: Set<UUID>
        let gridSize: Int

        let boardInnerPadding: CGFloat
        let cellSpacing: CGFloat

        init(
            savedBoard: SavedBoard,
            currentTime: Date
        ) {
            let normalizedGridSize = min(max(savedBoard.gridSize, 2), BoardEngine.maxGridSize)
            let expandedCells = BoardEngine.expandedBoardCache(from: savedBoard)
            let visibleCells = BoardEngine.projectVisibleCells(
                from: expandedCells,
                size: normalizedGridSize,
                referenceDate: currentTime
            )

            cells = visibleCells
            completedLines = BoardEngine.completedLines(in: visibleCells, size: normalizedGridSize)
            activeForcedCellIDs = Set(
                visibleCells
                    .flatMap(\.self)
                    .filter { cell in
                        cell.isForced &&
                            !cell.isCompleted &&
                            !cell.isEmpty &&
                            cell.isCurrentlyTappable(on: currentTime)
                    }
                    .map(\.id)
            )
            gridSize = normalizedGridSize

            switch normalizedGridSize {
            case ...3:
                boardInnerPadding = 16
                cellSpacing = 15
            case 4:
                boardInnerPadding = 13
                cellSpacing = 10
            default:
                boardInnerPadding = 10
                cellSpacing = 8
            }
        }
    }

    var body: some View {
        let projection = Projection(savedBoard: savedBoard, currentTime: currentTime)
        VStack(spacing: projection.cellSpacing) {
            ForEach(0..<projection.gridSize, id: \.self) { row in
                HStack(spacing: projection.cellSpacing) {
                    ForEach(0..<projection.gridSize, id: \.self) { column in
                        previewCell(row: row, column: column, projection: projection)
                    }
                }
            }
        }
        .padding(projection.boardInnerPadding)
        .frame(width: sideLength, height: sideLength)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "EBEBEB"))
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func previewCell(row: Int, column: Int, projection: Projection) -> some View {
        let cellSize = cellSize(for: projection)
        if row < projection.cells.count, column < projection.cells[row].count {
            let cell = projection.cells[row][column]
            BingoCellView(
                cell: cell,
                currentTime: currentTime,
                isScheduledInactive: isScheduledInactive(cell),
                scheduleStatusText: nil,
                debugIdentifier: "board-swipe-preview-\(row)-\(column)",
                isInBingoLine: isInCompletedLine(row: row, column: column, projection: projection),
                isLocked: !projection.activeForcedCellIDs.isEmpty && !projection.activeForcedCellIDs.contains(cell.id),
                cellSize: cellSize,
                isFirstCell: row == 0 && column == 0,
                isInteractive: false,
                isDragSource: false,
                isDropTarget: false,
                emptyHintText: nil,
                onTap: {},
                onLongPressRelease: {},
                onDragStart: {},
                onDragMove: { _ in },
                onDragEnd: { _ in }
            )
        } else {
            Color.clear
                .frame(width: cellSize, height: cellSize)
        }
    }

    private func cellSize(for projection: Projection) -> CGFloat {
        let totalSpacing = projection.cellSpacing * CGFloat(projection.gridSize - 1)
        return (sideLength - (projection.boardInnerPadding * 2) - totalSpacing) / CGFloat(projection.gridSize)
    }

    private func isScheduledInactive(_ cell: BingoCell) -> Bool {
        (cell.isDisplayOnlyInactive || !cell.isCurrentlyTappable(on: currentTime)) && !cell.isCompleted
    }

    private func isInCompletedLine(row: Int, column: Int, projection: Projection) -> Bool {
        projection.completedLines.contains { line in
            switch line {
            case .row(let lineRow):
                lineRow == row
            case .column(let lineColumn):
                lineColumn == column
            case .diagonalMain:
                row == column
            case .diagonalAnti:
                row + column == projection.gridSize - 1
            }
        }
    }
}
