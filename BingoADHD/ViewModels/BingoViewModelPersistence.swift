import Foundation

struct BingoViewModelPersistenceSnapshot {
    var board: SavedBoard
    var boardCountdownEndsAt: Date?
    var totalPoints: Int
    var lifetimePoints: Int
    var dailyRewardState: DailyRewardState
}

struct BingoViewModelPersistenceCommitResult: Equatable {
    var savedBoard = false
    var savedBoardCountdown = false
    var updatedDiary = false
    var savedPoints = false
    var reloadedWidgets = false
}

protocol BingoBoardRepository {
    func loadBoard() -> SavedBoard?
    func loadBoardLastSavedAt() -> Date?
    func loadBoardCountdownEndsAt() -> Date?
    func loadActiveNamedBoardID() -> UUID?
    @discardableResult
    func saveBoard(_ board: SavedBoard, savedAt: Date, associatedBoardID: UUID?, reloadWidgets: Bool) -> Bool
    func saveBoardCountdownEndsAt(_ endsAt: Date?)
    func reloadWidgetTimelines()
}

protocol BingoDiaryRepository {
    func save(board: SavedBoard, on date: Date)
    func applyExplicitTaskDelta(task: String, delta: Int, board: SavedBoard, on date: Date)
    func syncBoardSnapshotWithoutCounting(board: SavedBoard, on date: Date)
}

protocol BingoPointsRepository {
    func loadTotalPoints() -> Int?
    func loadLifetimePoints() -> Int?
    func loadDailyRewardState() -> DailyRewardState?
    func saveTotalPoints(_ points: Int)
    func saveLifetimePoints(_ points: Int)
    func saveDailyRewardState(_ state: DailyRewardState)
}

struct BingoViewModelPersistenceDependencies {
    var boardRepository: any BingoBoardRepository
    var diaryRepository: any BingoDiaryRepository
    var pointsRepository: any BingoPointsRepository

    static let live = BingoViewModelPersistenceDependencies(
        boardRepository: LiveBingoBoardRepository(),
        diaryRepository: LiveBingoDiaryRepository(),
        pointsRepository: LiveBingoPointsRepository()
    )
}

private struct LiveBingoBoardRepository: BingoBoardRepository {
    func loadBoard() -> SavedBoard? {
        BingoBoardStore.loadBoard()
    }

    func loadBoardLastSavedAt() -> Date? {
        BingoBoardStore.loadBoardLastSavedAt()
    }

    func loadBoardCountdownEndsAt() -> Date? {
        BingoBoardStore.loadBoardCountdownEndsAt()
    }

    func loadActiveNamedBoardID() -> UUID? {
        BingoBoardStore.loadActiveNamedBoardID()
    }

    func saveBoard(_ board: SavedBoard, savedAt: Date, associatedBoardID: UUID?, reloadWidgets: Bool) -> Bool {
        BingoBoardStore.saveBoard(
            board,
            savedAt: savedAt,
            associatedBoardID: associatedBoardID,
            reloadWidgets: reloadWidgets
        )
    }

    func saveBoardCountdownEndsAt(_ endsAt: Date?) {
        BingoBoardStore.saveBoardCountdownEndsAt(endsAt)
    }

    func reloadWidgetTimelines() {
        BingoBoardStore.reloadWidgetTimelines()
    }
}

private struct LiveBingoDiaryRepository: BingoDiaryRepository {
    func save(board: SavedBoard, on date: Date) {
        BingoDiaryStore.save(board: board, on: date)
    }

    func applyExplicitTaskDelta(task: String, delta: Int, board: SavedBoard, on date: Date) {
        BingoDiaryStore.applyExplicitTaskDelta(task: task, delta: delta, board: board, on: date)
    }

    func syncBoardSnapshotWithoutCounting(board: SavedBoard, on date: Date) {
        BingoDiaryStore.syncBoardSnapshotWithoutCounting(board: board, on: date)
    }
}

private struct LiveBingoPointsRepository: BingoPointsRepository {
    func loadTotalPoints() -> Int? {
        PointsStore.loadTotalPoints()
    }

    func loadLifetimePoints() -> Int? {
        PointsStore.loadLifetimePoints()
    }

    func loadDailyRewardState() -> DailyRewardState? {
        PointsStore.loadDailyRewardState()
    }

    func saveTotalPoints(_ points: Int) {
        PointsStore.saveTotalPoints(points)
    }

    func saveLifetimePoints(_ points: Int) {
        PointsStore.saveLifetimePoints(points)
    }

    func saveDailyRewardState(_ state: DailyRewardState) {
        PointsStore.saveDailyRewardState(state)
    }
}

enum BingoViewModelPersistence {
    @discardableResult
    static func save(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        persistDiary: Bool,
        savedAt: Date,
        dependencies: BingoViewModelPersistenceDependencies = .live
    ) -> BingoViewModelPersistenceCommitResult {
        var result = saveBoardState(snapshot, savedAt: savedAt, dependencies: dependencies)

        if persistDiary {
            dependencies.diaryRepository.save(board: snapshot.board, on: savedAt)
        } else {
            dependencies.diaryRepository.syncBoardSnapshotWithoutCounting(board: snapshot.board, on: savedAt)
        }
        result.updatedDiary = true

        savePoints(snapshot, dependencies: dependencies)
        result.savedPoints = true

        reloadWidgetsIfNeeded(&result, dependencies: dependencies)

        return result
    }

    @discardableResult
    static func saveWithExplicitDiaryDelta(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        task: String,
        delta: Int,
        savedAt: Date,
        dependencies: BingoViewModelPersistenceDependencies = .live
    ) -> BingoViewModelPersistenceCommitResult {
        var result = saveBoardState(snapshot, savedAt: savedAt, dependencies: dependencies)
        dependencies.diaryRepository.applyExplicitTaskDelta(
            task: task,
            delta: delta,
            board: snapshot.board,
            on: savedAt
        )
        result.updatedDiary = true
        savePoints(snapshot, dependencies: dependencies)
        result.savedPoints = true

        reloadWidgetsIfNeeded(&result, dependencies: dependencies)

        return result
    }

    @discardableResult
    static func syncDiarySnapshot(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        dependencies: BingoViewModelPersistenceDependencies = .live
    ) -> BingoViewModelPersistenceCommitResult {
        var result = BingoViewModelPersistenceCommitResult()
        dependencies.diaryRepository.save(board: snapshot.board, on: .now)
        result.updatedDiary = true
        savePoints(snapshot, dependencies: dependencies)
        result.savedPoints = true

        return result
    }

    private static func saveBoardState(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        savedAt: Date,
        dependencies: BingoViewModelPersistenceDependencies
    ) -> BingoViewModelPersistenceCommitResult {
        var result = BingoViewModelPersistenceCommitResult()
        result.savedBoard = dependencies.boardRepository.saveBoard(
            snapshot.board,
            savedAt: savedAt,
            associatedBoardID: nil,
            reloadWidgets: false
        )
        dependencies.boardRepository.saveBoardCountdownEndsAt(snapshot.boardCountdownEndsAt)
        result.savedBoardCountdown = true
        return result
    }

    private static func reloadWidgetsIfNeeded(
        _ result: inout BingoViewModelPersistenceCommitResult,
        dependencies: BingoViewModelPersistenceDependencies
    ) {
        guard result.savedBoard else { return }
        dependencies.boardRepository.reloadWidgetTimelines()
        result.reloadedWidgets = true
    }

    private static func savePoints(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        dependencies: BingoViewModelPersistenceDependencies
    ) {
        dependencies.pointsRepository.saveTotalPoints(snapshot.totalPoints)
        dependencies.pointsRepository.saveLifetimePoints(snapshot.lifetimePoints)
        dependencies.pointsRepository.saveDailyRewardState(snapshot.dailyRewardState)
    }
}
