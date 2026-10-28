import SwiftUI

struct MacBoardGrid: View {
    @ObservedObject var workspace: MacWorkspaceStore
    let theme: AppTheme
    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<workspace.model.gridSize, id: \.self) { row in
                GridRow {
                    ForEach(0..<workspace.model.gridSize, id: \.self) { col in
                        let cell = workspace.model.cells[row][col]
                        MacTaskCell(
                            cell: cell, theme: theme,
                            isInLine: workspace.model.isInCompletedLine(row: row, col: col),
                            isSelected: workspace.editingCellID == cell.id,
                            isOrganizing: workspace.isOrganizing,
                            isAvailable: workspace.model.canToggleComplete(row: row, col: col),
                            onTap: { workspace.toggle(row: row, col: col) },
                            onEdit: { workspace.editingCellID = cell.id }
                        )
                        .modifier(MacTaskDragModifier(enabled: workspace.isOrganizing, cellID: cell.id))
                        .dropDestination(for: String.self) { values, _ in
                            guard workspace.isOrganizing, let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                            for r in workspace.model.cells.indices {
                                for c in workspace.model.cells[r].indices where workspace.model.cells[r][c].id == id {
                                    workspace.model.moveCell(from: (r, c), to: (row, col))
                                    workspace.persist()
                                    return true
                                }
                            }
                            return false
                        }
                    }
                }
            }
        }
        .overlay {
            MacBingoLineOverlay(lines: workspace.model.completedLines, gridSize: workspace.model.gridSize)
                .stroke(theme.bingoAccentColor.opacity(0.35), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .allowsHitTesting(false)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.75), lineWidth: 1) }
        .shadow(color: theme.darkShadowColor.opacity(0.2), radius: 24, y: 12)
    }
}
