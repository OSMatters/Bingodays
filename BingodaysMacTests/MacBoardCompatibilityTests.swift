import XCTest

final class MacBoardCompatibilityTests: XCTestCase {
    func testMobileBoardRoundTripPreservesHiddenCellsAndTaskRules() throws {
        var full = BoardEngine.createEmptyGrid(size: 5)
        full[4][4] = BingoCell(text: "每周运动", residentTaskText: "每周运动", recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [2, 4]), isForced: true)
        let board = SavedBoard(gridSize: 3, cells: Array(full.prefix(3)).map { Array($0.prefix(3)) }, completedLines: [], fullBoardCells: full)
        let restored = try JSONDecoder().decode(SavedBoard.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(restored, board)
        XCTAssertEqual(BoardEngine.expandedBoardCache(from: restored)[4][4].recurrenceRule?.weekdays, [2, 4])
        XCTAssertTrue(BoardEngine.expandedBoardCache(from: restored)[4][4].isForced)
    }

    func testBingoRequiresCompleteRowAndUpdatesWhenCompletionIsRemoved() {
        var cells = BoardEngine.createEmptyGrid(size: 3)
        for col in 0..<3 { cells[1][col] = BingoCell(text: "任务 \(col)", isCompleted: true) }
        XCTAssertEqual(BoardEngine.completedLines(in: cells, size: 3), [.row(1)])
        cells[1][1].isCompleted = false
        XCTAssertTrue(BoardEngine.completedLines(in: cells, size: 3).isEmpty)
    }

    func testScheduledTaskRemainsUnavailableBeforeStartTime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let cell = BingoCell(text: "按时开始", startVisibleAt: start, endVisibleAt: start.addingTimeInterval(3600))
        XCTAssertFalse(cell.isCurrentlyTappable(on: start.addingTimeInterval(-60)))
        XCTAssertTrue(cell.isCurrentlyTappable(on: start.addingTimeInterval(60)))
    }

    func testDailyResetPreservesRepeatingRuleAndRemovesCompletedOneTimeTask() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        var cells = BoardEngine.createEmptyGrid(size: 3)
        cells[0][0] = BingoCell(text: "喝水", residentTaskText: "喝水", recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: yesterday), isCompleted: true, lastCompletedAt: yesterday)
        cells[0][1] = BingoCell(text: "寄信", recurrenceRule: TaskRecurrenceRule(kind: .none), isCompleted: true, lastCompletedAt: yesterday)
        let saved = SavedBoard(gridSize: 3, cells: cells, completedLines: [], fullBoardCells: cells)
        let named = BingoBoardStore.NamedBoard(name: "测试", board: saved, lastTaskResetAppliedAt: yesterday, updatedAt: yesterday)
        let reset = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(named, now: today)
        let result = BoardEngine.expandedBoardCache(from: reset.board)
        XCTAssertFalse(result[0][0].isCompleted)
        XCTAssertEqual(result[0][0].effectiveRecurrenceRule?.kind, .daily)
        XCTAssertFalse(result[0][1].hasStoredTask)
    }

    func testEditingRecurringTaskNameKeepsWeeklyRuleAndRemovesUnsupportedTimeWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rule = TaskRecurrenceRule(kind: .weekly, weekdays: [2, 4])
        let previous = BingoCell(text: "运动", residentTaskText: "运动", recurrenceRule: rule)
        let result = TaskEditRuleEngine.apply(TaskEditRuleInput(previousCell: previous, text: "散步", isForced: false, residentWeekdays: [2, 4], isOneTimeTask: false, recurrenceRule: rule, estimatedDurationMinutes: nil, startVisibleAt: now, endVisibleAt: now.addingTimeInterval(3600), startReminderEnabled: false, startReminderOffsetMinutes: 5, referenceDate: now, calendar: .current, maxTaskLength: 20, maxCountdownMinutes: 1440))
        XCTAssertEqual(result.cell.storedTaskText, "散步")
        XCTAssertEqual(result.cell.effectiveRecurrenceRule?.weekdays, [2, 4])
        XCTAssertNil(result.cell.startVisibleAt)
        XCTAssertNil(result.cell.endVisibleAt)
    }

    func testCloudModelBuildsOnMacWithoutIOSFileProtectionOption() throws {
        let controller = try NativeICloudPersistenceController(mode: .inMemory)
        XCTAssertNotNil(controller.container.managedObjectModel.entitiesByName[NativeCloudStateEnvelope.entityName])
    }
}
