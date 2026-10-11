import SwiftUI

struct BingodaysLockScreenMiniBoard: View {
    let board: SavedBoard

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<board.gridSize, id: \.self) { row in
                GridRow {
                    ForEach(0..<board.gridSize, id: \.self) { col in
                        if board.cells.indices.contains(row), board.cells[row].indices.contains(col) {
                            let cell = board.cells[row][col]
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(.primary.opacity(cell.isCompleted ? 1 : cell.isEmpty ? 0.08 : 0.2))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .stroke(.primary.opacity(cell.isEmpty ? 0.15 : 0.5), lineWidth: 0.5)
                                }
                                .widgetAccentable(cell.isCompleted)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
