import SwiftUI
import Combine

// These modifiers own SwiftUI lifecycle/onChange wiring only; business mutations stay in ContentView callbacks.
struct HomeLifecycleObserversModifier: ViewModifier {
    @Binding var boardTemplateShareDraft: BoardTemplatePayload?
    @Binding var isTemplateShareComposerPresented: Bool
    @Binding var hasCheckedAppUpdateOnLaunch: Bool
    @Binding var hasStartedDeferredHomePreloads: Bool
    @Binding var hasStartedDeferredSubscriptionRefresh: Bool

    let scenePhase: ScenePhase
    let onDismissTemplateImportPreview: () -> Void
    let onDismissPendingTemplate: () -> Void
    let onProcessLifecycleEvents: (Date, Bool, String, Bool) -> Void
    let onCheckAppUpdate: () async -> Void
    let onRefreshLimitedTimeOfferConfig: () async -> Void
    let onRefreshAllSubscriptions: () async -> Void
    let onRefreshEntitlements: () async -> Void
    let onEnforceCustomResetAccess: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !AppFeatureFlags.isTemplateSharingEnabled {
                    boardTemplateShareDraft = nil
                    isTemplateShareComposerPresented = false
                    onDismissTemplateImportPreview()
                    onDismissPendingTemplate()
                }

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
        // Stagger startup work so first-frame home rendering does not compete with preloads.
        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 900_000_000)
            PAGCompletionView.preload(resourceName: "cat_bmp")
            PointsSoundPlayer.shared.preload()
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
    @Binding var boardTemplateShareDraft: BoardTemplatePayload?
    @Binding var boardRulesTargetBoardID: UUID?

    let isQuickEditPresented: Bool
    let pendingTemplate: BoardTemplatePayload?
    let pendingTemplateSource: String
    let isTemplateShareComposerPresented: Bool
    let isTemplateImportPreviewPresented: Bool
    let isBoardCountdownPresented: Bool
    let isBoardRulesPresented: Bool
    let isBlackBoxModePresented: Bool
    let isGridSizeSheetPresented: Bool
    let isSidebarPresented: Bool
    let firstStepGuideOverlay: FirstStepGuideOverlay?
    let isUpdatePromptPresented: Bool
    let boardActionSheetBoardID: UUID?
    let onPresentImportPreview: (BoardTemplatePayload, String) -> Void
    let onDismissPendingTemplate: () -> Void
    let onClearTemplateImportPreview: () -> Void
    let onDebugTileGestureBlockers: (String) -> Void

    func body(content: Content) -> some View {
        content
            // Presentation changes collapse mutually exclusive overlays and clear transient drafts.
            .onChange(of: isQuickEditPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: pendingTemplate) { _, incomingTemplate in
                guard AppFeatureFlags.isTemplateSharingEnabled else { return }
                guard let incomingTemplate else { return }
                onPresentImportPreview(incomingTemplate, pendingTemplateSource)
                onDismissPendingTemplate()
            }
            .onChange(of: isTemplateShareComposerPresented) { _, isPresented in
                if !isPresented {
                    boardTemplateShareDraft = nil
                }
            }
            .onChange(of: isTemplateImportPreviewPresented) { _, isPresented in
                if !isPresented { onClearTemplateImportPreview() }
            }
            .onChange(of: isBoardCountdownPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: isBoardRulesPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
                if !newValue { boardRulesTargetBoardID = nil }
            }
            .onChange(of: isBlackBoxModePresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
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
    let cells: [[BingoCell]]
    let gridSize: Int
    let completedLines: Set<BingoLine>
    let boardCountdownEndsAt: Date?
    let hasCompletedEntitlementRefresh: Bool
    let hasPremiumAccess: Bool
    let onSyncSelectedBoardSnapshot: () -> Void
    let onEvaluateFirstStepGuideProgress: () -> Void
    let onEvaluateAppReviewTaskCompletionOpportunity: () -> Void
    let onEvaluateAppReviewLineCompletionOpportunity: () -> Void
    let onReconcileStickerOwnership: () -> Void
    let onEnforceCustomResetAccess: () -> Void

    func body(content: Content) -> some View {
        content
            // Board mutations are mirrored into the selected-board snapshot for switcher persistence.
            .onChange(of: cells) { _, _ in
                onSyncSelectedBoardSnapshot()
                onEvaluateFirstStepGuideProgress()
                onEvaluateAppReviewTaskCompletionOpportunity()
                onReconcileStickerOwnership()
            }
            .onChange(of: gridSize) { _, _ in
                onSyncSelectedBoardSnapshot()
            }
            .onChange(of: completedLines) { _, _ in
                onSyncSelectedBoardSnapshot()
                onEvaluateAppReviewLineCompletionOpportunity()
            }
            .onChange(of: boardCountdownEndsAt) { _, _ in
                onSyncSelectedBoardSnapshot()
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
