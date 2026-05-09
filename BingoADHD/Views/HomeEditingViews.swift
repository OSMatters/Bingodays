import SwiftUI

struct QuickEditView: View {
    @ObservedObject var viewModel: BingoViewModel
    let onSaveSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var library = CommonTasksStore.loadLibrary()
    @State private var taskHistoryRecords = TaskHistoryStore.load()
    @State private var lastTrackedLibrary = CommonTasksStore.loadLibrary()
    @FocusState private var focusedField: FocusedMyTaskField?
    @State private var deleteConfirmationTarget: QuickEditDeleteTarget?
    @State private var localToastMessage: String?
    @State private var isLocalToastVisible = false
    @State private var hideLocalToastWorkItem: DispatchWorkItem?
    @State private var selectedTaskKeys: [String] = []
    @State private var previewSlots: [PreviewSlot] = []
    @State private var previewDragSourceID: UUID?
    @State private var previewDropTargetID: UUID?
    @State private var initialSnapshot: QuickEditSnapshot?
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
    @State private var pendingGroupDeleteFinalConfirmation: UUID?
    @State private var taskEditorDraft: QuickEditTaskEditorDraft?
    @State private var previewEditingTarget: QuickEditPreviewEditingTarget?
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue

    typealias PreviewSlot = QuickEditPreviewSlot

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var quickEditSectionFlatBackground: Color { NeumorphicColors.innerSurface }
    private var quickEditTaskFlatBackground: Color { NeumorphicColors.background.opacity(0.96) }
    private var quickEditSelectedBadgeBackground: Color { NeumorphicColors.accent.opacity(0.14) }
    private var quickEditFieldStroke: Color { NeumorphicColors.text.opacity(0.06) }
    private var quickEditPlaceholderColor: Color { NeumorphicColors.text.opacity(0.34) }
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var previewEmptySlotFill: Color { activeTheme.bingoSurfaceColor.opacity(0.16) }
    private var previewFilledSlotFill: Color { activeTheme.bingoSurfaceColor.opacity(0.44) }
    private var previewEmptySlotStroke: Color { activeTheme.bingoSurfaceShadowColor.opacity(0.44) }
    private var previewFilledSlotStroke: Color { activeTheme.bingoSurfaceShadowColor.opacity(0.66) }

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
        isPremiumUser || library.tasks.count < AppSettings.maxCommonTasks
    }

    private var canAddGroup: Bool {
        isPremiumUser || library.groups.count < AppSettings.maxTaskGroups
    }

    private func canAddTask(to group: MyTaskGroup) -> Bool {
        isPremiumUser || group.tasks.count < AppSettings.maxTasksPerGroup
    }

    private var maxGridSizeForCurrentPlan: Int {
        isPremiumUser ? 5 : 4
    }

    private func taskKey(for task: MyTaskItem) -> String {
        quickEditTaskKey(task)
    }

    private func historyTaskKey(for record: TaskHistoryRecord) -> String {
        quickEditHistoryTaskKey(record)
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
        previewSlots.compactMap(\.task).count
    }

    private var selectedCountSummary: String {
        L10n.quickEditSelectedCount(selected: selectedPreviewCount, total: totalGridSlots)
    }

    private var activeFilterTitle: String {
        switch activeFilter {
        case .all:
            return L10n.allTasks
        case .group(let groupID):
            guard let group = library.groups.first(where: { $0.id == groupID }) else {
                return L10n.allTasks
            }
            return quickEditDisplayGroupName(group)
        }
    }

    private var activeGroupID: UUID? {
        if case .group(let groupID) = activeFilter {
            return groupID
        }
        return nil
    }

    private var activeGroupTasks: [MyTaskItem] {
        guard case .group(let groupID) = activeFilter,
              let group = library.groups.first(where: { $0.id == groupID }) else {
            return []
        }
        return group.tasks.filter { !$0.trimmedText.isEmpty }
    }

    private var activeGroupTaskKeys: [String] {
        activeGroupTasks.map(taskKey(for:))
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
            targetGridSize = viewModel.gridSize
            activeFilter = .all
            previewSlots = buildInitialPreviewSlots()
            selectedTaskKeys = []
            seedTaskHistoryIfNeeded()
            initialSnapshot = makeCurrentSnapshot()
            syncActiveFilterWithCurrentLibrary()
        }
        .onChange(of: library) { _, _ in
            TaskHistoryStore.ensureLibrarySeeded(library)
            refreshTaskHistory()
            syncSelectedTaskKeysWithCurrentLibrary()
            syncPreviewSlotsWithCurrentLibrary()
            syncActiveFilterWithCurrentLibrary()
        }
        .onChange(of: targetGridSize) { _, _ in
            adjustPreviewSlotCount()
        }
        .fullScreenCover(isPresented: $isPremiumPaywallPresented) {
            PremiumPaywallView(entrySource: premiumPaywallSource)
        }
        .fullScreenCover(item: $previewEditingTarget) { target in
            previewEditTaskSheet(for: target.slotID)
                .background(Color.clear)
                .presentationBackground(.clear)
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
            Text(deleteMessage(for: target))
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
            let name = pendingGroupDeleteFinalConfirmation.map(groupName(for:)) ?? L10n.groupDefaultName
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
            if isPremiumUser {
                quickEditBottomAddTaskBar
            }
        }
    }

    private var quickEditNavigationContent: some View {
        ZStack {
            quickEditBackground
            quickEditMainScroll
            quickEditToastOverlay
            quickEditModalOverlays
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
        .toolbar {
            quickEditToolbarContent
        }
    }

    private var quickEditBackground: some View {
        NeumorphicColors.background
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
    }

    private var quickEditMainScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                quickEditControlsCard
                filterTabsSection
                    .padding(.top, -10)
                taskListSection
            }
            .frame(maxWidth: isPadLayout ? 760 : .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var quickEditToastOverlay: some View {
        if isLocalToastVisible, let localToastMessage {
            VStack {
                Text(localToastMessage)
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(quickEditToastBackground)
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.12), radius: 8, x: 0, y: 4)
                    .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
                Spacer()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var quickEditToastBackground: some View {
        Capsule(style: .continuous)
            .fill(NeumorphicColors.accent.opacity(0.92))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var quickEditModalOverlays: some View {
        if isAddingGroupModalPresented {
            addGroupModal
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
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

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()

            Button(L10n.done) {
                focusedField = nil
            }
            .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(NeumorphicColors.accent)
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
                deleteConfirmationTarget = .group(groupID)
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
                    focusedField = nil
                    deleteConfirmationTarget = .group(groupID)
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
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
        .background(NeumorphicColors.background.opacity(0.96))
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
        QuickEditAddGroupModal(
            groupName: $newGroupNameDraft,
            focusedField: $focusedField,
            isPadLayout: isPadLayout,
            placeholderColor: quickEditPlaceholderColor,
            taskBackground: quickEditTaskFlatBackground,
            fieldStroke: quickEditFieldStroke,
            onDismiss: dismissAddGroupModal,
            onCommit: commitAddGroup
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
        taskEditorDraft = QuickEditTaskEditorDraft(
            mode: .edit(location),
            text: currentTask.text,
            startMonthText: currentTask.startMonth.map(String.init) ?? "",
            startDayText: currentTask.startDay.map(String.init) ?? ""
        )

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
                startVisibleAt: currentCell.startVisibleAt,
                endVisibleAt: currentCell.endVisibleAt,
                isCompletedTask: currentCell.isCompleted,
                estimatedDurationMinutes: quickEditRemainingMinutes(from: currentCell.countdownEndsAt),
                onSave: { newText, isForcedTask, residentWeekdays, isOneTimeTask, estimatedDurationMinutes, startVisibleAt, endVisibleAt in
                    guard let latestIndex = previewSlots.firstIndex(where: { $0.id == slotID }) else {
                        previewEditingTarget = nil
                        return
                    }

                    let existingCell = previewSlots[latestIndex].cellState
                    previewSlots[latestIndex].cellState = quickEditMakePreviewCellFromEdit(
                        existingCell: existingCell,
                        text: newText,
                        isForcedTask: isForcedTask,
                        residentWeekdays: residentWeekdays,
                        isOneTimeTask: isOneTimeTask,
                        estimatedDurationMinutes: estimatedDurationMinutes,
                        startVisibleAt: startVisibleAt,
                        endVisibleAt: endVisibleAt
                    )

                    if let sourceTaskKey = previewSlots[latestIndex].sourceTaskKey {
                        let syncedTask = previewSlots[latestIndex].task ?? MyTaskItem(text: "")
                        syncLibraryTask(forTaskKey: sourceTaskKey, with: syncedTask)
                    }
                    previewEditingTarget = nil
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
        let normalizedName = draft.normalizedName
        guard draft.canSave else { return }

        let (startMonth, startDay) = quickEditNormalizedMonthDay(
            monthText: draft.startMonthText,
            dayText: draft.startDayText
        )

        switch draft.mode {
        case .edit(let location):
            guard var existingTask = task(for: location) else {
                dismissTaskEditor()
                return
            }
            existingTask.text = normalizedName
            existingTask.startMonth = startMonth
            existingTask.startDay = startDay
            existingTask.normalizeStartDate()
            setTask(existingTask, for: location)
            recordTaskHistory(existingTask, sourceTaskID: existingTask.id)
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
              var existingTask = task(for: location) else { return }
        existingTask.text = newTask.trimmedText
        existingTask.startMonth = newTask.startMonth
        existingTask.startDay = newTask.startDay
        existingTask.normalizeStartDate()
        setTask(existingTask, for: location)
        recordTaskHistory(existingTask, sourceTaskID: existingTask.id)
    }

    private func taskLocation(forTaskKey key: String) -> QuickEditTaskLocation? {
        quickEditTaskLocation(forTaskKey: key, in: library)
    }

    private func syncActiveFilterWithCurrentLibrary() {
        switch activeFilter {
        case .all:
            return
        case .group(let groupID):
            if !library.groups.contains(where: { $0.id == groupID }) {
                activeFilter = .all
            }
        }
    }

    private func refreshTaskHistory() {
        taskHistoryRecords = TaskHistoryStore.load()
    }

    private func seedTaskHistoryIfNeeded() {
        TaskHistoryStore.ensureLibrarySeeded(library)
        seedBoardTasksIntoHistory()
        backfillLegacyTaskHistoryIfNeeded()
        refreshTaskHistory()
    }

    private func recordTaskHistory(_ task: MyTaskItem, sourceTaskID: UUID? = nil) {
        guard !task.trimmedText.isEmpty else { return }
        TaskHistoryStore.upsert(task: task, sourceTaskID: sourceTaskID)
        refreshTaskHistory()
    }

    private func seedBoardTasksIntoHistory() {
        let boardTasks = viewModel.currentBoardTasksInRowMajor(size: BingoViewModel.maxGridSize).compactMap { $0 }
        guard !boardTasks.isEmpty else { return }
        TaskHistoryStore.upsertBoardTasks(boardTasks)
    }

    private func backfillLegacyTaskHistoryIfNeeded() {
        guard taskHistoryRecords.isEmpty else { return }

        var insertedAny = false
        let now = Date()

        for entry in BingoDiaryStore.loadAllEntriesDictionary().values {
            for task in entry.completedTaskCounts.keys {
                let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                TaskHistoryStore.upsert(task: MyTaskItem(text: trimmed), at: entry.date)
                insertedAny = true
            }

            for cell in entry.board.cells.flatMap({ $0 }) {
                let trimmed = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                TaskHistoryStore.upsert(
                    task: MyTaskItem(
                        text: trimmed,
                        startMonth: cell.startVisibleMonth,
                        startDay: cell.startVisibleDay
                    ),
                    at: entry.date
                )
                insertedAny = true
            }
        }

        for (dateKey, tasks) in BingoTimeoutStore.loadAllPayload() {
            let date = quickEditParseDateKey(dateKey) ?? now
            for task in tasks.keys {
                let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                TaskHistoryStore.upsert(task: MyTaskItem(text: trimmed), at: date)
                insertedAny = true
            }
        }

        if insertedAny {
            taskHistoryRecords = TaskHistoryStore.load()
        }
    }

    private func startAddingTaskInline() {
        if case .group(let groupID) = activeFilter,
           let group = library.groups.first(where: { $0.id == groupID }) {
            guard canAddTask(to: group) else {
                presentPremiumPaywallForLimit(source: "group_task_limit_inline")
                return
            }
        } else {
            guard canAddStandaloneTask else {
                presentPremiumPaywallForLimit(source: "standalone_task_limit_inline")
                return
            }
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
        let text = String(newTaskDraft.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let (startMonth, startDay) = quickEditNormalizedMonthDay(monthText: newTaskStartMonthDraft, dayText: newTaskStartDayDraft)
        let task = MyTaskItem(text: text, startMonth: startMonth, startDay: startDay)

        switch activeFilter {
        case .all:
            guard canAddStandaloneTask else {
                presentPremiumPaywallForLimit(source: "standalone_task_limit_commit")
                return
            }
            library.tasks.append(task)
            recordTaskHistory(task, sourceTaskID: task.id)
        case .group(let groupID):
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else {
                activeFilter = .all
                return
            }
            guard canAddTask(to: library.groups[groupIndex]) else {
                presentPremiumPaywallForLimit(source: "group_task_limit_commit")
                return
            }
            library.groups[groupIndex].tasks.append(task)
            recordTaskHistory(task, sourceTaskID: task.id)
        }

        isAddingTaskInline = false
        newTaskDraft = ""
        newTaskStartMonthDraft = ""
        newTaskStartDayDraft = ""
        focusedField = nil
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

    private func commitAddGroup() {
        guard canAddGroup else {
            presentPremiumPaywallForLimit(source: "group_limit_commit")
            return
        }

        let trimmedName = String(newGroupNameDraft.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let group = MyTaskGroup(name: trimmedName, tasks: [])
        library.groups.append(group)
        activeFilter = .group(group.id)
        dismissAddGroupModal()
    }

    private func taskBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard library.tasks.indices.contains(index) else { return "" }
                return library.tasks[index].text
            },
            set: { newValue in
                guard library.tasks.indices.contains(index) else { return }
                library.tasks[index].text = String(newValue.prefix(AppSettings.maxTaskLength))
                recordTaskHistory(library.tasks[index], sourceTaskID: library.tasks[index].id)
            }
        )
    }

    private func groupTaskBinding(groupID: UUID, index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return "" }
                return library.groups[groupIndex].tasks[index].text
            },
            set: { newValue in
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return }
                library.groups[groupIndex].tasks[index].text = String(newValue.prefix(AppSettings.maxTaskLength))
                recordTaskHistory(
                    library.groups[groupIndex].tasks[index],
                    sourceTaskID: library.groups[groupIndex].tasks[index].id
                )
            }
        )
    }

    private func toggleSelection(for key: String) {
        if let index = selectedTaskKeys.firstIndex(of: key) {
            selectedTaskKeys.remove(at: index)
            removePreviewTask(for: key)
        } else {
            guard addPreviewTask(for: key) else {
                showLocalToast(
                    L10n.tr(
                        "Preview board is full.",
                        zhHans: "预览棋盘已满。",
                        zhHant: "預覽棋盤已滿。"
                    )
                )
                return
            }
            selectedTaskKeys.append(key)
        }
    }

    private func applyActiveGroupToPreview() {
        guard !activeGroupTaskKeys.isEmpty else { return }
        focusedField = nil
        selectedTaskKeys = activeGroupTaskKeys
        rebuildPreviewFromSelectedKeys()
        showLocalToast(L10n.quickEditGroupAppliedToPreview)
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
        guard let initialSnapshot else { return false }
        return makeCurrentSnapshot() != initialSnapshot
    }

    private func makeCurrentSnapshot() -> QuickEditSnapshot {
        let previewItems = previewSlots.map { slot in
            QuickEditSnapshot.PreviewItem(
                cellState: slot.cellState,
                sourceTaskKey: slot.sourceTaskKey
            )
        }

        return QuickEditSnapshot(
            targetGridSize: targetGridSize,
            selectedTaskKeys: selectedTaskKeys,
            previewItems: previewItems,
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
        let orderedCells = previewSlots.map(\.cellState)
        viewModel.applyBoardOrderedCells(orderedCells, targetGridSize: plan.targetGridSize)
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
        if previewSlots.isEmpty {
            previewSlots = buildInitialPreviewSlots()
            return
        }

        if previewSlots.count > totalGridSlots {
            previewSlots = Array(previewSlots.prefix(totalGridSlots))
        } else if previewSlots.count < totalGridSlots {
            previewSlots.append(contentsOf: quickEditEmptyPreviewSlots(count: totalGridSlots - previewSlots.count))
        }
    }

    private func addPreviewTask(for key: String) -> Bool {
        guard let task = candidateTaskMap[key], task.isStartDateReached() else { return false }

        if let existingIndex = previewSlots.firstIndex(where: { $0.sourceTaskKey == key }) {
            previewSlots[existingIndex].cellState = quickEditMakePreviewCell(from: task, preserving: previewSlots[existingIndex].cellState)
            return true
        }

        guard let emptyIndex = previewSlots.firstIndex(where: { $0.task == nil }) else {
            return false
        }

        previewSlots[emptyIndex].cellState = quickEditMakePreviewCell(from: task)
        previewSlots[emptyIndex].sourceTaskKey = key
        return true
    }

    private func removePreviewTask(for key: String) {
        guard let index = previewSlots.firstIndex(where: { $0.sourceTaskKey == key }) else { return }
        previewSlots[index].cellState = nil
        previewSlots[index].sourceTaskKey = nil
    }

    private func rebuildPreviewFromSelectedKeys() {
        let activeTasks = selectedTaskKeys.compactMap { key -> PreviewSlot? in
            guard let task = candidateTaskMap[key], task.isStartDateReached() else { return nil }
            return PreviewSlot(cellState: quickEditMakePreviewCell(from: task), sourceTaskKey: key)
        }

        previewSlots = Array(activeTasks.prefix(totalGridSlots))
        if previewSlots.count < totalGridSlots {
            previewSlots.append(contentsOf: quickEditEmptyPreviewSlots(count: totalGridSlots - previewSlots.count))
        }
    }

    private func syncPreviewSlotsWithCurrentLibrary() {
        guard !previewSlots.isEmpty else { return }

        for index in previewSlots.indices {
            guard let sourceTaskKey = previewSlots[index].sourceTaskKey else { continue }

            guard let task = candidateTaskMap[sourceTaskKey],
                  !task.trimmedText.isEmpty,
                  task.isStartDateReached() else {
                previewSlots[index].cellState = nil
                previewSlots[index].sourceTaskKey = nil
                continue
            }

            previewSlots[index].cellState = quickEditMakePreviewCell(from: task, preserving: previewSlots[index].cellState)
        }
        adjustPreviewSlotCount()
    }

    private func clearPreviewDragState() {
        previewDragSourceID = nil
        previewDropTargetID = nil
    }

    private func finalizeLibrary(showSuccessToast: Bool = false, emitChangeToast: Bool = true) {
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
        AnalyticsService.logPremiumTasksGroupsLimitHit(
            source: source,
            taskCount: library.tasks.count,
            groupCount: library.groups.count,
            groupTaskCount: library.groups.reduce(0) { $0 + $1.tasks.count }
        )
        openPremiumPaywall(source: source)
    }

    private func openPremiumPaywall(source: String) {
        premiumPaywallSource = source
        focusedField = nil
        Task { @MainActor in
            isPremiumPaywallPresented = true
            await subscriptionManager.warmupProductsForPaywall()
        }
    }
private func confirmDelete(_ target: QuickEditDeleteTarget) {
    switch target {
    case .task(let index):
        guard library.tasks.indices.contains(index) else { return }
        let task = library.tasks[index]
        recordTaskHistory(task, sourceTaskID: task.id)
        library.tasks.remove(at: index)
        showLocalToast(target.successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    case .group(let groupID):
        deleteConfirmationTarget = nil
        focusedField = nil
        pendingGroupDeleteFinalConfirmation = groupID
    case .groupTask(let groupID, let index):
        guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
              library.groups[groupIndex].tasks.indices.contains(index) else { return }
        let task = library.groups[groupIndex].tasks[index]
        recordTaskHistory(task, sourceTaskID: task.id)
        library.groups[groupIndex].tasks.remove(at: index)
        showLocalToast(target.successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    case .history(let historyItemID):
        let prefix = "history:"
        guard historyItemID.hasPrefix(prefix) else {
            deleteConfirmationTarget = nil
            focusedField = nil
            return
        }
        let historyKey = String(historyItemID.dropFirst(prefix.count))
        TaskHistoryStore.deleteRecord(withKey: historyKey)
        selectedTaskKeys.removeAll(where: { $0 == historyItemID })
        removePreviewTask(for: historyItemID)
        refreshTaskHistory()
        showLocalToast(target.successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    }
}

private func finalizeGroupDeletion(_ groupID: UUID) {
    guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else {
        pendingGroupDeleteFinalConfirmation = nil
        return
    }

    for task in library.groups[groupIndex].tasks where !task.trimmedText.isEmpty {
        recordTaskHistory(task, sourceTaskID: task.id)
    }

    library.groups.remove(at: groupIndex)
    if activeFilter == .group(groupID) {
        activeFilter = .all
    }

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

private func deleteMessage(for target: QuickEditDeleteTarget) -> String {
    switch target {
    case .groupTask(let groupID, _):
        let name = groupName(for: groupID)
        return L10n.tr(
            "This task will be removed from \(name).",
            zhHans: "该任务将从「\(name)」中移除。",
            zhHant: "該任務將從「\(name)」中移除。"
        )
    default:
        return target.message
    }
}

private func groupName(for groupID: UUID) -> String {
    guard let group = library.groups.first(where: { $0.id == groupID }) else {
        return L10n.groupDefaultName
    }
    return quickEditDisplayGroupName(group)
}

    private func sectionHeader(title: String, subtitle: String, detail: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: subtitle.isEmpty ? 0 : 4) {
                Text(detail.isEmpty ? title : "\(title) (\(detail))")
                    .font(.appSystem(size: scaled(15, pad: 19), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.appSystem(size: scaled(12, pad: 16), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.56))
                }
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.appSystem(size: scaled(11, pad: 14), weight: .bold))
                        Text(actionTitle)
                            .font(.appSystem(size: scaled(13, pad: 18), weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(NeumorphicColors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.clear.neumorphicConvex(radius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func flatSectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(isPadLayout ? 22 : 18)
            .background(
                RoundedRectangle(cornerRadius: isPadLayout ? 30 : 26, style: .continuous)
                    .fill(quickEditSectionFlatBackground)
            )
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(isPadLayout ? 22 : 18)
            .background(Color.clear.neumorphicConcave(radius: isPadLayout ? 30 : 26))
    }

    private func emptyStateCard(title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 22), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Text(message)
                .font(.appSystem(size: scaled(13, pad: 17), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.appSystem(size: scaled(12, pad: 14), weight: .bold))
                    Text(actionTitle)
                        .font(.appSystem(size: scaled(14, pad: 18), weight: .semibold, design: .rounded))
                }
                .foregroundColor(NeumorphicColors.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.clear.neumorphicConvex(radius: 18))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isPadLayout ? 22 : 18)
        .background(Color.clear.neumorphicConvex(radius: 24))
    }
}
