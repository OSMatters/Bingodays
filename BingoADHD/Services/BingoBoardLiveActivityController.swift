import ActivityKit
import Foundation

@MainActor
enum BingoBoardLiveActivityController {
    enum Failure: LocalizedError {
        case unavailable, boardMissing, contentTooLarge

        var errorDescription: String? {
            switch self {
            case .unavailable:
                L10n.tr("Enable Live Activities in Settings to display this board.", zhHans: "请在系统设置中允许实时活动，以展示棋盘。", zhHant: "請在系統設定中允許即時動態，以展示棋盤。", ja: "ボードを表示するには、設定でライブアクティビティを許可してください。")
            case .boardMissing:
                L10n.tr("This board is no longer available.", zhHans: "这个棋盘已不存在。", zhHant: "這個棋盤已不存在。", ja: "このボードは存在しません。")
            case .contentTooLarge:
                L10n.tr("This board exceeds the system's Live Activity data limit.", zhHans: "这个棋盘超出了系统实时活动的数据限制。", zhHant: "這個棋盤超出了系統即時動態的資料限制。", ja: "このボードのデータは、ライブアクティビティの上限を超えています。")
            }
        }
    }

    private static var pending: Task<Void, Never>?

    static func isDisplaying(_ boardID: UUID) -> Bool {
        activities.contains { $0.attributes.boardID == boardID }
    }

    static func toggle(boardID: UUID) async throws {
        try await enqueue {
            if isDisplaying(boardID) {
                for activity in activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                return
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw Failure.unavailable }
            guard let board = loadBoard(boardID) else { throw Failure.boardMissing }
            let attributes = BingoBoardActivityAttributes(boardID: boardID)
            let content = try content(for: board)
            let previous = activities
            // Request first: a failed request leaves the previous board available.
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            for activity in previous {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }.value
    }

    static func scheduleRefresh() {
        _ = enqueue { await refreshActivities() }
    }

    static func refresh() async {
        _ = try? await enqueue { await refreshActivities() }.value
    }

    private static var activities: [Activity<BingoBoardActivityAttributes>] {
        Activity.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    private static func enqueue(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void, Error> {
        let previous = pending
        let task = Task { @MainActor in
            await previous?.value
            try await operation()
        }
        pending = Task { _ = try? await task.value }
        return task
    }

    private static func refreshActivities() async {
        for activity in activities {
            guard let board = loadBoard(activity.attributes.boardID) else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            do {
                let content = try content(for: board)
                if content.state != activity.content.state || content.staleDate != activity.content.staleDate {
                    await activity.update(content)
                }
            } catch {
                // Don't leave interactive stale content after a payload failure.
                DiagnosticLogStore.recordWarning("live_activity.update_failed", details: ["error": error.localizedDescription])
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func loadBoard(_ id: UUID) -> BingoBoardStore.NamedBoard? {
        BingoBoardStore.withBoardPersistenceLock {
            BingoBoardStore.loadNamedBoardsSnapshot(repairingPersistence: false).boards.first { $0.id == id }
        } ?? nil
    }

    static func content(for board: BingoBoardStore.NamedBoard, now: Date = .now) throws -> ActivityContent<BingoBoardActivityAttributes.ContentState> {
        let snapshot = BingoBoardActivitySnapshotBuilder.make(board: board, now: now)
        let state = try BingoBoardActivityAttributes.ContentState(snapshot: snapshot)
        let encoder = JSONEncoder()
        let attributesSize = try encoder.encode(BingoBoardActivityAttributes(boardID: board.id)).count
        guard try encoder.encode(state).count + attributesSize < 4_096 else { throw Failure.contentTooLarge }
        return ActivityContent(state: state, staleDate: BingoBoardActivitySnapshotBuilder.staleDate(board: board, now: now))
    }
}
