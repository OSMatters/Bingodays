import Foundation

struct BingoTaskSignature: Hashable {
    let text: String
    let startAt: Date?
    let endAt: Date?
    let startMonth: Int?
    let startDay: Int?

    init(task: MyTaskItem) {
        self.text = task.trimmedText
        self.startAt = task.startAt
        self.endAt = task.endAt
        self.startMonth = task.startMonth
        self.startDay = task.startDay
    }

    init(cell: BingoCell) {
        self.text = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.startAt = cell.startVisibleAt
        self.endAt = cell.endVisibleAt
        self.startMonth = cell.startVisibleMonth
        self.startDay = cell.startVisibleDay
    }
}

enum BingoTaskBoardHelpers {
    static func sanitizedTasks(_ tasks: [MyTaskItem], maxLength: Int) -> [MyTaskItem] {
        tasks.compactMap { sanitizedTask($0, maxLength: maxLength) }
    }

    static func sanitizedTask(_ task: MyTaskItem, maxLength: Int) -> MyTaskItem? {
        var sanitized = task
        sanitized.text = String(task.text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.normalizeVisibilityWindow()
        return sanitized.trimmedText.isEmpty ? nil : sanitized
    }

    static func taskItem(from cell: BingoCell, maxLength: Int) -> MyTaskItem? {
        let text = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return MyTaskItem(
            text: String(text.prefix(maxLength)),
            startAt: cell.startVisibleAt,
            endAt: cell.endVisibleAt,
            startMonth: cell.startVisibleMonth,
            startDay: cell.startVisibleDay
        )
    }

    static func cell(for task: MyTaskItem) -> BingoCell {
        BingoCell(
            text: task.trimmedText,
            residentTaskText: task.hasStartDate ? task.trimmedText : nil,
            startVisibleAt: task.startAt,
            endVisibleAt: task.endAt,
            usesRecurringTimeWindow: false,
            startVisibleMonth: task.startMonth,
            startVisibleDay: task.startDay
        )
    }

    static func applyTask(_ task: MyTaskItem, to cell: inout BingoCell) {
        cell.text = task.trimmedText
        cell.residentTaskText = task.hasStartDate ? task.trimmedText : nil
        cell.startVisibleAt = task.startAt
        cell.endVisibleAt = task.endAt
        cell.usesRecurringTimeWindow = false
        cell.startReminderEnabled = false
        cell.startReminderOffsetMinutes = BingoCell.defaultStartReminderOffsetMinutes
        cell.startVisibleMonth = task.startMonth
        cell.startVisibleDay = task.startDay
        cell.isForced = false
    }
}
