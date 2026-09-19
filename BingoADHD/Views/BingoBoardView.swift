import SwiftUI

struct BingoBoardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct EditingTarget: Identifiable, Equatable {
        let row: Int
        let col: Int
        let cellID: UUID?

        init(row: Int, col: Int, cellID: UUID? = nil) {
            self.row = row
            self.col = col
            self.cellID = cellID
        }

        var id: String {
            "\(row)-\(col)"
        }

        static func == (lhs: EditingTarget, rhs: EditingTarget) -> Bool {
            lhs.row == rhs.row && lhs.col == rhs.col
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
    var onTaskPresentationChange: ((Bool) -> Void)? = nil
    var onCellReorderActiveChanged: ((Bool) -> Void)? = nil
    @State private var editingTarget: EditingTarget?
    @State private var actionTarget: EditingTarget?
    @State private var countdownTarget: EditingTarget?
    @State private var dragState: DragState?
    @State private var residentScheduleNotice: String?
    @State private var deletedCellSnapshot: DeletedCellSnapshot?
    @State private var undoDismissWorkItem: DispatchWorkItem?
    @State private var pendingDeleteTarget: EditingTarget?
    @State private var pendingPadEditorTargetAfterActions: EditingTarget?
    @State private var taskMutationError: String?
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

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
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
                                    let target = EditingTarget(
                                        row: row,
                                        col: col,
                                        cellID: viewModel.cells[row][col].id
                                    )
                                    let isDragSource = dragState?.source == target
                                    let isDropTarget = dragState?.destination == target && dragState?.source != target
                                    let isScheduledInactive = !viewModel.isTaskCurrentlyTappable(
                                        row: row,
                                        col: col,
                                        referenceDate: currentTime
                                    ) && !viewModel.cells[row][col].isCompleted
                                    let scheduleStatusText = scheduleStatusTextForCell(
                                        row: row,
                                        col: col,
                                        isScheduledInactive: isScheduledInactive
                                    )

                                    ZStack {
                                        taskCompletionEffect(
                                            for: target,
                                            cellSize: cellSize
                                        )
                                        .zIndex(0)

                                        BingoCellView(
                                        cell: viewModel.cells[row][col],
                                        currentTime: currentTime,
                                        isScheduledInactive: isScheduledInactive,
                                        scheduleStatusText: scheduleStatusText,
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
                                            if let currentCell = currentVisibleCell(for: target),
                                                !currentCell.isEmpty &&
                                                !viewModel.isLocked(row: row, col: col) &&
                                                viewModel.canToggleComplete(row: row, col: col, referenceDate: currentTime) {
                                                // The tapped cell owns its local 70% → spring-back
                                                // feedback. Do not wrap the entire board mutation in
                                                // an animation transaction: it causes unrelated cells
                                                // and UIKit PAG views to be re-evaluated mid-playback.
                                                viewModel.toggleComplete(row: row, col: col, referenceDate: currentTime)
                                                onCellCompletionToggled?()
                                            }
                                        },
                                        onLongPressRelease: {
                                            guard let currentCell = currentVisibleCell(for: target) else {
                                                debugGesture("long press ignored stale target at \(row)-\(col)")
                                                return
                                            }
                                            guard !viewModel.isLocked(row: row, col: col) else {
                                                debugGesture("long press blocked by lock at \(row)-\(col)")
                                                return
                                            }
                                            // Fix 2: use hasStoredTask (checks storedTaskText) rather
                                            // than isEmpty (checks projected text). Resident tasks
                                            // on non-active days have text="" but storedTaskText!="".
                                            if currentCell.hasStoredTask {
                                                debugGesture("long press open action menu at \(row)-\(col)")
                                                DispatchQueue.main.async {
                                                    guard currentVisibleCell(for: target) != nil else {
                                                        debugGesture("long press ignored stale action menu at \(row)-\(col)")
                                                        return
                                                    }
                                                    setActionTargetWithoutSystemAnimation(target)
                                                }
                                            } else {
                                                debugGesture("long press open editor at \(row)-\(col)")
                                                presentEditor(for: target)
                                            }
                                        },
                                        onDragStart: {
                                            guard !viewModel.isLocked(row: row, col: col) else { return }
                                            guard let currentCell = currentVisibleCell(for: target),
                                                  !currentCell.isEmpty else { return }
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
                                        .zIndex(1)
                                    }
                                    .frame(width: cellSize, height: cellSize)
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
            // The rounded shape belongs to the board surface only.  Do not clip the content
            // layer here: a top-row completion effect is intentionally larger than its card and
            // needs to burst above the board edge.
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: editingTarget != nil || actionTarget != nil || countdownTarget != nil || pendingPadEditorTargetAfterActions != nil, initial: true) { _, presented in
            onTaskPresentationChange?(presented)
        }
        .onDisappear {
            if dragState != nil {
                dragState = nil
                onCellReorderActiveChanged?(false)
            }
        }
        .onChange(of: viewModel.taskCompletionMotion?.id) { _, motionID in
            guard reduceMotion, let motionID else { return }
            // The top-level presenter owns Bingo's reduced-motion fallback. Keeping the
            // Bingo state alive until it responds prevents the board layer from cancelling
            // its sound/haptic task before it begins.
            if viewModel.taskCompletionMotion?.kind == .singleTask {
#if canImport(libpag)
                PAGRewardSoundPlayer.shared.play(resourceName: "complete_once", fileExtension: "mp3")
#endif
                AppHaptics.completion()
                viewModel.dismissTaskCompletionMotion(id: motionID)
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
        .adaptivePadBottomHalfSheet(
            item: $editingTarget,
            usePadPresentation: isPadDevice,
            backgroundColor: Color(hex: "202020"),
            contentMaxWidth: 720,
            padHeightFraction: 0.7
        ) { target in
            editTaskSheet(for: target)
                .presentationDetents([.fraction(isPadLayout ? 0.66 : 0.74), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(isPadDevice ? Color.clear : Color(hex: "202020"))
        }
        .fullScreenCover(item: $actionTarget, onDismiss: {
            guard isPadDevice, let target = pendingPadEditorTargetAfterActions else { return }
            pendingPadEditorTargetAfterActions = nil
            presentEditor(for: target)
        }) { target in
            taskActionsOverlay(for: target)
                .background(Color.clear)
                .presentationBackground(.clear)
        }
        .sheet(item: $countdownTarget) { target in
            taskCountdownSheet(for: target)
                .presentationDetents([.height(taskCountdownSheetHeight(for: target))])
                .presentationDragIndicator(.visible)
                .presentationBackground(NeumorphicColors.background)
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
        .alert(
            L10n.tr("Could not remove task", zhHans: "无法移除任务", zhHant: "無法移除任務"),
            isPresented: Binding(
                get: { taskMutationError != nil },
                set: { isPresented in
                    if !isPresented {
                        taskMutationError = nil
                    }
                }
            )
        ) {
            Button(L10n.ok, role: .cancel) {
                taskMutationError = nil
            }
        } message: {
            Text(taskMutationError ?? "")
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

    @ViewBuilder
    private func editTaskSheet(for target: EditingTarget) -> some View {
        if let editingCell = currentEditingCell(for: target) {
            EditTaskSheet(
            text: editingCell.storedTaskText,
            isForcedTask: editingCell.isForced,
            residentWeekdays: editingCell.residentWeekdays,
            isOneTimeTask: editingCell.isOneTimeTask,
            recurrenceRule: editingCell.recurrenceRule,
            startVisibleAt: editingCell.startVisibleAt,
            endVisibleAt: editingCell.endVisibleAt,
            startReminderEnabled: editingCell.startReminderEnabled,
            startReminderOffsetMinutes: editingCell.startReminderOffsetMinutes,
                isCompletedTask: editingCell.isCompleted,
                estimatedDurationMinutes: viewModel.remainingTaskCountdownMinutes(row: target.row, col: target.col),
                usesClearPresentationBackground: isPadDevice,
                completionHistoryCountProvider: viewModel.completionHistoryCount(for:),
                diagnosticCellID: editingCell.id,
                diagnosticSource: "home_cell_editor",
                onSave: { newText, isForcedTask, residentWeekdays, isOneTimeTask, recurrenceRule, estimatedDurationMinutes, startVisibleAt, endVisibleAt, startReminderEnabled, startReminderOffsetMinutes in
                guard currentVisibleCell(for: target) != nil else {
                    return false
                }
                let scheduleNotice = residentVisibilityNotice(
                    text: newText,
                    residentWeekdays: residentWeekdays,
                    isOneTimeTask: isOneTimeTask,
                    recurrenceRule: recurrenceRule
                )
                let didSave = viewModel.updateTask(
                    row: target.row,
                    col: target.col,
                    text: newText,
                    isForced: isForcedTask,
                    residentWeekdays: residentWeekdays,
                    isOneTimeTask: isOneTimeTask,
                    recurrenceRule: recurrenceRule,
                    estimatedDurationMinutes: estimatedDurationMinutes,
                    startVisibleAt: startVisibleAt,
                    endVisibleAt: endVisibleAt,
                    startReminderEnabled: startReminderEnabled,
                    startReminderOffsetMinutes: startReminderOffsetMinutes,
                    editSource: "home_cell_editor"
                )
                guard didSave else { return false }
                editingTarget = nil
                residentScheduleNotice = scheduleNotice
                return true
            },
            onDelete: {
                requestDelete(at: target)
            },
            onCancel: { editingTarget = nil }
            )
            .id(editSheetSessionID)
        } else {
            Color.clear
                .onAppear {
                    editingTarget = nil
                }
        }
    }

    @ViewBuilder
    private func taskActionsOverlay(for target: EditingTarget) -> some View {
        if let cell = currentVisibleCell(for: target) {
            TaskActionsOverlayView(
            showsHideAction: cell.isCompleted,
            hideActionTitle: cell.isTaskHidden ? L10n.showTask : L10n.hideTask,
            showsCountdownAction: viewModel.canSetTaskCountdown(row: target.row, col: target.col, referenceDate: currentTime),
            isPadLayout: isPadLayout,
            onDismiss: dismissActionMenu,
            onEdit: {
                if isPadDevice {
                    pendingPadEditorTargetAfterActions = target
                } else {
                    presentEditor(for: target)
                }
            },
            onSetCountdown: {
                guard currentVisibleCell(for: target) != nil else {
                    dismissActionMenu()
                    return
                }
                countdownTarget = target
            },
            onDelete: {
                guard currentVisibleCell(for: target) != nil else {
                    dismissActionMenu()
                    return
                }
                pendingDeleteTarget = target
            },
            onToggleHidden: {
                guard currentVisibleCell(for: target) != nil else {
                    dismissActionMenu()
                    return
                }
                withAnimation(.easeInOut(duration: 0.45)) {
                    viewModel.toggleTaskHidden(row: target.row, col: target.col)
                }
            }
            )
        } else {
            Color.clear
                .onAppear {
                    dismissActionMenu()
                }
        }
    }

    private func taskCountdownSheet(for target: EditingTarget) -> some View {
        let referenceDate = Date()
        let editingCell = viewModel.editingCell(row: target.row, col: target.col)
        let remainingMinutes = viewModel.remainingTaskCountdownMinutes(
            row: target.row,
            col: target.col,
            referenceDate: referenceDate
        )
        let isPaused = viewModel.isTaskCountdownPaused(row: target.row, col: target.col)
        return TaskCountdownSheetView(
            initialMinutes: remainingMinutes,
            hasExistingCountdown: viewModel.hasTaskCountdown(row: target.row, col: target.col),
            countdownEndsAt: editingCell?.countdownEndsAt,
            pausedRemainingSeconds: editingCell?.countdownPausedRemainingSeconds,
            isCountdownPaused: isPaused,
            canPauseOrResumeCountdown: viewModel.canPauseOrResumeTaskCountdown(
                row: target.row,
                col: target.col,
                referenceDate: referenceDate
            ),
            isPadLayout: isPadLayout,
            onSave: { minutes in
                guard currentVisibleCell(for: target) != nil else {
                    countdownTarget = nil
                    return
                }
                _ = viewModel.setTaskCountdown(row: target.row, col: target.col, minutes: minutes)
                countdownTarget = nil
            },
            onPauseToggle: {
                guard currentVisibleCell(for: target) != nil else {
                    countdownTarget = nil
                    return
                }
                if isPaused {
                    _ = viewModel.resumeTaskCountdown(row: target.row, col: target.col)
                } else {
                    _ = viewModel.pauseTaskCountdown(row: target.row, col: target.col)
                }
                countdownTarget = nil
            },
            onCancelCountdown: {
                guard currentVisibleCell(for: target) != nil else {
                    countdownTarget = nil
                    return
                }
                _ = viewModel.cancelTaskCountdown(row: target.row, col: target.col)
                countdownTarget = nil
            }
        )
    }

    private func taskCountdownSheetHeight(for target: EditingTarget) -> CGFloat {
        let hasExistingCountdown = viewModel.hasTaskCountdown(row: target.row, col: target.col)
        switch (isPadLayout, hasExistingCountdown) {
        case (true, true):
            return 365
        case (true, false):
            return 340
        case (false, true):
            return 335
        case (false, false):
            return 315
        }
    }

    @ViewBuilder
    private func draggedCellOverlay(for dragState: DragState, cellSize: CGFloat) -> some View {
        if let sourceCell = currentVisibleCell(for: dragState.source) {
            let startCenter = cellCenter(for: dragState.source, cellSize: cellSize)
            let isScheduledInactive = !viewModel.isTaskCurrentlyTappable(
                row: dragState.source.row,
                col: dragState.source.col,
                referenceDate: currentTime
            ) && !sourceCell.isCompleted

            BingoCellView(
                cell: sourceCell,
                currentTime: currentTime,
                isScheduledInactive: isScheduledInactive,
                scheduleStatusText: scheduleStatusTextForCell(
                    row: dragState.source.row,
                    col: dragState.source.col,
                    isScheduledInactive: isScheduledInactive
                ),
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
        } else {
            Color.clear
                .allowsHitTesting(false)
        }
    }

    private func handleDelete(at target: EditingTarget) {
        guard currentVisibleCell(for: target) != nil else {
            dismissActionMenu()
            return
        }
        dismissActionMenu()
        guard viewModel.deleteCell(row: target.row, col: target.col) != nil else {
            taskMutationError = L10n.tr(
                "Could not save task completion history. Please try again.",
                zhHans: "任务完成历史保存失败，请重试。",
                zhHant: "任務完成歷史儲存失敗，請重試。"
            )
            return
        }
    }

    private func requestDelete(at target: EditingTarget) {
        guard currentVisibleCell(for: target) != nil else {
            dismissActionMenu()
            return
        }
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
        guard currentVisibleCell(for: target) != nil else { return }
        editSheetSessionID = UUID()
        editingTarget = target
    }

    private func currentVisibleCell(for target: EditingTarget) -> BingoCell? {
        viewModel.visibleCell(row: target.row, col: target.col, matching: target.cellID)
    }

    private func currentEditingCell(for target: EditingTarget) -> BingoCell? {
        guard let visibleCell = currentVisibleCell(for: target),
              let editingCell = viewModel.editingCell(row: target.row, col: target.col),
              visibleCell.id == editingCell.id else {
            return nil
        }
        return editingCell
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

    @ViewBuilder
    private func taskCompletionEffect(
        for target: EditingTarget,
        cellSize: CGFloat
    ) -> some View {
        if !reduceMotion, let motion = viewModel.taskCompletionMotion {
            let coordinate = BingoViewModel.TaskCompletionMotion.CellCoordinate(
                row: target.row,
                col: target.col
            )
            let isSingleTaskTarget = motion.kind == .singleTask && motion.triggeringCell == coordinate
            let isBingoTarget = motion.kind == .bingo && motion.bingoCells.contains(coordinate)
            // Both effects are authored as large visual canvases around one card.  Keeping the
            // canvas local to each winning cell lets Bingo effects overlap naturally while the
            // task card itself remains at its normal size above the animation.
            let effectCanvasScale: CGFloat = 2.8

            if isSingleTaskTarget || isBingoTarget {
                PAGCompletionView(
                    resourceName: isSingleTaskTarget
                        ? "complete_once_bmp"
                        : "complete_bingo_background_bmp",
                    // A line Bingo owns its audio at the later top-level Bingo reveal. The card
                    // background effect must stay silent so it never plays the one-task sound
                    // before the dedicated complete_bingo.mp3 track begins.
                    playsSound: isSingleTaskTarget,
                    soundResourceName: isSingleTaskTarget ? "complete_once" : nil,
                    soundFileExtension: "mp3",
                    playsHaptic: isSingleTaskTarget,
                    // A 4×4 line starts four of these compact card canvases at once. Keeping
                    // their frames in memory trades a small, bounded amount of memory during
                    // the celebration for deterministic first-run playback.
                    cacheAllFrames: true,
                    renderScale: 1,
                    maxFrameRate: 60,
                    playbackRate: 1,
                    onFinished: {
                        guard isSingleTaskTarget else { return }
                        viewModel.dismissTaskCompletionMotion(id: motion.id)
                    }
                )
                .id("\(motion.id.uuidString)-\(target.row)-\(target.col)")
                // The card remains cellSize. The one-task effect has a deliberately larger
                // canvas so its stars and arcs emerge around the card rather than being hidden
                // by the card's opaque center.
                .frame(width: cellSize * effectCanvasScale, height: cellSize * effectCanvasScale)
                .allowsHitTesting(false)
            }
        }
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
        recurrenceRule: TaskRecurrenceRule? = nil,
        referenceDate: Date = .now
    ) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isOneTimeTask else { return nil }

        if let recurrenceRule {
            let defaultDate = Date()
            let normalizedRule = recurrenceRule.normalized(
                defaultWeekday: Calendar.current.component(.weekday, from: defaultDate),
                defaultMonthDay: Calendar.current.component(.day, from: defaultDate),
                defaultAnchorDate: defaultDate
            )
            guard normalizedRule.kind != .daily,
                  normalizedRule.kind != .none,
                  !normalizedRule.isActive(on: referenceDate) else {
                return nil
            }
            return L10n.taskScheduledMessage(recurrenceNoticeLabel(for: normalizedRule))
        }

        guard !residentWeekdays.isEmpty else { return nil }

        let today = Calendar.current.component(.weekday, from: referenceDate)
        guard !residentWeekdays.contains(today) else { return nil }

        let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
        let labels = orderedWeekdays
            .filter { residentWeekdays.contains($0) }
            .map(weekdayLabel(for:))

        guard !labels.isEmpty else { return nil }
        return L10n.taskScheduledMessage(labels.joined(separator: AppLanguage.current == .english ? ", " : "、"))
    }

    private func recurrenceNoticeLabel(for rule: TaskRecurrenceRule) -> String {
        switch rule.kind {
        case .weekly:
            let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
            let labels = orderedWeekdays
                .filter { rule.weekdays.contains($0) }
                .map(weekdayLabel(for:))
            return labels.joined(separator: AppLanguage.current == .english ? ", " : "、")
        case .monthlyDay:
            let day = rule.monthDay ?? Calendar.current.component(.day, from: Date())
            return L10n.tr(
                "day \(day) each month",
                zhHans: "每月第 \(day) 天",
                zhHant: "每月第 \(day) 天",
                ja: "毎月\(day)日"
            )
        case .everyNDays:
            return L10n.tr(
                "every \(rule.interval) days",
                zhHans: "每隔 \(rule.interval) 天",
                zhHant: "每隔 \(rule.interval) 天",
                ja: "\(rule.interval)日ごと"
            )
        case .none, .daily:
            return ""
        }
    }

    private func scheduleStatusTextForCell(row: Int, col: Int, isScheduledInactive: Bool) -> String? {
        guard let sourceCell = viewModel.editingCell(row: row, col: col),
              sourceCell.hasStoredTask else {
            return nil
        }

        if isScheduledInactive {
            if sourceCell.isEndVisibilityReached(on: currentTime) {
                return L10n.tr("Ended", zhHans: "已结束", zhHant: "已結束", ja: "終了")
            }

            if sourceCell.isVisibilityWindowInactive(on: currentTime) {
                return startStatusText(for: sourceCell.occurrenceStartVisibleAt(on: currentTime))
            }

            if let nextActiveDate = sourceCell.nextResidentActiveDate(onOrAfter: currentTime),
               !Calendar.current.isDate(nextActiveDate, inSameDayAs: currentTime) {
                return L10n.tr(
                    "Next \(shortDateLabel(nextActiveDate))",
                    zhHans: "下次 \(shortDateLabel(nextActiveDate))",
                    zhHant: "下次 \(shortDateLabel(nextActiveDate))",
                    ja: "次回 \(shortDateLabel(nextActiveDate))"
                )
            }
            return nil
        }

        guard let rule = sourceCell.effectiveRecurrenceRule,
              rule.kind != .none else {
            return nil
        }
        return activeRecurrenceLabel(for: rule)
    }

    private func startStatusText(for startDate: Date?) -> String? {
        guard let startDate else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(startDate, inSameDayAs: currentTime) {
            return L10n.tr(
                "\(timeLabel(startDate)) start",
                zhHans: "\(timeLabel(startDate)) 开始",
                zhHant: "\(timeLabel(startDate)) 開始",
                ja: "\(timeLabel(startDate)) 開始"
            )
        }
        return L10n.tr(
            "\(shortDateLabel(startDate)) start",
            zhHans: "\(shortDateLabel(startDate)) 开始",
            zhHant: "\(shortDateLabel(startDate)) 開始",
            ja: "\(shortDateLabel(startDate)) 開始"
        )
    }

    private func activeRecurrenceLabel(for rule: TaskRecurrenceRule) -> String? {
        switch rule.kind {
        case .daily:
            return nil
        case .weekly:
            let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
            let labels = orderedWeekdays
                .filter { rule.weekdays.contains($0) }
                .map(weekdayLabel(for:))
            guard !labels.isEmpty else { return nil }
            return L10n.tr(
                "Every \(labels.joined(separator: ", "))",
                zhHans: "每周\(labels.joined(separator: "、"))",
                zhHant: "每週\(labels.joined(separator: "、"))",
                ja: "毎週\(labels.joined(separator: "・"))"
            )
        case .monthlyDay:
            let day = rule.monthDay ?? Calendar.current.component(.day, from: currentTime)
            return L10n.tr(
                "Monthly on day \(day)",
                zhHans: "每月 \(day) 日",
                zhHant: "每月 \(day) 日",
                ja: "毎月\(day)日"
            )
        case .everyNDays:
            return L10n.tr(
                "Every \(rule.interval) days",
                zhHans: "每隔 \(rule.interval) 天",
                zhHant: "每隔 \(rule.interval) 天",
                ja: "\(rule.interval)日ごと"
            )
        case .none:
            return nil
        }
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.calendar = Calendar.current
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.calendar = Calendar.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
    let showsCountdownAction: Bool
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onSetCountdown: () -> Void
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

                    if showsCountdownAction {
                        actionButton(
                            title: L10n.tr("Set countdown", zhHans: "设置倒计时", zhHant: "設定倒計時", ja: "カウントダウンを設定"),
                            color: NeumorphicColors.text,
                            action: {
                                close(then: onSetCountdown)
                            }
                        )
                    }

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

private struct TaskCountdownSheetView: View {
    private enum SheetMode {
        case manage
        case edit
    }

    private enum CountdownConfirmation: Identifiable, Equatable {
        case pause
        case cancel

        var id: String {
            switch self {
            case .pause:
                return "pause"
            case .cancel:
                return "cancel"
            }
        }
    }

    let initialMinutes: Int?
    let hasExistingCountdown: Bool
    let countdownEndsAt: Date?
    let pausedRemainingSeconds: Int?
    let isCountdownPaused: Bool
    let canPauseOrResumeCountdown: Bool
    let isPadLayout: Bool
    let onSave: (Int) -> Void
    let onPauseToggle: () -> Void
    let onCancelCountdown: () -> Void

    @State private var selectedPresetMinutes: Int?
    @State private var customMinutesText: String
    @State private var sheetMode: SheetMode
    @State private var pendingConfirmation: CountdownConfirmation?
    @FocusState private var isCustomFieldFocused: Bool

    private let presetMinutes = [15, 30, 45, 60]

    init(
        initialMinutes: Int?,
        hasExistingCountdown: Bool,
        countdownEndsAt: Date?,
        pausedRemainingSeconds: Int?,
        isCountdownPaused: Bool,
        canPauseOrResumeCountdown: Bool,
        isPadLayout: Bool,
        onSave: @escaping (Int) -> Void,
        onPauseToggle: @escaping () -> Void,
        onCancelCountdown: @escaping () -> Void
    ) {
        self.initialMinutes = initialMinutes
        self.hasExistingCountdown = hasExistingCountdown
        self.countdownEndsAt = countdownEndsAt
        self.pausedRemainingSeconds = pausedRemainingSeconds
        self.isCountdownPaused = isCountdownPaused
        self.canPauseOrResumeCountdown = canPauseOrResumeCountdown
        self.isPadLayout = isPadLayout
        self.onSave = onSave
        self.onPauseToggle = onPauseToggle
        self.onCancelCountdown = onCancelCountdown

        let presetCandidates = [15, 30, 45, 60]
        let normalizedInitialMinutes = initialMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }
        if let normalizedInitialMinutes, presetCandidates.contains(normalizedInitialMinutes) {
            _selectedPresetMinutes = State(initialValue: normalizedInitialMinutes)
            _customMinutesText = State(initialValue: "")
        } else if let normalizedInitialMinutes {
            _selectedPresetMinutes = State(initialValue: nil)
            _customMinutesText = State(initialValue: String(normalizedInitialMinutes))
        } else {
            _selectedPresetMinutes = State(initialValue: 15)
            _customMinutesText = State(initialValue: "")
        }
        _sheetMode = State(initialValue: hasExistingCountdown ? .manage : .edit)
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: sheetMode == .manage ? 16 : 14) {
                if sheetMode == .manage, hasExistingCountdown {
                    manageContent
                } else {
                    header
                    editContent
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: isPadLayout ? 460 : .infinity)
        .frame(maxWidth: .infinity)
        .padding(.top, sheetMode == .manage ? 28 : 48)
        .padding(.bottom, 12)
        .preferredColorScheme(.light)
        .alert(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingConfirmation = nil
                    }
                }
            ),
            presenting: pendingConfirmation
        ) { confirmation in
            Button(
                confirmationConfirmTitle(for: confirmation),
                role: confirmation == .cancel ? .destructive : nil
            ) {
                switch confirmation {
                case .pause:
                    onPauseToggle()
                case .cancel:
                    onCancelCountdown()
                }
                pendingConfirmation = nil
            }
            Button(L10n.tr("Cancel", zhHans: "取消", zhHant: "取消", ja: "キャンセル"), role: .cancel) {
                pendingConfirmation = nil
            }
        } message: { confirmation in
            Text(confirmationMessage(for: confirmation))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            saveButton
        }
    }

    private var manageContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                VStack(spacing: 8) {
                    Text(formattedCountdownText(referenceDate: context.date))
                        .font(.appSystem(size: scaled(48, pad: 58), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .monospacedDigit()

                    Text(countdownStatusText(referenceDate: context.date))
                        .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.62))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, scaled(18, pad: 22))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.68))
                )
            }

            HStack(spacing: 14) {
                largeCountdownActionButton(
                    systemName: isCountdownPaused ? "play.fill" : "pause.fill",
                    accessibilityLabel: isCountdownPaused
                        ? L10n.tr("Resume countdown", zhHans: "继续倒计时", zhHant: "繼續倒計時", ja: "カウントダウンを再開")
                        : L10n.tr("Pause countdown", zhHans: "暂停倒计时", zhHant: "暫停倒計時", ja: "カウントダウンを一時停止"),
                    foregroundColor: NeumorphicColors.text.opacity(canPauseOrResumeCountdown ? 0.86 : 0.34),
                    backgroundColor: Color.white.opacity(canPauseOrResumeCountdown ? 0.76 : 0.46),
                    isEnabled: canPauseOrResumeCountdown,
                    action: {
                        if isCountdownPaused {
                            onPauseToggle()
                        } else {
                            pendingConfirmation = .pause
                        }
                    }
                )

                largeCountdownActionButton(
                    systemName: "xmark",
                    accessibilityLabel: L10n.tr("Cancel countdown", zhHans: "取消倒计时", zhHant: "取消倒計時", ja: "カウントダウンをキャンセル"),
                    foregroundColor: Color.red.opacity(0.84),
                    backgroundColor: Color.red.opacity(0.12),
                    isEnabled: true,
                    action: {
                        pendingConfirmation = .cancel
                    }
                )
            }

            resetButton
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var editContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("Set countdown", zhHans: "设置倒计时", zhHant: "設定倒計時", ja: "カウントダウンを設定"))
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Text(L10n.tr(
                "Countdown starts when the task becomes clickable.",
                zhHans: "倒计时会在任务到开始时间、可点击时开始。",
                zhHant: "倒計時會在任務到開始時間、可點擊時開始。",
                ja: "タスクが開始時刻になり、タップ可能になると開始します。"
            ))
            .font(.appSystem(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.62))

            HStack(spacing: 8) {
                ForEach(presetMinutes, id: \.self) { minutes in
                    presetButton(minutes)
                }
            }

            customInput
        }
    }

    private var customInput: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("Custom", zhHans: "自定义", zhHant: "自訂", ja: "カスタム"))
                .font(.appSystem(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Spacer(minLength: 0)

            TextField(
                L10n.tr("Minutes", zhHans: "分钟", zhHant: "分鐘", ja: "分"),
                text: $customMinutesText
            )
            .keyboardType(.numberPad)
            .submitLabel(.done)
            .focused($isCustomFieldFocused)
            .font(.appSystem(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
            .foregroundColor(NeumorphicColors.text)
            .multilineTextAlignment(.trailing)
            .frame(width: scaled(92, pad: 116))
            .onTapGesture {
                selectedPresetMinutes = nil
            }
            .onChange(of: customMinutesText) { _, newValue in
                let filteredText = String(newValue.filter(\.isNumber))
                if filteredText != newValue {
                    customMinutesText = filteredText
                }
                if !filteredText.isEmpty {
                    selectedPresetMinutes = nil
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: scaled(50, pad: 56))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NeumorphicColors.text.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var saveButton: some View {
        Button {
            guard let normalizedMinutes else { return }
            isCustomFieldFocused = false
            onSave(normalizedMinutes)
        } label: {
            Text(L10n.tr("Start", zhHans: "开始", zhHant: "開始", ja: "開始"))
                .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                .foregroundColor(normalizedMinutes == nil ? NeumorphicColors.text.opacity(0.34) : AppTheme.concise.color)
                .frame(height: scaled(38, pad: 44))
                .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .disabled(normalizedMinutes == nil)
    }

    private var resetButton: some View {
        Button {
            isCustomFieldFocused = false
            withAnimation(.easeInOut(duration: 0.18)) {
                sheetMode = .edit
            }
        } label: {
            Text(L10n.tr("Reset", zhHans: "重新设定", zhHant: "重新設定", ja: "再設定"))
                .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.concise.color)
                .frame(height: scaled(38, pad: 44))
                .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
    }

    private func largeCountdownActionButton(
        systemName: String,
        accessibilityLabel: String,
        foregroundColor: Color,
        backgroundColor: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            isCustomFieldFocused = false
            action()
        } label: {
            Image(systemName: systemName)
                .font(.appSystem(size: scaled(22, pad: 26), weight: .bold))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(58, pad: 66))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var normalizedMinutes: Int? {
        if let selectedPresetMinutes {
            return selectedPresetMinutes
        }
        guard let customMinutes = Int(customMinutesText), customMinutes > 0 else {
            return nil
        }
        return min(max(customMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }

    private var confirmationTitle: String {
        guard let pendingConfirmation else { return "" }
        switch pendingConfirmation {
        case .pause:
            return L10n.tr("Pause countdown?", zhHans: "暂停倒计时？", zhHant: "暫停倒計時？", ja: "カウントダウンを一時停止しますか？")
        case .cancel:
            return L10n.tr("Cancel countdown?", zhHans: "取消倒计时？", zhHant: "取消倒計時？", ja: "カウントダウンをキャンセルしますか？")
        }
    }

    private func confirmationMessage(for confirmation: CountdownConfirmation) -> String {
        switch confirmation {
        case .pause:
            return L10n.tr(
                "You can resume it later.",
                zhHans: "暂停后可以随时继续。",
                zhHant: "暫停後可以隨時繼續。",
                ja: "あとで再開できます。"
            )
        case .cancel:
            return L10n.tr(
                "The current countdown will be cleared.",
                zhHans: "当前倒计时会被清除。",
                zhHant: "目前倒計時會被清除。",
                ja: "現在のカウントダウンが削除されます。"
            )
        }
    }

    private func confirmationConfirmTitle(for confirmation: CountdownConfirmation) -> String {
        switch confirmation {
        case .pause:
            return L10n.tr("Pause", zhHans: "暂停", zhHant: "暫停", ja: "一時停止")
        case .cancel:
            return L10n.tr("Cancel countdown", zhHans: "取消倒计时", zhHant: "取消倒計時", ja: "キャンセル")
        }
    }

    private func formattedCountdownText(referenceDate: Date) -> String {
        let seconds = countdownRemainingSeconds(referenceDate: referenceDate)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func countdownStatusText(referenceDate: Date) -> String {
        if isCountdownPaused {
            return L10n.tr("Paused", zhHans: "已暂停", zhHant: "已暫停", ja: "一時停止中")
        }
        if countdownRemainingSeconds(referenceDate: referenceDate) <= 0 {
            return L10n.tr("Time is up", zhHans: "倒计时已结束", zhHant: "倒計時已結束", ja: "時間になりました")
        }
        return L10n.tr("Counting down", zhHans: "倒计时进行中", zhHant: "倒計時進行中", ja: "カウントダウン中")
    }

    private func countdownRemainingSeconds(referenceDate: Date) -> Int {
        if let pausedRemainingSeconds, pausedRemainingSeconds > 0 {
            return pausedRemainingSeconds
        }
        if let countdownEndsAt {
            return max(Int(ceil(countdownEndsAt.timeIntervalSince(referenceDate))), 0)
        }
        if let initialMinutes {
            return max(initialMinutes, 0) * 60
        }
        return 0
    }

    private func presetButton(_ minutes: Int) -> some View {
        Button {
            selectedPresetMinutes = minutes
            customMinutesText = ""
            isCustomFieldFocused = false
        } label: {
            Text("\(minutes)")
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(selectedPresetMinutes == minutes ? .white : NeumorphicColors.text.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: scaled(42, pad: 48))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selectedPresetMinutes == minutes ? AppTheme.concise.color : Color.white.opacity(0.78))
                )
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}
