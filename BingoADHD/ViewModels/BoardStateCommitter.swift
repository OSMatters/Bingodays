import Foundation

struct BoardStateCommitResult: Equatable {
    var savedBoard = false
    var savedBoardCountdown = false
    var savedSelectedWidgetPanel = false
    var reloadedWidgets = false
}

protocol BoardStateCommitRepository {
    @discardableResult
    func saveBoard(_ board: SavedBoard, savedAt: Date, associatedBoardID: UUID?, reloadWidgets: Bool) -> Bool
    func saveBoardCountdownEndsAt(_ endsAt: Date?)
    func reloadWidgetTimelines()
}

protocol WidgetPanelSelectionRepository {
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
        result.savedBoard = repository.saveBoard(
            board,
            savedAt: savedAt,
            associatedBoardID: associatedBoardID,
            reloadWidgets: false
        )
        repository.saveBoardCountdownEndsAt(countdownEndsAt)
        result.savedBoardCountdown = true

        if let widgetPanelRepository {
            widgetPanelRepository.saveSelectedWidgetPanelID(selectedWidgetPanelID)
            result.savedSelectedWidgetPanel = true
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
        guard result.savedBoard else { return }
        repository.reloadWidgetTimelines()
        result.reloadedWidgets = true
    }
}
