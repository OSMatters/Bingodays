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
