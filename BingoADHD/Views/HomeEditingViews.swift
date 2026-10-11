import SwiftUI

struct QuickEditView: View {
    @ObservedObject var viewModel: BingoViewModel
    @Binding private var limitedOfferState: LimitedOfferHomeState
    let onSaveSuccess: (String) -> Void
    let onBoardApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var previewSlots: [PreviewSlot] = []
    @State private var deselectedTaskDrafts: [String: QuickEditDeselectedTaskDraft] = [:]
    @State private var explicitlyEditedCellIDs: Set<UUID> = []
    @State private var previewDragSourceID: UUID?
    @State private var previewDropTargetID: UUID?
    @State private var initialSnapshot: QuickEditSnapshot?
    @State private var editingContext: QuickEditBoardContext?
    @State private var isExitDiscardAlertPresented = false
    @State private var targetGridSize = 4
    @State private var didApplyToBoard = false
    @State private var pendingApplyPlan: QuickEditApplyPlan?
    @State private var isPremiumPaywallPresented = false
    @State private var premiumPaywallSource = "quick_edit"
    @State private var activeFilter: QuickEditFilterTab = .all
    @State private var isAddingTaskInline = false
    @State private var newTaskDraft = ""
    @State private var newTaskStartMonthDraft = ""
    @State private var newTaskStartDayDraft = ""
    @State private var isAddingGroupModalPresented = false
    @State private var newGroupNameDraft = ""
    @State private var groupActionTargetID: UUID?
    @State private var groupRenameTargetID: UUID?
    @State private var groupRenameDraft = ""
    @State private var pendingGroupDeleteFinalConfirmation: UUID?
    @State private var taskEditorDraft: QuickEditTaskEditorDraft?
    @State private var previewEditingTarget: QuickEditPreviewEditingTarget?

    typealias PreviewSlot = QuickEditPreviewSlot

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }
    
    private var activeTheme: AppTheme { .concise }
    private let quickEditBackgroundColor = Color(hex: "F4F4F4")
    private let quickEditBackgroundTint = Color.clear
    private let quickEditSectionFlatBackground = Color.clear
    private var quickEditTaskFlatBackground: Color { Color(hex: "F4F4F4") }
    private var quickEditSelectedBadgeBackground: Color { activeTheme.color.opacity(activeTheme == .concise ? 0.14 : 0.17) }
    private var quickEditFieldStroke: Color { activeTheme.bingoSurfaceShadowColor.opacity(0.16) }
    private var quickEditPlaceholderColor: Color { NeumorphicColors.text.opacity(0.34) }
    private var previewEmptySlotFill: Color { activeTheme.bingoSurfaceColor.opacity(0.16) }
    private var previewFilledSlotFill: Color { activeTheme.bingoSurfaceColor.opacity(0.44) }
    private var previewEmptySlotStroke: Color { activeTheme.bingoSurfaceShadowColor.opacity(0.44) }
    private var previewFilledSlotStroke: Color { activeTheme.bingoSurfaceShadowColor.opacity(0.66) }
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

    private var canAddStandaloneTask: Bool {
        quickEditCanAddStandaloneTask(isPremiumUser: isPremiumUser, library: library)
    }

    private var canAddGroup: Bool {
        quickEditCanAddGroup(isPremiumUser: isPremiumUser, library: library)
    }

    private var maxGridSizeForCurrentPlan: Int {
        quickEditMaxGridSizeForCurrentPlan(isPremiumUser: isPremiumUser)
    }

    private var libraryTaskIDs: Set<UUID> {
        quickEditLibraryTaskIDs(library: library)
    }

    private var historyBySourceTaskID: [UUID: TaskHistoryRecord] {
        quickEditHistoryBySourceTaskID(records: taskHistoryRecords)
    }

    private var historyOnlyRecordsSorted: [TaskHistoryRecord] {
        quickEditHistoryOnlyRecordsSorted(records: taskHistoryRecords, libraryTaskIDs: libraryTaskIDs)
    }

    private var unlockedHistoryRecords: [TaskHistoryRecord] {
        guard !isPremiumUser else { return historyOnlyRecordsSorted }
        return Array(historyOnlyRecordsSorted.prefix(AppSettings.freeHistoryTasksVisibleCount))
    }

    private var allTaskCandidates: [QuickEditTaskCandidate] {
        quickEditAllTaskCandidates(library: library, unlockedHistoryRecords: unlockedHistoryRecords)
    }

    private var filteredTaskItems: [QuickEditFilteredTaskItem] {
        quickEditFilteredTaskItems(
            activeFilter: activeFilter,
            library: library,
            historyBySourceTaskID: historyBySourceTaskID,
            historyOnlyRecordsSorted: historyOnlyRecordsSorted,
            isPremiumUser: isPremiumUser
        )
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
        .onDisappear {
            guard !didApplyToBoard else { return }
            finalizeLibrary()
        }
        .onAppear {
            handleQuickEditAppear()
        }
        .onChange(of: library) { _, _ in
            handleLibraryDidChange()
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
            flushPendingTaskHistoryEdits()
            TaskHistoryStore.ensureLibrarySeeded(library)
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
        .sheet(item: $previewEditingTarget) { target in
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
            Button(L10n.tr("Exit", zhHans: "退出", zhHant: "退出"), role: .destructive) {
                dismiss()
            }
        } message: {
            Text(L10n.tr("If you exit now, your recent edits will not be applied to the board.", zhHans: "现在退出，刚刚的改动将不会应用到棋盘。", zhHant: "現在退出，剛剛的改動將不會套用到棋盤。"))
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
        .safeAreaInset(edge: .bottom) {
            if isPremiumUser && activeFilter == .all && !isAddingGroupModalPresented {
                quickEditBottomAddTaskBar
            }
        }
    }

    private var quickEditNavigationContent: some View {
        ZStack {
            quickEditBackground
            quickEditMainScroll
            QuickEditToastOverlayView(
                isVisible: isLocalToastVisible,
                message: localToastMessage,
                isPadLayout: isPadLayout
            )
            quickEditModalOverlays
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
            let isPadPortrait = isPadLayout && geo.size.height > geo.size.width
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    quickEditControlsCard
                    filterTabsSection
                        .padding(.top, -10)
                    taskListSection
                }
                .frame(maxWidth: isPadLayout ? 760 : .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, quickEditPageHorizontalPadding)
                .padding(.top, 24 + (isPadPortrait ? 80 : 0))
                .padding(.bottom, isPadPortrait ? 0 : 110)
            }
            .scrollDismissesKeyboard(.interactively)
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
        ToolbarItem(placement: .principal) {
            Text(L10n.quickEdit)
                .font(.appSystem(size: scaled(20, pad: 23), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
        }

        ToolbarItem(placement: .topBarLeading) {
            Button(L10n.tr("Exit", zhHans: "退出", zhHant: "退出")) {
                handleExitTap()
            }
            .fontWeight(.semibold)
            .foregroundColor(NeumorphicColors.text)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button(L10n.tr("Apply", zhHans: "应用", zhHant: "套用")) {
                handleDoneTap()
            }
            .fontWeight(.semibold)
            .foregroundColor(NeumorphicColors.text)
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
            sectionBackground: quickEditSectionFlatBackground,
            selectedBadgeBackground: quickEditSelectedBadgeBackground,
            previewEmptySlotFill: previewEmptySlotFill,
            previewFilledSlotFill: previewFilledSlotFill,
            previewEmptySlotStroke: previewEmptySlotStroke,
            previewFilledSlotStroke: previewFilledSlotStroke,
            onDecreaseGrid: {
                targetGridSize = max(2, targetGridSize - 1)
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
            fieldStroke: quickEditFieldStroke,
            onSelectAll: {
                activeFilter = .all
            },
            onSelectGroup: { groupID in
                activeFilter = .group(groupID)
            },
            onLongPressGroup: { groupID in
                focusedField = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    groupActionTargetID = groupID
                }
            },
            onAddGroup: presentAddGroupModal
        )
    }

    private var taskListSection: some View {
        let visibleItems = filteredTaskItems.filter { !$0.isLocked }
        let lockedHistoryPreviewItems = Array(
            filteredTaskItems
                .filter { $0.isLocked && $0.source == .history }
                .prefix(5)
        )
        let isAllTasksFilter = activeFilter == .all

        return QuickEditTaskListContainerView(
            isAllTasksFilter: isAllTasksFilter,
            hasVisibleItems: !visibleItems.isEmpty,
            hasLockedHistoryPreview: !lockedHistoryPreviewItems.isEmpty,
            isAddingTaskInline: isAddingTaskInline,
            showsAddTaskButton: activeGroupID != nil,
            isPadLayout: isPadLayout,
            sectionBackground: quickEditSectionFlatBackground
        ) {
            QuickEditTaskListHeaderView(
                title: activeFilterTitle,
                activeGroupID: activeGroupID,
                canApplyGroup: !activeGroupTaskKeys.isEmpty,
                isPadLayout: isPadLayout,
                taskBackground: quickEditTaskFlatBackground,
                onApplyGroup: applyActiveGroupToPreview,
                onDeleteGroup: { groupID in
                    requestFinalGroupDeletion(groupID)
                }
            )
        } rows: {
            ForEach(visibleItems) { item in
                taskRow(for: item)
            }

            if !lockedHistoryPreviewItems.isEmpty {
                lockedHistoryPreviewBlock(items: lockedHistoryPreviewItems)
            }
        } inlineRow: {
            newTaskInlineRow
        } addTaskButton: {
            addTaskButton
        }
    }

    private var quickEditBottomAddTaskBar: some View {
        VStack(spacing: 0) {
            addTaskButton
                .frame(maxWidth: isPadLayout ? 760 : .infinity)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, quickEditPageHorizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
        .background(quickEditBackgroundColor)
    }

    private func lockedHistoryPreviewBlock(items: [QuickEditFilteredTaskItem]) -> some View {
        QuickEditLockedHistoryPreviewBlock(
            taskTexts: items.map { $0.task.trimmedText },
            isPadLayout: isPadLayout,
            taskBackground: quickEditTaskFlatBackground,
            fieldStroke: quickEditFieldStroke
        ) {
            presentPremiumPaywallForLimit(source: "quick_edit_all_tasks_history_locked")
        }
    }

    @ViewBuilder
    private func taskRow(for item: QuickEditFilteredTaskItem) -> some View {
        if item.isLocked {
            lockedHistoryTaskRow(for: item)
        } else {
            switch item.source {
            case .library(let location):
                editableLibraryTaskRow(for: item, location: location)
            case .history:
                readOnlyHistoryTaskRow(for: item)
            }
        }
    }

    private func editableLibraryTaskRow(for item: QuickEditFilteredTaskItem, location: QuickEditTaskLocation) -> some View {
        let key = item.id
        let isSelected = selectedTaskKeys.contains(key)

        return QuickEditEditableTaskRow(
            text: taskBinding(for: location),
            placeholder: location.placeholder,
            isSelected: isSelected,
            focusBinding: $focusedField,
            focusField: location.focusedField,
            isPadLayout: isPadLayout,
            placeholderColor: quickEditPlaceholderColor,
            taskBackground: quickEditTaskFlatBackground,
            fieldStroke: quickEditFieldStroke,
            onToggle: {
                toggleSelection(for: key)
            }
            ,
            onDelete: {
                focusedField = nil
                deleteConfirmationTarget = location.deleteTarget
            }
        )
    }

    private func readOnlyHistoryTaskRow(for item: QuickEditFilteredTaskItem) -> some View {
        let key = item.id
        let isSelected = selectedTaskKeys.contains(key)

        return QuickEditReadOnlyTaskRow(
            text: item.task.trimmedText,
            isSelected: isSelected,
            isPadLayout: isPadLayout,
            taskBackground: quickEditTaskFlatBackground,
            fieldStroke: quickEditFieldStroke,
            onToggle: {
                toggleSelection(for: key)
            },
            onDelete: {
                deleteConfirmationTarget = .history(item.id)
                focusedField = nil
            }
        )
    }

    private func lockedHistoryTaskRow(for item: QuickEditFilteredTaskItem) -> some View {
        QuickEditLockedTaskRow(
            text: item.task.trimmedText,
            isPadLayout: isPadLayout,
            taskBackground: quickEditTaskFlatBackground,
            fieldStroke: quickEditFieldStroke
        ) {
            presentPremiumPaywallForLimit(source: "quick_edit_all_tasks_history_locked")
        }
    }

    private var newTaskInlineRow: some View {
        QuickEditInlineNewTaskRow(
            draftText: $newTaskDraft,
            focusBinding: $focusedField,
            isPadLayout: isPadLayout,
            placeholderColor: quickEditPlaceholderColor,
            taskBackground: quickEditTaskFlatBackground,
            onSubmit: commitAddingTaskInline,
            onCancel: cancelAddingTaskInline
        )
    }

    private var addTaskButton: some View {
        QuickEditAddTaskButton(isPadLayout: isPadLayout) {
            if isAddingTaskInline {
                commitAddingTaskInline()
            } else {
                startAddingTaskInline()
            }
        }
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
        if let index = previewSlots.firstIndex(where: { $0.id == slotID }),
           let currentCell = previewSlots[index].cellState {
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
                completionHistoryCountProvider: completionHistoryCountLookup,
                diagnosticCellID: currentCell.id,
                diagnosticSource: "quick_edit_editor",
                onSave: { newText, isForcedTask, residentWeekdays, isOneTimeTask, recurrenceRule, estimatedDurationMinutes, startVisibleAt, endVisibleAt, startReminderEnabled, startReminderOffsetMinutes in
                    guard let latestIndex = previewSlots.firstIndex(where: { $0.id == slotID }) else {
                        return false
                    }

                    let existingCell = previewSlots[latestIndex].cellState
                    previewSlots[latestIndex].cellState = quickEditMakePreviewCellFromEdit(
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
                    )

                    if let editedCell = previewSlots[latestIndex].cellState {
                        explicitlyEditedCellIDs.insert(editedCell.id)
                        DiagnosticLogStore.recordStateChange("task_rule.preview_edited", details: [
                            "source": "quick_edit_editor", "cell_id": editedCell.id.uuidString,
                            "before_rule": existingCell?.diagnosticTaskRuleKind ?? "empty",
                            "after_rule": editedCell.diagnosticTaskRuleKind
                        ])
                    }
                    if let sourceTaskKey = previewSlots[latestIndex].sourceTaskKey {
                        let syncedTask = previewSlots[latestIndex].task ?? MyTaskItem(text: "")
                        syncLibraryTask(forTaskKey: sourceTaskKey, with: syncedTask)
                    }
                    previewEditingTarget = nil
                    return true
                },
                onDelete: {
                    deletePreviewTask(slotID: slotID)
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
        if let sourceTaskKey = previewSlots[index].sourceTaskKey {
            selectedTaskKeys.removeAll(where: { $0 == sourceTaskKey })
        }
        previewSlots[index].cellState = nil
        previewSlots[index].sourceTaskKey = nil
        showLocalToast(L10n.taskDeletedSuccess)
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

    private func syncLibraryTask(forTaskKey key: String, with newTask: MyTaskItem) {
        guard let location = taskLocation(forTaskKey: key),
              let existingTask = task(for: location) else { return }
        let syncedTask = quickEditSyncedTask(existingTask: existingTask, newTask: newTask)
        setTask(syncedTask, for: location)
        recordTaskHistory(syncedTask, sourceTaskID: syncedTask.id)
        DiagnosticLogStore.recordStateChange("task_rule.library_synced", details: [
            "source": "quick_edit_editor",
            "task_id": syncedTask.id.uuidString,
            "rule": syncedTask.recurrenceRule?.kind.rawValue ?? "single"
        ])
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
        editingContext = viewModel.makeQuickEditBoardContext()
        targetGridSize = viewModel.gridSize
        activeFilter = .all
        previewSlots = buildInitialPreviewSlots()
        selectedTaskKeys = []
        deselectedTaskDrafts = [:]
        explicitlyEditedCellIDs = []
        seedTaskHistoryIfNeeded()
        initialSnapshot = makeCurrentSnapshot()
        syncActiveFilterWithCurrentLibrary()
    }

    private func handleLibraryDidChange() {
        let candidates = candidateTaskMap
        deselectedTaskDrafts = deselectedTaskDrafts.filter { candidates[$0.key] != nil }
        syncSelectedTaskKeysWithCurrentLibrary()
        syncPreviewSlotsWithCurrentLibrary()
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
        guard !task.trimmedText.isEmpty else { return }
        if sourceTaskID == task.id {
            // A modal edit supersedes an earlier inline draft of the same task.
            pendingTaskHistoryEdits[task.id] = task
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

    private func flushPendingTaskHistoryEdits() {
        guard !pendingTaskHistoryEdits.isEmpty else { return }
        guard TaskHistoryStore.upsert(tasks: Array(pendingTaskHistoryEdits.values)) else { return }
        pendingTaskHistoryEdits.removeAll()
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

    private func startAddingTaskInline() {
        switch quickEditStartInlineAddDecision(
            activeFilter: activeFilter,
            library: library,
            isPremiumUser: isPremiumUser
        ) {
        case .paywall(let source):
            presentPremiumPaywallForLimit(source: source)
            return
        case .allowed:
            break
        }

        isAddingTaskInline = true
        newTaskDraft = ""
        newTaskStartMonthDraft = ""
        newTaskStartDayDraft = ""
        DispatchQueue.main.async {
            focusedField = .newTask
        }
    }

    private func cancelAddingTaskInline() {
        isAddingTaskInline = false
        newTaskDraft = ""
        newTaskStartMonthDraft = ""
        newTaskStartDayDraft = ""
        focusedField = nil
    }

    private func commitAddingTaskInline() {
        let result = quickEditCommitInlineTask(
            draftText: newTaskDraft,
            monthText: newTaskStartMonthDraft,
            dayText: newTaskStartDayDraft,
            activeFilter: activeFilter,
            isPremiumUser: isPremiumUser,
            library: &library
        )

        switch result {
        case .noOp:
            return
        case .paywall(let source):
            presentPremiumPaywallForLimit(source: source)
            return
        case .resetFilterToAll:
            activeFilter = .all
            return
        case .appended(let task):
            recordTaskHistory(task, sourceTaskID: task.id)
            isAddingTaskInline = false
            newTaskDraft = ""
            newTaskStartMonthDraft = ""
            newTaskStartDayDraft = ""
            focusedField = nil
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
        withAnimation(.easeInOut(duration: 0.2)) {
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
        finalizeLibrary(showSuccessToast: false, emitChangeToast: false)
        let plan = QuickEditApplyPlan(tasks: previewSlots.compactMap(\.task), targetGridSize: targetGridSize)

        guard !plan.tasks.isEmpty else {
            didApplyToBoard = true
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
            editingContext: editingContext
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
        didApplyToBoard = true
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

    private func finalizeLibrary(showSuccessToast: Bool = false, emitChangeToast: Bool = true) {
        flushPendingTaskHistoryEdits()
        let previousLibrary = lastTrackedLibrary
        CommonTasksStore.saveLibrary(library)
        let savedLibrary = CommonTasksStore.loadLibrary()
        library = savedLibrary
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

        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            isLocalToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.22)) {
                isLocalToastVisible = false
            }
        }
        hideLocalToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

}
