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

        store.scheduleSync(namedBoards: [], selectedBoardID: nil, activeBoard: nil)
        store.scheduleSync(namedBoards: [], selectedBoardID: nil, activeBoard: nil)

        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)

        let syncCount = await counter.value
        XCTAssertEqual(syncCount, 1)
    }
}

final class HomeBoardSnapshotSyncStoreTests: XCTestCase {
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
}

final class PointRedemptionReconcilerTests: XCTestCase {
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
    func testNormalSettlementAwardsOnlyDeltaWhenTotalPointsAreBelowCurrentBoardPoints() throws {
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

        XCTAssertEqual(completedOutput.totalPoints, 1)
        XCTAssertEqual(completedOutput.lifetimePoints, 1)

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
        XCTAssertEqual(undoOutput.lifetimePoints, 1)
    }
}

final class TaskRecurrenceRuleTests: XCTestCase {
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

    func testRecurringCompletionOnlyAppliesToCompletedOccurrenceDate() {
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
        XCTAssertFalse(cell.projectedForDisplay(on: nextDay, calendar: fixedCalendar).isCompleted)
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

    func testRecurringTimeWindowUsesOccurrenceDayWhenEnabled() {
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

        XCTAssertFalse(cell.isCurrentlyTappable(on: beforeStart, calendar: fixedCalendar))
        XCTAssertTrue(cell.isCurrentlyTappable(on: withinWindow, calendar: fixedCalendar))
        XCTAssertFalse(cell.isCurrentlyTappable(on: afterEnd, calendar: fixedCalendar))
        XCTAssertEqual(
            cell.occurrenceStartVisibleAt(on: withinWindow, calendar: fixedCalendar),
            makeDate(year: 2026, month: 6, day: 17, hour: 9)
        )
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

    func testRepeatingTaskWindowTimeoutCannotBePostponed() throws {
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
        let candidate = try XCTUnwrap(BoardEngine.expiredTaskCandidate(in: [[cell]], now: now))

        XCTAssertFalse(candidate.allowsPostpone)
        XCTAssertNil(BoardEngine.resolveExpiredTask(
            in: [[cell]],
            candidate: candidate,
            resolution: .postpone(minutes: 15),
            now: now,
            maxCountdownMinutes: BingoViewModel.maxCountdownMinutes,
            calendar: fixedCalendar
        ))
    }

    func testLegacyRepeatingTimeWindowKeepsAbsoluteEndDateByDefault() {
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
        XCTAssertFalse(cell.isCurrentlyTappable(on: nextDayWithinSameTime, calendar: fixedCalendar))
    }
}

final class TaskCountdownSettingViewModelTests: XCTestCase {
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

final class LimitedOfferEntryEligibilityTests: XCTestCase {
    private let config = LimitedTimeOfferConfig(
        isEnabled: true,
        campaignID: "campaign_a",
        offerDuration: 48 * 60 * 60,
        minimumAppVersion: "2.3.0"
    )

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

    func testPremiumAccessClearsHomeOfferState() {
        let state = LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: true,
            hasLegacyExposure: true,
            startedAt: makeDate(year: 2026, month: 6, day: 15, hour: 9).timeIntervalSince1970,
            campaignID: "campaign_a",
            isPresented: true
        )

        let clearedState = LimitedOfferHomeRules.applyingPremiumAccess(
            to: state,
            hasPremiumAccess: true
        )

        XCTAssertFalse(clearedState.hasVisitedPaywallWithoutPurchase)
        XCTAssertFalse(clearedState.hasLegacyExposure)
        XCTAssertEqual(clearedState.startedAt, 0)
        XCTAssertEqual(clearedState.campaignID, "")
        XCTAssertFalse(clearedState.isPresented)
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
}

final class BoardStateCommitterTests: XCTestCase {
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

        XCTAssertEqual(result.selectedBoard.name, "Second")
        XCTAssertEqual(store.selectedBoardID, result.selectedBoard.id)
        XCTAssertTrue(result.didChangeSelection)
        XCTAssertTrue(result.shouldInvalidateCountdownTickSchedule)
        XCTAssertTrue(result.shouldSyncTaskReminders)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
    }

    @MainActor
    func testReplaceSelectedBoardWithTemplateSyncsRemindersWithoutSelectionChange() {
        let now = makeDate(year: 2026, month: 6, day: 20, hour: 8, minute: 50)
        let namedBoard = makeNamedBoard(updatedAt: now)
        var cells = BoardEngine.createEmptyGrid(size: BoardEngine.maxGridSize)
        cells[0][0] = BingoCell(text: "Imported task")
        let importedBoard = makeNamedBoard(
            cells: cells,
            mode: .keepTaskStatus,
            lastTaskResetAppliedAt: now,
            updatedAt: now
        ).board
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

        let result = store.replaceSelectedBoardWithTemplate(
            nameDraft: "Imported",
            savedBoard: importedBoard
        )

        XCTAssertEqual(result?.selectedBoard.board, importedBoard)
        XCTAssertFalse(result?.didChangeSelection == true)
        XCTAssertTrue(result?.shouldInvalidateCountdownTickSchedule == true)
        XCTAssertTrue(result?.shouldSyncTaskReminders == true)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 1)
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

        let didRename = store.renameBoard(namedBoard.id, nameDraft: namedBoard.name)

        XCTAssertFalse(didRename)
        XCTAssertEqual(repository.saveNamedBoardsCallCount, 0)
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
    isBlackBoxModePresented: Bool = false,
    isContactUsPresented: Bool = false,
    isPointsFlowPresented: Bool = false,
    isBoardCountdownPresented: Bool = false,
    isBoardRulesPresented: Bool = false,
    isGridSizeSheetPresented: Bool = false,
    isTemplateImportPreviewPresented: Bool = false,
    isTemplateShareComposerPresented: Bool = false,
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
        isBlackBoxModePresented: isBlackBoxModePresented,
        isContactUsPresented: isContactUsPresented,
        isPointsFlowPresented: isPointsFlowPresented,
        isBoardCountdownPresented: isBoardCountdownPresented,
        isBoardRulesPresented: isBoardRulesPresented,
        isGridSizeSheetPresented: isGridSizeSheetPresented,
        isTemplateImportPreviewPresented: isTemplateImportPreviewPresented,
        isTemplateShareComposerPresented: isTemplateShareComposerPresented,
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
    mode: BoardTaskResetMode = .resetStatusNextDay,
    customResetMinutes: Int? = nil,
    lastTaskResetAppliedAt: Date? = nil,
    updatedAt: Date = makeDate(year: 2026, month: 5, day: 31)
) -> BingoBoardStore.NamedBoard {
    let visibleCells = BoardEngine.projectVisibleCells(from: cells, size: 2, referenceDate: updatedAt)
    let savedBoard = SavedBoard(
        gridSize: 2,
        cells: visibleCells,
        completedLines: BoardEngine.completedLines(in: visibleCells, size: 2),
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
    let pointsRepository: InMemoryBingoPointsRepository
}

private func makeInMemoryViewModelHarness(
    savedBoard: SavedBoard?,
    savedAt: Date? = nil,
    totalPoints: Int? = nil,
    lifetimePoints: Int? = nil,
    dailyRewardState: DailyRewardState? = nil
) -> InMemoryViewModelHarness {
    let boardRepository = InMemoryBingoBoardRepository(board: savedBoard, savedAt: savedAt)
    let pointsRepository = InMemoryBingoPointsRepository(
        totalPoints: totalPoints,
        lifetimePoints: lifetimePoints,
        dailyRewardState: dailyRewardState
    )
    let dependencies = BingoViewModelPersistenceDependencies(
        boardRepository: boardRepository,
        diaryRepository: InMemoryBingoDiaryRepository(),
        pointsRepository: pointsRepository
    )
    return InMemoryViewModelHarness(
        dependencies: dependencies,
        boardRepository: boardRepository,
        pointsRepository: pointsRepository
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

    init(
        board: SavedBoard?,
        savedAt: Date?,
        countdownEndsAt: Date? = nil,
        activeNamedBoardID: UUID? = nil
    ) {
        self.board = board
        self.savedAt = savedAt
        self.countdownEndsAt = countdownEndsAt
        self.activeNamedBoardID = activeNamedBoardID
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

private final class InMemoryBoardManagementRepository: BoardManagementRepository {
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

    init(
        snapshot: BingoBoardStore.NamedBoardsSnapshot,
        board: SavedBoard? = nil,
        savedAt: Date? = nil,
        countdownEndsAt: Date? = nil,
        activeNamedBoardID: UUID? = nil
    ) {
        self.snapshot = snapshot
        self.board = board
        self.savedAt = savedAt
        self.countdownEndsAt = countdownEndsAt
        self.activeNamedBoardID = activeNamedBoardID
    }

    func loadNamedBoardsSnapshot() -> BingoBoardStore.NamedBoardsSnapshot {
        snapshot
    }

    func saveNamedBoardsSnapshot(
        _ snapshot: BingoBoardStore.NamedBoardsSnapshot,
        reloadWidgets: Bool
    ) -> Bool {
        saveNamedBoardsCallCount += 1
        self.snapshot = snapshot
        return true
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
        self.board = board
        self.savedAt = savedAt
        activeNamedBoardID = associatedBoardID
        return true
    }

    func saveBoardCountdownEndsAt(_ endsAt: Date?) {
        saveCountdownCallCount += 1
        countdownEndsAt = endsAt
    }

    func loadWidgetTaskSyncEvent() -> WidgetTaskSyncStore.Event? {
        widgetTaskSyncEvent
    }

    func clearWidgetTaskSyncEvent() {
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
    func save(board: SavedBoard, on date: Date) {}
    func applyExplicitTaskDelta(task: String, delta: Int, board: SavedBoard, on date: Date) {}
    func syncBoardSnapshotWithoutCounting(board: SavedBoard, on date: Date) {}
}

private final class InMemoryBingoPointsRepository: BingoPointsRepository {
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
}
