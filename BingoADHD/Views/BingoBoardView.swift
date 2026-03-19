import SwiftUI

struct BingoBoardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    struct EditingTarget: Identifiable, Equatable {
        let row: Int
        let col: Int

        var id: String {
            "\(row)-\(col)"
        }
    }

    private struct DragState: Equatable {
        let source: EditingTarget
        var translation: CGSize = .zero
        var destination: EditingTarget?
    }

    private struct DeletedCellSnapshot: Equatable {
        let target: EditingTarget
        let cell: BingoCell
    }

    @ObservedObject var viewModel: BingoViewModel
    let currentTime: Date
    @State private var editingTarget: EditingTarget?
    @State private var actionTarget: EditingTarget?
    @State private var dragState: DragState?
    @State private var residentScheduleNotice: String?
    @State private var deletedCellSnapshot: DeletedCellSnapshot?
    @State private var undoDismissWorkItem: DispatchWorkItem?
    private let boardSurfaceColor = Color(hex: "EBF0F7")
    private let boardInnerShadowDark = Color(hex: "D1D9E6")
    private let boardInnerShadowLight = Color.white
    private let boardInnerShadowRadius: CGFloat = 8
    private let boardInnerShadowOffset: CGFloat = 6

    private let boardOuterPadding: CGFloat = 0
    private var boardInnerPadding: CGFloat {
        switch viewModel.gridSize {
        case ...3: return 16
        case 4: return 13
        default: return 10
        }
    }
    private var cellSpacing: CGFloat {
        switch viewModel.gridSize {
        case ...3: return 15
        case 4: return 10
        default: return 8
        }
    }
    private var boardCornerRadius: CGFloat {
        viewModel.gridSize <= 3 ? 24 : 20
    }
    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        GeometryReader { geo in
            let totalSpacing = cellSpacing * CGFloat(viewModel.gridSize - 1)
            let availableWidth = geo.size.width - (boardOuterPadding * 2) - (boardInnerPadding * 2)
            let cellSize = (availableWidth - totalSpacing) / CGFloat(viewModel.gridSize)

            ZStack {
                VStack(spacing: cellSpacing) {
                    ForEach(0..<viewModel.gridSize, id: \.self) { row in
                        HStack(spacing: cellSpacing) {
                            ForEach(0..<viewModel.gridSize, id: \.self) { col in
                                if row < viewModel.cells.count && col < viewModel.cells[row].count {
                                    let target = EditingTarget(row: row, col: col)
                                    let isDragSource = dragState?.source == target
                                    let isDropTarget = dragState?.destination == target && dragState?.source != target

                                    BingoCellView(
                                        cell: viewModel.cells[row][col],
                                        currentTime: currentTime,
                                        isInBingoLine: viewModel.isInCompletedLine(row: row, col: col),
                                        isLocked: viewModel.isLocked(row: row, col: col),
                                        cellSize: cellSize,
                                        isFirstCell: row == 0 && col == 0,
                                        isInteractive: dragState == nil || isDragSource,
                                        isDragSource: isDragSource,
                                        isDropTarget: isDropTarget,
                                        onTap: {
                                            dismissActionMenu()
                                            if !viewModel.cells[row][col].isEmpty && !viewModel.isLocked(row: row, col: col) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    viewModel.toggleComplete(row: row, col: col)
                                                }
                                            }
                                        },
                                        onLongPressRelease: {
                                            guard !viewModel.isLocked(row: row, col: col) else { return }
                                            if viewModel.cells[row][col].isEmpty {
                                                editingTarget = target
                                            } else {
                                                actionTarget = target
                                            }
                                        },
                                        onDragStart: {
                                            guard !viewModel.isLocked(row: row, col: col) else { return }
                                            guard !viewModel.cells[row][col].isEmpty else { return }
                                            dismissActionMenu()
                                            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.82)) {
                                                dragState = DragState(source: target)
                                            }
                                        },
                                        onDragMove: { translation in
                                            guard dragState?.source == target else { return }
                                            dragState?.translation = translation
                                            dragState?.destination = destinationTarget(
                                                for: target,
                                                translation: translation,
                                                cellSize: cellSize
                                            )
                                        },
                                        onDragEnd: { translation in
                                            guard dragState?.source == target else { return }
                                            let destination = destinationTarget(
                                                for: target,
                                                translation: translation,
                                                cellSize: cellSize
                                            )

                                            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.84)) {
                                                if let destination, destination != target {
                                                    viewModel.moveCell(
                                                        from: (target.row, target.col),
                                                        to: (destination.row, destination.col)
                                                    )
                                                }
                                                dragState = nil
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(boardInnerPadding)

                if actionTarget != nil {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissActionMenu()
                        }
                }

                if let actionTarget {
                    actionMenu(for: actionTarget, cellSize: cellSize, boardSize: geo.size)
                }

                if let dragState {
                    draggedCellOverlay(for: dragState, cellSize: cellSize)
                }
            }
            .padding(boardOuterPadding)
            .background(
                boardContainerSurface
            )
            .clipShape(RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .top) {
            if deletedCellSnapshot != nil {
                undoToast
                    .padding(.horizontal, 20)
                    .padding(.top, -142)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .sheet(item: phoneEditingTargetBinding) { target in
            editTaskSheet(for: target)
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: padEditingTargetBinding) { target in
            NineTenthsSheetContainer(contentMaxWidth: 860) {
                editTaskSheet(for: target)
            }
            .background(Color.clear)
        }
        .alert(L10n.taskScheduledTitle, isPresented: Binding(
            get: { residentScheduleNotice != nil },
            set: { newValue in
                if !newValue {
                    residentScheduleNotice = nil
                }
            }
        )) {
            Button(L10n.ok) {
                residentScheduleNotice = nil
            }
        } message: {
            Text(residentScheduleNotice ?? "")
        }
    }

    private var boardContainerSurface: some View {
        let shape = RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous)
        let style = boardSurfaceColor
            .shadow(
                .inner(
                    color: boardInnerShadowDark,
                    radius: boardInnerShadowRadius,
                    x: boardInnerShadowOffset,
                    y: boardInnerShadowOffset
                )
            )
            .shadow(
                .inner(
                    color: boardInnerShadowLight,
                    radius: boardInnerShadowRadius,
                    x: -boardInnerShadowOffset,
                    y: -boardInnerShadowOffset
                )
            )

        return shape
            .fill(style)
    }

    private var undoToast: some View {
        HStack(spacing: 12) {
            Text(L10n.taskDeleted)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.96))

            Spacer(minLength: 0)

            Button(L10n.undo) {
                if let deletedCellSnapshot {
                    restoreDeletedCell(deletedCellSnapshot)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(NeumorphicColors.accent.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                )
        )
        .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
    }

    private var phoneEditingTargetBinding: Binding<EditingTarget?> {
        Binding(
            get: { isPadLayout ? nil : editingTarget },
            set: { editingTarget = $0 }
        )
    }

    private var padEditingTargetBinding: Binding<EditingTarget?> {
        Binding(
            get: { isPadLayout ? editingTarget : nil },
            set: { editingTarget = $0 }
        )
    }

    private func editTaskSheet(for target: EditingTarget) -> some View {
        EditTaskSheet(
            text: viewModel.cells[target.row][target.col].storedTaskText,
            isForcedTask: viewModel.cells[target.row][target.col].isForced,
            residentWeekdays: viewModel.cells[target.row][target.col].residentWeekdays,
            estimatedDurationMinutes: viewModel.remainingTaskCountdownMinutes(row: target.row, col: target.col),
            onSave: { newText, isForcedTask, residentWeekdays, estimatedDurationMinutes in
                let scheduleNotice = residentVisibilityNotice(
                    text: newText,
                    residentWeekdays: residentWeekdays
                )
                viewModel.updateTask(
                    row: target.row,
                    col: target.col,
                    text: newText,
                    isForced: isForcedTask,
                    residentWeekdays: residentWeekdays,
                    estimatedDurationMinutes: estimatedDurationMinutes
                )
                editingTarget = nil
                residentScheduleNotice = scheduleNotice
            },
            onDelete: {
                handleDelete(at: target)
                editingTarget = nil
            },
            onCancel: { editingTarget = nil }
        )
    }

    private func actionMenu(for target: EditingTarget, cellSize: CGFloat, boardSize: CGSize) -> some View {
        let menuSize = CGSize(width: 152, height: 104)
        let position = actionMenuPosition(
            for: target,
            cellSize: cellSize,
            boardSize: boardSize,
            menuSize: menuSize
        )

        return VStack(spacing: 10) {
            Button {
                dismissActionMenu()
                editingTarget = target
            } label: {
                Label(L10n.editTask, systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                handleDelete(at: target)
            } label: {
                Label(L10n.deleteTask, systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(NeumorphicColors.bingoAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: menuSize.width, height: menuSize.height)
        .background(Color.clear.neumorphicConvex(radius: 16))
        .position(position)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func draggedCellOverlay(for dragState: DragState, cellSize: CGFloat) -> some View {
        let sourceCell = viewModel.cells[dragState.source.row][dragState.source.col]
        let startCenter = cellCenter(for: dragState.source, cellSize: cellSize)

        return BingoCellView(
            cell: sourceCell,
            currentTime: currentTime,
            isInBingoLine: viewModel.isInCompletedLine(row: dragState.source.row, col: dragState.source.col),
            isLocked: false,
            cellSize: cellSize,
            isFirstCell: false,
            isInteractive: false,
            isDragSource: false,
            isDropTarget: false,
            onTap: {},
            onLongPressRelease: {},
            onDragStart: {},
            onDragMove: { _ in },
            onDragEnd: { _ in }
        )
        .position(
            x: startCenter.x + dragState.translation.width,
            y: startCenter.y + dragState.translation.height
        )
        .allowsHitTesting(false)
        .shadow(color: NeumorphicColors.darkShadow.opacity(0.2), radius: 14, x: 0, y: 8)
    }

    private func handleDelete(at target: EditingTarget) {
        dismissActionMenu()

        guard let deletedCell = viewModel.deleteCell(row: target.row, col: target.col) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            deletedCellSnapshot = DeletedCellSnapshot(target: target, cell: deletedCell)
        }
        scheduleUndoDismissal()
    }

    private func restoreDeletedCell(_ snapshot: DeletedCellSnapshot) {
        undoDismissWorkItem?.cancel()
        undoDismissWorkItem = nil
        viewModel.restoreCell(snapshot.cell, row: snapshot.target.row, col: snapshot.target.col)
        withAnimation(.easeInOut(duration: 0.2)) {
            deletedCellSnapshot = nil
        }
    }

    private func scheduleUndoDismissal() {
        undoDismissWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                deletedCellSnapshot = nil
            }
        }

        undoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func dismissActionMenu() {
        withAnimation(.easeInOut(duration: 0.18)) {
            actionTarget = nil
        }
    }

    private func actionMenuPosition(
        for target: EditingTarget,
        cellSize: CGFloat,
        boardSize: CGSize,
        menuSize: CGSize
    ) -> CGPoint {
        let cellCenter = cellCenter(for: target, cellSize: cellSize)
        let topAnchor = cellCenter.y - (cellSize / 2) - 12 - (menuSize.height / 2)
        let bottomAnchor = cellCenter.y + (cellSize / 2) + 12 + (menuSize.height / 2)

        let minX = menuSize.width / 2 + boardOuterPadding
        let maxX = boardSize.width - menuSize.width / 2 - boardOuterPadding
        let clampedX = min(max(cellCenter.x, minX), maxX)

        let minY = menuSize.height / 2 + boardOuterPadding
        let maxY = boardSize.height - menuSize.height / 2 - boardOuterPadding
        let preferredY = topAnchor >= minY ? topAnchor : bottomAnchor

        return CGPoint(
            x: clampedX,
            y: min(max(preferredY, minY), maxY)
        )
    }

    private func cellCenter(for target: EditingTarget, cellSize: CGFloat) -> CGPoint {
        let origin = boardOuterPadding + boardInnerPadding + cellSize / 2
        let stride = cellSize + cellSpacing

        return CGPoint(
            x: origin + CGFloat(target.col) * stride,
            y: origin + CGFloat(target.row) * stride
        )
    }

    private func destinationTarget(
        for source: EditingTarget,
        translation: CGSize,
        cellSize: CGFloat
    ) -> EditingTarget? {
        let origin = boardOuterPadding + boardInnerPadding
        let stride = cellSize + cellSpacing
        let totalGridSize = CGFloat(viewModel.gridSize) * cellSize + CGFloat(viewModel.gridSize - 1) * cellSpacing
        let sourceCenter = cellCenter(for: source, cellSize: cellSize)
        let location = CGPoint(
            x: sourceCenter.x + translation.width,
            y: sourceCenter.y + translation.height
        )

        guard location.x >= origin,
              location.y >= origin,
              location.x <= origin + totalGridSize,
              location.y <= origin + totalGridSize else {
            return nil
        }

        let col = min(max(Int((location.x - origin) / stride), 0), viewModel.gridSize - 1)
        let row = min(max(Int((location.y - origin) / stride), 0), viewModel.gridSize - 1)
        let target = EditingTarget(row: row, col: col)

        guard target == source || !viewModel.isLocked(row: row, col: col) else {
            return nil
        }

        return target
    }

    private func residentVisibilityNotice(text: String, residentWeekdays: Set<Int>, referenceDate: Date = .now) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !residentWeekdays.isEmpty else { return nil }

        let today = Calendar.current.component(.weekday, from: referenceDate)
        guard !residentWeekdays.contains(today) else { return nil }

        let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
        let labels = orderedWeekdays
            .filter { residentWeekdays.contains($0) }
            .map(weekdayLabel(for:))

        guard !labels.isEmpty else { return nil }
        return L10n.taskScheduledMessage(labels.joined(separator: AppLanguage.current == .english ? ", " : "、"))
    }

    private func weekdayLabel(for weekday: Int) -> String {
        switch weekday {
        case 2: return L10n.mondayShort
        case 3: return L10n.tuesdayShort
        case 4: return L10n.wednesdayShort
        case 5: return L10n.thursdayShort
        case 6: return L10n.fridayShort
        case 7: return L10n.saturdayShort
        default: return L10n.sundayShort
        }
    }
}
