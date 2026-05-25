import Combine
import Foundation

@MainActor
final class BoardManagementStore: ObservableObject {
    static let boardNameMaxLength = 20

    @Published var namedBoards: [BingoBoardStore.NamedBoard] = []
    @Published var selectedBoardID: UUID?
    @Published var hasLoadedBoardSwitcherState = false

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
            BingoBoardStore.saveNamedBoardsSnapshot(snapshot)
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

    func persistSnapshot() {
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: namedBoards
        )
        BingoBoardStore.saveNamedBoardsSnapshot(snapshot)
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

    func persistBoardState(
        for boardID: UUID,
        board: SavedBoard,
        countdownEndsAt: Date?,
        save: Bool = true
    ) {
        guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else { return }
        namedBoards[boardIndex].board = board
        namedBoards[boardIndex].countdownEndsAt = countdownEndsAt
        namedBoards[boardIndex].updatedAt = .now
        if save {
            persistSnapshot()
        }
    }

    func syncSelectedBoard(
        board: SavedBoard,
        countdownEndsAt: Date?
    ) {
        guard hasLoadedBoardSwitcherState, let selectedBoardID else { return }
        persistBoardState(
            for: selectedBoardID,
            board: board,
            countdownEndsAt: countdownEndsAt
        )
    }

    func selectBoard(
        _ boardID: UUID,
        currentBoard: SavedBoard,
        currentCountdownEndsAt: Date?
    ) -> BingoBoardStore.NamedBoard? {
        guard selectedBoardID != boardID else { return selectedBoard }

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
        persistSnapshot()
        return selected
    }

    func createBoard(
        nameDraft: String,
        currentBoard: SavedBoard?,
        currentCountdownEndsAt: Date?
    ) -> BingoBoardStore.NamedBoard {
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
        persistSnapshot()
        return newBoard
    }

    func deleteBoard(
        _ boardID: UUID,
        allowsDeletingFirstBoard: Bool
    ) -> BingoBoardStore.NamedBoard? {
        guard canDeleteBoard(boardID, allowsDeletingFirstBoard: allowsDeletingFirstBoard),
              let removeIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else {
            return selectedBoard
        }

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

        persistSnapshot()
        return selectedBoard
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

    func renameBoard(_ boardID: UUID, nameDraft: String) {
        guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else { return }
        let fallbackName = L10n.boardDefaultName(boardIndex + 1)
        namedBoards[boardIndex].name = Self.sanitizedBoardName(nameDraft, fallback: fallbackName)
        namedBoards[boardIndex].updatedAt = .now
        persistSnapshot()
    }

    func importTemplateAsNewBoard(
        nameDraft: String,
        savedBoard: SavedBoard,
        currentBoard: SavedBoard?,
        currentCountdownEndsAt: Date?
    ) -> BingoBoardStore.NamedBoard {
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
        persistSnapshot()
        return importedBoard
    }

    func replaceSelectedBoardWithTemplate(
        nameDraft: String,
        savedBoard: SavedBoard
    ) -> BingoBoardStore.NamedBoard? {
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
        persistSnapshot()
        return namedBoards[boardIndex]
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
        var snapshot = BingoBoardStore.loadNamedBoardsSnapshot()
        snapshot = snapshotByApplyingPendingWidgetTaskEvent(snapshot)
        guard !snapshot.boards.isEmpty,
              let currentBoard = BingoBoardStore.loadBoard(),
              let currentBoardSavedAt = BingoBoardStore.loadBoardLastSavedAt() else {
            return snapshot
        }

        let selectedID = snapshot.selectedBoardID ?? snapshot.boards.first?.id
        guard let selectedID,
              let selectedIndex = snapshot.boards.firstIndex(where: { $0.id == selectedID }),
              currentBoardSavedAt > snapshot.boards[selectedIndex].updatedAt else {
            return snapshot
        }

        snapshot.boards[selectedIndex].board = currentBoard
        snapshot.boards[selectedIndex].countdownEndsAt = BingoBoardStore.loadBoardCountdownEndsAt()
        snapshot.boards[selectedIndex].updatedAt = currentBoardSavedAt
        snapshot.selectedBoardID = selectedID
        BingoBoardStore.saveNamedBoardsSnapshot(snapshot)
        return snapshot
    }

    private func snapshotByApplyingPendingWidgetTaskEvent(
        _ snapshot: BingoBoardStore.NamedBoardsSnapshot
    ) -> BingoBoardStore.NamedBoardsSnapshot {
        guard let event = WidgetTaskSyncStore.load() else {
            return snapshot
        }
        defer {
            WidgetTaskSyncStore.clear()
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
        BingoBoardStore.saveNamedBoardsSnapshot(updatedSnapshot)
        BingoBoardStore.saveBoard(event.board.board, savedAt: event.savedAt)
        BingoBoardStore.saveBoardCountdownEndsAt(event.board.countdownEndsAt)
        WidgetPanelSelectionStore.saveSelectedPanelID(event.boardID)
        return updatedSnapshot
    }
}
