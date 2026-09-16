import SwiftUI
import Combine

// These modifiers own SwiftUI lifecycle/onChange wiring only; business mutations stay in ContentView callbacks.
struct HomeBoardStateChange: Equatable {
    let didChangeCells: Bool
    let didChangeGridSize: Bool
    let didChangeCompletedLines: Bool
    let didChangeBoardCountdown: Bool

    var affectsTaskReminders: Bool {
        didChangeCells || didChangeGridSize
    }

    var appReviewPromptTrigger: AppReviewPromptCandidate? {
        if didChangeCells {
            return .secondThreeDayStreak
        }
        if didChangeCompletedLines {
            return .firstTwoLines
        }
        return nil
    }

    init(
        didChangeCells: Bool,
        didChangeGridSize: Bool,
        didChangeCompletedLines: Bool,
        didChangeBoardCountdown: Bool
    ) {
        self.didChangeCells = didChangeCells
        self.didChangeGridSize = didChangeGridSize
        self.didChangeCompletedLines = didChangeCompletedLines
        self.didChangeBoardCountdown = didChangeBoardCountdown
    }

    fileprivate init(
        oldSignature: HomeBoardStateObserversModifier.BoardSignature,
        newSignature: HomeBoardStateObserversModifier.BoardSignature
    ) {
        self.init(
            didChangeCells: oldSignature.cells != newSignature.cells,
            didChangeGridSize: oldSignature.gridSize != newSignature.gridSize,
            didChangeCompletedLines: oldSignature.completedLines != newSignature.completedLines,
            didChangeBoardCountdown: oldSignature.boardCountdownEndsAt != newSignature.boardCountdownEndsAt
        )
    }
}

struct HomeLifecycleObserversModifier: ViewModifier {
    @Binding var hasCheckedAppUpdateOnLaunch: Bool
    @Binding var hasStartedDeferredHomePreloads: Bool
    @Binding var hasStartedDeferredSubscriptionRefresh: Bool

    let scenePhase: ScenePhase
    let onProcessLifecycleEvents: (Date, Bool, String, Bool) -> Void
    let onCheckAppUpdate: () async -> Void
    let onRefreshLimitedTimeOfferConfig: () async -> Void
    let onRefreshAllSubscriptions: () async -> Void
    let onRefreshEntitlements: () async -> Void
    let onEnforceCustomResetAccess: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                onProcessLifecycleEvents(Date(), true, "onAppear", true)
                refreshLimitedTimeOfferConfig()
                startDeferredHomePreloadsIfNeeded()
                startDeferredUpdateCheckIfNeeded()
                startDeferredSubscriptionRefreshIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                onProcessLifecycleEvents(Date(), true, "sceneActive", true)
                Task {
                    await onRefreshEntitlements()
                    onEnforceCustomResetAccess()
                }
                Task {
                    await onCheckAppUpdate()
                }
                refreshLimitedTimeOfferConfig()
            }
    }

    private func refreshLimitedTimeOfferConfig() {
        Task {
            await onRefreshLimitedTimeOfferConfig()
        }
    }

    private func startDeferredHomePreloadsIfNeeded() {
        guard !hasStartedDeferredHomePreloads else { return }
        hasStartedDeferredHomePreloads = true
        // This tiny, tap-triggered effect must already be decoded before the user can complete
        // their first task. The remaining larger effects stay deferred.
        PAGCompletionView.preload(
            resourceName: "complete_once_bmp",
            playsSound: true,
            soundResourceName: "complete_once",
            soundFileExtension: "mp3",
            cacheAllFrames: true,
            renderScale: 1,
            maxFrameRate: 60
        )
        // Stagger startup work so first-frame home rendering does not compete with preloads.
        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                PAGCompletionView.preload(
                    resourceName: "complete_bingo_background_bmp",
                    cacheAllFrames: true,
                    renderScale: 1,
                    maxFrameRate: 60
                )
                PAGCompletionView.preload(
                    resourceName: "complete_bingo_bmp",
                    playsSound: true,
                    soundResourceName: "complete_bingo",
                    soundFileExtension: "mp3",
                    renderScale: 1,
                    maxFrameRate: 60
                )
                PAGRewardSoundPlayer.shared.preload(
                    resourceName: "complete_bingo_background",
                    fileExtension: "mp3"
                )
                PAGRewardSoundPlayer.shared.preload(
                    resourceName: "complete_allbingo",
                    fileExtension: "mp3"
                )
                PointsSoundPlayer.shared.preload()
            }
        }
    }

    private func startDeferredUpdateCheckIfNeeded() {
        guard !hasCheckedAppUpdateOnLaunch else { return }
        hasCheckedAppUpdateOnLaunch = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await onCheckAppUpdate()
        }
    }

    private func startDeferredSubscriptionRefreshIfNeeded() {
        guard !hasStartedDeferredSubscriptionRefresh else { return }
        hasStartedDeferredSubscriptionRefresh = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await onRefreshAllSubscriptions()
            onEnforceCustomResetAccess()
        }
    }
}

struct HomePresentationStateObserversModifier: ViewModifier {
    @Binding var isEditActionsExpanded: Bool
    @Binding var boardRulesTargetBoardID: UUID?

    let isQuickEditPresented: Bool
    let isBoardCountdownPresented: Bool
    let isBoardRulesPresented: Bool
    let isGridSizeSheetPresented: Bool
    let isSidebarPresented: Bool
    let firstStepGuideOverlay: FirstStepGuideOverlay?
    let isUpdatePromptPresented: Bool
    let boardActionSheetBoardID: UUID?
    let onDebugTileGestureBlockers: (String) -> Void

    func body(content: Content) -> some View {
        content
            // Presentation changes collapse mutually exclusive overlays and clear transient drafts.
            .onChange(of: isQuickEditPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: isBoardCountdownPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: isBoardRulesPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
                if !newValue { boardRulesTargetBoardID = nil }
            }
            .onChange(of: isGridSizeSheetPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: isSidebarPresented) { _, _ in
                onDebugTileGestureBlockers("sidebar")
            }
            .onChange(of: isEditActionsExpanded) { _, _ in
                onDebugTileGestureBlockers("quickEditOverlay")
            }
            .onChange(of: firstStepGuideOverlay) { _, _ in
                onDebugTileGestureBlockers("firstStepGuide")
            }
            .onChange(of: isUpdatePromptPresented) { _, _ in
                onDebugTileGestureBlockers("updatePrompt")
            }
            .onChange(of: boardActionSheetBoardID) { _, _ in
                onDebugTileGestureBlockers("boardActionSheet")
            }
    }
}

struct HomeBoardStateObserversModifier: ViewModifier {
    fileprivate struct BoardSignature: Equatable {
        let cells: [[BingoCell]]
        let gridSize: Int
        let completedLines: Set<BingoLine>
        let boardCountdownEndsAt: Date?
    }

    let cells: [[BingoCell]]
    let gridSize: Int
    let completedLines: Set<BingoLine>
    let boardCountdownEndsAt: Date?
    let hasCompletedEntitlementRefresh: Bool
    let hasPremiumAccess: Bool
    let onSyncSelectedBoardSnapshot: (HomeBoardStateChange) -> Void
    let onEvaluateFirstStepGuideProgress: () -> Void
    let onEvaluateAppReviewPromptOpportunity: (AppReviewPromptCandidate) -> Void
    let onReconcileStickerOwnership: () -> Void
    let onEnforceCustomResetAccess: () -> Void

    private var boardSignature: BoardSignature {
        BoardSignature(
            cells: cells,
            gridSize: gridSize,
            completedLines: completedLines,
            boardCountdownEndsAt: boardCountdownEndsAt
        )
    }

    func body(content: Content) -> some View {
        content
            // Board mutations are mirrored into the selected-board snapshot for switcher persistence.
            .onChange(of: boardSignature) { oldSignature, newSignature in
                let change = HomeBoardStateChange(oldSignature: oldSignature, newSignature: newSignature)
                onSyncSelectedBoardSnapshot(change)

                if change.didChangeCells {
                    onEvaluateFirstStepGuideProgress()
                    onReconcileStickerOwnership()
                }

                if let trigger = change.appReviewPromptTrigger {
                    onEvaluateAppReviewPromptOpportunity(trigger)
                }
            }
            .onChange(of: hasCompletedEntitlementRefresh) { _, hasCompleted in
                guard hasCompleted else { return }
                onEnforceCustomResetAccess()
            }
            .onChange(of: hasPremiumAccess) { _, _ in
                // Entitlement changes can revoke custom reset access, so re-check after refreshes.
                guard hasCompletedEntitlementRefresh else { return }
                onEnforceCustomResetAccess()
            }
    }
}

struct HomePointsAndTimeoutObserversModifier: ViewModifier {
    let totalPoints: Int
    let availablePoints: Int
    let dailyResetNoticeID: Int
    let countdownTicker: Publishers.Autoconnect<Timer.TimerPublisher>
    let expiredTaskEventID: UUID?
    let expiredBoardCountdownEventID: UUID?
    let onReconcileStickerOwnership: () -> Void
    let onAvailablePointsChange: (Int, Int) -> Void
    let onShowDailyReset: () -> Void
    let onTick: (Date) -> Void
    let onExpiredTaskEventChange: () -> Void
    let onExpiredBoardCountdownEventChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                onReconcileStickerOwnership()
            }
            .onChange(of: totalPoints) { _, _ in
                onReconcileStickerOwnership()
            }
            .onChange(of: availablePoints) { oldValue, newValue in
                onReconcileStickerOwnership()
                onAvailablePointsChange(oldValue, newValue)
            }
            .onChange(of: dailyResetNoticeID) { _, newValue in
                guard newValue > 0 else { return }
                onShowDailyReset()
            }
            .onReceive(countdownTicker) { _ in
                // The callback owns timeout side effects; the modifier only wires the tick.
                onTick(Date())
            }
            .onChange(of: expiredTaskEventID) { _, _ in
                onExpiredTaskEventChange()
            }
            .onChange(of: expiredBoardCountdownEventID) { _, _ in
                onExpiredBoardCountdownEventChange()
            }
    }
}
