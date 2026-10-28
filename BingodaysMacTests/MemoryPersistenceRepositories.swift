import Foundation

final class InMemoryBingoBoardRepository: BingoBoardRepository {
    var board: SavedBoard?
    private(set) var saveBoardCallCount = 0
    private(set) var saveCountdownCallCount = 0
    private(set) var reloadWidgetCallCount = 0
    private var savedAt: Date?
    private var countdownEndsAt: Date?
    private var activeNamedBoardID: UUID?
    var shouldFailBoardSave: Bool

    init(
        board: SavedBoard?,
        savedAt: Date?,
        countdownEndsAt: Date? = nil,
        activeNamedBoardID: UUID? = nil,
        shouldFailBoardSave: Bool = false
    ) {
        self.board = board
        self.savedAt = savedAt
        self.countdownEndsAt = countdownEndsAt
        self.activeNamedBoardID = activeNamedBoardID
        self.shouldFailBoardSave = shouldFailBoardSave
    }

    func loadBoard() -> SavedBoard? {
        board
    }

    func loadBoardLastSavedAt() -> Date? {
        savedAt
    }

    func loadBoardCountdownEndsAt() -> Date? {
        countdownEndsAt
    }

    func loadActiveNamedBoardID() -> UUID? {
        activeNamedBoardID
    }

    func saveBoard(_ board: SavedBoard, savedAt: Date, associatedBoardID: UUID?, reloadWidgets: Bool) -> Bool {
        saveBoardCallCount += 1
        guard !shouldFailBoardSave else { return false }
        self.board = board
        self.savedAt = savedAt
        activeNamedBoardID = associatedBoardID
        return true
    }

    func saveBoardCountdownEndsAt(_ endsAt: Date?) {
        saveCountdownCallCount += 1
        countdownEndsAt = endsAt
    }

    func reloadWidgetTimelines() {
        reloadWidgetCallCount += 1
    }
}
final class InMemoryBingoDiaryRepository: BingoDiaryRepository {
    private(set) var replaceCallCount = 0
    private var entries: [String: BingoDiaryEntry]
    private let roundTripsThroughCodable: Bool

    init(
        entries: [String: BingoDiaryEntry] = [:],
        roundTripsThroughCodable: Bool = false
    ) {
        self.entries = entries
        self.roundTripsThroughCodable = roundTripsThroughCodable
    }

    func loadAllEntriesDictionary() -> [String: BingoDiaryEntry] {
        entries
    }

    func replaceAllEntriesDictionary(_ entries: [String: BingoDiaryEntry]) {
        replaceCallCount += 1
        if roundTripsThroughCodable,
           let data = try? JSONEncoder().encode(entries),
           let decoded = try? JSONDecoder().decode([String: BingoDiaryEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = entries
        }
    }
}

final class InMemoryTaskCompletionHistoryRepository: TaskCompletionHistoryRepository {
    private var records: [TaskCompletionHistoryRecord]
    private(set) var loadCallCount = 0

    init(records: [TaskCompletionHistoryRecord] = []) {
        self.records = TaskCompletionHistoryRuleEngine.normalizedRecords(records)
    }

    func loadCompletionHistory() -> [TaskCompletionHistoryRecord] {
        loadCallCount += 1
        return records
    }

    func replaceCompletionHistory(_ records: [TaskCompletionHistoryRecord]) -> Bool {
        self.records = TaskCompletionHistoryRuleEngine.normalizedRecords(records)
        return true
    }
}

final class InMemoryBingoPointsRepository: BingoPointsRepository {
    private(set) var saveStateCallCount = 0
    private var totalPoints: Int?
    private var lifetimePoints: Int?
    private var dailyRewardState: DailyRewardState?

    init(
        totalPoints: Int? = nil,
        lifetimePoints: Int? = nil,
        dailyRewardState: DailyRewardState? = nil
    ) {
        self.totalPoints = totalPoints
        self.lifetimePoints = lifetimePoints
        self.dailyRewardState = dailyRewardState
    }

    func loadTotalPoints() -> Int? {
        totalPoints
    }

    func loadLifetimePoints() -> Int? {
        lifetimePoints
    }

    func loadDailyRewardState() -> DailyRewardState? {
        dailyRewardState
    }

    func saveTotalPoints(_ points: Int) {
        totalPoints = points
    }

    func saveLifetimePoints(_ points: Int) {
        lifetimePoints = points
    }

    func saveDailyRewardState(_ state: DailyRewardState) {
        dailyRewardState = state
    }

    func saveState(totalPoints: Int, lifetimePoints: Int, dailyRewardState: DailyRewardState) -> Bool {
        saveStateCallCount += 1
        self.totalPoints = totalPoints
        self.lifetimePoints = lifetimePoints
        self.dailyRewardState = dailyRewardState
        return true
    }
}

final class InMemoryBingoPersistenceTransactionRepository: BingoPersistenceTransactionRepository {
    private(set) var pendingTransaction: BingoPendingPersistenceTransaction?
    private(set) var saveCallCount = 0
    private(set) var clearCallCount = 0
    private(set) var lastEncodedTransactionData: Data?
    var shouldFailSave = false
    var shouldFailClear = false

    init(pendingTransaction: BingoPendingPersistenceTransaction? = nil) {
        self.pendingTransaction = pendingTransaction
    }

    func loadPendingTransaction() -> BingoPendingPersistenceTransaction? {
        pendingTransaction
    }

    func savePendingTransaction(_ transaction: BingoPendingPersistenceTransaction) -> Bool {
        saveCallCount += 1
        guard !shouldFailSave else { return false }
        pendingTransaction = transaction
        return true
    }

    func savePendingTransaction(_ transaction: BingoPendingPersistenceTransaction, encodedData: Data) -> Bool {
        lastEncodedTransactionData = encodedData
        return savePendingTransaction(transaction)
    }

    func clearPendingTransaction() -> Bool {
        clearCallCount += 1
        guard !shouldFailClear else { return false }
        pendingTransaction = nil
        return true
    }
}
