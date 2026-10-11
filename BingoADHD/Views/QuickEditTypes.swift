import Foundation

struct QuickEditBoardContext {
    let boardID: UUID?
    let board: SavedBoard

    func matches(_ current: SavedBoard?, boardID: UUID?) -> Bool {
        guard self.boardID == boardID, let current else { return false }
        // Compare stored cells, not date-dependent projections or board metadata.
        return TaskRulePersistenceGuard.matchesStoredTasks(board, current)
    }
}

struct QuickEditTaskCandidate: Identifiable {
    let id: String
    let task: MyTaskItem
}

struct QuickEditTaskEditorDraft: Identifiable, Equatable {
    enum Mode: Equatable {
        case createStandalone
        case createGroup(UUID)
        case edit(QuickEditTaskLocation)
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

enum QuickEditFilterTab: Equatable {
    case all
    case group(UUID)
}

enum QuickEditTaskLocation: Hashable {
    case standalone(Int)
    case group(UUID, Int)
}

enum QuickEditFilteredTaskSource: Equatable {
    case library(QuickEditTaskLocation)
    case history
}

struct QuickEditFilteredTaskItem: Identifiable {
    let id: String
    let source: QuickEditFilteredTaskSource
    let task: MyTaskItem
    let operationDate: Date
    let isLocked: Bool
}

struct QuickEditPreviewSlot: Identifiable, Equatable {
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
            startAt: cellState.startVisibleAt,
            endAt: cellState.endVisibleAt,
            startMonth: cellState.startVisibleMonth,
            startDay: cellState.startVisibleDay,
            recurrenceRule: cellState.effectiveRecurrenceRule
        )
    }
}

struct QuickEditDeselectedTaskDraft {
    let sourceTask: MyTaskItem
    let cellState: BingoCell

    func restoredCell(for task: MyTaskItem, availableHistoryCount: Int) -> BingoCell {
        // Candidate keys identify tasks; history candidates can have regenerated UUIDs.
        if task.text == sourceTask.text,
           task.startAt == sourceTask.startAt,
           task.endAt == sourceTask.endAt,
           task.startMonth == sourceTask.startMonth,
           task.startDay == sourceTask.startDay,
           task.recurrenceRule == sourceTask.recurrenceRule {
            return cellState
        }

        // A missing library rule is legacy/unspecified data, not an explicit
        // request to downgrade a previously edited preview cell to a single
        // task. Keep the draft's effective rule while applying newer task
        // metadata such as a renamed title.
        var taskToRestore = task
        if taskToRestore.recurrenceRule == nil,
           let draftRule = cellState.effectiveRecurrenceRule {
            taskToRestore.recurrenceRule = draftRule
        }
        return quickEditMakePreviewCell(
            from: taskToRestore,
            preserving: cellState,
            availableHistoryCount: availableHistoryCount
        )
    }
}

struct QuickEditSnapshot: Equatable {
    struct PreviewItem: Equatable {
        let cellState: BingoCell?
        let sourceTaskKey: String?
    }

    let targetGridSize: Int
    let selectedTaskKeys: [String]
    let previewItems: [PreviewItem]
    let library: MyTasksLibrary
}

struct QuickEditApplyPlan: Equatable {
    let tasks: [MyTaskItem]
    let targetGridSize: Int
}

struct QuickEditPreviewAppendResult: Equatable {
    let updatedSlots: [QuickEditPreviewSlot]
    let addedTaskCount: Int
    let omittedTaskCount: Int
}

struct QuickEditPreviewEditingTarget: Identifiable, Equatable {
    let slotID: UUID
    var id: UUID { slotID }
}

enum QuickEditDeleteTarget: Equatable {
    case task(Int)
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
        }
    }
}

extension QuickEditTaskLocation {
    var focusedField: FocusedMyTaskField {
        switch self {
        case .standalone(let index):
            return .task(index)
        case .group(let groupID, let index):
            return .groupTask(groupID, index)
        }
    }

    var placeholder: String {
        switch self {
        case .standalone(let index):
            return L10n.taskNumber(index + 1)
        case .group:
            return L10n.task
        }
    }

    var deleteTarget: QuickEditDeleteTarget {
        switch self {
        case .standalone(let index):
            return .task(index)
        case .group(let groupID, let index):
            return .groupTask(groupID, index)
        }
    }
}

func quickEditNormalizedMonthDay(monthText: String, dayText: String) -> (Int?, Int?) {
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

func quickEditMakePreviewCell(
    from task: MyTaskItem,
    preserving existingCell: BingoCell? = nil,
    availableHistoryCount: Int = 0
) -> BingoCell {
    var taskCopy = task
    taskCopy.text = String(task.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    taskCopy.normalizeVisibilityWindow()

    guard let existingCell else {
        let recurrenceRule = taskCopy.recurrenceRule
        let usesStoredSchedule = recurrenceRule != nil ||
            taskCopy.startAt != nil || taskCopy.endAt != nil
        return BingoCell(
            text: taskCopy.trimmedText,
            residentTaskText: usesStoredSchedule ? taskCopy.trimmedText : nil,
            residentWeekdays: [],
            oneTimeVisibleDate: nil,
            recurrenceRule: recurrenceRule,
            startVisibleAt: taskCopy.startAt,
            endVisibleAt: taskCopy.endAt,
            usesRecurringTimeWindow: false,
            startVisibleMonth: taskCopy.startMonth,
            startVisibleDay: taskCopy.startDay,
            isTaskHidden: false,
            isCompleted: false,
            isForced: false,
            countdownEndsAt: nil,
            estimatedDurationMinutes: nil,
            completionStreakCount: TaskCompletionHistoryRuleEngine.inheritedCompletionCount(
                previousTaskText: "",
                previousCompletionCount: 0,
                updatedTaskText: taskCopy.trimmedText,
                availableHistoryCount: availableHistoryCount
            ),
            lastCompletedAt: nil
        )
    }

    var cell = existingCell
    let isRepeating = taskCopy.recurrenceRule.map { $0.kind != .none } ?? false
    let startAt = isRepeating ? nil : taskCopy.startAt
    let endAt = isRepeating ? nil : taskCopy.endAt
    let startMonth = isRepeating ? nil : taskCopy.startMonth
    let startDay = isRepeating ? nil : taskCopy.startDay
    let usesStoredSchedule = taskCopy.recurrenceRule != nil ||
        startAt != nil || endAt != nil || startMonth != nil || startDay != nil
    let definitionChanged = existingCell.storedTaskText != taskCopy.trimmedText ||
        existingCell.recurrenceRule != taskCopy.recurrenceRule ||
        !existingCell.residentWeekdays.isEmpty ||
        existingCell.oneTimeVisibleDate != nil ||
        existingCell.startVisibleAt != startAt ||
        existingCell.endVisibleAt != endAt ||
        existingCell.startVisibleMonth != startMonth ||
        existingCell.startVisibleDay != startDay
    cell.text = taskCopy.trimmedText
    cell.residentTaskText = usesStoredSchedule ? taskCopy.trimmedText : nil
    cell.residentWeekdays = []
    cell.oneTimeVisibleDate = nil
    cell.recurrenceRule = taskCopy.recurrenceRule
    cell.startVisibleAt = startAt
    cell.endVisibleAt = endAt
    cell.usesRecurringTimeWindow = false
    cell.startReminderEnabled = false
    cell.startReminderOffsetMinutes = BingoCell.defaultStartReminderOffsetMinutes
    cell.startVisibleMonth = startMonth
    cell.startVisibleDay = startDay
    cell.isTaskHidden = false
    // Force flag is only set by explicit EditTaskSheet toggle.
    cell.isForced = false
    cell.completionStreakCount = TaskCompletionHistoryRuleEngine.inheritedCompletionCount(
        previousTaskText: existingCell.storedTaskText,
        previousCompletionCount: definitionChanged ? 0 : existingCell.completionStreakCount,
        updatedTaskText: taskCopy.trimmedText,
        availableHistoryCount: availableHistoryCount
    )
    if definitionChanged {
        cell.isCompleted = false
        cell.lastCompletedAt = nil
        cell.countdownEndsAt = nil
        cell.countdownPausedRemainingSeconds = nil
        cell.estimatedDurationMinutes = nil
    }
    return cell
}

func quickEditMakePreviewCellFromEdit(
    existingCell: BingoCell?,
    text: String,
    isForcedTask: Bool,
    residentWeekdays: Set<Int>,
    isOneTimeTask: Bool,
    recurrenceRule: TaskRecurrenceRule? = nil,
    estimatedDurationMinutes: Int?,
    startVisibleAt: Date?,
    endVisibleAt: Date?,
    startReminderEnabled: Bool = false,
    startReminderOffsetMinutes: Int = BingoCell.defaultStartReminderOffsetMinutes,
    availableHistoryCount: Int = 0
) -> BingoCell? {
    let limitedText = String(text.prefix(AppSettings.maxTaskLength))
    let trimmedText = limitedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return nil }

    let submittedStartVisibleAt = startVisibleAt
    let submittedEndVisibleAt = {
        guard let endVisibleAt else { return nil as Date? }
        if let submittedStartVisibleAt, endVisibleAt <= submittedStartVisibleAt {
            return nil
        }
        return endVisibleAt
    }()
    let recurrenceDefaultDate = submittedStartVisibleAt ?? Date()
    let normalizedRecurrenceRule = recurrenceRule?.normalized(
        defaultWeekday: Calendar.current.component(.weekday, from: recurrenceDefaultDate),
        defaultMonthDay: Calendar.current.component(.day, from: recurrenceDefaultDate),
        defaultAnchorDate: recurrenceDefaultDate
    )
    let normalizedWeekdays: Set<Int>
    if normalizedRecurrenceRule?.kind == .weekly {
        normalizedWeekdays = normalizedRecurrenceRule?.weekdays ?? []
    } else {
        normalizedWeekdays = normalizedRecurrenceRule == nil ? Set(residentWeekdays.filter { (1...7).contains($0) }) : []
    }
    let hasRepeatingSchedule = normalizedRecurrenceRule.map { $0.kind != .none } ?? !normalizedWeekdays.isEmpty
    let normalizedStartVisibleAt = hasRepeatingSchedule ? nil : submittedStartVisibleAt
    let normalizedEndVisibleAt = hasRepeatingSchedule ? nil : submittedEndVisibleAt
    let allowsTaskCountdown = !hasRepeatingSchedule
    let normalizedEstimatedDurationMinutes = allowsTaskCountdown
        ? estimatedDurationMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }
        : nil
    let normalizedOneTimeTask = normalizedRecurrenceRule?.kind == TaskRecurrenceRule.Kind.none || (normalizedRecurrenceRule == nil && isOneTimeTask)
    let normalizedOneTimeVisibleDate = normalizedOneTimeTask
        ? (normalizedRecurrenceRule?.anchorDate ?? normalizedStartVisibleAt ?? Date())
        : nil
    let normalizedReminderEnabled = !hasRepeatingSchedule &&
        normalizedStartVisibleAt != nil &&
        normalizedEndVisibleAt != nil &&
        startReminderEnabled
    let normalizedReminderOffset = BingoCell.normalizedStartReminderOffsetMinutes(startReminderOffsetMinutes)
    let normalizedUsesRecurringTimeWindow = false
    let usesStoredSchedule = normalizedRecurrenceRule != nil || !normalizedWeekdays.isEmpty || normalizedOneTimeTask || normalizedStartVisibleAt != nil || normalizedEndVisibleAt != nil

    var cell = existingCell ?? BingoCell()
    let wasCompleted = cell.isCompleted
    let previousTaskIdentity = quickEditTaskIdentity(for: cell)
    let updatedTaskIdentity = QuickEditTaskIdentity(
        text: trimmedText,
        residentWeekdays: normalizedWeekdays,
        oneTimeVisibleDate: normalizedOneTimeVisibleDate,
        recurrenceRule: normalizedRecurrenceRule,
        startVisibleAt: normalizedStartVisibleAt,
        endVisibleAt: normalizedEndVisibleAt,
        usesRecurringTimeWindow: normalizedUsesRecurringTimeWindow
    )
    let didChangeTaskIdentity = previousTaskIdentity != updatedTaskIdentity

    cell.residentWeekdays = normalizedWeekdays
    cell.oneTimeVisibleDate = normalizedOneTimeVisibleDate
    cell.recurrenceRule = normalizedRecurrenceRule
    cell.startVisibleAt = normalizedStartVisibleAt
    cell.endVisibleAt = normalizedEndVisibleAt
    cell.usesRecurringTimeWindow = normalizedUsesRecurringTimeWindow
    cell.startReminderEnabled = normalizedReminderEnabled
    cell.startReminderOffsetMinutes = normalizedReminderOffset
    cell.startVisibleMonth = nil
    cell.startVisibleDay = nil
    cell.residentTaskText = usesStoredSchedule ? limitedText : nil
    let projectedText = cell.projectedForDisplay(on: .now).text
    cell.text = usesStoredSchedule ? projectedText : limitedText
    cell.isTaskHidden = false
    cell.isForced = isForcedTask
    cell.countdownEndsAt = nil
    cell.countdownPausedRemainingSeconds = nil
    cell.estimatedDurationMinutes = normalizedEstimatedDurationMinutes

    if cell.shouldStartCountdownForCurrentOccurrence(on: .now) {
        cell.countdownEndsAt = cell.countdownDeadlineForCurrentOccurrence(
            startingAt: .now,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes
        )
    }

    if didChangeTaskIdentity {
        cell.completionStreakCount = TaskCompletionHistoryRuleEngine.inheritedCompletionCount(
            previousTaskText: existingCell?.storedTaskText ?? "",
            // A quick-edit schedule change is a new task identity. Keep the
            // preview consistent with the normal editor, which clears the
            // outgoing count before the history rule evaluates the new name.
            previousCompletionCount: 0,
            updatedTaskText: cell.storedTaskText,
            availableHistoryCount: availableHistoryCount
        )
        cell.lastCompletedAt = nil
    }
    if wasCompleted && didChangeTaskIdentity {
        cell.isCompleted = false
        cell.isTaskHidden = false
        cell.lastCompletedAt = nil
    }

    return cell
}

private struct QuickEditTaskIdentity: Equatable {
    let text: String
    let residentWeekdays: Set<Int>
    let oneTimeVisibleDate: Date?
    let recurrenceRule: TaskRecurrenceRule?
    let startVisibleAt: Date?
    let endVisibleAt: Date?
    let usesRecurringTimeWindow: Bool
}

private func quickEditTaskIdentity(for cell: BingoCell) -> QuickEditTaskIdentity {
    QuickEditTaskIdentity(
        text: cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines),
        residentWeekdays: cell.residentWeekdays,
        oneTimeVisibleDate: cell.oneTimeVisibleDate,
        recurrenceRule: cell.recurrenceRule,
        startVisibleAt: cell.startVisibleAt,
        endVisibleAt: cell.endVisibleAt,
        usesRecurringTimeWindow: cell.usesRecurringTimeWindow
    )
}

func quickEditRemainingMinutes(from countdownEndsAt: Date?) -> Int? {
    guard let countdownEndsAt else { return nil }
    let remainingSeconds = max(countdownEndsAt.timeIntervalSince(.now), 0)
    let remainingMinutes = Int(ceil(remainingSeconds / 60))
    return max(remainingMinutes, 1)
}

func quickEditDisplayGroupName(_ group: MyTaskGroup) -> String {
    let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? L10n.groupDefaultName : trimmed
}

func quickEditSaveSuccessMessage(previous: MyTasksLibrary, current: MyTasksLibrary) -> String? {
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

func quickEditParseDateKey(_ key: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: key)
}

func quickEditEmptyPreviewSlots(count: Int) -> [QuickEditPreviewSlot] {
    guard count > 0 else { return [] }
    return (0..<count).map { _ in QuickEditPreviewSlot() }
}

func quickEditTaskKey(_ task: MyTaskItem) -> String {
    task.id.uuidString
}

func quickEditHistoryTaskKey(_ record: TaskHistoryRecord) -> String {
    "history:\(record.key)"
}

func quickEditTaskFromHistory(_ record: TaskHistoryRecord) -> MyTaskItem {
    return MyTaskItem(
        text: record.trimmedText,
        startAt: record.startAt,
        endAt: record.endAt,
        startMonth: record.startMonth,
        startDay: record.startDay,
        recurrenceRule: record.recurrenceRule
    )
}

func quickEditLibraryTaskIDs(library: MyTasksLibrary) -> Set<UUID> {
    Set(library.tasks.map(\.id) + library.groups.flatMap { $0.tasks.map(\.id) })
}

func quickEditHistoryBySourceTaskID(records: [TaskHistoryRecord]) -> [UUID: TaskHistoryRecord] {
    var result: [UUID: TaskHistoryRecord] = [:]
    for record in records {
        guard let sourceTaskID = record.sourceTaskID else { continue }
        if let existing = result[sourceTaskID], existing.lastEditedAt >= record.lastEditedAt {
            continue
        }
        result[sourceTaskID] = record
    }
    return result
}

func quickEditHistoryOnlyRecordsSorted(records: [TaskHistoryRecord], libraryTaskIDs: Set<UUID>) -> [TaskHistoryRecord] {
    records
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

func quickEditAllTaskCandidates(library: MyTasksLibrary, unlockedHistoryRecords: [TaskHistoryRecord]) -> [QuickEditTaskCandidate] {
    var candidates: [QuickEditTaskCandidate] = []
    var seenIDs = Set<String>()

    for task in library.tasks {
        guard !task.trimmedText.isEmpty else { continue }
        let key = quickEditTaskKey(task)
        guard !seenIDs.contains(key) else { continue }
        candidates.append(QuickEditTaskCandidate(id: key, task: task))
        seenIDs.insert(key)
    }

    for group in library.groups {
        for task in group.tasks {
            guard !task.trimmedText.isEmpty else { continue }
            let key = quickEditTaskKey(task)
            guard !seenIDs.contains(key) else { continue }
            candidates.append(QuickEditTaskCandidate(id: key, task: task))
            seenIDs.insert(key)
        }
    }

    for record in unlockedHistoryRecords {
        let key = quickEditHistoryTaskKey(record)
        guard !seenIDs.contains(key) else { continue }
        candidates.append(
            QuickEditTaskCandidate(
                id: key,
                task: quickEditTaskFromHistory(record)
            )
        )
        seenIDs.insert(key)
    }

    return candidates
}

func quickEditFilteredTaskItems(
    activeFilter: QuickEditFilterTab,
    library: MyTasksLibrary,
    historyBySourceTaskID: [UUID: TaskHistoryRecord],
    historyOnlyRecordsSorted: [TaskHistoryRecord],
    isPremiumUser: Bool
) -> [QuickEditFilteredTaskItem] {
    switch activeFilter {
    case .all:
        var items: [QuickEditFilteredTaskItem] = library.tasks.indices.compactMap { index in
            let task = library.tasks[index]
            guard !task.trimmedText.isEmpty else { return nil }
            let operationDate = historyBySourceTaskID[task.id]?.lastEditedAt ?? .distantPast
            return QuickEditFilteredTaskItem(
                id: quickEditTaskKey(task),
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
                return QuickEditFilteredTaskItem(
                    id: quickEditTaskKey(task),
                    source: .library(.group(group.id, index)),
                    task: task,
                    operationDate: operationDate,
                    isLocked: false
                )
            })
        }

        let historyItems = historyOnlyRecordsSorted.enumerated().map { index, record in
            let isLocked = !isPremiumUser && index >= AppSettings.freeHistoryTasksVisibleCount
            return QuickEditFilteredTaskItem(
                id: quickEditHistoryTaskKey(record),
                source: .history,
                task: quickEditTaskFromHistory(record),
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
            return QuickEditFilteredTaskItem(
                id: quickEditTaskKey(task),
                source: .library(.group(groupID, index)),
                task: task,
                operationDate: operationDate,
                isLocked: false
            )
        }
    }
}

func quickEditActiveFilterTitle(_ activeFilter: QuickEditFilterTab, library: MyTasksLibrary) -> String {
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

func quickEditActiveGroupID(_ activeFilter: QuickEditFilterTab) -> UUID? {
    if case .group(let groupID) = activeFilter {
        return groupID
    }
    return nil
}

func quickEditActiveGroupTasks(activeFilter: QuickEditFilterTab, library: MyTasksLibrary) -> [MyTaskItem] {
    guard case .group(let groupID) = activeFilter,
          let group = library.groups.first(where: { $0.id == groupID }) else {
        return []
    }
    return group.tasks.filter { !$0.trimmedText.isEmpty }
}

func quickEditSyncedActiveFilter(_ activeFilter: QuickEditFilterTab, library: MyTasksLibrary) -> QuickEditFilterTab {
    switch activeFilter {
    case .all:
        return .all
    case .group(let groupID):
        return library.groups.contains(where: { $0.id == groupID }) ? activeFilter : .all
    }
}

func quickEditCanAddStandaloneTask(isPremiumUser: Bool, library: MyTasksLibrary) -> Bool {
    isPremiumUser || library.tasks.count < AppSettings.maxCommonTasks
}

func quickEditCanAddGroup(isPremiumUser: Bool, library: MyTasksLibrary) -> Bool {
    isPremiumUser || library.groups.count < AppSettings.maxTaskGroups
}

func quickEditCanAddTask(to group: MyTaskGroup, isPremiumUser: Bool) -> Bool {
    isPremiumUser || group.tasks.count < AppSettings.maxTasksPerGroup
}

func quickEditMaxGridSizeForCurrentPlan(isPremiumUser: Bool) -> Int {
    isPremiumUser ? 5 : 4
}

func quickEditSelectedPreviewCount(_ slots: [QuickEditPreviewSlot]) -> Int {
    slots.compactMap(\.task).count
}

func quickEditSelectedCountSummary(selected: Int, total: Int) -> String {
    L10n.quickEditSelectedCount(selected: selected, total: total)
}

func quickEditTask(for location: QuickEditTaskLocation, in library: MyTasksLibrary) -> MyTaskItem? {
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

func quickEditSetTask(_ task: MyTaskItem, for location: QuickEditTaskLocation, in library: inout MyTasksLibrary) {
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

func quickEditTaskLocation(forTaskKey key: String, in library: MyTasksLibrary) -> QuickEditTaskLocation? {
    if let index = library.tasks.firstIndex(where: { quickEditTaskKey($0) == key }) {
        return .standalone(index)
    }

    for group in library.groups {
        if let taskIndex = group.tasks.firstIndex(where: { quickEditTaskKey($0) == key }) {
            return .group(group.id, taskIndex)
        }
    }
    return nil
}

func quickEditAdjustPreviewSlots(
    current: [QuickEditPreviewSlot],
    totalGridSlots: Int,
    initialSlots: [QuickEditPreviewSlot]
) -> [QuickEditPreviewSlot] {
    if current.isEmpty {
        return initialSlots
    }

    if current.count > totalGridSlots {
        return Array(current.prefix(totalGridSlots))
    }
    if current.count < totalGridSlots {
        return current + quickEditEmptyPreviewSlots(count: totalGridSlots - current.count)
    }
    return current
}

func quickEditAddPreviewTask(
    key: String,
    candidateTaskMap: [String: MyTaskItem],
    currentSlots: [QuickEditPreviewSlot],
    deselectedTaskDrafts: inout [String: QuickEditDeselectedTaskDraft],
    source: String = "task_library",
    explicitlyEditedCellIDs: Set<UUID> = [],
    completionHistoryCountProvider: (String) -> Int = { _ in 0 }
) -> (updatedSlots: [QuickEditPreviewSlot], wasAdded: Bool) {
    guard let task = candidateTaskMap[key], task.isStartDateReached() else {
        return (currentSlots, false)
    }

    var slots = currentSlots
    if let existingIndex = slots.firstIndex(where: { $0.sourceTaskKey == key }) {
        if let cellID = slots[existingIndex].cellState?.id,
           explicitlyEditedCellIDs.contains(cellID) {
            return (slots, true)
        }
        slots[existingIndex].cellState = quickEditMakePreviewCell(
            from: task,
            preserving: slots[existingIndex].cellState,
            availableHistoryCount: completionHistoryCountProvider(task.trimmedText)
        )
        deselectedTaskDrafts.removeValue(forKey: key)
        return (slots, true)
    }

    guard let emptyIndex = slots.firstIndex(where: { $0.task == nil }) else {
        return (slots, false)
    }

    let historyCount = completionHistoryCountProvider(task.trimmedText)
    if let draft = deselectedTaskDrafts.removeValue(forKey: key) {
        slots[emptyIndex].cellState = draft.restoredCell(for: task, availableHistoryCount: historyCount)
    } else {
        slots[emptyIndex].cellState = quickEditMakePreviewCell(
            from: task,
            availableHistoryCount: historyCount
        )
    }
    slots[emptyIndex].sourceTaskKey = key
    if let cell = slots[emptyIndex].cellState {
        DiagnosticLogStore.recordStateChange("task_rule.preview_selected", details: [
            "source": key.hasPrefix("history:") ? "task_history" : source,
            "cell_id": cell.id.uuidString,
            "source_rule": task.recurrenceRule?.kind.rawValue ?? "legacy_unspecified",
            "rule": cell.diagnosticTaskRuleKind
        ])
    }
    return (slots, true)
}

func quickEditAppendTasksToPreview(
    keys: [String],
    candidateTaskMap: [String: MyTaskItem],
    currentSlots: [QuickEditPreviewSlot],
    deselectedTaskDrafts: inout [String: QuickEditDeselectedTaskDraft],
    explicitlyEditedCellIDs: Set<UUID> = [],
    completionHistoryCountProvider: (String) -> Int = { _ in 0 }
) -> QuickEditPreviewAppendResult {
    var slots = currentSlots
    var addedTaskCount = 0
    var omittedTaskCount = 0

    for key in keys {
        guard let task = candidateTaskMap[key], task.isStartDateReached() else { continue }

        let wasSelected = slots.contains { $0.sourceTaskKey == key }
        // Group application is idempotent. In particular, do not run an
        // already restored draft through quickEditMakePreviewCell again,
        // because a duplicate key must not replace its preserved rule with
        // an unspecified library rule.
        if wasSelected { continue }

        let result = quickEditAddPreviewTask(
            key: key,
            candidateTaskMap: candidateTaskMap,
            currentSlots: slots,
            deselectedTaskDrafts: &deselectedTaskDrafts,
            source: "group_apply",
            explicitlyEditedCellIDs: explicitlyEditedCellIDs,
            completionHistoryCountProvider: completionHistoryCountProvider
        )
        guard result.wasAdded else {
            omittedTaskCount += 1
            continue
        }
        slots = result.updatedSlots
        if !wasSelected {
            addedTaskCount += 1
        }
    }

    return QuickEditPreviewAppendResult(
        updatedSlots: slots,
        addedTaskCount: addedTaskCount,
        omittedTaskCount: omittedTaskCount
    )
}

func quickEditRemovePreviewTask(
    key: String,
    currentSlots: [QuickEditPreviewSlot],
    candidateTaskMap: [String: MyTaskItem],
    deselectedTaskDrafts: inout [String: QuickEditDeselectedTaskDraft]
) -> [QuickEditPreviewSlot] {
    var slots = currentSlots
    guard let index = slots.firstIndex(where: { $0.sourceTaskKey == key }) else { return slots }
    if let cell = slots[index].cellState, let sourceTask = candidateTaskMap[key] {
        // Deselecting changes the preview, not the task configuration in this session.
        deselectedTaskDrafts[key] = QuickEditDeselectedTaskDraft(sourceTask: sourceTask, cellState: cell)
    } else {
        deselectedTaskDrafts.removeValue(forKey: key)
    }
    slots[index].cellState = nil
    slots[index].sourceTaskKey = nil
    return slots
}

func quickEditSyncPreviewSlotsWithLibrary(
    currentSlots: [QuickEditPreviewSlot],
    candidateTaskMap: [String: MyTaskItem],
    totalGridSlots: Int,
    explicitlyEditedCellIDs: Set<UUID> = [],
    completionHistoryCountProvider: (String) -> Int = { _ in 0 }
) -> [QuickEditPreviewSlot] {
    guard !currentSlots.isEmpty else { return currentSlots }

    var slots = currentSlots
    for index in slots.indices {
        guard let sourceTaskKey = slots[index].sourceTaskKey else { continue }
        guard let task = candidateTaskMap[sourceTaskKey],
              !task.trimmedText.isEmpty,
              task.isStartDateReached() else {
            slots[index].cellState = nil
            slots[index].sourceTaskKey = nil
            continue
        }
        if let cellID = slots[index].cellState?.id,
           explicitlyEditedCellIDs.contains(cellID) { continue }
        slots[index].cellState = quickEditMakePreviewCell(
            from: task,
            preserving: slots[index].cellState,
            availableHistoryCount: completionHistoryCountProvider(task.trimmedText)
        )
    }

    if slots.count > totalGridSlots {
        return Array(slots.prefix(totalGridSlots))
    }
    if slots.count < totalGridSlots {
        return slots + quickEditEmptyPreviewSlots(count: totalGridSlots - slots.count)
    }
    return slots
}

func quickEditCurrentSnapshot(
    targetGridSize: Int,
    selectedTaskKeys: [String],
    previewSlots: [QuickEditPreviewSlot],
    library: MyTasksLibrary
) -> QuickEditSnapshot {
    QuickEditSnapshot(
        targetGridSize: targetGridSize,
        selectedTaskKeys: selectedTaskKeys,
        previewItems: previewSlots.map { slot in
            QuickEditSnapshot.PreviewItem(cellState: slot.cellState, sourceTaskKey: slot.sourceTaskKey)
        },
        library: library
    )
}

func quickEditHasUnsavedChanges(initialSnapshot: QuickEditSnapshot?, currentSnapshot: QuickEditSnapshot) -> Bool {
    guard let initialSnapshot else { return false }
    return initialSnapshot != currentSnapshot
}

func quickEditBuildApplyPlan(
    selectedTaskKeys: [String],
    candidateTaskMap: [String: MyTaskItem],
    targetGridSize: Int
) -> QuickEditApplyPlan {
    let selectedTasks = selectedTaskKeys.compactMap { key -> MyTaskItem? in
        guard let task = candidateTaskMap[key], task.isStartDateReached() else { return nil }
        return task
    }
    let maxSelectable = targetGridSize * targetGridSize
    return QuickEditApplyPlan(tasks: Array(selectedTasks.prefix(maxSelectable)), targetGridSize: targetGridSize)
}

func quickEditEditorDraft(for location: QuickEditTaskLocation, task: MyTaskItem) -> QuickEditTaskEditorDraft {
    QuickEditTaskEditorDraft(
        mode: .edit(location),
        text: task.text,
        startMonthText: task.startMonth.map(String.init) ?? "",
        startDayText: task.startDay.map(String.init) ?? ""
    )
}

func quickEditTaskFromEditorDraft(
    _ draft: QuickEditTaskEditorDraft,
    existingTask: MyTaskItem?
) -> MyTaskItem? {
    guard draft.canSave else { return nil }
    guard case .edit = draft.mode else { return nil }
    guard var task = existingTask else { return nil }

    let (startMonth, startDay) = quickEditNormalizedMonthDay(
        monthText: draft.startMonthText,
        dayText: draft.startDayText
    )

    task.text = draft.normalizedName
    task.startMonth = startMonth
    task.startDay = startDay
    task.normalizeStartDate()
    return task
}

enum QuickEditDeleteResolution {
    case libraryTaskRemoved(task: MyTaskItem, successMessage: String)
    case historyItemRemoved(historyItemID: String, successMessage: String)
    case invalid
}

func quickEditResolveDeleteTarget(
    _ target: QuickEditDeleteTarget,
    in library: inout MyTasksLibrary
) -> QuickEditDeleteResolution {
    switch target {
    case .task(let index):
        guard library.tasks.indices.contains(index) else { return .invalid }
        let task = library.tasks[index]
        library.tasks.remove(at: index)
        return .libraryTaskRemoved(task: task, successMessage: target.successMessage)
    case .groupTask(let groupID, let index):
        guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
              library.groups[groupIndex].tasks.indices.contains(index) else { return .invalid }
        let task = library.groups[groupIndex].tasks[index]
        library.groups[groupIndex].tasks.remove(at: index)
        return .libraryTaskRemoved(task: task, successMessage: target.successMessage)
    case .history(let historyItemID):
        return .historyItemRemoved(historyItemID: historyItemID, successMessage: target.successMessage)
    }
}

struct QuickEditGroupDeletionResult {
    let removedTasks: [MyTaskItem]
    let updatedFilter: QuickEditFilterTab
    let deleted: Bool
}

func quickEditFinalizeGroupDeletion(
    _ groupID: UUID,
    in library: inout MyTasksLibrary,
    activeFilter: QuickEditFilterTab
) -> QuickEditGroupDeletionResult {
    guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else {
        return QuickEditGroupDeletionResult(removedTasks: [], updatedFilter: activeFilter, deleted: false)
    }

    let removedTasks = library.groups[groupIndex].tasks.filter { !$0.trimmedText.isEmpty }
    library.groups.remove(at: groupIndex)
    let updatedFilter: QuickEditFilterTab = activeFilter == .group(groupID) ? .all : activeFilter
    return QuickEditGroupDeletionResult(removedTasks: removedTasks, updatedFilter: updatedFilter, deleted: true)
}

func quickEditHistoryRecordKey(from historyItemID: String) -> String? {
    let prefix = "history:"
    guard historyItemID.hasPrefix(prefix) else { return nil }
    return String(historyItemID.dropFirst(prefix.count))
}

func quickEditGroupName(for groupID: UUID, in library: MyTasksLibrary) -> String {
    guard let group = library.groups.first(where: { $0.id == groupID }) else {
        return L10n.groupDefaultName
    }
    return quickEditDisplayGroupName(group)
}

func quickEditDeleteMessage(for target: QuickEditDeleteTarget, in library: MyTasksLibrary) -> String {
    switch target {
    case .groupTask(let groupID, _):
        let name = quickEditGroupName(for: groupID, in: library)
        return L10n.tr(
            "This task will be removed from \(name).",
            zhHans: "该任务将从「\(name)」中移除。",
            zhHant: "該任務將從「\(name)」中移除。"
        )
    default:
        return target.message
    }
}

struct QuickEditHistoryBackfillItem {
    let task: MyTaskItem
    let date: Date
}

func quickEditLegacyHistoryItemsFromDiaryEntries(_ entries: [BingoDiaryEntry]) -> [QuickEditHistoryBackfillItem] {
    var items: [QuickEditHistoryBackfillItem] = []

    for entry in entries {
        for task in entry.completedTaskCounts.keys {
            let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            items.append(QuickEditHistoryBackfillItem(task: MyTaskItem(text: trimmed), date: entry.date))
        }

        for cell in (entry.board.fullBoardCells ?? entry.board.cells).flatMap({ $0 }) {
            let trimmed = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            items.append(
                QuickEditHistoryBackfillItem(
                    task: MyTaskItem(
                        text: trimmed,
                        startAt: cell.startVisibleAt,
                        endAt: cell.endVisibleAt,
                        startMonth: cell.startVisibleMonth,
                        startDay: cell.startVisibleDay,
                        recurrenceRule: cell.effectiveRecurrenceRule
                    ),
                    date: entry.date
                )
            )
        }
    }

    return items
}

func quickEditLegacyHistoryItemsFromTimeoutPayload(
    _ payload: [String: [String: Int]],
    now: Date
) -> [QuickEditHistoryBackfillItem] {
    var items: [QuickEditHistoryBackfillItem] = []
    for (dateKey, tasks) in payload {
        let date = quickEditParseDateKey(dateKey) ?? now
        for task in tasks.keys {
            let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            items.append(QuickEditHistoryBackfillItem(task: MyTaskItem(text: trimmed), date: date))
        }
    }
    return items
}

enum QuickEditInlineStartResult {
    case allowed
    case paywall(String)
}

func quickEditStartInlineAddDecision(
    activeFilter: QuickEditFilterTab,
    library: MyTasksLibrary,
    isPremiumUser: Bool
) -> QuickEditInlineStartResult {
    if case .group(let groupID) = activeFilter,
       let group = library.groups.first(where: { $0.id == groupID }) {
        return quickEditCanAddTask(to: group, isPremiumUser: isPremiumUser)
            ? .allowed
            : .paywall("group_task_limit_inline")
    }

    return quickEditCanAddStandaloneTask(isPremiumUser: isPremiumUser, library: library)
        ? .allowed
        : .paywall("standalone_task_limit_inline")
}

enum QuickEditInlineCommitResult {
    case noOp
    case paywall(String)
    case resetFilterToAll
    case appended(MyTaskItem)
}

func quickEditCommitInlineTask(
    draftText: String,
    monthText: String,
    dayText: String,
    activeFilter: QuickEditFilterTab,
    isPremiumUser: Bool,
    library: inout MyTasksLibrary
) -> QuickEditInlineCommitResult {
    let text = String(draftText.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return .noOp }

    let (startMonth, startDay) = quickEditNormalizedMonthDay(monthText: monthText, dayText: dayText)
    let recurrenceRule: TaskRecurrenceRule
    switch activeFilter {
    case .all:
        recurrenceRule = TaskRecurrenceRule(kind: .none)
    case .group:
        recurrenceRule = TaskRecurrenceRule(kind: .daily)
    }
    let task = MyTaskItem(
        text: text, startMonth: startMonth, startDay: startDay,
        recurrenceRule: recurrenceRule
    )

    switch activeFilter {
    case .all:
        guard quickEditCanAddStandaloneTask(isPremiumUser: isPremiumUser, library: library) else {
            return .paywall("standalone_task_limit_commit")
        }
        library.tasks.append(task)
        return .appended(task)
    case .group(let groupID):
        guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else {
            return .resetFilterToAll
        }
        guard quickEditCanAddTask(to: library.groups[groupIndex], isPremiumUser: isPremiumUser) else {
            return .paywall("group_task_limit_commit")
        }
        library.groups[groupIndex].tasks.append(task)
        return .appended(task)
    }
}

func quickEditSyncedTask(existingTask: MyTaskItem, newTask: MyTaskItem) -> MyTaskItem {
    var task = existingTask
    task.text = newTask.trimmedText
    task.startAt = newTask.startAt
    task.endAt = newTask.endAt
    task.startMonth = newTask.startMonth
    task.startDay = newTask.startDay
    task.recurrenceRule = newTask.recurrenceRule
    task.normalizeStartDate()
    return task
}

enum QuickEditAddGroupCommitResult {
    case noOp
    case paywall(String)
    case appended(MyTaskGroup)
}

enum QuickEditGroupRenameResult: Equatable {
    case renamed
    case unchanged
    case invalid
}

func quickEditRenameGroup(
    _ groupID: UUID,
    nameDraft: String,
    library: inout MyTasksLibrary
) -> QuickEditGroupRenameResult {
    guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else {
        return .invalid
    }

    let name = String(nameDraft.prefix(AppSettings.maxTaskLength))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return .invalid }
    guard library.groups[groupIndex].name != name else { return .unchanged }

    library.groups[groupIndex].name = name
    return .renamed
}

func quickEditCommitAddGroup(
    nameDraft: String,
    isPremiumUser: Bool,
    library: inout MyTasksLibrary
) -> QuickEditAddGroupCommitResult {
    guard quickEditCanAddGroup(isPremiumUser: isPremiumUser, library: library) else {
        return .paywall("group_limit_commit")
    }

    let trimmedName = String(nameDraft.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return .noOp }

    let group = MyTaskGroup(name: trimmedName, tasks: [])
    library.groups.append(group)
    return .appended(group)
}

func quickEditStandaloneTaskText(index: Int, library: MyTasksLibrary) -> String {
    guard library.tasks.indices.contains(index) else { return "" }
    return library.tasks[index].text
}

@discardableResult
func quickEditUpdateStandaloneTaskText(
    index: Int,
    newValue: String,
    library: inout MyTasksLibrary
) -> MyTaskItem? {
    guard library.tasks.indices.contains(index) else { return nil }
    library.tasks[index].text = String(newValue.prefix(AppSettings.maxTaskLength))
    return library.tasks[index]
}

func quickEditGroupTaskText(groupID: UUID, index: Int, library: MyTasksLibrary) -> String {
    guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
          library.groups[groupIndex].tasks.indices.contains(index) else { return "" }
    return library.groups[groupIndex].tasks[index].text
}

@discardableResult
func quickEditUpdateGroupTaskText(
    groupID: UUID,
    index: Int,
    newValue: String,
    library: inout MyTasksLibrary
) -> MyTaskItem? {
    guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
          library.groups[groupIndex].tasks.indices.contains(index) else { return nil }
    library.groups[groupIndex].tasks[index].text = String(newValue.prefix(AppSettings.maxTaskLength))
    return library.groups[groupIndex].tasks[index]
}

enum QuickEditSelectionDecision {
    case remove(existingIndex: Int)
    case add
}

func quickEditSelectionDecision(currentKeys: [String], key: String) -> QuickEditSelectionDecision {
    if let index = currentKeys.firstIndex(of: key) {
        return .remove(existingIndex: index)
    }
    return .add
}

func quickEditPreviewFullMessage() -> String {
    L10n.tr(
        "Preview board is full.",
        zhHans: "预览棋盘已满。",
        zhHant: "預覽棋盤已滿。"
    )
}
