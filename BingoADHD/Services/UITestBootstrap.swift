#if DEBUG && targetEnvironment(simulator)
import Foundation
import UIKit

/// Seeds production stores only on a fresh simulator owned by the regression runner.
/// Relaunches in the same test retain the actual committed data.
@MainActor
enum UITestBootstrap {
    private static var prepared = false

    static func prepareIfNeeded() {
        guard AppDebugFlags.uiTesting, !prepared else { return }
        prepared = true
        UIView.setAnimationsEnabled(false)
        let environment = ProcessInfo.processInfo.environment
        guard let run = environment["BINGODAYS_UI_TEST_RUN"], UUID(uuidString: run) != nil,
              let scenario = environment["BINGODAYS_UI_TEST_SCENARIO"],
              ["tasks", "task-timeout", "board-timeout"].contains(scenario) else {
            preconditionFailure("UI tests require a known scenario and unique run ID")
        }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "ui_test_seed_run") != run else { return }
        defaults.set(true, forKey: AppSettings.hasSeenOnboardingKey)
        defaults.set(FirstStepGuideState.finished.rawValue, forKey: AppSettings.firstStepGuideStateKey)
        defaults.set(true, forKey: AppSettings.firstStepGuideIntroShownKey)
        defaults.set(true, forKey: AppSettings.hasAcknowledgedBoardEditHintKey)
        defaults.set(true, forKey: AppSettings.hasInteractedWithBoardPanelKey)
        defaults.set("en", forKey: AppSettings.languageKey)
        NativeICloudPreferences.isEnabled = false
        precondition(TaskCompletionHistoryStore.save([]))
        precondition(TaskHistoryStore.save([]))
        precondition(BingoTimeoutStore.replacePayload([:]))
        BingoDiaryStore.replaceAllEntriesDictionary([:])
        let now = Date()
        var cache = BoardEngine.createEmptyGrid(size: 5)
        cache[0][0] = BingoCell(text: "UI task")
        cache[0][1] = BingoCell(text: "Future neighbour", startVisibleAt: now.addingTimeInterval(604800))
        cache[1][1] = BingoCell(text: "Daily neighbour", recurrenceRule: .init(kind: .daily))
        if scenario == "task-timeout" {
            cache[0][0].startVisibleAt = now.addingTimeInterval(-120)
            cache[0][0].endVisibleAt = now.addingTimeInterval(-60)
        }
        let board = SavedBoard(gridSize: 3,
            cells: BoardEngine.projectVisibleCells(from: cache, size: 3, referenceDate: now),
            completedLines: [], fullBoardCells: cache)
        let deadline = scenario == "board-timeout" ? now.addingTimeInterval(-60) : nil
        let named = BingoBoardStore.NamedBoard(name: "UI regression", board: board,
            countdownEndsAt: deadline, taskResetMode: .keepTaskStatus, updatedAt: now)
        precondition(BingoBoardStore.saveNamedBoardsSnapshot(.init(selectedBoardID: named.id, boards: [named]), reloadWidgets: false))
        precondition(BingoBoardStore.saveBoard(board, savedAt: now, associatedBoardID: named.id, reloadWidgets: false))
        BingoBoardStore.saveBoardCountdownEndsAt(deadline)
        precondition(PointsStore.saveState(totalPoints: 50, lifetimePoints: 50,
            dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)))
        defaults.set(run, forKey: "ui_test_seed_run")
    }
}
#endif
