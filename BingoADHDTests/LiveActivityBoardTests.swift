import ActivityKit
import Testing
import UIKit
@testable import Bingodays

@Suite(.serialized)
@MainActor
struct LiveActivityBoardTests {
    @Test
    func progressExcludesEmptyTasksAndSupportsUndo() {
        func cell(_ text: String, completed: Bool) -> BingoBoardActivitySnapshot.Cell {
            .init(id: UUID(), text: text, version: "", completed: completed, inBingo: false, enabled: true)
        }
        let snapshot = BingoBoardActivitySnapshot(gridSize: 2, theme: "", cells: [
            cell("喝水", completed: true), cell("閱讀", completed: false),
            cell("", completed: true), cell(" \n", completed: false)
        ])
        #expect(snapshot.taskCount == 2)
        #expect(snapshot.completedTaskCount == 1)
        #expect(snapshot.completionProgress == 0.5)
        #expect(snapshot.completionPercentage == 50)
        let empty = BingoBoardActivitySnapshot(gridSize: 2, theme: "", cells: [])
        #expect(empty.completionProgress == 0)
        #expect(empty.completionPercentage == 0)
        let undone = BingoBoardActivitySnapshot(gridSize: 2, theme: "", cells: [cell("喝水", completed: false)])
        #expect(undone.completionProgress == 0)
        let complete = BingoBoardActivitySnapshot(gridSize: 2, theme: "", cells: [cell("喝水", completed: true)])
        #expect(complete.completionProgress == 1)
        #expect(complete.completionPercentage == 100)
    }

    @Test(arguments: [2, 3, 4, 5])
    func fullTextPayloadRoundTrips(size: Int) throws {
        let now = Date()
        var board = makeBoard(size: size, now: now)
        let text = "喝水整理房間閱讀寫日記出門運動洗衣服休息"
        var cells = board.board.cells
        for row in 0..<size {
            for col in 0..<size {
                cells[row][col].text = String(text.prefix(AppSettings.maxTaskLength))
            }
        }
        board.board = SavedBoard(gridSize: size, cells: cells, completedLines: [])
        let snapshot = BingoBoardActivitySnapshotBuilder.make(board: board, now: now)
        let content = try BingoBoardLiveActivityController.content(for: board, now: now)
        #expect(content.state.snapshot == snapshot)
        #expect(snapshot.cells.allSatisfy { $0.text == String(text.prefix(AppSettings.maxTaskLength)) })
        let encoder = JSONEncoder()
        #expect(try encoder.encode(content.state).count + encoder.encode(BingoBoardActivityAttributes(boardID: board.id)).count < 4_096)
    }

    @Test
    func diverseEmojiPayloadPreservesEveryCharacter() throws {
        let now = Date()
        var board = makeBoard(size: 5, now: now)
        let emoji = ["👨‍👩‍👧‍👦", "👍🏽", "🏳️‍🌈", "🧑🏾‍💻", "🇹🇼"]
        var cells = board.board.cells
        for row in 0..<5 {
            for col in 0..<5 {
                cells[row][col].text = String(repeating: emoji[(row + col) % emoji.count], count: 20)
            }
        }
        board.board = SavedBoard(gridSize: 5, cells: cells, completedLines: [])
        let content = try BingoBoardLiveActivityController.content(for: board, now: now)
        #expect(content.state.snapshot?.cells.map(\.text) == board.board.cells.flatMap { $0 }.map(\.text))
    }

    @Test(arguments: ["一二三四五六七八九十一二三四五六七八九十", "ABCDEFGHIJKLMNOPQRST", "一\n二\n三\n四\n五\n六\n七\n八\n九\n十", "👨‍👩‍👧‍👦👍🏽🏳️‍🌈🧑🏾‍💻🇹🇼"])
    func denseCellTextFitsWithoutTruncation(text: String) {
        let size = CGSize(width: 54, height: 18)
        let font = BingoBoardTextFitter.fontSize(for: text, in: size, maximum: 15)
        #expect(BingoBoardTextFitter.fits(text, fontSize: font, in: size))
    }

    @Test
    func completeUndoAndDuplicateKeepPointsAndSelectionConsistent() throws {
        try withPersistence { now in
            let active = makeBoard(size: 3, now: now)
            let displayed = makeBoard(size: 3, now: now)
            try save(boards: [active, displayed], selected: active.id)
            WidgetPanelSelectionStore.saveSelectedPanelID(active.id)
            let cell = displayed.board.cells[0][0]
            let command = ExternalBoardTaskMutationService.Target.cell(
                id: cell.id, completed: true,
                version: BingoBoardActivitySnapshotBuilder.version(cell: cell, board: displayed, now: now)
            )
            #expect(ExternalBoardTaskMutationService.apply(boardID: displayed.id, target: command, selectBoard: false, now: now))
            #expect(PointsStore.loadTotalPoints() == 1)
            #expect(!ExternalBoardTaskMutationService.apply(boardID: displayed.id, target: command, selectBoard: false, now: now))
            #expect(PointsStore.loadTotalPoints() == 1)
            let snapshot = BingoBoardStore.loadNamedBoardsSnapshot()
            #expect(snapshot.selectedBoardID == active.id)
            #expect(BingoBoardStore.loadActiveNamedBoardID() == active.id)
            #expect(WidgetPanelSelectionStore.loadSelectedPanelID() == active.id)
            let updated = try #require(snapshot.boards.first { $0.id == displayed.id })
            let updatedCell = try #require(updated.board.fullBoardCells?[0][0])
            #expect(updatedCell.isCompleted)
            let undo = ExternalBoardTaskMutationService.Target.cell(
                id: cell.id, completed: false,
                version: BingoBoardActivitySnapshotBuilder.version(cell: updatedCell, board: updated, now: now)
            )
            #expect(ExternalBoardTaskMutationService.apply(boardID: displayed.id, target: undo, selectBoard: false, now: now))
            #expect(PointsStore.loadTotalPoints() == 0)
            #expect(WidgetTaskSyncStore.load() == nil)
            #expect(BingoBoardStore.loadNamedBoardsSnapshot().boards.first { $0.id == displayed.id }?.board.cells[0][0].isCompleted == false)
        }
    }

    @Test
    func staleTaskDefinitionCannotBeCompleted() throws {
        try withPersistence { now in
            var board = makeBoard(size: 3, now: now)
            let old = board.board.cells[0][0]
            let version = BingoBoardActivitySnapshotBuilder.version(cell: old, board: board, now: now)
            var cells = board.board.cells
            cells[0][0].text = "Replacement"
            board.board = SavedBoard(gridSize: 3, cells: cells, completedLines: [])
            try save(boards: [board], selected: board.id)
            #expect(!ExternalBoardTaskMutationService.apply(boardID: board.id, target: .cell(id: old.id, completed: true, version: version), selectBoard: false, now: now))
            #expect(PointsStore.loadTotalPoints() == 0)
            #expect(!BingoBoardStore.loadNamedBoardsSnapshot().boards[0].board.cells[0][0].isCompleted)
        }
    }

    @Test
    func cellIdentitySurvivesReordering() throws {
        try withPersistence { now in
            var board = makeBoard(size: 3, now: now)
            let cell = board.board.cells[0][0]
            let version = BingoBoardActivitySnapshotBuilder.version(cell: cell, board: board, now: now)
            var cells = board.board.cells
            cells[0].swapAt(0, 1)
            board.board = SavedBoard(gridSize: 3, cells: cells, completedLines: [])
            try save(boards: [board], selected: board.id)
            #expect(ExternalBoardTaskMutationService.apply(boardID: board.id, target: .cell(id: cell.id, completed: true, version: version), selectBoard: false, now: now))
            let saved = BingoBoardStore.loadNamedBoardsSnapshot().boards[0].board
            #expect(saved.cells[0][1].isCompleted)
            #expect(!saved.cells[0][0].isCompleted)
        }
    }

    @Test
    func projectedResetButtonRemainsValidUntilNextCycle() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        var board = makeBoard(size: 3, now: yesterday)
        board.taskResetMode = .resetStatusNextDay
        let snapshot = BingoBoardActivitySnapshotBuilder.make(board: board, now: now)
        let cell = snapshot.cells[0]
        let command = ExternalBoardTaskMutationService.Target.cell(id: cell.id, completed: true, version: cell.version)
        let later = now.addingTimeInterval(60)
        let prepared = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(board, now: later)
        #expect(command.position(in: prepared, now: later)?.row == 0)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: later)!
        let nextCycle = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(board, now: tomorrow)
        #expect(command.position(in: nextCycle, now: tomorrow) == nil)
    }

    @Test
    func desktopToggleStillSelectsItsBoard() throws {
        try withPersistence { now in
            let first = makeBoard(size: 3, now: now)
            let second = makeBoard(size: 3, now: now)
            try save(boards: [first, second], selected: first.id)
            #expect(ExternalBoardTaskMutationService.apply(boardID: second.id, target: .position(row: 0, col: 0), selectBoard: true, now: now))
            #expect(BingoBoardStore.loadNamedBoardsSnapshot().selectedBoardID == second.id)
            #expect(WidgetPanelSelectionStore.loadSelectedPanelID() == second.id)
            #expect(PointsStore.loadTotalPoints() == 1)
        }
    }

    @Test
    func completedLineRewardIsReversedByUndo() throws {
        try withPersistence { now in
            let board = makeBoard(size: 3, now: now)
            try save(boards: [board], selected: board.id)
            for col in 0..<3 {
                let current = BingoBoardStore.loadNamedBoardsSnapshot().boards[0]
                let cell = try #require(current.board.fullBoardCells?[0][col] ?? current.board.cells[0][col])
                #expect(ExternalBoardTaskMutationService.apply(
                    boardID: board.id,
                    target: .cell(id: cell.id, completed: true, version: BingoBoardActivitySnapshotBuilder.version(cell: cell, board: current, now: now)),
                    selectBoard: false, now: now
                ))
            }
            #expect(PointsStore.loadTotalPoints() == 8)
            let current = BingoBoardStore.loadNamedBoardsSnapshot().boards[0]
            let cell = try #require(current.board.fullBoardCells?[0][2])
            #expect(ExternalBoardTaskMutationService.apply(
                boardID: board.id,
                target: .cell(id: cell.id, completed: false, version: BingoBoardActivitySnapshotBuilder.version(cell: cell, board: current, now: now)),
                selectBoard: false, now: now
            ))
            #expect(PointsStore.loadTotalPoints() == 2)
        }
    }

    @Test
    func intentUpdatesLiveActivityAndSharedStores() async throws {
        try await withAsyncPersistence { now in
            #expect(ActivityAuthorizationInfo().areActivitiesEnabled)
            let board = makeBoard(size: 3, now: now)
            try save(boards: [board], selected: board.id)
            try await BingoBoardLiveActivityController.toggle(boardID: board.id)
            let activity = try #require(Activity<BingoBoardActivityAttributes>.activities.first { $0.attributes.boardID == board.id })
            do {
                let cell = try #require(activity.content.state.snapshot?.cells.first)
                _ = try await ToggleLiveActivityTaskIntent(boardID: board.id, cell: cell).perform()
                #expect(PointsStore.loadTotalPoints() == 1)
                #expect(activity.content.state.snapshot?.cells.first?.completed == true)
                #expect(BingoBoardStore.loadBoard()?.cells[0][0].isCompleted == true)
                let completed = try #require(activity.content.state.snapshot?.cells.first)
                _ = try await ToggleLiveActivityTaskIntent(boardID: board.id, cell: completed).perform()
                #expect(PointsStore.loadTotalPoints() == 0)
                #expect(activity.content.state.snapshot?.cells.first?.completed == false)
                #expect(BingoBoardStore.loadBoard()?.cells[0][0].isCompleted == false)
                await activity.end(nil, dismissalPolicy: .immediate)
            } catch {
                await activity.end(nil, dismissalPolicy: .immediate)
                throw error
            }
        }
    }

    private func makeBoard(size: Int, now: Date) -> BingoBoardStore.NamedBoard {
        var cells = BoardEngine.createEmptyGrid(size: size)
        for row in 0..<size {
            for col in 0..<size { cells[row][col].text = "Task \(row) \(col)" }
        }
        return .init(name: "Test", board: SavedBoard(gridSize: size, cells: cells, completedLines: []), taskResetMode: .keepTaskStatus, lastTaskResetAppliedAt: now, updatedAt: now)
    }

    private func save(boards: [BingoBoardStore.NamedBoard], selected: UUID) throws {
        #expect(BingoBoardStore.saveNamedBoardsSnapshot(.init(selectedBoardID: selected, boards: boards), reloadWidgets: false))
        let repository = WidgetIntentBoardRepository()
        _ = try #require(WidgetBoardSelectionService.selectBoard(selected, repository: repository))
    }

    private func withPersistence(_ body: (Date) throws -> Void) throws {
        let context = preparePersistence()
        defer { context.restore() }
        try body(context.now)
    }

    private func withAsyncPersistence(_ body: (Date) async throws -> Void) async throws {
        let context = preparePersistence()
        defer { context.restore() }
        try await body(context.now)
    }

    private func preparePersistence() -> (now: Date, restore: () -> Void) {
        let now = Date()
        let boards = BingoBoardStore.loadNamedBoardsSnapshot()
        let activeBoard = BingoBoardStore.loadBoard()
        let activeID = BingoBoardStore.loadActiveNamedBoardID()
        let countdown = BingoBoardStore.loadBoardCountdownEndsAt()
        let points = PointsStore.loadPersistenceSnapshot()
        let history = TaskCompletionHistoryStore.load()
        let diary = BingoDiaryStore.loadAllEntriesDictionary()
        let panel = WidgetPanelSelectionStore.loadSelectedPanelID()
        let restore = {
            WidgetTaskSyncStore.clear()
            _ = BingoBoardStore.saveNamedBoardsSnapshot(boards, reloadWidgets: false)
            if let activeBoard {
                _ = BingoBoardStore.saveBoard(activeBoard, savedAt: now, associatedBoardID: activeID, reloadWidgets: false)
            } else {
                BingoBoardStore.clearBoard(reloadWidgets: false)
                BingoBoardStore.saveActiveNamedBoardID(activeID)
            }
            BingoBoardStore.saveBoardCountdownEndsAt(countdown)
            WidgetPanelSelectionStore.saveSelectedPanelID(panel)
            _ = PointsStore.replacePersistenceSnapshot(points)
            _ = TaskCompletionHistoryStore.save(history)
            _ = BingoDiaryStore.replaceAllEntriesDictionary(diary)
        }
        WidgetTaskSyncStore.clear()
        #expect(BingoDiaryStore.replaceAllEntriesDictionary([:]))
        #expect(TaskCompletionHistoryStore.save([]))
        #expect(PointsStore.saveState(totalPoints: 0, lifetimePoints: 0, dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)))
        return (now, restore)
    }
}
