import Combine
import Foundation

struct HomeLifecycleWorkContext: Equatable {
    let now: Date
    let force: Bool
    let source: String
    let shouldApplyForegroundCleanup: Bool
}

enum HomeLifecycleWorkStep: Equatable {
    case loadPointsAfterFirstFrame
    case ensureBoardSwitcherLoaded
    case reloadBoardSwitcherSnapshotFromSharedStore
    case handleBoardResetLifecycle
    case forceApplyDebugBoardReset
    case evaluateFirstStepGuideEntry
    case updateCountdownClock
    case processTimeoutWork
    case syncTaskStartReminders
    case evaluateAppReviewPromptOpportunity
    case debugTileGestureBlockers
    case refreshCountdownTickSchedule
}

struct HomeLifecycleWorkPlan: Equatable {
    let context: HomeLifecycleWorkContext
    let steps: [HomeLifecycleWorkStep]
}

struct HomeLifecycleWorkStore {
    func catchUpPlan(
        now: Date,
        force: Bool,
        source: String,
        shouldApplyForegroundCleanup: Bool,
        simulateNextDayBoardRuleReset: Bool
    ) -> HomeLifecycleWorkPlan {
        var steps: [HomeLifecycleWorkStep] = [
            .loadPointsAfterFirstFrame,
            .ensureBoardSwitcherLoaded,
            .reloadBoardSwitcherSnapshotFromSharedStore,
            .handleBoardResetLifecycle
        ]
        if simulateNextDayBoardRuleReset {
            steps.append(.forceApplyDebugBoardReset)
        }
        steps.append(contentsOf: [
            .evaluateFirstStepGuideEntry,
            .updateCountdownClock,
            .processTimeoutWork,
            .syncTaskStartReminders,
            .evaluateAppReviewPromptOpportunity,
            .debugTileGestureBlockers,
            .refreshCountdownTickSchedule
        ])

        return HomeLifecycleWorkPlan(
            context: HomeLifecycleWorkContext(
                now: now,
                force: force,
                source: source,
                shouldApplyForegroundCleanup: shouldApplyForegroundCleanup
            ),
            steps: steps
        )
    }
}

enum AppReviewPromptCandidate: Equatable {
    case firstTwoLines
    case secondThreeDayStreak
    case secondFullBoard
    case debug

    var stageToRecord: Int? {
        switch self {
        case .firstTwoLines:
            return 1
        case .secondThreeDayStreak, .secondFullBoard:
            return 2
        case .debug:
            return nil
        }
    }
}

struct AppReviewPromptEvaluationState: Equatable {
    let now: Date
    let todayKey: String
    let forceDebugPrompt: Bool
    let hasPresentedDebugPromptThisLaunch: Bool
    let hasRatedPrompt: Bool
    let lifetimeShownCount: Int
    let cooldownUntil: Double
    let stage: Int
    let lastShownDay: String
    let completedLineCount: Int
    let isBoardFullyCompleted: Bool
    let consecutiveTaskCompletionDays: Int
}

struct AppReviewPromptPresentationState: Equatable {
    let isPromptPresented: Bool
    let debugBypassesBlockers: Bool
    let hasFirstStepGuideOverlay: Bool
    let isUpdatePromptPresented: Bool
    let isCustomResetDowngradeAlertPresented: Bool
    let isSidebarPresented: Bool
    let isQuickEditPresented: Bool
    let isContactUsPresented: Bool
    let isPointsFlowPresented: Bool
    let isBoardCountdownPresented: Bool
    let isBoardRulesPresented: Bool
    let isGridSizeSheetPresented: Bool
    let isShowingCelebration: Bool
    let isShowingBoardCompletionAnimation: Bool
    let hasBoardActionSheet: Bool
    let hasTimeoutDelayPicker: Bool
    let hasExpiredTaskEvent: Bool
    let hasExpiredBoardCountdownEvent: Bool
    let hasScheduledTaskReplacementEvent: Bool

    var hasBlockingPresentation: Bool {
        hasFirstStepGuideOverlay ||
            isUpdatePromptPresented ||
            isCustomResetDowngradeAlertPresented ||
            isSidebarPresented ||
            isQuickEditPresented ||
            isContactUsPresented ||
            isPointsFlowPresented ||
            isBoardCountdownPresented ||
            isBoardRulesPresented ||
            isGridSizeSheetPresented ||
            isShowingCelebration ||
            isShowingBoardCompletionAnimation ||
            hasBoardActionSheet ||
            hasTimeoutDelayPicker ||
            hasExpiredTaskEvent ||
            hasExpiredBoardCountdownEvent ||
            hasScheduledTaskReplacementEvent
    }
}

struct HomeAppReviewPromptStore {
    func candidate(
        trigger: AppReviewPromptCandidate?,
        state: AppReviewPromptEvaluationState
    ) -> AppReviewPromptCandidate? {
        if state.forceDebugPrompt, !state.hasPresentedDebugPromptThisLaunch {
            return .debug
        }

        guard !state.hasRatedPrompt,
              state.lifetimeShownCount < 2,
              state.now.timeIntervalSince1970 >= state.cooldownUntil else {
            return nil
        }

        if state.stage <= 0, state.completedLineCount >= 2 {
            return .firstTwoLines
        }

        guard state.stage == 1, state.lastShownDay != state.todayKey else {
            return nil
        }

        if trigger == .secondFullBoard, state.isBoardFullyCompleted {
            return .secondFullBoard
        }

        if trigger == .secondThreeDayStreak || trigger == nil,
           state.consecutiveTaskCompletionDays >= 3 {
            return .secondThreeDayStreak
        }

        if state.isBoardFullyCompleted {
            return .secondFullBoard
        }

        return nil
    }

    func canPresent(
        candidate: AppReviewPromptCandidate,
        state: AppReviewPromptPresentationState
    ) -> Bool {
        guard !state.isPromptPresented else { return false }
        if candidate == .debug, state.debugBypassesBlockers {
            return true
        }
        return !state.hasBlockingPresentation
    }
}

@MainActor
final class HomeAppReviewEvaluationStore: ObservableObject {
    typealias DelayedActionScheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void

    private struct PendingRequest {
        let boardID: UUID?
        let trigger: AppReviewPromptCandidate
    }

    private static let evaluationDelay: TimeInterval = 1.0

    private let scheduler: DelayedActionScheduler
    private var requestGeneration: UInt = 0
    private var pendingRequest: PendingRequest?

    init(scheduler: @escaping DelayedActionScheduler = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }) {
        self.scheduler = scheduler
    }

    func scheduleEvaluation(
        trigger: AppReviewPromptCandidate,
        boardID: UUID?,
        currentBoardID: @escaping @MainActor () -> UUID?,
        onEvaluate: @escaping @MainActor (AppReviewPromptCandidate) -> Void
    ) {
        let coalescedTrigger: AppReviewPromptCandidate
        if let pendingRequest, pendingRequest.boardID == boardID {
            coalescedTrigger = Self.coalescedTrigger(
                pending: pendingRequest.trigger,
                incoming: trigger
            )
        } else {
            coalescedTrigger = trigger
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        pendingRequest = PendingRequest(boardID: boardID, trigger: coalescedTrigger)

        scheduler(Self.evaluationDelay) { [weak self] in
            guard let self, self.requestGeneration == generation else { return }
            guard let request = self.pendingRequest else { return }
            self.pendingRequest = nil
            guard request.boardID == currentBoardID() else { return }
            onEvaluate(request.trigger)
        }
    }

    private static func coalescedTrigger(
        pending: AppReviewPromptCandidate,
        incoming: AppReviewPromptCandidate
    ) -> AppReviewPromptCandidate {
        if pending == .secondThreeDayStreak || incoming == .secondThreeDayStreak {
            return .secondThreeDayStreak
        }
        return incoming
    }
}
