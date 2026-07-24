import Combine
import Foundation

protocol BoardManagementRepository: BoardStateCommitRepository, WidgetPanelSelectionRepository {
    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot
    @discardableResult
    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool
    func loadBoardLastSavedAt() -> Date?

    func loadWidgetTaskSyncEvent() -> WidgetTaskSyncStore.Event?
    func clearWidgetTaskSyncEvent(ifMatching eventID: UUID)
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
    private var requiresNamedBoardsPersistenceRetry = false
    private var requiresActiveBoardMirrorPersistenceRetry = false

    init(repository: any BoardManagementRepository = LiveBoardManagementRepository()) {
        self.repository = repository
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
                deletedBoardIDs: snapshot.effectiveDeletedBoardIDs
            )
            saveNamedBoardsSnapshotIfChanged(snapshot, reloadWidgets: true)
        }

        namedBoards = snapshot.boards
        deletedBoardIDs = snapshot.effectiveDeletedBoardIDs
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
        let selectedID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
        let hasSelectionChange = selectedID != selectedBoardID

        guard hasNewerBoard || hasBoardMembershipChange || hasSelectionChange else { return nil }

        namedBoards = snapshot.boards
        deletedBoardIDs = snapshot.effectiveDeletedBoardIDs
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
        selectedBoardID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
        refreshActiveBoardMirrorPersistenceRetryRequirement()
        return selectedBoard
    }

    @discardableResult
    func persistSnapshot(reloadWidgets: Bool = true) -> Bool {
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: namedBoards,
            deletedBoardIDs: deletedBoardIDs
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
        commitNamedBoardsSnapshot(
            activeMirror: activeMirror,
            persistNamedBoardsSnapshot: shouldPersistNamedBoards,
            requireNamedBoardsPersistenceBeforeActiveMirror: false
        )
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
        var nextSelectedID = selectedBoardID
        if selectedBoardID == boardID {
            let fallbackIndex = removeIndex == 0 ? 1 : removeIndex - 1
            nextSelectedID = namedBoards.indices.contains(fallbackIndex) ? namedBoards[fallbackIndex].id : nil
        }

        namedBoards.remove(at: removeIndex)
        deletedBoardIDs.insert(boardID)

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
                deletedBoardIDs: rollbackDeletedBoardIDs
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
           let firstBoardID = namedBoards.first?.id,
           boardID == firstBoardID {
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
        guard !requiresNamedBoardsPersistenceRetry else {
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

        snapshot.boards[targetIndex].board = currentBoard
        snapshot.boards[targetIndex].countdownEndsAt = repository.loadBoardCountdownEndsAt()
        snapshot.boards[targetIndex].updatedAt = currentBoardSavedAt
        saveNamedBoardsSnapshotIfChanged(snapshot, reloadWidgets: true)
        return snapshot
    }

    private func snapshotByApplyingPendingWidgetTaskEvent(
        _ snapshot: BingoBoardStore.NamedBoardsSnapshot
    ) -> BingoBoardStore.NamedBoardsSnapshot {
        guard let event = repository.loadWidgetTaskSyncEvent() else {
            return snapshot
        }

        let updatedSnapshot = WidgetTaskEventMerge.applying(event, to: snapshot)
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
            requiresNamedBoardsPersistenceRetry
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
        let didSave = repository.saveNamedBoardsSnapshot(snapshot, reloadWidgets: reloadWidgets)
        requiresNamedBoardsPersistenceRetry = !didSave &&
            repository.loadNamedBoardsSnapshot() != snapshot
        return didSave
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
        deletedBoardIDs: Set<UUID>? = nil
    ) {
        namedBoards = boards
        self.selectedBoardID = selectedBoardID
        if let deletedBoardIDs {
            self.deletedBoardIDs = deletedBoardIDs
        }
        let restoredSnapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: boards,
            deletedBoardIDs: self.deletedBoardIDs
        )
        requiresNamedBoardsPersistenceRetry =
            repository.loadNamedBoardsSnapshot() != restoredSnapshot
        refreshActiveBoardMirrorPersistenceRetryRequirement()
    }
}
