import Combine
import XCTest
@testable import Bingodays

final class BoardResetRuleEngineTests: XCTestCase {
    func testNextDayResetClearsCompletedStateAndCountdowns() {
        let yesterday = makeDate(year: 2026, month: 5, day: 30, hour: 10)
        let today = makeDate(year: 2026, month: 5, day: 31, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Write plan",
            isCompleted: true,
            isForced: true,
            countdownEndsAt: today.addingTimeInterval(3600),
            countdownPausedRemainingSeconds: 1800,
            estimatedDurationMinutes: 45,
            completionStreakCount: 2,
            lastCompletedAt: yesterday
        )
        let board = makeNamedBoard(
            cells: cells,
            mode: .resetStatusNextDay,
            lastTaskResetAppliedAt: yesterday,
            updatedAt: yesterday
        )

        let updated = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(board, now: today, calendar: fixedCalendar)
        let updatedCell = updated.board.fullBoardCells?[0][0]

        XCTAssertEqual(updated.lastTaskResetAppliedAt, today)
        XCTAssertEqual(updated.updatedAt, today)
        XCTAssertEqual(updatedCell?.storedTaskText, "Write plan")
        XCTAssertEqual(updatedCell?.isCompleted, false)
        XCTAssertEqual(updatedCell?.isTaskHidden, false)
        XCTAssertNil(updatedCell?.countdownEndsAt)
        XCTAssertNil(updatedCell?.countdownPausedRemainingSeconds)
        XCTAssertNil(updatedCell?.estimatedDurationMinutes)
        XCTAssertEqual(updated.board.completedLines, [])
    }

    func testCustomResetWaitsUntilTriggerAndOnlyRunsOncePerTrigger() {
        let beforeTrigger = makeDate(year: 2026, month: 5, day: 31, hour: 7, minute: 59)
        let afterTrigger = makeDate(year: 2026, month: 5, day: 31, hour: 8, minute: 1)
        let afterApplied = makeDate(year: 2026, month: 5, day: 31, hour: 8, minute: 5)
        let yesterday = makeDate(year: 2026, month: 5, day: 30, hour: 10)
        let board = makeNamedBoard(
            mode: .resetStatusNextDay,
            customResetMinutes: 8 * 60,
            lastTaskResetAppliedAt: yesterday,
            updatedAt: yesterday
        )

        let beforeEvaluation = BoardResetRuleEngine.pendingResetEvaluation(for: board, now: beforeTrigger, calendar: fixedCalendar)
        XCTAssertFalse(beforeEvaluation.shouldApply)

        let afterEvaluation = BoardResetRuleEngine.pendingResetEvaluation(for: board, now: afterTrigger, calendar: fixedCalendar)
        XCTAssertTrue(afterEvaluation.shouldApply)
        XCTAssertTrue(afterEvaluation.customResetDue)

        var alreadyAppliedBoard = board
        alreadyAppliedBoard.lastTaskResetAppliedAt = afterApplied
        let alreadyAppliedEvaluation = BoardResetRuleEngine.pendingResetEvaluation(
            for: alreadyAppliedBoard,
            now: afterApplied,
            calendar: fixedCalendar
        )
        XCTAssertFalse(alreadyAppliedEvaluation.shouldApply)
    }

    func testCustomResetKeepsRecurringCompletionAcrossMidnightUntilTrigger() {
        let completedAt = makeDate(year: 2026, month: 5, day: 30, hour: 22)
        let previousReset = makeDate(year: 2026, month: 5, day: 30, hour: 3)
        let afterMidnight = makeDate(year: 2026, month: 5, day: 31, hour: 0, minute: 1)
        let afterTrigger = makeDate(year: 2026, month: 5, day: 31, hour: 3, minute: 1)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Drink water",
            residentTaskText: "Drink water",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: completedAt),
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: completedAt
        )
        var board = makeNamedBoard(
            cells: cells,
            mode: .resetStatusNextDay,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousReset,
            updatedAt: completedAt
        )
        board.countdownEndsAt = afterTrigger.addingTimeInterval(60 * 60)

        let midnightProjection = BoardEngine.projectVisibleCells(
            from: cells,
            size: 2,
            referenceDate: afterMidnight
        )
        XCTAssertTrue(midnightProjection[0][0].isCompleted)

        let beforeReset = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            board,
            now: afterMidnight,
            calendar: fixedCalendar
        )
        XCTAssertTrue(beforeReset.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertEqual(beforeReset.lastTaskResetAppliedAt, previousReset)
        XCTAssertNotNil(beforeReset.countdownEndsAt)

        let afterReset = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            board,
            now: afterTrigger,
            calendar: fixedCalendar
        )
        XCTAssertFalse(afterReset.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertEqual(afterReset.lastTaskResetAppliedAt, afterTrigger)
        XCTAssertNil(afterReset.countdownEndsAt)
    }

    func testNonActiveBoardResetDoesNotReportActiveBoardReset() {
        let now = makeDate(year: 2026, month: 5, day: 31, hour: 5, minute: 1)
        let yesterday = makeDate(year: 2026, month: 5, day: 30, hour: 5)
        var activeCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        activeCells[0][0] = BingoCell(text: "Active completed", isCompleted: true, lastCompletedAt: now)
        let activeBoard = makeNamedBoard(
            cells: activeCells,
            mode: .keepTaskStatus,
            lastTaskResetAppliedAt: yesterday,
            updatedAt: now
        )
        var inactiveCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        inactiveCells[0][0] = BingoCell(text: "Inactive completed", isCompleted: true, lastCompletedAt: yesterday)
        var inactiveBoard = makeNamedBoard(
            cells: inactiveCells,
            mode: .resetStatusNextDay,
            customResetMinutes: 5 * 60,
            lastTaskResetAppliedAt: yesterday,
            updatedAt: yesterday
        )
        inactiveBoard.countdownEndsAt = now.addingTimeInterval(60 * 60)
        var coordinator = BoardResetCoordinator(
            namedBoards: [activeBoard, inactiveBoard],
            selectedBoardID: activeBoard.id,
            lastEvaluationDateKey: PointsStore.dateKey(for: now, calendar: fixedCalendar),
            hasAppliedDebugSimulatedResetThisLaunch: true,
            lastCustomResetDebugToastKey: "",
            debugConfiguration: BoardResetDebugConfiguration(
                simulateNextDayReset: false,
                prepareStreakTest: false,
                showCustomResetToast: false
            )
        )

        let result = coordinator.evaluate(now: now, force: true, source: "test")

        XCTAssertTrue(result.didReset)
        XCTAssertFalse(result.didResetActiveBoard)
        XCTAssertTrue(coordinator.namedBoards[0].board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertFalse(coordinator.namedBoards[1].board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertNil(coordinator.namedBoards[1].countdownEndsAt)
    }

    func testCustomResetNormalizationRejectsNoOpAndKeepStatusValues() {
        XCTAssertNil(
            BoardResetRuleEngine.normalizedCustomResetMinutes(0, mode: .resetStatusNextDay)
        )
        XCTAssertNil(
            BoardResetRuleEngine.normalizedCustomResetMinutes(3 * 60, mode: .keepTaskStatus)
        )
        XCTAssertEqual(
            BoardResetRuleEngine.normalizedCustomResetMinutes(3 * 60, mode: .clearTasksNextDay),
            3 * 60
        )
    }

    func testKeepStatusDoesNotImplicitlyResetRecurringCompletionAtMidnight() {
        let completedAt = makeDate(year: 2026, month: 5, day: 30, hour: 22)
        let nextDay = makeDate(year: 2026, month: 5, day: 31, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Drink water",
            residentTaskText: "Drink water",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: completedAt),
            isCompleted: true,
            lastCompletedAt: completedAt
        )
        let board = makeNamedBoard(
            cells: cells,
            mode: .keepTaskStatus,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: completedAt,
            updatedAt: completedAt
        )

        let updated = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            board,
            now: nextDay,
            calendar: fixedCalendar
        )
        let projected = BoardEngine.projectVisibleCells(
            from: BoardEngine.expandedBoardCache(from: updated.board),
            size: 2,
            referenceDate: nextDay
        )

        XCTAssertTrue(projected[0][0].isCompleted)
        XCTAssertEqual(updated.lastTaskResetAppliedAt, completedAt)
    }

    func testNextScheduledResetUsesCustomTimeAndThenAdvancesOneDay() throws {
        let beforeTrigger = makeDate(year: 2026, month: 5, day: 31, hour: 2, minute: 30)
        let afterTrigger = makeDate(year: 2026, month: 5, day: 31, hour: 3, minute: 30)
        let expectedToday = makeDate(year: 2026, month: 5, day: 31, hour: 3)
        let expectedTomorrow = makeDate(year: 2026, month: 6, day: 1, hour: 3)
        let board = makeNamedBoard(
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: makeDate(year: 2026, month: 5, day: 30, hour: 3),
            updatedAt: beforeTrigger
        )

        XCTAssertEqual(
            BoardResetRuleEngine.nextScheduledResetTime(
                for: board,
                after: beforeTrigger,
                calendar: fixedCalendar
            ),
            expectedToday
        )
        XCTAssertEqual(
            BoardResetRuleEngine.nextScheduledResetTime(
                for: board,
                after: afterTrigger,
                calendar: fixedCalendar
            ),
            expectedTomorrow
        )
    }

    func testLegacyCustomModeWithoutTimeFallsBackToMidnightReset() {
        let yesterday = makeDate(year: 2026, month: 5, day: 30, hour: 9)
        let today = makeDate(year: 2026, month: 5, day: 31, hour: 0, minute: 1)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Legacy task", isCompleted: true, lastCompletedAt: yesterday)
        let board = makeNamedBoard(
            cells: cells,
            mode: .customResetStatusTime,
            customResetMinutes: nil,
            lastTaskResetAppliedAt: yesterday,
            updatedAt: yesterday
        )

        let updated = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            board,
            now: today,
            calendar: fixedCalendar
        )

        XCTAssertFalse(updated.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertEqual(updated.lastTaskResetAppliedAt, today)
    }

    func testClearTasksModeUsesCustomResetTimeBeforeClearingTasks() {
        let beforeTrigger = makeDate(year: 2026, month: 5, day: 31, hour: 7, minute: 59)
        let afterTrigger = makeDate(year: 2026, month: 5, day: 31, hour: 8, minute: 1)
        let yesterday = makeDate(year: 2026, month: 5, day: 30, hour: 10)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Clear this",
            isCompleted: true,
            lastCompletedAt: yesterday
        )
        cells[0][1] = BingoCell(
            text: "Keep scheduled task",
            residentTaskText: "Keep scheduled task",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: yesterday),
            isCompleted: true,
            lastCompletedAt: yesterday
        )
        let board = makeNamedBoard(
            cells: cells,
            mode: .clearTasksNextDay,
            customResetMinutes: 8 * 60,
            lastTaskResetAppliedAt: yesterday,
            updatedAt: yesterday
        )

        let beforeEvaluation = BoardResetRuleEngine.pendingResetEvaluation(for: board, now: beforeTrigger, calendar: fixedCalendar)
        XCTAssertTrue(beforeEvaluation.usesCustomResetTime)
        XCTAssertFalse(beforeEvaluation.shouldApply)

        let beforeUpdated = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(board, now: beforeTrigger, calendar: fixedCalendar)
        XCTAssertEqual(beforeUpdated.board.fullBoardCells?[0][0].storedTaskText, "Clear this")
        XCTAssertTrue(beforeUpdated.board.fullBoardCells?[0][1].isCompleted == true)

        let afterUpdated = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(board, now: afterTrigger, calendar: fixedCalendar)
        XCTAssertEqual(afterUpdated.lastTaskResetAppliedAt, afterTrigger)
        XCTAssertTrue(afterUpdated.board.fullBoardCells?[0][0].isEmpty ?? false)
        XCTAssertEqual(afterUpdated.board.fullBoardCells?[0][1].storedTaskText, "Keep scheduled task")
        XCTAssertFalse(afterUpdated.board.fullBoardCells?[0][1].isCompleted == true)
    }
}

final class BoardRulesSaveRulesTests: XCTestCase {
    func testCountdownOnlySavePreservesResetAnchor() {
        let previousReset = makeDate(year: 2026, month: 6, day: 29, hour: 3)
        let now = makeDate(year: 2026, month: 6, day: 30, hour: 9)

        let resolved = BoardRulesSaveRules.resolvedLastResetAppliedAt(
            previousMode: .resetStatusNextDay,
            previousCustomResetMinutes: 3 * 60,
            previousLastResetAppliedAt: previousReset,
            newMode: .resetStatusNextDay,
            newCustomResetMinutes: 3 * 60,
            now: now
        )

        XCTAssertEqual(resolved, previousReset)
    }

    func testResetScheduleChangeStartsNewCycleAtSaveTime() {
        let previousReset = makeDate(year: 2026, month: 6, day: 29, hour: 3)
        let now = makeDate(year: 2026, month: 6, day: 30, hour: 9)

        let resolved = BoardRulesSaveRules.resolvedLastResetAppliedAt(
            previousMode: .resetStatusNextDay,
            previousCustomResetMinutes: 3 * 60,
            previousLastResetAppliedAt: previousReset,
            newMode: .clearTasksNextDay,
            newCustomResetMinutes: 4 * 60,
            now: now
        )

        XCTAssertEqual(resolved, now)
    }

    func testLegacyCustomModeEquivalentDoesNotRewriteResetAnchor() {
        let previousReset = makeDate(year: 2026, month: 6, day: 29, hour: 3)
        let now = makeDate(year: 2026, month: 6, day: 30, hour: 9)

        let resolved = BoardRulesSaveRules.resolvedLastResetAppliedAt(
            previousMode: .customResetStatusTime,
            previousCustomResetMinutes: 3 * 60,
            previousLastResetAppliedAt: previousReset,
            newMode: .resetStatusNextDay,
            newCustomResetMinutes: 3 * 60,
            now: now
        )

        XCTAssertEqual(resolved, previousReset)
    }
}

final class BoardRulesPremiumReturnRulesTests: XCTestCase {
    func testPurchaseSuccessRestoresExactBoardRulesDraft() {
        let boardID = UUID()
        let draft = BoardRulesDraft(
            boardID: boardID,
            countdownMinutes: 2 * 24 * 60 + 45,
            resetMode: .clearTasksNextDay,
            customResetMinutes: 3 * 60 + 17
        )

        let restored = BoardRulesPremiumReturnRules.restorableDraft(
            from: draft,
            hasPremiumAccess: true,
            availableBoardIDs: [boardID]
        )

        XCTAssertEqual(restored, draft)
        XCTAssertEqual(restored?.customResetMinutes, 3 * 60 + 17)
        XCTAssertEqual(restored?.countdownMinutes, 2 * 24 * 60 + 45)
    }

    func testCanceledOrFailedPurchaseDoesNotRestoreDraft() {
        let boardID = UUID()
        let draft = BoardRulesDraft(
            boardID: boardID,
            countdownMinutes: nil,
            resetMode: .resetStatusNextDay,
            customResetMinutes: 3 * 60
        )

        XCTAssertNil(
            BoardRulesPremiumReturnRules.restorableDraft(
                from: draft,
                hasPremiumAccess: false,
                availableBoardIDs: [boardID]
            )
        )
    }

    func testDeletedBoardDoesNotRestoreDraftAfterPurchase() {
        let draft = BoardRulesDraft(
            boardID: UUID(),
            countdownMinutes: 30,
            resetMode: .resetStatusNextDay,
            customResetMinutes: 4 * 60
        )

        XCTAssertNil(
            BoardRulesPremiumReturnRules.restorableDraft(
                from: draft,
                hasPremiumAccess: true,
                availableBoardIDs: []
            )
        )
    }
}

final class BoardEngineTimeSensitivityTests: XCTestCase {
    func testNextTimeSensitiveUpdateDateReturnsUpcomingStartDate() {
        let now = makeDate(year: 2026, month: 6, day: 19, hour: 9)
        let startAt = now.addingTimeInterval(15 * 60)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Future task", startVisibleAt: startAt)

        let nextDate = BoardEngine.nextTimeSensitiveUpdateDate(in: cells, size: 2, now: now)

        XCTAssertEqual(nextDate?.timeIntervalSince(startAt) ?? 1, 0, accuracy: 0.5)
    }

    func testNextTimeSensitiveUpdateDateIgnoresPastStartDateWithoutDeadline() {
        let now = makeDate(year: 2026, month: 6, day: 19, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Visible task",
            startVisibleAt: now.addingTimeInterval(-15 * 60)
        )

        XCTAssertNil(BoardEngine.nextTimeSensitiveUpdateDate(in: cells, size: 2, now: now))
    }
}

final class TaskStartReminderServiceTests: XCTestCase {
    func testRecurringDailyTaskDoesNotScheduleLegacyTimeWindowReminder() {
        let anchorStart = makeDate(year: 2026, month: 6, day: 18, hour: 9)
        let anchorEnd = makeDate(year: 2026, month: 6, day: 18, hour: 10)
        let now = makeDate(year: 2026, month: 6, day: 19, hour: 9)
        let cell = BingoCell(
            text: "Take meds",
            residentTaskText: "Take meds",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: anchorStart),
            startVisibleAt: anchorStart,
            endVisibleAt: anchorEnd,
            usesRecurringTimeWindow: true,
            startReminderEnabled: true,
            startReminderOffsetMinutes: 5
        )

        XCTAssertNil(
            TaskStartReminderService.nextReminderDate(
                for: cell,
                now: now,
                calendar: fixedCalendar
            )
        )
    }

    func testRecurringWeeklyTaskDoesNotScheduleLegacyTimeWindowReminder() {
        let anchorStart = makeDate(year: 2026, month: 6, day: 15, hour: 9)
        let anchorEnd = makeDate(year: 2026, month: 6, day: 15, hour: 10)
        let expectedStart = makeDate(year: 2026, month: 6, day: 22, hour: 9)
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 12)
        let targetWeekday = fixedCalendar.component(.weekday, from: expectedStart)
        let cell = BingoCell(
            text: "Weekly review",
            residentTaskText: "Weekly review",
            recurrenceRule: TaskRecurrenceRule(
                kind: .weekly,
                weekdays: [targetWeekday],
                anchorDate: anchorStart
            ),
            startVisibleAt: anchorStart,
            endVisibleAt: anchorEnd,
            usesRecurringTimeWindow: true,
            startReminderEnabled: true,
            startReminderOffsetMinutes: 10
        )

        XCTAssertNil(
            TaskStartReminderService.nextReminderDate(
                for: cell,
                now: now,
                calendar: fixedCalendar
            )
        )
    }

    func testOneTimeReminderKeepsAbsoluteStartDate() {
        let startAt = makeDate(year: 2026, month: 6, day: 19, hour: 10)
        let cell = BingoCell(
            text: "Focus block",
            startVisibleAt: startAt,
            endVisibleAt: startAt.addingTimeInterval(60 * 60),
            startReminderEnabled: true,
            startReminderOffsetMinutes: 5
        )

        XCTAssertEqual(
            TaskStartReminderService.nextReminderDate(
                for: cell,
                now: makeDate(year: 2026, month: 6, day: 19, hour: 9),
                calendar: fixedCalendar
            ),
            makeDate(year: 2026, month: 6, day: 19, hour: 9, minute: 55)
        )
    }

    func testSyncSignatureStaysStableWhileReminderSetIsUnchanged() {
        let now = makeDate(year: 2026, month: 6, day: 19, hour: 9)
        let startAt = makeDate(year: 2026, month: 6, day: 19, hour: 10)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Focus block",
            startVisibleAt: startAt,
            endVisibleAt: startAt.addingTimeInterval(60 * 60),
            startReminderEnabled: true,
            startReminderOffsetMinutes: 5
        )
        let board = makeNamedBoard(cells: cells, updatedAt: now)

        let initialSignature = TaskStartReminderService.syncSignature(
            namedBoards: [board],
            selectedBoardID: board.id,
            activeBoard: nil,
            now: now
        )
        let laterSignature = TaskStartReminderService.syncSignature(
            namedBoards: [board],
            selectedBoardID: board.id,
            activeBoard: nil,
            now: now.addingTimeInterval(60)
        )

        XCTAssertFalse(initialSignature.isEmpty)
        XCTAssertEqual(initialSignature, laterSignature)
    }
}

final class TaskStartReminderSyncStoreTests: XCTestCase {
    @MainActor
    func testScheduleSyncSkipsDuplicateSignature() async {
        let counter = ReminderSyncCounter()
        let scheduler = FakeTaskStartReminderScheduler(signature: "same", counter: counter)
        let store = TaskStartReminderSyncStore(scheduler: scheduler, debounceNanoseconds: 0)

        let syncTask = store.scheduleSync(namedBoards: [], selectedBoardID: nil, activeBoard: nil)
        store.scheduleSync(namedBoards: [], selectedBoardID: nil, activeBoard: nil)

        await syncTask?.value

        let syncCount = await counter.value
        XCTAssertEqual(syncCount, 1)
    }

    @MainActor
    func testCancelPendingSyncAllowsSameSignatureToBeScheduledAgain() async {
        let counter = ReminderSyncCounter()
        let scheduler = FakeTaskStartReminderScheduler(signature: "same", counter: counter)
        let store = TaskStartReminderSyncStore(scheduler: scheduler, debounceNanoseconds: .max)

        XCTAssertNotNil(store.scheduleSync(namedBoards: [], selectedBoardID: nil, activeBoard: nil))
        store.cancelPendingSync()

        XCTAssertNotNil(store.scheduleSync(namedBoards: [], selectedBoardID: nil, activeBoard: nil))
        store.cancelPendingSync()

        let syncCount = await counter.value
        XCTAssertEqual(syncCount, 0)
    }
}

final class HomeBoardSnapshotSyncStoreTests: XCTestCase {
    private func pointsTransaction(
        previousBoard: BingoBoardStore.NamedBoard,
        updatedBoard: BingoBoardStore.NamedBoard
    ) -> (previous: PointsPersistenceSnapshot, updated: PointsPersistenceSnapshot) {
        let previous = PointsPersistenceSnapshot(
            totalPoints: 20,
            lifetimePoints: 20,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: updatedBoard.updatedAt)
        )
        let updated = WidgetTaskToggleService.projectedPointsSnapshot(
            previousBoard: previousBoard,
            updatedBoard: updatedBoard,
            now: updatedBoard.updatedAt,
            didApplyBoardReset: false,
            currentPoints: previous
        )
        return (previous, updated)
    }

    @MainActor
    func testSyncSelectedBoardSnapshotSkipsSideEffectsWhenSnapshotIsUnchanged() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 10)
        let countdownEndsAt = now.addingTimeInterval(30 * 60)
        var namedBoard = makeNamedBoard(updatedAt: now)
        namedBoard.countdownEndsAt = countdownEndsAt
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            )
        )
        let boardManagementStore = BoardManagementStore(repository: repository)
        boardManagementStore.namedBoards = [namedBoard]
        boardManagementStore.selectedBoardID = namedBoard.id
        boardManagementStore.hasLoadedBoardSwitcherState = true
        let store = HomeBoardSnapshotSyncStore()

        let result = store.syncSelectedBoardSnapshot(
            boardManagementStore: boardManagementStore,
            board: namedBoard.board,
            countdownEndsAt: countdownEndsAt,
            syncTaskReminders: true
        )

        XCTAssertFalse(result.didChangeSnapshot)
        XCTAssertFalse(result.shouldInvalidateCountdownTickSchedule)
        XCTAssertFalse(result.shouldSyncTaskReminders)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 0)
    }

    @MainActor
    func testLoadRepairsCrossBoardActiveMirrorWithoutOverwritingNamedBoard() throws {
        let now = makeDate(year: 2026, month: 7, day: 19, hour: 10, minute: 30)
        var localBoard = makeNamedBoard(updatedAt: now)
        localBoard.name = "Local board"
        var remotelySelectedBoard = makeNamedBoard(updatedAt: now)
        remotelySelectedBoard.name = "Remote selection"
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: remotelySelectedBoard.id,
                boards: [localBoard, remotelySelectedBoard]
            ),
            board: remotelySelectedBoard.board,
            savedAt: now.addingTimeInterval(60),
            activeNamedBoardID: localBoard.id
        )
        let store = BoardManagementStore(repository: repository)

        let loaded = try XCTUnwrap(store.loadIfNeeded(
            initialBoard: localBoard.board,
            countdownEndsAt: nil
        ))

        XCTAssertEqual(loaded.id, localBoard.id)
        XCTAssertEqual(store.selectedBoardID, localBoard.id)
        XCTAssertEqual(repository.persistedSelectedBoardID, localBoard.id)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, localBoard.id)
        XCTAssertEqual(repository.persistedWidgetPanelID, localBoard.id)
        XCTAssertEqual(repository.loadBoard(), localBoard.board)
        XCTAssertEqual(
            repository.loadNamedBoardsSnapshot().boards.first(where: { $0.id == localBoard.id }),
            localBoard
        )
    }

    @MainActor
    func testLoadRepairsOlderCrossBoardActiveMirror() throws {
        let now = makeDate(year: 2026, month: 7, day: 19, hour: 10, minute: 30)
        var localBoard = makeNamedBoard(updatedAt: now)
        localBoard.name = "Local board"
        let unrelatedBoard = makeNamedBoard(updatedAt: now.addingTimeInterval(-120))
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: localBoard.id,
                boards: [localBoard, unrelatedBoard]
            ),
            board: unrelatedBoard.board,
            savedAt: now.addingTimeInterval(-60),
            activeNamedBoardID: localBoard.id
        )
        let store = BoardManagementStore(repository: repository)

        let loaded = try XCTUnwrap(store.loadIfNeeded(
            initialBoard: unrelatedBoard.board,
            countdownEndsAt: nil
        ))

        XCTAssertEqual(loaded.id, localBoard.id)
        XCTAssertEqual(repository.loadBoard(), localBoard.board)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, localBoard.id)
        XCTAssertEqual(repository.persistedWidgetPanelID, localBoard.id)
        XCTAssertEqual(
            repository.loadNamedBoardsSnapshot().boards.first(where: { $0.id == localBoard.id }),
            localBoard
        )
    }

    @MainActor
    func testSyncSelectedBoardSnapshotRequestsReminderSyncWhenChangedAndAllowed() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 11)
        var namedBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            )
        )
        let boardManagementStore = BoardManagementStore(repository: repository)
        boardManagementStore.namedBoards = [namedBoard]
        boardManagementStore.selectedBoardID = namedBoard.id
        boardManagementStore.hasLoadedBoardSwitcherState = true
        let store = HomeBoardSnapshotSyncStore()
        namedBoard.countdownEndsAt = now.addingTimeInterval(30 * 60)

        let result = store.syncSelectedBoardSnapshot(
            boardManagementStore: boardManagementStore,
            board: namedBoard.board,
            countdownEndsAt: namedBoard.countdownEndsAt,
            syncTaskReminders: true
        )

        XCTAssertTrue(result.didChangeSnapshot)
        XCTAssertTrue(result.shouldInvalidateCountdownTickSchedule)
        XCTAssertTrue(result.shouldSyncTaskReminders)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
    }

    @MainActor
    func testCompletionCommitSynchronouslyUpdatesLocalNamedAndActiveSnapshots() throws {
        let originalUpdatedAt = makeDate(year: 2026, month: 6, day: 20, hour: 12)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Local task")
        let originalBoard = makeNamedBoard(
            cells: cells,
            lastTaskResetAppliedAt: originalUpdatedAt,
            updatedAt: originalUpdatedAt
        )
        let completedBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: originalBoard,
                row: 0,
                col: 0,
                now: originalUpdatedAt.addingTimeInterval(1),
                commitSideEffects: false
            )
        )
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: originalBoard.id,
                boards: [originalBoard]
            ),
            board: originalBoard.board,
            savedAt: originalBoard.updatedAt,
            activeNamedBoardID: originalBoard.id
        )
        let boardManagementStore = BoardManagementStore(repository: repository)
        boardManagementStore.namedBoards = [originalBoard]
        boardManagementStore.selectedBoardID = originalBoard.id
        boardManagementStore.hasLoadedBoardSwitcherState = true

        let result = HomeBoardSnapshotSyncStore().commitCellCompletionSnapshot(
            boardManagementStore: boardManagementStore,
            board: completedBoard.board,
            countdownEndsAt: nil
        )

        let persistedBoard = try XCTUnwrap(
            repository.loadNamedBoardsSnapshot().boards.first
        )
        XCTAssertTrue(persistedBoard.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertTrue(repository.loadBoard()?.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, originalBoard.id)
        XCTAssertTrue(result.didChangeSnapshot)
        XCTAssertTrue(result.shouldInvalidateCountdownTickSchedule)
        XCTAssertFalse(result.shouldSyncTaskReminders)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 1)
        XCTAssertEqual(repository.reloadWidgetCallCount, 1)
    }

}


final class HomeLifecycleWorkStoreTests: XCTestCase {
    func testCatchUpPlanKeepsLifecycleWorkOrder() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 12)
        let plan = HomeLifecycleWorkStore().catchUpPlan(
            now: now,
            force: true,
            source: "onAppear",
            shouldApplyForegroundCleanup: true,
            simulateNextDayBoardRuleReset: false
        )

        XCTAssertEqual(plan.context, HomeLifecycleWorkContext(
            now: now,
            force: true,
            source: "onAppear",
            shouldApplyForegroundCleanup: true
        ))
        XCTAssertEqual(plan.steps, [
            .loadPointsAfterFirstFrame,
            .ensureBoardSwitcherLoaded,
            .reloadBoardSwitcherSnapshotFromSharedStore,
            .handleBoardResetLifecycle,
            .evaluateFirstStepGuideEntry,
            .updateCountdownClock,
            .processTimeoutWork,
            .syncTaskStartReminders,
            .evaluateAppReviewPromptOpportunity,
            .debugTileGestureBlockers,
            .refreshCountdownTickSchedule
        ])
    }

    func testCatchUpPlanInsertsDebugResetAfterScheduledReset() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 13)
        let plan = HomeLifecycleWorkStore().catchUpPlan(
            now: now,
            force: true,
            source: "debug",
            shouldApplyForegroundCleanup: true,
            simulateNextDayBoardRuleReset: true
        )

        XCTAssertEqual(
            plan.steps.prefix(5),
            [
                .loadPointsAfterFirstFrame,
                .ensureBoardSwitcherLoaded,
                .reloadBoardSwitcherSnapshotFromSharedStore,
                .handleBoardResetLifecycle,
                .forceApplyDebugBoardReset
            ]
        )
    }
}

final class HomeAppReviewPromptStoreTests: XCTestCase {
    func testCandidateReturnsFirstTwoLinesBeforeFirstPromptStage() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 12)
        let state = makeAppReviewPromptState(
            now: now,
            stage: 0,
            completedLineCount: 2
        )

        let candidate = HomeAppReviewPromptStore().candidate(trigger: nil, state: state)

        XCTAssertEqual(candidate, .firstTwoLines)
        XCTAssertEqual(candidate?.stageToRecord, 1)
    }

    func testCandidateBlocksSecondStageOnSameDay() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 13)
        let state = makeAppReviewPromptState(
            now: now,
            stage: 1,
            lastShownDay: PointsStore.dateKey(for: now, calendar: fixedCalendar),
            isBoardFullyCompleted: true,
            consecutiveTaskCompletionDays: 3
        )

        let candidate = HomeAppReviewPromptStore().candidate(trigger: .secondFullBoard, state: state)

        XCTAssertNil(candidate)
    }

    func testGenericCandidateFindsThreeDayStreakAfterFirstPromptStage() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 13)
        let state = makeAppReviewPromptState(
            now: now,
            stage: 1,
            lastShownDay: PointsStore.dateKey(
                for: makeDate(year: 2026, month: 6, day: 19, hour: 13),
                calendar: fixedCalendar
            ),
            consecutiveTaskCompletionDays: 3
        )

        let candidate = HomeAppReviewPromptStore().candidate(trigger: nil, state: state)

        XCTAssertEqual(candidate, .secondThreeDayStreak)
    }

    func testCandidateAllowsDebugPromptBeforeNormalEligibilityChecks() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 14)
        let state = makeAppReviewPromptState(
            now: now,
            forceDebugPrompt: true,
            hasRatedPrompt: true,
            lifetimeShownCount: 2,
            cooldownUntil: now.addingTimeInterval(60 * 60).timeIntervalSince1970
        )

        let candidate = HomeAppReviewPromptStore().candidate(trigger: nil, state: state)

        XCTAssertEqual(candidate, .debug)
        XCTAssertNil(candidate?.stageToRecord)
    }

    func testPresentationBlocksNormalCandidateWhenAnotherOverlayIsVisible() {
        let state = makeAppReviewPresentationState(isSidebarPresented: true)

        let canPresent = HomeAppReviewPromptStore().canPresent(
            candidate: .firstTwoLines,
            state: state
        )

        XCTAssertFalse(canPresent)
    }

    func testPresentationAllowsDebugCandidateToBypassBlockers() {
        let state = makeAppReviewPresentationState(
            debugBypassesBlockers: true,
            isSidebarPresented: true,
            hasTimeoutDelayPicker: true
        )

        let canPresent = HomeAppReviewPromptStore().canPresent(
            candidate: .debug,
            state: state
        )

        XCTAssertTrue(canPresent)
    }

    func testPresentationNeverShowsWhenAlreadyPresented() {
        let state = makeAppReviewPresentationState(
            isPromptPresented: true,
            debugBypassesBlockers: true
        )

        let canPresent = HomeAppReviewPromptStore().canPresent(
            candidate: .debug,
            state: state
        )

        XCTAssertFalse(canPresent)
    }
}

@MainActor
final class HomeAppReviewEvaluationStoreTests: XCTestCase {
    func testRapidRequestsCoalesceToTaskCompletionAndIgnoreStaleCallback() {
        var scheduledActions: [() -> Void] = []
        let store = HomeAppReviewEvaluationStore { _, action in
            scheduledActions.append(action)
        }
        let boardID = UUID()
        var evaluatedTriggers: [AppReviewPromptCandidate] = []

        store.scheduleEvaluation(
            trigger: .firstTwoLines,
            boardID: boardID,
            currentBoardID: { boardID },
            onEvaluate: { evaluatedTriggers.append($0) }
        )
        store.scheduleEvaluation(
            trigger: .secondThreeDayStreak,
            boardID: boardID,
            currentBoardID: { boardID },
            onEvaluate: { evaluatedTriggers.append($0) }
        )

        XCTAssertEqual(scheduledActions.count, 2)
        scheduledActions[0]()
        XCTAssertTrue(evaluatedTriggers.isEmpty)

        scheduledActions[1]()
        XCTAssertEqual(evaluatedTriggers, [.secondThreeDayStreak])
    }

    func testBoardSwitchInvalidatesPendingEvaluation() {
        var scheduledAction: (() -> Void)?
        let store = HomeAppReviewEvaluationStore { _, action in
            scheduledAction = action
        }
        let originalBoardID = UUID()
        let currentBoardID = UUID()
        var evaluatedTriggers: [AppReviewPromptCandidate] = []

        store.scheduleEvaluation(
            trigger: .secondThreeDayStreak,
            boardID: originalBoardID,
            currentBoardID: { currentBoardID },
            onEvaluate: { evaluatedTriggers.append($0) }
        )
        scheduledAction?()

        XCTAssertTrue(evaluatedTriggers.isEmpty)
    }

    func testRequestsFromDifferentBoardsDoNotMergeTriggers() {
        var scheduledActions: [() -> Void] = []
        let store = HomeAppReviewEvaluationStore { _, action in
            scheduledActions.append(action)
        }
        let originalBoardID = UUID()
        let currentBoardID = UUID()
        var evaluatedTriggers: [AppReviewPromptCandidate] = []

        store.scheduleEvaluation(
            trigger: .secondThreeDayStreak,
            boardID: originalBoardID,
            currentBoardID: { currentBoardID },
            onEvaluate: { evaluatedTriggers.append($0) }
        )
        store.scheduleEvaluation(
            trigger: .firstTwoLines,
            boardID: currentBoardID,
            currentBoardID: { currentBoardID },
            onEvaluate: { evaluatedTriggers.append($0) }
        )

        scheduledActions[0]()
        scheduledActions[1]()

        XCTAssertEqual(evaluatedTriggers, [.firstTwoLines])
    }
}

final class HomeTimeoutWorkStoreTests: XCTestCase {
    func testShouldRunMaintenanceUsesCachedSchedule() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 13)
        let store = HomeTimeoutWorkStore()

        XCTAssertTrue(store.shouldRunMaintenance(
            now: now,
            hasComputedSchedule: false,
            nextWorkDate: nil
        ))
        XCTAssertFalse(store.shouldRunMaintenance(
            now: now,
            hasComputedSchedule: true,
            nextWorkDate: nil
        ))
        XCTAssertFalse(store.shouldRunMaintenance(
            now: now,
            hasComputedSchedule: true,
            nextWorkDate: now.addingTimeInterval(60)
        ))
        XCTAssertTrue(store.shouldRunMaintenance(
            now: now,
            hasComputedSchedule: true,
            nextWorkDate: now
        ))
    }

    func testTickPlanReturnsNilWhenNoClockOrMaintenanceWorkIsNeeded() {
        let plan = HomeTimeoutWorkStore().tickPlan(
            now: makeDate(year: 2026, month: 6, day: 20, hour: 14),
            shouldRunMaintenance: false,
            requiresLiveCountdownTicks: false,
            hasTimeoutDelayPicker: false
        )

        XCTAssertNil(plan)
    }

    func testTickPlanOnlyUpdatesClockForLiveCountdownWithoutMaintenance() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 15)
        let plan = HomeTimeoutWorkStore().tickPlan(
            now: now,
            shouldRunMaintenance: false,
            requiresLiveCountdownTicks: true,
            hasTimeoutDelayPicker: false
        )

        XCTAssertEqual(plan?.context, HomeTimeoutWorkContext(
            now: now,
            shouldRunMaintenance: false,
            requiresLiveCountdownTicks: true,
            hasTimeoutDelayPicker: false
        ))
        XCTAssertEqual(plan?.steps, [.updateCountdownClock])
    }

    func testTickPlanRunsFullMaintenanceOrderWhenDue() {
        let plan = HomeTimeoutWorkStore().tickPlan(
            now: makeDate(year: 2026, month: 6, day: 20, hour: 16),
            shouldRunMaintenance: true,
            requiresLiveCountdownTicks: false,
            hasTimeoutDelayPicker: false
        )

        XCTAssertEqual(plan?.steps, [
            .updateCountdownClock,
            .handleBoardResetLifecycle,
            .processTimeoutWork(refreshVisibilityWindows: true),
            .refreshCountdownTickSchedule
        ])
    }

    func testNextCountdownTickWorkDateUsesEarliestScheduledSource() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 17)
        let activeBoard = makeNamedBoard(
            mode: .keepTaskStatus,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )
        var otherBoard = makeNamedBoard(
            mode: .keepTaskStatus,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )
        let otherCountdownDate = now.addingTimeInterval(10 * 60)
        otherBoard.countdownEndsAt = otherCountdownDate

        let nextDate = HomeTimeoutWorkStore().nextCountdownTickWorkDate(
            after: now,
            activeBoardNextUpdateDate: now.addingTimeInterval(60 * 60),
            namedBoards: [activeBoard, otherBoard],
            selectedBoardID: activeBoard.id,
            lastBoardRulesEvaluationDateKey: PointsStore.dateKey(for: now, calendar: fixedCalendar),
            hasAppliedDebugSimulatedResetThisLaunch: true,
            simulateNextDayBoardRuleReset: false,
            calendar: fixedCalendar
        )

        XCTAssertEqual(nextDate?.timeIntervalSince(otherCountdownDate) ?? 1, 0, accuracy: 0.5)
    }

    func testNextCountdownTickWorkDateReturnsNowWhenResetEvaluationIsStale() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 18)
        let yesterday = makeDate(year: 2026, month: 6, day: 19, hour: 18)
        let board = makeNamedBoard(
            mode: .keepTaskStatus,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )

        let nextDate = HomeTimeoutWorkStore().nextCountdownTickWorkDate(
            after: now,
            activeBoardNextUpdateDate: now.addingTimeInterval(60 * 60),
            namedBoards: [board],
            selectedBoardID: board.id,
            lastBoardRulesEvaluationDateKey: PointsStore.dateKey(for: yesterday, calendar: fixedCalendar),
            hasAppliedDebugSimulatedResetThisLaunch: true,
            simulateNextDayBoardRuleReset: false,
            calendar: fixedCalendar
        )

        XCTAssertEqual(nextDate?.timeIntervalSince(now) ?? 1, 0, accuracy: 0.5)
    }

    func testNextBoardWithExpiredTimeoutFindsOtherBoardTaskDeadline() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 19)
        let activeBoard = makeNamedBoard(
            mode: .keepTaskStatus,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Expired task",
            countdownEndsAt: now.addingTimeInterval(-60)
        )
        let otherBoard = makeNamedBoard(
            cells: cells,
            mode: .keepTaskStatus,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )

        let targetBoardID = HomeTimeoutWorkStore().nextBoardWithExpiredTimeout(
            in: [activeBoard, otherBoard],
            excluding: activeBoard.id,
            now: now
        )

        XCTAssertEqual(targetBoardID, otherBoard.id)
    }
}

final class HomeBoardStateChangeTests: XCTestCase {
    func testCountdownOnlyChangeDoesNotAffectTaskReminders() {
        let change = HomeBoardStateChange(
            didChangeCells: false,
            didChangeGridSize: false,
            didChangeCompletedLines: false,
            didChangeBoardCountdown: true
        )

        XCTAssertFalse(change.affectsTaskReminders)
    }

    func testCellsOrGridChangesAffectTaskReminders() {
        let cellsChange = HomeBoardStateChange(
            didChangeCells: true,
            didChangeGridSize: false,
            didChangeCompletedLines: false,
            didChangeBoardCountdown: false
        )
        let gridChange = HomeBoardStateChange(
            didChangeCells: false,
            didChangeGridSize: true,
            didChangeCompletedLines: false,
            didChangeBoardCountdown: false
        )

        XCTAssertTrue(cellsChange.affectsTaskReminders)
        XCTAssertTrue(gridChange.affectsTaskReminders)
    }

    func testAppReviewPromptTriggerPreservesCellAndLineSemantics() {
        let cellsChange = HomeBoardStateChange(
            didChangeCells: true,
            didChangeGridSize: false,
            didChangeCompletedLines: false,
            didChangeBoardCountdown: false
        )
        let completedLinesChange = HomeBoardStateChange(
            didChangeCells: false,
            didChangeGridSize: false,
            didChangeCompletedLines: true,
            didChangeBoardCountdown: false
        )
        let combinedChange = HomeBoardStateChange(
            didChangeCells: true,
            didChangeGridSize: false,
            didChangeCompletedLines: true,
            didChangeBoardCountdown: false
        )

        XCTAssertEqual(cellsChange.appReviewPromptTrigger, .secondThreeDayStreak)
        XCTAssertEqual(completedLinesChange.appReviewPromptTrigger, .firstTwoLines)
        XCTAssertEqual(combinedChange.appReviewPromptTrigger, .secondThreeDayStreak)
    }

    func testGridOrCountdownChangesDoNotProduceAppReviewPromptTrigger() {
        let gridChange = HomeBoardStateChange(
            didChangeCells: false,
            didChangeGridSize: true,
            didChangeCompletedLines: false,
            didChangeBoardCountdown: false
        )
        let countdownChange = HomeBoardStateChange(
            didChangeCells: false,
            didChangeGridSize: false,
            didChangeCompletedLines: false,
            didChangeBoardCountdown: true
        )

        XCTAssertNil(gridChange.appReviewPromptTrigger)
        XCTAssertNil(countdownChange.appReviewPromptTrigger)
    }
}

final class WidgetTaskToggleServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistenceSideEffects()
    }

    override func tearDown() {
        clearPersistenceSideEffects()
        super.tearDown()
    }

    func testDeferredWidgetSideEffectsRunOnlyAfterExplicitCommit() throws {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 8)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Deferred task")
        let board = makeNamedBoard(cells: cells, lastTaskResetAppliedAt: now, updatedAt: now)

        let updated = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: board,
                row: 0,
                col: 0,
                now: now,
                commitSideEffects: false
            )
        )

        XCTAssertNil(PointsStore.loadTotalPoints())
        WidgetTaskToggleService.commitToggleSideEffects(
            previousBoard: board,
            updatedBoard: updated,
            row: 0,
            col: 0,
            now: now,
            didApplyBoardReset: false
        )
        XCTAssertEqual(PointsStore.loadTotalPoints(), 1)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), 1)
    }

    @MainActor
    func testAppLaunchRecoversPointsWhenWidgetEventArrivesBeforePointCommit() throws {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 8, minute: 30)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Race task")
        let originalBoard = makeNamedBoard(cells: cells, lastTaskResetAppliedAt: now, updatedAt: now)
        let updatedBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: originalBoard,
                row: 0,
                col: 0,
                now: now.addingTimeInterval(1),
                commitSideEffects: false
            )
        )
        let mutation = try XCTUnwrap(
            WidgetTaskToggleService.cellMutation(
                previousBoard: originalBoard.board,
                updatedBoard: updatedBoard.board,
                row: 0,
                col: 0
            )
        )
        let event = WidgetTaskSyncStore.Event(
            boardID: updatedBoard.id,
            board: updatedBoard,
            savedAt: updatedBoard.updatedAt,
            didApplyBoardReset: false,
            cellMutation: mutation
        )
        PointsStore.saveState(
            totalPoints: 10,
            lifetimePoints: 10,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: originalBoard.board.cells,
                completedLines: originalBoard.board.completedLines,
                isBoardFullyCompleted: false
            )
        )
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: originalBoard.id,
                boards: [originalBoard]
            ),
            widgetTaskSyncEvent: event
        )
        let store = BoardManagementStore(repository: repository)

        let selectedBoard = try XCTUnwrap(
            store.loadIfNeeded(initialBoard: originalBoard.board, countdownEndsAt: nil)
        )

        XCTAssertTrue(selectedBoard.board.cells[0][0].isCompleted)
        XCTAssertEqual(PointsStore.loadTotalPoints(), 11)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), 11)
        XCTAssertFalse(repository.hasWidgetTaskSyncEvent)

        _ = store.reloadPersistedSnapshot()
        XCTAssertEqual(PointsStore.loadTotalPoints(), 11)
    }

    @MainActor
    func testAppLaunchDoesNotSettlePointsTwiceAfterWidgetSideEffectsCommit() throws {
        let now = makeDate(year: 2026, month: 7, day: 20, hour: 14)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Already settled")
        let originalBoard = makeNamedBoard(cells: cells, lastTaskResetAppliedAt: now, updatedAt: now)
        let updatedBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: originalBoard,
                row: 0,
                col: 0,
                now: now.addingTimeInterval(1),
                commitSideEffects: false
            )
        )
        let mutation = try XCTUnwrap(
            WidgetTaskToggleService.cellMutation(
                previousBoard: originalBoard.board,
                updatedBoard: updatedBoard.board,
                row: 0,
                col: 0
            )
        )
        let event = WidgetTaskSyncStore.Event(
            boardID: updatedBoard.id,
            board: updatedBoard,
            savedAt: updatedBoard.updatedAt,
            didApplyBoardReset: false,
            cellMutation: mutation,
            sideEffectsCommitted: true
        )
        PointsStore.saveState(
            totalPoints: 11,
            lifetimePoints: 11,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: updatedBoard.board.cells,
                completedLines: updatedBoard.board.completedLines,
                isBoardFullyCompleted: false
            )
        )
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: originalBoard.id,
                boards: [originalBoard]
            ),
            widgetTaskSyncEvent: event
        )
        let store = BoardManagementStore(repository: repository)

        let selectedBoard = try XCTUnwrap(
            store.loadIfNeeded(initialBoard: originalBoard.board, countdownEndsAt: nil)
        )

        XCTAssertTrue(selectedBoard.board.cells[0][0].isCompleted)
        XCTAssertEqual(PointsStore.loadTotalPoints(), 11)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), 11)
        XCTAssertFalse(repository.hasWidgetTaskSyncEvent)
    }

    @MainActor
    func testAppLaunchRetainsWidgetEventUntilActiveBoardMirrorRetrySucceeds() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 20)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Retry active mirror")
        let originalBoard = makeNamedBoard(
            cells: cells,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )
        let updatedBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: originalBoard,
                row: 0,
                col: 0,
                now: now.addingTimeInterval(1),
                commitSideEffects: false
            )
        )
        let mutation = try XCTUnwrap(
            WidgetTaskToggleService.cellMutation(
                previousBoard: originalBoard.board,
                updatedBoard: updatedBoard.board,
                row: 0,
                col: 0
            )
        )
        let event = WidgetTaskSyncStore.Event(
            boardID: updatedBoard.id,
            board: updatedBoard,
            savedAt: updatedBoard.updatedAt,
            didApplyBoardReset: false,
            cellMutation: mutation
        )
        PointsStore.saveState(
            totalPoints: 10,
            lifetimePoints: 10,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: originalBoard.board.cells,
                completedLines: originalBoard.board.completedLines,
                isBoardFullyCompleted: false
            )
        )
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: originalBoard.id,
                boards: [originalBoard]
            ),
            board: originalBoard.board,
            savedAt: originalBoard.updatedAt,
            activeNamedBoardID: originalBoard.id,
            widgetTaskSyncEvent: event,
            boardSaveFailureCount: 1
        )
        let store = BoardManagementStore(repository: repository)

        let selectedBoard = try XCTUnwrap(
            store.loadIfNeeded(initialBoard: originalBoard.board, countdownEndsAt: nil)
        )

        XCTAssertEqual(selectedBoard.board, updatedBoard.board)
        XCTAssertTrue(repository.hasWidgetTaskSyncEvent)
        XCTAssertEqual(repository.loadBoard(), originalBoard.board)
        XCTAssertEqual(PointsStore.loadTotalPoints(), 10)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 1)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)

        _ = store.reloadPersistedSnapshot()

        XCTAssertFalse(repository.hasWidgetTaskSyncEvent)
        XCTAssertEqual(repository.loadBoard(), updatedBoard.board)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, updatedBoard.id)
        XCTAssertEqual(PointsStore.loadTotalPoints(), 11)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), 11)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 2)
        XCTAssertEqual(repository.reloadWidgetCallCount, 1)
    }

    func testToggleCompletesVisibleTaskAndClearsCountdown() throws {
        let now = makeDate(year: 2026, month: 5, day: 31, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Focus block",
            countdownEndsAt: now.addingTimeInterval(600),
            estimatedDurationMinutes: 20
        )
        cells[0][1] = BingoCell(text: "Second task")
        let board = makeNamedBoard(cells: cells, lastTaskResetAppliedAt: now, updatedAt: now)

        let updated = try XCTUnwrap(WidgetTaskToggleService.toggled(board: board, row: 0, col: 0, now: now))
        let updatedCell = try XCTUnwrap(updated.board.fullBoardCells?[0][0])

        XCTAssertTrue(updatedCell.isCompleted)
        XCTAssertEqual(updatedCell.storedTaskText, "Focus block")
        XCTAssertNil(updatedCell.countdownEndsAt)
        XCTAssertNil(updatedCell.countdownPausedRemainingSeconds)
        XCTAssertNil(updatedCell.estimatedDurationMinutes)
        XCTAssertEqual(updatedCell.completionStreakCount, 1)
        XCTAssertEqual(PointsStore.loadTotalPoints(), 1)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), 1)
    }

    func testFiveByFiveWidgetToggleCompletesBottomRightTaskAndAwardsOnePoint() throws {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[4][4] = BingoCell(text: "Bottom right task")
        let board = makeNamedBoard(
            cells: cells,
            gridSize: 5,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )

        let updated = try XCTUnwrap(
            WidgetTaskToggleService.toggled(board: board, row: 4, col: 4, now: now)
        )

        XCTAssertTrue(updated.board.fullBoardCells?[4][4].isCompleted == true)
        XCTAssertTrue(updated.board.cells[4][4].isCompleted)
        XCTAssertEqual(PointsStore.loadTotalPoints(), 1)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), 1)
    }

    func testToggleWithoutDueResetPreservesLastAppliedResetTimestamp() throws {
        let lastReset = makeDate(year: 2026, month: 5, day: 31, hour: 3)
        let now = makeDate(year: 2026, month: 5, day: 31, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Focus block")
        let board = makeNamedBoard(
            cells: cells,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: lastReset,
            updatedAt: lastReset
        )

        let updated = try XCTUnwrap(
            WidgetTaskToggleService.toggled(board: board, row: 0, col: 0, now: now)
        )

        XCTAssertEqual(updated.lastTaskResetAppliedAt, lastReset)
        XCTAssertEqual(updated.updatedAt, now)
    }

    func testToggleAfterCustomResetStartsNewCompletionAndRewardCycle() throws {
        let previousReset = makeDate(year: 2026, month: 5, day: 30, hour: 3)
        let previousCompletion = makeDate(year: 2026, month: 5, day: 31, hour: 1)
        let now = makeDate(year: 2026, month: 5, day: 31, hour: 4)
        let cellID = UUID()
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            id: cellID,
            text: "Drink water",
            residentTaskText: "Drink water",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: previousCompletion),
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: previousCompletion
        )
        let board = makeNamedBoard(
            cells: cells,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousReset,
            updatedAt: previousCompletion
        )
        PointsStore.saveTotalPoints(1)
        PointsStore.saveLifetimePoints(1)
        PointsStore.saveDailyRewardState(
            DailyRewardState(
                dateKey: PointsStore.dateKey(for: previousCompletion),
                rewardedCellIDs: [cellID],
                peakCompletedLineCount: 0,
                fullBoardRewardGranted: false
            )
        )

        let updated = try XCTUnwrap(
            WidgetTaskToggleService.toggled(board: board, row: 0, col: 0, now: now)
        )
        let updatedCell = try XCTUnwrap(updated.board.fullBoardCells?[0][0])

        XCTAssertTrue(updatedCell.isCompleted)
        XCTAssertEqual(updatedCell.completionStreakCount, 2)
        XCTAssertEqual(updatedCell.lastCompletedAt, now)
        XCTAssertEqual(updated.lastTaskResetAppliedAt, now)
        XCTAssertEqual(PointsStore.loadTotalPoints(), 2)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), 2)
        XCTAssertEqual(PointsStore.loadDailyRewardState()?.rewardedCellIDs, Set([cellID]))
    }

    func testToggleOnDifferentWidgetBoardDoesNotDeductPreviouslyEarnedBoardPoints() throws {
        let now = makeDate(year: 2026, month: 6, day: 30, hour: 9)
        let boardOneRewardedIDs = Set((0..<44).map { _ in UUID() })
        PointsStore.saveTotalPoints(44)
        PointsStore.saveLifetimePoints(44)
        PointsStore.saveDailyRewardState(
            DailyRewardState(
                dateKey: PointsStore.dateKey(for: now),
                rewardedCellIDs: boardOneRewardedIDs,
                peakCompletedLineCount: 0,
                fullBoardRewardGranted: false
            )
        )

        var boardTwoCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        boardTwoCells[0][0] = BingoCell(text: "Board 2 task")
        let boardTwo = makeNamedBoard(
            cells: boardTwoCells,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )

        let updated = try XCTUnwrap(WidgetTaskToggleService.toggled(board: boardTwo, row: 0, col: 0, now: now))

        XCTAssertTrue(updated.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertEqual(PointsStore.loadTotalPoints(), 45)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), 45)
        XCTAssertEqual(PointsStore.loadDailyRewardState()?.rewardedCellIDs, Set([updated.board.cells[0][0].id]))
    }

    func testWidgetCompletionThenAppBoardSwitchKeepsAccumulatedPoints() throws {
        let now = makeDate(year: 2026, month: 6, day: 30, hour: 10)
        var boardOneCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        boardOneCells[0][0] = BingoCell(
            text: "Board 1 completed",
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: now
        )
        boardOneCells[0][1] = BingoCell(text: "Board 1 next")
        let boardOne = makeNamedBoard(
            cells: boardOneCells,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )

        PointsStore.saveTotalPoints(44)
        PointsStore.saveLifetimePoints(44)
        PointsStore.saveDailyRewardState(
            BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: boardOne.board.cells,
                completedLines: boardOne.board.completedLines,
                isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(boardOne.board.cells)
            )
        )

        var boardTwoCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        boardTwoCells[0][0] = BingoCell(text: "Board 2 task")
        let boardTwo = makeNamedBoard(
            cells: boardTwoCells,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        )
        let widgetUpdatedBoardTwo = try XCTUnwrap(
            WidgetTaskToggleService.toggled(board: boardTwo, row: 0, col: 0, now: now)
        )
        XCTAssertEqual(PointsStore.loadTotalPoints(), 45)

        let harness = makeInMemoryViewModelHarness(
            savedBoard: widgetUpdatedBoardTwo.board,
            savedAt: now,
            totalPoints: PointsStore.loadTotalPoints(),
            lifetimePoints: PointsStore.loadLifetimePoints(),
            dailyRewardState: PointsStore.loadDailyRewardState()
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        viewModel.applySavedBoardSnapshot(
            widgetUpdatedBoardTwo.board,
            countdownEndsAt: nil,
            referenceDate: now,
            reloadPersistedPoints: true
        )
        XCTAssertEqual(viewModel.totalPoints, 45)

        viewModel.applySavedBoardSnapshot(
            boardOne.board,
            countdownEndsAt: nil,
            referenceDate: now
        )
        XCTAssertEqual(viewModel.totalPoints, 45)

        viewModel.toggleComplete(row: 0, col: 1, referenceDate: now.addingTimeInterval(60))
        let expectedPointsAfterTaskAndLineReward = 45 + 1 + 5
        XCTAssertEqual(viewModel.totalPoints, expectedPointsAfterTaskAndLineReward)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), expectedPointsAfterTaskAndLineReward)
    }

    func testToggleUndoDoesNotRestoreClearedCountdown() throws {
        let now = makeDate(year: 2026, month: 5, day: 31, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Focus block",
            countdownEndsAt: now.addingTimeInterval(600),
            estimatedDurationMinutes: 20
        )
        let board = makeNamedBoard(cells: cells, lastTaskResetAppliedAt: now, updatedAt: now)

        let completedBoard = try XCTUnwrap(WidgetTaskToggleService.toggled(board: board, row: 0, col: 0, now: now))
        let undoAt = now.addingTimeInterval(120)
        let restoredBoard = try XCTUnwrap(WidgetTaskToggleService.toggled(board: completedBoard, row: 0, col: 0, now: undoAt))
        let restoredCell = try XCTUnwrap(restoredBoard.board.fullBoardCells?[0][0])

        XCTAssertFalse(restoredCell.isCompleted)
        XCTAssertNil(restoredCell.countdownPausedRemainingSeconds)
        XCTAssertNil(restoredCell.countdownEndsAt)
        XCTAssertNil(restoredCell.estimatedDurationMinutes)
    }

    func testToggleIgnoresLockedNonForcedTaskWhenAnotherForcedTaskIsActive() {
        let now = makeDate(year: 2026, month: 5, day: 31, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Forced task", isForced: true)
        cells[0][1] = BingoCell(text: "Regular task")
        let board = makeNamedBoard(cells: cells, lastTaskResetAppliedAt: now, updatedAt: now)

        let updated = WidgetTaskToggleService.toggled(board: board, row: 0, col: 1, now: now)

        XCTAssertNil(updated)
    }

    func testToggleCanUndoCompletedTaskAfterEndTime() throws {
        let now = Date()
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Focus block",
            startVisibleAt: now.addingTimeInterval(-120),
            endVisibleAt: now.addingTimeInterval(-60),
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: now.addingTimeInterval(-30)
        )
        let board = makeNamedBoard(cells: cells, lastTaskResetAppliedAt: now, updatedAt: now)

        let updated = try XCTUnwrap(WidgetTaskToggleService.toggled(board: board, row: 0, col: 0, now: now))
        let updatedCell = try XCTUnwrap(updated.board.fullBoardCells?[0][0])

        XCTAssertFalse(cells[0][0].isCurrentlyTappable(on: now))
        XCTAssertFalse(updatedCell.isCompleted)
        XCTAssertNil(updatedCell.lastCompletedAt)
    }

    func testUndoCompletedTaskRevokesPersistedCustomRewardWhenPointsBecomeInsufficient() throws {
        let now = makeDate(year: 2026, month: 5, day: 31, hour: 9)
        RewardStore.saveRewards([
            CustomReward(
                title: "Break",
                requiredPoints: 1,
                redemptionCount: 1,
                totalSpentPoints: 1
            )
        ])

        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Focus block",
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: now
        )
        let board = makeNamedBoard(cells: cells, lastTaskResetAppliedAt: now, updatedAt: now)

        _ = try XCTUnwrap(WidgetTaskToggleService.toggled(board: board, row: 0, col: 0, now: now.addingTimeInterval(60)))

        XCTAssertEqual(PointsStore.loadTotalPoints(), 0)
        let updatedReward = try XCTUnwrap(RewardStore.loadRewards().first)
        XCTAssertEqual(updatedReward.redemptionCount, 0)
        XCTAssertEqual(updatedReward.totalSpentPoints, 0)
    }

    func testAppAndWidgetCrossToggleConsistencyAcrossEveryResetModeAndTaskKind() throws {
        XCTAssertEqual(
            Set(CrossEntryTaskKind.allCases.compactMap { $0.recurrenceKind?.rawValue }),
            Set(TaskRecurrenceRule.Kind.allCases.map(\.rawValue)),
            "A new recurrence kind must be added to the App/Widget cross-entry matrix."
        )
        XCTAssertEqual(BoardTaskResetMode.allCases.count * CrossEntryTaskKind.allCases.count * CrossEntryDirection.allCases.count, 48)

        let previousReset = makeDate(year: 2026, month: 7, day: 17, hour: 3)
        let now = makeDate(year: 2026, month: 7, day: 18, hour: 3, minute: 1)

        for resetMode in BoardTaskResetMode.allCases {
            for taskKind in CrossEntryTaskKind.allCases {
                let expectation = crossEntryExpectation(resetMode: resetMode, taskKind: taskKind)
                let preparedBoard = makeCrossEntryBoard(
                    resetMode: resetMode,
                    taskKind: taskKind,
                    previousReset: previousReset,
                    now: now
                )

                for direction in CrossEntryDirection.allCases {
                    clearPersistenceSideEffects()
                    seedGlobalCrossEntryPoints(board: preparedBoard.board, now: now)
                    let scenario = "\(resetMode.rawValue) / \(taskKind.rawValue) / \(direction.rawValue)"

                    guard expectation.taskSurvives else {
                        try assertRemovedTaskRejectsBothEntries(
                            board: preparedBoard,
                            now: now,
                            scenario: scenario
                        )
                        continue
                    }

                    switch direction {
                    case .appFirst:
                        try runAppFirstCrossEntrySequence(
                            board: preparedBoard,
                            initialCompleted: expectation.initialCompleted,
                            now: now,
                            scenario: scenario
                        )
                    case .widgetFirst:
                        try runWidgetFirstCrossEntrySequence(
                            board: preparedBoard,
                            initialCompleted: expectation.initialCompleted,
                            now: now,
                            scenario: scenario
                        )
                    }
                }
            }
        }
    }

    private enum CrossEntryDirection: String, CaseIterable {
        case appFirst
        case widgetFirst
    }

    private enum CrossEntryTaskKind: String, CaseIterable {
        case regular
        case oneTime
        case daily
        case weekly
        case monthlyDay
        case everyNDays

        var recurrenceKind: TaskRecurrenceRule.Kind? {
            switch self {
            case .regular: nil
            case .oneTime: .some(.none)
            case .daily: .daily
            case .weekly: .weekly
            case .monthlyDay: .monthlyDay
            case .everyNDays: .everyNDays
            }
        }
    }

    private struct CrossEntryExpectation {
        let taskSurvives: Bool
        let initialCompleted: Bool
    }

    private struct CrossEntryPointExpectation {
        let total: Int
        let lifetime: Int
    }

    private func crossEntryExpectation(
        resetMode: BoardTaskResetMode,
        taskKind: CrossEntryTaskKind
    ) -> CrossEntryExpectation {
        switch resetMode {
        case .resetStatusNextDay, .customResetStatusTime:
            CrossEntryExpectation(taskSurvives: true, initialCompleted: false)
        case .clearTasksNextDay:
            CrossEntryExpectation(taskSurvives: taskKind != .regular, initialCompleted: false)
        case .keepTaskStatus:
            CrossEntryExpectation(taskSurvives: true, initialCompleted: true)
        }
    }

    private func makeCrossEntryBoard(
        resetMode: BoardTaskResetMode,
        taskKind: CrossEntryTaskKind,
        previousReset: Date,
        now: Date
    ) -> BingoBoardStore.NamedBoard {
        let title = "Cross entry \(taskKind.rawValue)"
        let recurrenceRule: TaskRecurrenceRule?
        switch taskKind {
        case .regular:
            recurrenceRule = nil
        case .oneTime:
            recurrenceRule = TaskRecurrenceRule(kind: .none, anchorDate: now)
        case .daily:
            recurrenceRule = TaskRecurrenceRule(kind: .daily, anchorDate: previousReset)
        case .weekly:
            recurrenceRule = TaskRecurrenceRule(
                kind: .weekly,
                weekdays: [fixedCalendar.component(.weekday, from: now)],
                anchorDate: previousReset
            )
        case .monthlyDay:
            recurrenceRule = TaskRecurrenceRule(
                kind: .monthlyDay,
                monthDay: fixedCalendar.component(.day, from: now),
                anchorDate: previousReset
            )
        case .everyNDays:
            recurrenceRule = TaskRecurrenceRule(
                kind: .everyNDays,
                interval: 2,
                anchorDate: fixedCalendar.date(byAdding: .day, value: -2, to: now)
            )
        }

        var fullBoard = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        fullBoard[0][0] = BingoCell(
            text: title,
            residentTaskText: taskKind == .regular ? nil : title,
            recurrenceRule: recurrenceRule,
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: previousReset
        )
        let sourceBoard = makeNamedBoard(
            cells: fullBoard,
            mode: resetMode,
            customResetMinutes: resetMode == .customResetStatusTime ? 3 * 60 : nil,
            lastTaskResetAppliedAt: previousReset,
            updatedAt: previousReset
        )
        var preparedBoard = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            sourceBoard,
            now: now,
            calendar: fixedCalendar
        )
        let preparedFullBoard = BoardEngine.expandedBoardCache(from: preparedBoard.board)
        let visibleCells = BoardEngine.projectVisibleCells(
            from: preparedFullBoard,
            size: preparedBoard.board.gridSize,
            referenceDate: now
        )
        preparedBoard.board = SavedBoard(
            gridSize: preparedBoard.board.gridSize,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(
                in: visibleCells,
                size: preparedBoard.board.gridSize
            ),
            fullBoardCells: preparedFullBoard
        )
        return preparedBoard
    }

    private func seedGlobalCrossEntryPoints(board: SavedBoard, now: Date) {
        XCTAssertTrue(PointsStore.saveState(
            totalPoints: 20,
            lifetimePoints: 30,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: board.cells,
                completedLines: board.completedLines,
                isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(board.cells)
            )
        ))
    }

    private func runAppFirstCrossEntrySequence(
        board: BingoBoardStore.NamedBoard,
        initialCompleted: Bool,
        now: Date,
        scenario: String
    ) throws {
        let firstAt = now.addingTimeInterval(1)
        let secondAt = now.addingTimeInterval(2)
        let thirdAt = now.addingTimeInterval(3)
        let harness = makeInMemoryViewModelHarness(
            savedBoard: nil,
            totalPoints: 20,
            lifetimePoints: 30,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        viewModel.applySavedBoardSnapshot(
            board.board,
            countdownEndsAt: board.countdownEndsAt,
            referenceDate: now
        )

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: firstAt)
        assertAppCrossEntryState(
            viewModel: viewModel,
            repository: harness.pointsRepository,
            completed: !initialCompleted,
            points: crossEntryPoints(initialCompleted: initialCompleted, transition: 1),
            scenario: "\(scenario) App first"
        )

        let appSavedBoard = try XCTUnwrap(harness.boardRepository.loadBoard(), scenario)
        try persistAppCrossEntryPointsToGlobal(harness.pointsRepository, scenario: scenario)
        let widgetInput = replacingCrossEntryBoard(board, with: appSavedBoard, updatedAt: firstAt)
        let widgetUpdatedBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: widgetInput,
                row: 0,
                col: 0,
                now: secondAt
            ),
            scenario
        )
        assertWidgetCrossEntryState(
            board: widgetUpdatedBoard,
            completed: initialCompleted,
            points: crossEntryPoints(initialCompleted: initialCompleted, transition: 2),
            scenario: "\(scenario) Widget reverse"
        )

        try loadGlobalCrossEntryPoints(into: harness.pointsRepository, scenario: scenario)
        viewModel.applySavedBoardSnapshot(
            widgetUpdatedBoard.board,
            countdownEndsAt: widgetUpdatedBoard.countdownEndsAt,
            referenceDate: secondAt,
            reloadPersistedPoints: true
        )
        viewModel.toggleComplete(row: 0, col: 0, referenceDate: thirdAt)
        let finalPoints = crossEntryPoints(initialCompleted: initialCompleted, transition: 3)
        assertAppCrossEntryState(
            viewModel: viewModel,
            repository: harness.pointsRepository,
            completed: !initialCompleted,
            points: finalPoints,
            scenario: "\(scenario) App repeat"
        )
        try persistAppCrossEntryPointsToGlobal(harness.pointsRepository, scenario: scenario)
        assertGlobalCrossEntryPoints(finalPoints, scenario: "\(scenario) final")
    }

    private func runWidgetFirstCrossEntrySequence(
        board: BingoBoardStore.NamedBoard,
        initialCompleted: Bool,
        now: Date,
        scenario: String
    ) throws {
        let firstAt = now.addingTimeInterval(1)
        let secondAt = now.addingTimeInterval(2)
        let thirdAt = now.addingTimeInterval(3)
        let widgetUpdatedBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: board,
                row: 0,
                col: 0,
                now: firstAt
            ),
            scenario
        )
        assertWidgetCrossEntryState(
            board: widgetUpdatedBoard,
            completed: !initialCompleted,
            points: crossEntryPoints(initialCompleted: initialCompleted, transition: 1),
            scenario: "\(scenario) Widget first"
        )

        let harness = makeInMemoryViewModelHarness(
            savedBoard: nil,
            totalPoints: PointsStore.loadTotalPoints(),
            lifetimePoints: PointsStore.loadLifetimePoints(),
            dailyRewardState: PointsStore.loadDailyRewardState()
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        viewModel.applySavedBoardSnapshot(
            widgetUpdatedBoard.board,
            countdownEndsAt: widgetUpdatedBoard.countdownEndsAt,
            referenceDate: firstAt
        )
        viewModel.toggleComplete(row: 0, col: 0, referenceDate: secondAt)
        assertAppCrossEntryState(
            viewModel: viewModel,
            repository: harness.pointsRepository,
            completed: initialCompleted,
            points: crossEntryPoints(initialCompleted: initialCompleted, transition: 2),
            scenario: "\(scenario) App reverse"
        )

        let appSavedBoard = try XCTUnwrap(harness.boardRepository.loadBoard(), scenario)
        try persistAppCrossEntryPointsToGlobal(harness.pointsRepository, scenario: scenario)
        let widgetInput = replacingCrossEntryBoard(
            widgetUpdatedBoard,
            with: appSavedBoard,
            updatedAt: secondAt
        )
        let finalWidgetBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: widgetInput,
                row: 0,
                col: 0,
                now: thirdAt
            ),
            scenario
        )
        let finalPoints = crossEntryPoints(initialCompleted: initialCompleted, transition: 3)
        assertWidgetCrossEntryState(
            board: finalWidgetBoard,
            completed: !initialCompleted,
            points: finalPoints,
            scenario: "\(scenario) Widget repeat"
        )

        try loadGlobalCrossEntryPoints(into: harness.pointsRepository, scenario: scenario)
        viewModel.applySavedBoardSnapshot(
            finalWidgetBoard.board,
            countdownEndsAt: finalWidgetBoard.countdownEndsAt,
            referenceDate: thirdAt,
            reloadPersistedPoints: true
        )
        assertAppCrossEntryState(
            viewModel: viewModel,
            repository: harness.pointsRepository,
            completed: !initialCompleted,
            points: finalPoints,
            scenario: "\(scenario) final App reload"
        )
    }

    private func assertRemovedTaskRejectsBothEntries(
        board: BingoBoardStore.NamedBoard,
        now: Date,
        scenario: String
    ) throws {
        let harness = makeInMemoryViewModelHarness(
            savedBoard: nil,
            totalPoints: 20,
            lifetimePoints: 30,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        viewModel.applySavedBoardSnapshot(
            board.board,
            countdownEndsAt: board.countdownEndsAt,
            referenceDate: now
        )
        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(1))
        assertAppCrossEntryState(
            viewModel: viewModel,
            repository: harness.pointsRepository,
            completed: false,
            points: CrossEntryPointExpectation(total: 20, lifetime: 30),
            scenario: "\(scenario) removed App task"
        )
        XCTAssertNil(
            WidgetTaskToggleService.toggled(
                board: board,
                row: 0,
                col: 0,
                now: now.addingTimeInterval(2)
            ),
            scenario
        )
        assertGlobalCrossEntryPoints(
            CrossEntryPointExpectation(total: 20, lifetime: 30),
            scenario: "\(scenario) removed Widget task"
        )
    }

    private func crossEntryPoints(
        initialCompleted: Bool,
        transition: Int
    ) -> CrossEntryPointExpectation {
        switch (initialCompleted, transition) {
        case (false, 1): return CrossEntryPointExpectation(total: 21, lifetime: 31)
        case (false, 2): return CrossEntryPointExpectation(total: 20, lifetime: 31)
        case (false, 3): return CrossEntryPointExpectation(total: 21, lifetime: 32)
        case (true, 1): return CrossEntryPointExpectation(total: 19, lifetime: 30)
        case (true, 2): return CrossEntryPointExpectation(total: 20, lifetime: 31)
        case (true, 3): return CrossEntryPointExpectation(total: 19, lifetime: 31)
        default:
            XCTFail("Unexpected cross-entry transition \(transition)")
            return CrossEntryPointExpectation(total: 20, lifetime: 30)
        }
    }

    private func replacingCrossEntryBoard(
        _ namedBoard: BingoBoardStore.NamedBoard,
        with board: SavedBoard,
        updatedAt: Date
    ) -> BingoBoardStore.NamedBoard {
        var updatedBoard = namedBoard
        updatedBoard.board = board
        updatedBoard.updatedAt = updatedAt
        return updatedBoard
    }

    private func persistAppCrossEntryPointsToGlobal(
        _ repository: InMemoryBingoPointsRepository,
        scenario: String
    ) throws {
        let total = try XCTUnwrap(repository.loadTotalPoints(), scenario)
        let lifetime = try XCTUnwrap(repository.loadLifetimePoints(), scenario)
        let rewardState = try XCTUnwrap(repository.loadDailyRewardState(), scenario)
        XCTAssertTrue(PointsStore.saveState(
            totalPoints: total,
            lifetimePoints: lifetime,
            dailyRewardState: rewardState
        ), scenario)
    }

    private func loadGlobalCrossEntryPoints(
        into repository: InMemoryBingoPointsRepository,
        scenario: String
    ) throws {
        let total = try XCTUnwrap(PointsStore.loadTotalPoints(), scenario)
        let lifetime = try XCTUnwrap(PointsStore.loadLifetimePoints(), scenario)
        let rewardState = try XCTUnwrap(PointsStore.loadDailyRewardState(), scenario)
        XCTAssertTrue(repository.saveState(
            totalPoints: total,
            lifetimePoints: lifetime,
            dailyRewardState: rewardState
        ), scenario)
    }

    private func assertAppCrossEntryState(
        viewModel: BingoViewModel,
        repository: InMemoryBingoPointsRepository,
        completed: Bool,
        points: CrossEntryPointExpectation,
        scenario: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(viewModel.cells[0][0].isCompleted, completed, scenario, file: file, line: line)
        XCTAssertEqual(viewModel.totalPoints, points.total, scenario, file: file, line: line)
        XCTAssertEqual(repository.loadTotalPoints(), points.total, scenario, file: file, line: line)
        XCTAssertEqual(repository.loadLifetimePoints(), points.lifetime, scenario, file: file, line: line)
    }

    private func assertWidgetCrossEntryState(
        board: BingoBoardStore.NamedBoard,
        completed: Bool,
        points: CrossEntryPointExpectation,
        scenario: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(board.board.cells[0][0].isCompleted, completed, scenario, file: file, line: line)
        assertGlobalCrossEntryPoints(points, scenario: scenario, file: file, line: line)
    }

    private func assertGlobalCrossEntryPoints(
        _ points: CrossEntryPointExpectation,
        scenario: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(PointsStore.loadTotalPoints(), points.total, scenario, file: file, line: line)
        XCTAssertEqual(PointsStore.loadLifetimePoints(), points.lifetime, scenario, file: file, line: line)
    }
}

final class WidgetTaskEventMergeTests: XCTestCase {
    func testNewerWidgetToggleDoesNotOverwriteConcurrentTaskEdit() throws {
        let baseSavedAt = makeDate(year: 2026, month: 7, day: 12, hour: 15)
        let appEditAt = baseSavedAt.addingTimeInterval(1)
        let widgetSavedAt = baseSavedAt.addingTimeInterval(2)
        var baseCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        baseCells[0][0] = BingoCell(text: "Original task")
        let baseBoard = makeNamedBoard(cells: baseCells, updatedAt: baseSavedAt)

        var widgetCells = baseCells
        widgetCells[0][0].isCompleted = true
        widgetCells[0][0].completionStreakCount = 1
        widgetCells[0][0].lastCompletedAt = widgetSavedAt
        let widgetSnapshot = makeNamedBoard(cells: widgetCells, updatedAt: widgetSavedAt)
        let widgetBoard = BingoBoardStore.NamedBoard(
            id: baseBoard.id,
            name: baseBoard.name,
            board: widgetSnapshot.board,
            lastTaskResetAppliedAt: baseBoard.lastTaskResetAppliedAt,
            updatedAt: widgetSavedAt
        )

        var editedCells = baseCells
        editedCells[0][0].text = "Edited in App"
        let editedSnapshot = makeNamedBoard(cells: editedCells, updatedAt: appEditAt)
        let editedBoard = BingoBoardStore.NamedBoard(
            id: baseBoard.id,
            name: baseBoard.name,
            board: editedSnapshot.board,
            lastTaskResetAppliedAt: baseBoard.lastTaskResetAppliedAt,
            updatedAt: appEditAt
        )
        let mutation = try XCTUnwrap(
            WidgetTaskToggleService.cellMutation(
                previousBoard: baseBoard.board,
                updatedBoard: widgetBoard.board,
                row: 0,
                col: 0
            )
        )
        let event = WidgetTaskSyncStore.Event(
            boardID: baseBoard.id,
            board: widgetBoard,
            savedAt: widgetSavedAt,
            didApplyBoardReset: false,
            cellMutation: mutation
        )
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: baseBoard.id,
            boards: [editedBoard]
        )

        let merged = WidgetTaskEventMerge.applying(event, to: snapshot)

        XCTAssertEqual(merged, snapshot)
        XCTAssertEqual(merged.boards[0].board.fullBoardCells?[0][0].storedTaskText, "Edited in App")
        XCTAssertFalse(merged.boards[0].board.fullBoardCells?[0][0].isCompleted == true)
    }

    func testResetEventPreservesConcurrentTaskDefinition() throws {
        let previousReset = makeDate(year: 2026, month: 7, day: 11, hour: 3)
        let resetAt = makeDate(year: 2026, month: 7, day: 12, hour: 3)
        var currentCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        currentCells[0][0] = BingoCell(text: "Edited task", isCompleted: true)
        let currentSnapshot = makeNamedBoard(
            cells: currentCells,
            mode: .resetStatusNextDay,
            lastTaskResetAppliedAt: previousReset,
            updatedAt: resetAt.addingTimeInterval(-1)
        )
        var eventBoard = currentSnapshot
        eventBoard.lastTaskResetAppliedAt = resetAt
        eventBoard.updatedAt = resetAt
        let event = WidgetTaskSyncStore.Event(
            boardID: currentSnapshot.id,
            board: eventBoard,
            savedAt: resetAt,
            didApplyBoardReset: true
        )

        let merged = WidgetTaskEventMerge.applying(
            event,
            to: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: currentSnapshot.id,
                boards: [currentSnapshot]
            )
        )

        let mergedCell = try XCTUnwrap(merged.boards.first?.board.fullBoardCells?[0][0])
        XCTAssertEqual(mergedCell.storedTaskText, "Edited task")
        XCTAssertFalse(mergedCell.isCompleted)
        XCTAssertEqual(merged.boards.first?.lastTaskResetAppliedAt, resetAt)
    }

    func testCellMutationMergesConcurrentDifferentCellAndPreservesAppSelection() throws {
        let baseSavedAt = makeDate(year: 2026, month: 7, day: 12, hour: 9)
        let widgetSavedAt = baseSavedAt.addingTimeInterval(1)
        let appSavedAt = baseSavedAt.addingTimeInterval(2)
        var baseCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        baseCells[0][0] = BingoCell(text: "Widget task")
        baseCells[0][1] = BingoCell(text: "App task")
        let baseBoard = makeNamedBoard(cells: baseCells, updatedAt: baseSavedAt)

        var widgetCells = baseCells
        widgetCells[0][0].isCompleted = true
        widgetCells[0][0].completionStreakCount = 1
        widgetCells[0][0].lastCompletedAt = widgetSavedAt
        var widgetBoard = makeNamedBoard(cells: widgetCells, updatedAt: widgetSavedAt)
        widgetBoard = BingoBoardStore.NamedBoard(
            id: baseBoard.id,
            name: baseBoard.name,
            board: widgetBoard.board,
            taskResetMode: baseBoard.taskResetMode,
            lastTaskResetAppliedAt: baseBoard.lastTaskResetAppliedAt,
            updatedAt: widgetSavedAt
        )

        var appCells = baseCells
        appCells[0][1].isCompleted = true
        appCells[0][1].completionStreakCount = 1
        appCells[0][1].lastCompletedAt = appSavedAt
        var currentBoard = makeNamedBoard(cells: appCells, updatedAt: appSavedAt)
        currentBoard = BingoBoardStore.NamedBoard(
            id: baseBoard.id,
            name: baseBoard.name,
            board: currentBoard.board,
            taskResetMode: baseBoard.taskResetMode,
            lastTaskResetAppliedAt: baseBoard.lastTaskResetAppliedAt,
            updatedAt: appSavedAt
        )
        let selectedBoard = makeNamedBoard(updatedAt: appSavedAt)
        let mutation = try XCTUnwrap(
            WidgetTaskToggleService.cellMutation(
                previousBoard: baseBoard.board,
                updatedBoard: widgetBoard.board,
                row: 0,
                col: 0
            )
        )
        let event = WidgetTaskSyncStore.Event(
            boardID: baseBoard.id,
            board: widgetBoard,
            savedAt: widgetSavedAt,
            didApplyBoardReset: false,
            cellMutation: mutation
        )

        let merged = WidgetTaskEventMerge.applying(
            event,
            to: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: selectedBoard.id,
                boards: [currentBoard, selectedBoard]
            )
        )

        let mergedBoard = try XCTUnwrap(merged.boards.first(where: { $0.id == baseBoard.id }))
        XCTAssertTrue(mergedBoard.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertTrue(mergedBoard.board.fullBoardCells?[0][1].isCompleted == true)
        XCTAssertEqual(merged.selectedBoardID, selectedBoard.id)
        XCTAssertEqual(mergedBoard.updatedAt, appSavedAt)
    }

    func testCellMutationFallsBackToCoordinatesWhenLegacyCellIDDiffers() throws {
        let baseSavedAt = makeDate(year: 2026, month: 7, day: 12, hour: 10)
        let widgetSavedAt = baseSavedAt.addingTimeInterval(1)
        var sourceCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        sourceCells[0][0] = BingoCell(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            text: "Shared task"
        )
        let sourceBoard = makeNamedBoard(cells: sourceCells, updatedAt: baseSavedAt)
        let completedSourceBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: sourceBoard,
                row: 0,
                col: 0,
                now: widgetSavedAt,
                commitSideEffects: false
            )
        )
        let mutation = try XCTUnwrap(
            WidgetTaskToggleService.cellMutation(
                previousBoard: sourceBoard.board,
                updatedBoard: completedSourceBoard.board,
                row: 0,
                col: 0
            )
        )

        let destinationCellID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        var destinationCells = sourceCells
        destinationCells[0][0] = BingoCell(id: destinationCellID, text: "Shared task")
        var destinationBoard = makeNamedBoard(cells: destinationCells, updatedAt: baseSavedAt)
        destinationBoard = BingoBoardStore.NamedBoard(
            id: sourceBoard.id,
            name: sourceBoard.name,
            board: destinationBoard.board,
            taskResetMode: sourceBoard.taskResetMode,
            lastTaskResetAppliedAt: sourceBoard.lastTaskResetAppliedAt,
            updatedAt: baseSavedAt
        )
        let event = WidgetTaskSyncStore.Event(
            boardID: sourceBoard.id,
            board: completedSourceBoard,
            savedAt: widgetSavedAt,
            didApplyBoardReset: false,
            cellMutation: mutation
        )

        let merged = WidgetTaskEventMerge.applying(
            event,
            to: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: destinationBoard.id,
                boards: [destinationBoard]
            )
        )

        let mergedCell = try XCTUnwrap(merged.boards.first?.board.fullBoardCells?[0][0])
        XCTAssertEqual(mergedCell.id, destinationCellID)
        XCTAssertEqual(mergedCell.storedTaskText, "Shared task")
        XCTAssertTrue(mergedCell.isCompleted)
        XCTAssertEqual(mutation.row, 0)
        XCTAssertEqual(mutation.col, 0)
    }

    func testCoordinateFallbackRejectsAReplacedTaskWithDifferentIdentityAndDefinition() throws {
        let baseSavedAt = makeDate(year: 2026, month: 7, day: 12, hour: 11)
        var sourceCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        sourceCells[0][0] = BingoCell(text: "Old task")
        let sourceBoard = makeNamedBoard(cells: sourceCells, updatedAt: baseSavedAt)
        let completedSourceBoard = try XCTUnwrap(
            WidgetTaskToggleService.toggled(
                board: sourceBoard,
                row: 0,
                col: 0,
                now: baseSavedAt.addingTimeInterval(1),
                commitSideEffects: false
            )
        )
        let mutation = try XCTUnwrap(
            WidgetTaskToggleService.cellMutation(
                previousBoard: sourceBoard.board,
                updatedBoard: completedSourceBoard.board,
                row: 0,
                col: 0
            )
        )

        var destinationCells = sourceCells
        destinationCells[0][0] = BingoCell(text: "Replacement task")
        var destinationBoard = makeNamedBoard(cells: destinationCells, updatedAt: baseSavedAt)
        destinationBoard = BingoBoardStore.NamedBoard(
            id: sourceBoard.id,
            name: sourceBoard.name,
            board: destinationBoard.board,
            taskResetMode: sourceBoard.taskResetMode,
            lastTaskResetAppliedAt: sourceBoard.lastTaskResetAppliedAt,
            updatedAt: baseSavedAt
        )
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: destinationBoard.id,
            boards: [destinationBoard]
        )
        let event = WidgetTaskSyncStore.Event(
            boardID: sourceBoard.id,
            board: completedSourceBoard,
            savedAt: baseSavedAt.addingTimeInterval(1),
            didApplyBoardReset: false,
            cellMutation: mutation
        )

        XCTAssertEqual(WidgetTaskEventMerge.applying(event, to: snapshot), snapshot)
    }

    func testTaskEventPreservesCurrentBoardRules() throws {
        let ruleSavedAt = makeDate(year: 2026, month: 6, day: 30, hour: 9)
        let widgetSavedAt = makeDate(year: 2026, month: 6, day: 30, hour: 9, minute: 1)
        var currentBoard = makeNamedBoard(
            mode: .clearTasksNextDay,
            customResetMinutes: 4 * 60,
            lastTaskResetAppliedAt: ruleSavedAt,
            updatedAt: ruleSavedAt
        )
        var staleWidgetBoard = currentBoard
        staleWidgetBoard.taskResetMode = .resetStatusNextDay
        staleWidgetBoard.customResetMinutes = nil
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Widget task", isCompleted: true, lastCompletedAt: widgetSavedAt)
        staleWidgetBoard.board = makeNamedBoard(cells: cells, updatedAt: widgetSavedAt).board
        staleWidgetBoard.updatedAt = widgetSavedAt
        let event = WidgetTaskSyncStore.Event(
            boardID: currentBoard.id,
            board: staleWidgetBoard,
            savedAt: widgetSavedAt,
            didApplyBoardReset: false
        )

        let merged = WidgetTaskEventMerge.applying(
            event,
            to: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: currentBoard.id,
                boards: [currentBoard]
            )
        )

        currentBoard = try XCTUnwrap(merged.boards.first)
        XCTAssertTrue(currentBoard.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertEqual(currentBoard.taskResetMode, .clearTasksNextDay)
        XCTAssertEqual(currentBoard.customResetMinutes, 4 * 60)
        XCTAssertEqual(currentBoard.lastTaskResetAppliedAt, ruleSavedAt)
    }

    func testResetEventUpdatesResetAnchorButKeepsRuleConfiguration() throws {
        let previousReset = makeDate(year: 2026, month: 6, day: 29, hour: 3)
        let widgetReset = makeDate(year: 2026, month: 6, day: 30, hour: 3)
        var currentBoard = makeNamedBoard(
            mode: .clearTasksNextDay,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousReset,
            updatedAt: previousReset
        )
        var eventBoard = currentBoard
        eventBoard.lastTaskResetAppliedAt = widgetReset
        eventBoard.countdownEndsAt = nil
        eventBoard.updatedAt = widgetReset
        let event = WidgetTaskSyncStore.Event(
            boardID: currentBoard.id,
            board: eventBoard,
            savedAt: widgetReset,
            didApplyBoardReset: true
        )

        let merged = WidgetTaskEventMerge.applying(
            event,
            to: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: currentBoard.id,
                boards: [currentBoard]
            )
        )

        currentBoard = try XCTUnwrap(merged.boards.first)
        XCTAssertEqual(currentBoard.taskResetMode, .clearTasksNextDay)
        XCTAssertEqual(currentBoard.customResetMinutes, 3 * 60)
        XCTAssertEqual(currentBoard.lastTaskResetAppliedAt, widgetReset)
    }

    func testTaskEventDoesNotResurrectDeletedBoard() {
        let now = makeDate(year: 2026, month: 6, day: 30, hour: 11)
        let deletedBoard = makeNamedBoard(updatedAt: now)
        let event = WidgetTaskSyncStore.Event(
            boardID: deletedBoard.id,
            board: deletedBoard,
            savedAt: now,
            didApplyBoardReset: false
        )
        let remainingBoard = makeNamedBoard(updatedAt: now)
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: remainingBoard.id,
            boards: [remainingBoard]
        )

        XCTAssertEqual(WidgetTaskEventMerge.applying(event, to: snapshot), snapshot)
    }
}


final class PointRedemptionReconcilerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistenceSideEffects()
    }

    override func tearDown() {
        clearPersistenceSideEffects()
        super.tearDown()
    }

    func testLegacyAggregateMigrationPreservesExactTotalSpend() throws {
        let reward = CustomReward(
            title: "Legacy reward",
            requiredPoints: 30,
            redemptionCount: 3,
            totalSpentPoints: 20
        )
        StickerStore.saveInventoryCounts([.cowCat: 1])
        RewardStore.saveRewards([reward])

        let records = try XCTUnwrap(
            PointRedemptionLedger.loadOrMigrate(
                stickerInventoryCounts: StickerStore.loadInventoryCounts(),
                customRewards: RewardStore.loadRewards()
            )
        )
        let rewardRecords = records.filter { $0.referencedCustomRewardID == reward.id && $0.isActive }

        XCTAssertEqual(rewardRecords.count, 3)
        XCTAssertEqual(rewardRecords.reduce(0) { $0 + $1.points }, 20)
        XCTAssertEqual(records.filter { $0.referencedStickerKind == .cowCat && $0.isActive }.count, 1)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettings.pointRedemptionLedgerInitializedKey))
    }

    func testLedgerRevocationUsesActualRedemptionPriceAfterRewardPriceChanges() throws {
        let rewardID = UUID()
        let earlyRecord = PointRedemptionRecord(
            itemKind: .customReward,
            title: "Flexible reward",
            points: 5,
            redeemedAt: makeDate(year: 2026, month: 7, day: 10, hour: 9),
            itemReferenceID: PointRedemptionRecord.customRewardReferenceID(rewardID)
        )
        let expensiveRecord = PointRedemptionRecord(
            itemKind: .customReward,
            title: "Flexible reward",
            points: 20,
            redeemedAt: makeDate(year: 2026, month: 7, day: 11, hour: 9),
            itemReferenceID: PointRedemptionRecord.customRewardReferenceID(rewardID)
        )
        let reward = CustomReward(
            id: rewardID,
            title: "Flexible reward",
            requiredPoints: 50,
            redemptionCount: 2,
            totalSpentPoints: 25
        )

        let result = PointRedemptionReconciler.reconcileRedemptionsIfNeeded(
            totalPoints: 5,
            stickerInventoryCounts: [:],
            homeStickerPlacements: [],
            customRewards: [reward],
            redemptionRecords: [earlyRecord, expensiveRecord],
            now: makeDate(year: 2026, month: 7, day: 12, hour: 9)
        )

        let updatedReward = try XCTUnwrap(result.customRewards.first)
        XCTAssertEqual(updatedReward.redemptionCount, 1)
        XCTAssertEqual(updatedReward.totalSpentPoints, 5)
        XCTAssertTrue(result.redemptionRecords?.first(where: { $0.id == earlyRecord.id })?.isActive == true)
        XCTAssertFalse(result.redemptionRecords?.first(where: { $0.id == expensiveRecord.id })?.isActive == true)
    }

    @MainActor
    func testLedgerRepairsCorruptedRewardAggregatesOnReload() throws {
        let reward = CustomReward(title: "Break", requiredPoints: 10)
        RewardStore.saveRewards([reward])
        let firstStore = PointsFeatureStore()

        firstStore.redeemReward(reward, totalPoints: 100)
        var repricedReward = try XCTUnwrap(firstStore.customRewards.first)
        repricedReward.requiredPoints = 20
        firstStore.updateReward(repricedReward)
        firstStore.redeemReward(repricedReward, totalPoints: 100)

        var corruptedReward = try XCTUnwrap(firstStore.customRewards.first)
        corruptedReward.redemptionCount = 0
        corruptedReward.totalSpentPoints = 0
        RewardStore.saveRewards([corruptedReward])

        let recoveredStore = PointsFeatureStore()
        let recoveredReward = try XCTUnwrap(recoveredStore.customRewards.first)
        XCTAssertEqual(recoveredReward.redemptionCount, 2)
        XCTAssertEqual(recoveredReward.totalSpentPoints, 30)
        XCTAssertEqual(recoveredStore.redemptionHistory.count, 2)
    }

    func testReconcileRevokesStickersAndCustomRewardsWhenPointsDropBelowSpent() throws {
        let stickerPlacement = HomeStickerPlacement(kind: .cowCat, xRatio: 0.25, yRatio: 0.4)
        let reward = CustomReward(
            title: "Snack",
            requiredPoints: 10,
            redemptionCount: 2,
            totalSpentPoints: 20
        )

        let result = PointRedemptionReconciler.reconcileRedemptionsIfNeeded(
            totalPoints: 0,
            stickerInventoryCounts: [.cowCat: 1],
            homeStickerPlacements: [stickerPlacement],
            customRewards: [reward]
        )

        XCTAssertTrue(result.didRevokeStickers)
        XCTAssertTrue(result.didRevokeCustomRewards)
        XCTAssertEqual(result.stickerInventoryCounts[.cowCat, default: 0], 0)
        XCTAssertTrue(result.homeStickerPlacements.isEmpty)
        let updatedReward = try XCTUnwrap(result.customRewards.first)
        XCTAssertEqual(updatedReward.redemptionCount, 0)
        XCTAssertEqual(updatedReward.totalSpentPoints, 0)
    }

    func testReconcileKeepsRedemptionsWhenPointsStillCoverSpent() throws {
        let stickerPlacement = HomeStickerPlacement(kind: .cowCat, xRatio: 0.25, yRatio: 0.4)
        let reward = CustomReward(
            title: "Snack",
            requiredPoints: 10,
            redemptionCount: 1,
            totalSpentPoints: 10
        )

        let result = PointRedemptionReconciler.reconcileRedemptionsIfNeeded(
            totalPoints: 25,
            stickerInventoryCounts: [.cowCat: 1],
            homeStickerPlacements: [stickerPlacement],
            customRewards: [reward]
        )

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.stickerInventoryCounts[.cowCat, default: 0], 1)
        XCTAssertEqual(result.homeStickerPlacements, [stickerPlacement])
        let updatedReward = try XCTUnwrap(result.customRewards.first)
        XCTAssertEqual(updatedReward.redemptionCount, 1)
        XCTAssertEqual(updatedReward.totalSpentPoints, 10)
    }
}

final class BingoRewardSettlementTests: XCTestCase {
    func testNormalSettlementRepairsLedgerWithoutReplayingBoardPoints() throws {
        let now = makeDate(year: 2026, month: 6, day: 29, hour: 9)
        let firstCellID = UUID()
        let secondCellID = UUID()
        let previousState = DailyRewardState(
            dateKey: PointsStore.dateKey(for: now),
            rewardedCellIDs: [firstCellID],
            peakCompletedLineCount: 0,
            fullBoardRewardGranted: false
        )
        let updatedCells = [
            [
                BingoCell(id: firstCellID, text: "Existing", isCompleted: true),
                BingoCell(id: secondCellID, text: "New", isCompleted: true)
            ]
        ]

        let completedOutput = BingoRewardSettlement.settle(
            input: BingoRewardSettlementInput(
                date: now,
                cells: updatedCells,
                completedLines: [],
                isBoardFullyCompleted: false,
                totalPoints: 0,
                lifetimePoints: 0,
                dailyRewardState: previousState
            ),
            mode: .normal
        )

        XCTAssertEqual(completedOutput.totalPoints, 0)
        XCTAssertEqual(completedOutput.lifetimePoints, 0)
        XCTAssertEqual(completedOutput.dailyRewardState.rewardedCellIDs, [firstCellID, secondCellID])

        let undoOutput = BingoRewardSettlement.settle(
            input: BingoRewardSettlementInput(
                date: now,
                cells: [[BingoCell(id: firstCellID, text: "Existing", isCompleted: true)]],
                completedLines: [],
                isBoardFullyCompleted: false,
                totalPoints: completedOutput.totalPoints,
                lifetimePoints: completedOutput.lifetimePoints,
                dailyRewardState: completedOutput.dailyRewardState
            ),
            mode: .normal
        )

        XCTAssertEqual(undoOutput.totalPoints, 0)
        XCTAssertEqual(undoOutput.lifetimePoints, 0)
        XCTAssertEqual(undoOutput.dailyRewardState.rewardedCellIDs, [firstCellID])
    }

    func testTaskToggleUsesActualBoardTransitionWhenSavedLedgerIsStale() {
        let now = makeDate(year: 2026, month: 7, day: 20, hour: 12)
        let cellID = UUID()
        let staleLedger = DailyRewardState(
            dateKey: PointsStore.dateKey(for: now),
            rewardedCellIDs: [cellID],
            peakCompletedLineCount: 0,
            fullBoardRewardGranted: false
        )
        let previousCells = [[BingoCell(id: cellID, text: "Focus")]]
        let currentCells = [[BingoCell(id: cellID, text: "Focus", isCompleted: true)]]

        let output = BingoRewardSettlement.settleTaskToggle(
            date: now,
            previousCells: previousCells,
            previousCompletedLines: [],
            previousIsBoardFullyCompleted: false,
            currentCells: currentCells,
            currentCompletedLines: [],
            currentIsBoardFullyCompleted: false,
            totalPoints: 337,
            lifetimePoints: 773,
            dailyRewardState: staleLedger
        )

        XCTAssertEqual(output.totalPoints, 338)
        XCTAssertEqual(output.lifetimePoints, 774)
        XCTAssertEqual(output.dailyRewardState.rewardedCellIDs, [cellID])
    }

    func testExplicitCompletionNeverLosesPointsWhenImportedLineCacheRegresses() {
        let now = makeDate(year: 2026, month: 7, day: 20, hour: 12)
        let first = BingoCell(text: "One", isCompleted: true)
        let second = BingoCell(text: "Two", isCompleted: true)
        let third = BingoCell(text: "Three", isCompleted: true)
        let fourth = BingoCell(text: "Four")
        let fifth = BingoCell(text: "Five", isCompleted: true)

        // This models a stale imported line cache: the new task is completed,
        // but the cached line set temporarily drops a line from the prior board.
        let output = BingoRewardSettlement.settleTaskToggle(
            date: now,
            previousCells: [[first, second, third, fourth]],
            previousCompletedLines: [.row(0)],
            previousIsBoardFullyCompleted: false,
            currentCells: [[first, second, third, fourth], [fifth]],
            currentCompletedLines: [],
            currentIsBoardFullyCompleted: false,
            totalPoints: 362,
            lifetimePoints: 799,
            dailyRewardState: DailyRewardState(dateKey: PointsStore.dateKey(for: now)),
            taskIsNowCompleted: true
        )

        XCTAssertEqual(output.totalPoints, 363)
        XCTAssertEqual(output.lifetimePoints, 800)
    }

    func testInitialRewardStateRebuildsWhenSavedStateDoesNotMatchBoardStatus() {
        let now = makeDate(year: 2026, month: 7, day: 20, hour: 12)
        let cellID = UUID()
        let recovered = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: now,
            boardLastSavedAt: now,
            currentCells: [[BingoCell(id: cellID, text: "Focus")]],
            currentCompletedLines: [],
            isBoardFullyCompleted: false,
            savedDailyRewardState: DailyRewardState(
                dateKey: PointsStore.dateKey(for: now),
                rewardedCellIDs: [cellID],
                peakCompletedLineCount: 0,
                fullBoardRewardGranted: false
            )
        )

        XCTAssertTrue(recovered.rewardedCellIDs.isEmpty)
        XCTAssertEqual(recovered.peakCompletedLineCount, 0)
    }
}

final class TaskRecurrenceRuleTests: XCTestCase {
    func testBoardCompletionRegistersOnlyNewCompletionTransitions() {
        let previousCompletion = makeDate(year: 2026, month: 6, day: 16, hour: 1)
        let afterCustomReset = makeDate(year: 2026, month: 6, day: 16, hour: 4)
        let cells = [[
            BingoCell(
                text: "Already complete",
                isCompleted: true,
                completionStreakCount: 1,
                lastCompletedAt: previousCompletion
            ),
            BingoCell(
                text: "Reset to incomplete",
                isCompleted: false,
                completionStreakCount: 1,
                lastCompletedAt: previousCompletion
            )
        ]]

        let result = BoardEngine.resolveExpiredBoardCountdown(
            in: cells,
            resolution: .markAsCompleted,
            now: afterCustomReset,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
            calendar: fixedCalendar
        )

        XCTAssertEqual(result.cells[0][0].completionStreakCount, 1)
        XCTAssertEqual(result.cells[0][0].lastCompletedAt, previousCompletion)
        XCTAssertEqual(result.cells[0][1].completionStreakCount, 2)
        XCTAssertEqual(result.cells[0][1].lastCompletedAt, afterCustomReset)
    }

    func testMonthlyDayRecurrenceOnlyShowsOnConfiguredDay() {
        let anchor = makeDate(year: 2026, month: 6, day: 16)
        let activeDay = makeDate(year: 2026, month: 7, day: 16)
        let inactiveDay = makeDate(year: 2026, month: 7, day: 15)
        let cell = BingoCell(
            text: "Pay rent",
            residentTaskText: "Pay rent",
            recurrenceRule: TaskRecurrenceRule(kind: .monthlyDay, monthDay: 16, anchorDate: anchor)
        )

        let activeProjection = cell.projectedForDisplay(on: activeDay, calendar: fixedCalendar)
        let inactiveProjection = cell.projectedForDisplay(on: inactiveDay, calendar: fixedCalendar)

        XCTAssertEqual(activeProjection.text, "Pay rent")
        XCTAssertFalse(activeProjection.isDisplayOnlyInactive)
        XCTAssertEqual(inactiveProjection.text, "Pay rent")
        XCTAssertTrue(inactiveProjection.isDisplayOnlyInactive)
    }

    func testMonthlyDayThirtyOneSkipsShorterMonths() {
        let anchor = makeDate(year: 2026, month: 1, day: 31)
        let activeDay = makeDate(year: 2026, month: 3, day: 31)
        let shortMonthDay = makeDate(year: 2026, month: 2, day: 28)
        let cell = BingoCell(
            text: "Close books",
            residentTaskText: "Close books",
            recurrenceRule: TaskRecurrenceRule(kind: .monthlyDay, monthDay: 31, anchorDate: anchor)
        )

        let activeProjection = cell.projectedForDisplay(on: activeDay, calendar: fixedCalendar)
        let inactiveProjection = cell.projectedForDisplay(on: shortMonthDay, calendar: fixedCalendar)

        XCTAssertEqual(activeProjection.text, "Close books")
        XCTAssertFalse(activeProjection.isDisplayOnlyInactive)
        XCTAssertEqual(inactiveProjection.text, "Close books")
        XCTAssertTrue(inactiveProjection.isDisplayOnlyInactive)
    }

    func testWeeklyRecurrenceDoesNotRequireAnchorDate() {
        let defaultAnchor = makeDate(year: 2026, month: 6, day: 17)
        let matchingDayBeforeDefaultAnchor = makeDate(year: 2026, month: 6, day: 16)
        let weekday = fixedCalendar.component(.weekday, from: matchingDayBeforeDefaultAnchor)
        let rule = TaskRecurrenceRule(kind: .weekly, weekdays: [weekday]).normalized(
            defaultWeekday: weekday,
            defaultMonthDay: 17,
            defaultAnchorDate: defaultAnchor
        )

        XCTAssertNil(rule.anchorDate)
        XCTAssertTrue(rule.isActive(on: matchingDayBeforeDefaultAnchor, calendar: fixedCalendar))
    }

    func testMonthlyRecurrenceDoesNotRequireAnchorDate() {
        let defaultAnchor = makeDate(year: 2026, month: 6, day: 17)
        let matchingDayBeforeDefaultAnchor = makeDate(year: 2026, month: 6, day: 16)
        let rule = TaskRecurrenceRule(kind: .monthlyDay, monthDay: 16).normalized(
            defaultWeekday: 4,
            defaultMonthDay: 17,
            defaultAnchorDate: defaultAnchor
        )

        XCTAssertNil(rule.anchorDate)
        XCTAssertTrue(rule.isActive(on: matchingDayBeforeDefaultAnchor, calendar: fixedCalendar))
    }

    func testEveryNDaysRecurrenceUsesAnchorDate() {
        let anchor = makeDate(year: 2026, month: 6, day: 1)
        let activeDay = makeDate(year: 2026, month: 6, day: 7)
        let inactiveDay = makeDate(year: 2026, month: 6, day: 5)
        let cell = BingoCell(
            text: "Water plants",
            residentTaskText: "Water plants",
            recurrenceRule: TaskRecurrenceRule(kind: .everyNDays, interval: 3, anchorDate: anchor)
        )

        let activeProjection = cell.projectedForDisplay(on: activeDay, calendar: fixedCalendar)
        let inactiveProjection = cell.projectedForDisplay(on: inactiveDay, calendar: fixedCalendar)

        XCTAssertEqual(activeProjection.text, "Water plants")
        XCTAssertFalse(activeProjection.isDisplayOnlyInactive)
        XCTAssertEqual(inactiveProjection.text, "Water plants")
        XCTAssertTrue(inactiveProjection.isDisplayOnlyInactive)
    }

    func testEveryNDaysRecurrenceDoesNotShowBeforeAnchorDate() {
        let anchor = makeDate(year: 2026, month: 6, day: 10)
        let beforeAnchor = makeDate(year: 2026, month: 6, day: 9)
        let cell = BingoCell(
            text: "Water plants",
            residentTaskText: "Water plants",
            recurrenceRule: TaskRecurrenceRule(kind: .everyNDays, interval: 2, anchorDate: anchor)
        )

        let anchorProjection = cell.projectedForDisplay(on: anchor, calendar: fixedCalendar)
        let beforeAnchorProjection = cell.projectedForDisplay(on: beforeAnchor, calendar: fixedCalendar)

        XCTAssertEqual(anchorProjection.text, "Water plants")
        XCTAssertFalse(anchorProjection.isDisplayOnlyInactive)
        XCTAssertEqual(beforeAnchorProjection.text, "Water plants")
        XCTAssertTrue(beforeAnchorProjection.isDisplayOnlyInactive)
    }

    func testLegacyWeekdayScheduleStillProjectsFromOldFields() {
        let activeDay = makeDate(year: 2026, month: 6, day: 16)
        let inactiveDay = makeDate(year: 2026, month: 6, day: 17)
        let activeWeekday = fixedCalendar.component(.weekday, from: activeDay)
        let cell = BingoCell(
            text: "Drink water",
            residentTaskText: "Drink water",
            residentWeekdays: [activeWeekday]
        )

        XCTAssertNil(cell.recurrenceRule)
        let activeProjection = cell.projectedForDisplay(on: activeDay, calendar: fixedCalendar)
        let inactiveProjection = cell.projectedForDisplay(on: inactiveDay, calendar: fixedCalendar)

        XCTAssertEqual(activeProjection.text, "Drink water")
        XCTAssertFalse(activeProjection.isDisplayOnlyInactive)
        XCTAssertEqual(inactiveProjection.text, "Drink water")
        XCTAssertTrue(inactiveProjection.isDisplayOnlyInactive)
    }

    func testRecurringCompletionPersistsUntilBoardResetRuleChangesState() {
        let anchor = makeDate(year: 2026, month: 6, day: 16)
        let completedDay = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let nextDay = makeDate(year: 2026, month: 6, day: 17, hour: 9)
        let cell = BingoCell(
            text: "Drink water",
            residentTaskText: "Drink water",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: anchor),
            isCompleted: true,
            lastCompletedAt: completedDay
        )

        XCTAssertTrue(cell.projectedForDisplay(on: completedDay, calendar: fixedCalendar).isCompleted)
        XCTAssertTrue(cell.projectedForDisplay(on: nextDay, calendar: fixedCalendar).isCompleted)
    }

    func testRecurringCountdownDoesNotStartOnNewOccurrenceAfterPreviousCompletion() {
        let anchor = makeDate(year: 2026, month: 6, day: 16)
        let previousCompletion = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let currentOccurrence = makeDate(year: 2026, month: 6, day: 17, hour: 9, minute: 5)
        let cell = BingoCell(
            text: "Drink water",
            residentTaskText: "Drink water",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: anchor),
            startVisibleAt: makeDate(year: 2026, month: 6, day: 16, hour: 9),
            endVisibleAt: makeDate(year: 2026, month: 6, day: 16, hour: 10),
            usesRecurringTimeWindow: true,
            isCompleted: true,
            estimatedDurationMinutes: 15,
            lastCompletedAt: previousCompletion
        )

        XCTAssertFalse(cell.shouldStartCountdownForCurrentOccurrence(on: currentOccurrence, calendar: fixedCalendar))
        XCTAssertNil(
            cell.countdownDeadlineForCurrentOccurrence(
                startingAt: currentOccurrence,
                maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
                calendar: fixedCalendar
            )
        )
    }

    func testOneTimeTaskWithStartTimeCanStartCountdown() {
        let start = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 5)
        let cell = BingoCell(
            text: "Focus",
            residentTaskText: "Focus",
            oneTimeVisibleDate: start,
            recurrenceRule: TaskRecurrenceRule(kind: .none, anchorDate: start),
            startVisibleAt: start,
            estimatedDurationMinutes: 15
        )

        XCTAssertTrue(cell.shouldStartCountdownForCurrentOccurrence(on: now, calendar: fixedCalendar))
        XCTAssertEqual(
            cell.countdownDeadlineForCurrentOccurrence(
                startingAt: now,
                maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
                calendar: fixedCalendar
            ),
            makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 20)
        )
    }

    func testSingleTaskWithoutStartTimeStartsCountdownImmediately() {
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 5)
        let cell = BingoCell(
            text: "Focus",
            estimatedDurationMinutes: 15
        )

        XCTAssertTrue(cell.shouldStartCountdownForCurrentOccurrence(on: now, calendar: fixedCalendar))
        XCTAssertEqual(
            cell.countdownDeadlineForCurrentOccurrence(
                startingAt: now,
                maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
                calendar: fixedCalendar
            ),
            makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 20)
        )
    }

    func testRecurringCountdownDoesNotStartOnInactiveDate() {
        let tuesday = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let wednesday = makeDate(year: 2026, month: 6, day: 17, hour: 9, minute: 5)
        let tuesdayWeekday = fixedCalendar.component(.weekday, from: tuesday)
        let cell = BingoCell(
            text: "Drink water",
            residentTaskText: "Drink water",
            recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [tuesdayWeekday]),
            startVisibleAt: tuesday,
            endVisibleAt: makeDate(year: 2026, month: 6, day: 16, hour: 10),
            usesRecurringTimeWindow: true,
            estimatedDurationMinutes: 15
        )

        XCTAssertFalse(cell.shouldStartCountdownForCurrentOccurrence(on: wednesday, calendar: fixedCalendar))
    }

    func testRecurringProjectionHidesStaleCountdownFromPreviousOccurrence() {
        let previousOccurrence = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 5)
        let currentOccurrence = makeDate(year: 2026, month: 6, day: 17, hour: 9, minute: 5)
        let cell = BingoCell(
            text: "Drink water",
            residentTaskText: "Drink water",
            recurrenceRule: TaskRecurrenceRule(kind: .daily),
            countdownEndsAt: previousOccurrence.addingTimeInterval(15 * 60),
            estimatedDurationMinutes: 15
        )

        XCTAssertNil(cell.projectedForDisplay(on: currentOccurrence, calendar: fixedCalendar).countdownEndsAt)
    }

    func testDisplayOnlyInactiveCellsDoNotCountAsCompletedLines() {
        let anchor = makeDate(year: 2026, month: 6, day: 16)
        let inactiveDay = makeDate(year: 2026, month: 6, day: 17)
        let scheduledCell = BingoCell(
            text: "Pay rent",
            residentTaskText: "Pay rent",
            recurrenceRule: TaskRecurrenceRule(kind: .monthlyDay, monthDay: 16, anchorDate: anchor)
        )
        var displayOnlyCell = scheduledCell.projectedForDisplay(on: inactiveDay, calendar: fixedCalendar)
        displayOnlyCell.isCompleted = true
        let cells = [
            [displayOnlyCell, BingoCell(text: "Done", isCompleted: true)],
            [BingoCell(), BingoCell()]
        ]

        XCTAssertTrue(displayOnlyCell.isDisplayOnlyInactive)
        XCTAssertEqual(BoardEngine.completedLines(in: cells, size: 2), [])
    }

    func testSingleCompletedTaskDoesNotGrantFullBoardBonus() {
        let cells = [
            [BingoCell(text: "Done", isCompleted: true), BingoCell()],
            [BingoCell(), BingoCell()]
        ]

        XCTAssertFalse(BoardEngine.isBoardFullyCompleted(cells))
        XCTAssertEqual(BoardEngine.boardScore(cells: cells, completedLines: []), 1)
    }

    func testFullBoardBonusRequiresEveryVisibleCellCompleted() {
        let cells = [
            [BingoCell(text: "One", isCompleted: true), BingoCell(text: "Two", isCompleted: true)],
            [BingoCell(text: "Three", isCompleted: true), BingoCell(text: "Four", isCompleted: true)]
        ]

        XCTAssertTrue(BoardEngine.isBoardFullyCompleted(cells))
        XCTAssertEqual(
            BoardEngine.boardScore(cells: cells, completedLines: BoardEngine.completedLines(in: cells, size: 2)),
            44
        )
    }

    func testClearTasksNextDayClearsRegularTasksAndPreservesPlannedTasks() {
        let yesterday = makeDate(year: 2026, month: 6, day: 15, hour: 10)
        let today = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "One-off note", isCompleted: true, lastCompletedAt: yesterday)
        cells[0][1] = BingoCell(
            text: "Water plants",
            residentTaskText: "Water plants",
            recurrenceRule: TaskRecurrenceRule(kind: .everyNDays, interval: 3, anchorDate: yesterday),
            isCompleted: true,
            isForced: true,
            countdownEndsAt: today.addingTimeInterval(600),
            countdownPausedRemainingSeconds: 300,
            estimatedDurationMinutes: 15,
            lastCompletedAt: yesterday
        )
        let board = makeNamedBoard(
            cells: cells,
            mode: .clearTasksNextDay,
            lastTaskResetAppliedAt: yesterday,
            updatedAt: yesterday
        )

        let updated = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(board, now: today, calendar: fixedCalendar)
        let regularCell = updated.board.fullBoardCells?[0][0]
        let plannedCell = updated.board.fullBoardCells?[0][1]

        XCTAssertEqual(regularCell?.storedTaskText, "")
        XCTAssertEqual(plannedCell?.storedTaskText, "Water plants")
        XCTAssertEqual(plannedCell?.recurrenceRule?.kind, .everyNDays)
        XCTAssertEqual(plannedCell?.isCompleted, false)
        XCTAssertEqual(plannedCell?.isTaskHidden, false)
        XCTAssertEqual(plannedCell?.isForced, false)
        XCTAssertNil(plannedCell?.countdownEndsAt)
        XCTAssertNil(plannedCell?.countdownPausedRemainingSeconds)
        XCTAssertNil(plannedCell?.estimatedDurationMinutes)
    }

    func testRecurringTaskIgnoresLegacyTimeWindowAndRemainsAvailableAllDay() {
        let anchorStart = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let anchorEnd = makeDate(year: 2026, month: 6, day: 16, hour: 10)
        let beforeStart = makeDate(year: 2026, month: 6, day: 17, hour: 8, minute: 59)
        let withinWindow = makeDate(year: 2026, month: 6, day: 17, hour: 9, minute: 30)
        let afterEnd = makeDate(year: 2026, month: 6, day: 17, hour: 10, minute: 1)
        let cell = BingoCell(
            text: "Take meds",
            residentTaskText: "Take meds",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: anchorStart),
            startVisibleAt: anchorStart,
            endVisibleAt: anchorEnd,
            usesRecurringTimeWindow: true
        )

        XCTAssertTrue(cell.isCurrentlyTappable(on: beforeStart, calendar: fixedCalendar))
        XCTAssertTrue(cell.isCurrentlyTappable(on: withinWindow, calendar: fixedCalendar))
        XCTAssertTrue(cell.isCurrentlyTappable(on: afterEnd, calendar: fixedCalendar))
        XCTAssertNil(cell.occurrenceStartVisibleAt(on: withinWindow, calendar: fixedCalendar))
        XCTAssertNil(cell.occurrenceEndVisibleAt(on: withinWindow, calendar: fixedCalendar))
    }

    func testCountdownDeadlineIsCappedByEndTime() {
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 5)
        let cell = BingoCell(
            text: "Focus",
            startVisibleAt: makeDate(year: 2026, month: 6, day: 16, hour: 9),
            endVisibleAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 10),
            estimatedDurationMinutes: 15
        )

        XCTAssertEqual(
            cell.countdownDeadlineForCurrentOccurrence(
                startingAt: now,
                maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
                calendar: fixedCalendar
            ),
            makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 10)
        )
    }

    func testExpiredTaskUsesEarlierOfCountdownAndEndTime() throws {
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 11)
        let cell = BingoCell(
            text: "Focus",
            startVisibleAt: makeDate(year: 2026, month: 6, day: 16, hour: 9),
            endVisibleAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 10),
            countdownEndsAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 30),
            estimatedDurationMinutes: 30
        )
        let candidate = try XCTUnwrap(BoardEngine.expiredTaskCandidate(in: [[cell]], now: now))

        XCTAssertEqual(candidate.expiredAt, makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 10))
    }

    func testExpiredTaskCompletionClearsCountdownConfiguration() throws {
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 11)
        let cell = BingoCell(
            text: "Focus",
            countdownEndsAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 10),
            countdownPausedRemainingSeconds: 300,
            estimatedDurationMinutes: 20
        )
        let candidate = try XCTUnwrap(BoardEngine.expiredTaskCandidate(in: [[cell]], now: now))

        let result = try XCTUnwrap(BoardEngine.resolveExpiredTask(
            in: [[cell]],
            candidate: candidate,
            resolution: .markAsCompleted,
            now: now,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
            calendar: fixedCalendar
        ))
        let updatedCell = result.cells[0][0]

        XCTAssertTrue(updatedCell.isCompleted)
        XCTAssertNil(updatedCell.countdownEndsAt)
        XCTAssertNil(updatedCell.countdownPausedRemainingSeconds)
        XCTAssertNil(updatedCell.estimatedDurationMinutes)
    }

    func testExpiredWindowCompletionClearsSingleTaskScheduleAndCountdown() throws {
        let start = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let end = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 10)
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 11)
        let cell = BingoCell(
            text: "Focus",
            startVisibleAt: start,
            endVisibleAt: end,
            countdownEndsAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 30),
            estimatedDurationMinutes: 30
        )
        let candidate = try XCTUnwrap(BoardEngine.expiredTaskCandidate(in: [[cell]], now: now))

        let result = try XCTUnwrap(BoardEngine.resolveExpiredTask(
            in: [[cell]],
            candidate: candidate,
            resolution: .markAsCompleted,
            now: now,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
            calendar: fixedCalendar
        ))
        let updatedCell = result.cells[0][0]

        XCTAssertTrue(candidate.expiredByVisibilityWindow)
        XCTAssertTrue(updatedCell.isCompleted)
        XCTAssertNil(updatedCell.startVisibleAt)
        XCTAssertNil(updatedCell.endVisibleAt)
        XCTAssertNil(updatedCell.countdownEndsAt)
        XCTAssertNil(updatedCell.countdownPausedRemainingSeconds)
        XCTAssertNil(updatedCell.estimatedDurationMinutes)
    }

    func testPostponingSingleTaskWindowKeepsStartAndExtendsEndTime() throws {
        let start = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let end = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 10)
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 11)
        let cell = BingoCell(
            text: "Focus",
            startVisibleAt: start,
            endVisibleAt: end
        )
        let candidate = try XCTUnwrap(BoardEngine.expiredTaskCandidate(in: [[cell]], now: now))

        let result = try XCTUnwrap(BoardEngine.resolveExpiredTask(
            in: [[cell]],
            candidate: candidate,
            resolution: .postpone(minutes: 15),
            now: now,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
            calendar: fixedCalendar
        ))
        let updatedCell = result.cells[0][0]

        XCTAssertTrue(candidate.allowsPostpone)
        XCTAssertEqual(updatedCell.startVisibleAt, start)
        XCTAssertEqual(updatedCell.endVisibleAt, makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 26))
        XCTAssertNil(updatedCell.countdownEndsAt)
    }

    func testRepeatingTaskLegacyWindowDoesNotCreateTimeoutEvent() {
        let anchorStart = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let anchorEnd = makeDate(year: 2026, month: 6, day: 16, hour: 10)
        let now = makeDate(year: 2026, month: 6, day: 17, hour: 10, minute: 1)
        let cell = BingoCell(
            text: "Take meds",
            residentTaskText: "Take meds",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: anchorStart),
            startVisibleAt: anchorStart,
            endVisibleAt: anchorEnd,
            usesRecurringTimeWindow: true
        )
        XCTAssertNil(BoardEngine.expiredTaskCandidate(in: [[cell]], now: now))
    }

    func testLegacyRepeatingTimeWindowIsIgnoredEvenWithoutWindowFlag() {
        let anchorStart = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let anchorEnd = makeDate(year: 2026, month: 6, day: 16, hour: 10)
        let nextDayWithinSameTime = makeDate(year: 2026, month: 6, day: 17, hour: 9, minute: 30)
        let cell = BingoCell(
            text: "Take meds",
            residentTaskText: "Take meds",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: anchorStart),
            startVisibleAt: anchorStart,
            endVisibleAt: anchorEnd
        )

        XCTAssertFalse(cell.usesRecurringTimeWindow)
        XCTAssertTrue(cell.isCurrentlyTappable(on: nextDayWithinSameTime, calendar: fixedCalendar))
        XCTAssertNil(cell.occurrenceStartVisibleAt(on: nextDayWithinSameTime, calendar: fixedCalendar))
        XCTAssertNil(cell.occurrenceEndVisibleAt(on: nextDayWithinSameTime, calendar: fixedCalendar))
    }
}

final class TaskCountdownSettingViewModelTests: XCTestCase {
    func testTaskCountdownDisplayUsesHoursMinutesSecondsWithoutUnits() {
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(TaskCountdownDisplayRules.refreshInterval, 1)
        XCTAssertEqual(TaskCountdownDisplayRules.text(remainingSeconds: -1), "00:00:00")
        XCTAssertEqual(TaskCountdownDisplayRules.text(remainingSeconds: 65), "00:01:05")
        XCTAssertEqual(TaskCountdownDisplayRules.text(remainingSeconds: 3_661), "01:01:01")
        XCTAssertEqual(TaskCountdownDisplayRules.text(remainingSeconds: 25 * 3_600), "25:00:00")
        XCTAssertEqual(
            TaskCountdownDisplayRules.remainingSeconds(
                until: referenceDate.addingTimeInterval(1.01),
                at: referenceDate
            ),
            2
        )
        XCTAssertEqual(
            TaskCountdownDisplayRules.remainingSeconds(
                until: referenceDate.addingTimeInterval(-0.01),
                at: referenceDate
            ),
            0
        )
    }

    func testFiveByFiveTaskCountdownUpdatesVisibleAndPersistedBoardAndKeepsTickerActive() throws {
        let now = Date()
        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        fullBoardCells[4][4] = BingoCell(text: "Bottom corner task")
        let savedBoard = SavedBoard(
            gridSize: 5,
            cells: BoardEngine.projectVisibleCells(
                from: fullBoardCells,
                size: 5,
                referenceDate: now
            ),
            completedLines: [],
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertTrue(
            viewModel.setTaskCountdown(
                row: 4,
                col: 4,
                minutes: 20,
                referenceDate: now
            )
        )

        let deadline = try XCTUnwrap(viewModel.editingCell(row: 4, col: 4)?.countdownEndsAt)
        XCTAssertEqual(deadline.timeIntervalSince(now), 20 * 60, accuracy: 0.5)
        XCTAssertEqual(viewModel.cells[4][4].countdownEndsAt, deadline)
        XCTAssertEqual(harness.boardRepository.board?.fullBoardCells?[4][4].countdownEndsAt, deadline)
        XCTAssertTrue(viewModel.requiresLiveCountdownTicks(now: now.addingTimeInterval(1)))
        XCTAssertEqual(
            viewModel.remainingTaskCountdownMinutes(
                row: 4,
                col: 4,
                referenceDate: now.addingTimeInterval(61)
            ),
            19
        )
    }

    func testSingleTaskWithoutStartTimeCanSetCountdown() throws {
        let now = Date()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(text: "Focus"),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertTrue(viewModel.canSetTaskCountdown(row: 0, col: 0, referenceDate: now))
        XCTAssertTrue(viewModel.setTaskCountdown(row: 0, col: 0, minutes: 20, referenceDate: now))

        let updatedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertEqual(updatedCell.estimatedDurationMinutes, 20)
        XCTAssertEqual(updatedCell.countdownEndsAt?.timeIntervalSince(now) ?? 0, 20 * 60, accuracy: 0.5)
    }

    func testSingleTaskWithStartAndEndTimeCannotSetCountdown() throws {
        let now = Date()
        let start = now.addingTimeInterval(-60)
        let end = now.addingTimeInterval(60 * 60)
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Focus",
                residentTaskText: "Focus",
                oneTimeVisibleDate: now,
                recurrenceRule: TaskRecurrenceRule(kind: .none, anchorDate: now),
                startVisibleAt: start,
                endVisibleAt: end
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertFalse(viewModel.canSetTaskCountdown(row: 0, col: 0, referenceDate: now))
        XCTAssertFalse(viewModel.setTaskCountdown(row: 0, col: 0, minutes: 20, referenceDate: now))

        let updatedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertNil(updatedCell.estimatedDurationMinutes)
        XCTAssertNil(updatedCell.countdownEndsAt)
        XCTAssertNil(harness.boardRepository.board?.fullBoardCells?[0][0].estimatedDurationMinutes)
    }

    func testRepeatingTaskCannotSetCountdown() {
        let now = Date()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Drink water",
                residentTaskText: "Drink water",
                recurrenceRule: TaskRecurrenceRule(kind: .daily),
                startVisibleAt: now.addingTimeInterval(-60)
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertFalse(viewModel.canSetTaskCountdown(row: 0, col: 0, referenceDate: now))
        XCTAssertFalse(viewModel.setTaskCountdown(row: 0, col: 0, minutes: 20, referenceDate: now))
        XCTAssertNil(viewModel.editingCell(row: 0, col: 0)?.estimatedDurationMinutes)
    }

    func testCompletedTaskTextChangeBecomesIncomplete() throws {
        let now = Date()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Wash dishes",
                isCompleted: true,
                completionStreakCount: 2,
                lastCompletedAt: now
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.updateTask(
            row: 0,
            col: 0,
            text: "Write resume",
            isForced: false,
            residentWeekdays: []
        )

        let updatedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertEqual(updatedCell.storedTaskText, "Write resume")
        XCTAssertFalse(updatedCell.isCompleted)
        XCTAssertEqual(updatedCell.completionStreakCount, 0)
        XCTAssertNil(updatedCell.lastCompletedAt)
        XCTAssertEqual(viewModel.totalPoints, 1)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 1)
    }

    func testCompletedTaskRepeatRuleChangeBecomesIncomplete() throws {
        let now = Date()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Drink water",
                isCompleted: true,
                completionStreakCount: 1,
                lastCompletedAt: now
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.updateTask(
            row: 0,
            col: 0,
            text: "Drink water",
            isForced: false,
            residentWeekdays: [],
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )

        let updatedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertEqual(updatedCell.storedTaskText, "Drink water")
        XCTAssertEqual(updatedCell.recurrenceRule?.kind, .daily)
        XCTAssertFalse(updatedCell.isCompleted)
        XCTAssertEqual(updatedCell.completionStreakCount, 0)
        XCTAssertNil(updatedCell.lastCompletedAt)
        XCTAssertEqual(viewModel.totalPoints, 1)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 1)
    }

    func testQuickEditCellReplacementPreservesAccumulatedPoints() throws {
        let now = Date()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Completed task",
                isCompleted: true,
                completionStreakCount: 1,
                lastCompletedAt: now
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.applyBoardOrderedCells(
            [BingoCell(text: "Replacement task")],
            targetGridSize: 2
        )

        XCTAssertEqual(viewModel.editingCell(row: 0, col: 0)?.storedTaskText, "Replacement task")
        XCTAssertFalse(viewModel.editingCell(row: 0, col: 0)?.isCompleted == true)
        XCTAssertEqual(viewModel.totalPoints, 1)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 1)
    }

    func testCompletedExpiredWindowTaskCanBeToggledIncomplete() throws {
        let now = Date()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Focus",
                startVisibleAt: now.addingTimeInterval(-120),
                endVisibleAt: now.addingTimeInterval(-60),
                isCompleted: true,
                completionStreakCount: 1,
                lastCompletedAt: now.addingTimeInterval(-30)
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertFalse(viewModel.isTaskCurrentlyTappable(row: 0, col: 0, referenceDate: now))
        XCTAssertTrue(viewModel.canToggleComplete(row: 0, col: 0, referenceDate: now))

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now)

        let updatedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertFalse(updatedCell.isCompleted)
        XCTAssertEqual(updatedCell.completionStreakCount, 0)
        XCTAssertNil(updatedCell.lastCompletedAt)
        XCTAssertEqual(viewModel.totalPoints, 0)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 0)
    }

    func testUndoCompletionDoesNotRestoreClearedCountdown() throws {
        let now = Date()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Focus",
                countdownEndsAt: now.addingTimeInterval(600),
                estimatedDurationMinutes: 20
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now)
        var updatedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertTrue(updatedCell.isCompleted)
        XCTAssertNil(updatedCell.countdownEndsAt)
        XCTAssertNil(updatedCell.countdownPausedRemainingSeconds)
        XCTAssertNil(updatedCell.estimatedDurationMinutes)

        let undoAt = now.addingTimeInterval(120)
        viewModel.toggleComplete(row: 0, col: 0, referenceDate: undoAt)

        updatedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertFalse(updatedCell.isCompleted)
        XCTAssertNil(updatedCell.countdownPausedRemainingSeconds)
        XCTAssertNil(updatedCell.countdownEndsAt)
        XCTAssertNil(updatedCell.estimatedDurationMinutes)
        XCTAssertFalse(viewModel.refreshVisibilityWindowsIfNeeded(now: undoAt.addingTimeInterval(1)))
    }

    func testApplyingWidgetSnapshotReloadsPersistedPointsBeforeSaving() throws {
        let now = makeDate(year: 2026, month: 6, day: 29, hour: 9)
        var incompleteCell = BingoCell(text: "Focus")
        let incompleteBoard = makeSavedBoardForViewModel(cell: incompleteCell, referenceDate: now)
        let harness = makeInMemoryViewModelHarness(
            savedBoard: incompleteBoard,
            savedAt: now,
            totalPoints: 10,
            lifetimePoints: 10,
            dailyRewardState: DailyRewardState(dateKey: PointsStore.dateKey(for: now))
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        XCTAssertEqual(viewModel.totalPoints, 10)

        incompleteCell.isCompleted = true
        incompleteCell.lastCompletedAt = now
        incompleteCell.completionStreakCount = 1
        let widgetUpdatedBoard = makeSavedBoardForViewModel(cell: incompleteCell, referenceDate: now)
        let widgetRewardState = BingoRewardSettlement.dailyRewardSnapshot(
            for: now,
            cells: widgetUpdatedBoard.cells,
            completedLines: widgetUpdatedBoard.completedLines,
            isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(widgetUpdatedBoard.cells)
        )
        harness.pointsRepository.saveTotalPoints(11)
        harness.pointsRepository.saveLifetimePoints(11)
        harness.pointsRepository.saveDailyRewardState(widgetRewardState)

        viewModel.applySavedBoardSnapshot(
            widgetUpdatedBoard,
            countdownEndsAt: nil,
            referenceDate: now,
            reloadPersistedPoints: true
        )

        XCTAssertEqual(viewModel.totalPoints, 11)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 11)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(60))

        XCTAssertEqual(viewModel.totalPoints, 10)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 10)
    }

    func testApplyingSavedBoardSnapshotPreservesActiveNamedBoardAssociation() {
        let now = makeDate(year: 2026, month: 6, day: 29, hour: 10)
        let activeBoardID = UUID()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(text: "Board 2 task"),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            activeNamedBoardID: activeBoardID
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.applySavedBoardSnapshot(
            savedBoard,
            countdownEndsAt: nil,
            referenceDate: now
        )

        XCTAssertEqual(harness.boardRepository.loadActiveNamedBoardID(), activeBoardID)
    }

    func testPauseResumeAndCancelTaskCountdown() throws {
        let now = Date()
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Focus",
                countdownEndsAt: now.addingTimeInterval(20 * 60),
                estimatedDurationMinutes: 20
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertTrue(viewModel.canPauseOrResumeTaskCountdown(row: 0, col: 0, referenceDate: now))
        XCTAssertTrue(viewModel.pauseTaskCountdown(row: 0, col: 0, referenceDate: now))

        var pausedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertNil(pausedCell.countdownEndsAt)
        XCTAssertEqual(pausedCell.countdownPausedRemainingSeconds, 20 * 60)
        XCTAssertFalse(viewModel.refreshVisibilityWindowsIfNeeded(now: now.addingTimeInterval(60)))
        pausedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertNil(pausedCell.countdownEndsAt)
        XCTAssertEqual(pausedCell.countdownPausedRemainingSeconds, 20 * 60)

        let resumeAt = now.addingTimeInterval(120)
        XCTAssertTrue(viewModel.resumeTaskCountdown(row: 0, col: 0, referenceDate: resumeAt))
        let resumedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertNil(resumedCell.countdownPausedRemainingSeconds)
        XCTAssertEqual(resumedCell.countdownEndsAt?.timeIntervalSince(resumeAt) ?? 0, 20 * 60, accuracy: 0.5)

        XCTAssertTrue(viewModel.cancelTaskCountdown(row: 0, col: 0, referenceDate: resumeAt))
        let cancelledCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertNil(cancelledCell.estimatedDurationMinutes)
        XCTAssertNil(cancelledCell.countdownEndsAt)
        XCTAssertNil(cancelledCell.countdownPausedRemainingSeconds)
    }
}

final class RepeatingTaskTimingRuleTests: XCTestCase {
    func testAllRepeatingKindsDiscardStartEndReminderAndCountdownOnSave() {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 9)
        let start = now.addingTimeInterval(60 * 60)
        let end = now.addingTimeInterval(2 * 60 * 60)
        let rules = [
            TaskRecurrenceRule(kind: .daily),
            TaskRecurrenceRule(kind: .weekly, weekdays: [2]),
            TaskRecurrenceRule(kind: .monthlyDay, monthDay: 12),
            TaskRecurrenceRule(kind: .everyNDays, interval: 3, anchorDate: now)
        ]

        for rule in rules {
            let savedBoard = makeSavedBoardForViewModel(
                cell: BingoCell(text: "Original"),
                referenceDate: now
            )
            let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)
            let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

            viewModel.updateTask(
                row: 0,
                col: 0,
                text: "Repeating",
                isForced: false,
                residentWeekdays: rule.weekdays,
                recurrenceRule: rule,
                estimatedDurationMinutes: 15,
                startVisibleAt: start,
                endVisibleAt: end,
                startReminderEnabled: true,
                startReminderOffsetMinutes: 5
            )

            let updated = viewModel.editingCell(row: 0, col: 0)
            XCTAssertEqual(updated?.recurrenceRule?.kind, rule.kind, "Failed for \(rule.kind)")
            XCTAssertNil(updated?.startVisibleAt, "Failed for \(rule.kind)")
            XCTAssertNil(updated?.endVisibleAt, "Failed for \(rule.kind)")
            XCTAssertFalse(updated?.usesRecurringTimeWindow == true, "Failed for \(rule.kind)")
            XCTAssertFalse(updated?.startReminderEnabled == true, "Failed for \(rule.kind)")
            XCTAssertNil(updated?.estimatedDurationMinutes, "Failed for \(rule.kind)")
            XCTAssertNil(updated?.countdownEndsAt, "Failed for \(rule.kind)")
        }
    }

    func testQuickEditAlsoDiscardsTimingForRepeatingTask() throws {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 9)
        let cell = try XCTUnwrap(
            quickEditMakePreviewCellFromEdit(
                existingCell: nil,
                text: "Weekly",
                isForcedTask: false,
                residentWeekdays: [2],
                isOneTimeTask: false,
                recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [2]),
                estimatedDurationMinutes: 30,
                startVisibleAt: now,
                endVisibleAt: now.addingTimeInterval(60 * 60),
                startReminderEnabled: true
            )
        )

        XCTAssertEqual(cell.recurrenceRule?.kind, .weekly)
        XCTAssertNil(cell.startVisibleAt)
        XCTAssertNil(cell.endVisibleAt)
        XCTAssertFalse(cell.usesRecurringTimeWindow)
        XCTAssertFalse(cell.startReminderEnabled)
        XCTAssertNil(cell.estimatedDurationMinutes)
    }

    func testLegacyMigrationPreservesEveryNDaysAnchorTaskStateAndIdentity() throws {
        let anchor = makeDate(year: 2026, month: 7, day: 10, hour: 9)
        let end = anchor.addingTimeInterval(60 * 60)
        let cellID = UUID()
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            id: cellID,
            text: "Legacy interval",
            residentTaskText: "Legacy interval",
            recurrenceRule: TaskRecurrenceRule(kind: .everyNDays, interval: 3),
            startVisibleAt: anchor,
            endVisibleAt: end,
            usesRecurringTimeWindow: true,
            startReminderEnabled: true,
            isCompleted: true,
            isForced: true,
            countdownEndsAt: end,
            countdownPausedRemainingSeconds: 300,
            estimatedDurationMinutes: 20,
            completionStreakCount: 4,
            lastCompletedAt: anchor
        )
        let board = makeNamedBoard(cells: cells, updatedAt: anchor).board

        let migrated = BoardEngine.removingUnsupportedRecurringTiming(
            from: board,
            referenceDate: anchor
        )
        let migratedCell = try XCTUnwrap(migrated.fullBoardCells?[0][0])

        XCTAssertEqual(migratedCell.id, cellID)
        XCTAssertEqual(migratedCell.storedTaskText, "Legacy interval")
        XCTAssertEqual(migratedCell.recurrenceRule?.kind, .everyNDays)
        XCTAssertEqual(migratedCell.recurrenceRule?.anchorDate, anchor)
        XCTAssertTrue(migratedCell.isCompleted)
        XCTAssertTrue(migratedCell.isForced)
        XCTAssertEqual(migratedCell.completionStreakCount, 4)
        XCTAssertEqual(migratedCell.lastCompletedAt, anchor)
        XCTAssertNil(migratedCell.startVisibleAt)
        XCTAssertNil(migratedCell.endVisibleAt)
        XCTAssertFalse(migratedCell.usesRecurringTimeWindow)
        XCTAssertFalse(migratedCell.startReminderEnabled)
        XCTAssertNil(migratedCell.countdownEndsAt)
        XCTAssertNil(migratedCell.countdownPausedRemainingSeconds)
        XCTAssertNil(migratedCell.estimatedDurationMinutes)
    }

    func testViewModelMigrationPreservesCurrentAndLifetimePoints() {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 9)
        let cellID = UUID()
        let legacyCell = BingoCell(
            id: cellID,
            text: "Legacy daily",
            residentTaskText: "Legacy daily",
            recurrenceRule: TaskRecurrenceRule(kind: .daily),
            startVisibleAt: now,
            endVisibleAt: now.addingTimeInterval(60 * 60),
            usesRecurringTimeWindow: true,
            startReminderEnabled: true,
            isCompleted: true,
            completionStreakCount: 2,
            lastCompletedAt: now
        )
        let board = makeSavedBoardForViewModel(cell: legacyCell, referenceDate: now)
        let harness = makeInMemoryViewModelHarness(
            savedBoard: board,
            savedAt: now,
            totalPoints: 12,
            lifetimePoints: 20,
            dailyRewardState: DailyRewardState(
                dateKey: PointsStore.dateKey(for: now),
                rewardedCellIDs: [cellID],
                peakCompletedLineCount: 0,
                fullBoardRewardGranted: false
            )
        )

        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertEqual(viewModel.totalPoints, 12)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 20)
        XCTAssertTrue(viewModel.cells[0][0].isCompleted)
        XCTAssertNil(viewModel.cells[0][0].startVisibleAt)
        XCTAssertNil(viewModel.cells[0][0].endVisibleAt)
        XCTAssertFalse(viewModel.cells[0][0].startReminderEnabled)
        XCTAssertGreaterThan(harness.boardRepository.saveBoardCallCount, 0)
    }

    func testLegacyMigrationPreservesBoardCountdownAndSuppressesOnlyTaskTimeoutPopup() {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 10)
        let boardDeadline = now.addingTimeInterval(-1)
        let legacyCell = BingoCell(
            text: "Legacy daily",
            residentTaskText: "Legacy daily",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: now),
            startVisibleAt: now.addingTimeInterval(-3_600),
            endVisibleAt: now.addingTimeInterval(-1_800),
            usesRecurringTimeWindow: true,
            countdownEndsAt: now.addingTimeInterval(-1_800),
            estimatedDurationMinutes: 30
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: makeSavedBoardForViewModel(cell: legacyCell, referenceDate: now),
            savedAt: now,
            countdownEndsAt: boardDeadline,
            totalPoints: 44,
            lifetimePoints: 60,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertEqual(viewModel.boardCountdownEndsAt, boardDeadline)
        XCTAssertNil(viewModel.cells[0][0].countdownEndsAt)
        XCTAssertNil(viewModel.cells[0][0].estimatedDurationMinutes)

        viewModel.processExpiredCountdowns(now: now)
        viewModel.processExpiredTaskCountdowns(now: now)

        XCTAssertNotNil(viewModel.expiredBoardCountdownEvent)
        XCTAssertNil(viewModel.expiredTaskEvent)
        XCTAssertEqual(viewModel.totalPoints, 44)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 60)

        XCTAssertNotNil(viewModel.resolveExpiredBoardCountdown(.postpone(minutes: 5), now: now))
        XCTAssertEqual(viewModel.boardCountdownEndsAt, now.addingTimeInterval(5 * 60))
        XCTAssertEqual(viewModel.totalPoints, 44)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 60)
    }

    func testMigratedRepeatingTaskUsesCustomResetOnceAtThreeInsteadOfMidnight() throws {
        let completedAt = makeDate(year: 2026, month: 7, day: 11, hour: 22)
        let previousReset = makeDate(year: 2026, month: 7, day: 11, hour: 3)
        let afterMidnight = makeDate(year: 2026, month: 7, day: 12, hour: 0, minute: 1)
        let afterTrigger = makeDate(year: 2026, month: 7, day: 12, hour: 3, minute: 1)
        let repeatedEvaluation = makeDate(year: 2026, month: 7, day: 12, hour: 3, minute: 5)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Legacy daily",
            residentTaskText: "Legacy daily",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: completedAt),
            startVisibleAt: makeDate(year: 2026, month: 7, day: 11, hour: 9),
            endVisibleAt: makeDate(year: 2026, month: 7, day: 11, hour: 10),
            usesRecurringTimeWindow: true,
            isCompleted: true,
            completionStreakCount: 2,
            lastCompletedAt: completedAt
        )
        var board = makeNamedBoard(
            cells: cells,
            mode: .resetStatusNextDay,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousReset,
            updatedAt: completedAt
        )
        board.countdownEndsAt = afterTrigger.addingTimeInterval(3_600)
        board.board = BoardEngine.removingUnsupportedRecurringTiming(
            from: board.board,
            referenceDate: afterMidnight
        )

        let migratedCell = try XCTUnwrap(board.board.fullBoardCells?[0][0])
        XCTAssertTrue(migratedCell.isCompleted)
        XCTAssertNil(migratedCell.startVisibleAt)
        XCTAssertNil(migratedCell.endVisibleAt)

        let midnightResult = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            board,
            now: afterMidnight,
            calendar: fixedCalendar
        )
        XCTAssertTrue(midnightResult.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertEqual(midnightResult.lastTaskResetAppliedAt, previousReset)
        XCTAssertNotNil(midnightResult.countdownEndsAt)

        let triggerResult = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            midnightResult,
            now: afterTrigger,
            calendar: fixedCalendar
        )
        XCTAssertFalse(triggerResult.board.fullBoardCells?[0][0].isCompleted == true)
        XCTAssertEqual(triggerResult.lastTaskResetAppliedAt, afterTrigger)
        XCTAssertNil(triggerResult.countdownEndsAt)

        let secondResult = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            triggerResult,
            now: repeatedEvaluation,
            calendar: fixedCalendar
        )
        XCTAssertEqual(secondResult, triggerResult)
    }

    func testWidgetLikeLegacySnapshotMigrationKeepsPersistedPointsAndBoardCountdown() {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 9)
        let cellID = UUID()
        let initialBoard = makeSavedBoardForViewModel(
            cell: BingoCell(id: cellID, text: "Daily"),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: initialBoard,
            savedAt: now,
            totalPoints: 44,
            lifetimePoints: 59,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        let legacyCompletedCell = BingoCell(
            id: cellID,
            text: "Daily",
            residentTaskText: "Daily",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: now),
            startVisibleAt: now.addingTimeInterval(-3_600),
            endVisibleAt: now.addingTimeInterval(3_600),
            usesRecurringTimeWindow: true,
            startReminderEnabled: true,
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: now
        )
        let widgetUpdatedBoard = makeSavedBoardForViewModel(
            cell: legacyCompletedCell,
            referenceDate: now
        )
        let widgetRewardState = BingoRewardSettlement.dailyRewardSnapshot(
            for: now,
            cells: widgetUpdatedBoard.cells,
            completedLines: widgetUpdatedBoard.completedLines,
            isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(widgetUpdatedBoard.cells)
        )
        harness.pointsRepository.saveTotalPoints(45)
        harness.pointsRepository.saveLifetimePoints(60)
        harness.pointsRepository.saveDailyRewardState(widgetRewardState)
        let boardDeadline = now.addingTimeInterval(30 * 60)

        viewModel.applySavedBoardSnapshot(
            widgetUpdatedBoard,
            countdownEndsAt: boardDeadline,
            referenceDate: now,
            reloadPersistedPoints: true
        )

        XCTAssertEqual(viewModel.totalPoints, 45)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 60)
        XCTAssertEqual(viewModel.boardCountdownEndsAt, boardDeadline)
        XCTAssertTrue(viewModel.cells[0][0].isCompleted)
        XCTAssertNil(viewModel.cells[0][0].startVisibleAt)
        XCTAssertNil(viewModel.cells[0][0].endVisibleAt)
        XCTAssertFalse(viewModel.cells[0][0].startReminderEnabled)
        XCTAssertNil(viewModel.expiredTaskEvent)
        XCTAssertNil(viewModel.expiredBoardCountdownEvent)
    }

    func testLegacyRepeatingMigrationDoesNotAlterAdjacentSingleTaskCountdown() throws {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 9)
        let singleStart = now.addingTimeInterval(60)
        let singleEnd = now.addingTimeInterval(3_600)
        let singleCountdown = now.addingTimeInterval(1_800)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Legacy daily",
            residentTaskText: "Legacy daily",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: now),
            startVisibleAt: now,
            endVisibleAt: now.addingTimeInterval(3_600),
            usesRecurringTimeWindow: true,
            countdownEndsAt: now.addingTimeInterval(600),
            estimatedDurationMinutes: 10
        )
        cells[0][1] = BingoCell(
            text: "Single timed task",
            startVisibleAt: singleStart,
            endVisibleAt: singleEnd,
            countdownEndsAt: singleCountdown,
            countdownPausedRemainingSeconds: 120,
            estimatedDurationMinutes: 30
        )
        let board = makeNamedBoard(cells: cells, updatedAt: now).board

        let migrated = BoardEngine.removingUnsupportedRecurringTiming(
            from: board,
            referenceDate: now
        )
        let migratedCells = try XCTUnwrap(migrated.fullBoardCells)

        XCTAssertNil(migratedCells[0][0].startVisibleAt)
        XCTAssertNil(migratedCells[0][0].countdownEndsAt)
        XCTAssertEqual(migratedCells[0][1], cells[0][1])
        XCTAssertEqual(migratedCells[0][1].startVisibleAt, singleStart)
        XCTAssertEqual(migratedCells[0][1].endVisibleAt, singleEnd)
        XCTAssertEqual(migratedCells[0][1].countdownEndsAt, singleCountdown)
        XCTAssertEqual(migratedCells[0][1].countdownPausedRemainingSeconds, 120)
        XCTAssertEqual(migratedCells[0][1].estimatedDurationMinutes, 30)
    }
}

final class BoardTaskPointIntegrationTests: XCTestCase {
    func testResetModeMatrixHandlesRegularRepeatingAndOneTimeTasks() throws {
        let previousDay = makeDate(year: 2026, month: 7, day: 10, hour: 3)
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 3, minute: 1)
        let futureDay = makeDate(year: 2026, month: 7, day: 12, hour: 9)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Regular",
            isCompleted: true,
            countdownEndsAt: now.addingTimeInterval(600),
            estimatedDurationMinutes: 10,
            lastCompletedAt: previousDay
        )
        cells[0][1] = BingoCell(
            text: "Daily",
            residentTaskText: "Daily",
            recurrenceRule: TaskRecurrenceRule(kind: .daily, anchorDate: previousDay),
            isCompleted: true,
            lastCompletedAt: previousDay
        )
        cells[1][0] = BingoCell(
            text: "Old one-time",
            residentTaskText: "Old one-time",
            oneTimeVisibleDate: previousDay,
            isCompleted: true,
            lastCompletedAt: previousDay
        )
        cells[1][1] = BingoCell(
            text: "Future one-time",
            recurrenceRule: TaskRecurrenceRule(kind: .none, anchorDate: futureDay),
            isCompleted: true,
            lastCompletedAt: previousDay
        )

        var resetStatusBoard = makeNamedBoard(
            cells: cells,
            mode: .resetStatusNextDay,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousDay,
            updatedAt: previousDay
        )
        resetStatusBoard.countdownEndsAt = now.addingTimeInterval(3_600)
        let resetStatusResult = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            resetStatusBoard,
            now: now,
            calendar: fixedCalendar
        )
        let resetCells = try XCTUnwrap(resetStatusResult.board.fullBoardCells)

        XCTAssertTrue(resetCells[0][0].hasStoredTask)
        XCTAssertFalse(resetCells[0][0].isCompleted)
        XCTAssertNil(resetCells[0][0].countdownEndsAt)
        XCTAssertNil(resetCells[0][0].estimatedDurationMinutes)
        XCTAssertTrue(resetCells[0][1].hasStoredTask)
        XCTAssertFalse(resetCells[0][1].isCompleted)
        XCTAssertFalse(resetCells[1][0].hasStoredTask)
        XCTAssertTrue(resetCells[1][1].hasStoredTask)
        XCTAssertFalse(resetCells[1][1].isCompleted)
        XCTAssertNil(resetStatusResult.countdownEndsAt)

        let clearTasksBoard = makeNamedBoard(
            cells: cells,
            mode: .clearTasksNextDay,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousDay,
            updatedAt: previousDay
        )
        let clearTasksResult = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            clearTasksBoard,
            now: now,
            calendar: fixedCalendar
        )
        let clearedCells = try XCTUnwrap(clearTasksResult.board.fullBoardCells)

        XCTAssertFalse(clearedCells[0][0].hasStoredTask)
        XCTAssertTrue(clearedCells[0][1].hasStoredTask)
        XCTAssertFalse(clearedCells[0][1].isCompleted)
        XCTAssertFalse(clearedCells[1][0].hasStoredTask)
        XCTAssertTrue(clearedCells[1][1].hasStoredTask)
        XCTAssertFalse(clearedCells[1][1].isCompleted)

        var keepStatusBoard = makeNamedBoard(
            cells: cells,
            mode: .keepTaskStatus,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousDay,
            updatedAt: previousDay
        )
        keepStatusBoard.countdownEndsAt = now.addingTimeInterval(3_600)
        let keepStatusResult = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            keepStatusBoard,
            now: now,
            calendar: fixedCalendar
        )

        XCTAssertEqual(keepStatusResult, keepStatusBoard)
        XCTAssertEqual(keepStatusResult.countdownEndsAt, keepStatusBoard.countdownEndsAt)
    }

    func testBoardCountdownResolutionMatrixHasExpectedTaskAndDeadlineEffects() throws {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 10)
        let countdownEnd = now.addingTimeInterval(-1)
        let cells = [[
            BingoCell(
                text: "First",
                countdownEndsAt: countdownEnd,
                estimatedDurationMinutes: 5
            ),
            BingoCell(text: "Second", isCompleted: true, lastCompletedAt: now)
        ]]

        let completed = BoardEngine.resolveExpiredBoardCountdown(
            in: cells,
            resolution: .markAsCompleted,
            now: now,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
            calendar: fixedCalendar
        )
        XCTAssertTrue(completed.cells.flatMap(\.self).allSatisfy(\.isCompleted))
        XCTAssertTrue(completed.cells.flatMap(\.self).allSatisfy { $0.countdownEndsAt == nil })
        XCTAssertTrue(completed.cells.flatMap(\.self).allSatisfy { $0.estimatedDurationMinutes == nil })
        XCTAssertNil(completed.boardCountdownEndsAt)

        let abandoned = BoardEngine.resolveExpiredBoardCountdown(
            in: cells,
            resolution: .abandon,
            now: now,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
            calendar: fixedCalendar
        )
        XCTAssertEqual(abandoned.cells, cells)
        XCTAssertNil(abandoned.boardCountdownEndsAt)

        let postponed = BoardEngine.resolveExpiredBoardCountdown(
            in: cells,
            resolution: .postpone(minutes: 0),
            now: now,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
            calendar: fixedCalendar
        )
        XCTAssertEqual(postponed.cells, cells)
        XCTAssertEqual(postponed.clampedPostponeMinutes, 1)
        XCTAssertEqual(postponed.boardCountdownEndsAt, now.addingTimeInterval(60))
    }

    func testExpiredBoardCountdownCompletionAwardsFullTwoByTwoBoardExactlyOnce() {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 10)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "A")
        cells[0][1] = BingoCell(text: "B")
        cells[1][0] = BingoCell(text: "C")
        cells[1][1] = BingoCell(text: "D")
        let savedBoard = makeNamedBoard(cells: cells, updatedAt: now).board
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            countdownEndsAt: now.addingTimeInterval(-1),
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.processExpiredCountdowns(now: now)
        XCTAssertNotNil(viewModel.expiredBoardCountdownEvent)
        XCTAssertNotNil(viewModel.resolveExpiredBoardCountdown(.markAsCompleted, now: now))

        XCTAssertTrue(viewModel.cells.flatMap(\.self).allSatisfy(\.isCompleted))
        XCTAssertNil(viewModel.boardCountdownEndsAt)
        XCTAssertEqual(viewModel.totalPoints, 44)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 44)
        XCTAssertNil(viewModel.resolveExpiredBoardCountdown(.markAsCompleted, now: now))
        XCTAssertEqual(viewModel.totalPoints, 44)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 44)
    }

    func testBoardCountdownAbandonAndPostponeDoNotChangePointsOrTasks() {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 10)
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(text: "Unfinished"),
            referenceDate: now
        )

        let abandonHarness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            countdownEndsAt: now.addingTimeInterval(-1),
            totalPoints: 7,
            lifetimePoints: 10,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let abandonViewModel = BingoViewModel(persistenceDependencies: abandonHarness.dependencies)
        abandonViewModel.processExpiredCountdowns(now: now)
        XCTAssertNotNil(abandonViewModel.resolveExpiredBoardCountdown(.abandon, now: now))
        XCTAssertEqual(abandonViewModel.cells[0][0].storedTaskText, "Unfinished")
        XCTAssertFalse(abandonViewModel.cells[0][0].isCompleted)
        XCTAssertEqual(abandonViewModel.totalPoints, 7)
        XCTAssertEqual(abandonHarness.pointsRepository.loadLifetimePoints(), 10)

        let postponeHarness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            countdownEndsAt: now.addingTimeInterval(-1),
            totalPoints: 7,
            lifetimePoints: 10,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let postponeViewModel = BingoViewModel(persistenceDependencies: postponeHarness.dependencies)
        postponeViewModel.processExpiredCountdowns(now: now)
        XCTAssertNotNil(postponeViewModel.resolveExpiredBoardCountdown(.postpone(minutes: 5), now: now))
        XCTAssertEqual(postponeViewModel.cells[0][0].storedTaskText, "Unfinished")
        XCTAssertFalse(postponeViewModel.cells[0][0].isCompleted)
        XCTAssertEqual(postponeViewModel.boardCountdownEndsAt, now.addingTimeInterval(5 * 60))
        XCTAssertEqual(postponeViewModel.totalPoints, 7)
        XCTAssertEqual(postponeHarness.pointsRepository.loadLifetimePoints(), 10)
    }

    func testExpiredBoardCountdownPromptSurvivesAppRelaunchUntilResolution() {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 10)
        let expiredAt = now.addingTimeInterval(-1)
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(text: "Unfinished"),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            countdownEndsAt: expiredAt,
            totalPoints: 7,
            lifetimePoints: 10,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )

        let firstLaunch = BingoViewModel(persistenceDependencies: harness.dependencies)
        firstLaunch.processExpiredCountdowns(now: now)
        XCTAssertNotNil(firstLaunch.expiredBoardCountdownEvent)
        XCTAssertEqual(harness.boardRepository.loadBoardCountdownEndsAt(), expiredAt)

        let relaunched = BingoViewModel(persistenceDependencies: harness.dependencies)
        XCTAssertEqual(relaunched.boardCountdownEndsAt, expiredAt)
        relaunched.processExpiredCountdowns(now: now)
        XCTAssertNotNil(relaunched.expiredBoardCountdownEvent)
        XCTAssertEqual(relaunched.totalPoints, 7)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 10)

        XCTAssertNotNil(relaunched.resolveExpiredBoardCountdown(.markAsCompleted, now: now))
        XCTAssertNil(harness.boardRepository.loadBoardCountdownEndsAt())
        XCTAssertEqual(relaunched.totalPoints, 8)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 11)
        XCTAssertNil(relaunched.resolveExpiredBoardCountdown(.markAsCompleted, now: now))
        XCTAssertEqual(relaunched.totalPoints, 8)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 11)
    }

    func testCustomBoardResetPreservesAccumulatedPointsAndStartsFreshRewardCycle() throws {
        let completedAt = makeDate(year: 2026, month: 7, day: 11, hour: 1)
        let resetAt = makeDate(year: 2026, month: 7, day: 11, hour: 3, minute: 1)
        let cellID = UUID()
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            id: cellID,
            text: "Resettable",
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: completedAt
        )
        let board = makeNamedBoard(
            cells: cells,
            mode: .resetStatusNextDay,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: makeDate(year: 2026, month: 7, day: 10, hour: 3),
            updatedAt: completedAt
        )
        let resetBoard = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            board,
            now: resetAt,
            calendar: fixedCalendar
        )
        XCTAssertFalse(resetBoard.board.fullBoardCells?[0][0].isCompleted == true)

        let harness = makeInMemoryViewModelHarness(
            savedBoard: board.board,
            savedAt: completedAt,
            totalPoints: 10,
            lifetimePoints: 10,
            dailyRewardState: DailyRewardState(
                dateKey: PointsStore.dateKey(for: completedAt),
                rewardedCellIDs: [cellID],
                peakCompletedLineCount: 0,
                fullBoardRewardGranted: false
            )
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        viewModel.applySavedBoardSnapshot(
            resetBoard.board,
            countdownEndsAt: resetBoard.countdownEndsAt,
            referenceDate: resetAt
        )

        XCTAssertEqual(viewModel.totalPoints, 10)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 10)
        viewModel.toggleComplete(row: 0, col: 0, referenceDate: resetAt.addingTimeInterval(1))
        XCTAssertEqual(viewModel.totalPoints, 11)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 11)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 11)
    }

    func testTaskCompletionUndoAndRecompletionHaveExpectedPointLifecycle() {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 10)
        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(text: "Repeatable action"),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now)
        XCTAssertEqual(viewModel.totalPoints, 1)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 1)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(1))
        XCTAssertEqual(viewModel.totalPoints, 0)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 1)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(2))
        XCTAssertEqual(viewModel.totalPoints, 1)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 2)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 1)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 2)
    }

    func testExpiredTaskResolutionPointMatrix() {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 10)
        let expiredBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Timed task",
                countdownEndsAt: now.addingTimeInterval(-1),
                estimatedDurationMinutes: 5
            ),
            referenceDate: now
        )

        let completeHarness = makeInMemoryViewModelHarness(
            savedBoard: expiredBoard,
            savedAt: now,
            totalPoints: 5,
            lifetimePoints: 8,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let completeViewModel = BingoViewModel(persistenceDependencies: completeHarness.dependencies)
        completeViewModel.processExpiredTaskCountdowns(now: now)
        XCTAssertNotNil(completeViewModel.resolveExpiredTask(.markAsCompleted, now: now))
        XCTAssertEqual(completeViewModel.totalPoints, 6)
        XCTAssertEqual(completeHarness.pointsRepository.loadLifetimePoints(), 9)

        let abandonHarness = makeInMemoryViewModelHarness(
            savedBoard: expiredBoard,
            savedAt: now,
            totalPoints: 5,
            lifetimePoints: 8,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let abandonViewModel = BingoViewModel(persistenceDependencies: abandonHarness.dependencies)
        abandonViewModel.processExpiredTaskCountdowns(now: now)
        XCTAssertNotNil(abandonViewModel.resolveExpiredTask(.abandon, now: now))
        XCTAssertEqual(abandonViewModel.totalPoints, 5)
        XCTAssertEqual(abandonHarness.pointsRepository.loadLifetimePoints(), 8)
        XCTAssertTrue(abandonViewModel.cells[0][0].isEmpty)

        let postponeHarness = makeInMemoryViewModelHarness(
            savedBoard: expiredBoard,
            savedAt: now,
            totalPoints: 5,
            lifetimePoints: 8,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let postponeViewModel = BingoViewModel(persistenceDependencies: postponeHarness.dependencies)
        postponeViewModel.processExpiredTaskCountdowns(now: now)
        XCTAssertNotNil(postponeViewModel.resolveExpiredTask(.postpone(minutes: 5), now: now))
        XCTAssertEqual(postponeViewModel.totalPoints, 5)
        XCTAssertEqual(postponeHarness.pointsRepository.loadLifetimePoints(), 8)
        XCTAssertEqual(postponeViewModel.cells[0][0].countdownEndsAt, now.addingTimeInterval(5 * 60))
    }

    func testExpiredTaskPromptSurvivesAppRelaunchUntilResolution() throws {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 10)
        let expiredAt = now.addingTimeInterval(-1)
        let expiredBoard = makeSavedBoardForViewModel(
            cell: BingoCell(
                text: "Timed task",
                countdownEndsAt: expiredAt,
                estimatedDurationMinutes: 5
            ),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: expiredBoard,
            savedAt: now,
            totalPoints: 5,
            lifetimePoints: 8,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )

        let firstLaunch = BingoViewModel(persistenceDependencies: harness.dependencies)
        firstLaunch.processExpiredTaskCountdowns(now: now)
        XCTAssertNotNil(firstLaunch.expiredTaskEvent)
        let firstPersistedBoard = try XCTUnwrap(harness.boardRepository.loadBoard())
        XCTAssertEqual(BoardEngine.expandedBoardCache(from: firstPersistedBoard)[0][0].countdownEndsAt, expiredAt)

        let relaunched = BingoViewModel(persistenceDependencies: harness.dependencies)
        relaunched.processExpiredTaskCountdowns(now: now)
        XCTAssertNotNil(relaunched.expiredTaskEvent)
        XCTAssertEqual(relaunched.totalPoints, 5)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 8)

        XCTAssertNotNil(relaunched.resolveExpiredTask(.postpone(minutes: 5), now: now))
        XCTAssertEqual(relaunched.cells[0][0].countdownEndsAt, now.addingTimeInterval(5 * 60))
        XCTAssertEqual(relaunched.totalPoints, 5)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 8)
    }

    func testBoardResetWinsWhenResetAndCountdownsExpireAtSameTime() throws {
        let previousReset = makeDate(year: 2026, month: 7, day: 10, hour: 3)
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 3)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Timed task",
            isCompleted: true,
            countdownEndsAt: now,
            estimatedDurationMinutes: 5,
            lastCompletedAt: makeDate(year: 2026, month: 7, day: 10, hour: 20)
        )
        var board = makeNamedBoard(
            cells: cells,
            mode: .resetStatusNextDay,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousReset,
            updatedAt: previousReset
        )
        board.countdownEndsAt = now

        let resetBoard = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
            board,
            now: now,
            calendar: fixedCalendar
        )
        let resetCell = try XCTUnwrap(resetBoard.board.fullBoardCells?[0][0])
        XCTAssertFalse(resetCell.isCompleted)
        XCTAssertNil(resetCell.countdownEndsAt)
        XCTAssertNil(resetCell.estimatedDurationMinutes)
        XCTAssertNil(resetBoard.countdownEndsAt)

        let harness = makeInMemoryViewModelHarness(
            savedBoard: resetBoard.board,
            savedAt: now,
            countdownEndsAt: resetBoard.countdownEndsAt,
            totalPoints: 9,
            lifetimePoints: 12,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        viewModel.processExpiredCountdowns(now: now)
        viewModel.processExpiredTaskCountdowns(now: now)

        XCTAssertNil(viewModel.expiredBoardCountdownEvent)
        XCTAssertNil(viewModel.expiredTaskEvent)
        XCTAssertEqual(viewModel.totalPoints, 9)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 12)
    }

    func testBoardTaskPointRegressionMatrixDimensionsStayComplete() {
        let coveredResetModes = Set(BoardTaskResetMode.allCases.map(\.rawValue))
        let expectedResetModes: Set<String> = [
            BoardTaskResetMode.resetStatusNextDay.rawValue,
            BoardTaskResetMode.clearTasksNextDay.rawValue,
            BoardTaskResetMode.customResetStatusTime.rawValue,
            BoardTaskResetMode.keepTaskStatus.rawValue
        ]
        XCTAssertEqual(
            coveredResetModes,
            expectedResetModes,
            "A new board reset mode must be added to the fixed board-task-points regression matrix."
        )

        let coveredRecurrenceKinds = Set(
            MatrixTaskKind.allCases.compactMap { $0.recurrenceKind?.rawValue }
        )
        XCTAssertEqual(
            coveredRecurrenceKinds,
            Set(TaskRecurrenceRule.Kind.allCases.map(\.rawValue)),
            "A new task recurrence kind must be added to MatrixTaskKind."
        )
        XCTAssertEqual(
            MatrixTaskKind.allCases.filter { $0.recurrenceKind == nil },
            [.regular],
            "The unplanned regular task must remain an explicit matrix case."
        )
        XCTAssertEqual(BoardTaskResetMode.allCases.count * MatrixTaskKind.allCases.count, 24)
    }

    func testEveryBoardResetModeTaskKindAndPointLifecycleCombination() throws {
        let previousReset = makeDate(year: 2026, month: 7, day: 10, hour: 3)
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 3, minute: 1)
        let baselineTotalPoints = 20
        let baselineLifetimePoints = 30

        for resetMode in BoardTaskResetMode.allCases {
            for taskKind in MatrixTaskKind.allCases {
                let scenario = "\(resetMode.rawValue) / \(taskKind.rawValue)"
                let sourceCell = makeMatrixTaskCell(
                    kind: taskKind,
                    previousReset: previousReset,
                    now: now
                )
                var fullBoard = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
                fullBoard[0][0] = sourceCell
                let namedBoard = makeNamedBoard(
                    cells: fullBoard,
                    mode: resetMode,
                    customResetMinutes: resetMode == .customResetStatusTime ? 3 * 60 : nil,
                    lastTaskResetAppliedAt: previousReset,
                    updatedAt: previousReset
                )

                let resetResult = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(
                    namedBoard,
                    now: now,
                    calendar: fixedCalendar
                )
                let taskShouldSurvive = resetMode != .clearTasksNextDay || taskKind != .regular
                let taskShouldRemainCompleted = resetMode == .keepTaskStatus
                let resetCell = try XCTUnwrap(
                    resetResult.board.fullBoardCells?[0][0],
                    "Missing reset cell for \(scenario)"
                )

                XCTAssertEqual(resetCell.hasStoredTask, taskShouldSurvive, scenario)
                XCTAssertEqual(
                    resetCell.isCompleted,
                    taskShouldSurvive && taskShouldRemainCompleted,
                    scenario
                )
                XCTAssertEqual(
                    resetResult.lastTaskResetAppliedAt,
                    resetMode == .keepTaskStatus ? previousReset : now,
                    scenario
                )

                let harness = makeInMemoryViewModelHarness(
                    savedBoard: resetResult.board,
                    savedAt: now,
                    countdownEndsAt: resetResult.countdownEndsAt,
                    totalPoints: baselineTotalPoints,
                    lifetimePoints: baselineLifetimePoints,
                    dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
                )
                let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
                viewModel.applySavedBoardSnapshot(
                    resetResult.board,
                    countdownEndsAt: resetResult.countdownEndsAt,
                    referenceDate: now
                )

                assertPersistedPoints(
                    viewModel: viewModel,
                    repository: harness.pointsRepository,
                    total: baselineTotalPoints,
                    lifetime: baselineLifetimePoints,
                    scenario: "\(scenario) after reset"
                )

                guard taskShouldSurvive else {
                    viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(1))
                    assertPersistedPoints(
                        viewModel: viewModel,
                        repository: harness.pointsRepository,
                        total: baselineTotalPoints,
                        lifetime: baselineLifetimePoints,
                        scenario: "\(scenario) removed task cannot score"
                    )
                    continue
                }

                if taskShouldRemainCompleted {
                    viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(1))
                    assertPersistedPoints(
                        viewModel: viewModel,
                        repository: harness.pointsRepository,
                        total: baselineTotalPoints - 1,
                        lifetime: baselineLifetimePoints,
                        scenario: "\(scenario) undo"
                    )
                    viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(2))
                    assertPersistedPoints(
                        viewModel: viewModel,
                        repository: harness.pointsRepository,
                        total: baselineTotalPoints,
                        lifetime: baselineLifetimePoints + 1,
                        scenario: "\(scenario) recomplete"
                    )
                } else {
                    viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(1))
                    assertPersistedPoints(
                        viewModel: viewModel,
                        repository: harness.pointsRepository,
                        total: baselineTotalPoints + 1,
                        lifetime: baselineLifetimePoints + 1,
                        scenario: "\(scenario) complete"
                    )
                    viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(2))
                    assertPersistedPoints(
                        viewModel: viewModel,
                        repository: harness.pointsRepository,
                        total: baselineTotalPoints,
                        lifetime: baselineLifetimePoints + 1,
                        scenario: "\(scenario) undo"
                    )
                    viewModel.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(3))
                    assertPersistedPoints(
                        viewModel: viewModel,
                        repository: harness.pointsRepository,
                        total: baselineTotalPoints + 1,
                        lifetime: baselineLifetimePoints + 2,
                        scenario: "\(scenario) recomplete"
                    )
                }
            }
        }
    }

    func testBoardSnapshotSettlementNeverReplaysPointsAcrossGridSizesAndLineShapes() {
        let now = makeDate(year: 2026, month: 7, day: 11, hour: 10)

        for gridSize in 2...BoardEngine.maxGridSize {
            for shape in MatrixScoringShape.allCases {
                let scenario = "\(gridSize)x\(gridSize) / \(shape.rawValue)"
                var cells = BoardEngine.createEmptyGrid(size: gridSize)
                for row in 0..<gridSize {
                    for col in 0..<gridSize {
                        cells[row][col] = BingoCell(
                            text: "Task \(row)-\(col)",
                            isCompleted: shape.isCompleted(row: row, col: col, size: gridSize),
                            lastCompletedAt: now
                        )
                    }
                }

                let completedLines = BoardEngine.completedLines(in: cells, size: gridSize)
                let isFullBoard = BoardEngine.isBoardFullyCompleted(cells)
                let expectedPoints = shape.completedTaskCount(size: gridSize)
                    + (shape.completedLineCount(size: gridSize) * 5)
                    + (shape == .fullBoard ? 10 : 0)
                XCTAssertEqual(completedLines.count, shape.completedLineCount(size: gridSize), scenario)
                XCTAssertEqual(isFullBoard, shape == .fullBoard, scenario)
                XCTAssertEqual(
                    BoardEngine.boardScore(cells: cells, completedLines: completedLines),
                    expectedPoints,
                    scenario
                )

                let firstSettlement = BingoRewardSettlement.settle(
                    input: BingoRewardSettlementInput(
                        date: now,
                        cells: cells,
                        completedLines: completedLines,
                        isBoardFullyCompleted: isFullBoard,
                        totalPoints: 0,
                        lifetimePoints: 0,
                        dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
                    ),
                    mode: .normal
                )
                XCTAssertEqual(firstSettlement.totalPoints, 0, scenario)
                XCTAssertEqual(firstSettlement.lifetimePoints, 0, scenario)
                XCTAssertEqual(
                    firstSettlement.dailyRewardState,
                    BingoRewardSettlement.dailyRewardSnapshot(
                        for: now,
                        cells: cells,
                        completedLines: completedLines,
                        isBoardFullyCompleted: isFullBoard
                    ),
                    scenario
                )

                let repeatedSettlement = BingoRewardSettlement.settle(
                    input: BingoRewardSettlementInput(
                        date: now,
                        cells: cells,
                        completedLines: completedLines,
                        isBoardFullyCompleted: isFullBoard,
                        totalPoints: firstSettlement.totalPoints,
                        lifetimePoints: firstSettlement.lifetimePoints,
                        dailyRewardState: firstSettlement.dailyRewardState
                    ),
                    mode: .normal
                )
                XCTAssertEqual(repeatedSettlement.totalPoints, 0, scenario)
                XCTAssertEqual(repeatedSettlement.lifetimePoints, 0, scenario)
            }
        }
    }

    private enum MatrixTaskKind: String, CaseIterable {
        case regular
        case oneTime
        case daily
        case weekly
        case monthlyDay
        case everyNDays

        var recurrenceKind: TaskRecurrenceRule.Kind? {
            switch self {
            case .regular: nil
            case .oneTime: .some(.none)
            case .daily: .daily
            case .weekly: .weekly
            case .monthlyDay: .monthlyDay
            case .everyNDays: .everyNDays
            }
        }
    }

    private enum MatrixScoringShape: String, CaseIterable {
        case singleCell
        case row
        case column
        case mainDiagonal
        case antiDiagonal
        case fullBoard

        func isCompleted(row: Int, col: Int, size: Int) -> Bool {
            switch self {
            case .singleCell: row == 0 && col == 0
            case .row: row == 0
            case .column: col == 0
            case .mainDiagonal: row == col
            case .antiDiagonal: row + col == size - 1
            case .fullBoard: true
            }
        }

        func completedTaskCount(size: Int) -> Int {
            switch self {
            case .singleCell: 1
            case .row, .column, .mainDiagonal, .antiDiagonal: size
            case .fullBoard: size * size
            }
        }

        func completedLineCount(size: Int) -> Int {
            switch self {
            case .singleCell: 0
            case .row, .column, .mainDiagonal, .antiDiagonal: 1
            case .fullBoard: (size * 2) + 2
            }
        }
    }

    private func makeMatrixTaskCell(
        kind: MatrixTaskKind,
        previousReset: Date,
        now: Date
    ) -> BingoCell {
        let title = "Matrix \(kind.rawValue)"
        let recurrenceRule: TaskRecurrenceRule?
        switch kind {
        case .regular:
            recurrenceRule = nil
        case .oneTime:
            recurrenceRule = TaskRecurrenceRule(kind: .none, anchorDate: now)
        case .daily:
            recurrenceRule = TaskRecurrenceRule(kind: .daily, anchorDate: previousReset)
        case .weekly:
            recurrenceRule = TaskRecurrenceRule(
                kind: .weekly,
                weekdays: [fixedCalendar.component(.weekday, from: now)],
                anchorDate: previousReset
            )
        case .monthlyDay:
            recurrenceRule = TaskRecurrenceRule(
                kind: .monthlyDay,
                monthDay: fixedCalendar.component(.day, from: now),
                anchorDate: previousReset
            )
        case .everyNDays:
            recurrenceRule = TaskRecurrenceRule(
                kind: .everyNDays,
                interval: 2,
                anchorDate: fixedCalendar.date(byAdding: .day, value: -2, to: now)
            )
        }

        return BingoCell(
            text: title,
            residentTaskText: kind == .regular ? nil : title,
            recurrenceRule: recurrenceRule,
            isCompleted: true,
            completionStreakCount: 1,
            lastCompletedAt: previousReset
        )
    }

    private func assertPersistedPoints(
        viewModel: BingoViewModel,
        repository: InMemoryBingoPointsRepository,
        total: Int,
        lifetime: Int,
        scenario: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(viewModel.totalPoints, total, scenario, file: file, line: line)
        XCTAssertEqual(repository.loadTotalPoints(), total, scenario, file: file, line: line)
        XCTAssertEqual(repository.loadLifetimePoints(), lifetime, scenario, file: file, line: line)
    }
}

final class LimitedOfferEntryEligibilityTests: XCTestCase {
    private let config = LimitedTimeOfferConfig(
        isEnabled: true,
        campaignID: "campaign_a",
        offerDuration: 48 * 60 * 60,
        minimumAppVersion: "2.3.0"
    )

    func testBundledFallbackKeepsCurrentCampaignAvailableWhenRemoteConfigIsUnreachable() {
        XCTAssertTrue(LimitedTimeOfferConfig.bundledFallback.isEnabled)
        XCTAssertEqual(
            LimitedTimeOfferConfig.bundledFallback.campaignID,
            LimitedTimeOfferConfig.defaultCampaignID
        )
        XCTAssertEqual(
            LimitedTimeOfferConfig.bundledFallback.offerDuration,
            LimitedTimeOfferConfig.defaultOfferDurationHours * 60 * 60
        )
        XCTAssertEqual(
            LimitedTimeOfferConfig.bundledFallback.minimumAppVersion,
            LimitedTimeOfferConfig.defaultMinimumAppVersion
        )
    }

    func testShowsEntryAfterPaywallExitForNonPremiumUser() {
        let now = makeDate(year: 2026, month: 6, day: 15, hour: 10)

        XCTAssertTrue(LimitedOfferEntryEligibility.shouldShowEntry(
            config: config,
            appVersion: "2.3.0",
            hasPremiumAccess: false,
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: false,
            startedAt: 0,
            campaignID: "",
            now: now
        ))
    }

    func testHidesEntryUntilEntitlementsHaveLoaded() {
        let now = makeDate(year: 2026, month: 6, day: 15, hour: 10)

        XCTAssertFalse(LimitedOfferEntryEligibility.shouldShowEntry(
            config: config,
            appVersion: "2.3.0",
            hasPremiumAccess: false,
            hasCompletedEntitlementRefresh: false,
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: false,
            startedAt: 0,
            campaignID: "",
            now: now
        ))
    }

    func testHidesEntryBeforePaywallExitOrForPremiumUser() {
        let now = makeDate(year: 2026, month: 6, day: 15, hour: 10)

        XCTAssertFalse(LimitedOfferEntryEligibility.shouldShowEntry(
            config: config,
            appVersion: "2.3.0",
            hasPremiumAccess: false,
            hasVisitedPaywallWithoutPurchase: false,
            hasLegacyExposure: false,
            startedAt: 0,
            campaignID: "",
            now: now
        ))
        XCTAssertFalse(LimitedOfferEntryEligibility.shouldShowEntry(
            config: config,
            appVersion: "2.3.0",
            hasPremiumAccess: true,
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: false,
            startedAt: 0,
            campaignID: "",
            now: now
        ))
    }

    func testHidesEntryWhenCurrentCampaignCountdownExpired() {
        let startedAt = makeDate(year: 2026, month: 6, day: 10, hour: 9).timeIntervalSince1970
        let now = makeDate(year: 2026, month: 6, day: 13, hour: 10)

        XCTAssertTrue(LimitedOfferEntryEligibility.hasCountdownExpired(
            config: config,
            startedAt: startedAt,
            campaignID: "campaign_a",
            now: now
        ))
        XCTAssertFalse(LimitedOfferEntryEligibility.shouldShowEntry(
            config: config,
            appVersion: "2.3.0",
            hasPremiumAccess: false,
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: false,
            startedAt: startedAt,
            campaignID: "campaign_a",
            now: now
        ))
    }

    func testDifferentCampaignKeepsExpiredCountdownHistory() {
        let startedAt = makeDate(year: 2026, month: 6, day: 10, hour: 9).timeIntervalSince1970
        let now = makeDate(year: 2026, month: 6, day: 13, hour: 10)

        XCTAssertTrue(LimitedOfferEntryEligibility.hasCountdownExpired(
            config: config,
            startedAt: startedAt,
            campaignID: "old_campaign",
            now: now
        ))
        XCTAssertFalse(LimitedOfferEntryEligibility.shouldShowEntry(
            config: config,
            appVersion: "2.3.0",
            hasPremiumAccess: false,
            hasVisitedPaywallWithoutPurchase: false,
            hasLegacyExposure: true,
            startedAt: startedAt,
            campaignID: "old_campaign",
            now: now
        ))
    }

    func testDifferentCampaignKeepsActiveCountdownHistory() {
        let startedAt = makeDate(year: 2026, month: 6, day: 15, hour: 9).timeIntervalSince1970
        let now = makeDate(year: 2026, month: 6, day: 15, hour: 21)

        XCTAssertFalse(LimitedOfferEntryEligibility.hasCountdownExpired(
            config: config,
            startedAt: startedAt,
            campaignID: "old_campaign",
            now: now
        ))
        XCTAssertTrue(LimitedOfferEntryEligibility.shouldShowEntry(
            config: config,
            appVersion: "2.3.0",
            hasPremiumAccess: false,
            hasVisitedPaywallWithoutPurchase: false,
            hasLegacyExposure: true,
            startedAt: startedAt,
            campaignID: "old_campaign",
            now: now
        ))
    }

    func testMinimumAppVersionGate() {
        XCTAssertTrue(config.isEnabled(forAppVersion: "2.3.0"))
        XCTAssertTrue(config.isEnabled(forAppVersion: "2.4.1"))
        XCTAssertFalse(config.isEnabled(forAppVersion: "2.2.9"))
    }

    func testPremiumAccessHidesButPreservesHomeOfferState() {
        let state = LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: true,
            startedAt: makeDate(year: 2026, month: 6, day: 15, hour: 9).timeIntervalSince1970,
            campaignID: "campaign_a",
            isPresented: true
        )

        let hiddenState = LimitedOfferHomeRules.applyingPremiumAccess(
            to: state,
            hasPremiumAccess: true
        )

        XCTAssertTrue(hiddenState.hasVisitedPaywallWithoutPurchase)
        XCTAssertTrue(hiddenState.hasLegacyExposure)
        XCTAssertEqual(hiddenState.startedAt, state.startedAt)
        XCTAssertEqual(hiddenState.campaignID, state.campaignID)
        XCTAssertFalse(hiddenState.isPresented)
    }

    func testLegacyExposureMigrationPreservesExistingCountdownState() {
        let startedAt = makeDate(year: 2026, month: 6, day: 15, hour: 9).timeIntervalSince1970
        let state = LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: false,
            hasLegacyExposure: false,
            startedAt: startedAt,
            campaignID: "campaign_a",
            isPresented: false
        )

        let migratedState = LimitedOfferHomeRules.applyingLegacyExposureMigration(to: state)

        XCTAssertTrue(migratedState.hasLegacyExposure)
        XCTAssertEqual(migratedState.startedAt, startedAt)
        XCTAssertEqual(migratedState.campaignID, "campaign_a")
    }

    func testCampaignSyncOnlySeedsFreshOfferState() {
        let freshState = LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: false,
            startedAt: 0,
            campaignID: "",
            isPresented: false
        )
        let activeState = LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: false,
            startedAt: makeDate(year: 2026, month: 6, day: 15, hour: 9).timeIntervalSince1970,
            campaignID: "old_campaign",
            isPresented: true
        )

        XCTAssertEqual(
            LimitedOfferHomeRules.applyingCampaignSync(to: freshState, config: config).campaignID,
            "campaign_a"
        )
        XCTAssertEqual(
            LimitedOfferHomeRules.applyingCampaignSync(to: activeState, config: config).campaignID,
            "old_campaign"
        )
    }

    func testPaywallExitWithoutPurchasePreservesAnActiveCountdown() {
        let startedAt = makeDate(year: 2026, month: 6, day: 15, hour: 9).timeIntervalSince1970
        let state = LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: false,
            hasLegacyExposure: true,
            startedAt: startedAt,
            campaignID: "campaign_a",
            isPresented: false
        )

        let updatedState = LimitedOfferHomeRules.applyingPaywallExitWithoutPurchase(to: state)

        XCTAssertTrue(updatedState.hasVisitedPaywallWithoutPurchase)
        XCTAssertEqual(updatedState.startedAt, startedAt)
        XCTAssertEqual(updatedState.campaignID, "campaign_a")
    }

    func testDiscountPagePresentationStartsCountdownOnlyOnce() {
        let firstOpen = makeDate(year: 2026, month: 6, day: 15, hour: 9)
        let secondOpen = makeDate(year: 2026, month: 6, day: 15, hour: 10)
        let state = LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: false,
            startedAt: 0,
            campaignID: "",
            isPresented: true
        )

        let started = LimitedOfferHomeRules.applyingDiscountPagePresentation(
            to: state,
            campaignID: "campaign_a",
            now: firstOpen
        )
        let reopened = LimitedOfferHomeRules.applyingDiscountPagePresentation(
            to: started,
            campaignID: "campaign_a",
            now: secondOpen
        )

        XCTAssertEqual(started.startedAt, firstOpen.timeIntervalSince1970)
        XCTAssertEqual(reopened.startedAt, firstOpen.timeIntervalSince1970)
        XCTAssertEqual(reopened.campaignID, "campaign_a")
    }

    func testConfirmedPurchaseClearsTheWholeOfferState() {
        let state = LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: true,
            startedAt: makeDate(year: 2026, month: 6, day: 15, hour: 9).timeIntervalSince1970,
            campaignID: "campaign_a",
            isPresented: true
        )

        let updatedState = LimitedOfferHomeRules.applyingConfirmedPurchase(to: state)

        XCTAssertFalse(updatedState.hasVisitedPaywallWithoutPurchase)
        XCTAssertFalse(updatedState.hasLegacyExposure)
        XCTAssertEqual(updatedState.startedAt, 0)
        XCTAssertEqual(updatedState.campaignID, "")
        XCTAssertFalse(updatedState.isPresented)
    }
}

final class SubscriptionPriceCacheTests: XCTestCase {
    func testPriceCatalogLoadingStatesAreExplicit() {
        XCTAssertTrue(PaywallPriceCatalogState.loading.isLoading)
        XCTAssertTrue(PaywallPriceCatalogState.refreshing.isLoading)
        XCTAssertFalse(PaywallPriceCatalogState.ready.isLoading)
        XCTAssertFalse(PaywallPriceCatalogState.unavailable.isLoading)
    }

    func testRevenueCatConfigurationIsAvailableAtLaunch() {
        XCTAssertTrue(SubscriptionManager.isRevenueCatConfigurationAllowed())
    }

    func testInitialStorefrontResolutionDoesNotInvalidateSameStorefrontCache() {
        XCTAssertFalse(SubscriptionManager.didStorefrontChange(
            previousStorefrontID: "--",
            currentStorefrontID: "143470"
        ))
        XCTAssertTrue(SubscriptionManager.didStorefrontChange(
            previousStorefrontID: "143470",
            currentStorefrontID: "143443"
        ))
    }

    func testRevenueCatCancelledPurchaseDoesNotBecomePendingOrActivated() {
        XCTAssertEqual(
            SubscriptionManager.purchaseOutcome(
                userCancelled: true,
                hasActivePremiumEntitlement: false
            ),
            .cancelled
        )
    }

    func testOnlyAnActiveEntitlementCompletesPurchase() {
        XCTAssertEqual(
            SubscriptionManager.purchaseOutcome(
                userCancelled: false,
                hasActivePremiumEntitlement: true
            ),
            .activated
        )
        XCTAssertEqual(
            SubscriptionManager.purchaseOutcome(
                userCancelled: false,
                hasActivePremiumEntitlement: false
            ),
            .pending
        )
    }

    func testRevenueCatEntitlementActivatesEvenWhenTransactionIsUnavailable() {
        XCTAssertEqual(
            SubscriptionManager.purchaseOutcome(
                userCancelled: false,
                hasActivePremiumEntitlement: true
            ),
            .activated
        )
    }
}

final class BoardStateCommitterTests: XCTestCase {
    func testWidgetTimelineReloadSchedulerCoalescesRapidRequests() {
        let reloadExpectation = expectation(description: "Widget timeline reload")
        reloadExpectation.expectedFulfillmentCount = 1
        let counter = LockedTestCounter()
        let scheduler = WidgetTimelineReloadScheduler(
            delay: 0.02,
            queue: DispatchQueue(label: "WidgetTimelineReloadSchedulerTests")
        ) {
            counter.increment()
            reloadExpectation.fulfill()
        }

        scheduler.requestReload()
        scheduler.requestReload()
        scheduler.requestReload()

        wait(for: [reloadExpectation], timeout: 1)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(counter.value, 1)
    }

    func testPendingAppTransactionRecoversPartialCommitExactlyOnce() throws {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 14)
        let boardID = UUID()
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Recover task", isCompleted: true)
        let updatedBoard = makeNamedBoard(cells: cells, updatedAt: now).board
        let finalDiaryEntries = BingoDiaryStore.entriesByApplyingExplicitTaskDelta(
            task: "Recover task",
            delta: 1,
            board: updatedBoard,
            on: now,
            entries: [:]
        )
        let rewardState = BingoRewardSettlement.dailyRewardSnapshot(
            for: now,
            cells: updatedBoard.cells,
            completedLines: updatedBoard.completedLines,
            isBoardFullyCompleted: false
        )
        let pending = BingoPendingPersistenceTransaction(
            boardState: BingoPendingPersistenceTransaction.BoardState(
                board: updatedBoard,
                countdownEndsAt: nil,
                savedAt: now,
                associatedBoardID: boardID
            ),
            diaryEntries: finalDiaryEntries,
            totalPoints: 1,
            lifetimePoints: 1,
            dailyRewardState: rewardState
        )
        // Simulate termination after the board write but before diary and points were committed.
        let boardRepository = InMemoryBingoBoardRepository(
            board: updatedBoard,
            savedAt: now,
            activeNamedBoardID: boardID
        )
        let diaryRepository = InMemoryBingoDiaryRepository()
        let pointsRepository = InMemoryBingoPointsRepository(
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let transactionRepository = InMemoryBingoPersistenceTransactionRepository(
            pendingTransaction: pending
        )
        let dependencies = BingoViewModelPersistenceDependencies(
            boardRepository: boardRepository,
            diaryRepository: diaryRepository,
            pointsRepository: pointsRepository,
            transactionRepository: transactionRepository
        )

        let recovery = try XCTUnwrap(
            BingoViewModelPersistence.recoverPendingTransactionIfNeeded(dependencies: dependencies)
        )

        XCTAssertTrue(recovery.updatedDiary)
        XCTAssertTrue(recovery.savedPoints)
        XCTAssertFalse(recovery.failedToSaveTransaction)
        XCTAssertNil(transactionRepository.pendingTransaction)
        XCTAssertEqual(pointsRepository.loadTotalPoints(), 1)
        XCTAssertEqual(pointsRepository.loadLifetimePoints(), 1)
        XCTAssertEqual(
            diaryRepository.loadAllEntriesDictionary().values.first?.completedTaskCounts["Recover task"],
            1
        )

        XCTAssertNil(BingoViewModelPersistence.recoverPendingTransactionIfNeeded(dependencies: dependencies))
        XCTAssertEqual(diaryRepository.replaceCallCount, 1)
        XCTAssertEqual(pointsRepository.loadTotalPoints(), 1)
    }

    func testPersistenceCanonicalizesRepeatingTaskBeforeBoardVerification() {
        let now = makeDate(year: 2026, month: 7, day: 20, hour: 10)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(
            text: "Repeating task",
            residentTaskText: "Repeating task",
            recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [2]),
            startVisibleAt: now,
            endVisibleAt: now.addingTimeInterval(3_600),
            usesRecurringTimeWindow: true,
            startReminderEnabled: true,
            isCompleted: true,
            estimatedDurationMinutes: 30
        )
        cells[0][1] = BingoCell(
            text: "Inactive display projection",
            isDisplayOnlyInactive: true
        )
        let board = makeNamedBoard(cells: cells, updatedAt: now).board
        let canonicalBoard = BingoBoardStore.normalizedBoardForPersistence(
            board,
            referenceDate: now
        )
        XCTAssertNotEqual(board, canonicalBoard)
        XCTAssertTrue(board.fullBoardCells?[0][1].isDisplayOnlyInactive == true)
        XCTAssertFalse(canonicalBoard.fullBoardCells?[0][1].isDisplayOnlyInactive == true)

        let boardRepository = InMemoryBingoBoardRepository(board: nil, savedAt: nil)
        let diaryRepository = InMemoryBingoDiaryRepository(roundTripsThroughCodable: true)
        let pointsRepository = InMemoryBingoPointsRepository(
            totalPoints: 10,
            lifetimePoints: 20,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let transactionRepository = InMemoryBingoPersistenceTransactionRepository()
        let dependencies = BingoViewModelPersistenceDependencies(
            boardRepository: boardRepository,
            diaryRepository: diaryRepository,
            pointsRepository: pointsRepository,
            transactionRepository: transactionRepository
        )

        let result = BingoViewModelPersistence.saveWithExplicitDiaryDelta(
            BingoViewModelPersistenceSnapshot(
                board: board,
                boardCountdownEndsAt: nil,
                totalPoints: 11,
                lifetimePoints: 21,
                dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                    for: now,
                    cells: canonicalBoard.cells,
                    completedLines: canonicalBoard.completedLines,
                    isBoardFullyCompleted: false
                )
            ),
            task: "Repeating task",
            delta: 1,
            savedAt: now,
            dependencies: dependencies
        )

        XCTAssertFalse(result.failedToSaveTransaction)
        XCTAssertTrue(result.savedPoints)
        XCTAssertEqual(boardRepository.board, canonicalBoard)
        XCTAssertEqual(pointsRepository.loadTotalPoints(), 11)
        XCTAssertNil(transactionRepository.pendingTransaction)
    }

    func testFailedBoardSaveStopsDependentWritesAndWidgetReload() {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 10)
        let originalBoard = makeNamedBoard(updatedAt: now).board
        var updatedCells = BoardEngine.expandedBoardCache(from: originalBoard)
        updatedCells[0][0] = BingoCell(text: "Unsaved task")
        let updatedBoard = makeNamedBoard(cells: updatedCells, updatedAt: now.addingTimeInterval(1)).board
        let repository = InMemoryBingoBoardRepository(
            board: originalBoard,
            savedAt: now,
            shouldFailBoardSave: true
        )

        let result = BoardStateCommitter.saveActiveBoardState(
            board: updatedBoard,
            countdownEndsAt: now.addingTimeInterval(600),
            savedAt: now.addingTimeInterval(1),
            associatedBoardID: nil,
            repository: repository,
            reloadWidgets: true
        )

        XCTAssertTrue(result.failedToSaveBoard)
        XCTAssertFalse(result.savedBoardCountdown)
        XCTAssertFalse(result.reloadedWidgets)
        XCTAssertEqual(repository.board, originalBoard)
        XCTAssertEqual(repository.saveCountdownCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    func testViewModelPersistenceSkipsDiaryAndPointsAfterBoardSaveFailure() {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 11)
        let originalBoard = makeNamedBoard(updatedAt: now).board
        var updatedCells = BoardEngine.expandedBoardCache(from: originalBoard)
        updatedCells[0][0] = BingoCell(text: "Completed task", isCompleted: true)
        let updatedBoard = makeNamedBoard(cells: updatedCells, updatedAt: now.addingTimeInterval(1)).board
        let boardRepository = InMemoryBingoBoardRepository(
            board: originalBoard,
            savedAt: now,
            shouldFailBoardSave: true
        )
        let diaryRepository = InMemoryBingoDiaryRepository()
        let pointsRepository = InMemoryBingoPointsRepository(
            totalPoints: 3,
            lifetimePoints: 5,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let dependencies = BingoViewModelPersistenceDependencies(
            boardRepository: boardRepository,
            diaryRepository: diaryRepository,
            pointsRepository: pointsRepository,
            transactionRepository: InMemoryBingoPersistenceTransactionRepository()
        )

        let result = BingoViewModelPersistence.saveWithExplicitDiaryDelta(
            BingoViewModelPersistenceSnapshot(
                board: updatedBoard,
                boardCountdownEndsAt: nil,
                totalPoints: 4,
                lifetimePoints: 6,
                dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                    for: now,
                    cells: updatedBoard.cells,
                    completedLines: updatedBoard.completedLines,
                    isBoardFullyCompleted: false
                )
            ),
            task: "Completed task",
            delta: 1,
            savedAt: now.addingTimeInterval(1),
            dependencies: dependencies
        )

        XCTAssertTrue(result.failedToSaveBoard)
        XCTAssertFalse(result.updatedDiary)
        XCTAssertFalse(result.savedPoints)
        XCTAssertEqual(diaryRepository.replaceCallCount, 0)
        XCTAssertEqual(pointsRepository.loadTotalPoints(), 3)
        XCTAssertEqual(pointsRepository.loadLifetimePoints(), 5)
    }

    func testSaveActiveBoardStateSkipsUnchangedBoardCountdownAndWidgetReload() {
        let now = makeDate(year: 2026, month: 6, day: 19, hour: 9)
        let countdownEndsAt = now.addingTimeInterval(30 * 60)
        let board = makeNamedBoard(updatedAt: now).board
        let repository = InMemoryBingoBoardRepository(
            board: board,
            savedAt: now,
            countdownEndsAt: countdownEndsAt
        )

        let result = BoardStateCommitter.saveActiveBoardState(
            board: board,
            countdownEndsAt: countdownEndsAt,
            savedAt: now,
            associatedBoardID: nil,
            repository: repository,
            reloadWidgets: true
        )

        XCTAssertFalse(result.savedBoard)
        XCTAssertFalse(result.savedBoardCountdown)
        XCTAssertFalse(result.reloadedWidgets)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.saveCountdownCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    func testSaveActiveBoardStateReloadsOnceWhenCountdownChanges() {
        let now = makeDate(year: 2026, month: 6, day: 19, hour: 10)
        let board = makeNamedBoard(updatedAt: now).board
        let repository = InMemoryBingoBoardRepository(board: board, savedAt: now)
        let countdownEndsAt = now.addingTimeInterval(45 * 60)

        let result = BoardStateCommitter.saveActiveBoardState(
            board: board,
            countdownEndsAt: countdownEndsAt,
            savedAt: now,
            associatedBoardID: nil,
            repository: repository,
            reloadWidgets: true
        )

        XCTAssertFalse(result.savedBoard)
        XCTAssertTrue(result.savedBoardCountdown)
        XCTAssertTrue(result.reloadedWidgets)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.saveCountdownCallCount, 1)
        XCTAssertEqual(repository.reloadWidgetCallCount, 1)
    }

    func testReloadWidgetsIfNeededReloadsOnceWhenNamedBoardsChange() {
        let repository = InMemoryBingoBoardRepository(board: nil, savedAt: nil)
        var result = BoardStateCommitResult()
        result.savedNamedBoards = true

        BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)
        BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)

        XCTAssertTrue(result.reloadedWidgets)
        XCTAssertEqual(repository.reloadWidgetCallCount, 1)
    }
}

private final class LockedTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

final class BingoViewModelPersistenceGuardrailTests: XCTestCase {
    func testInvalidPersistedGridSizeIsClampedDuringInitialization() {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 12)
        let malformedBoard = SavedBoard(
            gridSize: -1,
            cells: [],
            completedLines: [],
            fullBoardCells: BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: malformedBoard, savedAt: now)

        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        XCTAssertEqual(viewModel.gridSize, 2)
        XCTAssertEqual(viewModel.cells.count, 2)
        XCTAssertEqual(viewModel.cells.first?.count, 2)
        XCTAssertEqual(harness.boardRepository.board?.gridSize, 2)
    }

    func testDuplicateIDRepairPreservesPausedCountdownAndTimeoutMarker() throws {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 13)
        let duplicateID = UUID()
        var fullBoard = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        fullBoard[0][0] = BingoCell(id: duplicateID, text: "First task")
        fullBoard[0][1] = BingoCell(
            id: duplicateID,
            text: "Paused task",
            countdownPausedRemainingSeconds: 180,
            estimatedDurationMinutes: 10,
            lastVisibilityWindowTimeoutAt: now
        )
        let visibleCells = BoardEngine.projectVisibleCells(from: fullBoard, size: 2, referenceDate: now)
        let savedBoard = SavedBoard(
            gridSize: 2,
            cells: visibleCells,
            completedLines: [],
            fullBoardCells: fullBoard
        )
        let harness = makeInMemoryViewModelHarness(savedBoard: savedBoard, savedAt: now)

        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        let firstCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        let repairedCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 1))
        XCTAssertNotEqual(firstCell.id, repairedCell.id)
        XCTAssertEqual(repairedCell.countdownPausedRemainingSeconds, 180)
        XCTAssertEqual(repairedCell.lastVisibilityWindowTimeoutAt, now)
    }
}

final class TaskEditRuleEngineTests: XCTestCase {
    func testIdentityChangeClearsCompletionAndStartsClampedCountdown() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 9)
        let previousCell = BingoCell(
            text: "Old task",
            isCompleted: true,
            countdownEndsAt: now.addingTimeInterval(600),
            countdownPausedRemainingSeconds: 300,
            estimatedDurationMinutes: 10,
            completionStreakCount: 3,
            lastCompletedAt: now.addingTimeInterval(-60)
        )

        let result = TaskEditRuleEngine.apply(
            makeInput(
                previousCell: previousCell,
                text: "New task",
                referenceDate: now,
                estimatedDurationMinutes: 45,
                maxCountdownMinutes: 30
            )
        )

        XCTAssertEqual(result.cell.storedTaskText, "New task")
        XCTAssertFalse(result.cell.isCompleted)
        XCTAssertEqual(result.cell.completionStreakCount, 0)
        XCTAssertNil(result.cell.lastCompletedAt)
        XCTAssertEqual(result.cell.estimatedDurationMinutes, 30)
        XCTAssertEqual(
            result.cell.countdownEndsAt?.timeIntervalSince(now) ?? 0,
            30 * 60,
            accuracy: 0.001
        )
    }

    func testSameIdentityPreservesCompletionHistory() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 10)
        let lastCompletedAt = now.addingTimeInterval(-300)
        let previousCell = BingoCell(
            text: "Focus",
            isCompleted: true,
            completionStreakCount: 2,
            lastCompletedAt: lastCompletedAt
        )

        let result = TaskEditRuleEngine.apply(
            makeInput(
                previousCell: previousCell,
                text: "Focus",
                referenceDate: now
            )
        )

        XCTAssertTrue(result.cell.isCompleted)
        XCTAssertEqual(result.cell.completionStreakCount, 2)
        XCTAssertEqual(result.cell.lastCompletedAt, lastCompletedAt)
        XCTAssertNil(result.cell.countdownEndsAt)
    }

    func testWeeklyRuleDropsUnsupportedTimingReminderAndCountdown() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 11)
        let submittedStart = now.addingTimeInterval(60 * 60)
        let submittedEnd = now.addingTimeInterval(2 * 60 * 60)
        let expectedWeekday = fixedCalendar.component(.weekday, from: submittedStart)

        let result = TaskEditRuleEngine.apply(
            makeInput(
                previousCell: BingoCell(),
                text: "Weekly task",
                referenceDate: now,
                recurrenceRule: TaskRecurrenceRule(kind: .weekly),
                estimatedDurationMinutes: 20,
                startVisibleAt: submittedStart,
                endVisibleAt: submittedEnd,
                startReminderEnabled: true
            )
        )

        XCTAssertEqual(result.cell.recurrenceRule?.kind, .weekly)
        XCTAssertEqual(result.cell.recurrenceRule?.weekdays, [expectedWeekday])
        XCTAssertEqual(result.cell.residentTaskText, "Weekly task")
        XCTAssertNil(result.normalizedStartVisibleAt)
        XCTAssertNil(result.normalizedEndVisibleAt)
        XCTAssertFalse(result.cell.startReminderEnabled)
        XCTAssertNil(result.cell.estimatedDurationMinutes)
        XCTAssertNil(result.cell.countdownEndsAt)
    }

    func testInvalidEndDateDisablesReminderWithoutDroppingStartDate() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 12)
        let submittedStart = now.addingTimeInterval(60 * 60)

        let result = TaskEditRuleEngine.apply(
            makeInput(
                previousCell: BingoCell(),
                text: "Planned task",
                referenceDate: now,
                startVisibleAt: submittedStart,
                endVisibleAt: submittedStart,
                startReminderEnabled: true
            )
        )

        XCTAssertEqual(result.normalizedStartVisibleAt, submittedStart)
        XCTAssertNil(result.normalizedEndVisibleAt)
        XCTAssertFalse(result.cell.startReminderEnabled)
    }

    func testEmptyEditClearsTaskOwnedState() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 13)
        let previousCell = BingoCell(
            text: "Task",
            residentTaskText: "Task",
            residentWeekdays: [2],
            recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [2]),
            startVisibleAt: now,
            endVisibleAt: now.addingTimeInterval(3600),
            usesRecurringTimeWindow: true,
            startReminderEnabled: true,
            isTaskHidden: true,
            isCompleted: true,
            isForced: true,
            countdownEndsAt: now.addingTimeInterval(1800),
            countdownPausedRemainingSeconds: 600,
            estimatedDurationMinutes: 30,
            completionStreakCount: 4,
            lastCompletedAt: now,
            lastVisibilityWindowTimeoutAt: now
        )

        let result = TaskEditRuleEngine.apply(
            makeInput(
                previousCell: previousCell,
                text: "  \n",
                referenceDate: now
            )
        )

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.cell.id, previousCell.id)
        XCTAssertTrue(result.cell.storedTaskText.isEmpty)
        XCTAssertFalse(result.cell.isCompleted)
        XCTAssertFalse(result.cell.isForced)
        XCTAssertFalse(result.cell.isTaskHidden)
        XCTAssertFalse(result.cell.startReminderEnabled)
        XCTAssertNil(result.cell.recurrenceRule)
        XCTAssertNil(result.cell.startVisibleAt)
        XCTAssertNil(result.cell.endVisibleAt)
        XCTAssertNil(result.cell.estimatedDurationMinutes)
        XCTAssertNil(result.cell.countdownEndsAt)
        XCTAssertNil(result.cell.countdownPausedRemainingSeconds)
        XCTAssertEqual(result.cell.completionStreakCount, 0)
        XCTAssertNil(result.cell.lastCompletedAt)
        XCTAssertNil(result.cell.lastVisibilityWindowTimeoutAt)
    }

    private func makeInput(
        previousCell: BingoCell,
        text: String,
        referenceDate: Date,
        isForced: Bool = false,
        residentWeekdays: Set<Int> = [],
        isOneTimeTask: Bool = false,
        recurrenceRule: TaskRecurrenceRule? = nil,
        estimatedDurationMinutes: Int? = nil,
        startVisibleAt: Date? = nil,
        endVisibleAt: Date? = nil,
        startReminderEnabled: Bool = false,
        startReminderOffsetMinutes: Int = BingoCell.defaultStartReminderOffsetMinutes,
        maxCountdownMinutes: Int = 30 * 24 * 60
    ) -> TaskEditRuleInput {
        TaskEditRuleInput(
            previousCell: previousCell,
            text: text,
            isForced: isForced,
            residentWeekdays: residentWeekdays,
            isOneTimeTask: isOneTimeTask,
            recurrenceRule: recurrenceRule,
            estimatedDurationMinutes: estimatedDurationMinutes,
            startVisibleAt: startVisibleAt,
            endVisibleAt: endVisibleAt,
            startReminderEnabled: startReminderEnabled,
            startReminderOffsetMinutes: startReminderOffsetMinutes,
            referenceDate: referenceDate,
            calendar: fixedCalendar,
            maxTaskLength: 20,
            maxCountdownMinutes: maxCountdownMinutes
        )
    }
}

final class TaskCountdownRuleEngineTests: XCTestCase {
    func testSetClampsDurationAndStartsCountdown() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 14)

        let updatedCell = try XCTUnwrap(
            apply(
                cell: BingoCell(text: "Focus"),
                action: .set(minutes: 45),
                referenceDate: now,
                maxCountdownMinutes: 30
            )
        )

        XCTAssertEqual(updatedCell.estimatedDurationMinutes, 30)
        XCTAssertEqual(
            updatedCell.countdownEndsAt?.timeIntervalSince(now) ?? 0,
            30 * 60,
            accuracy: 0.001
        )
        XCTAssertNil(updatedCell.countdownPausedRemainingSeconds)
    }

    func testSetRejectsCompletedAndRepeatingTasks() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 15)
        let completedCell = BingoCell(text: "Done", isCompleted: true)
        let repeatingCell = BingoCell(
            text: "Repeat",
            residentTaskText: "Repeat",
            recurrenceRule: TaskRecurrenceRule(kind: .daily)
        )

        XCTAssertNil(
            apply(cell: completedCell, action: .set(minutes: 10), referenceDate: now)
        )
        XCTAssertNil(
            apply(cell: repeatingCell, action: .set(minutes: 10), referenceDate: now)
        )
    }

    func testPauseRoundsRemainingTimeUp() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 16)
        let cell = BingoCell(
            text: "Focus",
            countdownEndsAt: now.addingTimeInterval(60.2),
            estimatedDurationMinutes: 10
        )

        let updatedCell = try XCTUnwrap(
            apply(cell: cell, action: .pause, referenceDate: now)
        )

        XCTAssertNil(updatedCell.countdownEndsAt)
        XCTAssertEqual(updatedCell.countdownPausedRemainingSeconds, 61)
    }

    func testResumeCapsDeadlineAtVisibilityEnd() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 17)
        let endVisibleAt = now.addingTimeInterval(30)
        let cell = BingoCell(
            text: "Focus",
            startVisibleAt: now.addingTimeInterval(-60),
            endVisibleAt: endVisibleAt,
            countdownPausedRemainingSeconds: 120,
            estimatedDurationMinutes: 10
        )

        let updatedCell = try XCTUnwrap(
            apply(cell: cell, action: .resume, referenceDate: now)
        )

        XCTAssertEqual(updatedCell.countdownEndsAt, endVisibleAt)
        XCTAssertNil(updatedCell.countdownPausedRemainingSeconds)
    }

    func testSetNilClearsCountdownState() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 18)
        let cell = BingoCell(
            text: "Focus",
            countdownEndsAt: now.addingTimeInterval(600),
            countdownPausedRemainingSeconds: 300,
            estimatedDurationMinutes: 10
        )

        let updatedCell = try XCTUnwrap(
            apply(cell: cell, action: .set(minutes: nil), referenceDate: now)
        )

        XCTAssertNil(updatedCell.estimatedDurationMinutes)
        XCTAssertNil(updatedCell.countdownEndsAt)
        XCTAssertNil(updatedCell.countdownPausedRemainingSeconds)
    }

    private func apply(
        cell: BingoCell,
        action: TaskCountdownRuleAction,
        referenceDate: Date,
        maxCountdownMinutes: Int = 30 * 24 * 60
    ) -> BingoCell? {
        TaskCountdownRuleEngine.apply(
            TaskCountdownRuleInput(
                cell: cell,
                action: action,
                referenceDate: referenceDate,
                calendar: fixedCalendar,
                maxCountdownMinutes: maxCountdownMinutes
            )
        )
    }
}

final class VisibleCellMutationRuleEngineTests: XCTestCase {
    func testToggleHiddenRequiresCompletedUnlockedTask() throws {
        let completedCell = BingoCell(text: "Done", isCompleted: true)

        let updatedCell = try XCTUnwrap(
            apply(currentCell: completedCell, action: .toggleTaskHidden)
        )

        XCTAssertEqual(updatedCell.id, completedCell.id)
        XCTAssertTrue(updatedCell.isTaskHidden)
        XCTAssertNil(
            apply(
                currentCell: completedCell,
                action: .toggleTaskHidden,
                isLocked: true
            )
        )
        XCTAssertNil(
            apply(
                currentCell: BingoCell(text: "Pending"),
                action: .toggleTaskHidden
            )
        )
        XCTAssertNil(
            apply(currentCell: BingoCell(), action: .toggleTaskHidden)
        )
    }

    func testDeleteReturnsFreshEmptyCellAndRejectsEmptyCell() throws {
        let originalCell = BingoCell(text: "Task", isCompleted: true)

        let updatedCell = try XCTUnwrap(
            apply(currentCell: originalCell, action: .delete)
        )

        XCTAssertTrue(updatedCell.isEmpty)
        XCTAssertNotEqual(updatedCell.id, originalCell.id)
        XCTAssertNil(apply(currentCell: BingoCell(), action: .delete))
    }

    func testRestoreProjectsCellForReferenceDate() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 20)
        let storedCell = BingoCell(
            text: "Planned task",
            startVisibleAt: now.addingTimeInterval(3600),
            endVisibleAt: now.addingTimeInterval(7200),
            isTaskHidden: true,
            isCompleted: true,
            isForced: true,
            countdownEndsAt: now.addingTimeInterval(1800),
            estimatedDurationMinutes: 30
        )

        let restoredCell = try XCTUnwrap(
            apply(
                currentCell: BingoCell(),
                action: .restore(storedCell),
                referenceDate: now
            )
        )

        XCTAssertEqual(restoredCell.id, storedCell.id)
        XCTAssertEqual(restoredCell.startVisibleAt, storedCell.startVisibleAt)
        XCTAssertEqual(restoredCell.endVisibleAt, storedCell.endVisibleAt)
        XCTAssertTrue(restoredCell.isDisplayOnlyInactive)
        XCTAssertFalse(restoredCell.isCompleted)
        XCTAssertFalse(restoredCell.isTaskHidden)
        XCTAssertFalse(restoredCell.isForced)
        XCTAssertNil(restoredCell.countdownEndsAt)
    }

    private func apply(
        currentCell: BingoCell,
        action: VisibleCellMutationAction,
        isLocked: Bool = false,
        referenceDate: Date = makeDate(year: 2026, month: 7, day: 17, hour: 20)
    ) -> BingoCell? {
        VisibleCellMutationRuleEngine.apply(
            VisibleCellMutationRuleInput(
                currentCell: currentCell,
                action: action,
                isLocked: isLocked,
                referenceDate: referenceDate,
                calendar: fixedCalendar
            )
        )
    }
}

final class BoardCellMoveRuleEngineTests: XCTestCase {
    func testMoveSwapsCompleteCellStateWithoutMutatingInput() throws {
        let sourceCell = BingoCell(
            text: "Source",
            isTaskHidden: true,
            isCompleted: true,
            completionStreakCount: 3
        )
        let destinationCell = BingoCell(
            text: "Destination",
            countdownPausedRemainingSeconds: 120,
            estimatedDurationMinutes: 10
        )
        var cells = BoardEngine.createEmptyGrid(size: 2)
        cells[0][0] = sourceCell
        cells[1][1] = destinationCell

        let updatedCells = try XCTUnwrap(
            apply(cells: cells, source: (0, 0), destination: (1, 1))
        )

        XCTAssertEqual(updatedCells[0][0], destinationCell)
        XCTAssertEqual(updatedCells[1][1], sourceCell)
        XCTAssertEqual(cells[0][0], sourceCell)
        XCTAssertEqual(cells[1][1], destinationCell)
    }

    func testMoveRejectsInvalidSameAndEmptySourcePositions() {
        var cells = BoardEngine.createEmptyGrid(size: 2)
        cells[0][0] = BingoCell(text: "Source")

        XCTAssertNil(apply(cells: cells, source: (-1, 0), destination: (0, 1)))
        XCTAssertNil(apply(cells: cells, source: (0, 0), destination: (0, -1)))
        XCTAssertNil(apply(cells: cells, source: (0, 0), destination: (2, 0)))
        XCTAssertNil(apply(cells: cells, source: (0, 0), destination: (0, 0)))
        XCTAssertNil(apply(cells: cells, source: (1, 1), destination: (0, 0)))
    }

    func testMoveRejectsLockedSourceOrDestination() {
        var cells = BoardEngine.createEmptyGrid(size: 2)
        cells[0][0] = BingoCell(text: "Source")

        XCTAssertNil(
            apply(
                cells: cells,
                source: (0, 0),
                destination: (0, 1),
                isSourceLocked: true
            )
        )
        XCTAssertNil(
            apply(
                cells: cells,
                source: (0, 0),
                destination: (0, 1),
                isDestinationLocked: true
            )
        )
    }

    private func apply(
        cells: [[BingoCell]],
        source: (row: Int, col: Int),
        destination: (row: Int, col: Int),
        isSourceLocked: Bool = false,
        isDestinationLocked: Bool = false
    ) -> [[BingoCell]]? {
        BoardCellMoveRuleEngine.apply(
            BoardCellMoveRuleInput(
                cells: cells,
                source: source,
                destination: destination,
                isSourceLocked: isSourceLocked,
                isDestinationLocked: isDestinationLocked
            )
        )
    }
}

final class BoardOrderedCellsRuleEngineTests: XCTestCase {
    func testApplyClampsGridAndNormalizesLegacyCellFields() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 9)
        let inputCell = BingoCell(
            text: " 123456789 ",
            residentWeekdays: [0, 2, 8],
            startVisibleMonth: 7,
            startVisibleDay: 19,
            isForced: true
        )

        let result = apply(
            orderedCells: [inputCell],
            targetGridSize: 1,
            maxTaskLength: 5,
            referenceDate: now
        )

        XCTAssertEqual(result.gridSize, 2)
        XCTAssertEqual(result.fullBoardCells.count, BoardEngine.maxGridSize)
        XCTAssertEqual(result.fullBoardCells[0][0].text, "12345")
        XCTAssertEqual(
            result.fullBoardCells[0][0].startVisibleAt,
            makeDate(year: 2026, month: 7, day: 19)
        )
        XCTAssertNil(result.fullBoardCells[0][0].startVisibleMonth)
        XCTAssertNil(result.fullBoardCells[0][0].startVisibleDay)
        XCTAssertEqual(result.fullBoardCells[0][0].residentWeekdays, [2])
        XCTAssertFalse(result.fullBoardCells[0][0].isForced)
        XCTAssertEqual(result.appliedTasks.map(\.text), ["12345"])
        XCTAssertEqual(result.appliedTasks.first?.startMonth, 7)
        XCTAssertEqual(result.appliedTasks.first?.startDay, 19)
    }

    func testApplyDropsUnsupportedRepeatingTimingButPreservesTaskState() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 10)
        let cellID = UUID()
        let inputCell = BingoCell(
            id: cellID,
            text: "Repeat",
            recurrenceRule: TaskRecurrenceRule(kind: .daily),
            startVisibleAt: now,
            endVisibleAt: now.addingTimeInterval(3600),
            usesRecurringTimeWindow: true,
            startReminderEnabled: true,
            isCompleted: true,
            isForced: true,
            countdownEndsAt: now.addingTimeInterval(1800),
            countdownPausedRemainingSeconds: 300,
            estimatedDurationMinutes: 30,
            completionStreakCount: 4,
            lastCompletedAt: now,
            lastVisibilityWindowTimeoutAt: now
        )

        let result = apply(
            orderedCells: [inputCell],
            targetGridSize: 2,
            referenceDate: now
        )
        let normalizedCell = result.fullBoardCells[0][0]

        XCTAssertEqual(normalizedCell.id, cellID)
        XCTAssertEqual(normalizedCell.residentTaskText, "Repeat")
        XCTAssertEqual(normalizedCell.recurrenceRule?.kind, .daily)
        XCTAssertTrue(normalizedCell.isCompleted)
        XCTAssertEqual(normalizedCell.completionStreakCount, 4)
        XCTAssertEqual(normalizedCell.lastCompletedAt, now)
        XCTAssertFalse(normalizedCell.isForced)
        XCTAssertFalse(normalizedCell.startReminderEnabled)
        XCTAssertFalse(normalizedCell.usesRecurringTimeWindow)
        XCTAssertNil(normalizedCell.startVisibleAt)
        XCTAssertNil(normalizedCell.endVisibleAt)
        XCTAssertNil(normalizedCell.countdownEndsAt)
        XCTAssertNil(normalizedCell.countdownPausedRemainingSeconds)
        XCTAssertNil(normalizedCell.estimatedDurationMinutes)
        XCTAssertNil(normalizedCell.lastVisibilityWindowTimeoutAt)
    }

    func testApplyClipsCellsOutsideTargetGridAndRejectsInvalidEndDate() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 11)
        let startVisibleAt = now.addingTimeInterval(3600)
        let cells = [
            BingoCell(text: "A", startVisibleAt: startVisibleAt, endVisibleAt: startVisibleAt),
            BingoCell(text: "B"),
            BingoCell(text: "C"),
            BingoCell(text: "D"),
            BingoCell(text: "Outside")
        ]

        let result = apply(
            orderedCells: cells,
            targetGridSize: 2,
            referenceDate: now
        )

        XCTAssertNil(result.fullBoardCells[0][0].endVisibleAt)
        XCTAssertEqual(result.fullBoardCells[0][1].storedTaskText, "B")
        XCTAssertEqual(result.fullBoardCells[1][0].storedTaskText, "C")
        XCTAssertEqual(result.fullBoardCells[1][1].storedTaskText, "D")
        XCTAssertFalse(result.fullBoardCells.flatMap { $0 }.contains { $0.storedTaskText == "Outside" })
        XCTAssertEqual(result.appliedTasks.map(\.text), ["A", "B", "C", "D"])
    }

    private func apply(
        orderedCells: [BingoCell?],
        targetGridSize: Int,
        maxTaskLength: Int = BingoViewModel.maxTaskLength,
        referenceDate: Date
    ) -> BoardOrderedCellsRuleResult {
        BoardOrderedCellsRuleEngine.apply(
            BoardOrderedCellsRuleInput(
                orderedCells: orderedCells,
                targetGridSize: targetGridSize,
                minimumGridSize: 2,
                maximumGridSize: BoardEngine.maxGridSize,
                maxTaskLength: maxTaskLength,
                referenceDate: referenceDate,
                calendar: fixedCalendar
            )
        )
    }
}

final class QuickEditGroupRenameTests: XCTestCase {
    func testRenameGroupNormalizesNameAndKeepsTasks() {
        let groupID = UUID()
        let task = MyTaskItem(text: "Keep this task")
        var library = MyTasksLibrary(
            groups: [MyTaskGroup(id: groupID, name: "Original", tasks: [task])]
        )

        let result = quickEditRenameGroup(groupID, nameDraft: "  Updated name  ", library: &library)

        XCTAssertEqual(result, .renamed)
        XCTAssertEqual(library.groups.first?.name, "Updated name")
        XCTAssertEqual(library.groups.first?.tasks, [task])
    }

    func testRenameGroupRejectsEmptyNameWithoutChangingGroup() {
        let groupID = UUID()
        var library = MyTasksLibrary(groups: [MyTaskGroup(id: groupID, name: "Original")])

        let result = quickEditRenameGroup(groupID, nameDraft: "   ", library: &library)

        XCTAssertEqual(result, .invalid)
        XCTAssertEqual(library.groups.first?.name, "Original")
    }
}

final class QuickEditPreviewAppendTests: XCTestCase {
    func testAppendingGroupTasksPreservesBoardTasksAndReportsOverflow() {
        let firstGroupTask = MyTaskItem(text: "Group task one")
        let secondGroupTask = MyTaskItem(text: "Group task two")
        let thirdGroupTask = MyTaskItem(text: "Group task three")
        let firstKey = quickEditTaskKey(firstGroupTask)
        let secondKey = quickEditTaskKey(secondGroupTask)
        let thirdKey = quickEditTaskKey(thirdGroupTask)
        let candidates = [
            firstKey: firstGroupTask,
            secondKey: secondGroupTask,
            thirdKey: thirdGroupTask
        ]
        let initialSlots = [
            QuickEditPreviewSlot(cellState: BingoCell(text: "Existing first")),
            QuickEditPreviewSlot(),
            QuickEditPreviewSlot(cellState: BingoCell(text: "Existing second")),
            QuickEditPreviewSlot()
        ]

        let result = quickEditAppendTasksToPreview(
            keys: [firstKey, secondKey, thirdKey],
            candidateTaskMap: candidates,
            currentSlots: initialSlots
        )

        XCTAssertEqual(result.updatedSlots.map { $0.task?.text }, [
            "Existing first",
            "Group task one",
            "Existing second",
            "Group task two"
        ])
        XCTAssertEqual(result.addedTaskCount, 2)
        XCTAssertEqual(result.omittedTaskCount, 1)
    }
}

final class TaskHistoryStoreTests: XCTestCase {
    func testArchiveBoardRetainsVisibleAndHiddenBoardTasksForQuickEditHistory() {
        let visibleTask = MyTaskItem(text: "Deleted board visible \(UUID().uuidString)")
        let hiddenTask = MyTaskItem(text: "Deleted board hidden \(UUID().uuidString)")
        let visibleKey = TaskHistoryStore.makeKey(for: visibleTask)
        let hiddenKey = TaskHistoryStore.makeKey(for: hiddenTask)
        defer {
            TaskHistoryStore.deleteRecord(withKey: visibleKey)
            TaskHistoryStore.deleteRecord(withKey: hiddenKey)
        }

        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        fullBoardCells[0][0] = BingoCell(text: visibleTask.text)
        fullBoardCells[4][4] = BingoCell(text: hiddenTask.text)
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 2,
            referenceDate: .now
        )
        let board = SavedBoard(
            gridSize: 2,
            cells: visibleCells,
            completedLines: [],
            fullBoardCells: fullBoardCells
        )

        XCTAssertTrue(TaskHistoryStore.archive(board: board))

        let historyKeys = Set(TaskHistoryStore.load().map(\.key))
        XCTAssertTrue(historyKeys.contains(visibleKey))
        XCTAssertTrue(historyKeys.contains(hiddenKey))
    }
}

final class BingoViewModelSideEffectCountTests: XCTestCase {
    func testTaskEditCommitsEachPersistenceSideEffectOnce() {
        let now = Date()
        let boardID = UUID()
        let taskText = "Guard-\(UUID().uuidString.prefix(8))"
        let historyTask = MyTaskItem(text: taskText)
        let historyKey = TaskHistoryStore.makeKey(for: historyTask)
        defer { TaskHistoryStore.deleteRecord(withKey: historyKey) }

        let harness = makeInMemoryViewModelHarness(
            savedBoard: makeSavedBoardForViewModel(cell: BingoCell(), referenceDate: now),
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now),
            activeNamedBoardID: boardID
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        let baseline = persistenceSideEffectCounts(for: harness)
        var cellsPublicationCount = 0
        let cellsCancellable = viewModel.$cells
            .dropFirst()
            .sink { _ in cellsPublicationCount += 1 }

        viewModel.updateTask(
            row: 0,
            col: 0,
            text: taskText,
            isForced: false,
            residentWeekdays: []
        )

        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertEqual(cellsPublicationCount, 1)
        XCTAssertEqual(harness.boardRepository.loadBoard()?.cells[0][0].storedTaskText, taskText)
        XCTAssertEqual(harness.boardRepository.loadActiveNamedBoardID(), boardID)
        withExtendedLifetime(cellsCancellable) {}
    }

    func testForcedTaskEditPublishesCellsOnceAndClearsCachedForcedTask() throws {
        let now = Date()
        let boardID = UUID()
        let taskText = "Force-\(UUID().uuidString.prefix(8))"
        let historyTask = MyTaskItem(text: taskText)
        let historyKey = TaskHistoryStore.makeKey(for: historyTask)
        defer { TaskHistoryStore.deleteRecord(withKey: historyKey) }

        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        fullBoardCells[4][4] = BingoCell(text: "Cached forced", isForced: true)
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 2,
            referenceDate: now
        )
        let savedBoard = SavedBoard(
            gridSize: 2,
            cells: visibleCells,
            completedLines: [],
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now),
            activeNamedBoardID: boardID
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        let baseline = persistenceSideEffectCounts(for: harness)
        var cellsPublicationCount = 0
        let cellsCancellable = viewModel.$cells
            .dropFirst()
            .sink { _ in cellsPublicationCount += 1 }

        viewModel.updateTask(
            row: 0,
            col: 1,
            text: taskText,
            isForced: true,
            residentWeekdays: []
        )

        let persistedFullBoardCells = try XCTUnwrap(
            harness.boardRepository.loadBoard()?.fullBoardCells
        )
        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertEqual(cellsPublicationCount, 1)
        XCTAssertTrue(viewModel.cells[0][1].isForced)
        XCTAssertFalse(persistedFullBoardCells[4][4].isForced)
        XCTAssertTrue(persistedFullBoardCells[0][1].isForced)
        withExtendedLifetime(cellsCancellable) {}
    }

    func testTaskCompletionCommitsEachPersistenceSideEffectOnce() {
        let now = Date()
        let boardID = UUID()
        let harness = makeInMemoryViewModelHarness(
            savedBoard: makeSavedBoardForViewModel(
                cell: BingoCell(text: "Complete once"),
                referenceDate: now
            ),
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now),
            activeNamedBoardID: boardID
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        let baseline = persistenceSideEffectCounts(for: harness)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now)

        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertEqual(viewModel.totalPoints, 1)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 1)
        XCTAssertEqual(
            harness.diaryRepository.loadAllEntriesDictionary().values.first?
                .completedTaskCounts["Complete once"],
            1
        )
    }

    func testTaskCompletionDoesNotReversePointWhenPersistedLedgerLagsBoard() {
        let now = makeDate(year: 2026, month: 7, day: 20, hour: 12)
        let cellID = UUID()
        let harness = makeInMemoryViewModelHarness(
            savedBoard: makeSavedBoardForViewModel(
                cell: BingoCell(id: cellID, text: "Sync-safe completion"),
                referenceDate: now
            ),
            savedAt: now,
            totalPoints: 337,
            lifetimePoints: 773,
            dailyRewardState: DailyRewardState(
                dateKey: PointsStore.dateKey(for: now),
                rewardedCellIDs: [cellID],
                peakCompletedLineCount: 0,
                fullBoardRewardGranted: false
            )
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now)

        XCTAssertTrue(viewModel.cells[0][0].isCompleted)
        XCTAssertEqual(viewModel.totalPoints, 338)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 338)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 774)
        XCTAssertEqual(harness.pointsRepository.loadDailyRewardState()?.rewardedCellIDs, [cellID])
    }

    func testTaskCompletionRebasesNewerPersistedPointsBeforeSaving() {
        let now = makeDate(year: 2026, month: 7, day: 20, hour: 12)
        let cellID = UUID()
        let board = makeSavedBoardForViewModel(
            cell: BingoCell(id: cellID, text: "Widget already changed points"),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: board,
            savedAt: now,
            totalPoints: 337,
            lifetimePoints: 773,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        // Simulate a WidgetKit process updating the shared points file while the
        // already-open app still has the old totals in memory.
        XCTAssertTrue(harness.pointsRepository.saveState(
            totalPoints: 345,
            lifetimePoints: 780,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        ))

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now)

        XCTAssertTrue(viewModel.cells[0][0].isCompleted)
        XCTAssertEqual(viewModel.totalPoints, 346)
        XCTAssertEqual(harness.pointsRepository.loadTotalPoints(), 346)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 781)
    }

    func testTaskCountdownActionsPublishAndCommitOnceEach() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 19)
        let boardID = UUID()
        let harness = makeInMemoryViewModelHarness(
            savedBoard: makeSavedBoardForViewModel(
                cell: BingoCell(text: "Countdown task"),
                referenceDate: now
            ),
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now),
            activeNamedBoardID: boardID
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        var baseline = persistenceSideEffectCounts(for: harness)
        var cellsPublicationCount = 0
        let cellsCancellable = viewModel.$cells
            .dropFirst()
            .sink { _ in cellsPublicationCount += 1 }

        XCTAssertTrue(viewModel.setTaskCountdown(row: 0, col: 0, minutes: 20, referenceDate: now))
        assertSinglePersistenceCommit(after: baseline, harness: harness)
        baseline = persistenceSideEffectCounts(for: harness)

        XCTAssertTrue(
            viewModel.pauseTaskCountdown(
                row: 0,
                col: 0,
                referenceDate: now.addingTimeInterval(60)
            )
        )
        assertSinglePersistenceCommit(after: baseline, harness: harness)
        baseline = persistenceSideEffectCounts(for: harness)

        XCTAssertTrue(
            viewModel.resumeTaskCountdown(
                row: 0,
                col: 0,
                referenceDate: now.addingTimeInterval(120)
            )
        )
        assertSinglePersistenceCommit(after: baseline, harness: harness)
        baseline = persistenceSideEffectCounts(for: harness)

        XCTAssertTrue(
            viewModel.cancelTaskCountdown(
                row: 0,
                col: 0,
                referenceDate: now.addingTimeInterval(180)
            )
        )
        assertSinglePersistenceCommit(after: baseline, harness: harness)

        XCTAssertEqual(cellsPublicationCount, 4)
        let finalCell = try XCTUnwrap(viewModel.editingCell(row: 0, col: 0))
        XCTAssertNil(finalCell.estimatedDurationMinutes)
        XCTAssertNil(finalCell.countdownEndsAt)
        XCTAssertNil(finalCell.countdownPausedRemainingSeconds)
        withExtendedLifetime(cellsCancellable) {}
    }

    func testVisibleCellMutationsPublishAndCommitOnceWithoutChangingPoints() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 21)
        let boardID = UUID()
        let taskText = "Mutation-\(UUID().uuidString.prefix(8))"
        let historyTask = MyTaskItem(text: taskText)
        let historyKey = TaskHistoryStore.makeKey(for: historyTask)
        defer { TaskHistoryStore.deleteRecord(withKey: historyKey) }

        let savedBoard = makeSavedBoardForViewModel(
            cell: BingoCell(text: taskText, isCompleted: true),
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 9,
            lifetimePoints: 12,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: savedBoard.cells,
                completedLines: savedBoard.completedLines,
                isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(savedBoard.cells)
            ),
            activeNamedBoardID: boardID
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        var baseline = persistenceSideEffectCounts(for: harness)
        var cellsPublicationCount = 0
        let cellsCancellable = viewModel.$cells
            .dropFirst()
            .sink { _ in cellsPublicationCount += 1 }

        viewModel.toggleTaskHidden(row: 0, col: 0)
        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertTrue(viewModel.cells[0][0].isTaskHidden)
        XCTAssertEqual(viewModel.totalPoints, 9)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 12)
        baseline = persistenceSideEffectCounts(for: harness)

        let deletedCell = try XCTUnwrap(viewModel.deleteCell(row: 0, col: 0))
        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertTrue(viewModel.cells[0][0].isEmpty)
        XCTAssertEqual(viewModel.totalPoints, 9)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 12)
        baseline = persistenceSideEffectCounts(for: harness)

        viewModel.restoreCell(deletedCell, row: 0, col: 0)
        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertEqual(viewModel.cells[0][0].id, deletedCell.id)
        XCTAssertEqual(viewModel.cells[0][0].storedTaskText, taskText)
        XCTAssertEqual(viewModel.totalPoints, 9)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 12)
        XCTAssertEqual(cellsPublicationCount, 3)
        XCTAssertEqual(harness.boardRepository.loadBoard()?.fullBoardCells?[0][0].id, deletedCell.id)
        withExtendedLifetime(cellsCancellable) {}
    }

    func testVisibleCellMutationsRejectNegativeCoordinatesWithoutSideEffects() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 22)
        let harness = makeInMemoryViewModelHarness(
            savedBoard: makeSavedBoardForViewModel(
                cell: BingoCell(text: "Task", isCompleted: true),
                referenceDate: now
            ),
            savedAt: now,
            totalPoints: 1,
            lifetimePoints: 1,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        let baseline = persistenceSideEffectCounts(for: harness)
        var cellsPublicationCount = 0
        let cellsCancellable = viewModel.$cells
            .dropFirst()
            .sink { _ in cellsPublicationCount += 1 }

        viewModel.toggleTaskHidden(row: -1, col: 0)
        XCTAssertNil(viewModel.deleteCell(row: 0, col: -1))
        viewModel.restoreCell(BingoCell(text: "Restored"), row: -1, col: -1)

        XCTAssertEqual(persistenceSideEffectCounts(for: harness), baseline)
        XCTAssertEqual(cellsPublicationCount, 0)
        XCTAssertEqual(viewModel.cells[0][0].storedTaskText, "Task")
        withExtendedLifetime(cellsCancellable) {}
    }

    func testMoveCellPublishesAndCommitsOnceWithoutChangingPoints() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 23)
        let sourceCell = BingoCell(text: "Source", isCompleted: true)
        let destinationCell = BingoCell(text: "Destination")
        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        fullBoardCells[0][0] = sourceCell
        fullBoardCells[1][1] = destinationCell
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 2,
            referenceDate: now
        )
        let savedBoard = SavedBoard(
            gridSize: 2,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(in: visibleCells, size: 2),
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 9,
            lifetimePoints: 12,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: savedBoard.cells,
                completedLines: savedBoard.completedLines,
                isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(savedBoard.cells)
            )
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        var baseline = persistenceSideEffectCounts(for: harness)
        var cellsPublicationCount = 0
        let cellsCancellable = viewModel.$cells
            .dropFirst()
            .sink { _ in cellsPublicationCount += 1 }

        viewModel.moveCell(from: (0, 0), to: (1, 1))

        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertEqual(viewModel.cells[0][0].id, destinationCell.id)
        XCTAssertEqual(viewModel.cells[1][1].id, sourceCell.id)
        XCTAssertEqual(viewModel.totalPoints, 9)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 12)
        XCTAssertEqual(cellsPublicationCount, 1)
        XCTAssertEqual(harness.boardRepository.loadBoard()?.fullBoardCells?[1][1].id, sourceCell.id)

        baseline = persistenceSideEffectCounts(for: harness)
        viewModel.moveCell(from: (-1, 0), to: (0, 0))
        viewModel.moveCell(from: (0, 0), to: (0, 0))
        XCTAssertEqual(persistenceSideEffectCounts(for: harness), baseline)
        XCTAssertEqual(cellsPublicationCount, 1)
        withExtendedLifetime(cellsCancellable) {}
    }

    func testMoveCellEnforcesForcedTaskLockWithoutSideEffects() {
        let now = makeDate(year: 2026, month: 7, day: 18, hour: 0)
        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        fullBoardCells[0][0] = BingoCell(text: "Forced", isForced: true)
        fullBoardCells[0][1] = BingoCell(text: "Locked destination")
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 2,
            referenceDate: now
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: SavedBoard(
                gridSize: 2,
                cells: visibleCells,
                completedLines: [],
                fullBoardCells: fullBoardCells
            ),
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        let baseline = persistenceSideEffectCounts(for: harness)
        var cellsPublicationCount = 0
        let cellsCancellable = viewModel.$cells
            .dropFirst()
            .sink { _ in cellsPublicationCount += 1 }

        viewModel.moveCell(from: (0, 0), to: (0, 1))

        XCTAssertEqual(persistenceSideEffectCounts(for: harness), baseline)
        XCTAssertEqual(viewModel.cells[0][0].storedTaskText, "Forced")
        XCTAssertEqual(viewModel.cells[0][1].storedTaskText, "Locked destination")
        XCTAssertEqual(cellsPublicationCount, 0)
        withExtendedLifetime(cellsCancellable) {}
    }

    func testTaskCompletionMotionUsesSingleTaskOnlyWhenNoBingoIsCreated() throws {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 10)
        let harness = makeInMemoryViewModelHarness(
            savedBoard: makeSavedBoardForViewModel(
                cell: BingoCell(text: "One task"),
                referenceDate: now
            ),
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now)

        let motion = try XCTUnwrap(viewModel.taskCompletionMotion)
        XCTAssertEqual(motion.kind, .singleTask)
        XCTAssertEqual(motion.triggeringCell, .init(row: 0, col: 0))
        XCTAssertTrue(motion.bingoCells.isEmpty)
        XCTAssertNil(viewModel.boardCompletionAnimationID)
    }

    func testTaskCompletionMotionUsesNewBingoLineCells() throws {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 11)
        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        for row in 0..<3 {
            for col in 0..<3 {
                fullBoardCells[row][col] = BingoCell(
                    text: "Task \(row)-\(col)",
                    isCompleted: row == 0 && col < 2
                )
            }
        }
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 3,
            referenceDate: now
        )
        let savedBoard = SavedBoard(
            gridSize: 3,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(in: visibleCells, size: 3),
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 0, col: 2, referenceDate: now)

        let motion = try XCTUnwrap(viewModel.taskCompletionMotion)
        XCTAssertEqual(motion.kind, .bingo)
        XCTAssertEqual(
            motion.bingoCells,
            Set((0..<3).map { .init(row: 0, col: $0) })
        )
        XCTAssertNil(viewModel.boardCompletionAnimationID)
    }

    func testFullBoardCompletionSuppressesCellMotionAndPresentsFullScreenFlow() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 12)
        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        for row in 0..<2 {
            for col in 0..<2 {
                fullBoardCells[row][col] = BingoCell(
                    text: "Task \(row)-\(col)",
                    isCompleted: row != 1 || col != 1
                )
            }
        }
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 2,
            referenceDate: now
        )
        let savedBoard = SavedBoard(
            gridSize: 2,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(in: visibleCells, size: 2),
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 1, col: 1, referenceDate: now)

        XCTAssertNil(viewModel.taskCompletionMotion)
        XCTAssertNotNil(viewModel.boardCompletionAnimationID)
    }

    func testResizeGridCancelsInFlightTaskCompletionMotion() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 13)
        let harness = makeInMemoryViewModelHarness(
            savedBoard: makeSavedBoardForViewModel(
                cell: BingoCell(text: "One task"),
                referenceDate: now
            ),
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 0, col: 0, referenceDate: now)
        XCTAssertNotNil(viewModel.taskCompletionMotion)

        viewModel.resizeGrid(to: 3)

        XCTAssertNil(viewModel.taskCompletionMotion)
    }

    func testResizeGridClearsCelebrationWithoutChangingAccumulatedPoints() {
        let now = makeDate(year: 2026, month: 7, day: 18, hour: 1)
        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        for row in 0..<2 {
            for col in 0..<2 {
                fullBoardCells[row][col] = BingoCell(
                    text: "Task \(row)-\(col)",
                    isCompleted: row != 1 || col != 1
                )
            }
        }
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 2,
            referenceDate: now
        )
        let savedBoard = SavedBoard(
            gridSize: 2,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(in: visibleCells, size: 2),
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: savedBoard.cells,
                completedLines: savedBoard.completedLines,
                isBoardFullyCompleted: false
            )
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 1, col: 1, referenceDate: now)

        XCTAssertTrue(viewModel.showCelebration)
        XCTAssertTrue(viewModel.showBoardCompletionAnimation)
        XCTAssertFalse(viewModel.newlyCompletedLines.isEmpty)
        let accumulatedPoints = viewModel.totalPoints
        let lifetimePoints = harness.pointsRepository.loadLifetimePoints()
        let baseline = persistenceSideEffectCounts(for: harness)

        viewModel.resizeGrid(to: 3)

        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertEqual(viewModel.gridSize, 3)
        XCTAssertFalse(viewModel.showCelebration)
        XCTAssertFalse(viewModel.showBoardCompletionAnimation)
        XCTAssertTrue(viewModel.newlyCompletedLines.isEmpty)
        XCTAssertEqual(viewModel.totalPoints, accumulatedPoints)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), lifetimePoints)
    }

    func testNewBingoCelebrationSupersedesPendingDismissal() {
        let now = makeDate(year: 2026, month: 7, day: 18, hour: 2)
        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        for row in 0..<2 {
            for col in 0..<3 {
                fullBoardCells[row][col] = BingoCell(
                    text: "Task \(row)-\(col)",
                    isCompleted: col < 2
                )
            }
        }
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 3,
            referenceDate: now
        )
        let savedBoard = SavedBoard(
            gridSize: 3,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(in: visibleCells, size: 3),
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        var pendingDismissals: [() -> Void] = []
        let viewModel = BingoViewModel(
            persistenceDependencies: harness.dependencies,
            bingoCelebrationDismissScheduler: { _, action in
                pendingDismissals.append(action)
            }
        )

        viewModel.toggleComplete(row: 0, col: 2, referenceDate: now)
        XCTAssertTrue(viewModel.showCelebration)
        XCTAssertEqual(pendingDismissals.count, 1)

        viewModel.toggleComplete(
            row: 1,
            col: 2,
            referenceDate: now.addingTimeInterval(0.15)
        )
        let secondCelebrationLines = viewModel.newlyCompletedLines
        XCTAssertFalse(secondCelebrationLines.isEmpty)
        XCTAssertEqual(pendingDismissals.count, 2)

        pendingDismissals.removeFirst()()
        XCTAssertTrue(viewModel.showCelebration)
        XCTAssertEqual(viewModel.newlyCompletedLines, secondCelebrationLines)

        pendingDismissals.removeFirst()()
        XCTAssertFalse(viewModel.showCelebration)
        XCTAssertTrue(viewModel.newlyCompletedLines.isEmpty)
    }

    func testStaleBoardCompletionCallbackCannotDismissRecompletionAnimation() throws {
        let now = makeDate(year: 2026, month: 7, day: 18, hour: 3)
        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        for row in 0..<2 {
            for col in 0..<2 {
                fullBoardCells[row][col] = BingoCell(
                    text: "Task \(row)-\(col)",
                    isCompleted: row != 1 || col != 1
                )
            }
        }
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 2,
            referenceDate: now
        )
        let savedBoard = SavedBoard(
            gridSize: 2,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(in: visibleCells, size: 2),
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            totalPoints: 0,
            lifetimePoints: 0,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: savedBoard.cells,
                completedLines: savedBoard.completedLines,
                isBoardFullyCompleted: false
            )
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        viewModel.toggleComplete(row: 1, col: 1, referenceDate: now)
        let firstAnimationID = try XCTUnwrap(viewModel.boardCompletionAnimationID)

        viewModel.toggleComplete(row: 1, col: 1, referenceDate: now.addingTimeInterval(1))
        XCTAssertNil(viewModel.boardCompletionAnimationID)

        viewModel.toggleComplete(row: 1, col: 1, referenceDate: now.addingTimeInterval(2))
        let secondAnimationID = try XCTUnwrap(viewModel.boardCompletionAnimationID)
        XCTAssertNotEqual(secondAnimationID, firstAnimationID)

        XCTAssertFalse(viewModel.dismissBoardCompletionAnimation(id: firstAnimationID))
        XCTAssertEqual(viewModel.boardCompletionAnimationID, secondAnimationID)
        XCTAssertTrue(viewModel.showBoardCompletionAnimation)

        XCTAssertTrue(viewModel.dismissBoardCompletionAnimation(id: secondAnimationID))
        XCTAssertNil(viewModel.boardCompletionAnimationID)
        XCTAssertFalse(viewModel.showBoardCompletionAnimation)
    }

    func testApplyBoardOrderedCellsPublishesAndCommitsOnceWithoutChangingPoints() {
        let now = Date()
        let taskText = "Quick-\(UUID().uuidString.prefix(8))"
        let historyTask = MyTaskItem(text: taskText)
        let historyKey = TaskHistoryStore.makeKey(for: historyTask)
        defer { TaskHistoryStore.deleteRecord(withKey: historyKey) }

        var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        fullBoardCells[0][0] = BingoCell(text: "Completed", isCompleted: true)
        fullBoardCells[4][4] = BingoCell(text: "Cached")
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoardCells,
            size: 2,
            referenceDate: now
        )
        let savedBoard = SavedBoard(
            gridSize: 2,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(in: visibleCells, size: 2),
            fullBoardCells: fullBoardCells
        )
        let harness = makeInMemoryViewModelHarness(
            savedBoard: savedBoard,
            savedAt: now,
            countdownEndsAt: now.addingTimeInterval(600),
            totalPoints: 9,
            lifetimePoints: 12,
            dailyRewardState: BingoRewardSettlement.dailyRewardSnapshot(
                for: now,
                cells: savedBoard.cells,
                completedLines: savedBoard.completedLines,
                isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(savedBoard.cells)
            )
        )
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)
        let baseline = persistenceSideEffectCounts(for: harness)
        var cellsPublicationCount = 0
        let cellsCancellable = viewModel.$cells
            .dropFirst()
            .sink { _ in cellsPublicationCount += 1 }

        viewModel.applyBoardOrderedCells(
            [BingoCell(text: taskText, isForced: true)],
            targetGridSize: 2
        )

        assertSinglePersistenceCommit(after: baseline, harness: harness)
        XCTAssertEqual(cellsPublicationCount, 1)
        XCTAssertEqual(viewModel.cells[0][0].storedTaskText, taskText)
        XCTAssertFalse(viewModel.cells[0][0].isForced)
        XCTAssertTrue(harness.boardRepository.loadBoard()?.fullBoardCells?[4][4].isEmpty == true)
        XCTAssertNil(viewModel.boardCountdownEndsAt)
        XCTAssertEqual(viewModel.totalPoints, 9)
        XCTAssertEqual(harness.pointsRepository.loadLifetimePoints(), 12)
        withExtendedLifetime(cellsCancellable) {}
    }

    private struct PersistenceSideEffectCounts: Equatable {
        let boardSaves: Int
        let diaryReplacements: Int
        let pointsStateSaves: Int
        let transactionSaves: Int
        let transactionClears: Int
        let widgetReloads: Int
    }

    private func persistenceSideEffectCounts(
        for harness: InMemoryViewModelHarness
    ) -> PersistenceSideEffectCounts {
        PersistenceSideEffectCounts(
            boardSaves: harness.boardRepository.saveBoardCallCount,
            diaryReplacements: harness.diaryRepository.replaceCallCount,
            pointsStateSaves: harness.pointsRepository.saveStateCallCount,
            transactionSaves: harness.transactionRepository.saveCallCount,
            transactionClears: harness.transactionRepository.clearCallCount,
            widgetReloads: harness.boardRepository.reloadWidgetCallCount
        )
    }

    private func assertSinglePersistenceCommit(
        after baseline: PersistenceSideEffectCounts,
        harness: InMemoryViewModelHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(harness.boardRepository.saveBoardCallCount - baseline.boardSaves, 1, file: file, line: line)
        XCTAssertEqual(harness.diaryRepository.replaceCallCount - baseline.diaryReplacements, 1, file: file, line: line)
        XCTAssertEqual(harness.pointsRepository.saveStateCallCount - baseline.pointsStateSaves, 1, file: file, line: line)
        XCTAssertEqual(harness.transactionRepository.saveCallCount - baseline.transactionSaves, 1, file: file, line: line)
        XCTAssertEqual(harness.transactionRepository.clearCallCount - baseline.transactionClears, 1, file: file, line: line)
        XCTAssertEqual(harness.boardRepository.reloadWidgetCallCount - baseline.widgetReloads, 1, file: file, line: line)
    }
}

final class BoardManagementStoreTests: XCTestCase {
    @MainActor
    func testSelectBoardReportsSelectionSideEffects() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 8)
        let firstBoard = makeNamedBoard(updatedAt: now)
        let secondBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: firstBoard.id,
                boards: [firstBoard, secondBoard]
            )
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [firstBoard, secondBoard]
        store.selectedBoardID = firstBoard.id
        store.hasLoadedBoardSwitcherState = true

        let result = store.selectBoard(
            secondBoard.id,
            currentBoard: firstBoard.board,
            currentCountdownEndsAt: firstBoard.countdownEndsAt
        )

        XCTAssertEqual(result?.selectedBoard.id, secondBoard.id)
        XCTAssertEqual(store.selectedBoardID, secondBoard.id)
        XCTAssertTrue(result?.didChangeSelection == true)
        XCTAssertTrue(result?.shouldInvalidateCountdownTickSchedule == true)
        XCTAssertTrue(result?.shouldSyncTaskReminders == true)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.persistedSelectedBoardID, secondBoard.id)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, secondBoard.id)
        XCTAssertEqual(repository.persistedWidgetPanelID, secondBoard.id)
    }

    @MainActor
    func testWidgetBoardSelectionUpdatesHomeAndActiveBoardMirror() throws {
        let now = makeDate(year: 2026, month: 7, day: 12, hour: 14)
        let boards = (1...5).map { index in
            var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
            cells[0][0] = BingoCell(text: "Board \(index)")
            return makeNamedBoard(cells: cells, updatedAt: now.addingTimeInterval(Double(index)))
        }
        let boardFive = boards[4]
        let boardFour = boards[3]
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: boardFive.id,
                boards: boards
            ),
            board: boardFive.board,
            savedAt: boardFive.updatedAt,
            countdownEndsAt: boardFive.countdownEndsAt,
            activeNamedBoardID: boardFive.id
        )
        repository.saveSelectedWidgetPanelID(boardFive.id)

        var result = try XCTUnwrap(
            WidgetBoardSelectionService.selectBoard(boardFour.id, repository: repository)
        )
        BoardStateCommitter.reloadWidgetsIfNeeded(&result, repository: repository)

        XCTAssertEqual(repository.persistedSelectedBoardID, boardFour.id)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, boardFour.id)
        XCTAssertEqual(repository.persistedWidgetPanelID, boardFour.id)
        XCTAssertEqual(repository.loadBoard(), boardFour.board)
        XCTAssertTrue(result.reloadedWidgets)
    }

    @MainActor
    func testSelectBoardRejectsUnknownIDWithoutPersisting() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 8, minute: 30)
        let namedBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            )
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        let result = store.selectBoard(
            UUID(),
            currentBoard: namedBoard.board,
            currentCountdownEndsAt: namedBoard.countdownEndsAt
        )

        XCTAssertNil(result)
        XCTAssertEqual(store.selectedBoardID, namedBoard.id)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 0)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    @MainActor
    func testSelectBoardRollsBackWhenNamedSnapshotSaveFails() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 17, minute: 30)
        let firstBoard = makeNamedBoard(updatedAt: now)
        let secondBoard = makeNamedBoard(updatedAt: now.addingTimeInterval(60))
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: firstBoard.id,
                boards: [firstBoard, secondBoard]
            ),
            board: firstBoard.board,
            savedAt: firstBoard.updatedAt,
            countdownEndsAt: firstBoard.countdownEndsAt,
            activeNamedBoardID: firstBoard.id,
            namedBoardsSaveFailureCount: 1
        )
        repository.saveSelectedWidgetPanelID(firstBoard.id)
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [firstBoard, secondBoard]
        store.selectedBoardID = firstBoard.id
        store.hasLoadedBoardSwitcherState = true

        let result = store.selectBoard(
            secondBoard.id,
            currentBoard: firstBoard.board,
            currentCountdownEndsAt: firstBoard.countdownEndsAt
        )

        XCTAssertNil(result)
        XCTAssertEqual(store.selectedBoardID, firstBoard.id)
        XCTAssertEqual(store.namedBoards.map(\.id), [firstBoard.id, secondBoard.id])
        XCTAssertEqual(repository.persistedSelectedBoardID, firstBoard.id)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, firstBoard.id)
        XCTAssertEqual(repository.persistedWidgetPanelID, firstBoard.id)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    @MainActor
    func testCreateBoardReportsReminderAndScheduleSideEffects() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 8, minute: 45)
        let namedBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            )
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        let result = store.createBoard(
            nameDraft: "Second",
            currentBoard: namedBoard.board,
            currentCountdownEndsAt: namedBoard.countdownEndsAt
        )

        XCTAssertEqual(result?.selectedBoard.name, "Second")
        XCTAssertEqual(store.selectedBoardID, result?.selectedBoard.id)
        XCTAssertTrue(result?.didChangeSelection == true)
        XCTAssertTrue(result?.shouldInvalidateCountdownTickSchedule == true)
        XCTAssertTrue(result?.shouldSyncTaskReminders == true)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
    }

    @MainActor
    func testCreateBoardRollsBackWhenNamedSnapshotSaveFails() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 17, minute: 45)
        let namedBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            ),
            board: namedBoard.board,
            savedAt: namedBoard.updatedAt,
            countdownEndsAt: namedBoard.countdownEndsAt,
            activeNamedBoardID: namedBoard.id,
            namedBoardsSaveFailureCount: 1
        )
        repository.saveSelectedWidgetPanelID(namedBoard.id)
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        let result = store.createBoard(
            nameDraft: "Not persisted",
            currentBoard: namedBoard.board,
            currentCountdownEndsAt: namedBoard.countdownEndsAt
        )

        XCTAssertNil(result)
        XCTAssertEqual(store.namedBoards, [namedBoard])
        XCTAssertEqual(store.selectedBoardID, namedBoard.id)
        XCTAssertEqual(repository.loadNamedBoardsSnapshot().boards, [namedBoard])
        XCTAssertEqual(repository.persistedActiveNamedBoardID, namedBoard.id)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    @MainActor
    func testMarkSelectedBoardAsStarterGuidePersistsOrigin() {
        let now = makeDate(year: 2026, month: 7, day: 22, hour: 11)
        let namedBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            )
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        XCTAssertTrue(store.markSelectedBoardAsStarterGuide())
        XCTAssertEqual(store.namedBoards.first?.origin, .starterGuide)
        XCTAssertEqual(repository.loadNamedBoardsSnapshot().boards.first?.origin, .starterGuide)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
    }

    @MainActor
    func testMarkSelectedBoardAsStarterGuideRollsBackWhenSaveFails() {
        let now = makeDate(year: 2026, month: 7, day: 22, hour: 11, minute: 15)
        let namedBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            ),
            namedBoardsSaveFailureCount: 1
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        XCTAssertFalse(store.markSelectedBoardAsStarterGuide())
        XCTAssertEqual(store.namedBoards.first?.origin, .user)
        XCTAssertEqual(repository.loadNamedBoardsSnapshot().boards.first?.origin, .user)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
    }

    @MainActor
    func testActualInstalledGuideTasksMatchPristineStarterBoardRule() {
        let harness = makeInMemoryViewModelHarness(savedBoard: nil)
        let viewModel = BingoViewModel(persistenceDependencies: harness.dependencies)

        FirstStepGuideStore.installSeedTasks(in: viewModel)
        let namedBoard = BingoBoardStore.NamedBoard(
            name: L10n.boardDefaultName(1),
            board: viewModel.makeSavedBoardSnapshot(),
            origin: .starterGuide
        )

        XCTAssertTrue(BingoBoardStore.isPristineStarterGuideBoard(namedBoard))
    }

    @MainActor
    func testDeleteBoardRollsBackWhenNamedSnapshotSaveFails() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 18)
        let firstBoard = makeNamedBoard(updatedAt: now)
        let secondBoard = makeNamedBoard(updatedAt: now.addingTimeInterval(60))
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: secondBoard.id,
                boards: [firstBoard, secondBoard]
            ),
            board: secondBoard.board,
            savedAt: secondBoard.updatedAt,
            countdownEndsAt: secondBoard.countdownEndsAt,
            activeNamedBoardID: secondBoard.id,
            namedBoardsSaveFailureCount: 1
        )
        repository.saveSelectedWidgetPanelID(secondBoard.id)
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [firstBoard, secondBoard]
        store.selectedBoardID = secondBoard.id
        store.hasLoadedBoardSwitcherState = true

        let result = store.deleteBoard(secondBoard.id, allowsDeletingFirstBoard: true)

        XCTAssertNil(result)
        XCTAssertEqual(store.namedBoards.map(\.id), [firstBoard.id, secondBoard.id])
        XCTAssertEqual(store.selectedBoardID, secondBoard.id)
        XCTAssertEqual(repository.loadNamedBoardsSnapshot().boards.map(\.id), [firstBoard.id, secondBoard.id])
        XCTAssertTrue(repository.loadNamedBoardsSnapshot().effectiveDeletedBoardIDs.isEmpty)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, secondBoard.id)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    @MainActor
    func testDeletingTwoBoardsConsecutivelyPersistsBothDeletionTombstones() throws {
        let now = makeDate(year: 2026, month: 7, day: 22, hour: 10)
        let boardA = makeNamedBoard(updatedAt: now)
        let boardB = makeNamedBoard(updatedAt: now.addingTimeInterval(60))
        let boardC = makeNamedBoard(updatedAt: now.addingTimeInterval(120))
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: boardC.id,
                boards: [boardA, boardB, boardC]
            ),
            board: boardC.board,
            savedAt: boardC.updatedAt,
            countdownEndsAt: boardC.countdownEndsAt,
            activeNamedBoardID: boardC.id
        )
        repository.saveSelectedWidgetPanelID(boardC.id)
        let store = BoardManagementStore(repository: repository)
        _ = store.loadIfNeeded(initialBoard: boardC.board, countdownEndsAt: nil)

        XCTAssertNotNil(store.deleteBoard(boardA.id, allowsDeletingFirstBoard: true))
        XCTAssertEqual(store.namedBoards.map(\.id), [boardB.id, boardC.id])
        XCTAssertEqual(repository.loadNamedBoardsSnapshot().effectiveDeletedBoardIDs, [boardA.id])

        XCTAssertNotNil(store.deleteBoard(boardB.id, allowsDeletingFirstBoard: true))
        XCTAssertEqual(store.namedBoards.map(\.id), [boardC.id])
        XCTAssertEqual(store.selectedBoardID, boardC.id)
        XCTAssertEqual(
            repository.loadNamedBoardsSnapshot().effectiveDeletedBoardIDs,
            [boardA.id, boardB.id]
        )
        XCTAssertEqual(repository.loadNamedBoardsSnapshot().boards.map(\.id), [boardC.id])
    }

    @MainActor
    func testPersistedBoardDeletionRefreshesLoadedBoardMembershipWithoutNewerBoardDate() {
        let now = makeDate(year: 2026, month: 7, day: 22, hour: 10, minute: 30)
        let boardA = makeNamedBoard(updatedAt: now)
        let boardB = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: boardB.id,
                boards: [boardA, boardB]
            ),
            board: boardB.board,
            savedAt: boardB.updatedAt,
            countdownEndsAt: boardB.countdownEndsAt,
            activeNamedBoardID: boardB.id
        )
        repository.saveSelectedWidgetPanelID(boardB.id)
        let store = BoardManagementStore(repository: repository)
        _ = store.loadIfNeeded(initialBoard: boardB.board, countdownEndsAt: nil)

        _ = repository.saveNamedBoardsSnapshot(
            BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: boardB.id,
                boards: [boardB],
                deletedBoardIDs: [boardA.id]
            ),
            reloadWidgets: false
        )

        let selected = store.reloadPersistedSnapshotIfNewer()

        XCTAssertEqual(selected?.id, boardB.id)
        XCTAssertEqual(store.namedBoards.map(\.id), [boardB.id])
    }

    @MainActor
    func testRenameBoardSkipsUnchangedNameWithoutReminderRelevantWork() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 8, minute: 55)
        let namedBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            )
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        let result = store.renameBoard(namedBoard.id, nameDraft: namedBoard.name)

        XCTAssertEqual(result, .unchanged)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 0)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    @MainActor
    func testRenameBoardRollsBackWhenNamedSnapshotSaveFails() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 18, minute: 15)
        let namedBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            ),
            board: namedBoard.board,
            savedAt: namedBoard.updatedAt,
            countdownEndsAt: namedBoard.countdownEndsAt,
            activeNamedBoardID: namedBoard.id,
            namedBoardsSaveFailureCount: 1
        )
        repository.saveSelectedWidgetPanelID(namedBoard.id)
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        let result = store.renameBoard(namedBoard.id, nameDraft: "Not persisted")

        XCTAssertEqual(result, .persistenceFailed)
        XCTAssertEqual(store.namedBoards, [namedBoard])
        XCTAssertEqual(repository.loadNamedBoardsSnapshot().boards, [namedBoard])
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    @MainActor
    func testPersistBoardStateSkipsUnchangedBoardAndCountdown() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 9)
        let countdownEndsAt = now.addingTimeInterval(30 * 60)
        var namedBoard = makeNamedBoard(updatedAt: now)
        namedBoard.countdownEndsAt = countdownEndsAt
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            )
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        let didPersist = store.persistBoardState(
            for: namedBoard.id,
            board: namedBoard.board,
            countdownEndsAt: countdownEndsAt
        )

        XCTAssertFalse(didPersist)
        XCTAssertEqual(store.namedBoards.first?.updatedAt, now)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 0)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 0)
    }

    @MainActor
    func testSyncSelectedBoardKeepsSnapshotAndActiveMirrorConsistentWithOneReload() throws {
        let now = Date()
        let originalBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: originalBoard.id,
                boards: [originalBoard]
            ),
            board: originalBoard.board,
            savedAt: originalBoard.updatedAt,
            countdownEndsAt: originalBoard.countdownEndsAt,
            activeNamedBoardID: originalBoard.id
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [originalBoard]
        store.selectedBoardID = originalBoard.id
        store.hasLoadedBoardSwitcherState = true

        var updatedCells = BoardEngine.expandedBoardCache(from: originalBoard.board)
        updatedCells[0][0] = BingoCell(text: "Committed once")
        let updatedBoard = SavedBoard(
            gridSize: originalBoard.board.gridSize,
            cells: BoardEngine.projectVisibleCells(
                from: updatedCells,
                size: originalBoard.board.gridSize,
                referenceDate: now
            ),
            completedLines: [],
            fullBoardCells: updatedCells
        )

        XCTAssertTrue(store.syncSelectedBoard(board: updatedBoard, countdownEndsAt: nil))

        let persistedBoard = try XCTUnwrap(
            repository.loadNamedBoardsSnapshot().boards.first(where: { $0.id == originalBoard.id })
        )
        XCTAssertEqual(persistedBoard.board, updatedBoard)
        XCTAssertEqual(repository.loadBoard(), updatedBoard)
        XCTAssertEqual(repository.persistedSelectedBoardID, originalBoard.id)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, originalBoard.id)
        XCTAssertEqual(repository.persistedWidgetPanelID, originalBoard.id)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 1)
        XCTAssertEqual(repository.reloadWidgetCallCount, 1)
    }

    @MainActor
    func testSyncSelectedBoardRetriesFailedNamedSnapshotWithoutRepeatingStateChange() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 16)
        let originalBoard = makeNamedBoard(updatedAt: now)
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: originalBoard.id,
                boards: [originalBoard]
            ),
            board: originalBoard.board,
            savedAt: originalBoard.updatedAt,
            activeNamedBoardID: originalBoard.id,
            namedBoardsSaveFailureCount: 1
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [originalBoard]
        store.selectedBoardID = originalBoard.id
        store.hasLoadedBoardSwitcherState = true

        var updatedCells = BoardEngine.expandedBoardCache(from: originalBoard.board)
        updatedCells[0][0] = BingoCell(text: "Retry snapshot")
        let updatedBoard = SavedBoard(
            gridSize: originalBoard.board.gridSize,
            cells: BoardEngine.projectVisibleCells(
                from: updatedCells,
                size: originalBoard.board.gridSize,
                referenceDate: now
            ),
            completedLines: [],
            fullBoardCells: updatedCells
        )

        XCTAssertTrue(store.syncSelectedBoard(board: updatedBoard, countdownEndsAt: nil))
        XCTAssertNotEqual(repository.loadNamedBoardsSnapshot().boards.first?.board, updatedBoard)

        XCTAssertFalse(store.syncSelectedBoard(board: updatedBoard, countdownEndsAt: nil))

        let persistedBoard = try XCTUnwrap(
            repository.loadNamedBoardsSnapshot().boards.first(where: { $0.id == originalBoard.id })
        )
        XCTAssertEqual(persistedBoard.board, updatedBoard)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 2)
        XCTAssertEqual(repository.saveBoardCallCount, 1)
        XCTAssertEqual(repository.reloadWidgetCallCount, 2)
    }

    @MainActor
    func testSelectedBoardSyncRetriesFailedActiveMirrorWithoutRewritingNamedSnapshot() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 16, minute: 30)
        let firstBoard = makeNamedBoard(updatedAt: now)
        var secondBoard = makeNamedBoard(updatedAt: now.addingTimeInterval(60))
        secondBoard.name = "Second"
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: firstBoard.id,
                boards: [firstBoard, secondBoard]
            ),
            board: firstBoard.board,
            savedAt: firstBoard.updatedAt,
            countdownEndsAt: firstBoard.countdownEndsAt,
            activeNamedBoardID: firstBoard.id,
            boardSaveFailureCount: 1
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [firstBoard, secondBoard]
        store.selectedBoardID = firstBoard.id
        store.hasLoadedBoardSwitcherState = true

        let selection = try XCTUnwrap(
            store.selectBoard(
                secondBoard.id,
                currentBoard: firstBoard.board,
                currentCountdownEndsAt: firstBoard.countdownEndsAt
            )
        )

        XCTAssertTrue(selection.didChangeSelection)
        XCTAssertTrue(selection.commitResult.savedNamedBoards)
        XCTAssertTrue(selection.commitResult.failedToSaveBoard)
        XCTAssertEqual(repository.persistedSelectedBoardID, secondBoard.id)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, firstBoard.id)

        XCTAssertFalse(
            store.syncSelectedBoard(
                board: secondBoard.board,
                countdownEndsAt: secondBoard.countdownEndsAt
            )
        )

        XCTAssertEqual(repository.loadBoard(), secondBoard.board)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, secondBoard.id)
        XCTAssertEqual(repository.persistedWidgetPanelID, secondBoard.id)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 2)
        XCTAssertEqual(repository.reloadWidgetCallCount, 2)
    }

    @MainActor
    func testLoadKeepsLocalActiveBoardWhenSnapshotSelectionDiffers() throws {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 17)
        let firstBoard = makeNamedBoard(updatedAt: now)
        var secondBoard = makeNamedBoard(updatedAt: now.addingTimeInterval(60))
        secondBoard.name = "Selected"
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: secondBoard.id,
                boards: [firstBoard, secondBoard]
            ),
            board: firstBoard.board,
            savedAt: firstBoard.updatedAt,
            countdownEndsAt: firstBoard.countdownEndsAt,
            activeNamedBoardID: firstBoard.id
        )
        let store = BoardManagementStore(repository: repository)

        let selectedBoard = try XCTUnwrap(
            store.loadIfNeeded(
                initialBoard: firstBoard.board,
                countdownEndsAt: firstBoard.countdownEndsAt
            )
        )

        XCTAssertEqual(selectedBoard.id, firstBoard.id)
        XCTAssertFalse(
            store.syncSelectedBoard(
                board: firstBoard.board,
                countdownEndsAt: firstBoard.countdownEndsAt
            )
        )
        XCTAssertEqual(repository.persistedSelectedBoardID, firstBoard.id)
        XCTAssertEqual(repository.loadBoard(), firstBoard.board)
        XCTAssertEqual(repository.persistedActiveNamedBoardID, firstBoard.id)
        XCTAssertEqual(repository.persistedWidgetPanelID, firstBoard.id)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
        XCTAssertEqual(repository.saveBoardCallCount, 0)
        XCTAssertEqual(repository.reloadWidgetCallCount, 1)
    }

    @MainActor
    func testQuickEditLikeBoardUpdatePreservesBoardRules() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 10)
        let previousReset = makeDate(year: 2026, month: 6, day: 19, hour: 3)
        let countdownEndsAt = now.addingTimeInterval(45 * 60)
        var namedBoard = makeNamedBoard(
            mode: .clearTasksNextDay,
            customResetMinutes: 3 * 60,
            lastTaskResetAppliedAt: previousReset,
            updatedAt: now
        )
        namedBoard.countdownEndsAt = countdownEndsAt
        let repository = InMemoryBoardManagementRepository(
            snapshot: BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: namedBoard.id,
                boards: [namedBoard]
            )
        )
        let store = BoardManagementStore(repository: repository)
        store.namedBoards = [namedBoard]
        store.selectedBoardID = namedBoard.id
        store.hasLoadedBoardSwitcherState = true

        var updatedCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        updatedCells[0][0] = BingoCell(text: "Quick edit task")
        let updatedVisibleCells = BoardEngine.projectVisibleCells(
            from: updatedCells,
            size: 2,
            referenceDate: now
        )
        let quickEditedBoard = SavedBoard(
            gridSize: 2,
            cells: updatedVisibleCells,
            completedLines: [],
            fullBoardCells: updatedCells
        )

        let didPersist = store.persistBoardState(
            for: namedBoard.id,
            board: quickEditedBoard,
            countdownEndsAt: countdownEndsAt
        )

        XCTAssertTrue(didPersist)
        XCTAssertEqual(store.namedBoards.first?.board, quickEditedBoard)
        XCTAssertEqual(store.namedBoards.first?.taskResetMode, .clearTasksNextDay)
        XCTAssertEqual(store.namedBoards.first?.customResetMinutes, 3 * 60)
        XCTAssertEqual(store.namedBoards.first?.lastTaskResetAppliedAt, previousReset)
        XCTAssertEqual(store.namedBoards.first?.countdownEndsAt, countdownEndsAt)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
    }
}

final class PersistenceWriteTransactionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistenceSideEffects()
    }

    override func tearDown() {
        clearPersistenceSideEffects()
        super.tearDown()
    }

    func testFailedStepRollsBackItselfAndCompletedStepsInReverseOrder() {
        var firstValue = "first-old"
        var secondValue = "second-old"
        var rollbackOrder: [Int] = []

        let didCommit = PersistenceWriteTransaction.commit([
            PersistenceWriteStep(
                apply: {
                    firstValue = "first-new"
                    return true
                },
                rollback: {
                    rollbackOrder.append(1)
                    firstValue = "first-old"
                    return true
                }
            ),
            PersistenceWriteStep(
                apply: {
                    secondValue = "second-partial"
                    return false
                },
                rollback: {
                    rollbackOrder.append(2)
                    secondValue = "second-old"
                    return true
                }
            )
        ])

        XCTAssertFalse(didCommit)
        XCTAssertEqual(firstValue, "first-old")
        XCTAssertEqual(secondValue, "second-old")
        XCTAssertEqual(rollbackOrder, [2, 1])
    }

    func testPointsSnapshotReplacementKeepsRemainingFieldsWhenOneValueIsCleared() {
        let now = makeDate(year: 2026, month: 7, day: 17, hour: 21)
        let dailyState = BingoRewardSettlement.emptyDailyRewardState(for: now)
        let complete = PointsPersistenceSnapshot(
            totalPoints: 12,
            lifetimePoints: 20,
            dailyRewardState: dailyState
        )

        XCTAssertTrue(PointsStore.replacePersistenceSnapshot(complete))
        XCTAssertEqual(PointsStore.loadPersistenceSnapshot(), complete)

        let withoutTotal = PointsPersistenceSnapshot(
            totalPoints: nil,
            lifetimePoints: 20,
            dailyRewardState: dailyState
        )
        XCTAssertTrue(PointsStore.replacePersistenceSnapshot(withoutTotal))
        XCTAssertEqual(PointsStore.loadPersistenceSnapshot(), withoutTotal)
    }

}


private let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0
) -> Date {
    fixedCalendar.date(from: DateComponents(
        timeZone: fixedCalendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    ))!
}

private func makeAppReviewPromptState(
    now: Date,
    forceDebugPrompt: Bool = false,
    hasPresentedDebugPromptThisLaunch: Bool = false,
    hasRatedPrompt: Bool = false,
    lifetimeShownCount: Int = 0,
    cooldownUntil: Double = 0,
    stage: Int = 0,
    lastShownDay: String = "",
    completedLineCount: Int = 0,
    isBoardFullyCompleted: Bool = false,
    consecutiveTaskCompletionDays: Int = 0
) -> AppReviewPromptEvaluationState {
    AppReviewPromptEvaluationState(
        now: now,
        todayKey: PointsStore.dateKey(for: now, calendar: fixedCalendar),
        forceDebugPrompt: forceDebugPrompt,
        hasPresentedDebugPromptThisLaunch: hasPresentedDebugPromptThisLaunch,
        hasRatedPrompt: hasRatedPrompt,
        lifetimeShownCount: lifetimeShownCount,
        cooldownUntil: cooldownUntil,
        stage: stage,
        lastShownDay: lastShownDay,
        completedLineCount: completedLineCount,
        isBoardFullyCompleted: isBoardFullyCompleted,
        consecutiveTaskCompletionDays: consecutiveTaskCompletionDays
    )
}

private func makeAppReviewPresentationState(
    isPromptPresented: Bool = false,
    debugBypassesBlockers: Bool = false,
    hasFirstStepGuideOverlay: Bool = false,
    isUpdatePromptPresented: Bool = false,
    isCustomResetDowngradeAlertPresented: Bool = false,
    isSidebarPresented: Bool = false,
    isQuickEditPresented: Bool = false,
    isContactUsPresented: Bool = false,
    isPointsFlowPresented: Bool = false,
    isBoardCountdownPresented: Bool = false,
    isBoardRulesPresented: Bool = false,
    isGridSizeSheetPresented: Bool = false,
    isShowingCelebration: Bool = false,
    isShowingBoardCompletionAnimation: Bool = false,
    hasBoardActionSheet: Bool = false,
    hasTimeoutDelayPicker: Bool = false,
    hasExpiredTaskEvent: Bool = false,
    hasExpiredBoardCountdownEvent: Bool = false,
    hasScheduledTaskReplacementEvent: Bool = false
) -> AppReviewPromptPresentationState {
    AppReviewPromptPresentationState(
        isPromptPresented: isPromptPresented,
        debugBypassesBlockers: debugBypassesBlockers,
        hasFirstStepGuideOverlay: hasFirstStepGuideOverlay,
        isUpdatePromptPresented: isUpdatePromptPresented,
        isCustomResetDowngradeAlertPresented: isCustomResetDowngradeAlertPresented,
        isSidebarPresented: isSidebarPresented,
        isQuickEditPresented: isQuickEditPresented,
        isContactUsPresented: isContactUsPresented,
        isPointsFlowPresented: isPointsFlowPresented,
        isBoardCountdownPresented: isBoardCountdownPresented,
        isBoardRulesPresented: isBoardRulesPresented,
        isGridSizeSheetPresented: isGridSizeSheetPresented,
        isShowingCelebration: isShowingCelebration,
        isShowingBoardCompletionAnimation: isShowingBoardCompletionAnimation,
        hasBoardActionSheet: hasBoardActionSheet,
        hasTimeoutDelayPicker: hasTimeoutDelayPicker,
        hasExpiredTaskEvent: hasExpiredTaskEvent,
        hasExpiredBoardCountdownEvent: hasExpiredBoardCountdownEvent,
        hasScheduledTaskReplacementEvent: hasScheduledTaskReplacementEvent
    )
}

private actor ReminderSyncCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct FakeTaskStartReminderScheduler: TaskStartReminderScheduling {
    let signature: String
    let counter: ReminderSyncCounter

    func syncReminders(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date
    ) async {
        await counter.increment()
    }

    func syncSignature(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date
    ) -> String {
        signature
    }
}

private func makeNamedBoard(
    cells: [[BingoCell]] = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize),
    gridSize: Int = 2,
    mode: BoardTaskResetMode = .resetStatusNextDay,
    customResetMinutes: Int? = nil,
    lastTaskResetAppliedAt: Date? = nil,
    updatedAt: Date = makeDate(year: 2026, month: 5, day: 31)
) -> BingoBoardStore.NamedBoard {
    let visibleCells = BoardEngine.projectVisibleCells(from: cells, size: gridSize, referenceDate: updatedAt)
    let savedBoard = SavedBoard(
        gridSize: gridSize,
        cells: visibleCells,
        completedLines: BoardEngine.completedLines(in: visibleCells, size: gridSize),
        fullBoardCells: cells
    )
    return BingoBoardStore.NamedBoard(
        name: "Test Board",
        board: savedBoard,
        taskResetMode: mode,
        customResetMinutes: customResetMinutes,
        lastTaskResetAppliedAt: lastTaskResetAppliedAt,
        updatedAt: updatedAt
    )
}

private func clearPersistenceSideEffects() {
    PointsStore.clearTotalPoints()
    PointsStore.clearLifetimePoints()
    PointsStore.clearDailyRewardState()
    RewardStore.clearRewards()
    StickerStore.clearInventoryCounts()
    StickerStore.clearPlacements()
    PointRedemptionHistoryStore.clear()
    BingoDiaryStore.replaceAllEntriesDictionary([:])
}

private struct InMemoryViewModelHarness {
    let dependencies: BingoViewModelPersistenceDependencies
    let boardRepository: InMemoryBingoBoardRepository
    let diaryRepository: InMemoryBingoDiaryRepository
    let pointsRepository: InMemoryBingoPointsRepository
    let transactionRepository: InMemoryBingoPersistenceTransactionRepository
}

private func makeInMemoryViewModelHarness(
    savedBoard: SavedBoard?,
    savedAt: Date? = nil,
    countdownEndsAt: Date? = nil,
    totalPoints: Int? = nil,
    lifetimePoints: Int? = nil,
    dailyRewardState: DailyRewardState? = nil,
    activeNamedBoardID: UUID? = nil
) -> InMemoryViewModelHarness {
    let boardRepository = InMemoryBingoBoardRepository(
        board: savedBoard,
        savedAt: savedAt,
        countdownEndsAt: countdownEndsAt,
        activeNamedBoardID: activeNamedBoardID
    )
    let pointsRepository = InMemoryBingoPointsRepository(
        totalPoints: totalPoints,
        lifetimePoints: lifetimePoints,
        dailyRewardState: dailyRewardState
    )
    let diaryRepository = InMemoryBingoDiaryRepository()
    let transactionRepository = InMemoryBingoPersistenceTransactionRepository()
    let dependencies = BingoViewModelPersistenceDependencies(
        boardRepository: boardRepository,
        diaryRepository: diaryRepository,
        pointsRepository: pointsRepository,
        transactionRepository: transactionRepository
    )
    return InMemoryViewModelHarness(
        dependencies: dependencies,
        boardRepository: boardRepository,
        diaryRepository: diaryRepository,
        pointsRepository: pointsRepository,
        transactionRepository: transactionRepository
    )
}

private func makeSavedBoardForViewModel(cell: BingoCell, referenceDate: Date) -> SavedBoard {
    var fullBoardCells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
    fullBoardCells[0][0] = cell
    let visibleCells = BoardEngine.projectVisibleCells(
        from: fullBoardCells,
        size: 2,
        referenceDate: referenceDate
    )
    return SavedBoard(
        gridSize: 2,
        cells: visibleCells,
        completedLines: BoardEngine.completedLines(in: visibleCells, size: 2),
        fullBoardCells: fullBoardCells
    )
}

private final class InMemoryBingoBoardRepository: BingoBoardRepository {
    var board: SavedBoard?
    private(set) var saveBoardCallCount = 0
    private(set) var saveCountdownCallCount = 0
    private(set) var reloadWidgetCallCount = 0
    private var savedAt: Date?
    private var countdownEndsAt: Date?
    private var activeNamedBoardID: UUID?
    private let shouldFailBoardSave: Bool

    init(
        board: SavedBoard?,
        savedAt: Date?,
        countdownEndsAt: Date? = nil,
        activeNamedBoardID: UUID? = nil,
        shouldFailBoardSave: Bool = false
    ) {
        self.board = board
        self.savedAt = savedAt
        self.countdownEndsAt = countdownEndsAt
        self.activeNamedBoardID = activeNamedBoardID
        self.shouldFailBoardSave = shouldFailBoardSave
    }

    func loadBoard() -> SavedBoard? {
        board
    }

    func loadBoardLastSavedAt() -> Date? {
        savedAt
    }

    func loadBoardCountdownEndsAt() -> Date? {
        countdownEndsAt
    }

    func loadActiveNamedBoardID() -> UUID? {
        activeNamedBoardID
    }

    func saveBoard(_ board: SavedBoard, savedAt: Date, associatedBoardID: UUID?, reloadWidgets: Bool) -> Bool {
        saveBoardCallCount += 1
        guard !shouldFailBoardSave else { return false }
        self.board = board
        self.savedAt = savedAt
        activeNamedBoardID = associatedBoardID
        return true
    }

    func saveBoardCountdownEndsAt(_ endsAt: Date?) {
        saveCountdownCallCount += 1
        countdownEndsAt = endsAt
    }

    func reloadWidgetTimelines() {
        reloadWidgetCallCount += 1
    }
}

private final class InMemoryBoardManagementRepository:
    BoardManagementRepository,
    WidgetBoardSelectionRepository {
    private(set) var saveNamedBoardsCallCount = 0
    private(set) var saveBoardCallCount = 0
    private(set) var saveCountdownCallCount = 0
    private(set) var reloadWidgetCallCount = 0
    private var snapshot: BingoBoardStore.NamedBoardsSnapshot
    private var board: SavedBoard?
    private var savedAt: Date?
    private var countdownEndsAt: Date?
    private var activeNamedBoardID: UUID?
    private var selectedWidgetPanelID: UUID?
    private var widgetTaskSyncEvent: WidgetTaskSyncStore.Event?
    private var namedBoardsSaveFailureCount: Int
    private var boardSaveFailureCount: Int
    private var boardClearFailureCount: Int

    var hasWidgetTaskSyncEvent: Bool {
        widgetTaskSyncEvent != nil
    }

    var persistedSelectedBoardID: UUID? {
        snapshot.selectedBoardID
    }

    var persistedActiveNamedBoardID: UUID? {
        activeNamedBoardID
    }

    var persistedWidgetPanelID: UUID? {
        selectedWidgetPanelID
    }

    init(
        snapshot: BingoBoardStore.NamedBoardsSnapshot,
        board: SavedBoard? = nil,
        savedAt: Date? = nil,
        countdownEndsAt: Date? = nil,
        activeNamedBoardID: UUID? = nil,
        widgetTaskSyncEvent: WidgetTaskSyncStore.Event? = nil,
        namedBoardsSaveFailureCount: Int = 0,
        boardSaveFailureCount: Int = 0,
        boardClearFailureCount: Int = 0
    ) {
        self.snapshot = snapshot
        self.board = board
        self.savedAt = savedAt
        self.countdownEndsAt = countdownEndsAt
        self.activeNamedBoardID = activeNamedBoardID
        self.widgetTaskSyncEvent = widgetTaskSyncEvent
        self.namedBoardsSaveFailureCount = namedBoardsSaveFailureCount
        self.boardSaveFailureCount = boardSaveFailureCount
        self.boardClearFailureCount = boardClearFailureCount
    }

    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot {
        snapshot
    }

    func saveNamedBoardsSnapshot(
        _ snapshot: BingoBoardStore.NamedBoardsSnapshot,
        reloadWidgets: Bool
    ) -> Bool {
        saveNamedBoardsCallCount += 1
        guard namedBoardsSaveFailureCount == 0 else {
            namedBoardsSaveFailureCount -= 1
            return false
        }
        self.snapshot = snapshot
        return true
    }

    func clearNamedBoardsSnapshot(reloadWidgets: Bool) {
        snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: nil,
            boards: []
        )
    }

    func loadBoard() -> SavedBoard? {
        board
    }

    func loadBoardLastSavedAt() -> Date? {
        savedAt
    }

    func loadBoardCountdownEndsAt() -> Date? {
        countdownEndsAt
    }

    func loadActiveNamedBoardID() -> UUID? {
        activeNamedBoardID
    }

    func saveBoard(_ board: SavedBoard, savedAt: Date, associatedBoardID: UUID?, reloadWidgets: Bool) -> Bool {
        saveBoardCallCount += 1
        guard boardSaveFailureCount == 0 else {
            boardSaveFailureCount -= 1
            return false
        }
        self.board = board
        self.savedAt = savedAt
        activeNamedBoardID = associatedBoardID
        return true
    }

    func clearBoard(reloadWidgets: Bool) {
        guard boardClearFailureCount == 0 else {
            boardClearFailureCount -= 1
            return
        }
        board = nil
        savedAt = nil
        countdownEndsAt = nil
        activeNamedBoardID = nil
    }

    func saveBoardCountdownEndsAt(_ endsAt: Date?) {
        saveCountdownCallCount += 1
        countdownEndsAt = endsAt
    }

    func loadWidgetTaskSyncEvent() -> WidgetTaskSyncStore.Event? {
        widgetTaskSyncEvent
    }

    func saveWidgetTaskSyncEvent(_ event: WidgetTaskSyncStore.Event) -> Bool {
        widgetTaskSyncEvent = event
        return true
    }

    func clearWidgetTaskSyncEvent(ifMatching eventID: UUID) {
        guard widgetTaskSyncEvent?.id == eventID else { return }
        widgetTaskSyncEvent = nil
    }

    func loadSelectedWidgetPanelID() -> UUID? {
        selectedWidgetPanelID
    }

    func saveSelectedWidgetPanelID(_ boardID: UUID?) {
        selectedWidgetPanelID = boardID
    }

    func reloadWidgetTimelines() {
        reloadWidgetCallCount += 1
    }
}

private final class InMemoryBingoDiaryRepository: BingoDiaryRepository {
    private(set) var replaceCallCount = 0
    private var entries: [String: BingoDiaryEntry]
    private let roundTripsThroughCodable: Bool

    init(
        entries: [String: BingoDiaryEntry] = [:],
        roundTripsThroughCodable: Bool = false
    ) {
        self.entries = entries
        self.roundTripsThroughCodable = roundTripsThroughCodable
    }

    func loadAllEntriesDictionary() -> [String: BingoDiaryEntry] {
        entries
    }

    func replaceAllEntriesDictionary(_ entries: [String: BingoDiaryEntry]) {
        replaceCallCount += 1
        if roundTripsThroughCodable,
           let data = try? JSONEncoder().encode(entries),
           let decoded = try? JSONDecoder().decode([String: BingoDiaryEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = entries
        }
    }
}

private final class InMemoryBingoPointsRepository: BingoPointsRepository {
    private(set) var saveStateCallCount = 0
    private var totalPoints: Int?
    private var lifetimePoints: Int?
    private var dailyRewardState: DailyRewardState?

    init(
        totalPoints: Int? = nil,
        lifetimePoints: Int? = nil,
        dailyRewardState: DailyRewardState? = nil
    ) {
        self.totalPoints = totalPoints
        self.lifetimePoints = lifetimePoints
        self.dailyRewardState = dailyRewardState
    }

    func loadTotalPoints() -> Int? {
        totalPoints
    }

    func loadLifetimePoints() -> Int? {
        lifetimePoints
    }

    func loadDailyRewardState() -> DailyRewardState? {
        dailyRewardState
    }

    func saveTotalPoints(_ points: Int) {
        totalPoints = points
    }

    func saveLifetimePoints(_ points: Int) {
        lifetimePoints = points
    }

    func saveDailyRewardState(_ state: DailyRewardState) {
        dailyRewardState = state
    }

    func saveState(totalPoints: Int, lifetimePoints: Int, dailyRewardState: DailyRewardState) -> Bool {
        saveStateCallCount += 1
        self.totalPoints = totalPoints
        self.lifetimePoints = lifetimePoints
        self.dailyRewardState = dailyRewardState
        return true
    }
}

private final class InMemoryBingoPersistenceTransactionRepository: BingoPersistenceTransactionRepository {
    private(set) var pendingTransaction: BingoPendingPersistenceTransaction?
    private(set) var saveCallCount = 0
    private(set) var clearCallCount = 0
    var shouldFailSave = false
    var shouldFailClear = false

    init(pendingTransaction: BingoPendingPersistenceTransaction? = nil) {
        self.pendingTransaction = pendingTransaction
    }

    func loadPendingTransaction() -> BingoPendingPersistenceTransaction? {
        pendingTransaction
    }

    func savePendingTransaction(_ transaction: BingoPendingPersistenceTransaction) -> Bool {
        saveCallCount += 1
        guard !shouldFailSave else { return false }
        pendingTransaction = transaction
        return true
    }

    func clearPendingTransaction() -> Bool {
        clearCallCount += 1
        guard !shouldFailClear else { return false }
        pendingTransaction = nil
        return true
    }
}

final class AnalyticsEventContractTests: XCTestCase {
    func testCustomRewardVisualMapsKnownThemeToStableID() {
        XCTAssertEqual(
            AnalyticsEventContract.customRewardVisual(
                emoji: "😊",
                themeImageName: "CustomRewardTheme7"
            ),
            CustomRewardVisualAnalyticsDescriptor(type: "theme", id: "theme_7")
        )
    }

    func testCustomRewardVisualMapsDefaultEmojiToStableID() {
        XCTAssertEqual(
            AnalyticsEventContract.customRewardVisual(emoji: "⭐️", themeImageName: nil),
            CustomRewardVisualAnalyticsDescriptor(type: "emoji", id: "emoji_star")
        )
    }

    func testCustomRewardVisualRedactsUserEnteredEmoji() {
        XCTAssertEqual(
            AnalyticsEventContract.customRewardVisual(emoji: "🧑‍🚀", themeImageName: nil),
            CustomRewardVisualAnalyticsDescriptor(type: "emoji", id: "emoji_custom")
        )
    }

    func testPremiumFeatureMapsSourcesUsedAcrossTheFunnel() {
        XCTAssertEqual(
            AnalyticsEventContract.premiumFeature(forSource: "boards_limit"),
            .boards
        )
        XCTAssertEqual(
            AnalyticsEventContract.premiumFeature(forSource: "quick_edit_grid_5x5"),
            .grid5x5
        )
        XCTAssertEqual(
            AnalyticsEventContract.premiumFeature(forSource: "custom_reward_limit_save"),
            .customRewards
        )
        XCTAssertEqual(
            AnalyticsEventContract.premiumFeature(forSource: "home_limited_offer"),
            .limitedOffer
        )
    }
}

final class SubscriptionPriceDisplayTests: XCTestCase {
    func testRevenueCatDisplayPriceKeepsStoreFormattedValueUnchanged() {
        XCTAssertEqual(
            SubscriptionManager.revenueCatDisplayPrice(from: "NT$890.00"),
            "NT$890.00"
        )
        XCTAssertEqual(
            SubscriptionManager.revenueCatDisplayPrice(from: "US$39.99"),
            "US$39.99"
        )
    }

    func testEmptyRevenueCatDisplayPriceIsNotUsableForPaywallUI() {
        XCTAssertFalse(SubscriptionManager.hasUsableDisplayPrice(""))
        XCTAssertFalse(SubscriptionManager.hasUsableDisplayPrice("   "))
        XCTAssertFalse(SubscriptionManager.hasUsableDisplayPrice("--"))
        XCTAssertTrue(SubscriptionManager.hasUsableDisplayPrice("NT$890.00"))
    }

    func testRevenueCatPriceSnapshotIsTheOnlyVisiblePriceSource() {
        let snapshot = PaywallStoreProductPriceSnapshot(
            displayPrice: "US$39.99",
            price: Decimal(string: "39.99")!,
            currencyCode: "USD",
            source: "revenuecat_store_product"
        )

        XCTAssertEqual(snapshot.source, "revenuecat_store_product")
        XCTAssertEqual(snapshot.displayPrice, "US$39.99")
        XCTAssertEqual(snapshot.currencyCode, "USD")
    }
}
