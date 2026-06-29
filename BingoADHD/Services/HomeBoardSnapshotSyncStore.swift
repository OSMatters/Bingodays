import Combine
import Foundation

struct HomeBoardSnapshotSyncResult: Equatable {
    let didChangeSnapshot: Bool
    let shouldSyncTaskReminders: Bool

    var shouldInvalidateCountdownTickSchedule: Bool {
        didChangeSnapshot
    }
}

@MainActor
final class HomeBoardSnapshotSyncStore: ObservableObject {
    func persistNamedBoardsSnapshot(
        boardManagementStore: BoardManagementStore
    ) -> HomeBoardSnapshotSyncResult {
        let didChangeSnapshot = boardManagementStore.persistSnapshot()
        return HomeBoardSnapshotSyncResult(
            didChangeSnapshot: didChangeSnapshot,
            shouldSyncTaskReminders: false
        )
    }

    func syncSelectedBoardSnapshot(
        boardManagementStore: BoardManagementStore,
        board: SavedBoard,
        countdownEndsAt: Date?,
        syncTaskReminders: Bool
    ) -> HomeBoardSnapshotSyncResult {
        let didChangeSnapshot = boardManagementStore.syncSelectedBoard(
            board: board,
            countdownEndsAt: countdownEndsAt
        )
        return HomeBoardSnapshotSyncResult(
            didChangeSnapshot: didChangeSnapshot,
            shouldSyncTaskReminders: didChangeSnapshot && syncTaskReminders
        )
    }
}
