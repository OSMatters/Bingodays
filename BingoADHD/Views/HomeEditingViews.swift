import SwiftUI

struct QuickEditView: View {
    @ObservedObject var viewModel: BingoViewModel
    @Binding private var limitedOfferState: LimitedOfferHomeState
    let onSaveSuccess: (String) -> Void
    let onBoardApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var library = MyTasksLibrary()
    @State private var taskHistoryRecords: [TaskHistoryRecord] = []
    @State private var lastTrackedLibrary = MyTasksLibrary()
    @State private var pendingTaskHistoryEdits: [UUID: MyTaskItem] = [:]
    @State private var completionHistoryCountLookup: (String) -> Int = { _ in 0 }
    @FocusState private var focusedField: FocusedMyTaskField?
    @State private var deleteConfirmationTarget: QuickEditDeleteTarget?
    @State private var localToastMessage: String?
    @State private var isLocalToastVisible = false
    @State private var hideLocalToastWorkItem: DispatchWorkItem?
    @State private var selectedTaskKeys: [String] = []
    @State private var supplementalPoolTasks: [String: MyTaskItem] = [:]
    @State private var previewSlots: [PreviewSlot] = []
    @State private var deselectedTaskDrafts: [String: QuickEditDeselectedTaskDraft] = [:]
    @State private var explicitlyEditedCellIDs: Set<UUID> = []
    @State private var previewDragSourceID: UUID?
    @State private var previewDropTargetID: UUID?
    @State private var initialSnapshot: QuickEditSnapshot?
    @State private var editingContext: QuickEditBoardContext?
    @State private var librarySession: QuickEditLibrarySession?
    @State private var isExitDiscardAlertPresented = false
    @State private var targetGridSize = 4
    @State private var pendingApplyPlan: QuickEditApplyPlan?
    @State private var isPremiumPaywallPresented = false
    @State private var premiumPaywallSource = "quick_edit"
    @State private var activeFilter: QuickEditFilterTab = .all
    @State private var newPoolTaskDestination: QuickEditFilterTab?
    @State private var isAddingGroupModalPresented = false
    @State private var newGroupNameDraft = ""
    @State private var groupActionTargetID: UUID?
    @State private var groupRenameTargetID: UUID?
    @State private var groupRenameDraft = ""
    @State private var pendingGroupDeleteFinalConfirmation: UUID?
    @State private var taskEditorDraft: QuickEditTaskEditorDraft?
    @State private var previewEditingTarget: QuickEditPreviewEditingTarget?
    @State private var poolEditingSlot: PreviewSlot?
    @State private var movingTaskKey: String?
    @State private var isTaskPoolHintVisible = true
    @State private var pendingGridSize: Int?

    typealias PreviewSlot = QuickEditPreviewSlot

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }
    
    private var activeTheme: AppTheme { .concise }
    private let quickEditBackgroundColor = Color(hex: "F4F4F4")
    private let quickEditBackgroundTint = Color.clear
    private var quickEditTaskFlatBackground: Color { Color(hex: "F4F4F4") }
    private var quickEditSelectedBadgeBackground: Color { Color(hex: "F4F4F4") }
    private var quickEditFieldStroke: Color { activeTheme.bingoSurfaceShadowColor.opacity(0.16) }
    private var quickEditPlaceholderColor: Color { NeumorphicColors.text.opacity(0.34) }
    private var previewEmptySlotFill: Color { Color(hex: "F4F4F4") }
    private var previewFilledSlotFill: Color { Color(hex: "E8D5C2") }
    private var previewEmptySlotStroke: Color { .clear }
    private var previewFilledSlotStroke: Color { .clear }
    private let quickEditPageHorizontalPadding: CGFloat = 20

    init(
        viewModel: BingoViewModel,
        limitedOfferState: Binding<LimitedOfferHomeState>,
        onSaveSuccess: @escaping (String) -> Void,
        onBoardApplied: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        _limitedOfferState = limitedOfferState
        self.onSaveSuccess = onSaveSuccess
        self.onBoardApplied = onBoardApplied
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
    private var hasExistingBoardTasks: Bool {
        !viewModel.currentTaskPoolTasks().isEmpty
    }

    private var isPremiumUser: Bool {
        subscriptionManager.hasPremiumAccess
    }

    private var isQuickEditCustomModalPresented: Bool {
        isAddingGroupModalPresented
            || groupRenameTargetID != nil
            || taskEditorDraft != nil
            || (groupActionTargetID.map { groupID in
                library.groups.contains(where: { $0.id == groupID })
            } ?? false)
    }

    private var canAddStandaloneTask: Bool {
        quickEditCanAddStandaloneTask(isPremiumUser: isPremiumUser, library: library)
    }

    private var canAddGroup: Bool {
        quickEditCanAddGroup(isPremiumUser: isPremiumUser, library: library)
    }

    private var maxGridSizeForCurrentPlan: Int {
        quickEditMaxGridSizeForCurrentPlan(isPremiumUser: isPremiumUser)
    }

    private var historyBySourceTaskID: [UUID: TaskHistoryRecord] {
        quickEditHistoryBySourceTaskID(records: taskHistoryRecords)
    }

    private var historyOnlyRecordsSorted: [TaskHistoryRecord] {
        quickEditHistoryOnlyRecordsSorted(records: taskHistoryRecords, library: library)
    }

    private var unlockedHistoryRecords: [TaskHistoryRecord] {
        guard !isPremiumUser else { return historyOnlyRecordsSorted }
        return Array(historyOnlyRecordsSorted.prefix(AppSettings.freeHistoryTasksVisibleCount))
    }

    private var allTaskCandidates: [QuickEditTaskCandidate] {
        let base = quickEditAllTaskCandidates(library: library, unlockedHistoryRecords: unlockedHistoryRecords)
        var tasks = Dictionary(uniqueKeysWithValues: base.filter { candidate in
            !candidate.id.hasPrefix("history:") || !supplementalPoolTasks.contains {
                $0.key != candidate.id && quickEditSameTaskDefinition($0.value, candidate.task)
            }
        }.map { ($0.id, $0.task) })
        tasks.merge(supplementalPoolTasks) { _, supplemental in supplemental }
        return tasks.map { QuickEditTaskCandidate(id: $0.key, task: $0.value) }.sorted { $0.id < $1.id }
    }

    private var filteredTaskItems: [QuickEditFilteredTaskItem] {
        let base = quickEditFilteredTaskItems(
            activeFilter: activeFilter,
            library: library,
            historyBySourceTaskID: historyBySourceTaskID,
            historyOnlyRecordsSorted: historyOnlyRecordsSorted,
            isPremiumUser: isPremiumUser
        )
        guard activeFilter == .all else { return base }
        let visible = base.filter { item in
            guard case .history = item.source else { return true }
            return supplementalPoolTasks[item.id] == nil &&
                !supplementalPoolTasks.contains { quickEditSameTaskDefinition($0.value, item.task) }
        }
        let supplemental = supplementalPoolTasks.map { key, task in
            QuickEditFilteredTaskItem(id: key, source: .history, task: task, operationDate: .distantFuture, isLocked: false)
        }.sorted { $0.id < $1.id }
        return supplemental + visible
    }

    private var candidateTaskMap: [String: MyTaskItem] {
        Dictionary(uniqueKeysWithValues: allTaskCandidates.map { ($0.id, $0.task) })
    }

    private var totalGridSlots: Int {
        targetGridSize * targetGridSize
    }

    private var selectedPreviewCount: Int {
        quickEditSelectedPreviewCount(previewSlots)
    }

    private var selectedCountSummary: String {
        quickEditSelectedCountSummary(selected: selectedPreviewCount, total: totalGridSlots)
    }

    private var activeFilterTitle: String {
        quickEditActiveFilterTitle(activeFilter, library: library)
    }

    private var activeGroupID: UUID? {
        quickEditActiveGroupID(activeFilter)
    }

    private var activeGroupTasks: [MyTaskItem] {
        quickEditActiveGroupTasks(activeFilter: activeFilter, library: library)
    }

    private var activeGroupTaskKeys: [String] {
        activeGroupTasks.map(quickEditTaskKey)
    }
    var body: some View {
        NavigationStack {
            quickEditNavigationContent
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
        .onAppear {
            handleQuickEditAppear()
        }
        .onChange(of: library) { previousLibrary, _ in
            handleLibraryDidChange(previousLibrary: previousLibrary)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nativeICloudSecondaryProjectionDidChange).receive(on: RunLoop.main)) { _ in
            refreshTaskHistory()
        }
        .task(id: library) {
            guard initialSnapshot != nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            refreshTaskHistory()
        }
        .onChange(of: targetGridSize) { _, _ in
            adjustPreviewSlotCount()
        }
        .fullScreenCover(isPresented: $isPremiumPaywallPresented) {
            PremiumPaywallView(
                entrySource: premiumPaywallSource,
                limitedOfferState: $limitedOfferState
            )
        }
        .sheet(item: $previewEditingTarget, onDismiss: {
            poolEditingSlot = nil
            newPoolTaskDestination = nil
        }) { target in
            previewEditTaskSheet(for: target.slotID)
                .presentationDetents([.fraction(isPadLayout ? 0.66 : 0.74), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: "202020"))
        }
        .alert(
            L10n.tr("Discard changes?", zhHans: "确认退出？", zhHant: "確認退出？"),
            isPresented: $isExitDiscardAlertPresented
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.tr("Save task library and exit", zhHans: "保存任务库并退出", zhHant: "儲存任務庫並退出")) {
                if finalizeLibrary() { dismiss() }
            }
            Button(L10n.tr("Discard unsaved edits and exit", zhHans: "放弃未保存的修改并退出", zhHant: "放棄未儲存的修改並退出"), role: .destructive) {
                dismiss()
            }
        } message: {
            Text(L10n.tr("Board changes will not be applied. Choose whether to save unsaved task library edits.",
                zhHans: "退出不会应用棋盘改动。请选择是否保存尚未保存的任务库修改。",
                zhHant: "退出不會套用棋盤改動。請選擇是否儲存尚未儲存的任務庫修改。"))
        }
        .alert(
            deleteConfirmationTarget?.title ?? L10n.deleteConfirmationTitle,
            isPresented: Binding(
                get: { deleteConfirmationTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteConfirmationTarget = nil
                    }
                }
            ),
            presenting: deleteConfirmationTarget
        ) { target in
            Button(L10n.cancel, role: .cancel) {}
            Button(target.title, role: .destructive) {
                confirmDelete(target)
            }
        } message: { target in
            Text(quickEditDeleteMessage(for: target, in: library))
        }
        .alert(
            L10n.tr("Delete this group?", zhHans: "删除该分组？", zhHant: "刪除該分組？"),
            isPresented: Binding(
                get: { pendingGroupDeleteFinalConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingGroupDeleteFinalConfirmation = nil
                    }
                }
            )
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.deleteConfirmationTitle, role: .destructive) {
                guard let groupID = pendingGroupDeleteFinalConfirmation else { return }
                finalizeGroupDeletion(groupID)
            }
        } message: {
            let name = pendingGroupDeleteFinalConfirmation.map { quickEditGroupName(for: $0, in: library) } ?? L10n.groupDefaultName
            Text(
                L10n.tr(
                    "All tasks in \"\(name)\" will be deleted and cannot be undone.",
                    zhHans: "「\(name)」中的所有任务将被删除，且不可恢复。",
                    zhHant: "「\(name)」中的所有任務將被刪除，且不可恢復。"
                )
            )
        }
        .alert(
            L10n.quickEditReplaceConfirmationTitle,
            isPresented: Binding(
                get: { pendingApplyPlan != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingApplyPlan = nil
                    }
                }
            )
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.apply) {
                guard let plan = pendingApplyPlan else { return }
                pendingApplyPlan = nil
                applySelectionToBoard(plan)
            }
        } message: {
            Text(L10n.quickEditReplaceConfirmationMessage)
        }
        .confirmationDialog(
            L10n.tr("Move to Group", zhHans: "移动分组", zhHant: "移動分組"),
            isPresented: Binding(get: { movingTaskKey != nil }, set: { if !$0 { movingTaskKey = nil } }),
            titleVisibility: .visible,
            presenting: movingTaskKey
        ) { key in
            Button(L10n.tr("Ungrouped", zhHans: "未分组", zhHant: "未分組")) {
                moveTask(key: key, to: nil)
            }
            ForEach(library.groups) { group in
                Button(quickEditDisplayGroupName(group)) { moveTask(key: key, to: group.id) }
            }
            Button(L10n.cancel, role: .cancel) { movingTaskKey = nil }
        }
        .alert(
            L10n.tr("Reduce board size?", zhHans: "缩小棋盘？", zhHant: "縮小棋盤？"),
            isPresented: Binding(get: { pendingGridSize != nil }, set: { if !$0 { pendingGridSize = nil } })
        ) {
            Button(L10n.cancel, role: .cancel) { pendingGridSize = nil }
            Button(L10n.tr("Reduce", zhHans: "缩小", zhHant: "縮小"), role: .destructive) {
                guard let size = pendingGridSize else { return }
                pendingGridSize = nil
                resizeGrid(to: size)
            }
        } message: {
            Text(L10n.tr("Tasks outside the smaller board will return to the task pool.", zhHans: "超出新棋盘范围的任务将取消选择，仍保留在任务池中。", zhHant: "超出新棋盤範圍的任務將取消選擇，仍保留在任務池中。"))
        }
    }

    private var quickEditNavigationContent: some View {
        ZStack {
            Group {
                quickEditBackground
                quickEditMainScroll
                QuickEditToastOverlayView(
                    isVisible: isLocalToastVisible,
                    message: localToastMessage,
                    isPadLayout: isPadLayout
                )
            }
            .accessibilityHidden(isQuickEditCustomModalPresented)
            quickEditModalOverlays
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(quickEditBackgroundColor, for: .navigationBar)
        .toolbar {
            quickEditToolbarContent
        }
    }

    private var quickEditBackground: some View {
        ZStack {
            quickEditBackgroundColor
            quickEditBackgroundTint
        }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
    }

    private var quickEditMainScroll: some View {
        GeometryReader { geo in
            if #available(iOS 27.1, *), isPadLayout, geo.size.width >= 700 {
                ArrangementView {
                    ScrollView {
                        quickEditControlsCard
                            .frame(maxWidth: 440)
                            .padding(24)
                            .frame(maxWidth: .infinity)
                    }
                    .splitArrangementLayoutRatio(0.48)
                    .layoutPriority(1)
                } secondary: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            taskPoolHint
                            filterTabsSection
                            taskListSection
                        }
                        .padding(.horizontal, quickEditPageHorizontalPadding)
                        .padding(.top, 24)
                        .padding(.bottom, 110)
                    }
                }
                .arrangementViewStyle(.split)
                .scrollDismissesKeyboard(.interactively)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        quickEditControlsCard
                            .frame(maxWidth: .infinity)
                        taskPoolHint
                        filterTabsSection
                        taskListSection
                    }
                    .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, quickEditPageHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    @ViewBuilder
    private var quickEditModalOverlays: some View {
        if let groupID = groupActionTargetID,
           library.groups.contains(where: { $0.id == groupID }) {
            QuickEditGroupActionsOverlayView(
                isPadLayout: isPadLayout,
                onDismiss: dismissGroupActions,
                onEdit: {
                    beginGroupRename(groupID)
                },
                onDelete: {
                    requestFinalGroupDeletion(groupID)
                },
                onApply: {
                    dismissGroupActions()
                    activeFilter = .group(groupID)
                    applyActiveGroupToPreview()
                }
            )
            .transition(.opacity)
        }

        if isAddingGroupModalPresented {
            addGroupModal
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if groupRenameTargetID != nil {
            renameGroupModal
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if taskEditorDraft != nil {
            taskEditorModal
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ToolbarContentBuilder
    private var quickEditToolbarContent: some ToolbarContent {
        if #available(iOS 26.0, *) {
            quickEditToolbarButtons.sharedBackgroundVisibility(.hidden)
        } else {
            quickEditToolbarButtons
        }
    }

    @ToolbarContentBuilder
    private var quickEditToolbarButtons: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(L10n.tr("Exit", zhHans: "退出", zhHant: "退出")) {
                handleExitTap()
            }
            .fontWeight(.semibold)
            .foregroundStyle(NeumorphicColors.text)
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color(hex: "EAE2DC"), in: Capsule())
            .accessibilityHidden(isQuickEditCustomModalPresented)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button(L10n.tr("Apply", zhHans: "应用", zhHant: "套用")) {
                handleDoneTap()
            }
            .fontWeight(.semibold)
            .foregroundStyle(NeumorphicColors.text)
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color(hex: "EAE2DC"), in: Capsule())
            .accessibilityHidden(isQuickEditCustomModalPresented)
        }

    }

    private var quickEditControlsCard: some View {
        QuickEditPreviewGridView(
            targetGridSize: $targetGridSize,
            previewSlots: $previewSlots,
            previewDragSourceID: $previewDragSourceID,
            previewDropTargetID: $previewDropTargetID,
            selectedCountSummary: selectedCountSummary,
            isPadLayout: isPadLayout,
            sectionBackground: .white,
            selectedBadgeBackground: quickEditSelectedBadgeBackground,
            previewEmptySlotFill: previewEmptySlotFill,
            previewFilledSlotFill: previewFilledSlotFill,
            previewEmptySlotStroke: previewEmptySlotStroke,
            previewFilledSlotStroke: previewFilledSlotStroke,
            onDecreaseGrid: {
                requestDecreaseGrid()
            },
            onIncreaseGrid: {
                let nextSize = targetGridSize + 1
                guard nextSize <= maxGridSizeForCurrentPlan else {
                    AnalyticsService.logPremiumGrid5x5LimitHit(
                        currentGridSize: targetGridSize,
                        source: "quick_edit"
                    )
                    openPremiumPaywall(source: "quick_edit_grid_5x5")
                    return
                }
                targetGridSize = min(5, nextSize)
            },
            onEditSlot: { slotID in
                previewEditingTarget = QuickEditPreviewEditingTarget(slotID: slotID)
            },
            onDeleteSlot: { slotID in
                deletePreviewTask(slotID: slotID)
            },
            onClearPreviewDrag: clearPreviewDragState
        )
    }

    private var filterTabsSection: some View {
        QuickEditFilterTabsView(
            groups: library.groups.map { QuickEditGroupTab(id: $0.id, title: quickEditDisplayGroupName($0)) },
            selectedGroupID: activeGroupID,
            isPadLayout: isPadLayout,
            onSelectAll: {
                activeFilter = .all
            },
            onSelectGroup: { groupID in
                activeFilter = .group(groupID)
            },
            onLongPressGroup: { groupID in
                focusedField = nil
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    groupActionTargetID = groupID
                }
            },
            onAddGroup: presentAddGroupModal
        )
    }

    @ViewBuilder
    private var taskPoolHint: some View {
        if isTaskPoolHintVisible {
            HStack(alignment: .top, spacing: 4) {
                Label {
                    Text(L10n.tr(
                        "Select task tags from the pool below to quickly place them on the board. Touch and hold a task tag to edit its details.",
                        zhHans: "从下方的任务池中选择任务tag快速放置到棋盘中，长按任务tag进行详细编辑。",
                        zhHant: "從下方的任務池中選擇任務tag快速放置到棋盤中，長按任務tag進行詳細編輯。"
                    ))
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(NeumorphicColors.text.opacity(0.22))
                }
                .font(.appSystem(size: scaled(13, pad: 15), weight: .medium))
                .foregroundStyle(NeumorphicColors.text.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        isTaskPoolHintVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 12, weight: .semibold))
                        .foregroundStyle(NeumorphicColors.text.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Dismiss tip", zhHans: "关闭提示", zhHant: "關閉提示"))
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Color(hex: "FAF7F4"), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var taskListSection: some View {
        let items = filteredTaskItems
        let selectedKeys = Set(selectedTaskKeys)
        let tagItems = items.filter { !$0.isLocked }.map { item in
            return QuickEditTaskTagItem(
                id: item.id, title: item.task.trimmedText,
                isSelected: selectedKeys.contains(item.id), isLocked: false,
                canEdit: true, canMove: true
            )
        }
        // Keep restricted history behind the existing paywall, without exposing its titles.
        let lockedItems = items.filter(\.isLocked).prefix(5).map { item in
            QuickEditTaskTagItem(
                id: item.id, title: item.task.trimmedText,
                isSelected: false, isLocked: true, canEdit: false, canMove: false
            )
        }
        return VStack(alignment: .leading, spacing: 12) {
            QuickEditTaskPoolView(
                items: tagItems + lockedItems,
                filterID: activeGroupID?.uuidString ?? "all",
                onAdd: startAddingPoolTask,
                onToggle: { key in
                    focusedField = nil
                    toggleSelection(for: key)
                    AppHaptics.control()
                },
                onEdit: { key in
                    openPoolTaskEditor(for: key)
                },
                onMove: { key in focusedField = nil; movingTaskKey = key },
                onDelete: { key in
                    focusedField = nil
                    if let location = taskLocation(forTaskKey: key) {
                        deleteConfirmationTarget = location.deleteTarget
                    } else {
                        deleteConfirmationTarget = .history(key)
                    }
                },
                onUnlock: { presentPremiumPaywallForLimit(source: "quick_edit_all_tasks_history_locked") }
            )
        }
    }

    private func moveTask(key: String, to groupID: UUID?) {
        movingTaskKey = nil
        guard let task = candidateTaskMap[key] else { return }
        let isExternalTask = taskLocation(forTaskKey: key) == nil
        // Commit the complete library once, so observers never see a task temporarily removed.
        var updatedLibrary = library
        switch quickEditMovePoolTask(key: key, task: task, to: groupID, isPremiumUser: isPremiumUser, library: &updatedLibrary) {
        case .moved:
            if isExternalTask {
                let newKey = quickEditTaskKey(task)
                selectedTaskKeys = selectedTaskKeys.map { $0 == key ? newKey : $0 }
                for index in previewSlots.indices where previewSlots[index].sourceTaskKey == key {
                    previewSlots[index].sourceTaskKey = newKey
                }
                if let draft = deselectedTaskDrafts.removeValue(forKey: key) { deselectedTaskDrafts[newKey] = draft }
                supplementalPoolTasks.removeValue(forKey: key)
            }
            library = updatedLibrary
            showLocalToast(L10n.tr("Task moved", zhHans: "已移动任务", zhHant: "已移動任務"))
        case .limitReached:
            presentPremiumPaywallForLimit(source: "quick_edit_move_task_limit")
        case .unchanged, .invalid:
            break
        }
    }

    private func requestDecreaseGrid() {
        let size = max(2, targetGridSize - 1)
        guard size != targetGridSize else { return }
        if previewSlots.dropFirst(size * size).contains(where: { $0.task != nil }) {
            pendingGridSize = size
        } else {
            resizeGrid(to: size)
        }
    }

    private func resizeGrid(to size: Int) {
        let removedKeys = previewSlots.dropFirst(size * size).compactMap(\.sourceTaskKey)
        for key in removedKeys {
            removePreviewTask(for: key)
            selectedTaskKeys.removeAll { $0 == key }
        }
        clearPreviewDragState()
        targetGridSize = size
    }

    @ViewBuilder
    private var addGroupModal: some View {
        QuickEditGroupNameModal(
            title: L10n.quickEditAddGroupTitle,
            groupName: $newGroupNameDraft,
            focusedField: $focusedField,
            focusField: .newGroupName,
            isPadLayout: isPadLayout,
            placeholderColor: quickEditPlaceholderColor,
            taskBackground: quickEditTaskFlatBackground,
            fieldStroke: quickEditFieldStroke,
            onDismiss: dismissAddGroupModal,
            onCommit: commitAddGroup
        )
    }

    @ViewBuilder
    private var renameGroupModal: some View {
        QuickEditGroupNameModal(
            title: L10n.quickEditEditGroupTitle,
            groupName: $groupRenameDraft,
            focusedField: $focusedField,
            focusField: .editGroupName,
            isPadLayout: isPadLayout,
            placeholderColor: quickEditPlaceholderColor,
            taskBackground: quickEditTaskFlatBackground,
            fieldStroke: quickEditFieldStroke,
            onDismiss: dismissGroupRename,
            onCommit: commitGroupRename
        )
    }

    @ViewBuilder
    private var taskEditorModal: some View {
        QuickEditTaskEditorModal(
            isPresented: taskEditorDraft != nil,
            isSaveEnabled: taskEditorDraft?.canSave == true,
            taskName: taskEditorNameBinding,
            startMonth: taskEditorMonthBinding,
            startDay: taskEditorDayBinding,
            focusedField: $focusedField,
            isPadLayout: isPadLayout,
            placeholderColor: quickEditPlaceholderColor,
            taskBackground: quickEditTaskFlatBackground,
            fieldStroke: quickEditFieldStroke,
            onDismiss: dismissTaskEditor,
            onClearStartDate: clearTaskEditorStartDate,
            onSave: saveTaskEditorDraft
        )
    }

    private var taskEditorNameBinding: Binding<String> {
        Binding(
            get: { taskEditorDraft?.text ?? "" },
            set: { newValue in
                guard var draft = taskEditorDraft else { return }
                draft.text = newValue
                taskEditorDraft = draft
            }
        )
    }

    private var taskEditorMonthBinding: Binding<String> {
        Binding(
            get: { taskEditorDraft?.startMonthText ?? "" },
            set: { newValue in
                guard var draft = taskEditorDraft else { return }
                draft.startMonthText = String(newValue.filter(\.isNumber).prefix(2))
                taskEditorDraft = draft
            }
        )
    }

    private var taskEditorDayBinding: Binding<String> {
        Binding(
            get: { taskEditorDraft?.startDayText ?? "" },
            set: { newValue in
                guard var draft = taskEditorDraft else { return }
                draft.startDayText = String(newValue.filter(\.isNumber).prefix(2))
                taskEditorDraft = draft
            }
        )
    }

    private func taskBinding(for location: QuickEditTaskLocation) -> Binding<String> {
        switch location {
        case .standalone(let index):
            return taskBinding(for: index)
        case .group(let groupID, let index):
            return groupTaskBinding(groupID: groupID, index: index)
        }
    }

    private func task(for location: QuickEditTaskLocation) -> MyTaskItem? {
        quickEditTask(for: location, in: library)
    }

    private func setTask(_ task: MyTaskItem, for location: QuickEditTaskLocation) {
        quickEditSetTask(task, for: location, in: &library)
    }

    private func taskStartDateLabel(for location: QuickEditTaskLocation) -> String {
        guard let task = task(for: location),
              let month = task.startMonth,
              let day = task.startDay else {
            return L10n.quickEditTaskNoStartDate
        }
        return "\(month)/\(day)"
    }

    private func openTaskEditor(for location: QuickEditTaskLocation) {
        guard let currentTask = task(for: location) else { return }
        taskEditorDraft = quickEditEditorDraft(for: location, task: currentTask)

        DispatchQueue.main.async {
            focusedField = .taskEditorName
        }
    }

    @ViewBuilder
    private func previewEditTaskSheet(for slotID: UUID) -> some View {
        if let editingSlot = taskEditingSlot(for: slotID), let currentCell = editingSlot.cellState {
            EditTaskSheet(
                text: currentCell.storedTaskText,
                isForcedTask: currentCell.isForced,
                residentWeekdays: currentCell.residentWeekdays,
                isOneTimeTask: currentCell.isOneTimeTask,
                recurrenceRule: currentCell.recurrenceRule,
                startVisibleAt: currentCell.startVisibleAt,
                endVisibleAt: currentCell.endVisibleAt,
                startReminderEnabled: currentCell.startReminderEnabled,
                startReminderOffsetMinutes: currentCell.startReminderOffsetMinutes,
                isCompletedTask: currentCell.isCompleted,
                estimatedDurationMinutes: quickEditRemainingMinutes(from: currentCell.countdownEndsAt),
                customCompletionPoints: currentCell.customCompletionPoints,
                completionHistoryCountProvider: completionHistoryCountLookup,
                diagnosticCellID: currentCell.id,
                diagnosticSource: "quick_edit_editor",
                onSave: { newText, isForcedTask, residentWeekdays, isOneTimeTask, recurrenceRule, estimatedDurationMinutes, startVisibleAt, endVisibleAt, startReminderEnabled, startReminderOffsetMinutes, taskRewardEdit in
                    guard let slot = taskEditingSlot(for: slotID), let existingCell = slot.cellState else { return false }
                    guard TaskCompletionRewardRules.allows(taskRewardEdit, hasPremiumAccess: subscriptionManager.hasPremiumAccess) else { return false }
                    guard var editedCell = quickEditMakePreviewCellFromEdit(
                        existingCell: existingCell,
                        text: newText,
                        isForcedTask: isForcedTask,
                        residentWeekdays: residentWeekdays,
                        isOneTimeTask: isOneTimeTask,
                        recurrenceRule: recurrenceRule,
                        estimatedDurationMinutes: estimatedDurationMinutes,
                        startVisibleAt: startVisibleAt,
                        endVisibleAt: endVisibleAt,
                        startReminderEnabled: startReminderEnabled,
                        startReminderOffsetMinutes: startReminderOffsetMinutes,
                        availableHistoryCount: viewModel.completionHistoryCount(for: newText)
                    ) else { return false }

                    let rewardDateKey = PointsStore.dateKey(for: .now)
                    let dailyRewards = PointsStore.loadDailyRewardState()
                    let legacyCredit = dailyRewards?.dateKey == rewardDateKey
                        ? dailyRewards?.taskReversalCredits[existingCell.id.uuidString.lowercased()] : nil
                    editedCell = TaskCompletionRewardRules.applyingEdit(
                        taskRewardEdit, previous: existingCell, updated: editedCell,
                        legacyReversalCredit: legacyCredit, dateKey: rewardDateKey
                    )
                    if let destination = newPoolTaskDestination {
                        guard commitNewPoolTask(cell: editedCell, destination: destination) else { return false }
                        poolEditingSlot = nil
                        previewEditingTarget = nil
                        return true
                    }
                    guard let updatedTask = PreviewSlot(cellState: editedCell).task else { return false }
                    if let key = slot.sourceTaskKey, !syncLibraryTask(forTaskKey: key, with: updatedTask) { return false }
                    if let index = previewSlots.firstIndex(where: { $0.id == slotID }) {
                        previewSlots[index].cellState = editedCell
                        explicitlyEditedCellIDs.insert(editedCell.id)
                    } else if let key = slot.sourceTaskKey, let task = candidateTaskMap[key] {
                        // Editing an unselected tag must not select it or consume a board slot.
                        deselectedTaskDrafts[key] = QuickEditDeselectedTaskDraft(sourceTask: task, cellState: editedCell)
                    }
                    poolEditingSlot = nil
                    DiagnosticLogStore.recordStateChange("task_rule.preview_edited", details: [
                        "source": "quick_edit_editor", "cell_id": editedCell.id.uuidString,
                        "before_rule": existingCell.diagnosticTaskRuleKind,
                        "after_rule": editedCell.diagnosticTaskRuleKind
                    ])
                    previewEditingTarget = nil
                    return true
                },
                onDelete: {
                    if previewSlots.contains(where: { $0.id == slotID }) {
                        deletePreviewTask(slotID: slotID)
                    } else if let key = editingSlot.sourceTaskKey {
                        if let location = taskLocation(forTaskKey: key) {
                            confirmDelete(location.deleteTarget)
                        } else {
                            confirmDelete(.history(key))
                        }
                    }
                    poolEditingSlot = nil
                    previewEditingTarget = nil
                },
                onCancel: {
                    previewEditingTarget = nil
                }
            )
        } else {
            Color.clear
                .onAppear {
                    previewEditingTarget = nil
                }
        }
    }

    private func deletePreviewTask(slotID: UUID) {
        guard let index = previewSlots.firstIndex(where: { $0.id == slotID }) else { return }
        if let key = previewSlots[index].sourceTaskKey {
            removePreviewTask(for: key)
        } else {
            previewSlots[index].cellState = nil
        }
        selectedTaskKeys = previewSlots.compactMap(\.sourceTaskKey)
        showLocalToast(L10n.tr("Removed from board", zhHans: "已从棋盘移除", zhHant: "已從棋盤移除"))
    }

    private func openPoolTaskEditor(for key: String) {
        focusedField = nil
        if let slot = previewSlots.first(where: { $0.sourceTaskKey == key && $0.task != nil }) {
            previewEditingTarget = QuickEditPreviewEditingTarget(slotID: slot.id)
        } else if let task = candidateTaskMap[key] {
            let cell = deselectedTaskDrafts[key]?.cellState ?? quickEditMakePreviewCell(from: task)
            let slot = PreviewSlot(cellState: cell, sourceTaskKey: key)
            poolEditingSlot = slot
            previewEditingTarget = QuickEditPreviewEditingTarget(slotID: slot.id)
        }
    }

    private func taskEditingSlot(for slotID: UUID) -> PreviewSlot? {
        previewSlots.first { $0.id == slotID } ?? (poolEditingSlot?.id == slotID ? poolEditingSlot : nil)
    }

    @discardableResult
    private func saveExternalPoolTask(_ task: MyTaskItem, for key: String) -> Bool {
        if let historyKey = quickEditHistoryRecordKey(from: key) {
            var records = TaskHistoryStore.load()
            guard let index = records.firstIndex(where: { $0.key == historyKey }) else { return false }
            guard canWriteLibraryHistory else { return false }
            records[index] = quickEditHistoryRecordByEditing(records[index], task: task)
            guard TaskHistoryStore.save(records) else { return false }
            refreshTaskHistory()
        }
        supplementalPoolTasks[key] = task
        return true
    }

    private func clearTaskEditorStartDate() {
        guard var draft = taskEditorDraft else { return }
        draft.startMonthText = ""
        draft.startDayText = ""
        taskEditorDraft = draft
    }

    private func dismissTaskEditor() {
        taskEditorDraft = nil
        focusedField = nil
    }

    private func saveTaskEditorDraft() {
        guard let draft = taskEditorDraft else { return }
        guard draft.canSave else { return }

        switch draft.mode {
        case .edit(let location):
            guard let existingTask = task(for: location),
                  let updatedTask = quickEditTaskFromEditorDraft(draft, existingTask: existingTask) else {
                dismissTaskEditor()
                return
            }
            setTask(updatedTask, for: location)
            recordTaskHistory(updatedTask, sourceTaskID: updatedTask.id)
        case .createStandalone:
            break
        case .createGroup:
            break
        }

        taskEditorDraft = nil
        focusedField = nil
    }

    @discardableResult
    private func syncLibraryTask(forTaskKey key: String, with newTask: MyTaskItem) -> Bool {
        guard let location = taskLocation(forTaskKey: key) else {
            return saveExternalPoolTask(newTask, for: key)
        }
        guard let existingTask = task(for: location) else { return false }
        let syncedTask = quickEditSyncedTask(existingTask: existingTask, newTask: newTask)
        setTask(syncedTask, for: location)
        recordTaskHistory(syncedTask, sourceTaskID: syncedTask.id)
        DiagnosticLogStore.recordStateChange("task_rule.library_synced", details: [
            "source": "quick_edit_editor",
            "task_id": syncedTask.id.uuidString,
            "rule": syncedTask.recurrenceRule?.kind.rawValue ?? "single"
        ])
        return true
    }

    private func taskLocation(forTaskKey key: String) -> QuickEditTaskLocation? {
        quickEditTaskLocation(forTaskKey: key, in: library)
    }

    private func handleQuickEditAppear() {
        guard initialSnapshot == nil else { return }
        // SwiftUI may construct this view repeatedly while the sheet is open.
        // Read persistence once per editing session, never in its initializer.
        library = CommonTasksStore.loadLibrary()
        taskHistoryRecords = TaskHistoryStore.load()
        completionHistoryCountLookup = viewModel.makeCompletionHistoryCountLookup()
        lastTrackedLibrary = library
        librarySession = QuickEditLibrarySession(library: library)
        editingContext = viewModel.makeQuickEditBoardContext()
        targetGridSize = viewModel.gridSize
        activeFilter = .all
        seedTaskHistoryIfNeeded()
        let initialPool = quickEditInitialTaskPool(
            cells: viewModel.currentBoardCellsInRowMajor(size: targetGridSize),
            // Only tasks already on this board may be surfaced from restricted history.
            candidates: quickEditAllTaskCandidates(library: library, unlockedHistoryRecords: historyOnlyRecordsSorted),
            totalSlots: totalGridSlots
        )
        supplementalPoolTasks = initialPool.supplementalTasks
        previewSlots = initialPool.slots
        selectedTaskKeys = previewSlots.compactMap(\.sourceTaskKey)
        deselectedTaskDrafts = [:]
        explicitlyEditedCellIDs = []
        initialSnapshot = makeCurrentSnapshot()
        syncActiveFilterWithCurrentLibrary()
    }

    private func handleLibraryDidChange(previousLibrary: MyTasksLibrary) {
        let candidates = candidateTaskMap
        deselectedTaskDrafts = deselectedTaskDrafts.filter { candidates[$0.key] != nil }
        // Moving or renaming groups must not rewrite board runtime state.
        if !quickEditHasSameTaskDefinitions(previousLibrary, library) {
            syncSelectedTaskKeysWithCurrentLibrary()
            syncPreviewSlotsWithCurrentLibrary()
        }
        syncActiveFilterWithCurrentLibrary()
    }

    private func syncActiveFilterWithCurrentLibrary() {
        activeFilter = quickEditSyncedActiveFilter(activeFilter, library: library)
    }

    private func refreshTaskHistory() {
        taskHistoryRecords = TaskHistoryStore.load()
        completionHistoryCountLookup = viewModel.makeCompletionHistoryCountLookup()
    }

    private func seedTaskHistoryIfNeeded() {
        TaskHistoryStore.ensureLibrarySeeded(library)
        seedBoardTasksIntoHistory()
        backfillLegacyTaskHistoryIfNeeded()
        refreshTaskHistory()
    }

    private func recordTaskHistory(_ task: MyTaskItem, sourceTaskID: UUID? = nil) {
        guard !task.trimmedText.isEmpty, canWriteLibraryHistory else { return }
        if sourceTaskID == task.id {
            // A modal edit supersedes an earlier inline draft of the same task.
            pendingTaskHistoryEdits[task.id] = task
            return
        }
        if TaskHistoryStore.upsert(task: task, sourceTaskID: sourceTaskID), sourceTaskID == task.id {
            pendingTaskHistoryEdits.removeValue(forKey: task.id)
        }
        refreshTaskHistory()
    }

    // Text input stays in the local draft. Coalesce writes while typing and
    // flush on exit/save so dismissing during the debounce cannot lose edits.
    private func queueTaskHistoryEdit(_ task: MyTaskItem) {
        guard !task.trimmedText.isEmpty else { return }
        pendingTaskHistoryEdits[task.id] = task
    }

    @discardableResult
    private func flushPendingTaskHistoryEdits() -> Bool {
        guard !pendingTaskHistoryEdits.isEmpty else { return true }
        guard canWriteLibraryHistory,
              TaskHistoryStore.upsert(tasks: Array(pendingTaskHistoryEdits.values)) else { return false }
        pendingTaskHistoryEdits.removeAll()
        return true
    }

    private func seedBoardTasksIntoHistory() {
        let boardTasks = viewModel.currentBoardTasksInRowMajor(size: BingoViewModel.maxGridSize).compactMap { $0 }
        guard !boardTasks.isEmpty else { return }
        TaskHistoryStore.upsertBoardTasks(boardTasks)
    }

    private func backfillLegacyTaskHistoryIfNeeded() {
        guard taskHistoryRecords.isEmpty else { return }

        let now = Date()
        let diaryItems = quickEditLegacyHistoryItemsFromDiaryEntries(Array(BingoDiaryStore.loadAllEntriesDictionary().values))
        let timeoutItems = quickEditLegacyHistoryItemsFromTimeoutPayload(BingoTimeoutStore.loadAllPayload(), now: now)
        let backfillItems = (diaryItems + timeoutItems).sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            // A board snapshot can carry an explicit rule that name-only
            // completion and timeout records cannot represent.
            return lhs.task.recurrenceRule == nil && rhs.task.recurrenceRule != nil
        }
        guard !backfillItems.isEmpty else { return }

        for item in backfillItems {
            TaskHistoryStore.upsert(task: item.task, at: item.date)
        }
        taskHistoryRecords = TaskHistoryStore.load()
    }

    private func startAddingPoolTask() {
        switch quickEditStartInlineAddDecision(activeFilter: activeFilter, library: library, isPremiumUser: isPremiumUser) {
        case .paywall(let source):
            presentPremiumPaywallForLimit(source: source)
            return
        case .allowed:
            break
        }
        focusedField = nil
        newPoolTaskDestination = activeFilter
        let rule = TaskRecurrenceRule(kind: activeGroupID == nil ? .none : .daily)
        let slot = PreviewSlot(cellState: BingoCell(recurrenceRule: rule))
        poolEditingSlot = slot
        previewEditingTarget = QuickEditPreviewEditingTarget(slotID: slot.id)
    }

    private func commitNewPoolTask(cell: BingoCell, destination: QuickEditFilterTab) -> Bool {
        var updatedLibrary = library
        switch quickEditCommitDetailedTask(cell: cell, destination: destination, isPremiumUser: isPremiumUser, library: &updatedLibrary) {
        case .appended(let task):
            library = updatedLibrary
            // Keep the complete editor configuration for later placement; adding does not select a tag.
            deselectedTaskDrafts[quickEditTaskKey(task)] = QuickEditDeselectedTaskDraft(sourceTask: task, cellState: cell)
            recordTaskHistory(task, sourceTaskID: task.id)
            focusedField = nil
            return true
        case .paywall(let source):
            showLocalToast(L10n.tr("Task limit reached. Your draft is still here.", zhHans: "任务数量已达上限，已保留编辑内容。", zhHant: "任務數量已達上限，已保留編輯內容。"))
            premiumPaywallSource = source
            return false
        case .resetFilterToAll:
            showLocalToast(L10n.tr("This group was removed. Cancel and choose another group.", zhHans: "该分组已被移除，请取消后重新选择分组。", zhHant: "該分組已被移除，請取消後重新選擇分組。"))
            return false
        case .noOp:
            return false
        }
    }

    private func presentAddGroupModal() {
        guard canAddGroup else {
            presentPremiumPaywallForLimit(source: "group_limit_modal")
            return
        }
        newGroupNameDraft = ""
        isAddingGroupModalPresented = true
        DispatchQueue.main.async {
            focusedField = .newGroupName
        }
    }

    private func dismissAddGroupModal() {
        isAddingGroupModalPresented = false
        newGroupNameDraft = ""
        focusedField = nil
    }

    private func beginGroupRename(_ groupID: UUID) {
        guard library.groups.contains(where: { $0.id == groupID }) else {
            dismissGroupActions()
            return
        }

        performAfterDismissingGroupActions {
            groupRenameTargetID = groupID
            groupRenameDraft = quickEditGroupName(for: groupID, in: library)
            focusedField = .editGroupName
        }
    }

    private func dismissGroupRename() {
        groupRenameTargetID = nil
        groupRenameDraft = ""
        focusedField = nil
    }

    private func commitGroupRename() {
        guard let groupID = groupRenameTargetID else { return }

        switch quickEditRenameGroup(groupID, nameDraft: groupRenameDraft, library: &library) {
        case .renamed:
            dismissGroupRename()
            showLocalToast(L10n.quickEditGroupRenamedSuccess)
        case .unchanged:
            dismissGroupRename()
        case .invalid:
            break
        }
    }

    private func requestFinalGroupDeletion(_ groupID: UUID) {
        focusedField = nil
        performAfterDismissingGroupActions {
            pendingGroupDeleteFinalConfirmation = groupID
        }
    }

    private func dismissGroupActions() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            groupActionTargetID = nil
        }
    }

    private func performAfterDismissingGroupActions(_ action: @escaping () -> Void) {
        dismissGroupActions()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
            action()
        }
    }

    private func commitAddGroup() {
        let result = quickEditCommitAddGroup(
            nameDraft: newGroupNameDraft,
            isPremiumUser: isPremiumUser,
            library: &library
        )
        switch result {
        case .noOp:
            return
        case .paywall(let source):
            presentPremiumPaywallForLimit(source: source)
        case .appended(let group):
            activeFilter = .group(group.id)
            dismissAddGroupModal()
        }
    }

    private func taskBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                quickEditStandaloneTaskText(index: index, library: library)
            },
            set: { newValue in
                guard let updatedTask = quickEditUpdateStandaloneTaskText(
                    index: index,
                    newValue: newValue,
                    library: &library
                ) else { return }
                queueTaskHistoryEdit(updatedTask)
            }
        )
    }

    private func groupTaskBinding(groupID: UUID, index: Int) -> Binding<String> {
        Binding(
            get: {
                quickEditGroupTaskText(groupID: groupID, index: index, library: library)
            },
            set: { newValue in
                guard let updatedTask = quickEditUpdateGroupTaskText(
                    groupID: groupID,
                    index: index,
                    newValue: newValue,
                    library: &library
                ) else { return }
                queueTaskHistoryEdit(updatedTask)
            }
        )
    }

    private func toggleSelection(for key: String) {
        switch quickEditSelectionDecision(currentKeys: selectedTaskKeys, key: key) {
        case .remove(let index):
            selectedTaskKeys.remove(at: index)
            removePreviewTask(for: key)
        case .add:
            guard addPreviewTask(for: key) else {
                showLocalToast(quickEditPreviewFullMessage())
                return
            }
            selectedTaskKeys.append(key)
        }
    }

    private func applyActiveGroupToPreview() {
        guard !activeGroupTaskKeys.isEmpty else { return }
        focusedField = nil
        let result = quickEditAppendTasksToPreview(
            keys: activeGroupTaskKeys,
            candidateTaskMap: candidateTaskMap,
            currentSlots: previewSlots,
            deselectedTaskDrafts: &deselectedTaskDrafts,
            explicitlyEditedCellIDs: explicitlyEditedCellIDs,
            completionHistoryCountProvider: completionHistoryCountLookup
        )
        previewSlots = result.updatedSlots
        selectedTaskKeys = previewSlots.compactMap(\.sourceTaskKey)

        if result.omittedTaskCount > 0 {
            showLocalToast(L10n.quickEditGroupPartiallyApplied(result.omittedTaskCount))
        } else {
            showLocalToast(L10n.quickEditGroupAppliedToPreview)
        }
    }

    private func handleExitTap() {
        focusedField = nil
        if hasUnsavedChanges {
            isExitDiscardAlertPresented = true
        } else {
            dismiss()
        }
    }

    private var hasUnsavedChanges: Bool {
        quickEditHasUnsavedChanges(initialSnapshot: initialSnapshot, currentSnapshot: makeCurrentSnapshot())
    }

    private func makeCurrentSnapshot() -> QuickEditSnapshot {
        quickEditCurrentSnapshot(
            targetGridSize: targetGridSize,
            selectedTaskKeys: selectedTaskKeys,
            previewSlots: previewSlots,
            library: library
        )
    }

    private func handleDoneTap() {
        focusedField = nil
        guard hasUnsavedChanges else {
            dismiss()
            return
        }
        guard finalizeLibrary(showSuccessToast: false, emitChangeToast: false) else { return }
        let plan = QuickEditApplyPlan(tasks: previewSlots.compactMap(\.task), targetGridSize: targetGridSize)

        let hadInitialTasks = initialSnapshot?.previewItems.contains { $0.cellState?.hasStoredTask == true } ?? false
        if plan.tasks.isEmpty && !hadInitialTasks {
            onSaveSuccess(L10n.quickEditKeptBoardWithoutSelection)
            dismiss()
            return
        }

        if hasExistingBoardTasks {
            pendingApplyPlan = plan
            return
        }

        applySelectionToBoard(plan)
    }

    private func applySelectionToBoard(_ plan: QuickEditApplyPlan) {
        guard let editingContext else { return }
        let orderedCells = previewSlots.map(\.cellState)
        guard viewModel.applyBoardOrderedCells(
            orderedCells, targetGridSize: plan.targetGridSize,
            explicitlyEditedCellIDs: explicitlyEditedCellIDs,
            editingContext: editingContext,
            hasPremiumTaskRewardAccess: subscriptionManager.hasPremiumAccess
        ) else {
            if !viewModel.isQuickEditBoardContextCurrent(editingContext) {
                showLocalToast(L10n.tr(
                    "The board changed while you were editing. Your draft is still here. Reopen quick edit to use the latest board.",
                    zhHans: "编辑期间棋盘已更新，草稿已保留。请重新打开快速编辑以使用最新棋盘。",
                    zhHant: "編輯期間棋盤已更新，草稿已保留。請重新開啟快速編輯以使用最新棋盤。",
                    ja: "編集中にボードが更新されました。下書きは保持されています。最新のボードを使うにはクイック編集を開き直してください。"
                ))
                return
            }
            showLocalToast(
                L10n.tr(
                    "Could not save board changes. Your edits are still here. Please try again.",
                    zhHans: "棋盘保存未成功，已保留编辑内容，请重试。",
                    zhHant: "棋盤儲存未成功，已保留編輯內容，請重試。",
                    ja: "ボードを保存できませんでした。編集内容は保持されています。もう一度お試しください。"
                )
            )
            return
        }
        onBoardApplied()
        onSaveSuccess(L10n.quickEditAppliedSuccess(min(plan.tasks.count, plan.targetGridSize * plan.targetGridSize)))
        dismiss()
    }

    private func syncSelectedTaskKeysWithCurrentLibrary() {
        let validKeys = Set(allTaskCandidates.map(\.id))
        selectedTaskKeys = selectedTaskKeys.filter { validKeys.contains($0) }
    }

    private func buildInitialPreviewSlots() -> [PreviewSlot] {
        let boardCells = viewModel.currentBoardCellsInRowMajor(size: targetGridSize)
        let slots = boardCells.prefix(totalGridSlots).map { cell in
            PreviewSlot(cellState: cell, sourceTaskKey: nil)
        }
        if slots.count >= totalGridSlots {
            return Array(slots.prefix(totalGridSlots))
        }
        return slots + quickEditEmptyPreviewSlots(count: totalGridSlots - slots.count)
    }

    private func adjustPreviewSlotCount() {
        previewSlots = quickEditAdjustPreviewSlots(
            current: previewSlots,
            totalGridSlots: totalGridSlots,
            initialSlots: buildInitialPreviewSlots()
        )
    }

    private func addPreviewTask(for key: String) -> Bool {
        let result = quickEditAddPreviewTask(
            key: key,
            candidateTaskMap: candidateTaskMap,
            currentSlots: previewSlots,
            deselectedTaskDrafts: &deselectedTaskDrafts,
            explicitlyEditedCellIDs: explicitlyEditedCellIDs,
            completionHistoryCountProvider: completionHistoryCountLookup
        )
        previewSlots = result.updatedSlots
        return result.wasAdded
    }

    private func removePreviewTask(for key: String) {
        previewSlots = quickEditRemovePreviewTask(
            key: key,
            currentSlots: previewSlots,
            candidateTaskMap: candidateTaskMap,
            deselectedTaskDrafts: &deselectedTaskDrafts
        )
    }

    private func syncPreviewSlotsWithCurrentLibrary() {
        previewSlots = quickEditSyncPreviewSlotsWithLibrary(
            currentSlots: previewSlots,
            candidateTaskMap: candidateTaskMap,
            totalGridSlots: totalGridSlots,
            explicitlyEditedCellIDs: explicitlyEditedCellIDs,
            completionHistoryCountProvider: completionHistoryCountLookup
        )
    }

    private func clearPreviewDragState() {
        previewDragSourceID = nil
        previewDropTargetID = nil
    }

    private var canWriteLibraryHistory: Bool {
        librarySession?.canWrite(current: CommonTasksStore.loadLibrary(),
            accountScope: NativeICloudPreferences.accountScopeIdentifier) == true
    }

    @discardableResult
    private func finalizeLibrary(showSuccessToast: Bool = false, emitChangeToast: Bool = true) -> Bool {
        guard var session = librarySession else { return false }
        if library == session.baseline, pendingTaskHistoryEdits.isEmpty { return true }
        NativeICloudPrimaryMutationGate.acquire()
        let accepted = BingoBoardStore.withBoardPersistenceLock {
            session.save(library, accountScope: NativeICloudPreferences.accountScopeIdentifier,
                load: { CommonTasksStore.loadLibrary() }, persist: CommonTasksStore.saveLibrary)
        }
        NativeICloudPrimaryMutationGate.release()
        guard accepted == true else {
            showLocalToast(L10n.tr("The task library changed or could not be saved. Your draft is still here.",
                zhHans: "任务库已更新或保存失败，草稿已保留，请重新检查后重试。",
                zhHant: "任務庫已更新或儲存失敗，草稿已保留，請重新檢查後重試。"))
            return false
        }
        librarySession = session
        library = session.baseline
        guard flushPendingTaskHistoryEdits() else {
            showLocalToast(L10n.tr("Could not save task history. Your draft is still here.",
                zhHans: "任务历史保存失败，草稿已保留，请重试。", zhHant: "任務歷史儲存失敗，草稿已保留，請重試。"))
            return false
        }
        let previousLibrary = lastTrackedLibrary
        let savedLibrary = library
        TaskHistoryStore.ensureLibrarySeeded(savedLibrary)
        refreshTaskHistory()

        if showSuccessToast {
            onSaveSuccess(L10n.tasksSavedSuccess)
        } else if emitChangeToast,
                  savedLibrary != lastTrackedLibrary,
                  let message = quickEditSaveSuccessMessage(previous: previousLibrary, current: savedLibrary) {
            onSaveSuccess(message)
        }
        AnalyticsService.syncMyTasksLibrary(savedLibrary)
        lastTrackedLibrary = savedLibrary
        return true
    }

    private func presentPremiumPaywallForLimit(source: String) {
        let normalizedSource = source.lowercased()
        if normalizedSource.contains("history") {
            AnalyticsService.logPremiumHistoryLimitHit(
                visibleHistoryCount: min(historyOnlyRecordsSorted.count, AppSettings.freeHistoryTasksVisibleCount),
                totalHistoryCount: historyOnlyRecordsSorted.count,
                source: source
            )
        } else {
            AnalyticsService.logPremiumTasksGroupsLimitHit(
                source: source,
                taskCount: library.tasks.count,
                groupCount: library.groups.count,
                groupTaskCount: library.groups.reduce(0) { $0 + $1.tasks.count }
            )
        }
        openPremiumPaywall(source: source)
    }

    private func openPremiumPaywall(source: String) {
        premiumPaywallSource = source
        focusedField = nil
        isPremiumPaywallPresented = true
        Task { @MainActor in
            await subscriptionManager.refreshEntitlements()
        }
    }
private func confirmDelete(_ target: QuickEditDeleteTarget) {
    if case .history(let key) = target, key.hasPrefix("board:") {
        removePreviewTask(for: key)
        selectedTaskKeys.removeAll { $0 == key }
        supplementalPoolTasks.removeValue(forKey: key)
        deselectedTaskDrafts.removeValue(forKey: key)
        deleteConfirmationTarget = nil
        showLocalToast(L10n.taskDeletedSuccess)
        return
    }
    let resolution = quickEditResolveDeleteTarget(target, in: &library)
    switch resolution {
    case .libraryTaskRemoved(let task, let successMessage):
        recordTaskHistory(task, sourceTaskID: task.id)
        showLocalToast(successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    case .historyItemRemoved(let historyItemID, let successMessage):
        guard let historyKey = quickEditHistoryRecordKey(from: historyItemID) else {
            deleteConfirmationTarget = nil
            focusedField = nil
            return
        }
        TaskHistoryStore.deleteRecord(withKey: historyKey)
        supplementalPoolTasks.removeValue(forKey: historyItemID)
        selectedTaskKeys.removeAll(where: { $0 == historyItemID })
        removePreviewTask(for: historyItemID)
        refreshTaskHistory()
        showLocalToast(successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    case .invalid:
        deleteConfirmationTarget = nil
        focusedField = nil
    }
}

private func finalizeGroupDeletion(_ groupID: UUID) {
    let result = quickEditFinalizeGroupDeletion(groupID, in: &library, activeFilter: activeFilter)
    guard result.deleted else {
        pendingGroupDeleteFinalConfirmation = nil
        return
    }

    for task in result.removedTasks {
        recordTaskHistory(task, sourceTaskID: task.id)
    }
    activeFilter = result.updatedFilter

    showLocalToast(L10n.groupDeletedSuccess)
    pendingGroupDeleteFinalConfirmation = nil
    deleteConfirmationTarget = nil
    focusedField = nil
}

    private func showLocalToast(_ message: String) {
        hideLocalToastWorkItem?.cancel()
        localToastMessage = message

        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
            isLocalToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                isLocalToastVisible = false
            }
        }
        hideLocalToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

}
