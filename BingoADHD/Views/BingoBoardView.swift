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
    let shouldShowCenterLongPressHint: Bool
    var onCellCompletionToggled: (() -> Void)? = nil
    var onCellReorderActiveChanged: ((Bool) -> Void)? = nil
    @State private var editingTarget: EditingTarget?
    @State private var actionTarget: EditingTarget?
    @State private var dragState: DragState?
    @State private var residentScheduleNotice: String?
    @State private var deletedCellSnapshot: DeletedCellSnapshot?
    @State private var undoDismissWorkItem: DispatchWorkItem?
    @State private var pendingDeleteTarget: EditingTarget?
    @State private var editSheetSessionID = UUID()
    private let boardSurfaceColor = Color(hex: "EBEBEB")

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
        24
    }
    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        GeometryReader { geo in
            let totalSpacing = cellSpacing * CGFloat(viewModel.gridSize - 1)
            let availableWidth = geo.size.width - (boardOuterPadding * 2) - (boardInnerPadding * 2)
            let cellSize = (availableWidth - totalSpacing) / CGFloat(viewModel.gridSize)
            let isBoardCompletelyEmpty = viewModel.cells.flatMap(\.self).allSatisfy(\.isEmpty)
            let centerIndex = viewModel.gridSize / 2
            let centerHintText = shouldShowCenterLongPressHint
                ? L10n.tr("Long press to edit tile task", zhHans: "长按编辑格子任务", zhHant: "長按編輯格子任務")
                : L10n.emptyBoardLongPressHint

            ZStack {
                VStack(spacing: cellSpacing) {
                    ForEach(0..<viewModel.gridSize, id: \.self) { row in
                        HStack(spacing: cellSpacing) {
                            ForEach(0..<viewModel.gridSize, id: \.self) { col in
                                if row < viewModel.cells.count && col < viewModel.cells[row].count {
                                    let target = EditingTarget(row: row, col: col)
                                    let isDragSource = dragState?.source == target
                                    let isDropTarget = dragState?.destination == target && dragState?.source != target
                                    let isScheduledInactive = !viewModel.isTaskCurrentlyTappable(
                                        row: row,
                                        col: col,
                                        referenceDate: currentTime
                                    ) && !viewModel.cells[row][col].isEmpty

                                    BingoCellView(
                                        cell: viewModel.cells[row][col],
                                        currentTime: currentTime,
                                        isScheduledInactive: isScheduledInactive,
                                        debugIdentifier: "\(row)-\(col)",
                                        isInBingoLine: viewModel.isInCompletedLine(row: row, col: col),
                                        isLocked: viewModel.isLocked(row: row, col: col),
                                        cellSize: cellSize,
                                        isFirstCell: row == 0 && col == 0,
                                        isInteractive: dragState == nil || isDragSource,
                                        isDragSource: isDragSource,
                                        isDropTarget: isDropTarget,
                                        emptyHintText: (isBoardCompletelyEmpty || shouldShowCenterLongPressHint) &&
                                            viewModel.cells[row][col].isEmpty &&
                                            row == centerIndex &&
                                            col == centerIndex
                                            ? centerHintText
                                            : nil,
                                        onTap: {
                                            dismissActionMenu()
                                            if !viewModel.cells[row][col].isEmpty &&
                                                !viewModel.isLocked(row: row, col: col) &&
                                                viewModel.isTaskCurrentlyTappable(row: row, col: col) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    viewModel.toggleComplete(row: row, col: col)
                                                }
                                                DispatchQueue.main.async {
                                                    onCellCompletionToggled?()
                                                }
                                            }
                                        },
                                        onLongPressRelease: {
                                            guard !viewModel.isLocked(row: row, col: col) else {
                                                debugGesture("long press blocked by lock at \(row)-\(col)")
                                                return
                                            }
                                            // Fix 2: use hasStoredTask (checks storedTaskText) rather
                                            // than isEmpty (checks projected text). Resident tasks
                                            // on non-active days have text="" but storedTaskText!="".
                                            if viewModel.cells[row][col].hasStoredTask {
                                                debugGesture("long press open action menu at \(row)-\(col)")
                                                DispatchQueue.main.async {
                                                    setActionTargetWithoutSystemAnimation(target)
                                                }
                                            } else {
                                                debugGesture("long press open editor at \(row)-\(col)")
                                                presentEditor(for: target)
                                            }
                                        },
                                        onDragStart: {
                                            guard !viewModel.isLocked(row: row, col: col) else { return }
                                            guard !viewModel.cells[row][col].isEmpty else { return }
                                            dismissActionMenu()
                                            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.82)) {
                                                dragState = DragState(source: target)
                                            }
                                            onCellReorderActiveChanged?(true)
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
                                            onCellReorderActiveChanged?(false)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(boardInnerPadding)

                if let dragState {
                    draggedCellOverlay(for: dragState, cellSize: cellSize)
                        .zIndex(3)
                }
            }
            .padding(boardOuterPadding)
            .background(
                boardContainerSurface
            )
            .clipShape(RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .onDisappear {
            if dragState != nil {
                dragState = nil
                onCellReorderActiveChanged?(false)
            }
        }
        .overlay(alignment: .top) {
            if deletedCellSnapshot != nil {
                undoToast
                    .padding(.horizontal, 20)
                    .padding(.top, -142)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .fullScreenCover(item: phoneEditingTargetBinding) { target in
            editTaskSheet(for: target)
                .background(Color.clear)
                .presentationBackground(.clear)
        }
        .fullScreenCover(item: padEditingTargetBinding) { target in
            editTaskSheet(for: target)
                .background(Color.clear)
                .presentationBackground(.clear)
        }
        .fullScreenCover(item: $actionTarget) { target in
            taskActionsOverlay(for: target)
                .background(Color.clear)
                .presentationBackground(.clear)
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
        .alert(L10n.tr("Remove task?", zhHans: "移除任务？", zhHant: "移除任務？"), isPresented: Binding(
            get: { pendingDeleteTarget != nil },
            set: { newValue in
                if !newValue {
                    pendingDeleteTarget = nil
                }
            }
        )) {
            Button(L10n.cancel, role: .cancel) {
                pendingDeleteTarget = nil
            }
            Button(L10n.tr("Remove", zhHans: "移除", zhHant: "移除"), role: .destructive) {
                if let target = pendingDeleteTarget {
                    handleDelete(at: target)
                }
                pendingDeleteTarget = nil
                editingTarget = nil
            }
        } message: {
            Text(L10n.tr("This action cannot be undone.", zhHans: "移除后不可恢复。", zhHant: "移除後無法復原。"))
        }
    }

    private var boardContainerSurface: some View {
        let shape = RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous)
        return shape
            .fill(boardSurfaceColor)
    }

    private var undoToast: some View {
        IOSNativeToastView(
            L10n.taskDeleted,
            actionTitle: L10n.undo,
            isPadLayout: isPadLayout
        ) {
            if let deletedCellSnapshot {
                restoreDeletedCell(deletedCellSnapshot)
            }
        }
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
        let editingCell = viewModel.editingCell(row: target.row, col: target.col) ?? viewModel.cells[target.row][target.col]
        return EditTaskSheet(
            text: editingCell.storedTaskText,
            isForcedTask: editingCell.isForced,
            residentWeekdays: editingCell.residentWeekdays,
            isOneTimeTask: editingCell.isOneTimeTask,
            startVisibleAt: editingCell.startVisibleAt,
            endVisibleAt: editingCell.endVisibleAt,
            startReminderEnabled: editingCell.startReminderEnabled,
            startReminderOffsetMinutes: editingCell.startReminderOffsetMinutes,
            isCompletedTask: editingCell.isCompleted,
            estimatedDurationMinutes: viewModel.remainingTaskCountdownMinutes(row: target.row, col: target.col),
            autoFocusTaskField: true,
            onSave: { newText, isForcedTask, residentWeekdays, isOneTimeTask, estimatedDurationMinutes, startVisibleAt, endVisibleAt, startReminderEnabled, startReminderOffsetMinutes in
                let scheduleNotice = residentVisibilityNotice(
                    text: newText,
                    residentWeekdays: residentWeekdays,
                    isOneTimeTask: isOneTimeTask
                )
                viewModel.updateTask(
                    row: target.row,
                    col: target.col,
                    text: newText,
                    isForced: isForcedTask,
                    residentWeekdays: residentWeekdays,
                    isOneTimeTask: isOneTimeTask,
                    estimatedDurationMinutes: estimatedDurationMinutes,
                    startVisibleAt: startVisibleAt,
                    endVisibleAt: endVisibleAt,
                    startReminderEnabled: startReminderEnabled,
                    startReminderOffsetMinutes: startReminderOffsetMinutes
                )
                editingTarget = nil
                residentScheduleNotice = scheduleNotice
            },
            onDelete: {
                requestDelete(at: target)
            },
            onCancel: { editingTarget = nil }
        )
        .id(editSheetSessionID)
    }

    private func taskActionsOverlay(for target: EditingTarget) -> some View {
        let cell = viewModel.cells[target.row][target.col]
        return TaskActionsOverlayView(
            showsHideAction: cell.isCompleted,
            hideActionTitle: cell.isTaskHidden ? L10n.showTask : L10n.hideTask,
            isPadLayout: isPadLayout,
            onDismiss: dismissActionMenu,
            onEdit: {
                presentEditor(for: target)
            },
            onDelete: {
                pendingDeleteTarget = target
            },
            onToggleHidden: {
                withAnimation(.easeInOut(duration: 0.45)) {
                    viewModel.toggleTaskHidden(row: target.row, col: target.col)
                }
            }
        )
    }

    private func draggedCellOverlay(for dragState: DragState, cellSize: CGFloat) -> some View {
        let sourceCell = viewModel.cells[dragState.source.row][dragState.source.col]
        let startCenter = cellCenter(for: dragState.source, cellSize: cellSize)

        return BingoCellView(
            cell: sourceCell,
            currentTime: currentTime,
            isScheduledInactive: !viewModel.isTaskCurrentlyTappable(
                row: dragState.source.row,
                col: dragState.source.col,
                referenceDate: currentTime
            ) && !sourceCell.isEmpty,
            debugIdentifier: "drag-overlay-\(dragState.source.row)-\(dragState.source.col)",
            isInBingoLine: viewModel.isInCompletedLine(row: dragState.source.row, col: dragState.source.col),
            isLocked: false,
            cellSize: cellSize,
            isFirstCell: false,
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
        .position(
            x: startCenter.x + dragState.translation.width,
            y: startCenter.y + dragState.translation.height
        )
        .allowsHitTesting(false)
    }

    private func handleDelete(at target: EditingTarget) {
        dismissActionMenu()
        _ = viewModel.deleteCell(row: target.row, col: target.col)
    }

    private func requestDelete(at target: EditingTarget) {
        dismissActionMenu()
        pendingDeleteTarget = target
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
        setActionTargetWithoutSystemAnimation(nil)
    }

    private func setActionTargetWithoutSystemAnimation(_ target: EditingTarget?) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            actionTarget = target
        }
    }

    private func presentEditor(for target: EditingTarget) {
        editSheetSessionID = UUID()
        editingTarget = target
    }

    private var isGestureDebugEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugTileGestures")
#else
        false
#endif
    }

    private func debugGesture(_ message: String) {
#if DEBUG
        guard isGestureDebugEnabled else { return }
        print("[TileGestureDebug][Board] \(message)")
#else
        _ = message
#endif
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

    private func residentVisibilityNotice(
        text: String,
        residentWeekdays: Set<Int>,
        isOneTimeTask: Bool,
        referenceDate: Date = .now
    ) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isOneTimeTask, !residentWeekdays.isEmpty else { return nil }

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

private struct TaskActionsOverlayView: View {
    let showsHideAction: Bool
    let hideActionTitle: String
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleHidden: () -> Void
    @State private var isVisible = false
    @State private var isClosing = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(isVisible ? 0.42 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        close()
                    }

                VStack(spacing: 12) {
                    actionButton(
                        title: L10n.editTask,
                        color: NeumorphicColors.text,
                        action: {
                            close(then: onEdit)
                        }
                    )

                    actionButton(
                        title: L10n.deleteTask,
                        color: Color.red.opacity(0.84),
                        action: {
                            close(then: onDelete)
                        }
                    )

                    if showsHideAction {
                        actionButton(
                            title: hideActionTitle,
                            color: NeumorphicColors.text,
                            action: {
                                close(then: onToggleHidden)
                            }
                        )
                    }
                }
                .frame(width: min(max(proxy.size.width - 40, 0), isPadLayout ? 460 : 353))
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 14) + 12)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.16)) {
                isVisible = true
            }
        }
    }

    private func actionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NeumorphicColors.background)
                )
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }

    private func close(then action: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeIn(duration: 0.14)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            onDismiss()
            action?()
        }
    }
}
