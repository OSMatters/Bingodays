import Combine
import Foundation

protocol BoardManagementRepository: BoardStateCommitRepository, WidgetPanelSelectionRepository {
    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot
    @discardableResult
    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool
    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, expected: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool
    func loadBoardLastSavedAt() -> Date?

    func loadWidgetTaskSyncEvent() -> WidgetTaskSyncStore.Event?
    func clearWidgetTaskSyncEvent(ifMatching eventID: UUID)
    func unconfirmedRuleDowngrades(from previous: SavedBoard?, to board: SavedBoard, boardID: UUID) -> Set<UUID>
    func taskRuleRecoveryBoard(_ persisted: BingoBoardStore.NamedBoard) -> BingoBoardStore.NamedBoard
}

extension BoardManagementRepository {
    func taskRuleRecoveryBoard(_ persisted: BingoBoardStore.NamedBoard) -> BingoBoardStore.NamedBoard { persisted }
    func unconfirmedRuleDowngrades(from previous: SavedBoard?, to board: SavedBoard, boardID: UUID) -> Set<UUID> {
        TaskRulePersistenceGuard.downgradedCellIDs(from: previous, to: board)
    }
    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, expected: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool {
        guard loadNamedBoardsSnapshot() == expected else { return false }
        return saveNamedBoardsSnapshot(snapshot, reloadWidgets: reloadWidgets)
    }
}

struct BoardManagementMutationResult: Equatable {
    let selectedBoard: BingoBoardStore.NamedBoard
    let didChangeSelection: Bool
    let commitResult: BoardStateCommitResult
    let shouldInvalidateCountdownTickSchedule: Bool
    let shouldSyncTaskReminders: Bool
}

enum BoardRenameResult: Equatable {
    case renamed
    case unchanged
    case persistenceFailed
}

struct LiveBoardManagementRepository: BoardManagementRepository {
    func taskRuleRecoveryBoard(_ persisted: BingoBoardStore.NamedBoard) -> BingoBoardStore.NamedBoard {
        BingoBoardStore.taskRuleRecoveryBoard(persisted)
    }
    func unconfirmedRuleDowngrades(from previous: SavedBoard?, to board: SavedBoard, boardID: UUID) -> Set<UUID> {
        BingoBoardStore.unconfirmedRuleDowngrades(from: previous, to: board, boardID: boardID)
    }
    private let widgetTimelineReloadScheduler: any WidgetTimelineReloadScheduling

    init(
        widgetTimelineReloadScheduler: any WidgetTimelineReloadScheduling = WidgetTimelineReloadScheduler.shared
    ) {
        self.widgetTimelineReloadScheduler = widgetTimelineReloadScheduler
    }

    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot {
        BingoBoardStore.loadNamedBoardsSnapshot()
    }

    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool {
        let didSave = BingoBoardStore.saveNamedBoardsSnapshot(snapshot, reloadWidgets: false)
        if didSave, reloadWidgets {
            widgetTimelineReloadScheduler.requestReload()
        }
        return didSave
    }

    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, expected: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool {
        let didSave = BingoBoardStore.saveNamedBoardsSnapshot(snapshot, reloadWidgets: false, expectedSnapshot: expected)
        if didSave, reloadWidgets { widgetTimelineReloadScheduler.requestReload() }
        return didSave
    }

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

    func loadWidgetTaskSyncEvent() -> WidgetTaskSyncStore.Event? {
        WidgetTaskSyncStore.load()
    }

    func clearWidgetTaskSyncEvent(ifMatching eventID: UUID) {
        WidgetTaskSyncStore.clear(ifMatching: eventID)
    }

    func loadSelectedWidgetPanelID() -> UUID? {
        WidgetPanelSelectionStore.loadSelectedPanelID()
    }

    func saveSelectedWidgetPanelID(_ boardID: UUID?) {
        WidgetPanelSelectionStore.saveSelectedPanelID(boardID)
    }

    func reloadWidgetTimelines() {
        widgetTimelineReloadScheduler.requestReload()
    }
}

@MainActor
final class BoardManagementStore: ObservableObject {
    static let boardNameMaxLength = 20

    @Published var namedBoards: [BingoBoardStore.NamedBoard] = []
    @Published var selectedBoardID: UUID?
    @Published var hasLoadedBoardSwitcherState = false

    private let repository: any BoardManagementRepository
    private var deletedBoardIDs: Set<UUID> = []
    private var protectedBoardID: UUID?
    private var boardOrderModifiedAt: Date?
    private var requiresNamedBoardsPersistenceRetry = false
    private var didRejectTaskRulesDuringLastSave = false
    private var requiresActiveBoardMirrorPersistenceRetry = false
    private var persistenceBaseline: BingoBoardStore.NamedBoardsSnapshot

    init(repository: any BoardManagementRepository = LiveBoardManagementRepository()) {
        self.repository = repository
        persistenceBaseline = repository.loadNamedBoardsSnapshot()
    }

    var selectedNamedBoardIndex: Int? {
        guard let selectedBoardID else { return nil }
        return namedBoards.firstIndex(where: { $0.id == selectedBoardID })
    }

    var selectedBoardName: String {
        guard let selectedNamedBoardIndex else {
            return L10n.boardDefaultName(1)
        }
        return namedBoards[selectedNamedBoardIndex].name
    }

    var selectedBoardSnapshot: BingoBoardStore.NamedBoard? {
        selectedBoard
    }

    var freePlanProtectedBoardID: UUID? {
        protectedBoardID ?? namedBoards.first?.id
    }

    func loadIfNeeded(
        initialBoard: SavedBoard,
        countdownEndsAt: Date?
    ) -> BingoBoardStore.NamedBoard? {
        guard !hasLoadedBoardSwitcherState else {
            return selectedBoard
        }
        hasLoadedBoardSwitcherState = true

        var snapshot = persistedSnapshotPreferringCurrentBoard()
        if snapshot.boards.isEmpty {
            let initialBoard = BingoBoardStore.NamedBoard(
                name: L10n.boardDefaultName(1),
                board: initialBoard,
                countdownEndsAt: countdownEndsAt,
                updatedAt: .now
            )
            snapshot = BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: initialBoard.id,
                boards: [initialBoard],
                deletedBoardIDs: snapshot.effectiveDeletedBoardIDs,
                protectedBoardID: initialBoard.id
            )
            saveNamedBoardsSnapshotIfChanged(snapshot, reloadWidgets: true)
        }

        namedBoards = snapshot.boards
        deletedBoardIDs = snapshot.effectiveDeletedBoardIDs
        protectedBoardID = snapshot.effectiveProtectedBoardID
        boardOrderModifiedAt = snapshot.boardOrderModifiedAt
        selectedBoardID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
        refreshActiveBoardMirrorPersistenceRetryRequirement()
        return selectedBoard
    }

    func reloadPersistedSnapshotIfNewer() -> BingoBoardStore.NamedBoard? {
        guard hasLoadedBoardSwitcherState else { return nil }

        let snapshot = persistedSnapshotPreferringCurrentBoard()
        guard !snapshot.boards.isEmpty else { return nil }

        let currentBoardsByID = Dictionary(uniqueKeysWithValues: namedBoards.map { ($0.id, $0) })
        let hasNewerBoard = snapshot.boards.contains { persistedBoard in
            guard let currentBoard = currentBoardsByID[persistedBoard.id] else { return true }
            return persistedBoard.updatedAt > currentBoard.updatedAt
        }
        let hasBoardMembershipChange = Set(snapshot.boards.map(\.id)) != Set(namedBoards.map(\.id)) ||
            snapshot.effectiveDeletedBoardIDs != deletedBoardIDs
        let hasBoardOrderChange = snapshot.boards.map(\.id) != namedBoards.map(\.id) ||
            snapshot.boardOrderModifiedAt != boardOrderModifiedAt ||
            snapshot.effectiveProtectedBoardID != freePlanProtectedBoardID
        let selectedID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
        let hasSelectionChange = selectedID != selectedBoardID

        guard hasNewerBoard || hasBoardMembershipChange || hasBoardOrderChange || hasSelectionChange else { return nil }

        namedBoards = snapshot.boards
        deletedBoardIDs = snapshot.effectiveDeletedBoardIDs
        protectedBoardID = snapshot.effectiveProtectedBoardID
        boardOrderModifiedAt = snapshot.boardOrderModifiedAt
        selectedBoardID = selectedID
        refreshActiveBoardMirrorPersistenceRetryRequirement()
        return selectedBoard
    }

    func reloadPersistedSnapshot() -> BingoBoardStore.NamedBoard? {
        guard hasLoadedBoardSwitcherState else { return nil }

        let snapshot = persistedSnapshotPreferringCurrentBoard()
        guard !snapshot.boards.isEmpty else { return nil }

        namedBoards = snapshot.boards
        deletedBoardIDs = snapshot.effectiveDeletedBoardIDs
        protectedBoardID = snapshot.effectiveProtectedBoardID
        boardOrderModifiedAt = snapshot.boardOrderModifiedAt
        selectedBoardID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
        refreshActiveBoardMirrorPersistenceRetryRequirement()
        return selectedBoard
    }

    @discardableResult
    func persistSnapshot(reloadWidgets: Bool = true) -> Bool {
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: namedBoards,
            deletedBoardIDs: deletedBoardIDs,
            protectedBoardID: freePlanProtectedBoardID,
            boardOrderModifiedAt: boardOrderModifiedAt
        )
        return saveNamedBoardsSnapshotIfChanged(snapshot, reloadWidgets: reloadWidgets)
    }

    func replaceBoards(
        _ boards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        save: Bool
    ) {
        namedBoards = boards
        self.selectedBoardID = selectedBoardID
        if save {
            persistSnapshot()
        }
    }

    @discardableResult
    func persistBoardState(
        for boardID: UUID,
        board: SavedBoard,
        countdownEndsAt: Date?,
        save: Bool = true
    ) -> Bool {
        guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else { return false }
        let persistenceDate = Date()
        let normalizedBoard = BingoBoardStore.normalizedBoardForPersistence(
            board,
            referenceDate: persistenceDate
        )
        guard !rejectUnconfirmedRuleChanges([(boardID, normalizedBoard)]) else { return false }
        let didChangeState = namedBoards[boardIndex].board != normalizedBoard ||
            namedBoards[boardIndex].countdownEndsAt != countdownEndsAt

        if didChangeState {
            namedBoards[boardIndex].board = normalizedBoard
            namedBoards[boardIndex].countdownEndsAt = countdownEndsAt
            namedBoards[boardIndex].updatedAt = persistenceDate
            requiresNamedBoardsPersistenceRetry = true
        }

        let shouldMirrorActiveBoard = selectedBoardID == boardID
        let shouldPersistNamedBoards = didChangeState || requiresNamedBoardsPersistenceRetry
        let shouldPersistActiveBoardMirror = shouldMirrorActiveBoard &&
            (didChangeState || requiresActiveBoardMirrorPersistenceRetry)

        guard save, shouldPersistNamedBoards || shouldPersistActiveBoardMirror else {
            return didChangeState
        }
        let activeMirror = shouldPersistActiveBoardMirror ? namedBoards[boardIndex] : nil
        let commitResult = commitNamedBoardsSnapshot(
            activeMirror: activeMirror,
            persistNamedBoardsSnapshot: shouldPersistNamedBoards,
            requireNamedBoardsPersistenceBeforeActiveMirror: false
        )
        if commitResult.failedToSaveNamedBoards,
           !repository.unconfirmedRuleDowngrades(
                from: repository.loadNamedBoardsSnapshot().boards.first { $0.id == boardID }?.board,
                to: normalizedBoard, boardID: boardID
           ).isEmpty {
            return false
        }
        return didChangeState
    }

    @discardableResult
    func syncSelectedBoard(
        board: SavedBoard,
        countdownEndsAt: Date?
    ) -> Bool {
        guard hasLoadedBoardSwitcherState, let selectedBoardID else { return false }
        return persistBoardState(
            for: selectedBoardID,
            board: board,
            countdownEndsAt: countdownEndsAt
        )
    }

    /// Rebuilds every board's completion-count display cache from the shared,
    /// name-scoped history ledger. The derived cache must not advance a board's
    /// `updatedAt`, otherwise a count-only repair could win a real board-content
    /// conflict during iCloud merge.
    @discardableResult
    func reconcileCompletionHistoryCounts(
        _ records: [TaskCompletionHistoryRecord]
    ) -> Bool {
        guard hasLoadedBoardSwitcherState, !namedBoards.isEmpty else { return false }

        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: namedBoards,
            deletedBoardIDs: deletedBoardIDs,
            protectedBoardID: freePlanProtectedBoardID,
            boardOrderModifiedAt: boardOrderModifiedAt
        )
        let reconciledSnapshot = TaskCompletionHistoryRuleEngine
            .namedBoardsSnapshotByReconcilingCompletionHistory(snapshot, records: records)
        guard reconciledSnapshot != snapshot else { return false }

        namedBoards = reconciledSnapshot.boards
        requiresNamedBoardsPersistenceRetry = true
        _ = persistSnapshot(reloadWidgets: true)
        return true
    }

    func hasDurableSelectedBoardState() -> Bool {
        guard let selectedBoard else { return false }
        let persistedSnapshot = repository.loadNamedBoardsSnapshot()
        guard persistedSnapshot.selectedBoardID == selectedBoardID,
              persistedSnapshot.boards.first(where: { $0.id == selectedBoard.id }) == selectedBoard else {
            return false
        }
        return repository.loadBoard() == selectedBoard.board &&
            repository.loadBoardCountdownEndsAt() == selectedBoard.countdownEndsAt &&
            repository.loadActiveNamedBoardID() == selectedBoard.id &&
            repository.loadSelectedWidgetPanelID() == selectedBoard.id
    }

    func selectBoard(
        _ boardID: UUID,
        currentBoard: SavedBoard,
        currentCountdownEndsAt: Date?
    ) -> BoardManagementMutationResult? {
        if selectedBoardID == boardID {
            guard let selectedBoard else { return nil }
            return BoardManagementMutationResult(
                selectedBoard: selectedBoard,
                didChangeSelection: false,
                commitResult: BoardStateCommitResult(),
                shouldInvalidateCountdownTickSchedule: false,
                shouldSyncTaskReminders: false
            )
        }
        guard namedBoards.contains(where: { $0.id == boardID }) else { return nil }

        if let previousBoardID = selectedBoardID {
            persistBoardState(
                for: previousBoardID,
                board: currentBoard,
                countdownEndsAt: currentCountdownEndsAt,
                save: false
            )
        }

        let rollbackBoards = namedBoards
        let rollbackSelectedBoardID = selectedBoardID
        selectedBoardID = boardID
        let selected = selectedBoard
        guard let selected else { return nil }
        let commitResult = commitNamedBoardsSnapshot(activeMirror: selected)
        guard !commitResult.failedToSaveNamedBoards else {
            restoreBoardManagementState(
                boards: rollbackBoards,
                selectedBoardID: rollbackSelectedBoardID
            )
            return nil
        }
        return BoardManagementMutationResult(
            selectedBoard: selected,
            didChangeSelection: true,
            commitResult: commitResult,
            shouldInvalidateCountdownTickSchedule: true,
            shouldSyncTaskReminders: true
        )
    }

    func createBoard(
        nameDraft: String,
        currentBoard: SavedBoard?,
        currentCountdownEndsAt: Date?
    ) -> BoardManagementMutationResult? {
        if let selectedBoardID, let currentBoard {
            persistBoardState(
                for: selectedBoardID,
                board: currentBoard,
                countdownEndsAt: currentCountdownEndsAt,
                save: false
            )
        }

        let rollbackBoards = namedBoards
        let rollbackSelectedBoardID = selectedBoardID
        let fallbackName = L10n.boardDefaultName(namedBoards.count + 1)
        let boardName = Self.sanitizedBoardName(nameDraft, fallback: fallbackName)
        let newBoard = BingoBoardStore.NamedBoard(
            name: boardName,
            board: BingoViewModel.createDefaultSavedBoard(),
            countdownEndsAt: nil,
            updatedAt: .now
        )

        namedBoards.append(newBoard)
        selectedBoardID = newBoard.id
        let commitResult = commitNamedBoardsSnapshot(activeMirror: newBoard)
        guard !commitResult.failedToSaveNamedBoards else {
            restoreBoardManagementState(
                boards: rollbackBoards,
                selectedBoardID: rollbackSelectedBoardID
            )
            return nil
        }
        return BoardManagementMutationResult(
            selectedBoard: newBoard,
            didChangeSelection: true,
            commitResult: commitResult,
            shouldInvalidateCountdownTickSchedule: true,
            shouldSyncTaskReminders: true
        )
    }

    func deleteBoard(
        _ boardID: UUID,
        allowsDeletingFirstBoard: Bool
    ) -> BoardManagementMutationResult? {
        guard canDeleteBoard(boardID, allowsDeletingFirstBoard: allowsDeletingFirstBoard),
              let removeIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else {
            return nil
        }

        let previousSelectedID = selectedBoardID
        let rollbackBoards = namedBoards
        let rollbackSelectedBoardID = selectedBoardID
        let rollbackDeletedBoardIDs = deletedBoardIDs
        let rollbackProtectedBoardID = protectedBoardID
        var nextSelectedID = selectedBoardID
        if selectedBoardID == boardID {
            let fallbackIndex = removeIndex == 0 ? 1 : removeIndex - 1
            nextSelectedID = namedBoards.indices.contains(fallbackIndex) ? namedBoards[fallbackIndex].id : nil
        }

        namedBoards.remove(at: removeIndex)
        deletedBoardIDs.insert(boardID)
        if protectedBoardID == boardID {
            protectedBoardID = namedBoards.first?.id
        }

        if let nextSelectedID,
           namedBoards.contains(where: { $0.id == nextSelectedID }) {
            selectedBoardID = nextSelectedID
        } else {
            selectedBoardID = namedBoards.first?.id
        }

        guard let selectedAfterDelete = selectedBoard else { return nil }
        let commitResult = commitNamedBoardsSnapshot(activeMirror: selectedAfterDelete)
        guard !commitResult.failedToSaveNamedBoards else {
            restoreBoardManagementState(
                boards: rollbackBoards,
                selectedBoardID: rollbackSelectedBoardID,
                deletedBoardIDs: rollbackDeletedBoardIDs,
                protectedBoardID: rollbackProtectedBoardID
            )
            return nil
        }
        return BoardManagementMutationResult(
            selectedBoard: selectedAfterDelete,
            didChangeSelection: previousSelectedID != selectedBoardID,
            commitResult: commitResult,
            shouldInvalidateCountdownTickSchedule: true,
            shouldSyncTaskReminders: true
        )
    }

    func canDeleteBoard(_ boardID: UUID, allowsDeletingFirstBoard: Bool) -> Bool {
        guard namedBoards.count > 1 else { return false }

        if !allowsDeletingFirstBoard,
           boardID == freePlanProtectedBoardID {
            return false
        }

        return true
    }

    /// Reorders only board presentation metadata. It deliberately leaves every
    /// board payload and its `updatedAt` untouched, so task/rule conflicts keep
    /// using their existing per-board timestamps.
    @discardableResult
    func reorderBoards(_ orderedBoardIDs: [UUID]) -> Bool {
        guard orderedBoardIDs.count == namedBoards.count,
              Set(orderedBoardIDs).count == orderedBoardIDs.count,
              Set(orderedBoardIDs) == Set(namedBoards.map(\.id)),
              orderedBoardIDs.first == namedBoards.first?.id else {
            return false
        }
        guard orderedBoardIDs != namedBoards.map(\.id) else { return true }

        let rollbackBoards = namedBoards
        let rollbackOrderModifiedAt = boardOrderModifiedAt
        let rollbackProtectedBoardID = protectedBoardID
        protectedBoardID = freePlanProtectedBoardID
        let boardsByID = Dictionary(uniqueKeysWithValues: namedBoards.map { ($0.id, $0) })
        namedBoards = orderedBoardIDs.compactMap { boardsByID[$0] }
        boardOrderModifiedAt = .now

        guard persistSnapshot() else {
            namedBoards = rollbackBoards
            boardOrderModifiedAt = rollbackOrderModifiedAt
            protectedBoardID = rollbackProtectedBoardID
            reconcileTaskRulesBeforeReset()
            return false
        }
        return true
    }

    func renameBoard(_ boardID: UUID, nameDraft: String) -> BoardRenameResult {
        guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else {
            return .unchanged
        }
        let fallbackName = L10n.boardDefaultName(boardIndex + 1)
        let boardName = Self.sanitizedBoardName(nameDraft, fallback: fallbackName)
        guard namedBoards[boardIndex].name != boardName else { return .unchanged }

        let rollbackBoards = namedBoards
        let rollbackSelectedBoardID = selectedBoardID
        namedBoards[boardIndex].name = boardName
        namedBoards[boardIndex].updatedAt = .now
        persistSnapshot()
        guard !requiresNamedBoardsPersistenceRetry, !didRejectTaskRulesDuringLastSave else {
            restoreBoardManagementState(
                boards: rollbackBoards,
                selectedBoardID: rollbackSelectedBoardID
            )
            return .persistenceFailed
        }
        return .renamed
    }

    @discardableResult
    func markSelectedBoardAsStarterGuide() -> Bool {
        guard let selectedBoardID,
              let boardIndex = namedBoards.firstIndex(where: { $0.id == selectedBoardID }) else {
            return false
        }
        guard namedBoards[boardIndex].origin != .starterGuide else { return true }

        let previousBoard = namedBoards[boardIndex]
        namedBoards[boardIndex].origin = .starterGuide
        namedBoards[boardIndex].updatedAt = .now
        let didSave = persistSnapshot(reloadWidgets: false)
        guard didSave else {
            namedBoards[boardIndex] = previousBoard
            return false
        }
        return true
    }

    func boardName(for boardID: UUID) -> String {
        guard let board = namedBoards.first(where: { $0.id == boardID }) else {
            return L10n.boardDefaultName(1)
        }
        return board.name
    }

    static func sanitizedBoardName(_ rawName: String, fallback: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(boardNameMaxLength))
        return limited.isEmpty ? fallback : limited
    }

    private var selectedBoard: BingoBoardStore.NamedBoard? {
        guard let selectedBoardID else { return namedBoards.first }
        return namedBoards.first(where: { $0.id == selectedBoardID }) ?? namedBoards.first
    }

    private func persistedSnapshotPreferringCurrentBoard() -> BingoBoardStore.NamedBoardsSnapshot {
        var snapshot = repository.loadNamedBoardsSnapshot()
        persistenceBaseline = snapshot
        snapshot = snapshotByApplyingPendingWidgetTaskEvent(snapshot)
        let activeMirrorBoardID = repository.loadActiveNamedBoardID()
        let locallySelectedSnapshot = BingoBoardStore.snapshotByApplyingLocalSelection(
            snapshot,
            activeBoardID: activeMirrorBoardID
        )
        if locallySelectedSnapshot != snapshot {
            _ = saveNamedBoardsSnapshotIfChanged(
                locallySelectedSnapshot,
                reloadWidgets: false
            )
            snapshot = locallySelectedSnapshot
        }
        guard !snapshot.boards.isEmpty,
              let currentBoard = repository.loadBoard(),
              let currentBoardSavedAt = repository.loadBoardLastSavedAt() else {
            return snapshot
        }

        let targetIndex: Int?
        if let activeMirrorBoardID {
            targetIndex = snapshot.boards.firstIndex(where: { $0.id == activeMirrorBoardID })
        } else if snapshot.boards.count == 1 {
            targetIndex = snapshot.boards.startIndex
        } else {
            targetIndex = nil
        }

        guard let targetIndex else { return snapshot }

        if !BingoBoardStore.hasMatchingCellIdentity(
            currentBoard,
            snapshot.boards[targetIndex].board
        ) {
            let authoritativeBoard = snapshot.boards[targetIndex]
            _ = BoardStateCommitter.saveActiveBoardState(
                board: authoritativeBoard.board,
                countdownEndsAt: authoritativeBoard.countdownEndsAt,
                savedAt: authoritativeBoard.updatedAt,
                associatedBoardID: authoritativeBoard.id,
                repository: repository,
                widgetPanelRepository: repository,
                selectedWidgetPanelID: authoritativeBoard.id,
                reloadWidgets: true
            )
            DiagnosticLogStore.recordWarning(
                "board.active_mirror_repaired",
                details: ["board_id": String(authoritativeBoard.id.uuidString.prefix(8))]
            )
            return snapshot
        }

        guard currentBoardSavedAt > snapshot.boards[targetIndex].updatedAt else {
            return snapshot
        }

        guard repository.unconfirmedRuleDowngrades(
            from: snapshot.boards[targetIndex].board, to: currentBoard, boardID: snapshot.boards[targetIndex].id
        ).isEmpty else {
            DiagnosticLogStore.recordWarning("task_rule.active_mirror_downgrade_rejected", details: [
                "board_id": snapshot.boards[targetIndex].id.uuidString
            ])
            return snapshot
        }
        snapshot.boards[targetIndex].board = currentBoard
        snapshot.boards[targetIndex].countdownEndsAt = repository.loadBoardCountdownEndsAt()
        snapshot.boards[targetIndex].updatedAt = currentBoardSavedAt
        saveNamedBoardsSnapshotIfChanged(snapshot, reloadWidgets: true)
        return snapshot
    }

    private func snapshotByApplyingPendingWidgetTaskEvent(
        _ snapshot: BingoBoardStore.NamedBoardsSnapshot
    ) -> BingoBoardStore.NamedBoardsSnapshot {
        BingoBoardStore.withBoardPersistenceLock {
            applyPendingWidgetTaskEventUnderLock(snapshot)
        } ?? snapshot
    }

    private func applyPendingWidgetTaskEventUnderLock(
        _ snapshot: BingoBoardStore.NamedBoardsSnapshot
    ) -> BingoBoardStore.NamedBoardsSnapshot {
        guard let event = repository.loadWidgetTaskSyncEvent() else {
            return snapshot
        }

        let updatedSnapshot = WidgetTaskEventMerge.applying(event, to: snapshot, recoverBoard: repository.taskRuleRecoveryBoard)
        let savedNamedBoards: Bool
        if updatedSnapshot == snapshot {
            savedNamedBoards = false
        } else {
            savedNamedBoards = saveNamedBoardsSnapshotIfChanged(
                updatedSnapshot,
                reloadWidgets: false
            )
            guard savedNamedBoards else { return snapshot }
        }

        let activeBoard = updatedSnapshot.boards.first(where: {
            $0.id == updatedSnapshot.selectedBoardID
        }) ?? updatedSnapshot.boards.first
        var result = activeBoard.map { board in
            BoardStateCommitter.saveActiveBoardState(
                board: board.board,
                countdownEndsAt: board.countdownEndsAt,
                savedAt: board.updatedAt,
                associatedBoardID: board.id,
                repository: repository,
                reloadWidgets: false
            )
        } ?? BoardStateCommitResult()
        guard !result.failedToSaveBoard else { return updatedSnapshot }

        if !event.sideEffectsCommitted,
           let mergedBoard = updatedSnapshot.boards.first(where: { $0.id == event.boardID }) {
            guard WidgetTaskToggleService.reconcileRewards(
                for: event,
                mergedBoard: mergedBoard,
                now: event.savedAt
            ) else {
                return updatedSnapshot
            }
        }
        // Keep the event available until board and point recovery have both completed.
        repository.clearWidgetTaskSyncEvent(ifMatching: event.id)
        result.savedNamedBoards = savedNamedBoards
        BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)
        return updatedSnapshot
    }

    @discardableResult
    private func commitNamedBoardsSnapshot(
        activeMirror: BingoBoardStore.NamedBoard?,
        persistNamedBoardsSnapshot: Bool = true,
        requireNamedBoardsPersistenceBeforeActiveMirror: Bool = true
    ) -> BoardStateCommitResult {
        let savedNamedBoards = persistNamedBoardsSnapshot
            ? persistSnapshot(reloadWidgets: false)
            : false
        let failedToSaveNamedBoards = persistNamedBoardsSnapshot &&
            (requiresNamedBoardsPersistenceRetry || didRejectTaskRulesDuringLastSave)
        guard !failedToSaveNamedBoards ||
                !requireNamedBoardsPersistenceBeforeActiveMirror else {
            return BoardStateCommitResult(failedToSaveNamedBoards: true)
        }
        guard let activeMirror else {
            var result = BoardStateCommitResult(
                savedNamedBoards: savedNamedBoards,
                failedToSaveNamedBoards: failedToSaveNamedBoards
            )
            BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)
            return result
        }
        var result = persistActiveBoardMirror(
            boardID: activeMirror.id,
            board: activeMirror.board,
            countdownEndsAt: activeMirror.countdownEndsAt,
            savedAt: activeMirror.updatedAt
        )
        requiresActiveBoardMirrorPersistenceRetry = result.failedToSaveBoard
        result.savedNamedBoards = savedNamedBoards
        result.failedToSaveNamedBoards = failedToSaveNamedBoards
        BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)
        return result
    }

    @discardableResult
    private func persistActiveBoardMirror(
        boardID: UUID,
        board: SavedBoard,
        countdownEndsAt: Date?,
        savedAt: Date
    ) -> BoardStateCommitResult {
        BoardStateCommitter.saveActiveBoardState(
            board: board,
            countdownEndsAt: countdownEndsAt,
            savedAt: savedAt,
            associatedBoardID: boardID,
            repository: repository,
            widgetPanelRepository: repository,
            selectedWidgetPanelID: boardID,
            reloadWidgets: false
        )
    }

    @discardableResult
    private func saveNamedBoardsSnapshotIfChanged(
        _ snapshot: BingoBoardStore.NamedBoardsSnapshot,
        reloadWidgets: Bool
    ) -> Bool {
        didRejectTaskRulesDuringLastSave = false
        guard !rejectUnconfirmedRuleChanges(snapshot.boards.map { ($0.id, $0.board) }) else {
            didRejectTaskRulesDuringLastSave = true
            return false
        }
        let didSave = repository.saveNamedBoardsSnapshot(snapshot, expected: persistenceBaseline, reloadWidgets: reloadWidgets)
        if !didSave, rejectUnconfirmedRuleChanges(snapshot.boards.map { ($0.id, $0.board) }) {
            didRejectTaskRulesDuringLastSave = true
            return false
        }
        if didSave { persistenceBaseline = snapshot }
        requiresNamedBoardsPersistenceRetry = !didSave &&
            repository.loadNamedBoardsSnapshot() != snapshot
        return didSave
    }

    // A rejected rule mutation is not a retryable draft: reset must never consume it.
    private func rejectUnconfirmedRuleChanges(_ boards: [(UUID, SavedBoard)]) -> Bool {
        let durable = repository.loadNamedBoardsSnapshot()
        let rejected = boards.filter { id, board in
            !repository.unconfirmedRuleDowngrades(
                from: durable.boards.first { $0.id == id }?.board, to: board, boardID: id
            ).isEmpty
        }
        guard !rejected.isEmpty else { return false }
        for (id, _) in rejected {
            if let index = namedBoards.firstIndex(where: { $0.id == id }),
               let restored = durable.boards.first(where: { $0.id == id }) {
                namedBoards[index] = repository.taskRuleRecoveryBoard(restored)
            }
            DiagnosticLogStore.recordWarning("task_rule.memory_downgrade_rejected", details: ["board_id": id.uuidString])
        }
        requiresNamedBoardsPersistenceRetry = namedBoards != durable.boards
        refreshActiveBoardMirrorPersistenceRetryRequirement()
        return true
    }

    func reconcileTaskRulesBeforeReset() {
        _ = rejectUnconfirmedRuleChanges(namedBoards.map { ($0.id, $0.board) })
    }

    @discardableResult
    func commitResetBoards(_ boards: [BingoBoardStore.NamedBoard]) -> Bool {
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID, boards: boards,
            deletedBoardIDs: deletedBoardIDs, protectedBoardID: freePlanProtectedBoardID,
            boardOrderModifiedAt: boardOrderModifiedAt
        )
        let saved = saveNamedBoardsSnapshotIfChanged(snapshot, reloadWidgets: true)
        guard saved || repository.loadNamedBoardsSnapshot() == snapshot else {
            DiagnosticLogStore.recordWarning("task_rule.reset_commit_failed")
            return false
        }
        namedBoards = boards
        return true
    }

    private func refreshActiveBoardMirrorPersistenceRetryRequirement() {
        guard let selectedBoard else {
            requiresActiveBoardMirrorPersistenceRetry = false
            return
        }
        requiresActiveBoardMirrorPersistenceRetry =
            repository.loadBoard() != selectedBoard.board ||
            repository.loadBoardCountdownEndsAt() != selectedBoard.countdownEndsAt ||
            repository.loadActiveNamedBoardID() != selectedBoard.id ||
            repository.loadSelectedWidgetPanelID() != selectedBoard.id
    }

    private func restoreBoardManagementState(
        boards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        deletedBoardIDs: Set<UUID>? = nil,
        protectedBoardID: UUID? = nil
    ) {
        namedBoards = boards
        self.selectedBoardID = selectedBoardID
        if let deletedBoardIDs {
            self.deletedBoardIDs = deletedBoardIDs
        }
        if let protectedBoardID {
            self.protectedBoardID = protectedBoardID
        }
        let restoredSnapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: boards,
            deletedBoardIDs: self.deletedBoardIDs,
            protectedBoardID: freePlanProtectedBoardID,
            boardOrderModifiedAt: boardOrderModifiedAt
        )
        requiresNamedBoardsPersistenceRetry =
            repository.loadNamedBoardsSnapshot() != restoredSnapshot
        reconcileTaskRulesBeforeReset()
        refreshActiveBoardMirrorPersistenceRetryRequirement()
    }
}
