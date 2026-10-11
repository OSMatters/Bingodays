import Foundation

/// One durable transaction for desktop widgets and Live Activities. Rules and rewards
/// stay in WidgetTaskToggleService; choosing a board is a caller policy.
enum ExternalBoardTaskMutationService {
    enum Target {
        case position(row: Int, col: Int)
        case cell(id: UUID, completed: Bool, version: String)

        func position(in board: BingoBoardStore.NamedBoard, now: Date) -> (row: Int, col: Int)? {
            switch self {
            case let .position(row, col):
                return (row, col)
            case let .cell(id, completed, version):
                let cells = BoardEngine.expandedBoardCache(from: board.board)
                let size = min(max(board.board.gridSize, 2), BoardEngine.maxGridSize)
                for row in 0..<size {
                    for col in 0..<size where cells[row][col].id == id {
                        let cell = cells[row][col]
                        guard cell.isCompleted != completed,
                              BingoBoardActivitySnapshotBuilder.version(cell: cell, board: board, now: now) == version else {
                            return nil
                        }
                        return (row, col)
                    }
                }
                return nil
            }
        }
    }

    static func apply(boardID: UUID, target: Target, selectBoard: Bool, now: Date = .now) -> Bool {
        BingoBoardStore.withBoardPersistenceLock {
            guard recoverPendingEvent() else { return false }
            return commit(boardID: boardID, target: target, selectBoard: selectBoard, now: now)
        } ?? false
    }

    /// Never overwrite the single recovery event with another in-flight transaction.
    private static func recoverPendingEvent() -> Bool {
        guard let event = WidgetTaskSyncStore.load() else { return true }
        let repository = WidgetIntentBoardRepository()
        let original = repository.loadNamedBoardsSnapshot()
        let merged = WidgetTaskEventMerge.applying(event, to: original)
        if !event.sideEffectsCommitted,
           let board = merged.boards.first(where: { $0.id == event.boardID }),
           !WidgetTaskToggleService.reconcileRewards(for: event, mergedBoard: board, now: event.savedAt) {
            return false
        }
        guard merged == original || repository.saveNamedBoardsSnapshot(merged, reloadWidgets: false) else { return false }
        if let active = merged.boards.first(where: { $0.id == merged.selectedBoardID }) {
            let result = BoardStateCommitter.saveActiveBoardState(
                board: active.board, countdownEndsAt: active.countdownEndsAt,
                savedAt: active.updatedAt, associatedBoardID: active.id,
                repository: repository, reloadWidgets: false
            )
            guard !result.failedToSaveBoard else { return false }
        }
        WidgetTaskSyncStore.clear(ifMatching: event.id)
        return true
    }

    private static func commit(
        boardID id: UUID,
        target: Target,
        selectBoard: Bool,
        now: Date
    ) -> Bool {
        let repository = WidgetIntentBoardRepository()

        var snapshot = WidgetTaskEventMerge.applying(
            WidgetTaskSyncStore.load(),
            to: repository.loadNamedBoardsSnapshot()
        )
        let originalSnapshot = snapshot
        guard let index = snapshot.boards.firstIndex(where: { $0.id == id }) else {
            return false
        }

        snapshot.boards[index] = BingoBoardStore.taskRuleRecoveryBoard(snapshot.boards[index])

        let previousBoard = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            snapshot.boards[index],
            now: now
        )
        guard let position = target.position(in: previousBoard, now: now) else { return false }
        let row = position.row
        let col = position.col
        guard let updatedBoard = WidgetTaskToggleService.toggled(
            board: snapshot.boards[index],
            row: row,
            col: col,
            now: now,
            commitSideEffects: false
        ) else {
            return false
        }

        let didApplyBoardReset = updatedBoard.lastTaskResetAppliedAt != snapshot.boards[index].lastTaskResetAppliedAt
        let cellMutation = WidgetTaskToggleService.cellMutation(
            previousBoard: previousBoard.board,
            updatedBoard: updatedBoard.board,
            row: row,
            col: col
        )
        guard let localSyncEvent = WidgetTaskSyncStore.saveEvent(
            board: updatedBoard,
            didApplyBoardReset: didApplyBoardReset,
            cellMutation: cellMutation
        ) else {
            return false
        }
        // The local event is the recovery marker. Settle points before publishing the
        // named-board snapshot so App launch cannot observe a new board with old points.
        let committedSideEffects = NativeICloudLocalChangeReporter.withReportingSuppressed {
            WidgetTaskToggleService.commitToggleSideEffects(
                previousBoard: previousBoard,
                updatedBoard: updatedBoard,
                row: row,
                col: col,
                now: now,
                didApplyBoardReset: didApplyBoardReset
            )
        }
        guard committedSideEffects else {
            return false
        }
        guard let committedSyncEvent = WidgetTaskSyncStore.markSideEffectsCommitted(
            for: localSyncEvent
        ) else {
            return false
        }

        let latestSnapshot = repository.loadNamedBoardsSnapshot()
        snapshot = WidgetTaskEventMerge.applying(WidgetTaskSyncStore.load(), to: latestSnapshot)
        snapshot = TaskCompletionHistoryRuleEngine.namedBoardsSnapshotByReconcilingCompletionHistory(
            snapshot,
            records: TaskCompletionHistoryStore.load()
        )
        let shouldSaveNamedBoards = snapshot != latestSnapshot || snapshot != originalSnapshot
        let savedNamedBoards = shouldSaveNamedBoards
            ? repository.saveNamedBoardsSnapshot(snapshot, reloadWidgets: false)
            : false
        guard !shouldSaveNamedBoards || savedNamedBoards else {
            return false
        }
        if selectBoard {
            guard WidgetBoardSelectionService.selectBoard(id, repository: repository) != nil else { return false }
        } else if let active = snapshot.boards.first(where: { $0.id == snapshot.selectedBoardID }) {
            let result = BoardStateCommitter.saveActiveBoardState(
                board: active.board,
                countdownEndsAt: active.countdownEndsAt,
                savedAt: active.updatedAt,
                associatedBoardID: active.id,
                repository: repository,
                reloadWidgets: false
            )
            guard !result.failedToSaveBoard else { return false }
        }

        // Every local repository is now durable, so the recovery marker can be removed.
        WidgetTaskSyncStore.clear(ifMatching: committedSyncEvent.id)

        return true
    }
}
