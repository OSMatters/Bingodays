import Combine
import Foundation

protocol BoardManagementRepository: BoardStateCommitRepository, WidgetPanelSelectionRepository {
    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot
    @discardableResult
    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool
    func loadBoardLastSavedAt() -> Date?

    func loadWidgetTaskSyncEvent() -> WidgetTaskSyncStore.Event?
    func clearWidgetTaskSyncEvent()
}

struct BoardManagementMutationResult: Equatable {
    let selectedBoard: BingoBoardStore.NamedBoard
    let didChangeSelection: Bool
    let commitResult: BoardStateCommitResult
    let shouldInvalidateCountdownTickSchedule: Bool
    let shouldSyncTaskReminders: Bool
}

struct LiveBoardManagementRepository: BoardManagementRepository {
    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot {
        BingoBoardStore.loadNamedBoardsSnapshot()
    }

    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool {
        BingoBoardStore.saveNamedBoardsSnapshot(snapshot, reloadWidgets: reloadWidgets)
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

    func loadWidgetTaskSyncEvent() -> WidgetTaskSyncStore.Event? {
        WidgetTaskSyncStore.load()
    }

    func clearWidgetTaskSyncEvent() {
        WidgetTaskSyncStore.clear()
    }

    func loadSelectedWidgetPanelID() -> UUID? {
        WidgetPanelSelectionStore.loadSelectedPanelID()
    }

    func saveSelectedWidgetPanelID(_ boardID: UUID?) {
        WidgetPanelSelectionStore.saveSelectedPanelID(boardID)
    }

    func reloadWidgetTimelines() {
        BingoBoardStore.reloadWidgetTimelines()
    }
}

@MainActor
final class BoardManagementStore: ObservableObject {
    static let boardNameMaxLength = 20

    @Published var namedBoards: [BingoBoardStore.NamedBoard] = []
    @Published var selectedBoardID: UUID?
    @Published var hasLoadedBoardSwitcherState = false

    private let repository: any BoardManagementRepository

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
                boards: [initialBoard]
            )
            saveNamedBoardsSnapshotIfChanged(snapshot, reloadWidgets: true)
        }

        namedBoards = snapshot.boards
        selectedBoardID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
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
        let selectedID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
        let hasSelectionChange = selectedID != selectedBoardID

        guard hasNewerBoard || hasSelectionChange else { return nil }

        namedBoards = snapshot.boards
        selectedBoardID = selectedID
        return selectedBoard
    }

    func reloadPersistedSnapshot() -> BingoBoardStore.NamedBoard? {
        guard hasLoadedBoardSwitcherState else { return nil }

        let snapshot = persistedSnapshotPreferringCurrentBoard()
        guard !snapshot.boards.isEmpty else { return nil }

        namedBoards = snapshot.boards
        selectedBoardID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
        return selectedBoard
    }

    @discardableResult
    func persistSnapshot(reloadWidgets: Bool = true) -> Bool {
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: namedBoards
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
        guard namedBoards[boardIndex].board != board ||
                namedBoards[boardIndex].countdownEndsAt != countdownEndsAt else {
            return false
        }

        namedBoards[boardIndex].board = board
        namedBoards[boardIndex].countdownEndsAt = countdownEndsAt
        namedBoards[boardIndex].updatedAt = .now
        if save {
            let shouldMirrorActiveBoard = selectedBoardID == boardID
            let activeMirror = shouldMirrorActiveBoard ? namedBoards[boardIndex] : nil
            commitNamedBoardsSnapshot(activeMirror: activeMirror)
        }
        return true
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

        selectedBoardID = boardID
        let selected = selectedBoard
        guard let selected else { return nil }
        let commitResult = commitNamedBoardsSnapshot(activeMirror: selected)
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
    ) -> BoardManagementMutationResult {
        if let selectedBoardID, let currentBoard {
            persistBoardState(
                for: selectedBoardID,
                board: currentBoard,
                countdownEndsAt: currentCountdownEndsAt,
                save: false
            )
        }

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
        var nextSelectedID = selectedBoardID
        if selectedBoardID == boardID {
            let fallbackIndex = removeIndex == 0 ? 1 : removeIndex - 1
            nextSelectedID = namedBoards.indices.contains(fallbackIndex) ? namedBoards[fallbackIndex].id : nil
        }

        namedBoards.remove(at: removeIndex)

        if let nextSelectedID,
           namedBoards.contains(where: { $0.id == nextSelectedID }) {
            selectedBoardID = nextSelectedID
        } else {
            selectedBoardID = namedBoards.first?.id
        }

        guard let selectedAfterDelete = selectedBoard else { return nil }
        let commitResult = commitNamedBoardsSnapshot(activeMirror: selectedAfterDelete)
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

    @discardableResult
    func renameBoard(_ boardID: UUID, nameDraft: String) -> Bool {
        guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else { return false }
        let fallbackName = L10n.boardDefaultName(boardIndex + 1)
        let boardName = Self.sanitizedBoardName(nameDraft, fallback: fallbackName)
        guard namedBoards[boardIndex].name != boardName else { return false }

        namedBoards[boardIndex].name = boardName
        namedBoards[boardIndex].updatedAt = .now
        return persistSnapshot()
    }

    func importTemplateAsNewBoard(
        nameDraft: String,
        savedBoard: SavedBoard,
        currentBoard: SavedBoard?,
        currentCountdownEndsAt: Date?
    ) -> BoardManagementMutationResult {
        if let selectedBoardID, let currentBoard {
            persistBoardState(
                for: selectedBoardID,
                board: currentBoard,
                countdownEndsAt: currentCountdownEndsAt,
                save: false
            )
        }

        let fallbackName = L10n.boardDefaultName(namedBoards.count + 1)
        let boardName = Self.sanitizedBoardName(nameDraft, fallback: fallbackName)
        let importedBoard = BingoBoardStore.NamedBoard(
            name: boardName,
            board: savedBoard,
            countdownEndsAt: nil,
            updatedAt: .now
        )
        namedBoards.append(importedBoard)
        selectedBoardID = importedBoard.id
        let commitResult = commitNamedBoardsSnapshot(activeMirror: importedBoard)
        return BoardManagementMutationResult(
            selectedBoard: importedBoard,
            didChangeSelection: true,
            commitResult: commitResult,
            shouldInvalidateCountdownTickSchedule: true,
            shouldSyncTaskReminders: true
        )
    }

    func replaceSelectedBoardWithTemplate(
        nameDraft: String,
        savedBoard: SavedBoard
    ) -> BoardManagementMutationResult? {
        guard let targetBoardID = selectedBoardID ?? namedBoards.first?.id,
              let boardIndex = namedBoards.firstIndex(where: { $0.id == targetBoardID }) else {
            return nil
        }

        let fallbackName = L10n.boardDefaultName(namedBoards.count + 1)
        namedBoards[boardIndex].name = Self.sanitizedBoardName(nameDraft, fallback: fallbackName)
        namedBoards[boardIndex].board = savedBoard
        namedBoards[boardIndex].countdownEndsAt = nil
        namedBoards[boardIndex].updatedAt = .now
        selectedBoardID = targetBoardID
        let updatedBoard = namedBoards[boardIndex]
        let commitResult = commitNamedBoardsSnapshot(activeMirror: updatedBoard)
        return BoardManagementMutationResult(
            selectedBoard: updatedBoard,
            didChangeSelection: false,
            commitResult: commitResult,
            shouldInvalidateCountdownTickSchedule: true,
            shouldSyncTaskReminders: true
        )
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
        guard !snapshot.boards.isEmpty,
              let currentBoard = repository.loadBoard(),
              let currentBoardSavedAt = repository.loadBoardLastSavedAt() else {
            return snapshot
        }

        let activeMirrorBoardID = repository.loadActiveNamedBoardID()
        let targetIndex: Int?
        if let activeMirrorBoardID {
            targetIndex = snapshot.boards.firstIndex(where: { $0.id == activeMirrorBoardID })
        } else if snapshot.boards.count == 1 {
            targetIndex = snapshot.boards.startIndex
        } else {
            targetIndex = nil
        }

        guard let targetIndex,
              currentBoardSavedAt > snapshot.boards[targetIndex].updatedAt else {
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
        defer {
            repository.clearWidgetTaskSyncEvent()
        }

        var updatedSnapshot = snapshot
        if let boardIndex = updatedSnapshot.boards.firstIndex(where: { $0.id == event.boardID }) {
            guard event.savedAt >= updatedSnapshot.boards[boardIndex].updatedAt else {
                return snapshot
            }
            updatedSnapshot.boards[boardIndex] = event.board
        } else {
            updatedSnapshot.boards.append(event.board)
        }

        updatedSnapshot.selectedBoardID = event.boardID
        let savedNamedBoards = saveNamedBoardsSnapshotIfChanged(updatedSnapshot, reloadWidgets: false)
        var result = BoardStateCommitter.saveActiveBoardState(
            board: event.board.board,
            countdownEndsAt: event.board.countdownEndsAt,
            savedAt: event.savedAt,
            associatedBoardID: event.boardID,
            repository: repository,
            widgetPanelRepository: repository,
            selectedWidgetPanelID: event.boardID,
            reloadWidgets: false
        )
        result.savedNamedBoards = savedNamedBoards
        BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)
        return updatedSnapshot
    }

    @discardableResult
    private func commitNamedBoardsSnapshot(activeMirror: BingoBoardStore.NamedBoard?) -> BoardStateCommitResult {
        let savedNamedBoards = persistSnapshot(reloadWidgets: false)
        guard let activeMirror else {
            var result = BoardStateCommitResult(savedNamedBoards: savedNamedBoards)
            BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)
            return result
        }
        var result = persistActiveBoardMirror(
            boardID: activeMirror.id,
            board: activeMirror.board,
            countdownEndsAt: activeMirror.countdownEndsAt,
            savedAt: activeMirror.updatedAt
        )
        result.savedNamedBoards = savedNamedBoards
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
        repository.saveNamedBoardsSnapshot(snapshot, reloadWidgets: reloadWidgets)
    }
}
