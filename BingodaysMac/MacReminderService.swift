import Foundation
import UserNotifications

@MainActor
enum MacReminderService {
    private static let prefix = "mac_task_start."
    static func sync(boards: [BingoBoardStore.NamedBoard]) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier))
        guard UserDefaults.standard.bool(forKey: "mac_task_reminders_enabled") else { return }
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        guard allowed else { return }
        for board in boards {
            for cell in BoardEngine.expandedBoardCache(from: board.board).flatMap({ $0 }) {
                guard cell.hasStoredTask, !cell.isCompleted, cell.startReminderEnabled,
                      !cell.hasRepeatingSchedule, cell.endVisibleAt != nil, let start = cell.startVisibleAt else { continue }
                let date = start.addingTimeInterval(-Double(cell.startReminderOffsetMinutes * 60))
                guard date > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = board.name
                content.body = "即将开始：\(cell.storedTaskText)"
                content.sound = .default
                let request = UNNotificationRequest(identifier: prefix + board.id.uuidString + "." + cell.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false))
                do { try await center.add(request) }
                catch { DiagnosticLogStore.recordWarning("mac_reminder.schedule_failed") }
            }
        }
    }
}
