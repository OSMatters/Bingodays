import XCTest

final class MacCompletionPersistenceTests: XCTestCase {
    @MainActor
    func testCompletingAndUndoingTaskPersistsBoardHistoryAndPoints() throws {
        let now = Date()
        var cells = BoardEngine.createEmptyGrid(size: 3)
        cells[0][0] = BingoCell(text: "读一页书")
        let board = SavedBoard(gridSize: 3, cells: cells, completedLines: [], fullBoardCells: cells)
        let boards = InMemoryBingoBoardRepository(board: board, savedAt: now)
        let diary = InMemoryBingoDiaryRepository()
        let points = InMemoryBingoPointsRepository(totalPoints: 0, lifetimePoints: 0)
        let history = InMemoryTaskCompletionHistoryRepository()
        let transactions = InMemoryBingoPersistenceTransactionRepository()
        let model = BingoViewModel(persistenceDependencies: BingoViewModelPersistenceDependencies(boardRepository: boards, diaryRepository: diary, pointsRepository: points, completionHistoryRepository: history, transactionRepository: transactions))
        let initialPoints = model.totalPoints
        model.toggleComplete(row: 0, col: 0, referenceDate: now)
        XCTAssertTrue(model.cells[0][0].isCompleted)
        XCTAssertTrue(try XCTUnwrap(boards.board).cells[0][0].isCompleted)
        XCTAssertGreaterThan(model.totalPoints, initialPoints)
        XCTAssertFalse(diary.loadAllEntriesDictionary().isEmpty)
        XCTAssertFalse(history.loadCompletionHistory().isEmpty)
        XCTAssertNil(transactions.loadPendingTransaction())

        model.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(1))
        XCTAssertFalse(model.cells[0][0].isCompleted)
        XCTAssertFalse(try XCTUnwrap(boards.board).cells[0][0].isCompleted)
        XCTAssertEqual(model.totalPoints, initialPoints)
        XCTAssertNil(transactions.loadPendingTransaction())
    }

    @MainActor
    func testFailedTaskEditLeavesOriginalTaskAndRecurringRuleIntact() {
        let now = Date()
        var cells = BoardEngine.createEmptyGrid(size: 3)
        cells[0][0] = BingoCell(text: "散步", residentTaskText: "散步", recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [2, 4]))
        let original = SavedBoard(gridSize: 3, cells: cells, completedLines: [], fullBoardCells: cells)
        let boards = InMemoryBingoBoardRepository(board: original, savedAt: now)
        let model = BingoViewModel(persistenceDependencies: BingoViewModelPersistenceDependencies(boardRepository: boards, diaryRepository: InMemoryBingoDiaryRepository(), pointsRepository: InMemoryBingoPointsRepository(), completionHistoryRepository: InMemoryTaskCompletionHistoryRepository(), transactionRepository: InMemoryBingoPersistenceTransactionRepository()))
        boards.shouldFailBoardSave = true
        XCTAssertFalse(model.updateTask(row: 0, col: 0, text: "跑步", isForced: false, residentWeekdays: [2, 4], recurrenceRule: cells[0][0].recurrenceRule))
        XCTAssertEqual(boards.board?.cells[0][0].storedTaskText, "散步")
        XCTAssertEqual(boards.board?.cells[0][0].effectiveRecurrenceRule?.weekdays, [2, 4])
    }
}
