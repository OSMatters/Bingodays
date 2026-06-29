import Foundation
import AppIntents
import WidgetKit

struct SwitchBoardIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Board"
    static var description = IntentDescription("Switches the current board shown in the large widget.")
    static var openAppWhenRun = false

    @Parameter(title: "Step")
    var step: Int

    init() {
        step = 1
    }

    init(step: Int) {
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        let repository = WidgetIntentBoardRepository()
        let snapshot = repository.loadNamedBoardsSnapshot()
        guard snapshot.boards.count > 1 else {
            return .result()
        }

        let preferredPanelID = repository.loadSelectedWidgetPanelID() ?? snapshot.selectedBoardID
        let currentIndex = snapshot.boards.firstIndex(where: { $0.id == preferredPanelID }) ?? 0
        let nextIndex = wrappedIndex(currentIndex + step, count: snapshot.boards.count)
        let nextPanelID = snapshot.boards[nextIndex].id

        guard repository.loadSelectedWidgetPanelID() != nextPanelID else {
            return .result()
        }

        repository.saveSelectedWidgetPanelID(nextPanelID)
        var result = BoardStateCommitResult(savedSelectedWidgetPanel: true)
        BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)

        return .result()
    }

    private func wrappedIndex(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let remainder = value % count
        return remainder >= 0 ? remainder : remainder + count
    }
}

struct ToggleWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Task"
    static var description = IntentDescription("Marks a widget task complete or incomplete.")
    static var openAppWhenRun = false

    @Parameter(title: "Board ID")
    var boardID: String

    @Parameter(title: "Row")
    var row: Int

    @Parameter(title: "Column")
    var col: Int

    init() {
        boardID = ""
        row = 0
        col = 0
    }

    init(boardID: String, row: Int, col: Int) {
        self.boardID = boardID
        self.row = row
        self.col = col
    }

    func perform() async throws -> some IntentResult {
        let repository = WidgetIntentBoardRepository()
        guard let id = UUID(uuidString: boardID) else {
            return .result()
        }

        var snapshot = repository.loadNamedBoardsSnapshot()
        let originalSnapshot = snapshot
        guard let index = snapshot.boards.firstIndex(where: { $0.id == id }) else {
            return .result()
        }

        guard let updatedBoard = WidgetTaskToggleService.toggled(
            board: snapshot.boards[index],
            row: row,
            col: col,
            now: .now
        ) else {
            return .result()
        }

        snapshot.boards[index] = updatedBoard
        snapshot.selectedBoardID = id
        WidgetTaskSyncStore.save(board: updatedBoard)
        let savedNamedBoards = snapshot != originalSnapshot
            ? repository.saveNamedBoardsSnapshot(snapshot, reloadWidgets: false)
            : false

        var result = BoardStateCommitter.saveActiveBoardState(
            board: updatedBoard.board,
            countdownEndsAt: updatedBoard.countdownEndsAt,
            savedAt: updatedBoard.updatedAt,
            associatedBoardID: id,
            repository: repository,
            widgetPanelRepository: repository,
            selectedWidgetPanelID: id,
            reloadWidgets: false
        )
        result.savedNamedBoards = savedNamedBoards
        BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)

        return .result()
    }
}

private struct WidgetIntentBoardRepository: BoardStateCommitRepository, WidgetPanelSelectionRepository {
    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot {
        BingoBoardStore.loadNamedBoardsSnapshot()
    }

    @discardableResult
    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool {
        BingoBoardStore.saveNamedBoardsSnapshot(snapshot, reloadWidgets: reloadWidgets)
    }

    func loadBoard() -> SavedBoard? {
        BingoBoardStore.loadBoard()
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
