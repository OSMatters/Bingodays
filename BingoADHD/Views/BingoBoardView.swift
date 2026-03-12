import SwiftUI

struct BingoBoardView: View {
    struct EditingTarget: Identifiable {
        let row: Int
        let col: Int

        var id: String {
            "\(row)-\(col)"
        }
    }

    @ObservedObject var viewModel: BingoViewModel
    @State private var editingTarget: EditingTarget?

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let totalSpacing = spacing * CGFloat(viewModel.gridSize - 1)
            let cellSize = (geo.size.width - 24 - totalSpacing) / CGFloat(viewModel.gridSize)

            ZStack {
                VStack(spacing: spacing) {
                    ForEach(0..<viewModel.gridSize, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<viewModel.gridSize, id: \.self) { col in
                                if row < viewModel.cells.count && col < viewModel.cells[row].count {
                                    BingoCellView(
                                        cell: viewModel.cells[row][col],
                                        isInBingoLine: viewModel.isInCompletedLine(row: row, col: col),
                                        isLocked: viewModel.isLocked(row: row, col: col),
                                        cellSize: cellSize,
                                        isFirstCell: row == 0 && col == 0,
                                        onTap: {
                                            if !viewModel.cells[row][col].isEmpty && !viewModel.isLocked(row: row, col: col) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    viewModel.toggleComplete(row: row, col: col)
                                                }
                                            }
                                        },
                                        onLongPress: {
                                            if row < viewModel.cells.count &&
                                                col < viewModel.cells[row].count &&
                                                !viewModel.isLocked(row: row, col: col) {
                                                editingTarget = EditingTarget(row: row, col: col)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
            .padding(12)
            .neumorphicConvex(radius: 20)
        }
        .aspectRatio(1, contentMode: .fit)
        .sheet(item: $editingTarget) { target in
            EditTaskSheet(
                text: viewModel.cells[target.row][target.col].text,
                isForcedTask: viewModel.cells[target.row][target.col].isForced,
                onApplyGroup: { tasks in
                    let didApply = viewModel.applyTasksToEmptyCells(tasks)
                    if didApply {
                        editingTarget = nil
                    }
                    return didApply
                },
                onSave: { newText, isForcedTask in
                    viewModel.updateTask(row: target.row, col: target.col, text: newText, isForced: isForcedTask)
                    editingTarget = nil
                },
                onDelete: {
                    viewModel.clearTask(row: target.row, col: target.col)
                    editingTarget = nil
                },
                onCancel: { editingTarget = nil }
            )
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.visible)
        }
    }
}
