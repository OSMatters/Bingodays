import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct PersistenceWriteStep {
    let apply: () -> Bool
    let rollback: () -> Bool
}

enum PersistenceWriteTransaction {
    static func commit(_ steps: [PersistenceWriteStep]) -> Bool {
        for index in steps.indices {
            guard steps[index].apply() else {
                var rollbackSucceeded = true
                for rollbackIndex in (steps.startIndex...index).reversed() {
                    if !steps[rollbackIndex].rollback() { rollbackSucceeded = false }
                }
                DiagnosticLogStore.recordWarning("persistence.transaction_failed", details: [
                    "failed_step": String(index), "step_count": String(steps.count),
                    "rollback_succeeded": String(rollbackSucceeded)
                ])
                return false
            }
        }
        return true
    }

    static func fileDataStep(at url: URL, newData: Data?) -> PersistenceWriteStep? {
        let hadPreviousFile = FileManager.default.fileExists(atPath: url.path)
        let previousData = try? Data(contentsOf: url)
        guard !hadPreviousFile || previousData != nil else { return nil }

        return PersistenceWriteStep(
            apply: { replaceFile(at: url, with: newData) },
            rollback: {
                replaceFile(
                    at: url,
                    with: hadPreviousFile ? previousData : nil
                )
            }
        )
    }

    static func userDefaultsStep(
        defaults: UserDefaults,
        key: String,
        newValue: Any?
    ) -> PersistenceWriteStep {
        let previousValue = defaults.object(forKey: key)
        return PersistenceWriteStep(
            apply: {
                replaceUserDefaultsValue(newValue, defaults: defaults, key: key)
            },
            rollback: {
                replaceUserDefaultsValue(previousValue, defaults: defaults, key: key)
            }
        )
    }

    private static func replaceFile(at url: URL, with data: Data?) -> Bool {
        do {
            if let data {
                try data.write(to: url, options: .atomic)
                return (try? Data(contentsOf: url)) == data
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return !FileManager.default.fileExists(atPath: url.path)
        } catch {
            let failure = error as NSError
            DiagnosticLogStore.recordWarning("persistence.file_write_failed", details: [
                "error_domain": failure.domain, "error_code": String(failure.code)
            ])
            return false
        }
    }

    private static func replaceUserDefaultsValue(
        _ value: Any?,
        defaults: UserDefaults,
        key: String
    ) -> Bool {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        return propertyListValuesEqual(defaults.object(forKey: key), value)
    }

    private static func propertyListValuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs as NSObject, rhs as NSObject):
            return lhs.isEqual(rhs)
        default:
            return false
        }
    }
}

enum BoardTaskResetMode: String, Codable, CaseIterable {
    case resetStatusNextDay
    case clearTasksNextDay
    case customResetStatusTime
    case keepTaskStatus
}

enum BingoNamedBoardOrigin: String, Codable {
    case user
    case starterGuide
}

enum BingoBoardStore {
    static let appGroupID = "group.com.bingoday.app"
    private static let saveKey = "bingo_board_v1"
    private static let lastSavedAtKey = "bingo_board_last_saved_at_v1"
    private static let activeNamedBoardIDKey = "bingo_board_active_named_board_id_v1"
    private static let taskRuleEditReceiptKey = "bingo_task_rule_edit_receipt_v1"

    private struct TaskRuleEditReceipt: Codable {
        let boardID: UUID?
        let cells: [BingoCell]
    }

    private static func confirmedTaskRuleEdits(for board: SavedBoard, boardID: UUID?) -> [BingoCell] {
        guard let data = sharedDefaults.data(forKey: taskRuleEditReceiptKey),
              let receipt = try? JSONDecoder().decode(TaskRuleEditReceipt.self, from: data),
              receipt.boardID == boardID else { return [] }
        let cells = BoardEngine.expandedBoardCache(from: board).flatMap { $0 }
        return receipt.cells.filter { authorized in
            cells.contains { TaskRulePersistenceGuard.matchesTaskDefinition(authorized, $0) }
        }
    }
    private static let sharedFileName = "bingo_board_v1.json"
    private static let metricsFileName = "bingo_metrics_v1.json"
    private static let boardsSaveKey = "bingo_boards_v1"
    /// Marks the commit shared by the App Group file and the two defaults mirrors.
    /// It prevents an older, still-valid file from winning over a newer task-rule edit.
    private static let namedBoardsLastSavedAtKey = "bingo_boards_last_saved_at_v1"
    private static let boardsFileName = "bingo_boards_v1.json"
    private static let maxBoardNameLength = 20

    static func withBoardPersistenceLock<T>(_ operation: () -> T) -> T? {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        return withNamedSnapshotWriteCoordination(operation)
    }

    /// NSFileCoordinator provides App Group coordination without leaving a
    /// POSIX advisory lock behind when iOS suspends either the app or widget.
    /// Nested board writes stay in the same coordinator block.
    private static func withNamedSnapshotWriteCoordination<T>(
        _ operation: () -> T
    ) -> T? {
        let state = Thread.current.threadDictionary
        let depthKey = "bingo.named.coordination.depth"
        let depth = state[depthKey] as? Int ?? 0
        if depth > 0 {
            state[depthKey] = depth + 1
            defer { state[depthKey] = depth }
            return operation()
        }

        var coordinationError: NSError?
        var result: T?
        NSFileCoordinator().coordinate(
            writingItemAt: namedBoardsFileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { _ in
            state[depthKey] = 1
            defer { state.removeObject(forKey: depthKey) }
            result = operation()
        }
        if let coordinationError {
            DiagnosticLogStore.recordWarning("board.snapshot_coordination_failed", details: [
                "error_domain": coordinationError.domain,
                "error_code": String(coordinationError.code)
            ])
        }
        return result
    }

    private struct SnapshotCommitMetadata: Codable {
        var localCommitID: UUID?
        var localCommittedAt: Date?
    }

    private struct ActiveBoardCommitMetadata: Codable {
        let activeCommitID: UUID
        let activeCommitRevision: UInt64
    }

    private struct CommittedActiveBoard: Encodable {
        let board: SavedBoard
        let metadata: ActiveBoardCommitMetadata

        func encode(to encoder: Encoder) throws {
            try board.encode(to: encoder)
            try metadata.encode(to: encoder)
        }
    }

    private static func encodeCommittedActiveBoard(_ board: SavedBoard) throws -> Data? {
        let revisions = [try? Data(contentsOf: sharedFileURL), sharedDefaults.data(forKey: saveKey),
                         UserDefaults.standard.data(forKey: saveKey)].compactMap { data -> UInt64? in
            guard let data, (try? JSONDecoder().decode(SavedBoard.self, from: data)) != nil else { return nil }
            return (try? JSONDecoder().decode(ActiveBoardCommitMetadata.self, from: data))?.activeCommitRevision
        }
        let latest = revisions.max() ?? 0
        guard latest < UInt64.max else { return nil }
        return try JSONEncoder().encode(CommittedActiveBoard(
            board: board,
            metadata: ActiveBoardCommitMetadata(activeCommitID: UUID(), activeCommitRevision: latest + 1)
        ))
    }

    static func unconfirmedRuleDowngrades(from previous: SavedBoard?, to board: SavedBoard, boardID: UUID) -> Set<UUID> {
        let confirmed = confirmedTaskRuleEdits(for: board, boardID: boardID).map(\.id)
        let active = loadActiveNamedBoardID() == boardID ? loadBoard() : nil
        return TaskRulePersistenceGuard.downgradedCellIDs(from: previous, to: board)
            .union(TaskRulePersistenceGuard.downgradedCellIDs(from: active, to: board))
            .subtracting(confirmed)
    }

    static func taskRuleRecoveryBoard(_ persisted: NamedBoard) -> NamedBoard {
        guard loadActiveNamedBoardID() == persisted.id, let active = loadBoard(),
              !unconfirmedRuleDowngrades(from: active, to: persisted.board, boardID: persisted.id).isEmpty else {
            return persisted
        }
        var restored = persisted
        restored.board = active
        restored.countdownEndsAt = loadBoardCountdownEndsAt()
        return restored
    }

    private struct CommittedSnapshot: Encodable {
        let snapshot: NamedBoardsSnapshot
        let metadata: SnapshotCommitMetadata

        func encode(to encoder: Encoder) throws {
            try snapshot.encode(to: encoder)
            try metadata.encode(to: encoder)
        }
    }

    private static func encodeCommittedSnapshot(_ snapshot: NamedBoardsSnapshot, at date: Date) throws -> Data {
        try JSONEncoder().encode(CommittedSnapshot(
            snapshot: snapshot,
            metadata: SnapshotCommitMetadata(localCommitID: UUID(), localCommittedAt: date)
        ))
    }

    private enum NamedBoardsPersistenceSource: Int {
        case file
        case sharedDefaults
        case standardDefaults

        var diagnosticValue: String {
            switch self {
            case .file: "file"
            case .sharedDefaults: "shared_defaults"
            case .standardDefaults: "standard_defaults"
            }
        }
    }

    private struct NamedBoardsPersistenceCandidate {
        let source: NamedBoardsPersistenceSource
        let data: Data
        let snapshot: NamedBoardsSnapshot
        let savedAt: Date?

        var freshness: Date {
            savedAt ?? (snapshot.boards.map(\.updatedAt) + [snapshot.boardOrderModifiedAt].compactMap { $0 }).max() ?? .distantPast
        }
    }

    struct NamedBoard: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String
        var board: SavedBoard
        var countdownEndsAt: Date?
        var taskResetMode: BoardTaskResetMode
        var customResetMinutes: Int?
        var lastTaskResetAppliedAt: Date?
        var origin: BingoNamedBoardOrigin
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case board
            case countdownEndsAt
            case taskResetMode
            case customResetMinutes
            case lastTaskResetAppliedAt
            case origin
            case updatedAt
        }

        init(
            id: UUID = UUID(),
            name: String,
            board: SavedBoard,
            countdownEndsAt: Date? = nil,
            taskResetMode: BoardTaskResetMode = .resetStatusNextDay,
            customResetMinutes: Int? = nil,
            lastTaskResetAppliedAt: Date? = .now,
            origin: BingoNamedBoardOrigin = .user,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.board = board
            self.countdownEndsAt = countdownEndsAt
            self.taskResetMode = taskResetMode
            self.customResetMinutes = NamedBoard.clampedCustomResetMinutes(customResetMinutes)
            self.lastTaskResetAppliedAt = lastTaskResetAppliedAt
            self.origin = origin
            self.updatedAt = updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try container.decode(String.self, forKey: .name)
            board = try container.decode(SavedBoard.self, forKey: .board)
            countdownEndsAt = try container.decodeIfPresent(Date.self, forKey: .countdownEndsAt)
            taskResetMode = try container.decodeIfPresent(BoardTaskResetMode.self, forKey: .taskResetMode) ?? .resetStatusNextDay
            customResetMinutes = NamedBoard.clampedCustomResetMinutes(try container.decodeIfPresent(Int.self, forKey: .customResetMinutes))
            origin = try container.decodeIfPresent(BingoNamedBoardOrigin.self, forKey: .origin) ?? .user
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
            // Migration-safe anchor: if historical data doesn't have this field,
            // use updatedAt to avoid immediate same-day reset on first launch.
            lastTaskResetAppliedAt = try container.decodeIfPresent(Date.self, forKey: .lastTaskResetAppliedAt) ?? updatedAt
        }

        private static func clampedCustomResetMinutes(_ value: Int?) -> Int? {
            guard let value else { return nil }
            return min(max(value, 0), 23 * 60 + 59)
        }
    }

    struct NamedBoardsSnapshot: Codable, Equatable {
        var selectedBoardID: UUID?
        var boards: [NamedBoard]
        var deletedBoardIDs: Set<UUID>?
        /// The original free-plan board remains protected even when users reorder boards.
        /// Older snapshots infer this from their first board during sanitization.
        var protectedBoardID: UUID?
        /// Kept separate from a board's content timestamp so sorting never wins a
        /// task, countdown, reset-rule, or point conflict.
        var boardOrderModifiedAt: Date?

        init(
            selectedBoardID: UUID?,
            boards: [NamedBoard],
            deletedBoardIDs: Set<UUID> = [],
            protectedBoardID: UUID? = nil,
            boardOrderModifiedAt: Date? = nil
        ) {
            self.selectedBoardID = selectedBoardID
            self.boards = boards
            self.deletedBoardIDs = deletedBoardIDs
            self.protectedBoardID = protectedBoardID
            self.boardOrderModifiedAt = boardOrderModifiedAt
        }

        var effectiveDeletedBoardIDs: Set<UUID> {
            deletedBoardIDs ?? []
        }

        var effectiveProtectedBoardID: UUID? {
            if let protectedBoardID,
               boards.contains(where: { $0.id == protectedBoardID }) {
                return protectedBoardID
            }
            return boards.first?.id
        }
    }

    static func snapshotByRemovingRedundantStarterGuideBoards(
        _ snapshot: NamedBoardsSnapshot
    ) -> NamedBoardsSnapshot {
        let liveBoards = snapshot.boards.filter {
            !snapshot.effectiveDeletedBoardIDs.contains($0.id)
        }
        let starterBoards = liveBoards.filter(isPristineStarterGuideBoard)
        guard !starterBoards.isEmpty else {
            return NamedBoardsSnapshot(
                selectedBoardID: snapshot.selectedBoardID,
                boards: liveBoards,
                deletedBoardIDs: snapshot.effectiveDeletedBoardIDs,
                protectedBoardID: snapshot.protectedBoardID,
                boardOrderModifiedAt: snapshot.boardOrderModifiedAt
            )
        }

        let hasMeaningfulUserBoard = liveBoards.contains { board in
            !isPristineStarterGuideBoard(board) && !isPristineEmptyDefaultBoard(board)
        }
        let retainedStarterID: UUID?
        if hasMeaningfulUserBoard {
            retainedStarterID = nil
        } else if let selectedBoardID = snapshot.selectedBoardID,
                  starterBoards.contains(where: { $0.id == selectedBoardID }) {
            retainedStarterID = selectedBoardID
        } else {
            retainedStarterID = starterBoards.min { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }?.id
        }

        let removedStarterIDs = Set(starterBoards.compactMap { board in
            board.id == retainedStarterID ? nil : board.id
        })
        guard !removedStarterIDs.isEmpty else {
            return NamedBoardsSnapshot(
                selectedBoardID: snapshot.selectedBoardID,
                boards: liveBoards,
                deletedBoardIDs: snapshot.effectiveDeletedBoardIDs,
                protectedBoardID: snapshot.protectedBoardID,
                boardOrderModifiedAt: snapshot.boardOrderModifiedAt
            )
        }

        let boards = liveBoards.filter { !removedStarterIDs.contains($0.id) }
        let selectedBoardID = snapshot.selectedBoardID.flatMap { selectedID in
            boards.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? boards.first?.id
        return NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: boards,
            deletedBoardIDs: snapshot.effectiveDeletedBoardIDs.union(removedStarterIDs),
            protectedBoardID: snapshot.effectiveProtectedBoardID.flatMap { protectedID in
                boards.contains(where: { $0.id == protectedID }) ? protectedID : boards.first?.id
            } ?? boards.first?.id,
            boardOrderModifiedAt: snapshot.boardOrderModifiedAt
        )
    }

    static func isPristineStarterGuideBoard(_ namedBoard: NamedBoard) -> Bool {
        guard defaultBoardNames.contains(normalizedBoardName(namedBoard.name)),
              namedBoard.countdownEndsAt == nil,
              namedBoard.taskResetMode == .resetStatusNextDay,
              namedBoard.customResetMinutes == nil,
              namedBoard.board.gridSize == 3,
              namedBoard.board.completedLines.isEmpty else {
            return false
        }

        let cells = BoardEngine.expandedBoardCache(from: namedBoard.board).flatMap(\.self)
        let taskCells = cells.filter(\.hasStoredTask)
        guard taskCells.count == 3,
              cells.allSatisfy(isPristineStarterGuideCell) else {
            return false
        }
        let taskKeys = Set(taskCells.map { normalizedTaskText($0.storedTaskText) })
        return starterGuideTaskSets.contains(taskKeys)
    }

    private static func isPristineEmptyDefaultBoard(_ namedBoard: NamedBoard) -> Bool {
        guard defaultBoardNames.contains(normalizedBoardName(namedBoard.name)),
              namedBoard.countdownEndsAt == nil,
              namedBoard.taskResetMode == .resetStatusNextDay,
              namedBoard.customResetMinutes == nil,
              namedBoard.board.gridSize == 3,
              namedBoard.board.completedLines.isEmpty else {
            return false
        }
        return BoardEngine.expandedBoardCache(from: namedBoard.board)
            .flatMap(\.self)
            .allSatisfy { !$0.hasStoredTask && isPristineStarterGuideCell($0) }
    }

    private static func isPristineStarterGuideCell(_ cell: BingoCell) -> Bool {
        !cell.isCompleted &&
            !cell.isForced &&
            !cell.isTaskHidden &&
            !cell.isDisplayOnlyInactive &&
            cell.residentWeekdays.isEmpty &&
            cell.oneTimeVisibleDate == nil &&
            cell.recurrenceRule == nil &&
            cell.startVisibleAt == nil &&
            cell.endVisibleAt == nil &&
            !cell.usesRecurringTimeWindow &&
            !cell.startReminderEnabled &&
            cell.startVisibleMonth == nil &&
            cell.startVisibleDay == nil &&
            cell.countdownEndsAt == nil &&
            cell.countdownPausedRemainingSeconds == nil &&
            cell.estimatedDurationMinutes == nil &&
            cell.completionStreakCount == 0 &&
            cell.lastCompletedAt == nil &&
            cell.lastVisibilityWindowTimeoutAt == nil &&
            (cell.residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static let defaultBoardNames: Set<String> = Set([
        "Board 1", "Board1", "棋盘1", "棋盘 1", "棋盤1", "棋盤 1", "ボード1", "ボード 1"
    ].map(normalizedBoardName))

    private static let starterGuideTaskSets: [Set<String>] = [
        ["Drink a glass of water", "Stand for 1 minute", "Stretch your body"],
        ["喝一杯水", "站立1分钟", "拉伸身体"],
        ["喝一杯水", "站立1分鐘", "拉伸身體"]
    ].map { Set($0.map(normalizedTaskText)) }

    private static func normalizedBoardName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedTaskText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Board selection is a device-local projection. The active mirror identifies the board
    /// currently rendered by this device and therefore wins over a stale snapshot selection.
    static func resolvedLocalBoardID(
        in snapshot: NamedBoardsSnapshot,
        activeBoardID: UUID?
    ) -> UUID? {
        if let activeBoardID,
           snapshot.boards.contains(where: { $0.id == activeBoardID }) {
            return activeBoardID
        }
        if let selectedBoardID = snapshot.selectedBoardID,
           snapshot.boards.contains(where: { $0.id == selectedBoardID }) {
            return selectedBoardID
        }
        return snapshot.boards.first?.id
    }

    static func snapshotByApplyingLocalSelection(
        _ snapshot: NamedBoardsSnapshot,
        activeBoardID: UUID?
    ) -> NamedBoardsSnapshot {
        NamedBoardsSnapshot(
            selectedBoardID: resolvedLocalBoardID(
                in: snapshot,
                activeBoardID: activeBoardID
            ),
            boards: snapshot.boards,
            deletedBoardIDs: snapshot.effectiveDeletedBoardIDs,
            protectedBoardID: snapshot.protectedBoardID,
            boardOrderModifiedAt: snapshot.boardOrderModifiedAt
        )
    }

    /// The active board is a repairable projection of one named board. A different cell identity
    /// means it came from another board (or a damaged projection) and must never be merged back.
    static func hasMatchingCellIdentity(_ lhs: SavedBoard, _ rhs: SavedBoard) -> Bool {
        canonicalCellIDs(in: lhs) == canonicalCellIDs(in: rhs)
    }

    private struct WidgetMetrics: Codable {
        let firstSeenAt: Date
    }

    static func loadBoard(repairingPersistence: Bool = true) -> SavedBoard? {
        if !repairingPersistence {
            return preferredBoardDataCandidates(
                fileData: try? Data(contentsOf: sharedFileURL),
                sharedData: sharedDefaults.data(forKey: saveKey),
                standardData: UserDefaults.standard.data(forKey: saveKey)
            )
            .lazy
            .compactMap { try? JSONDecoder().decode(SavedBoard.self, from: $0) }
            .first
        }
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        return withNamedSnapshotWriteCoordination { () -> SavedBoard? in
            let fileData = try? Data(contentsOf: sharedFileURL)
            let sharedData = sharedDefaults.data(forKey: saveKey)
            let standardData = UserDefaults.standard.data(forKey: saveKey)

            for data in preferredBoardDataCandidates(
                fileData: fileData,
                sharedData: sharedData,
                standardData: standardData
            ) {
                guard let saved = try? JSONDecoder().decode(SavedBoard.self, from: data) else {
                    continue
                }
                repairBoardPersistenceIfNeeded(data)
                return saved
            }

            return nil
        } ?? loadBoard(repairingPersistence: false)
    }

    static func normalizedBoardForPersistence(
        _ board: SavedBoard,
        referenceDate: Date
    ) -> SavedBoard {
        let normalized = BoardEngine.removingUnsupportedRecurringTiming(
            from: board,
            referenceDate: referenceDate
        )

        // `BingoCell.isDisplayOnlyInactive` is intentionally not Codable because
        // it is a view projection, not user data. A board assembled from visible
        // cells can therefore differ from the same board immediately after a
        // successful encode/decode. Canonicalize through the real persistence
        // representation so transaction verification compares what is actually
        // durable instead of transient UI-only state.
        guard let data = try? JSONEncoder().encode(normalized),
              let canonical = try? JSONDecoder().decode(SavedBoard.self, from: data) else {
            return normalized
        }
        return canonical
    }

    @discardableResult
    static func saveBoard(
        _ board: SavedBoard,
        savedAt: Date = .now,
        associatedBoardID: UUID? = nil,
        reloadWidgets: Bool = true,
        explicitlyEditedCellIDs: Set<UUID> = []
    ) -> Bool {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        return withNamedSnapshotWriteCoordination {
        let normalizedBoard = normalizedBoardForPersistence(board, referenceDate: savedAt)
        let activeBoard = loadActiveNamedBoardID() == associatedBoardID ? loadBoard() : nil
        let namedBoard = associatedBoardID.flatMap { id in
            preferredNamedBoardsPersistenceCandidate()?.snapshot.boards.first { $0.id == id }
        }
        let confirmedEdits = confirmedTaskRuleEdits(for: normalizedBoard, boardID: associatedBoardID)
        let permittedIDs = explicitlyEditedCellIDs.union(confirmedEdits.map(\.id))
        let blocked = TaskRulePersistenceGuard.downgradedCellIDs(from: activeBoard, to: normalizedBoard)
            .union(TaskRulePersistenceGuard.downgradedCellIDs(from: namedBoard?.board, to: normalizedBoard))
            .subtracting(permittedIDs)
        guard blocked.isEmpty else {
            DiagnosticLogStore.recordWarning("task_rule.downgrade_blocked", details: [
                "source": "active_board_save", "board_id": associatedBoardID?.uuidString ?? "none",
                "cell_ids": blocked.map(\.uuidString).sorted().joined(separator: ",")
            ])
            return false
        }
        guard let data = try? encodeCommittedActiveBoard(normalizedBoard) else { return false }
        let authorizedCells = BoardEngine.expandedBoardCache(from: normalizedBoard).flatMap { $0 }
            .filter { $0.hasStoredTask && permittedIDs.contains($0.id) }
        guard let receiptData = try? JSONEncoder().encode(
            TaskRuleEditReceipt(boardID: associatedBoardID, cells: authorizedCells)
        ) else { return false }

        guard let fileStep = PersistenceWriteTransaction.fileDataStep(
            at: sharedFileURL,
            newData: data
        ) else { return false }
        let didCommit = PersistenceWriteTransaction.commit([
            fileStep,
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults, key: taskRuleEditReceiptKey, newValue: receiptData
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: saveKey,
                newValue: data
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: saveKey,
                newValue: data
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: lastSavedAtKey,
                newValue: savedAt
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: lastSavedAtKey,
                newValue: savedAt
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: activeNamedBoardIDKey,
                newValue: associatedBoardID?.uuidString
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: activeNamedBoardIDKey,
                newValue: associatedBoardID?.uuidString
            )
        ])
        guard didCommit else { return false }

        if reloadWidgets {
            reloadWidgetTimelines()
        }

        return true
        } ?? false
    }

    static func clearBoard(reloadWidgets: Bool = true) {
        guard let fileStep = PersistenceWriteTransaction.fileDataStep(
            at: sharedFileURL,
            newData: nil
        ) else { return }
        let didClear = PersistenceWriteTransaction.commit([
            fileStep,
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults, key: taskRuleEditReceiptKey, newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: saveKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: saveKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: lastSavedAtKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: lastSavedAtKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: activeNamedBoardIDKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: activeNamedBoardIDKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.boardCountdownKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.boardCountdownKey,
                newValue: nil
            )
        ])
        guard didClear else { return }

        if reloadWidgets {
            reloadWidgetTimelines()
        }
    }

    static func clearNamedBoardsSnapshot(reloadWidgets: Bool = true) {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        _ = withNamedSnapshotWriteCoordination { () -> Void in
        guard let fileStep = PersistenceWriteTransaction.fileDataStep(
            at: namedBoardsFileURL,
            newData: nil
        ) else { return }
        let didClear = PersistenceWriteTransaction.commit([
            fileStep,
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: boardsSaveKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: boardsSaveKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: namedBoardsLastSavedAtKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: namedBoardsLastSavedAtKey,
                newValue: nil
            )
        ])
        guard didClear else { return }

        if reloadWidgets {
            reloadWidgetTimelines()
        }
        }
    }

    static func loadNamedBoardsSnapshot(
        repairingPersistence: Bool = true
    ) -> NamedBoardsSnapshot {
        if !repairingPersistence {
            if let candidate = preferredNamedBoardsPersistenceCandidate() {
                return sanitizeNamedBoardsSnapshot(candidate.snapshot)
            }
            if let legacyBoard = loadBoard(repairingPersistence: false) {
                let migratedBoard = NamedBoard(
                    name: L10n.boardDefaultName(1),
                    board: legacyBoard,
                    countdownEndsAt: loadBoardCountdownEndsAt(),
                    updatedAt: loadBoardLastSavedAt() ?? .now
                )
                return NamedBoardsSnapshot(selectedBoardID: migratedBoard.id, boards: [migratedBoard])
            }
            return NamedBoardsSnapshot(selectedBoardID: nil, boards: [])
        }
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        return withNamedSnapshotWriteCoordination { () -> NamedBoardsSnapshot in
        if let candidate = preferredNamedBoardsPersistenceCandidate() {
            let sanitized = sanitizeNamedBoardsSnapshot(candidate.snapshot)
            let didSanitize = sanitized != candidate.snapshot
            let selectedData = didSanitize
                ? (try? JSONEncoder().encode(sanitized))
                : candidate.data

            recordNamedBoardsReplicaRecoveryIfNeeded(selected: candidate)
            if let selectedData {
                let recoveredAt = candidate.savedAt ?? candidate.freshness
                if didSanitize {
                    _ = saveNamedBoardsSnapshot(sanitized)
                } else {
                    repairNamedBoardsPersistenceIfNeeded(selectedData, savedAt: recoveredAt)
                }
            }

            return sanitized
        }

        if let legacyBoard = loadBoard() {
            let migratedBoard = NamedBoard(
                name: L10n.boardDefaultName(1),
                board: legacyBoard,
                countdownEndsAt: loadBoardCountdownEndsAt(),
                updatedAt: loadBoardLastSavedAt() ?? .now
            )
            let snapshot = NamedBoardsSnapshot(selectedBoardID: migratedBoard.id, boards: [migratedBoard])
            saveNamedBoardsSnapshot(snapshot)
            return snapshot
        }

        return NamedBoardsSnapshot(selectedBoardID: nil, boards: [])
        } ?? loadNamedBoardsSnapshot(repairingPersistence: false)
    }

    @discardableResult
    static func saveNamedBoardsSnapshot(
        _ snapshot: NamedBoardsSnapshot,
        reloadWidgets: Bool = true,
        expectedSnapshot: NamedBoardsSnapshot? = nil,
        source: String = #function,
        authorizedRuleChangeCellIDs: [UUID: Set<UUID>] = [:]
    ) -> Bool {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        return withNamedSnapshotWriteCoordination {
        let sanitized = sanitizeNamedBoardsSnapshot(snapshot)
        #if DEBUG
        let previousSnapshot = loadPersistedNamedBoardsSnapshotForIntegrityCheck()
        debugValidateNamedBoardsTransition(from: previousSnapshot, to: sanitized)
        #endif
        let previous = preferredNamedBoardsPersistenceCandidate()
        if let expectedSnapshot,
           sanitizeNamedBoardsSnapshot(previous?.snapshot ?? .init(selectedBoardID: nil, boards: [])) != sanitizeNamedBoardsSnapshot(expectedSnapshot) {
            DiagnosticLogStore.recordWarning("board.snapshot_stale_write_rejected", details: [
                "source": source,
                "expected_boards": String(expectedSnapshot.boards.count),
                "actual_boards": String(previous?.snapshot.boards.count ?? 0)
            ])
            return false
        }
        if let previous, previous.snapshot == sanitized, isNamedBoardsPersistenceCurrent(previous.data) {
            return false
        }
        let activeBoardID = loadActiveNamedBoardID()
        let activeBoard = loadBoard()
        for oldBoard in previous?.snapshot.boards ?? [] {
            guard let newBoard = sanitized.boards.first(where: { $0.id == oldBoard.id }) else { continue }
            let downgraded = TaskRulePersistenceGuard.downgradedCellIDs(from: oldBoard.board, to: newBoard.board)
                .union(TaskRulePersistenceGuard.downgradedCellIDs(
                    from: activeBoardID == oldBoard.id ? activeBoard : nil, to: newBoard.board
                ))
                .subtracting(authorizedRuleChangeCellIDs[oldBoard.id] ?? [])
            guard !downgraded.isEmpty else { continue }
            let confirmed = Set(confirmedTaskRuleEdits(for: newBoard.board, boardID: newBoard.id).map(\.id))
            guard downgraded.subtracting(confirmed).isEmpty else {
                DiagnosticLogStore.recordWarning("task_rule.downgrade_blocked", details: [
                    "source": source, "board_id": oldBoard.id.uuidString,
                    "cell_ids": downgraded.map(\.uuidString).sorted().joined(separator: ",")
                ])
                return false
            }
        }
        let savedAt = Date()
        guard let data = try? encodeCommittedSnapshot(sanitized, at: savedAt) else { return false }
        let operationID = UUID().uuidString

        guard let fileStep = PersistenceWriteTransaction.fileDataStep(
            at: namedBoardsFileURL,
            newData: data
        ) else { return false }
        guard PersistenceWriteTransaction.commit([
            fileStep,
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: boardsSaveKey,
                newValue: data
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: boardsSaveKey,
                newValue: data
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: namedBoardsLastSavedAtKey,
                newValue: savedAt
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: namedBoardsLastSavedAtKey,
                newValue: savedAt
            )
        ]) else {
            DiagnosticLogStore.recordWarning("board.snapshot_commit_failed", details: ["operation_id": operationID])
            return false
        }
        recordSnapshotTransition(from: previous?.snapshot, to: sanitized, operationID: operationID, source: source)
        DiagnosticLogStore.recordStateChange("board.snapshot_committed", details: [
            "operation_id": operationID,
            "source": source,
            "previous_commit": previous.flatMap { try? JSONDecoder().decode(SnapshotCommitMetadata.self, from: $0.data).localCommitID?.uuidString } ?? "legacy",
            "commit_id": (try? JSONDecoder().decode(SnapshotCommitMetadata.self, from: data).localCommitID?.uuidString) ?? "unknown",
            "boards": String(sanitized.boards.count)
        ])

        if reloadWidgets {
            reloadWidgetTimelines()
        }

        return true
        } ?? false
    }

    /// Commits an imported template as one local state change.  This is kept
    /// separate from the regular board-edit paths so importing cannot inherit
    /// task completion, rules, reminders, or point state from either board.
    ///
    /// The transaction covers the multi-board snapshot, the active-board mirror
    /// read by the app and widgets, the active board ID, panel selection, and the
    /// active board countdown.  Every persistence write has a rollback step.
    @discardableResult
    static func commitImportedBoardSnapshot(
        _ snapshot: NamedBoardsSnapshot,
        activeBoardID: UUID,
        additionalPersistenceSteps: [PersistenceWriteStep] = [],
        savedAt: Date = .now,
        reloadWidgets: Bool = true
    ) -> Bool {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        return withNamedSnapshotWriteCoordination {

        let sanitizedSnapshot = sanitizeNamedBoardsSnapshot(snapshot)
        guard sanitizedSnapshot.selectedBoardID == activeBoardID,
              let activeNamedBoard = sanitizedSnapshot.boards.first(where: { $0.id == activeBoardID }) else {
            return false
        }

        let normalizedActiveBoard = normalizedBoardForPersistence(
            activeNamedBoard.board,
            referenceDate: savedAt
        )
        var committedBoards = sanitizedSnapshot.boards
        guard let activeIndex = committedBoards.firstIndex(where: { $0.id == activeBoardID }) else {
            return false
        }
        committedBoards[activeIndex].board = normalizedActiveBoard
        committedBoards[activeIndex].updatedAt = savedAt
        let committedSnapshot = NamedBoardsSnapshot(
            selectedBoardID: activeBoardID,
            boards: committedBoards,
            deletedBoardIDs: sanitizedSnapshot.effectiveDeletedBoardIDs,
            protectedBoardID: sanitizedSnapshot.effectiveProtectedBoardID,
            boardOrderModifiedAt: sanitizedSnapshot.boardOrderModifiedAt
        )

        guard let namedBoardsData = try? encodeCommittedSnapshot(committedSnapshot, at: savedAt),
              let activeBoardData = try? encodeCommittedActiveBoard(normalizedActiveBoard),
              let namedBoardsFileStep = PersistenceWriteTransaction.fileDataStep(
                  at: namedBoardsFileURL,
                  newData: namedBoardsData
              ),
              let activeBoardFileStep = PersistenceWriteTransaction.fileDataStep(
                  at: sharedFileURL,
                  newData: activeBoardData
              ) else {
            return false
        }

        var steps: [PersistenceWriteStep] = [
            namedBoardsFileStep,
            activeBoardFileStep,
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: boardsSaveKey,
                newValue: namedBoardsData
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: boardsSaveKey,
                newValue: namedBoardsData
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: namedBoardsLastSavedAtKey,
                newValue: savedAt
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: namedBoardsLastSavedAtKey,
                newValue: savedAt
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: saveKey,
                newValue: activeBoardData
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: saveKey,
                newValue: activeBoardData
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: lastSavedAtKey,
                newValue: savedAt
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: lastSavedAtKey,
                newValue: savedAt
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: activeNamedBoardIDKey,
                newValue: activeBoardID.uuidString
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: activeNamedBoardIDKey,
                newValue: activeBoardID.uuidString
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.boardCountdownKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.boardCountdownKey,
                newValue: nil
            ),
            WidgetPanelSelectionStore.persistenceStep(selectedPanelID: activeBoardID)
        ]
        steps.append(contentsOf: additionalPersistenceSteps)

        let didCommit = PersistenceWriteTransaction.commit(steps)
        guard didCommit else { return false }

        if reloadWidgets {
            reloadWidgetTimelines()
        }
        return true
        } ?? false
    }

    static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Cloud imports update both widget kinds from the App Group projection.
    /// Targeted reloads make the intended refresh observable and avoid relying
    /// on WidgetKit to infer which timeline changed.
    static func reloadICloudWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: BingodaysWidgetKind.countdown)
        WidgetCenter.shared.reloadTimelines(ofKind: BingodaysWidgetKind.board)
        #endif
        DiagnosticLogStore.recordStateChange("icloud.widget_timeline_reload_requested")
    }

    static func reloadBoardWidgetTimeline() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: BingodaysWidgetKind.board)
        #endif
    }

    static func loadBoardLastSavedAt() -> Date? {
        if let date = sharedDefaults.object(forKey: lastSavedAtKey) as? Date {
            repairStandardDefaultsValueIfNeeded(date, forKey: lastSavedAtKey)
            return date
        }

        if let date = UserDefaults.standard.object(forKey: lastSavedAtKey) as? Date {
            _ = PersistenceWriteTransaction.commit([
                PersistenceWriteTransaction.userDefaultsStep(
                    defaults: sharedDefaults,
                    key: lastSavedAtKey,
                    newValue: date
                )
            ])
            return date
        }

        if let values = try? sharedFileURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modificationDate = values.contentModificationDate {
            saveBoardLastSavedAt(modificationDate)
            return modificationDate
        }

        return nil
    }

    static func saveBoardLastSavedAt(_ date: Date) {
        _ = PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: lastSavedAtKey,
                newValue: date
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: lastSavedAtKey,
                newValue: date
            )
        ])
    }

    static func loadActiveNamedBoardID() -> UUID? {
        if let rawValue = sharedDefaults.string(forKey: activeNamedBoardIDKey),
           let boardID = UUID(uuidString: rawValue) {
            repairStandardDefaultsValueIfNeeded(rawValue, forKey: activeNamedBoardIDKey)
            return boardID
        }

        if let rawValue = UserDefaults.standard.string(forKey: activeNamedBoardIDKey),
           let boardID = UUID(uuidString: rawValue) {
            _ = PersistenceWriteTransaction.commit([
                PersistenceWriteTransaction.userDefaultsStep(
                    defaults: sharedDefaults,
                    key: activeNamedBoardIDKey,
                    newValue: rawValue
                )
            ])
            return boardID
        }

        return nil
    }

    static func saveActiveNamedBoardID(_ boardID: UUID?) {
        _ = PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: activeNamedBoardIDKey,
                newValue: boardID?.uuidString
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: activeNamedBoardIDKey,
                newValue: boardID?.uuidString
            )
        ])
    }

    static func loadBoardCountdownEndsAt() -> Date? {
        if let countdown = sharedDefaults.object(forKey: AppSettings.boardCountdownKey) as? Date {
            repairStandardDefaultsValueIfNeeded(
                countdown,
                forKey: AppSettings.boardCountdownKey
            )
            return countdown
        }

        if let countdown = UserDefaults.standard.object(forKey: AppSettings.boardCountdownKey) as? Date {
            _ = PersistenceWriteTransaction.commit([
                PersistenceWriteTransaction.userDefaultsStep(
                    defaults: sharedDefaults,
                    key: AppSettings.boardCountdownKey,
                    newValue: countdown
                )
            ])
            return countdown
        }

        return nil
    }

    static func saveBoardCountdownEndsAt(_ date: Date?) {
        _ = PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.boardCountdownKey,
                newValue: date
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.boardCountdownKey,
                newValue: date
            )
        ])
    }

    static func usageDays(referenceDate: Date = .now) -> Int {
        let metrics = loadOrCreateMetrics(referenceDate: referenceDate)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: metrics.firstSeenAt)
        let end = calendar.startOfDay(for: referenceDate)
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(dayCount + 1, 1)
    }

    static func firstSeenDate(referenceDate: Date = .now) -> Date {
        Calendar.current.startOfDay(for: loadOrCreateMetrics(referenceDate: referenceDate).firstSeenAt)
    }

    static func setFirstSeenDate(_ date: Date) {
        persistMetrics(WidgetMetrics(firstSeenAt: date))
    }

    static func clearFirstSeenDate() {
        try? FileManager.default.removeItem(at: metricsFileURL)
    }

    private static func sanitizeNamedBoardsSnapshot(_ snapshot: NamedBoardsSnapshot) -> NamedBoardsSnapshot {
        let deletedBoardIDs = snapshot.effectiveDeletedBoardIDs
        var seenIDs = Set<UUID>()
        var sanitizedBoards: [NamedBoard] = []
        sanitizedBoards.reserveCapacity(snapshot.boards.count)

        for board in snapshot.boards {
            guard !deletedBoardIDs.contains(board.id) else { continue }
            guard seenIDs.insert(board.id).inserted else { continue }
            let normalizedBoard = normalizedBoardForPersistence(
                board.board,
                referenceDate: .now
            )
            sanitizedBoards.append(
                NamedBoard(
                    id: board.id,
                    name: board.name,
                    board: normalizedBoard,
                    countdownEndsAt: board.countdownEndsAt,
                    taskResetMode: board.taskResetMode,
                    customResetMinutes: board.customResetMinutes,
                    lastTaskResetAppliedAt: board.lastTaskResetAppliedAt,
                    origin: board.origin,
                    updatedAt: board.updatedAt
                )
            )
        }

        for index in sanitizedBoards.indices {
            let fallbackIndex = index + 1
            let trimmed = sanitizedBoards[index].name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let limited = String(trimmed.prefix(maxBoardNameLength))
            sanitizedBoards[index].name = limited.isEmpty ? L10n.boardDefaultName(fallbackIndex) : limited
            sanitizedBoards[index].customResetMinutes = BoardResetRuleEngine.normalizedCustomResetMinutes(
                sanitizedBoards[index].customResetMinutes,
                mode: sanitizedBoards[index].taskResetMode
            )
        }

        sanitizeCrossBoardCellIdentityReuse(in: &sanitizedBoards)

        let selectedBoardID: UUID?
        if let existingSelected = snapshot.selectedBoardID,
           sanitizedBoards.contains(where: { $0.id == existingSelected }) {
            selectedBoardID = existingSelected
        } else {
            selectedBoardID = sanitizedBoards.first?.id
        }

        return snapshotByRemovingRedundantStarterGuideBoards(NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: sanitizedBoards,
            deletedBoardIDs: deletedBoardIDs,
            protectedBoardID: snapshot.protectedBoardID,
            boardOrderModifiedAt: snapshot.boardOrderModifiedAt
        ))
    }

    private static func sanitizeCrossBoardCellIdentityReuse(in boards: inout [NamedBoard]) {
        guard boards.count > 1 else { return }

        var ownerByCellID: [UUID: UUID] = [:]
        for index in boards.indices {
            let originalIDs = canonicalCellIDs(in: boards[index].board)
            var IDsInCurrentBoard = Set<UUID>()
            let hasInternalDuplicate = originalIDs.contains { !IDsInCurrentBoard.insert($0).inserted }
            let hasCrossBoardDuplicate = originalIDs.contains { cellID in
                guard let ownerID = ownerByCellID[cellID] else { return false }
                return ownerID != boards[index].id
            }

            if hasInternalDuplicate || hasCrossBoardDuplicate {
                boards[index].board = boardByRegeneratingCellIDs(boards[index].board)
            }

            for cellID in canonicalCellIDs(in: boards[index].board) {
                ownerByCellID[cellID] = boards[index].id
            }
        }
    }

    private static func canonicalCellIDs(in board: SavedBoard) -> [UUID] {
        let source = board.fullBoardCells ?? board.cells
        return source.flatMap { $0.map(\.id) }
    }

    private static func boardByRegeneratingCellIDs(_ board: SavedBoard) -> SavedBoard {
        if let fullBoardCells = board.fullBoardCells {
            var remintedFullBoardCells = fullBoardCells
            var idByPosition: [CellPositionKey: UUID] = [:]

            for row in remintedFullBoardCells.indices {
                for col in remintedFullBoardCells[row].indices {
                    let newID = UUID()
                    idByPosition[CellPositionKey(row: row, col: col)] = newID
                    remintedFullBoardCells[row][col] = cellByReplacingID(remintedFullBoardCells[row][col], id: newID)
                }
            }

            let remintedVisibleCells = cellsByRegeneratingIDs(board.cells, preferredIDsByPosition: idByPosition)
            return SavedBoard(
                gridSize: board.gridSize,
                cells: remintedVisibleCells,
                completedLines: board.completedLines,
                fullBoardCells: remintedFullBoardCells
            )
        }

        return SavedBoard(
            gridSize: board.gridSize,
            cells: cellsByRegeneratingIDs(board.cells, preferredIDsByPosition: [:]),
            completedLines: board.completedLines,
            fullBoardCells: nil
        )
    }

    private struct CellPositionKey: Hashable {
        let row: Int
        let col: Int
    }

    private static func cellsByRegeneratingIDs(
        _ cells: [[BingoCell]],
        preferredIDsByPosition: [CellPositionKey: UUID]
    ) -> [[BingoCell]] {
        cells.indices.map { row in
            cells[row].indices.map { col in
                let preferredID = preferredIDsByPosition[CellPositionKey(row: row, col: col)]
                return cellByReplacingID(cells[row][col], id: preferredID ?? UUID())
            }
        }
    }

    private static func cellByReplacingID(_ cell: BingoCell, id: UUID) -> BingoCell {
        BingoCell(
            id: id,
            text: cell.text,
            residentTaskText: cell.residentTaskText,
            residentWeekdays: cell.residentWeekdays,
            oneTimeVisibleDate: cell.oneTimeVisibleDate,
            recurrenceRule: cell.recurrenceRule,
            startVisibleAt: cell.startVisibleAt,
            endVisibleAt: cell.endVisibleAt,
            usesRecurringTimeWindow: cell.usesRecurringTimeWindow,
            startReminderEnabled: cell.startReminderEnabled,
            startReminderOffsetMinutes: cell.startReminderOffsetMinutes,
            startVisibleMonth: cell.startVisibleMonth,
            startVisibleDay: cell.startVisibleDay,
            isTaskHidden: cell.isTaskHidden,
            isCompleted: cell.isCompleted,
            isForced: cell.isForced,
            countdownEndsAt: cell.countdownEndsAt,
            countdownPausedRemainingSeconds: cell.countdownPausedRemainingSeconds,
            estimatedDurationMinutes: cell.estimatedDurationMinutes,
            completionStreakCount: cell.completionStreakCount,
            lastCompletedAt: cell.lastCompletedAt,
            lastVisibilityWindowTimeoutAt: cell.lastVisibilityWindowTimeoutAt
        )
    }

    #if DEBUG
    private struct DebugBoardSignature {
        let id: UUID
        let name: String
        let hasContent: Bool
        let signature: String
    }

    private static func loadPersistedNamedBoardsSnapshotForIntegrityCheck() -> NamedBoardsSnapshot? {
        if let data = try? Data(contentsOf: namedBoardsFileURL),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            return sanitizeNamedBoardsSnapshot(decoded)
        }

        if let data = sharedDefaults.data(forKey: boardsSaveKey),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            return sanitizeNamedBoardsSnapshot(decoded)
        }

        if let data = UserDefaults.standard.data(forKey: boardsSaveKey),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            return sanitizeNamedBoardsSnapshot(decoded)
        }

        return nil
    }

    private static func debugValidateNamedBoardsTransition(
        from previousSnapshot: NamedBoardsSnapshot?,
        to nextSnapshot: NamedBoardsSnapshot
    ) {
        debugAssertNoCrossBoardCellIDReuse(in: nextSnapshot)
        guard let previousSnapshot,
              previousSnapshot.boards.count > 1,
              nextSnapshot.boards.count > 1 else {
            return
        }

        let previousSignatures = previousSnapshot.boards.map(debugBoardSignature)
        let nextSignatures = nextSnapshot.boards.map(debugBoardSignature)
        let previousByID = Dictionary(uniqueKeysWithValues: previousSignatures.map { ($0.id, $0) })

        for nextBoard in nextSignatures {
            guard nextBoard.hasContent,
                  let previousBoard = previousByID[nextBoard.id],
                  previousBoard.hasContent,
                  previousBoard.signature != nextBoard.signature else {
                continue
            }

            let matchingPreviousBoard = previousSignatures.first {
                $0.id != nextBoard.id &&
                $0.hasContent &&
                $0.signature == nextBoard.signature &&
                $0.signature != previousBoard.signature
            }
            let matchingNextBoard = nextSignatures.first {
                $0.id != nextBoard.id &&
                $0.hasContent &&
                $0.signature == nextBoard.signature &&
                $0.signature != previousBoard.signature
            }

            guard let sourceBoard = matchingPreviousBoard ?? matchingNextBoard else {
                continue
            }

            debugReportNamedBoardsIntegrityFailure(
                """
                [BoardIntegrity] Possible cross-board overwrite detected. Board "\(nextBoard.name)" (\(nextBoard.id)) changed from its previous content to match "\(sourceBoard.name)" (\(sourceBoard.id)). Check recent board persistence, widget sync, and lifecycle reload paths.
                """
            )
        }
    }

    private static func debugAssertNoCrossBoardCellIDReuse(in snapshot: NamedBoardsSnapshot) {
        guard snapshot.boards.count > 1 else { return }

        var ownerByCellID: [UUID: (boardID: UUID, boardName: String)] = [:]
        for namedBoard in snapshot.boards {
            for cell in debugCanonicalCells(in: namedBoard.board) {
                if let owner = ownerByCellID[cell.id], owner.boardID != namedBoard.id {
                    debugReportNamedBoardsIntegrityFailure(
                        """
                        [BoardIntegrity] Cell ID \(cell.id) appears in both "\(owner.boardName)" (\(owner.boardID)) and "\(namedBoard.name)" (\(namedBoard.id)). This usually means one board snapshot was copied into another without regenerating cell identities.
                        """
                    )
                } else {
                    ownerByCellID[cell.id] = (namedBoard.id, namedBoard.name)
                }
            }
        }
    }

    private static func debugReportNamedBoardsIntegrityFailure(_ message: String) {
        print(message)
        assertionFailure(message)
    }

    private static func debugBoardSignature(_ namedBoard: NamedBoard) -> DebugBoardSignature {
        DebugBoardSignature(
            id: namedBoard.id,
            name: namedBoard.name,
            hasContent: debugBoardHasContent(namedBoard.board),
            signature: debugBoardContentSignature(namedBoard.board)
        )
    }

    private static func debugBoardHasContent(_ board: SavedBoard) -> Bool {
        debugCanonicalCells(in: board).contains { $0.hasStoredTask || $0.isCompleted }
    }

    private static func debugBoardContentSignature(_ board: SavedBoard) -> String {
        [
            "grid=\(board.gridSize)",
            "lines=\(board.completedLines.map(debugLineSignature).sorted().joined(separator: ","))",
            "visible=\(debugCellMatrixSignature(board.cells))",
            "full=\(debugCellMatrixSignature(board.fullBoardCells ?? []))"
        ].joined(separator: "\n")
    }

    private static func debugCanonicalCells(in board: SavedBoard) -> [BingoCell] {
        let source = board.fullBoardCells ?? board.cells
        return source.flatMap { $0 }
    }

    private static func debugCellMatrixSignature(_ cells: [[BingoCell]]) -> String {
        cells.enumerated().map { row, rowCells in
            rowCells.enumerated().map { col, cell in
                "r\(row)c\(col):\(debugCellSignature(cell))"
            }.joined(separator: ";")
        }.joined(separator: "/")
    }

    private static func debugCellSignature(_ cell: BingoCell) -> String {
        let residentTaskText = cell.residentTaskText ?? "nil"
        let residentWeekdays = cell.residentWeekdays.sorted().map { String($0) }.joined(separator: ",")
        let startVisibleMonth = cell.startVisibleMonth.map { String($0) } ?? "nil"
        let startVisibleDay = cell.startVisibleDay.map { String($0) } ?? "nil"
        let countdownPausedRemainingSeconds = cell.countdownPausedRemainingSeconds.map { String($0) } ?? "nil"
        let estimatedDurationMinutes = cell.estimatedDurationMinutes.map { String($0) } ?? "nil"
        let recurrenceRule = debugRecurrenceRuleSignature(cell.recurrenceRule)

        let parts: [String] = [
            cell.id.uuidString,
            cell.text,
            residentTaskText,
            residentWeekdays,
            recurrenceRule,
            debugDateSignature(cell.oneTimeVisibleDate),
            debugDateSignature(cell.startVisibleAt),
            debugDateSignature(cell.endVisibleAt),
            startVisibleMonth,
            startVisibleDay,
            cell.isTaskHidden ? "hidden" : "shown",
            cell.isCompleted ? "done" : "open",
            cell.isForced ? "forced" : "normal",
            debugDateSignature(cell.countdownEndsAt),
            countdownPausedRemainingSeconds,
            estimatedDurationMinutes,
            String(cell.completionStreakCount),
            debugDateSignature(cell.lastCompletedAt),
            debugDateSignature(cell.lastVisibilityWindowTimeoutAt)
        ]
        return parts.joined(separator: "|")
    }

    private static func debugRecurrenceRuleSignature(_ rule: TaskRecurrenceRule?) -> String {
        guard let rule else { return "nil" }
        let weekdays = rule.weekdays.sorted().map { String($0) }.joined(separator: ",")
        let monthDay = rule.monthDay.map { String($0) } ?? "nil"
        return [
            rule.kind.rawValue,
            String(rule.interval),
            weekdays,
            monthDay,
            debugDateSignature(rule.anchorDate)
        ].joined(separator: ":")
    }

    private static func debugDateSignature(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return String(date.timeIntervalSinceReferenceDate)
    }

    private static func debugLineSignature(_ line: BingoLine) -> String {
        switch line {
        case .row(let row):
            return "row:\(row)"
        case .column(let column):
            return "column:\(column)"
        case .diagonalMain:
            return "diagonalMain"
        case .diagonalAnti:
            return "diagonalAnti"
        }
    }
    #endif

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static var sharedFileURL: URL {
        sharedURL(for: sharedFileName)
    }

    private static var namedBoardsFileURL: URL {
        sharedURL(for: boardsFileName)
    }

    private static func preferredBoardDataCandidates(
        fileData: Data?,
        sharedData: Data?,
        standardData: Data?
    ) -> [Data] {
        let candidates = uniqueDataCandidates([fileData, sharedData, standardData])
        let committed = candidates.compactMap { data -> (data: Data, revision: UInt64)? in
            guard (try? JSONDecoder().decode(SavedBoard.self, from: data)) != nil,
                  let metadata = try? JSONDecoder().decode(ActiveBoardCommitMetadata.self, from: data) else { return nil }
            return (data, metadata.activeCommitRevision)
        }.sorted { $0.revision > $1.revision }
        if let newest = committed.first {
            if candidates.count > 1 {
                DiagnosticLogStore.recordWarning("task_rule.active_replica_recovery", details: [
                    "selected_revision": String(newest.revision),
                    "replica_count": String(candidates.count),
                    "committed_count": String(committed.count)
                ])
            }
            return uniqueDataCandidates(committed.map { $0.data } + candidates)
        }
        let defaultsData = sharedData ?? standardData
        guard let fileData else {
            return uniqueDataCandidates([defaultsData, standardData])
        }
        guard let defaultsData, defaultsData != fileData else {
            return uniqueDataCandidates([fileData, sharedData, standardData])
        }

        let fileModifiedAt = try? sharedFileURL
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        let defaultsSavedAt = (sharedDefaults.object(forKey: lastSavedAtKey) as? Date)
            ?? (UserDefaults.standard.object(forKey: lastSavedAtKey) as? Date)
        let defaultsAreNewer = defaultsSavedAt.map { savedAt in
            guard let fileModifiedAt else { return true }
            return savedAt > fileModifiedAt
        } ?? false

        return defaultsAreNewer
            ? uniqueDataCandidates([defaultsData, fileData, standardData])
            : uniqueDataCandidates([fileData, defaultsData, standardData])
    }

    private static func uniqueDataCandidates(_ candidates: [Data?]) -> [Data] {
        var seen = Set<Data>()
        return candidates.compactMap { data in
            guard let data, seen.insert(data).inserted else { return nil }
            return data
        }
    }

    private static func repairBoardPersistenceIfNeeded(_ data: Data) {
        var steps: [PersistenceWriteStep] = []
        if (try? Data(contentsOf: sharedFileURL)) != data {
            guard let fileStep = PersistenceWriteTransaction.fileDataStep(
                at: sharedFileURL,
                newData: data
            ) else { return }
            steps.append(fileStep)
        }
        if sharedDefaults.data(forKey: saveKey) != data {
            steps.append(PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: saveKey,
                newValue: data
            ))
        }
        if UserDefaults.standard.data(forKey: saveKey) != data {
            steps.append(PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: saveKey,
                newValue: data
            ))
        }
        _ = PersistenceWriteTransaction.commit(steps)
    }

    private static func preferredNamedBoardsPersistenceCandidate() -> NamedBoardsPersistenceCandidate? {
        let fileData = try? Data(contentsOf: namedBoardsFileURL)
        let candidates = [
            (NamedBoardsPersistenceSource.file, fileData),
            (
                .sharedDefaults,
                sharedDefaults.data(forKey: boardsSaveKey)
            ),
            (
                .standardDefaults,
                UserDefaults.standard.data(forKey: boardsSaveKey)
            )
        ].compactMap { source, data -> NamedBoardsPersistenceCandidate? in
            guard let data,
                  let snapshot = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) else {
                return nil
            }
            return NamedBoardsPersistenceCandidate(
                source: source,
                data: data,
                snapshot: snapshot,
                savedAt: (try? JSONDecoder().decode(SnapshotCommitMetadata.self, from: data))?.localCommittedAt
            )
        }

        let selected = candidates.max { lhs, rhs in
            if lhs.freshness != rhs.freshness {
                return lhs.freshness < rhs.freshness
            }
            return lhs.source.rawValue > rhs.source.rawValue
        }
        if let selected, candidates.contains(where: { $0.snapshot != selected.snapshot }) {
            for candidate in candidates {
                DiagnosticLogStore.recordWarning("board.snapshot_replica_conflict", details: [
                    "source": candidate.source.diagnosticValue,
                    "selected_source": selected.source.diagnosticValue,
                    "committed_at": String(candidate.freshness.timeIntervalSince1970),
                    "legacy": String(candidate.savedAt == nil),
                    "boards": String(candidate.snapshot.boards.count),
                    "commit_id": (try? JSONDecoder().decode(SnapshotCommitMetadata.self, from: candidate.data).localCommitID?.uuidString) ?? "legacy"
                ])
            }
        }
        return selected
    }

    private static func recordNamedBoardsReplicaRecoveryIfNeeded(
        selected: NamedBoardsPersistenceCandidate
    ) {
        guard selected.source != .file,
              let fileData = try? Data(contentsOf: namedBoardsFileURL),
              fileData != selected.data else {
            return
        }
        DiagnosticLogStore.recordWarning(
            "board.named_snapshot_newer_replica_selected",
            details: [
                "selected_source": selected.source.diagnosticValue,
                "selected_saved_at": String(selected.freshness.timeIntervalSinceReferenceDate)
            ]
        )
    }

    private static func recordSnapshotTransition(from previous: NamedBoardsSnapshot?, to next: NamedBoardsSnapshot, operationID: String, source: String) {
        guard let previous else { return }
        for board in previous.boards {
            let nextBoard = next.boards.first { $0.id == board.id }
            let nextCells = nextBoard.map { BoardEngine.expandedBoardCache(from: $0.board).flatMap { $0 } } ?? []
            for cell in BoardEngine.expandedBoardCache(from: board.board).flatMap({ $0 }) where cell.hasStoredTask {
                let replacement = nextCells.first { $0.id == cell.id }
                let nextRule = replacement.flatMap { $0.hasStoredTask ? $0.diagnosticTaskRuleKind : nil } ?? "removed"
                guard nextRule != cell.diagnosticTaskRuleKind else { continue }
                DiagnosticLogStore.recordStateChange("board.snapshot_task_transition", details: [
                    "source": source,
                    "operation_id": operationID,
                    "board_id": String(board.id.uuidString.prefix(8)),
                    "cell_id": String(cell.id.uuidString.prefix(8)),
                    "before_rule": cell.diagnosticTaskRuleKind,
                    "after_rule": nextRule,
                    "board_removed": String(nextBoard == nil)
                ])
            }
        }
    }

    private static func repairNamedBoardsPersistenceIfNeeded(_ data: Data, savedAt: Date) {
        var steps: [PersistenceWriteStep] = []
        if (try? Data(contentsOf: namedBoardsFileURL)) != data {
            guard let fileStep = PersistenceWriteTransaction.fileDataStep(
                at: namedBoardsFileURL,
                newData: data
            ) else { return }
            steps.append(fileStep)
        }
        if sharedDefaults.data(forKey: boardsSaveKey) != data {
            steps.append(PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: boardsSaveKey,
                newValue: data
            ))
        }
        if UserDefaults.standard.data(forKey: boardsSaveKey) != data {
            steps.append(PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: boardsSaveKey,
                newValue: data
            ))
        }
        if (sharedDefaults.object(forKey: namedBoardsLastSavedAtKey) as? Date) != savedAt {
            steps.append(PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: namedBoardsLastSavedAtKey,
                newValue: savedAt
            ))
        }
        if (UserDefaults.standard.object(forKey: namedBoardsLastSavedAtKey) as? Date) != savedAt {
            steps.append(PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: namedBoardsLastSavedAtKey,
                newValue: savedAt
            ))
        }
        let repaired = PersistenceWriteTransaction.commit(steps)
        if !steps.isEmpty {
            DiagnosticLogStore.record("board.snapshot_repair_result", category: "state_change",
                level: repaired ? .info : .warning,
                details: ["success": String(repaired), "steps": String(steps.count)])
        }
    }

    private static func repairStandardDefaultsValueIfNeeded(
        _ value: Any,
        forKey key: String
    ) {
        guard let current = UserDefaults.standard.object(forKey: key) as? NSObject,
              !current.isEqual(value as AnyObject) else {
            if UserDefaults.standard.object(forKey: key) == nil {
                _ = PersistenceWriteTransaction.commit([
                    PersistenceWriteTransaction.userDefaultsStep(
                        defaults: .standard,
                        key: key,
                        newValue: value
                    )
                ])
            }
            return
        }
        _ = PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: key,
                newValue: value
            )
        ])
    }

    private static func isNamedBoardsPersistenceCurrent(_ data: Data) -> Bool {
        guard (try? Data(contentsOf: namedBoardsFileURL)) == data else {
            return false
        }
        guard sharedDefaults.data(forKey: boardsSaveKey) == data else {
            return false
        }
        guard UserDefaults.standard.data(forKey: boardsSaveKey) == data else {
            return false
        }
        return (sharedDefaults.object(forKey: namedBoardsLastSavedAtKey) as? Date) != nil &&
            (UserDefaults.standard.object(forKey: namedBoardsLastSavedAtKey) as? Date) != nil
    }

    private static var metricsFileURL: URL {
        sharedURL(for: metricsFileName)
    }

    private static func loadOrCreateMetrics(referenceDate: Date) -> WidgetMetrics {
        if let data = try? Data(contentsOf: metricsFileURL),
           let metrics = try? JSONDecoder().decode(WidgetMetrics.self, from: data) {
            return metrics
        }

        let metrics = WidgetMetrics(firstSeenAt: referenceDate)
        persistMetrics(metrics)
        return metrics
    }

    private static func persistMetrics(_ metrics: WidgetMetrics) {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        try? data.write(to: metricsFileURL, options: .atomic)
    }

    private static func sharedURL(for fileName: String) -> URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let directory = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(fileName)
        }

        #if targetEnvironment(simulator)
        let simulatorDirectory = URL(fileURLWithPath: "/tmp/\(appGroupID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: simulatorDirectory, withIntermediateDirectories: true)
        return simulatorDirectory.appendingPathComponent(fileName)
        #else
        let fallbackDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        return fallbackDirectory.appendingPathComponent(fileName)
        #endif
    }
}
