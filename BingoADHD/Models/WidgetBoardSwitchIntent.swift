import Foundation
import AppIntents
import WidgetKit

protocol WidgetBoardSelectionRepository: BoardStateCommitRepository, WidgetPanelSelectionRepository {
    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot
    @discardableResult
    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool
}

enum WidgetBoardSelectionService {
    @discardableResult
    static func selectBoard(
        _ boardID: UUID,
        repository: any WidgetBoardSelectionRepository
    ) -> BoardStateCommitResult? {
        var snapshot = repository.loadNamedBoardsSnapshot()
        guard let selectedBoard = snapshot.boards.first(where: { $0.id == boardID }) else {
            return nil
        }

        var savedNamedBoards = false
        if snapshot.selectedBoardID != boardID {
            snapshot.selectedBoardID = boardID
            savedNamedBoards = repository.saveNamedBoardsSnapshot(snapshot, reloadWidgets: false)
            guard savedNamedBoards else { return nil }
        }

        var result = BoardStateCommitter.saveActiveBoardState(
            board: selectedBoard.board,
            countdownEndsAt: selectedBoard.countdownEndsAt,
            savedAt: selectedBoard.updatedAt,
            associatedBoardID: selectedBoard.id,
            repository: repository,
            widgetPanelRepository: repository,
            selectedWidgetPanelID: selectedBoard.id,
            reloadWidgets: false
        )
        result.savedNamedBoards = savedNamedBoards
        return result
    }
}

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

        guard WidgetBoardSelectionService.selectBoard(
            nextPanelID,
            repository: repository
        ) != nil else { return .result() }

        // Interactive widget intents receive a guaranteed timeline refresh after
        // perform() returns. Avoid requesting another full reload here because two
        // consecutive timeline replacements make the entire widget flash.

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

    // On iOS 26 and later, keep the interaction in the containing app's background process.
    // The app stays off-screen while the shared local transaction completes.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

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
        guard let id = UUID(uuidString: boardID) else {
            return .result()
        }

        let committed = ExternalBoardTaskMutationService.apply(
            boardID: id, target: .position(row: row, col: col), selectBoard: true
        )
        guard committed else { return .result() }
        BingoBoardStore.reloadBoardWidgetTimeline()
        if NativeICloudPreferences.isEnabled {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .externalBoardTaskDidChange, object: nil)
        }
        await BingoBoardLiveActivityController.refresh()
        return .result()
    }
}

// iOS 17–25 use this conformance to execute an interactive-widget intent in the containing
// app's background process. It does not foreground or visibly open the app. The protocol is
// unavailable to the widget-extension slice by design; both targets still share the AppIntent.
@available(iOS, introduced: 16.4, deprecated: 26.0)
@available(iOSApplicationExtension, unavailable)
extension ToggleWidgetTaskIntent: ForegroundContinuableIntent {}

final class WidgetIntentBoardRepository: WidgetBoardSelectionRepository {
    private var persistenceBaseline: BingoBoardStore.NamedBoardsSnapshot?

    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot {
        let snapshot = BingoBoardStore.loadNamedBoardsSnapshot()
        persistenceBaseline = snapshot
        return snapshot
    }

    @discardableResult
    func saveNamedBoardsSnapshot(_ snapshot: BingoBoardStore.NamedBoardsSnapshot, reloadWidgets: Bool) -> Bool {
        guard let persistenceBaseline else { return false }
        let saved = BingoBoardStore.saveNamedBoardsSnapshot(snapshot, reloadWidgets: reloadWidgets, expectedSnapshot: persistenceBaseline)
        if saved { self.persistenceBaseline = snapshot }
        return saved
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
