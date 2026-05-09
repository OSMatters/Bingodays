import Foundation

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
            startMonth: cellState.startVisibleMonth,
            startDay: cellState.startVisibleDay
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

struct QuickEditPreviewEditingTarget: Identifiable, Equatable {
    let slotID: UUID
    var id: UUID { slotID }
}

enum QuickEditDeleteTarget: Equatable {
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

func quickEditMakePreviewCell(from task: MyTaskItem, preserving existingCell: BingoCell? = nil) -> BingoCell {
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

func quickEditMakePreviewCellFromEdit(
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
