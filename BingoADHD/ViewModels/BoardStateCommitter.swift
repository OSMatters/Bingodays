import Foundation

struct BoardStateCommitResult: Equatable {
    var savedBoard = false
    var savedBoardCountdown = false
    var savedNamedBoards = false
    var savedSelectedWidgetPanel = false
    var reloadedWidgets = false

    var didChangeWidgetInputs: Bool {
        savedBoard || savedBoardCountdown || savedNamedBoards || savedSelectedWidgetPanel
    }
}

protocol BoardStateCommitRepository {
    func loadBoard() -> SavedBoard?
    func loadBoardCountdownEndsAt() -> Date?
    func loadActiveNamedBoardID() -> UUID?

    @discardableResult
    func saveBoard(_ board: SavedBoard, savedAt: Date, associatedBoardID: UUID?, reloadWidgets: Bool) -> Bool
    func saveBoardCountdownEndsAt(_ endsAt: Date?)
    func reloadWidgetTimelines()
}

protocol WidgetPanelSelectionRepository {
    func loadSelectedWidgetPanelID() -> UUID?
    func saveSelectedWidgetPanelID(_ boardID: UUID?)
}

enum BoardStateCommitter {
    @discardableResult
    static func saveActiveBoardState(
        board: SavedBoard,
        countdownEndsAt: Date?,
        savedAt: Date,
        associatedBoardID: UUID?,
        repository: any BoardStateCommitRepository,
        widgetPanelRepository: (any WidgetPanelSelectionRepository)? = nil,
        selectedWidgetPanelID: UUID? = nil,
        reloadWidgets: Bool
    ) -> BoardStateCommitResult {
        var result = BoardStateCommitResult()
        let existingBoard = repository.loadBoard()
        let existingAssociatedBoardID = repository.loadActiveNamedBoardID()
        if existingBoard != board || existingAssociatedBoardID != associatedBoardID {
            result.savedBoard = repository.saveBoard(
                board,
                savedAt: savedAt,
                associatedBoardID: associatedBoardID,
                reloadWidgets: false
            )
        }

        if repository.loadBoardCountdownEndsAt() != countdownEndsAt {
            repository.saveBoardCountdownEndsAt(countdownEndsAt)
            result.savedBoardCountdown = true
        }

        if let widgetPanelRepository {
            if widgetPanelRepository.loadSelectedWidgetPanelID() != selectedWidgetPanelID {
                widgetPanelRepository.saveSelectedWidgetPanelID(selectedWidgetPanelID)
                result.savedSelectedWidgetPanel = true
            }
        }

        if reloadWidgets {
            reloadWidgetsIfNeeded(&result, repository: repository)
        }

        return result
    }

    static func reloadWidgetsIfNeeded(
        _ result: inout BoardStateCommitResult,
        repository: any BoardStateCommitRepository
    ) {
        guard !result.reloadedWidgets, result.didChangeWidgetInputs else { return }
        repository.reloadWidgetTimelines()
        result.reloadedWidgets = true
    }
}
