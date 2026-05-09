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
    @State private var deleteConfirmationTarget: DeleteTarget?
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
    @State private var pendingApplyPlan: ApplyPlan?
    @State private var isPremiumPaywallPresented = false
    @State private var premiumPaywallSource = "quick_edit"
    @State private var activeFilter: FilterTab = .all
    @State private var isAddingTaskInline = false
    @State private var newTaskDraft = ""
    @State private var newTaskStartMonthDraft = ""
    @State private var newTaskStartDayDraft = ""
    @State private var isAddingGroupModalPresented = false
    @State private var newGroupNameDraft = ""
    @State private var pendingGroupDeleteFinalConfirmation: UUID?
    @State private var taskEditorDraft: TaskEditorDraft?
    @State private var previewEditingTarget: PreviewEditingTarget?
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue

    private enum DeleteTarget: Equatable {
        case task(Int)
        case group(UUID)
        case groupTask(UUID, Int)
        case history(String)

        var title: String {
            L10n.deleteConfirmationTitle
        }

        var message: String {
            switch self {
            case .task:
                return L10n.deleteTaskConfirmationMessage
            case .groupTask:
                return L10n.deleteTaskConfirmationMessage
            case .history:
                return L10n.deleteTaskConfirmationMessage
            case .group:
                return L10n.deleteGroupConfirmationMessage
            }
        }

        var successMessage: String {
            switch self {
            case .task:
                return L10n.taskDeletedSuccess
            case .groupTask:
                return L10n.taskDeletedSuccess
            case .history:
                return L10n.taskDeletedSuccess
            case .group:
                return L10n.groupDeletedSuccess
            }
        }
    }

    private struct TaskCandidate: Identifiable {
        let id: String
        let task: MyTaskItem
    }

    private struct TaskEditorDraft: Identifiable, Equatable {
        enum Mode: Equatable {
            case createStandalone
            case createGroup(UUID)
            case edit(TaskLocation)
        }

        let id = UUID()
        let mode: Mode
        var text: String
        var startMonthText: String
        var startDayText: String

        var normalizedName: String {
            String(text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var canSave: Bool {
            !normalizedName.isEmpty
        }
    }

    private enum FilterTab: Equatable {
        case all
        case group(UUID)
    }

    private enum TaskLocation: Hashable {
        case standalone(Int)
        case group(UUID, Int)
    }

    private enum FilteredTaskSource: Equatable {
        case library(TaskLocation)
        case history
    }

    private struct FilteredTaskItem: Identifiable {
        let id: String
        let source: FilteredTaskSource
        let task: MyTaskItem
        let operationDate: Date
        let isLocked: Bool
    }

    struct PreviewSlot: Identifiable, Equatable {
        let id: UUID
        var cellState: BingoCell?
        var sourceTaskKey: String?

        init(id: UUID = UUID(), cellState: BingoCell? = nil, sourceTaskKey: String? = nil) {
            self.id = id
            self.cellState = cellState
            self.sourceTaskKey = sourceTaskKey
        }

        var task: MyTaskItem? {
            guard let cellState else { return nil }
            let text = cellState.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MyTaskItem(
                text: text,
                startMonth: cellState.startVisibleMonth,
                startDay: cellState.startVisibleDay
            )
        }
    }

    private struct QuickEditSnapshot: Equatable {
        struct PreviewItem: Equatable {
            let cellState: BingoCell?
            let sourceTaskKey: String?
        }

        let targetGridSize: Int
        let selectedTaskKeys: [String]
        let previewItems: [PreviewItem]
        let library: MyTasksLibrary
    }

    private struct ApplyPlan: Equatable {
        let tasks: [MyTaskItem]
        let targetGridSize: Int
    }

    private struct PreviewEditingTarget: Identifiable, Equatable {
        let slotID: UUID
        var id: UUID { slotID }
    }

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
        task.id.uuidString
    }

    private func historyTaskKey(for record: TaskHistoryRecord) -> String {
        "history:\(record.key)"
    }

    private var libraryTaskIDs: Set<UUID> {
        Set(library.tasks.map(\.id) + library.groups.flatMap { $0.tasks.map(\.id) })
    }

    private var historyBySourceTaskID: [UUID: TaskHistoryRecord] {
        var result: [UUID: TaskHistoryRecord] = [:]
        for record in taskHistoryRecords {
            guard let sourceTaskID = record.sourceTaskID else { continue }
            if let existing = result[sourceTaskID], existing.lastEditedAt >= record.lastEditedAt {
                continue
            }
            result[sourceTaskID] = record
        }
        return result
    }

    private var historyOnlyRecordsSorted: [TaskHistoryRecord] {
        taskHistoryRecords
            .filter { record in
                guard !record.trimmedText.isEmpty else { return false }
                guard let sourceTaskID = record.sourceTaskID else { return true }
                return !libraryTaskIDs.contains(sourceTaskID)
            }
            .sorted { lhs, rhs in
                if lhs.lastEditedAt != rhs.lastEditedAt {
                    return lhs.lastEditedAt > rhs.lastEditedAt
                }
                return lhs.key < rhs.key
            }
    }

    private var unlockedHistoryRecords: [TaskHistoryRecord] {
        guard !isPremiumUser else { return historyOnlyRecordsSorted }
        return Array(historyOnlyRecordsSorted.prefix(AppSettings.freeHistoryTasksVisibleCount))
    }

    private var allTaskCandidates: [TaskCandidate] {
        var candidates: [TaskCandidate] = []
        var seenIDs = Set<String>()

        for index in library.tasks.indices {
            let task = library.tasks[index]
            guard !task.trimmedText.isEmpty else { continue }
            let key = taskKey(for: task)
            guard !seenIDs.contains(key) else { continue }
            candidates.append(TaskCandidate(id: key, task: task))
            seenIDs.insert(key)
        }

        for group in library.groups {
            for index in group.tasks.indices {
                let task = group.tasks[index]
                guard !task.trimmedText.isEmpty else { continue }
                let key = taskKey(for: task)
                guard !seenIDs.contains(key) else { continue }
                candidates.append(TaskCandidate(id: key, task: task))
                seenIDs.insert(key)
            }
        }

        for record in unlockedHistoryRecords {
            let key = historyTaskKey(for: record)
            guard !seenIDs.contains(key) else { continue }
            candidates.append(
                TaskCandidate(
                    id: key,
                    task: MyTaskItem(
                        text: record.trimmedText,
                        startMonth: record.startMonth,
                        startDay: record.startDay
                    )
                )
            )
            seenIDs.insert(key)
        }

        return candidates
    }

    private var filteredTaskItems: [FilteredTaskItem] {
        switch activeFilter {
        case .all:
            var items: [FilteredTaskItem] = library.tasks.indices.compactMap { index in
                let task = library.tasks[index]
                guard !task.trimmedText.isEmpty else { return nil }
                let operationDate = historyBySourceTaskID[task.id]?.lastEditedAt ?? .distantPast
                return FilteredTaskItem(
                    id: taskKey(for: task),
                    source: .library(.standalone(index)),
                    task: task,
                    operationDate: operationDate,
                    isLocked: false
                )
            }

            for group in library.groups {
                items.append(contentsOf: group.tasks.indices.compactMap { index in
                    let task = group.tasks[index]
                    guard !task.trimmedText.isEmpty else { return nil }
                    let operationDate = historyBySourceTaskID[task.id]?.lastEditedAt ?? .distantPast
                    return FilteredTaskItem(
                        id: taskKey(for: task),
                        source: .library(.group(group.id, index)),
                        task: task,
                        operationDate: operationDate,
                        isLocked: false
                    )
                })
            }

            let historyItems = historyOnlyRecordsSorted.enumerated().map { index, record in
                let isLocked = !isPremiumUser && index >= AppSettings.freeHistoryTasksVisibleCount
                return FilteredTaskItem(
                    id: historyTaskKey(for: record),
                    source: .history,
                    task: MyTaskItem(
                        text: record.trimmedText,
                        startMonth: record.startMonth,
                        startDay: record.startDay
                    ),
                    operationDate: record.lastEditedAt,
                    isLocked: isLocked
                )
            }
            items.append(contentsOf: historyItems)

            return items.sorted { lhs, rhs in
                if lhs.operationDate != rhs.operationDate {
                    return lhs.operationDate > rhs.operationDate
                }
                return lhs.id < rhs.id
            }
        case .group(let groupID):
            guard let group = library.groups.first(where: { $0.id == groupID }) else { return [] }
            return group.tasks.indices.compactMap { index in
                let task = group.tasks[index]
                guard !task.trimmedText.isEmpty else { return nil }
                let operationDate = historyBySourceTaskID[task.id]?.lastEditedAt ?? .distantPast
                return FilteredTaskItem(
                    id: taskKey(for: task),
                    source: .library(.group(groupID, index)),
                    task: task,
                    operationDate: operationDate,
                    isLocked: false
                )
            }
        }
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
        return displayGroupName(group)
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
                previewEditingTarget = PreviewEditingTarget(slotID: slotID)
            },
            onDeleteSlot: { slotID in
                deletePreviewTask(slotID: slotID)
            },
            onClearPreviewDrag: clearPreviewDragState
        )
    }

    private var filterTabsSection: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterTabButton(
                        title: L10n.allTasks,
                        isSelected: activeFilter == .all
                    ) {
                        activeFilter = .all
                    }

                    ForEach(library.groups) { group in
                        filterTabButton(
                            title: displayGroupName(group),
                            isSelected: activeFilter == .group(group.id)
                        ) {
                            activeFilter = .group(group.id)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.8)
                                .onEnded { _ in
                                    focusedField = nil
                                    deleteConfirmationTarget = .group(group.id)
                                }
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                presentAddGroupModal()
            } label: {
                Text("+ \(L10n.addGroup)")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.clear.neumorphicConvex(radius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private func filterTabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : NeumorphicColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? NeumorphicColors.accent : NeumorphicColors.background)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? NeumorphicColors.accent : quickEditFieldStroke,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

private var taskListSection: some View {
    flatSectionCard {
        let visibleItems = filteredTaskItems.filter { !$0.isLocked }
        let lockedHistoryPreviewItems = Array(
            filteredTaskItems
                .filter { $0.isLocked && $0.source == .history }
                .prefix(5)
        )
        let isAllTasksFilter = activeFilter == .all

        VStack(alignment: .leading, spacing: isAllTasksFilter ? 8 : 12) {
            if !isAllTasksFilter {
                HStack(spacing: 10) {
                    Text(activeFilterTitle)
                        .font(.appSystem(size: scaled(15, pad: 19), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Spacer(minLength: 0)

                    if let activeGroupID {
                        Button {
                            applyActiveGroupToPreview()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.appSystem(size: scaled(11, pad: 13), weight: .semibold))
                                Text(L10n.quickEditApplyGroup)
                                    .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(NeumorphicColors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(quickEditTaskFlatBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(NeumorphicColors.accent.opacity(0.28), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(activeGroupTaskKeys.isEmpty)
                        .opacity(activeGroupTaskKeys.isEmpty ? 0.45 : 1)

                        Button {
                            focusedField = nil
                            deleteConfirmationTarget = .group(activeGroupID)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.appSystem(size: scaled(11, pad: 13), weight: .semibold))
                                Text(L10n.tr("Delete Group", zhHans: "删除分组", zhHant: "刪除分組"))
                                    .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(NeumorphicColors.bingoAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(quickEditTaskFlatBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(NeumorphicColors.bingoAccent.opacity(0.28), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isAllTasksFilter {
                Text(
                    L10n.tr(
                        "You can view and edit all your task history here.",
                        zhHans: "在这里可以查看并编辑你所有的历史任务",
                        zhHant: "在這裡可以查看並編輯你所有的歷史任務"
                    )
                )
                .font(.appSystem(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
                .padding(.top, 2)
                .padding(.bottom, 4)
            }

            if visibleItems.isEmpty && !isAddingTaskInline && lockedHistoryPreviewItems.isEmpty {
                Text(L10n.quickEditNoTasksInFilter)
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.56))
                    .padding(.vertical, 8)
            }

            VStack(spacing: 10) {
                ForEach(visibleItems) { item in
                    taskRow(for: item)
                }

                if !lockedHistoryPreviewItems.isEmpty {
                    lockedHistoryPreviewBlock(items: lockedHistoryPreviewItems)
                }

                if isAddingTaskInline {
                    newTaskInlineRow
                }
            }

            if activeGroupID != nil {
                addTaskButton
                    .padding(.top, 8)
            }
        }
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

    private func lockedHistoryPreviewBlock(items: [FilteredTaskItem]) -> some View {
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
    private func taskRow(for item: FilteredTaskItem) -> some View {
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

    private func editableLibraryTaskRow(for item: FilteredTaskItem, location: TaskLocation) -> some View {
        let key = item.id
        let isSelected = selectedTaskKeys.contains(key)

        return HStack(spacing: 10) {
            Button {
                toggleSelection(for: key)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                    .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.38))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            TextField(
                text: taskBinding(for: location),
                prompt: Text(placeholder(for: location))
                    .foregroundColor(quickEditPlaceholderColor)
            ) {
                EmptyView()
            }
            .textInputAutocapitalization(.sentences)
            .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text)
            .lineLimit(1)
            .focused($focusedField, equals: focusedField(for: location))

            Button {
                focusedField = nil
                deleteConfirmationTarget = deleteTarget(for: location)
            } label: {
                Image(systemName: "trash")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .medium))
                    .foregroundColor(NeumorphicColors.text.opacity(0.52))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(quickEditTaskFlatBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(quickEditFieldStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func readOnlyHistoryTaskRow(for item: FilteredTaskItem) -> some View {
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

    private func lockedHistoryTaskRow(for item: FilteredTaskItem) -> some View {
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
    HStack(spacing: 10) {
        TextField(
            "",
            text: $newTaskDraft,
            prompt: Text(L10n.quickEditTaskNamePlaceholder)
                .foregroundColor(quickEditPlaceholderColor)
        )
        .textInputAutocapitalization(.sentences)
        .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
        .foregroundColor(NeumorphicColors.text)
        .focused($focusedField, equals: .newTask)
        .onSubmit {
            commitAddingTaskInline()
        }

        Button(L10n.save) {
            commitAddingTaskInline()
        }
        .font(.appSystem(size: scaled(12, pad: 14), weight: .bold, design: .rounded))
        .foregroundColor(NeumorphicColors.accent)
        .buttonStyle(.plain)
        .disabled(newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

        Button(L10n.cancel) {
            cancelAddingTaskInline()
        }
        .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
        .foregroundColor(NeumorphicColors.text.opacity(0.62))
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 50)
    .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(quickEditTaskFlatBackground)
    )
    .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(NeumorphicColors.accent.opacity(0.45), lineWidth: 1)
            .allowsHitTesting(false)
    }
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

    private func taskBinding(for location: TaskLocation) -> Binding<String> {
        switch location {
        case .standalone(let index):
            return taskBinding(for: index)
        case .group(let groupID, let index):
            return groupTaskBinding(groupID: groupID, index: index)
        }
    }

    private func focusedField(for location: TaskLocation) -> FocusedMyTaskField {
        switch location {
        case .standalone(let index):
            return .task(index)
        case .group(let groupID, let index):
            return .groupTask(groupID, index)
        }
    }

    private func placeholder(for location: TaskLocation) -> String {
        switch location {
        case .standalone(let index):
            return L10n.taskNumber(index + 1)
        case .group:
            return L10n.task
        }
    }

    private func deleteTarget(for location: TaskLocation) -> DeleteTarget {
        switch location {
        case .standalone(let index):
            return .task(index)
        case .group(let groupID, let index):
            return .groupTask(groupID, index)
        }
    }

    private func task(for location: TaskLocation) -> MyTaskItem? {
        switch location {
        case .standalone(let index):
            guard library.tasks.indices.contains(index) else { return nil }
            return library.tasks[index]
        case .group(let groupID, let index):
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                  library.groups[groupIndex].tasks.indices.contains(index) else { return nil }
            return library.groups[groupIndex].tasks[index]
        }
    }

    private func setTask(_ task: MyTaskItem, for location: TaskLocation) {
        switch location {
        case .standalone(let index):
            guard library.tasks.indices.contains(index) else { return }
            library.tasks[index] = task
        case .group(let groupID, let index):
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                  library.groups[groupIndex].tasks.indices.contains(index) else { return }
            library.groups[groupIndex].tasks[index] = task
        }
    }

    private func taskStartDateLabel(for location: TaskLocation) -> String {
        guard let task = task(for: location),
              let month = task.startMonth,
              let day = task.startDay else {
            return L10n.quickEditTaskNoStartDate
        }
        return "\(month)/\(day)"
    }

    private func normalizedMonthDay(monthText: String, dayText: String) -> (Int?, Int?) {
        let trimmedMonth = monthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDay = dayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMonth.isEmpty || !trimmedDay.isEmpty else {
            return (nil, nil)
        }

        guard let month = Int(trimmedMonth), let day = Int(trimmedDay) else {
            return (nil, nil)
        }

        guard (1...12).contains(month), (1...31).contains(day) else {
            return (nil, nil)
        }

        var components = DateComponents()
        components.year = 2000
        components.month = month
        components.day = day
        guard Calendar.current.date(from: components) != nil else {
            return (nil, nil)
        }

        return (month, day)
    }

    private func makePreviewCell(from task: MyTaskItem, preserving existingCell: BingoCell? = nil) -> BingoCell {
        var taskCopy = task
        taskCopy.text = String(task.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        taskCopy.normalizeVisibilityWindow()

        guard let existingCell else {
            return BingoCell(
                text: taskCopy.trimmedText,
                residentTaskText: nil,
                residentWeekdays: [],
                oneTimeVisibleDate: nil,
                startVisibleAt: taskCopy.startAt,
                endVisibleAt: taskCopy.endAt,
                startVisibleMonth: taskCopy.startMonth,
                startVisibleDay: taskCopy.startDay,
                isTaskHidden: false,
                isCompleted: false,
                isForced: false,
                countdownEndsAt: nil,
                estimatedDurationMinutes: nil,
                completionStreakCount: 0,
                lastCompletedAt: nil
            )
        }

        var cell = existingCell
        cell.text = taskCopy.trimmedText
        if cell.residentTaskText != nil {
            cell.residentTaskText = taskCopy.trimmedText
        }
        cell.startVisibleAt = taskCopy.startAt
        cell.endVisibleAt = taskCopy.endAt
        cell.startVisibleMonth = taskCopy.startMonth
        cell.startVisibleDay = taskCopy.startDay
        cell.isTaskHidden = false
        // Force flag is only set by explicit EditTaskSheet toggle.
        cell.isForced = false
        return cell
    }

    private func makePreviewCellFromEdit(
        existingCell: BingoCell?,
        text: String,
        isForcedTask: Bool,
        residentWeekdays: Set<Int>,
        isOneTimeTask: Bool,
        estimatedDurationMinutes: Int?,
        startVisibleAt: Date?,
        endVisibleAt: Date?
    ) -> BingoCell? {
        let limitedText = String(text.prefix(AppSettings.maxTaskLength))
        let trimmedText = limitedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let normalizedWeekdays = Set(residentWeekdays.filter { (1...7).contains($0) })
        let normalizedOneTimeTask = isOneTimeTask
        let normalizedStartVisibleAt = startVisibleAt
        let normalizedEndVisibleAt = {
            guard let endVisibleAt else { return nil as Date? }
            if let normalizedStartVisibleAt, endVisibleAt <= normalizedStartVisibleAt {
                return nil
            }
            return endVisibleAt
        }()
        let usesStoredSchedule = !normalizedWeekdays.isEmpty || normalizedOneTimeTask || normalizedStartVisibleAt != nil || normalizedEndVisibleAt != nil

        var cell = existingCell ?? BingoCell()
        let previousStoredTaskText = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isReplacingTaskIdentity = previousStoredTaskText != trimmedText

        cell.residentWeekdays = normalizedWeekdays
        cell.oneTimeVisibleDate = normalizedOneTimeTask ? .now : nil
        cell.startVisibleAt = normalizedStartVisibleAt
        cell.endVisibleAt = normalizedEndVisibleAt
        cell.startVisibleMonth = nil
        cell.startVisibleDay = nil
        cell.residentTaskText = usesStoredSchedule ? limitedText : nil
        let projectedText = cell.projectedForDisplay(on: .now).text
        cell.text = usesStoredSchedule ? projectedText : limitedText
        cell.isTaskHidden = false
        cell.isForced = isForcedTask
        cell.countdownEndsAt = nil
        cell.estimatedDurationMinutes = estimatedDurationMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }

        if let estimatedDurationMinutes {
            let totalMinutes = min(max(estimatedDurationMinutes, 1), BingoViewModel.maxCountdownMinutes)
            if let normalizedStartVisibleAt, normalizedStartVisibleAt > .now {
                cell.countdownEndsAt = nil
            } else {
                cell.countdownEndsAt = Date().addingTimeInterval(Double(totalMinutes * 60))
            }
        }

        if isReplacingTaskIdentity {
            cell.completionStreakCount = 0
            cell.lastCompletedAt = nil
        }

        return cell
    }

    private func remainingMinutes(from countdownEndsAt: Date?) -> Int? {
        guard let countdownEndsAt else { return nil }
        let remainingSeconds = max(countdownEndsAt.timeIntervalSince(.now), 0)
        let remainingMinutes = Int(ceil(remainingSeconds / 60))
        return max(remainingMinutes, 1)
    }

    private func openTaskEditor(for location: TaskLocation) {
        guard let currentTask = task(for: location) else { return }
        taskEditorDraft = TaskEditorDraft(
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
                estimatedDurationMinutes: remainingMinutes(from: currentCell.countdownEndsAt),
                onSave: { newText, isForcedTask, residentWeekdays, isOneTimeTask, estimatedDurationMinutes, startVisibleAt, endVisibleAt in
                    guard let latestIndex = previewSlots.firstIndex(where: { $0.id == slotID }) else {
                        previewEditingTarget = nil
                        return
                    }

                    let existingCell = previewSlots[latestIndex].cellState
                    previewSlots[latestIndex].cellState = makePreviewCellFromEdit(
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

        let (startMonth, startDay) = normalizedMonthDay(
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

    private func taskLocation(forTaskKey key: String) -> TaskLocation? {
        if let index = library.tasks.firstIndex(where: { taskKey(for: $0) == key }) {
            return .standalone(index)
        }

        for group in library.groups {
            if let taskIndex = group.tasks.firstIndex(where: { taskKey(for: $0) == key }) {
                return .group(group.id, taskIndex)
            }
        }
        return nil
    }

    private func displayGroupName(_ group: MyTaskGroup) -> String {
        let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.groupDefaultName : trimmed
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
            let date = parseDateKey(dateKey) ?? now
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

    private func parseDateKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
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
        let (startMonth, startDay) = normalizedMonthDay(monthText: newTaskStartMonthDraft, dayText: newTaskStartDayDraft)
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
        let plan = ApplyPlan(tasks: previewSlots.compactMap(\.task), targetGridSize: targetGridSize)

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

    private func applySelectionToBoard(_ plan: ApplyPlan) {
        let orderedCells = previewSlots.map(\.cellState)
        viewModel.applyBoardOrderedCells(orderedCells, targetGridSize: plan.targetGridSize)
        didApplyToBoard = true
        onSaveSuccess(L10n.quickEditAppliedSuccess(min(plan.tasks.count, plan.targetGridSize * plan.targetGridSize)))
        dismiss()
    }

    private func initialSelectedKeys(from taskTexts: [String], candidates: [TaskCandidate]) -> [String] {
        var pendingByText = Dictionary(grouping: candidates, by: { $0.task.trimmedText })
        var resolved: [String] = []

        for text in taskTexts {
            guard var list = pendingByText[text], let candidate = list.first else { continue }
            resolved.append(candidate.id)
            list.removeFirst()
            pendingByText[text] = list
        }

        return resolved
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
        return slots + emptyPreviewSlots(count: totalGridSlots - slots.count)
    }

    private func adjustPreviewSlotCount() {
        if previewSlots.isEmpty {
            previewSlots = buildInitialPreviewSlots()
            return
        }

        if previewSlots.count > totalGridSlots {
            previewSlots = Array(previewSlots.prefix(totalGridSlots))
        } else if previewSlots.count < totalGridSlots {
            previewSlots.append(contentsOf: emptyPreviewSlots(count: totalGridSlots - previewSlots.count))
        }
    }

    private func addPreviewTask(for key: String) -> Bool {
        guard let task = candidateTaskMap[key], task.isStartDateReached() else { return false }

        if let existingIndex = previewSlots.firstIndex(where: { $0.sourceTaskKey == key }) {
            previewSlots[existingIndex].cellState = makePreviewCell(from: task, preserving: previewSlots[existingIndex].cellState)
            return true
        }

        guard let emptyIndex = previewSlots.firstIndex(where: { $0.task == nil }) else {
            return false
        }

        previewSlots[emptyIndex].cellState = makePreviewCell(from: task)
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
            return PreviewSlot(cellState: makePreviewCell(from: task), sourceTaskKey: key)
        }

        previewSlots = Array(activeTasks.prefix(totalGridSlots))
        if previewSlots.count < totalGridSlots {
            previewSlots.append(contentsOf: emptyPreviewSlots(count: totalGridSlots - previewSlots.count))
        }
    }

    private func emptyPreviewSlots(count: Int) -> [PreviewSlot] {
        guard count > 0 else { return [] }
        return (0..<count).map { _ in PreviewSlot() }
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

            previewSlots[index].cellState = makePreviewCell(from: task, preserving: previewSlots[index].cellState)
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
                  let message = saveSuccessMessage(previous: previousLibrary, current: savedLibrary) {
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
private func confirmDelete(_ target: DeleteTarget) {
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

    private func saveSuccessMessage(previous: MyTasksLibrary, current: MyTasksLibrary) -> String? {
        let taskDelta = current.tasks.count - previous.tasks.count
        let groupDelta = current.groups.count - previous.groups.count

        if taskDelta > 0 && groupDelta > 0 {
            return L10n.tasksAndGroupsAddedSuccess
        }
        if taskDelta > 0 {
            return L10n.taskAddedSuccess
        }
        if groupDelta > 0 {
            return L10n.groupAddedSuccess
        }
        if taskDelta < 0 && groupDelta < 0 {
            return L10n.tasksAndGroupsDeletedSuccess
        }
        if taskDelta < 0 {
            return L10n.taskDeletedSuccess
        }
        if groupDelta < 0 {
            return L10n.groupDeletedSuccess
        }

        return nil
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

private func deleteMessage(for target: DeleteTarget) -> String {
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
    return displayGroupName(group)
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
