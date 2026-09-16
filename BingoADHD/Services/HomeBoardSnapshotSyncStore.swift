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

    /// Completion taps commit the named-board snapshot immediately so WidgetKit reads the same
    /// local state as the app without waiting for a later SwiftUI observation.
    func commitCellCompletionSnapshot(
        boardManagementStore: BoardManagementStore,
        board: SavedBoard,
        countdownEndsAt: Date?
    ) -> HomeBoardSnapshotSyncResult {
        let selectedBoardResult = syncSelectedBoardSnapshot(
            boardManagementStore: boardManagementStore,
            board: board,
            countdownEndsAt: countdownEndsAt,
            syncTaskReminders: false
        )
        // The selected-board write above already covers the single-board case.
        // Avoid a second no-op persistence pass unless there are other board
        // caches that can actually be stale.
        guard boardManagementStore.namedBoards.count > 1,
              TaskCompletionHistoryStore.ensureMigrated() else {
            return selectedBoardResult
        }

        let didReconcileAllBoards = boardManagementStore.reconcileCompletionHistoryCounts(
            TaskCompletionHistoryStore.load()
        )
        return HomeBoardSnapshotSyncResult(
            didChangeSnapshot: selectedBoardResult.didChangeSnapshot || didReconcileAllBoards,
            shouldSyncTaskReminders: false
        )
    }
}
