import XCTest
@testable import Bingodays

@MainActor
final class OperationPersistenceTests: XCTestCase {
    /// Keep the workflow runner reusable across features: every reopen constructs
    /// new repositories and new models, then exercises the normal maintenance path.
    private func assertStable(
        _ repository: OperationPersistenceRepository, at now: Date,
        verify: (BingoViewModel, OperationPersistenceRepository) -> Void
    ) throws {
        for _ in 0..<2 {
            let reopened = repository.reopened()
            let model = BingoViewModel(persistenceDependencies: reopened.dependencies)
            for offset in 1...3 {
                let tick = now.addingTimeInterval(Double(offset))
                _ = model.refreshVisibilityWindowsIfNeeded(now: tick)
                model.processExpiredCountdowns(now: tick)
                model.processExpiredTaskCountdowns(now: tick)
                XCTAssertNil(model.expiredTaskEvent)
                XCTAssertNil(model.expiredBoardCountdownEvent)
                verify(model, reopened)
            }
            let expected = BingoBoardStore.normalizedBoardForPersistence(model.makeSavedBoardSnapshot(), referenceDate: now)
            XCTAssertTrue(expected == (try XCTUnwrap(reopened.loadBoard())),
                          "Reopened model and durable board diverged after maintenance")
            XCTAssertNil(reopened.loadPendingTransaction())
        }
    }

    private func withFixture(
        mixed: Bool = true,
        task: BingoCell = BingoCell(text: "Operation target"),
        body: (OperationPersistenceRepository, BingoViewModel, Date) throws -> Void
    ) throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Run workflow integration tests in a simulator; UI/device acceptance uses dedicated test data.")
        #else
        let now = Date()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BingodaysOperationTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Some legacy action paths still write static stores. Preserve their exact
        // defaults, including absent values, rather than leaking fixture history.
        let defaults = [UserDefaults.standard, BingoBoardStore.sharedDefaults]
        let keys = [AppSettings.taskHistoryKey, AppSettings.taskCompletionHistoryKey,
                    AppSettings.taskCompletionHistoryMigrationVersionKey, "bingo_timeout_unfinished_stats_v1"]
        let backups = defaults.map { store in keys.map { store.object(forKey: $0) } }
        defer {
            for (index, store) in defaults.enumerated() {
                for (keyIndex, key) in keys.enumerated() { store.set(backups[index][keyIndex], forKey: key) }
            }
            do { try FileManager.default.removeItem(at: directory) }
            catch { XCTFail("Could not clean this fixture at \(directory.path): \(error)") }
        }
        let repository = OperationPersistenceRepository(directory: directory)
        var cache = BoardEngine.createEmptyGrid(size: 5)
        cache[0][0] = task
        if mixed {
            cache[0][1] = BingoCell(text: "Inactive neighbour", startVisibleAt: now.addingTimeInterval(604800))
            cache[1][1] = BingoCell(text: "Daily neighbour", recurrenceRule: .init(kind: .daily))
            cache[2][2] = BingoCell(text: "Independent neighbour")
        }
        let board = SavedBoard(gridSize: 3,
            cells: BoardEngine.projectVisibleCells(from: cache, size: 3, referenceDate: now),
            completedLines: [], fullBoardCells: cache)
        XCTAssertTrue(repository.saveBoard(board, savedAt: now, associatedBoardID: UUID(), reloadWidgets: false))
        let baseline = PointRedemptionLedger.currentCommittedSpend() + 50
        XCTAssertTrue(repository.saveState(totalPoints: baseline, lifetimePoints: baseline,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)))
        let model = BingoViewModel(persistenceDependencies: repository.dependencies)
        try body(repository, model, now)
        #endif
    }

    func testCompletionUndoAndRecompletionSurviveFreshRepositories() throws {
        for mixed in [false, true] {
            try withFixture(mixed: mixed) { repository, model, now in
                let baseline = model.totalPoints
                let lifetime = try XCTUnwrap(repository.loadLifetimePoints())
                let neighbour = repository.loadBoard()?.fullBoardCells?[0][1]
                XCTAssertTrue(model.toggleComplete(row: 0, col: 0, referenceDate: now))
                try assertStable(repository, at: now) { loaded, disk in
                    XCTAssertTrue(loaded.cells[0][0].isCompleted)
                    XCTAssertEqual(loaded.totalPoints, baseline + 1)
                    XCTAssertEqual(disk.loadBoard()?.fullBoardCells?[0][1], neighbour)
                }
                let undone = BingoViewModel(persistenceDependencies: repository.reopened().dependencies)
                XCTAssertTrue(undone.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(4)))
                try assertStable(repository, at: now.addingTimeInterval(4)) { loaded, disk in
                    XCTAssertFalse(loaded.cells[0][0].isCompleted)
                    XCTAssertEqual(loaded.totalPoints, baseline)
                    XCTAssertEqual(disk.loadLifetimePoints(), lifetime + 1)
                }
                let recompleted = BingoViewModel(persistenceDependencies: repository.reopened().dependencies)
                XCTAssertTrue(recompleted.toggleComplete(row: 0, col: 0, referenceDate: now.addingTimeInterval(8)))
                try assertStable(repository, at: now.addingTimeInterval(8)) { loaded, disk in
                    XCTAssertEqual(loaded.totalPoints, baseline + 1)
                    XCTAssertEqual(disk.loadLifetimePoints(), lifetime + 2)
                    XCTAssertEqual(disk.loadCompletionHistory().first?.completionCount, 1)
                }
            }
        }
    }

    func testTaskEditorSaveAndDeleteSurviveFreshRepositories() throws {
        for mixed in [false, true] {
            try withFixture(mixed: mixed) { repository, model, now in
                let baseline = model.totalPoints
                XCTAssertTrue(model.updateTask(row: 0, col: 0, text: "Saved edit", isForced: false,
                    residentWeekdays: [], recurrenceRule: .init(kind: .none), endVisibleAt: now.addingTimeInterval(3600)))
                try assertStable(repository, at: now) { loaded, _ in
                    XCTAssertEqual(loaded.cells[0][0].storedTaskText, "Saved edit")
                    XCTAssertEqual(loaded.cells[0][0].endVisibleAt, now.addingTimeInterval(3600))
                    XCTAssertEqual(loaded.totalPoints, baseline)
                }
                let deleting = BingoViewModel(persistenceDependencies: repository.reopened().dependencies)
                deleting.clearTask(row: 0, col: 0)
                try assertStable(repository, at: now) { loaded, _ in
                    XCTAssertFalse(loaded.cells[0][0].hasStoredTask)
                    XCTAssertEqual(loaded.totalPoints, baseline)
                }
            }
        }
    }

    func testEditorSaveFailurePreservesDurableStateAndAllowsRetry() throws {
        try withFixture { repository, model, now in
            let previous = repository.loadBoard()
            let points = repository.loadPersistenceSnapshot()
            repository.rejectedWrites = [.board]
            XCTAssertFalse(model.updateTask(row: 0, col: 0, text: "Retried edit", isForced: false, residentWeekdays: []))
            XCTAssertEqual(repository.reopened().loadBoard(), previous)
            XCTAssertEqual(repository.reopened().loadPersistenceSnapshot(), points)
            XCTAssertEqual(model.cells[0][0].storedTaskText, "Operation target")
            repository.rejectedWrites = []
            XCTAssertTrue(model.updateTask(row: 0, col: 0, text: "Retried edit", isForced: false, residentWeekdays: []))
            try assertStable(repository, at: now) { loaded, _ in
                XCTAssertEqual(loaded.cells[0][0].storedTaskText, "Retried edit")
                XCTAssertEqual(loaded.totalPoints, points.totalPoints)
            }
        }
    }

    func testInterruptedCompletionRecoversFromDiskExactlyOnce() throws {
        try withFixture { repository, model, now in
            let baseline = model.totalPoints
            repository.rejectedWrites = [.points]
            XCTAssertFalse(model.toggleComplete(row: 0, col: 0, referenceDate: now))
            XCTAssertNotNil(repository.reopened().loadPendingTransaction())
            XCTAssertEqual(repository.reopened().loadTotalPoints(), baseline)
            // New adapter has no failure injection and must recover the journal.
            try assertStable(repository, at: now) { loaded, disk in
                XCTAssertTrue(loaded.cells[0][0].isCompleted)
                XCTAssertEqual(loaded.totalPoints, baseline + 1)
                XCTAssertEqual(disk.loadCompletionHistory().first?.completionCount, 1)
            }
        }
    }

    func testQuickEditMoveAndResizeKeepIdentityAcrossStorage() throws {
        try withFixture { repository, model, now in
            let originalID = model.cells[0][0].id
            let baseline = model.totalPoints
            var draft = model.currentBoardCellsInRowMajor(size: 3)
            draft.swapAt(0, 2)
            XCTAssertTrue(model.applyBoardOrderedCells(draft, targetGridSize: 3,
                editingContext: model.makeQuickEditBoardContext()))
            try assertStable(repository, at: now) { loaded, _ in
                XCTAssertEqual(loaded.cells[0][2].id, originalID)
                XCTAssertEqual(loaded.totalPoints, baseline)
            }
            let resized = BingoViewModel(persistenceDependencies: repository.reopened().dependencies)
            resized.resizeGrid(to: 4)
            try assertStable(repository, at: now) { loaded, _ in
                XCTAssertEqual(loaded.gridSize, 4)
                XCTAssertEqual(loaded.cells[0][2].id, originalID)
                XCTAssertEqual(loaded.totalPoints, baseline)
            }
        }
    }

    func testCountdownPauseResumeAndCancelSurviveReload() throws {
        try withFixture { repository, model, now in
            XCTAssertTrue(model.setTaskCountdown(row: 0, col: 0, minutes: 5, referenceDate: now))
            XCTAssertTrue(model.pauseTaskCountdown(row: 0, col: 0, referenceDate: now))
            try assertStable(repository, at: now) { loaded, _ in
                XCTAssertNil(loaded.cells[0][0].countdownEndsAt)
                XCTAssertEqual(loaded.cells[0][0].countdownPausedRemainingSeconds, 300)
            }
            let resumed = BingoViewModel(persistenceDependencies: repository.reopened().dependencies)
            XCTAssertTrue(resumed.resumeTaskCountdown(row: 0, col: 0, referenceDate: now.addingTimeInterval(10)))
            try assertStable(repository, at: now.addingTimeInterval(10)) { loaded, _ in
                XCTAssertEqual(loaded.cells[0][0].countdownEndsAt, now.addingTimeInterval(310))
            }
            let canceled = BingoViewModel(persistenceDependencies: repository.reopened().dependencies)
            XCTAssertTrue(canceled.cancelTaskCountdown(row: 0, col: 0, referenceDate: now.addingTimeInterval(20)))
            try assertStable(repository, at: now.addingTimeInterval(400)) { loaded, _ in
                XCTAssertNil(loaded.cells[0][0].countdownEndsAt)
                XCTAssertNil(loaded.cells[0][0].estimatedDurationMinutes)
            }
        }
    }

    func testTaskTimeoutActionsCommitAcrossRealSerialization() throws {
        for action in [BingoViewModel.ExpiredTaskResolution.postpone(minutes: 5), .markAsCompleted, .abandon] {
            let task = BingoCell(text: "Expired target", startVisibleAt: Date().addingTimeInterval(-120),
                                 endVisibleAt: Date().addingTimeInterval(-60))
            try withFixture(task: task) { repository, model, now in
                let baseline = model.totalPoints
                // Copies the inactive neighbour's display projection into memory.
                XCTAssertTrue(model.toggleComplete(row: 2, col: 2, referenceDate: now))
                model.processExpiredTaskCountdowns(now: now)
                XCTAssertNotNil(model.expiredTaskEvent)
                let message = model.resolveExpiredTask(action, now: now)
                try assertStable(repository, at: now) { loaded, _ in
                    switch action {
                    case .postpone(let minutes):
                        XCTAssertEqual(message, L10n.taskPostponedSuccess(minutes))
                        XCTAssertEqual(loaded.cells[0][0].endVisibleAt, now.addingTimeInterval(Double(minutes * 60)))
                        XCTAssertEqual(loaded.totalPoints, baseline + 1)
                    case .markAsCompleted:
                        XCTAssertEqual(message, L10n.taskMarkedCompletedSuccess)
                        XCTAssertTrue(loaded.cells[0][0].isCompleted)
                        XCTAssertEqual(loaded.cells[0][0].completionStreakCount, 1)
                        XCTAssertEqual(loaded.totalPoints, baseline + 2)
                    case .abandon:
                        XCTAssertEqual(message, L10n.taskAbandonedSuccess)
                        XCTAssertFalse(loaded.cells[0][0].hasStoredTask)
                        XCTAssertEqual(loaded.totalPoints, baseline + 1)
                    }
                }
            }
        }
    }

    func testBoardTimeoutActionsCommitAcrossRealSerialization() throws {
        for action in [BingoViewModel.ExpiredBoardCountdownResolution.postpone(minutes: 5), .markAsCompleted, .abandon] {
            try withFixture { repository, model, now in
                model.setBoardCountdownEndsAt(now.addingTimeInterval(-1))
                model.processExpiredCountdowns(now: now)
                let message = model.resolveExpiredBoardCountdown(action, now: now)
                try assertStable(repository, at: now) { loaded, disk in
                    switch action {
                    case .postpone(let minutes):
                        XCTAssertEqual(message, L10n.boardCountdownPostponedSuccess(minutes))
                        XCTAssertEqual(loaded.boardCountdownEndsAt, now.addingTimeInterval(Double(minutes * 60)))
                    case .markAsCompleted:
                        XCTAssertEqual(message, L10n.boardMarkedCompletedSuccess)
                        XCTAssertTrue(loaded.cells[0][0].isCompleted)
                        XCTAssertEqual(loaded.cells[0][0].completionStreakCount, 1)
                        XCTAssertNil(disk.loadBoardCountdownEndsAt())
                    case .abandon:
                        XCTAssertEqual(message, L10n.boardCountdownCanceledSuccess)
                        XCTAssertNil(disk.loadBoardCountdownEndsAt())
                    }
                }
            }
        }
    }
}
