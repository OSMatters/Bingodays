import Foundation
import XCTest
@testable import Bingodays

/// Integration-test adapter: no model objects survive a read/write boundary.
/// Uses production Codable types and board normalization, but never the app's files.
final class OperationPersistenceRepository: BingoBoardRepository, BingoDiaryRepository,
    BingoPointsRepository, TaskCompletionHistoryRepository,
    BingoPersistenceTransactionRepository, TaskLibraryRepository {
    enum Write: Hashable { case board, points, transaction, clearTransaction, library }

    private struct BoardState: Codable {
        var board: SavedBoard?
        var savedAt: Date?
        var boardID: UUID?
    }

    let directory: URL
    var rejectedWrites: Set<Write> = []

    init(directory: URL) {
        self.directory = directory
    }

    var dependencies: BingoViewModelPersistenceDependencies {
        .init(boardRepository: self, diaryRepository: self, pointsRepository: self,
              completionHistoryRepository: self, transactionRepository: self,
              taskLibraryRepository: self)
    }

    func reopened() -> OperationPersistenceRepository {
        OperationPersistenceRepository(directory: directory)
    }

    private func read<Value: Decodable>(_ name: String, as type: Value.Type = Value.self) -> Value? {
        let url = directory.appendingPathComponent(name + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            XCTFail("Could not read integration fixture \(url.path): \(error)")
            return nil
        }
    }

    @discardableResult
    private func write<Value: Encodable>(_ value: Value, to name: String) -> Bool {
        let url = directory.appendingPathComponent(name + ".json")
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            XCTFail("Could not write integration fixture \(url.path): \(error)")
            return false
        }
    }

    private func remove(_ name: String) -> Bool {
        let url = directory.appendingPathComponent(name + ".json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            XCTFail("Could not remove integration fixture \(url.path): \(error)")
            return false
        }
    }

    private var boardState: BoardState {
        read("board") ?? BoardState()
    }

    func loadBoard() -> SavedBoard? { boardState.board }
    func loadBoardLastSavedAt() -> Date? { boardState.savedAt }
    func loadActiveNamedBoardID() -> UUID? { boardState.boardID }
    func loadBoardCountdownEndsAt() -> Date? { read("board-countdown") }

    @discardableResult
    func saveBoard(_ board: SavedBoard, savedAt: Date, associatedBoardID: UUID?, reloadWidgets: Bool) -> Bool {
        guard !rejectedWrites.contains(.board) else { return false }
        return write(BoardState(
            board: BingoBoardStore.normalizedBoardForPersistence(board, referenceDate: savedAt),
            savedAt: savedAt, boardID: associatedBoardID
        ), to: "board")
    }

    func saveBoardCountdownEndsAt(_ endsAt: Date?) {
        if let endsAt { write(endsAt, to: "board-countdown") }
        else { _ = remove("board-countdown") }
    }

    func reloadWidgetTimelines() {}

    func loadAllEntriesDictionary() -> [String: BingoDiaryEntry] { read("diary") ?? [:] }
    func replaceAllEntriesDictionary(_ entries: [String: BingoDiaryEntry]) { write(entries, to: "diary") }

    func loadPersistenceSnapshot() -> PointsPersistenceSnapshot {
        read("points") ?? .init(totalPoints: nil, lifetimePoints: nil, dailyRewardState: nil)
    }
    func loadTotalPoints() -> Int? { loadPersistenceSnapshot().totalPoints }
    func loadLifetimePoints() -> Int? { loadPersistenceSnapshot().lifetimePoints }
    func loadDailyRewardState() -> DailyRewardState? { loadPersistenceSnapshot().dailyRewardState }
    func saveTotalPoints(_ points: Int) {
        let state = loadPersistenceSnapshot()
        write(PointsPersistenceSnapshot(totalPoints: points, lifetimePoints: state.lifetimePoints,
              dailyRewardState: state.dailyRewardState), to: "points")
    }
    func saveLifetimePoints(_ points: Int) {
        let state = loadPersistenceSnapshot()
        write(PointsPersistenceSnapshot(totalPoints: state.totalPoints, lifetimePoints: points,
              dailyRewardState: state.dailyRewardState), to: "points")
    }
    func saveDailyRewardState(_ state: DailyRewardState) {
        let previous = loadPersistenceSnapshot()
        write(PointsPersistenceSnapshot(totalPoints: previous.totalPoints, lifetimePoints: previous.lifetimePoints,
              dailyRewardState: state), to: "points")
    }
    func saveState(totalPoints: Int, lifetimePoints: Int, dailyRewardState: DailyRewardState) -> Bool {
        guard !rejectedWrites.contains(.points) else { return false }
        return write(PointsPersistenceSnapshot(totalPoints: totalPoints, lifetimePoints: lifetimePoints,
                     dailyRewardState: dailyRewardState), to: "points")
    }

    func loadCompletionHistory() -> [TaskCompletionHistoryRecord] { read("completion-history") ?? [] }
    func replaceCompletionHistory(_ records: [TaskCompletionHistoryRecord]) -> Bool {
        write(TaskCompletionHistoryRuleEngine.normalizedRecords(records), to: "completion-history")
    }

    func loadPendingTransaction() -> BingoPendingPersistenceTransaction? { read("transaction") }
    func savePendingTransaction(_ transaction: BingoPendingPersistenceTransaction) -> Bool {
        guard !rejectedWrites.contains(.transaction) else { return false }
        return write(transaction, to: "transaction")
    }
    func clearPendingTransaction() -> Bool {
        guard !rejectedWrites.contains(.clearTransaction) else { return false }
        return remove("transaction")
    }

    func loadLibrary() -> MyTasksLibrary { read("library") ?? .init() }
    func saveLibrary(_ library: MyTasksLibrary) -> Bool {
        guard !rejectedWrites.contains(.library) else { return false }
        return write(library, to: "library")
    }
    func loadPendingEdit() -> TaskLibraryEditJournal? { read("library-edit") }
    func savePendingEdit(_ edit: TaskLibraryEditJournal) -> Bool { write(edit, to: "library-edit") }
    func clearPendingEdit() -> Bool { remove("library-edit") }
}
