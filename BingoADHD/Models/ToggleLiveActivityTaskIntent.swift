import AppIntents
import Foundation

extension Notification.Name {
    static let externalBoardTaskDidChange = Notification.Name("externalBoardTaskDidChange")
}

struct ToggleLiveActivityTaskIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("Toggle Task", table: "LiveActivity")
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: LocalizedStringResource("Board ID", table: "LiveActivity")) var boardID: String
    @Parameter(title: LocalizedStringResource("Cell ID", table: "LiveActivity")) var cellID: String
    @Parameter(title: LocalizedStringResource("Completed", table: "LiveActivity")) var completed: Bool
    @Parameter(title: LocalizedStringResource("Version", table: "LiveActivity")) var version: String

    init() {
        boardID = ""
        cellID = ""
        completed = false
        version = ""
    }

    init(boardID: UUID, cell: BingoBoardActivitySnapshot.Cell) {
        self.boardID = boardID.uuidString
        cellID = cell.id.uuidString
        completed = !cell.completed
        version = cell.version
    }

    func perform() async throws -> some IntentResult {
        guard let boardID = UUID(uuidString: boardID), let cellID = UUID(uuidString: cellID) else {
            return .result()
        }
        let committed = ExternalBoardTaskMutationService.apply(
            boardID: boardID,
            target: .cell(id: cellID, completed: completed, version: version),
            selectBoard: false
        )
        if committed {
            BingoBoardStore.reloadWidgetTimelines()
            if NativeICloudPreferences.isEnabled {
                NativeICloudLocalChangeReporter.primaryStateDidChange()
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .externalBoardTaskDidChange, object: nil)
            }
        }
        // Also refresh rejected stale taps, so the user gets the current board.
        await BingoBoardLiveActivityController.refresh()
        return .result()
    }
}
