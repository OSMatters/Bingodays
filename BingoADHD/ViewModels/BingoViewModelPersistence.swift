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
    var failedToSaveBoard = false
    var failedToSaveTransaction = false
    var savedBoardCountdown = false
    var updatedDiary = false
    var savedPoints = false
    var reloadedWidgets = false

    init() {}

    init(boardStateCommit: BoardStateCommitResult) {
        savedBoard = boardStateCommit.savedBoard
        failedToSaveBoard = boardStateCommit.failedToSaveBoard
        savedBoardCountdown = boardStateCommit.savedBoardCountdown
        reloadedWidgets = boardStateCommit.reloadedWidgets
    }

    mutating func apply(_ boardStateCommit: BoardStateCommitResult) {
        savedBoard = boardStateCommit.savedBoard
        failedToSaveBoard = boardStateCommit.failedToSaveBoard
        savedBoardCountdown = boardStateCommit.savedBoardCountdown
        reloadedWidgets = boardStateCommit.reloadedWidgets
    }
}

protocol BingoBoardRepository: BoardStateCommitRepository {
    func loadBoardLastSavedAt() -> Date?
    func withTaskEditLock(_ operation: () -> Bool) -> Bool
    func saveTaskEditBoard(_ board: SavedBoard, expected: SavedBoard?, boardID: UUID?, savedAt: Date, explicitlyEditedCellIDs: Set<UUID>) -> Bool
}

extension BingoBoardRepository {
    func withTaskEditLock(_ operation: () -> Bool) -> Bool { operation() }

    func saveTaskEditBoard(_ board: SavedBoard, expected: SavedBoard?, boardID: UUID?, savedAt: Date, explicitlyEditedCellIDs: Set<UUID> = []) -> Bool {
        guard loadBoard() == expected, loadActiveNamedBoardID() == boardID else { return false }
        guard TaskRulePersistenceGuard.downgradedCellIDs(from: expected, to: board)
            .subtracting(explicitlyEditedCellIDs).isEmpty else { return false }
        guard saveBoard(board, savedAt: savedAt, associatedBoardID: boardID, reloadWidgets: false),
              let persisted = loadBoard() else { return false }
        return BingoBoardStore.normalizedBoardForPersistence(persisted, referenceDate: savedAt) ==
            BingoBoardStore.normalizedBoardForPersistence(board, referenceDate: savedAt)
    }
}

protocol BingoDiaryRepository {
    func loadAllEntriesDictionary() -> [String: BingoDiaryEntry]
    func replaceAllEntriesDictionary(_ entries: [String: BingoDiaryEntry])
}

protocol BingoPointsRepository {
    func loadPersistenceSnapshot() -> PointsPersistenceSnapshot
    func loadTotalPoints() -> Int?
    func loadLifetimePoints() -> Int?
    func loadDailyRewardState() -> DailyRewardState?
    func saveTotalPoints(_ points: Int)
    func saveLifetimePoints(_ points: Int)
    func saveDailyRewardState(_ state: DailyRewardState)
    func saveState(totalPoints: Int, lifetimePoints: Int, dailyRewardState: DailyRewardState) -> Bool
}

protocol TaskCompletionHistoryRepository {
    func loadCompletionHistory() -> [TaskCompletionHistoryRecord]
    func replaceCompletionHistory(_ records: [TaskCompletionHistoryRecord]) -> Bool
}

extension BingoPointsRepository {
    func loadPersistenceSnapshot() -> PointsPersistenceSnapshot {
        PointsPersistenceSnapshot(
            totalPoints: loadTotalPoints(),
            lifetimePoints: loadLifetimePoints(),
            dailyRewardState: loadDailyRewardState()
        )
    }
}

struct BingoPendingPersistenceTransaction: Codable, Equatable {
    struct BoardState: Codable, Equatable {
        var board: SavedBoard
        var countdownEndsAt: Date?
        var savedAt: Date
        var associatedBoardID: UUID?
    }

    let id: UUID
    var boardState: BoardState?
    var diaryEntries: [String: BingoDiaryEntry]
    var taskCompletionHistory: [TaskCompletionHistoryRecord]
    var totalPoints: Int
    var lifetimePoints: Int
    var dailyRewardState: DailyRewardState

    init(
        id: UUID = UUID(),
        boardState: BoardState?,
        diaryEntries: [String: BingoDiaryEntry],
        taskCompletionHistory: [TaskCompletionHistoryRecord] = [],
        totalPoints: Int,
        lifetimePoints: Int,
        dailyRewardState: DailyRewardState
    ) {
        self.id = id
        self.boardState = boardState
        self.diaryEntries = diaryEntries
        self.taskCompletionHistory = taskCompletionHistory
        self.totalPoints = totalPoints
        self.lifetimePoints = lifetimePoints
        self.dailyRewardState = dailyRewardState
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case boardState
        case diaryEntries
        case taskCompletionHistory
        case totalPoints
        case lifetimePoints
        case dailyRewardState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        boardState = try container.decodeIfPresent(BoardState.self, forKey: .boardState)
        diaryEntries = try container.decode([String: BingoDiaryEntry].self, forKey: .diaryEntries)
        // Transactions written before the live history total did not carry this
        // snapshot. They remain valid and replay with the current history.
        taskCompletionHistory = try container.decodeIfPresent(
            [TaskCompletionHistoryRecord].self,
            forKey: .taskCompletionHistory
        ) ?? []
        totalPoints = try container.decode(Int.self, forKey: .totalPoints)
        lifetimePoints = try container.decode(Int.self, forKey: .lifetimePoints)
        dailyRewardState = try container.decode(DailyRewardState.self, forKey: .dailyRewardState)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(boardState, forKey: .boardState)
        try container.encode(diaryEntries, forKey: .diaryEntries)
        try container.encode(taskCompletionHistory, forKey: .taskCompletionHistory)
        try container.encode(totalPoints, forKey: .totalPoints)
        try container.encode(lifetimePoints, forKey: .lifetimePoints)
        try container.encode(dailyRewardState, forKey: .dailyRewardState)
    }
}

protocol BingoPersistenceTransactionRepository {
    func loadPendingTransaction() -> BingoPendingPersistenceTransaction?
    func savePendingTransaction(_ transaction: BingoPendingPersistenceTransaction) -> Bool
    func clearPendingTransaction() -> Bool
}

struct BingoViewModelPersistenceDependencies {
    var boardRepository: any BingoBoardRepository
    var diaryRepository: any BingoDiaryRepository
    var pointsRepository: any BingoPointsRepository
    var completionHistoryRepository: any TaskCompletionHistoryRepository
    var transactionRepository: any BingoPersistenceTransactionRepository

    init(
        boardRepository: any BingoBoardRepository,
        diaryRepository: any BingoDiaryRepository,
        pointsRepository: any BingoPointsRepository,
        completionHistoryRepository: any TaskCompletionHistoryRepository = LiveTaskCompletionHistoryRepository(),
        transactionRepository: any BingoPersistenceTransactionRepository = LiveBingoPersistenceTransactionRepository()
    ) {
        self.boardRepository = boardRepository
        self.diaryRepository = diaryRepository
        self.pointsRepository = pointsRepository
        self.completionHistoryRepository = completionHistoryRepository
        self.transactionRepository = transactionRepository
    }

    static let live = BingoViewModelPersistenceDependencies(
        boardRepository: LiveBingoBoardRepository(),
        diaryRepository: LiveBingoDiaryRepository(),
        pointsRepository: LiveBingoPointsRepository()
    )
}

private struct LiveTaskCompletionHistoryRepository: TaskCompletionHistoryRepository {
    func loadCompletionHistory() -> [TaskCompletionHistoryRecord] {
        _ = TaskCompletionHistoryStore.ensureMigrated()
        return TaskCompletionHistoryStore.load()
    }

    func replaceCompletionHistory(_ records: [TaskCompletionHistoryRecord]) -> Bool {
        TaskCompletionHistoryStore.save(records)
    }
}

protocol WidgetTimelineReloadScheduling: Sendable {
    func requestReload()
}

final class WidgetTimelineReloadScheduler: WidgetTimelineReloadScheduling, @unchecked Sendable {
    static let shared = WidgetTimelineReloadScheduler()

    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let reload: @Sendable () -> Void
    private let lock = NSLock()
    private var generation: UInt = 0

    init(
        delay: TimeInterval = 0.15,
        queue: DispatchQueue = .main,
        reload: @escaping @Sendable () -> Void = {
            BingoBoardStore.reloadWidgetTimelines()
        }
    ) {
        self.delay = delay
        self.queue = queue
        self.reload = reload
    }

    func requestReload() {
        lock.lock()
        generation &+= 1
        let scheduledGeneration = generation
        lock.unlock()

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performReloadIfCurrent(generation: scheduledGeneration)
        }
    }

    private func performReloadIfCurrent(generation scheduledGeneration: UInt) {
        lock.lock()
        guard generation == scheduledGeneration else {
            lock.unlock()
            return
        }
        lock.unlock()
        reload()
    }
}

private struct LiveBingoBoardRepository: BingoBoardRepository {
    private let widgetTimelineReloadScheduler: any WidgetTimelineReloadScheduling

    init(
        widgetTimelineReloadScheduler: any WidgetTimelineReloadScheduling = WidgetTimelineReloadScheduler.shared
    ) {
        self.widgetTimelineReloadScheduler = widgetTimelineReloadScheduler
    }

    func loadBoard() -> SavedBoard? {
        BingoBoardStore.loadBoard()
    }

    func withTaskEditLock(_ operation: () -> Bool) -> Bool {
        BingoBoardStore.withBoardPersistenceLock(operation) ?? false
    }

    func saveTaskEditBoard(_ board: SavedBoard, expected: SavedBoard?, boardID: UUID?, savedAt: Date, explicitlyEditedCellIDs: Set<UUID>) -> Bool {
        BingoBoardStore.withBoardPersistenceLock {
            guard BingoBoardStore.loadBoard() == expected,
                  BingoBoardStore.loadActiveNamedBoardID() == boardID else {
                DiagnosticLogStore.recordWarning("task_edit.stale_write_rejected")
                return false
            }
            guard BingoBoardStore.saveBoard(
                board, savedAt: savedAt, associatedBoardID: boardID, reloadWidgets: false,
                explicitlyEditedCellIDs: explicitlyEditedCellIDs
            ) else { return false }
            return BingoBoardStore.loadBoard() == BingoBoardStore.normalizedBoardForPersistence(board, referenceDate: savedAt)
        } ?? false
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
        let didSave = BingoBoardStore.saveBoard(
            board,
            savedAt: savedAt,
            associatedBoardID: associatedBoardID,
            reloadWidgets: false
        )
        if didSave, reloadWidgets {
            widgetTimelineReloadScheduler.requestReload()
        }
        return didSave
    }

    func saveBoardCountdownEndsAt(_ endsAt: Date?) {
        BingoBoardStore.saveBoardCountdownEndsAt(endsAt)
    }

    func reloadWidgetTimelines() {
        widgetTimelineReloadScheduler.requestReload()
    }
}

private struct LiveBingoDiaryRepository: BingoDiaryRepository {
    func loadAllEntriesDictionary() -> [String: BingoDiaryEntry] {
        BingoDiaryStore.loadAllEntriesDictionary()
    }

    func replaceAllEntriesDictionary(_ entries: [String: BingoDiaryEntry]) {
        BingoDiaryStore.replaceAllEntriesDictionary(entries)
    }
}

private struct LiveBingoPointsRepository: BingoPointsRepository {
    func loadPersistenceSnapshot() -> PointsPersistenceSnapshot {
        PointsStore.loadPersistenceSnapshot()
    }

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

    func saveState(totalPoints: Int, lifetimePoints: Int, dailyRewardState: DailyRewardState) -> Bool {
        PointsStore.saveState(
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState
        )
    }
}

struct LiveBingoPersistenceTransactionRepository: BingoPersistenceTransactionRepository {
    // V1/V2 transactions were created before the entire transaction was
    // canonicalized through Codable and could be replayed alternately on every
    // tap. Start a clean journal after the persistence-equivalence fix.
    private static let fileName = "bingo_pending_persistence_transaction_v3.json"
    private static let legacyFileNames = [
        "bingo_pending_persistence_transaction_v1.json",
        "bingo_pending_persistence_transaction_v2.json"
    ]

    init() {
        Self.repairAndRetireLegacyTransactionIfNeeded()
    }

    func loadPendingTransaction() -> BingoPendingPersistenceTransaction? {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return nil }
        return try? JSONDecoder().decode(BingoPendingPersistenceTransaction.self, from: data)
    }

    func savePendingTransaction(_ transaction: BingoPendingPersistenceTransaction) -> Bool {
        guard let data = try? JSONEncoder().encode(transaction) else { return false }
        do {
            try data.write(to: Self.fileURL, options: .atomic)
            return (try? Data(contentsOf: Self.fileURL)) == data
        } catch {
            return false
        }
    }

    func clearPendingTransaction() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: Self.fileURL.path) {
                try FileManager.default.removeItem(at: Self.fileURL)
            }
            return !FileManager.default.fileExists(atPath: Self.fileURL.path)
        } catch {
            return false
        }
    }

    private static var fileURL: URL {
        transactionFileURL(named: fileName)
    }

    private static var legacyFileURLs: [URL] {
        legacyFileNames.map(transactionFileURL(named:))
    }

    private static func transactionFileURL(named fileName: String) -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent("Bingodays", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    private static func repairAndRetireLegacyTransactionIfNeeded() {
        let existingLegacyURLs = legacyFileURLs.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !existingLegacyURLs.isEmpty else { return }
        defer {
            for url in existingLegacyURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard let baseline = DiagnosticLogStore.pointsBaselineBeforeLatestFailedTransactionEpisode() else {
            DiagnosticLogStore.recordWarning("points.legacy_transaction_discarded")
            return
        }

        let current = PointsStore.loadPersistenceSnapshot()
        let repaired = PointsPersistenceSnapshot(
            totalPoints: baseline.totalPoints,
            lifetimePoints: baseline.lifetimePoints,
            dailyRewardState: current.dailyRewardState
        )
        guard PointsStore.replacePersistenceSnapshot(repaired) else {
            DiagnosticLogStore.recordWarning(
                "points.legacy_transaction_repair_failed",
                details: [
                    "target_total": "\(baseline.totalPoints)",
                    "target_lifetime": "\(baseline.lifetimePoints)"
                ]
            )
            return
        }
        DiagnosticLogStore.recordStateChange(
            "points.legacy_transaction_repaired",
            details: [
                "before_total": current.totalPoints.map(String.init) ?? "nil",
                "after_total": "\(baseline.totalPoints)",
                "after_lifetime": "\(baseline.lifetimePoints)"
            ]
        )
    }
}

enum BingoViewModelPersistence {
    private enum DiaryMutation {
        case inferred
        case explicit(task: String, delta: Int)
        case snapshotOnly
    }

    @discardableResult
    static func save(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        persistDiary: Bool,
        savedAt: Date,
        dependencies: BingoViewModelPersistenceDependencies = .live
    ) -> BingoViewModelPersistenceCommitResult {
        commitNewTransaction(
            makeTransaction(
                snapshot: snapshot,
                savedAt: savedAt,
                boardStateIncluded: true,
                diaryMutation: persistDiary ? .inferred : .snapshotOnly,
                dependencies: dependencies
            ),
            dependencies: dependencies
        )
    }

    @discardableResult
    static func saveWithExplicitDiaryDelta(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        task: String,
        delta: Int,
        completionHistoryDelta: Int = 0,
        savedAt: Date,
        dependencies: BingoViewModelPersistenceDependencies = .live
    ) -> BingoViewModelPersistenceCommitResult {
        commitNewTransaction(
            makeTransaction(
                snapshot: snapshot,
                savedAt: savedAt,
                boardStateIncluded: true,
                diaryMutation: .explicit(task: task, delta: delta),
                completionHistoryTask: completionHistoryDelta == 0 ? nil : task,
                completionHistoryDelta: completionHistoryDelta,
                dependencies: dependencies
            ),
            dependencies: dependencies,
            forceCloudReport: true
        )
    }

    @discardableResult
    static func syncDiarySnapshot(
        _ snapshot: BingoViewModelPersistenceSnapshot,
        dependencies: BingoViewModelPersistenceDependencies = .live
    ) -> BingoViewModelPersistenceCommitResult {
        let now = Date()
        return commitNewTransaction(
            makeTransaction(
                snapshot: snapshot,
                savedAt: now,
                boardStateIncluded: false,
                diaryMutation: .inferred,
                dependencies: dependencies
            ),
            dependencies: dependencies
        )
    }

    @discardableResult
    static func recoverPendingTransactionIfNeeded(
        dependencies: BingoViewModelPersistenceDependencies = .live
    ) -> BingoViewModelPersistenceCommitResult? {
        guard let transaction = dependencies.transactionRepository.loadPendingTransaction() else {
            return nil
        }
        DiagnosticLogStore.recordWarning("persistence.recovery_started", details: [
            "transaction_id": transaction.id.uuidString,
            "board_id": transaction.boardState?.associatedBoardID.map { String($0.uuidString.prefix(8)) } ?? "none",
            "saved_at": transaction.boardState.map { String($0.savedAt.timeIntervalSince1970) } ?? "none"
        ])
        return commit(transaction, dependencies: dependencies, forceCloudReport: true)
    }

    private static func makeTransaction(
        snapshot: BingoViewModelPersistenceSnapshot,
        savedAt: Date,
        boardStateIncluded: Bool,
        diaryMutation: DiaryMutation,
        completionHistoryTask: String? = nil,
        completionHistoryDelta: Int = 0,
        dependencies: BingoViewModelPersistenceDependencies
    ) -> BingoPendingPersistenceTransaction {
        let existingEntries = dependencies.diaryRepository.loadAllEntriesDictionary()
        let diaryEntries: [String: BingoDiaryEntry]
        switch diaryMutation {
        case .inferred:
            diaryEntries = BingoDiaryStore.entriesBySaving(
                board: snapshot.board,
                on: savedAt,
                entries: existingEntries
            )
        case let .explicit(task, delta):
            diaryEntries = BingoDiaryStore.entriesByApplyingExplicitTaskDelta(
                task: task,
                delta: delta,
                board: snapshot.board,
                on: savedAt,
                entries: existingEntries
            )
        case .snapshotOnly:
            diaryEntries = BingoDiaryStore.entriesBySyncingBoardSnapshotWithoutCounting(
                board: snapshot.board,
                on: savedAt,
                entries: existingEntries
            )
        }

        // The live board store removes unsupported timing fields from repeating
        // tasks before writing. Keep the pending transaction in that same canonical
        // form so the read-after-write verification does not reject a successful
        // save and leave an old points transaction queued for the next tap.
        let boardForPersistence = BingoBoardStore.normalizedBoardForPersistence(
            snapshot.board,
            referenceDate: savedAt
        )
        let boardState = boardStateIncluded
            ? BingoPendingPersistenceTransaction.BoardState(
                board: boardForPersistence,
                countdownEndsAt: snapshot.boardCountdownEndsAt,
                savedAt: savedAt,
                associatedBoardID: dependencies.boardRepository.loadActiveNamedBoardID()
            )
            : nil
        let existingHistory = dependencies.completionHistoryRepository.loadCompletionHistory()
        let taskCompletionHistory: [TaskCompletionHistoryRecord]
        if let completionHistoryTask {
            taskCompletionHistory = TaskCompletionHistoryRuleEngine.recordsByApplyingCompletionDelta(
                taskText: completionHistoryTask,
                delta: completionHistoryDelta,
                to: existingHistory,
                at: savedAt
            )
        } else {
            taskCompletionHistory = existingHistory
        }
        return BingoPendingPersistenceTransaction(
            boardState: boardState,
            diaryEntries: diaryEntries,
            taskCompletionHistory: taskCompletionHistory,
            totalPoints: snapshot.totalPoints,
            lifetimePoints: snapshot.lifetimePoints,
            dailyRewardState: snapshot.dailyRewardState
        )
    }

    private static func commitNewTransaction(
        _ transaction: BingoPendingPersistenceTransaction,
        dependencies: BingoViewModelPersistenceDependencies,
        forceCloudReport: Bool = false
    ) -> BingoViewModelPersistenceCommitResult {
        if let pendingTransaction = dependencies.transactionRepository.loadPendingTransaction() {
            let recoveryResult = commit(
                pendingTransaction,
                dependencies: dependencies,
                forceCloudReport: true
            )
            guard dependencies.transactionRepository.loadPendingTransaction() == nil else {
                return recoveryResult
            }
        }
        // Commit exactly the Codable representation that can be recovered after a
        // process exit. UI-only BingoCell fields are deliberately not encoded; if
        // the in-memory object is committed directly, board/diary read-back checks
        // reject their own successful writes and the next tap replays stale points.
        guard let transactionData = try? JSONEncoder().encode(transaction),
              let durableTransaction = try? JSONDecoder().decode(
                BingoPendingPersistenceTransaction.self,
                from: transactionData
              ) else {
            DiagnosticLogStore.recordWarning(
                "points.persistence_failed",
                details: [
                    "stage": "canonicalize_transaction",
                    "target_total": "\(transaction.totalPoints)",
                    "target_lifetime": "\(transaction.lifetimePoints)"
                ]
            )
            var result = BingoViewModelPersistenceCommitResult()
            result.failedToSaveTransaction = true
            return result
        }
        guard dependencies.transactionRepository.savePendingTransaction(durableTransaction),
              dependencies.transactionRepository.loadPendingTransaction() == durableTransaction else {
            DiagnosticLogStore.recordWarning(
                "points.persistence_failed",
                details: [
                    "stage": "save_pending_transaction",
                    "target_total": "\(transaction.totalPoints)",
                    "target_lifetime": "\(transaction.lifetimePoints)"
                ]
            )
            var result = BingoViewModelPersistenceCommitResult()
            result.failedToSaveTransaction = true
            return result
        }
        return commit(
            durableTransaction,
            dependencies: dependencies,
            forceCloudReport: forceCloudReport
        )
    }

    private static func commit(
        _ transaction: BingoPendingPersistenceTransaction,
        dependencies: BingoViewModelPersistenceDependencies,
        forceCloudReport: Bool = false
    ) -> BingoViewModelPersistenceCommitResult {
        // A V3 journal may have been written before completion history was part
        // of the transaction. Never let that legacy replay erase a newer total.
        let completionHistoryToPersist = transaction.taskCompletionHistory.isEmpty
            ? dependencies.completionHistoryRepository.loadCompletionHistory()
            : transaction.taskCompletionHistory
        // Task completion and undo carry an explicit diary/history delta, so they
        // are already known user mutations. Avoid re-reading every persisted
        // primary-state surface before the write; the read-after-write checks
        // below remain the durability guard.
        let shouldReportPrimaryChange = forceCloudReport || hasPrimaryUserDataChanges(
            transaction,
            dependencies: dependencies
        )
        var result = BingoViewModelPersistenceCommitResult()
        defer {
            DiagnosticLogStore.record("persistence.commit_result", category: "state_change",
                level: result.failedToSaveBoard || result.failedToSaveTransaction ? .warning : .info,
                details: [
                    "transaction_id": transaction.id.uuidString,
                    "board_id": transaction.boardState?.associatedBoardID.map { String($0.uuidString.prefix(8)) } ?? "none",
                    "failed_board": String(result.failedToSaveBoard),
                    "failed_transaction": String(result.failedToSaveTransaction),
                    "saved_points": String(result.savedPoints),
                    "recovery": String(forceCloudReport)
                ])
        }

        if let boardState = transaction.boardState {
            let boardResult = BoardStateCommitter.saveActiveBoardState(
                board: boardState.board,
                countdownEndsAt: boardState.countdownEndsAt,
                savedAt: boardState.savedAt,
                associatedBoardID: boardState.associatedBoardID,
                repository: dependencies.boardRepository,
                reloadWidgets: false
            )
            result = BingoViewModelPersistenceCommitResult(boardStateCommit: boardResult)
            let persistedBoardMatches = dependencies.boardRepository.loadBoard() == boardState.board
            let persistedCountdownMatches =
                dependencies.boardRepository.loadBoardCountdownEndsAt() == boardState.countdownEndsAt
            let persistedBoardIDMatches =
                dependencies.boardRepository.loadActiveNamedBoardID() == boardState.associatedBoardID
            guard !result.failedToSaveBoard,
                  persistedBoardMatches,
                  persistedCountdownMatches,
                  persistedBoardIDMatches else {
                DiagnosticLogStore.recordWarning(
                    "points.persistence_failed",
                    details: [
                        "stage": "save_board",
                        "target_total": "\(transaction.totalPoints)",
                        "board_matches": "\(persistedBoardMatches)",
                        "countdown_matches": "\(persistedCountdownMatches)",
                        "board_id_matches": "\(persistedBoardIDMatches)"
                    ]
                )
                result.failedToSaveTransaction = true
                return result
            }
        }

        dependencies.diaryRepository.replaceAllEntriesDictionary(transaction.diaryEntries)
        guard dependencies.diaryRepository.loadAllEntriesDictionary() == transaction.diaryEntries else {
            DiagnosticLogStore.recordWarning(
                "points.persistence_failed",
                details: [
                    "stage": "save_diary",
                    "target_total": "\(transaction.totalPoints)"
                ]
            )
            result.failedToSaveTransaction = true
            return result
        }
        result.updatedDiary = true

        guard dependencies.completionHistoryRepository.replaceCompletionHistory(completionHistoryToPersist),
              dependencies.completionHistoryRepository.loadCompletionHistory() == completionHistoryToPersist else {
            DiagnosticLogStore.recordWarning(
                "points.persistence_failed",
                details: [
                    "stage": "save_completion_history",
                    "target_total": "\(transaction.totalPoints)"
                ]
            )
            result.failedToSaveTransaction = true
            return result
        }

        guard dependencies.pointsRepository.saveState(
            totalPoints: transaction.totalPoints,
            lifetimePoints: transaction.lifetimePoints,
            dailyRewardState: transaction.dailyRewardState
        ), dependencies.pointsRepository.loadTotalPoints() == transaction.totalPoints,
              dependencies.pointsRepository.loadLifetimePoints() == transaction.lifetimePoints,
              dependencies.pointsRepository.loadDailyRewardState() == transaction.dailyRewardState else {
            let persisted = dependencies.pointsRepository.loadPersistenceSnapshot()
            DiagnosticLogStore.recordWarning(
                "points.persistence_failed",
                details: [
                    "stage": "save_points",
                    "target_total": "\(transaction.totalPoints)",
                    "persisted_total": persisted.totalPoints.map { "\($0)" } ?? "nil"
                ]
            )
            result.failedToSaveTransaction = true
            return result
        }
        result.savedPoints = true

        guard dependencies.transactionRepository.clearPendingTransaction() else {
            DiagnosticLogStore.recordWarning(
                "points.persistence_failed",
                details: [
                    "stage": "clear_pending_transaction",
                    "target_total": "\(transaction.totalPoints)"
                ]
            )
            result.failedToSaveTransaction = true
            return result
        }
        reloadWidgetsIfNeeded(&result, dependencies: dependencies)
        if shouldReportPrimaryChange {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        return result
    }

    private static func hasPrimaryUserDataChanges(
        _ transaction: BingoPendingPersistenceTransaction,
        dependencies: BingoViewModelPersistenceDependencies
    ) -> Bool {
        if let boardState = transaction.boardState,
           dependencies.boardRepository.loadBoard() != boardState.board ||
            dependencies.boardRepository.loadBoardCountdownEndsAt() != boardState.countdownEndsAt ||
            dependencies.boardRepository.loadActiveNamedBoardID() != boardState.associatedBoardID {
            return true
        }

        if dependencies.diaryRepository.loadAllEntriesDictionary() != transaction.diaryEntries {
            return true
        }

        if !transaction.taskCompletionHistory.isEmpty,
           dependencies.completionHistoryRepository.loadCompletionHistory() != transaction.taskCompletionHistory {
            return true
        }

        return dependencies.pointsRepository.loadPersistenceSnapshot() != PointsPersistenceSnapshot(
            totalPoints: transaction.totalPoints,
            lifetimePoints: transaction.lifetimePoints,
            dailyRewardState: transaction.dailyRewardState
        )
    }

    private static func reloadWidgetsIfNeeded(
        _ result: inout BingoViewModelPersistenceCommitResult,
        dependencies: BingoViewModelPersistenceDependencies
    ) {
        var boardResult = BoardStateCommitResult(
            savedBoard: result.savedBoard,
            failedToSaveBoard: result.failedToSaveBoard,
            savedBoardCountdown: result.savedBoardCountdown,
            reloadedWidgets: result.reloadedWidgets
        )
        BoardStateCommitter.reloadWidgetsIfNeeded(&boardResult, repository: dependencies.boardRepository)
        result.apply(boardResult)
    }

}
