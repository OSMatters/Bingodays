import SwiftUI

/// A non-interactive neighbor page used only while the pager follows a horizontal drag.
/// It reads a persisted board snapshot and deliberately has no mutation callbacks.
struct BoardSwipePreviewView: View {
    let cells: [[BingoCell]]
    let completedLines: Set<BingoLine>
    let activeForcedCellIDs: Set<UUID>
    let gridSize: Int
    let currentTime: Date
    let sideLength: CGFloat

    private let boardInnerPadding: CGFloat
    private let cellSpacing: CGFloat

    init(
        savedBoard: SavedBoard,
        currentTime: Date,
        sideLength: CGFloat
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
        self.currentTime = currentTime
        self.sideLength = sideLength

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

    var body: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<gridSize, id: \.self) { row in
                HStack(spacing: cellSpacing) {
                    ForEach(0..<gridSize, id: \.self) { column in
                        previewCell(row: row, column: column)
                    }
                }
            }
        }
        .padding(boardInnerPadding)
        .frame(width: sideLength, height: sideLength)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "EBEBEB"))
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func previewCell(row: Int, column: Int) -> some View {
        if row < cells.count, column < cells[row].count {
            let cell = cells[row][column]
            BingoCellView(
                cell: cell,
                currentTime: currentTime,
                isScheduledInactive: isScheduledInactive(cell),
                scheduleStatusText: nil,
                debugIdentifier: "board-swipe-preview-\(row)-\(column)",
                isInBingoLine: isInCompletedLine(row: row, column: column),
                isLocked: isLocked(cell),
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

    private var cellSize: CGFloat {
        let totalSpacing = cellSpacing * CGFloat(gridSize - 1)
        return (sideLength - (boardInnerPadding * 2) - totalSpacing) / CGFloat(gridSize)
    }

    private func isScheduledInactive(_ cell: BingoCell) -> Bool {
        (cell.isDisplayOnlyInactive || !cell.isCurrentlyTappable(on: currentTime)) && !cell.isCompleted
    }

    private func isLocked(_ cell: BingoCell) -> Bool {
        !activeForcedCellIDs.isEmpty && !activeForcedCellIDs.contains(cell.id)
    }

    private func isInCompletedLine(row: Int, column: Int) -> Bool {
        completedLines.contains { line in
            switch line {
            case .row(let lineRow):
                lineRow == row
            case .column(let lineColumn):
                lineColumn == column
            case .diagonalMain:
                row == column
            case .diagonalAnti:
                row + column == gridSize - 1
            }
        }
    }
}
