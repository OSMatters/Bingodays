import Foundation

struct HomeTimeoutWorkContext: Equatable {
    let now: Date
    let shouldRunMaintenance: Bool
    let requiresLiveCountdownTicks: Bool
    let hasTimeoutDelayPicker: Bool
}

enum HomeTimeoutWorkStep: Equatable {
    case updateCountdownClock
    case handleBoardResetLifecycle
    case processTimeoutWork(refreshVisibilityWindows: Bool)
    case refreshCountdownTickSchedule
}

struct HomeTimeoutWorkPlan: Equatable {
    let context: HomeTimeoutWorkContext
    let steps: [HomeTimeoutWorkStep]
}

struct HomeTimeoutWorkStore {
    func shouldRunMaintenance(
        now: Date,
        hasComputedSchedule: Bool,
        nextWorkDate: Date?
    ) -> Bool {
        guard hasComputedSchedule else { return true }
        guard let nextWorkDate else { return false }
        return now >= nextWorkDate
    }

    func tickPlan(
        now: Date,
        shouldRunMaintenance: Bool,
        requiresLiveCountdownTicks: Bool,
        hasTimeoutDelayPicker: Bool
    ) -> HomeTimeoutWorkPlan? {
        let shouldUpdateClock = shouldRunMaintenance || requiresLiveCountdownTicks || hasTimeoutDelayPicker
        guard shouldUpdateClock else { return nil }

        var steps: [HomeTimeoutWorkStep] = [.updateCountdownClock]
        if shouldRunMaintenance {
            steps.append(contentsOf: [
                .handleBoardResetLifecycle,
                .processTimeoutWork(refreshVisibilityWindows: true),
                .refreshCountdownTickSchedule
            ])
        }

        return HomeTimeoutWorkPlan(
            context: HomeTimeoutWorkContext(
                now: now,
                shouldRunMaintenance: shouldRunMaintenance,
                requiresLiveCountdownTicks: requiresLiveCountdownTicks,
                hasTimeoutDelayPicker: hasTimeoutDelayPicker
            ),
            steps: steps
        )
    }

    func nextCountdownTickWorkDate(
        after now: Date,
        activeBoardNextUpdateDate: Date?,
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        lastBoardRulesEvaluationDateKey: String,
        hasAppliedDebugSimulatedResetThisLaunch: Bool,
        simulateNextDayBoardRuleReset: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        [
            activeBoardNextUpdateDate,
            nextOtherBoardTimeSensitiveUpdateDate(
                after: now,
                namedBoards: namedBoards,
                selectedBoardID: selectedBoardID,
                calendar: calendar
            ),
            nextBoardResetEvaluationDate(
                after: now,
                namedBoards: namedBoards,
                lastBoardRulesEvaluationDateKey: lastBoardRulesEvaluationDateKey,
                hasAppliedDebugSimulatedResetThisLaunch: hasAppliedDebugSimulatedResetThisLaunch,
                simulateNextDayBoardRuleReset: simulateNextDayBoardRuleReset,
                calendar: calendar
            )
        ]
        .compactMap(\.self)
        .min()
    }

    func nextBoardWithExpiredTimeout(
        in namedBoards: [BingoBoardStore.NamedBoard],
        excluding activeBoardID: UUID,
        now: Date
    ) -> UUID? {
        for board in namedBoards where board.id != activeBoardID {
            if let boardDeadline = board.countdownEndsAt, boardDeadline <= now {
                return board.id
            }
            if BoardEngine.expiredTaskCandidate(in: board.board, now: now) != nil {
                return board.id
            }
        }
        return nil
    }

    private func nextOtherBoardTimeSensitiveUpdateDate(
        after now: Date,
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        calendar: Calendar
    ) -> Date? {
        guard namedBoards.count > 1 else { return nil }
        guard let activeBoardID = selectedBoardID ?? namedBoards.first?.id else { return nil }

        var nextDate: Date?
        for board in namedBoards where board.id != activeBoardID {
            if let countdownEndsAt = board.countdownEndsAt {
                let candidate = countdownEndsAt <= now ? now : countdownEndsAt
                nextDate = nextDate.map { min($0, candidate) } ?? candidate
            }
            if let boardDate = BoardEngine.nextTimeSensitiveUpdateDate(
                in: board.board,
                now: now,
                calendar: calendar
            ) {
                nextDate = nextDate.map { min($0, boardDate) } ?? boardDate
            }
        }
        return nextDate
    }

    private func nextBoardResetEvaluationDate(
        after now: Date,
        namedBoards: [BingoBoardStore.NamedBoard],
        lastBoardRulesEvaluationDateKey: String,
        hasAppliedDebugSimulatedResetThisLaunch: Bool,
        simulateNextDayBoardRuleReset: Bool,
        calendar: Calendar
    ) -> Date? {
        guard !namedBoards.isEmpty else { return nil }

        if simulateNextDayBoardRuleReset,
           !hasAppliedDebugSimulatedResetThisLaunch {
            return now
        }

        if PointsStore.dateKey(for: now, calendar: calendar) != lastBoardRulesEvaluationDateKey {
            return now
        }

        var nextDate = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        )

        for board in namedBoards {
            let evaluation = BoardResetRuleEngine.pendingResetEvaluation(for: board, now: now, calendar: calendar)
            if evaluation.customResetDue || evaluation.shouldForceApplyForStaleCompletion {
                return now
            }
            guard let triggerTime = BoardResetRuleEngine.customResetTriggerTime(
                for: board,
                now: now,
                calendar: calendar
            ) else {
                continue
            }

            let candidate: Date
            if triggerTime > now {
                candidate = triggerTime
            } else {
                candidate = calendar.date(byAdding: .day, value: 1, to: triggerTime) ?? triggerTime.addingTimeInterval(86_400)
            }
            nextDate = nextDate.map { min($0, candidate) } ?? candidate
        }

        return nextDate
    }
}
