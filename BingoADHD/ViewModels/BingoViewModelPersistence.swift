import Foundation

struct BingoViewModelPersistenceSnapshot {
    var board: SavedBoard
    var boardCountdownEndsAt: Date?
    var totalPoints: Int
    var lifetimePoints: Int
    var dailyRewardState: DailyRewardState
}

enum BingoViewModelPersistence {
    static func save(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        persistDiary: Bool,
        savedAt: Date
    ) {
        BingoBoardStore.saveBoard(snapshot.board, savedAt: savedAt)
        BingoBoardStore.saveBoardCountdownEndsAt(snapshot.boardCountdownEndsAt)

        if persistDiary {
            BingoDiaryStore.save(board: snapshot.board, on: savedAt)
        } else {
            BingoDiaryStore.syncBoardSnapshotWithoutCounting(board: snapshot.board, on: savedAt)
        }

        savePoints(snapshot)
    }

    static func saveWithExplicitDiaryDelta(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        task: String,
        delta: Int,
        savedAt: Date
    ) {
        BingoBoardStore.saveBoard(snapshot.board, savedAt: savedAt)
        BingoBoardStore.saveBoardCountdownEndsAt(snapshot.boardCountdownEndsAt)
        BingoDiaryStore.applyExplicitTaskDelta(task: task, delta: delta, board: snapshot.board, on: savedAt)
        savePoints(snapshot)
    }

    static func syncDiarySnapshot(_ snapshot: BingoViewModelPersistenceSnapshot) {
        BingoDiaryStore.save(board: snapshot.board)
        savePoints(snapshot)
    }

    private static func savePoints(_ snapshot: BingoViewModelPersistenceSnapshot) {
        PointsStore.saveTotalPoints(snapshot.totalPoints)
        PointsStore.saveLifetimePoints(snapshot.lifetimePoints)
        PointsStore.saveDailyRewardState(snapshot.dailyRewardState)
    }
}
