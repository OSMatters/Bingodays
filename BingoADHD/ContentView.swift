import SwiftUI
import StoreKit
import UIKit

struct ContentView: View {
    private enum FeedbackEmailKind {
        case bugReport
        case featureSuggestion

        var logValue: String {
            switch self {
            case .bugReport:
                return "bug_report"
            case .featureSuggestion:
                return "feature_suggestion"
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var iCloudSyncCoordinator: NativeICloudSyncCoordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @StateObject private var viewModel = BingoViewModel()
    @StateObject private var boardManagementStore = BoardManagementStore()
    @StateObject private var pointsFeatureStore = PointsFeatureStore()
    @StateObject private var toastStore = HomeToastStore()
    @StateObject private var pointsAnimationStore = PointsAnimationStore()
    @StateObject private var boardActionPresentationStore = BoardActionPresentationStore()
    @StateObject private var boardSwitchAnimationStore = BoardSwitchAnimationStore()
    @StateObject private var homeBoardSnapshotSyncStore = HomeBoardSnapshotSyncStore()
    @StateObject private var appReviewEvaluationStore = HomeAppReviewEvaluationStore()
    @StateObject private var taskStartReminderSyncStore: TaskStartReminderSyncStore
    private let homeLifecycleWorkStore = HomeLifecycleWorkStore()
    private let homeTimeoutWorkStore = HomeTimeoutWorkStore()
    private let homeAppReviewPromptStore = HomeAppReviewPromptStore()
    @State private var selectedMainTab: HomeMainTab = .home
    @State private var meGreetingIndex = MeGreeting.randomIndex()
    @State private var isSidebarPresented = false
    @State private var isSettingsExpanded = false
    @State private var isWidgetGuideExpanded = false
    @State private var isThemePickerExpanded = false
    @State private var isThemePickerSheetPresented = false
    @State private var isMeSettingsPresented = false
    @State private var isICloudSyncPresented = false
    @State private var isPointsFlowPresented = false
    @State private var isPointsTabSubpagePresented = false
    @State private var pointsEntryFromBottomTab = true
    @State private var pointsNavigationOpacity: Double = 1
    @State private var isBoardCountdownPresented = false
    @State private var isBoardRulesPresented = false
    @State private var boardRulesTargetBoardID: UUID?
    @State private var pendingPremiumBoardRulesDraft: BoardRulesDraft?
    @State private var restoredBoardRulesDraft: BoardRulesDraft?
    @State private var selectedStickerID: UUID?
    @State private var isDiaryPresented = false
    @State private var isPremiumPaywallPresented = false
    @State private var isLimitedTimeDiscountPresented = false
    @State private var premiumPaywallSource = "unknown"
    @State private var isQuickEditPresented = false
    @State private var isContactUsPresented = false
    @State private var isEditActionsExpanded = false
    @State private var isGridSizeSheetPresented = false
    @State private var isClearBoardConfirmationPresented = false
    @State private var taskTimeoutDelayMinutes = 10
    @State private var boardTimeoutDelayMinutes = 10
    @State private var timeoutDelayPickerContext: TimeoutDelayPickerContext?
    @State private var timeoutDelayPickerHours = 0
    @State private var timeoutDelayPickerMinutes = 10
    @State private var isUpdatePromptPresented = false
    @State private var isAppReviewPromptPresented = false
    @State private var hasCheckedAppUpdateOnLaunch = false
    @State private var pendingUpdateInfo: AppUpdateInfo?
    @State private var hasStartedDeferredHomePreloads = false
    @State private var hasStartedDeferredSubscriptionRefresh = false
    @State private var firstStepGuideOverlay: FirstStepGuideOverlay?
    @State private var isCustomResetDowngradeAlertPresented = false
    @State private var customResetDowngradeBoardNames: [String] = []
    @State private var lastBoardRulesEvaluationDateKey = ""
    @State private var hasAppliedDebugSimulatedResetThisLaunch = false
    @State private var lastCustomResetDebugToastKey = ""
    @State private var hasDismissedBoardEditHintThisLaunch = false
    @State private var pendingAppReviewPromptCandidate: AppReviewPromptCandidate?
    @State private var hasPresentedDebugAppReviewPromptThisLaunch = false
    @State private var limitedTimeOfferConfig = LimitedTimeOfferConfig.disabled
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppSettings.soundEffectsEnabledKey) private var isSoundEffectsEnabled = true
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue
    @AppStorage(AppSettings.lastPromptedUpdateVersionKey) private var lastPromptedUpdateVersion = ""
    @AppStorage(AppSettings.skippedUpdateVersionKey) private var skippedUpdateVersion = ""
    @AppStorage(AppSettings.hasRatedAppReviewPromptKey) private var hasRatedAppReviewPrompt = false
    @AppStorage(AppSettings.appReviewPromptStageKey) private var appReviewPromptStage = 0
    @AppStorage(AppSettings.appReviewPromptCooldownUntilKey) private var appReviewPromptCooldownUntil = 0.0
    @AppStorage(AppSettings.appReviewPromptLifetimeShownCountKey) private var appReviewPromptLifetimeShownCount = 0
    @AppStorage(AppSettings.appReviewPromptLastShownDayKey) private var appReviewPromptLastShownDay = ""
    @AppStorage(AppSettings.firstStepGuideStateKey) private var firstStepGuideStateRawValue = FirstStepGuideState.notStarted.rawValue
    @AppStorage(AppSettings.firstStepGuideMilestoneKey) private var firstStepGuideMilestoneShown = 0
    @AppStorage(AppSettings.hasVisitedPremiumPaywallWithoutPurchaseKey) private var hasVisitedPremiumPaywallWithoutPurchase = false
    @AppStorage(AppSettings.hasLegacyLimitedTimeDiscountExposureKey) private var hasLegacyLimitedTimeDiscountExposure = false
    @AppStorage(AppSettings.limitedTimeDiscountStartedAtKey) private var limitedTimeDiscountStartedAt = 0.0
    @AppStorage(AppSettings.limitedTimeDiscountCampaignIDKey) private var limitedTimeDiscountCampaignID = ""

    init(taskStartReminderScheduler: any TaskStartReminderScheduling = LiveTaskStartReminderScheduler()) {
        _taskStartReminderSyncStore = StateObject(
            wrappedValue: TaskStartReminderSyncStore(scheduler: taskStartReminderScheduler)
        )
    }
    @AppStorage(AppSettings.hasAcknowledgedBoardEditHintKey) private var hasAcknowledgedBoardEditHint = false
    @AppStorage(AppSettings.hasInteractedWithBoardPanelKey) private var hasInteractedWithBoardPanel = false
    private let countdownTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var countdownNow = Date()
    @State private var nextCountdownTickWorkDate: Date?
    @State private var hasComputedCountdownTickSchedule = false
    private var bingoStreakDays: Int { BingoDiaryStore.consecutiveBingoDays() }
    private var streakGoals: [Int] { bingoStreakDays >= 60 ? [60, 180, 270, 365] : [7, 14, 30, 60] }
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var activeThemeColor: Color { activeTheme.color }
    private let conciseSurfaceColor = Color(hex: "FAF9F3")
    private var homeThemeBackgroundTint: some View {
        Color(hex: "FAF9F3")
    }
    private var appShortVersion: String {
        AppUpdatePromptStore.currentAppVersion
    }
    private var availablePoints: Int {
        pointsFeatureStore.availablePoints(totalPoints: viewModel.totalPoints)
    }

    private var firstStepGuideState: FirstStepGuideState {
        FirstStepGuideState(rawValue: firstStepGuideStateRawValue) ?? .notStarted
    }

    private let boardNameMaxLength = BoardManagementStore.boardNameMaxLength
    private var namedBoards: [BingoBoardStore.NamedBoard] {
        get { boardManagementStore.namedBoards }
        nonmutating set { boardManagementStore.namedBoards = newValue }
    }
    private var selectedBoardID: UUID? {
        get { boardManagementStore.selectedBoardID }
        nonmutating set { boardManagementStore.selectedBoardID = newValue }
    }
    private var hasLoadedBoardSwitcherState: Bool {
        get { boardManagementStore.hasLoadedBoardSwitcherState }
        nonmutating set { boardManagementStore.hasLoadedBoardSwitcherState = newValue }
    }
    private var canCreateAdditionalBoard: Bool {
        subscriptionManager.hasPremiumAccess || namedBoards.count < 1
    }
    private var selectedNamedBoardIndex: Int? {
        boardManagementStore.selectedNamedBoardIndex
    }

    private var boardSwipeBlockingState: BoardSwitchAnimationStore.SwipeBlockingState {
        BoardSwitchAnimationStore.SwipeBlockingState(
            isSidebarPresented: isSidebarPresented,
            isQuickEditPresented: isQuickEditPresented,
            isEditActionsExpanded: isEditActionsExpanded,
            isBoardCountdownPresented: isBoardCountdownPresented,
            isBoardRulesPresented: isBoardRulesPresented,
            hasTimeoutDelayPicker: timeoutDelayPickerContext != nil,
            hasExpiredTaskEvent: viewModel.expiredTaskEvent != nil,
            hasExpiredBoardCountdownEvent: viewModel.expiredBoardCountdownEvent != nil,
            hasScheduledTaskReplacementEvent: viewModel.scheduledTaskReplacementEvent != nil
        )
    }

    private var tileGestureOverlayDebugState: TileGestureDebugLogger.OverlayState {
        TileGestureDebugLogger.OverlayState(
            isSidebarPresented: isSidebarPresented,
            isEditActionsExpanded: isEditActionsExpanded,
            hasFirstStepGuideOverlay: firstStepGuideOverlay != nil,
            isUpdatePromptPresented: isUpdatePromptPresented,
            hasBoardActionSheet: boardActionPresentationStore.actionSheetBoardID != nil,
            hasExpiredTaskEvent: viewModel.expiredTaskEvent != nil,
            hasExpiredBoardCountdownEvent: viewModel.expiredBoardCountdownEvent != nil,
            hasScheduledTaskReplacementEvent: viewModel.scheduledTaskReplacementEvent != nil,
            hasTimeoutDelayPicker: timeoutDelayPickerContext != nil,
            isBoardRulesPresented: isBoardRulesPresented,
            isBoardCountdownPresented: isBoardCountdownPresented,
            isGridSizeSheetPresented: isGridSizeSheetPresented
        )
    }
    private var shouldShowMainTabBar: Bool {
        guard !(selectedMainTab == .me && isMeSettingsPresented) else { return false }
        switch selectedMainTab {
        case .home:
            return !isHomeMainTabBarSuppressed
        case .points:
            return !isPointsTabSubpagePresented
        case .me:
            return true
        }
    }
    private var isHomeMainTabBarSuppressed: Bool {
        boardActionPresentationStore.actionSheetBoardID != nil ||
            firstStepGuideOverlay != nil ||
            isUpdatePromptPresented ||
            isAppReviewPromptPresented ||
            isCustomResetDowngradeAlertPresented ||
            viewModel.expiredTaskEvent != nil ||
            viewModel.expiredBoardCountdownEvent != nil ||
            viewModel.scheduledTaskReplacementEvent != nil ||
            timeoutDelayPickerContext != nil
    }
    private var selectedBoardName: String {
        boardManagementStore.selectedBoardName
    }
    private var shouldShowBoardEditHint: Bool {
        if AppDebugFlags.forceBoardEditHint {
            return !hasDismissedBoardEditHintThisLaunch
        }
        return !hasInteractedWithBoardPanel && !hasAcknowledgedBoardEditHint
    }
    private var shouldReserveBoardEditHintSpace: Bool {
        hasInteractedWithBoardPanel || hasAcknowledgedBoardEditHint
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var usesPadBottomHalfSheets: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private func shortDiagnosticID(_ id: UUID?) -> String {
        guard let id else { return "none" }
        return String(id.uuidString.prefix(8))
    }

    private func diagnosticHomeStateDetails(source: String) -> [String: String] {
        [
            "source": source,
            "selected_board_id": shortDiagnosticID(selectedBoardID),
            "board_count": "\(namedBoards.count)",
            "grid_size": "\(viewModel.gridSize)",
            "has_premium": "\(subscriptionManager.hasPremiumAccess)",
            "entitlement_refresh_complete": "\(subscriptionManager.hasCompletedEntitlementRefresh)",
            "limited_offer_enabled": "\(limitedTimeOfferConfig.isEnabled(forAppVersion: appShortVersion))",
            "limited_offer_eligible": "\(hasUnlockedLimitedOfferEntry)",
            "limited_offer_should_show": "\(shouldShowLimitedOfferEntry)",
            "sidebar": "\(isSidebarPresented)",
            "edit_actions": "\(isEditActionsExpanded)",
            "points_flow": "\(isPointsFlowPresented)",
            "contact": "\(isContactUsPresented)",
            "quick_edit": "\(isQuickEditPresented)",
            "diary": "\(isDiaryPresented)",
            "premium_paywall": "\(isPremiumPaywallPresented)",
            "limited_offer": "\(isLimitedTimeDiscountPresented)",
            "app_review_prompt": "\(isAppReviewPromptPresented)",
            "update_prompt": "\(isUpdatePromptPresented)",
            "board_countdown": "\(isBoardCountdownPresented)",
            "board_rules": "\(isBoardRulesPresented)",
            "grid_size_sheet": "\(isGridSizeSheetPresented)",
            "board_action_sheet": "\(boardActionPresentationStore.actionSheetBoardID != nil)",
            "timeout_delay_picker": "\(timeoutDelayPickerContext != nil)",
            "expired_task": "\(viewModel.expiredTaskEvent != nil)",
            "expired_board": "\(viewModel.expiredBoardCountdownEvent != nil)",
            "scheduled_replace": "\(viewModel.scheduledTaskReplacementEvent != nil)"
        ]
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }

    private var maxGridSizeForCurrentPlan: Int {
        subscriptionManager.hasPremiumAccess ? 5 : 4
    }

    private func resizeGridWithPremiumGate(targetSize: Int, source: String) {
        DiagnosticLogStore.recordUserAction(
            "grid_size.resize_request",
            details: diagnosticHomeStateDetails(source: source)
                .merging([
                    "current_grid_size": "\(viewModel.gridSize)",
                    "target_grid_size": "\(targetSize)"
                ]) { current, _ in current }
        )
        guard targetSize > viewModel.gridSize else {
            viewModel.resizeGrid(to: targetSize)
            DiagnosticLogStore.recordStateChange(
                "grid_size.resized",
                details: [
                    "source": source,
                    "target_grid_size": "\(targetSize)"
                ]
            )
            return
        }

        guard targetSize <= maxGridSizeForCurrentPlan else {
            DiagnosticLogStore.recordWarning(
                "grid_size.blocked_premium",
                details: [
                    "source": source,
                    "current_grid_size": "\(viewModel.gridSize)",
                    "target_grid_size": "\(targetSize)",
                    "has_premium": "\(subscriptionManager.hasPremiumAccess)"
                ]
            )
            AnalyticsService.logPremiumGrid5x5LimitHit(
                currentGridSize: viewModel.gridSize,
                source: source
            )
            let hasBlockingOverlay = isGridSizeSheetPresented || isEditActionsExpanded
            if isGridSizeSheetPresented {
                isGridSizeSheetPresented = false
            }
            if isEditActionsExpanded {
                isEditActionsExpanded = false
            }
            if hasBlockingOverlay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    presentPremiumPaywall(source: source)
                }
            } else {
                presentPremiumPaywall(source: source)
            }
            return
        }

        viewModel.resizeGrid(to: targetSize)
        DiagnosticLogStore.recordStateChange(
            "grid_size.resized",
            details: [
                "source": source,
                "target_grid_size": "\(targetSize)"
            ]
        )
    }

    private func presentPremiumPaywall(source: String) {
        DiagnosticLogStore.recordUserAction(
            "premium_paywall.request",
            details: diagnosticHomeStateDetails(source: source)
        )
        if source.lowercased().contains("reset") {
            AnalyticsService.logPremiumCustomResetTimeLimitHit(source: source)
        }
        premiumPaywallSource = source
        isPremiumPaywallPresented = true
        DiagnosticLogStore.recordStateChange(
            "premium_paywall.presented",
            details: diagnosticHomeStateDetails(source: source)
        )
        Task { @MainActor in
            await subscriptionManager.refreshEntitlements()
            if subscriptionManager.hasPremiumAccess {
                DiagnosticLogStore.recordStateChange(
                    "premium_paywall.member_center_resolved",
                    details: diagnosticHomeStateDetails(source: source)
                )
            }
        }
    }

    private func presentLimitedTimeDiscount() {
        guard shouldShowLimitedOfferEntry else {
            DiagnosticLogStore.recordWarning(
                "limited_offer.blocked",
                details: diagnosticHomeStateDetails(source: "limited_offer_entry")
            )
            return
        }
        Task { @MainActor in
            await subscriptionManager.refreshEntitlements()
            guard shouldShowLimitedOfferEntry else {
                DiagnosticLogStore.recordStateChange(
                    "limited_offer.dismissed_after_refresh",
                    details: diagnosticHomeStateDetails(source: "limited_offer_entry")
                )
                clearLimitedOfferEntryIfPremium()
                return
            }
            syncLimitedTimeOfferCampaignIfNeeded(for: limitedTimeOfferConfig)
            isLimitedTimeDiscountPresented = true
            DiagnosticLogStore.recordStateChange(
                "limited_offer.presented",
                details: diagnosticHomeStateDetails(source: "limited_offer_entry")
            )
            await subscriptionManager.warmupProductsForPaywall()
            clearLimitedOfferEntryIfPremium()
        }
    }

    var body: some View {
        withStateObservers(
            content: withBoardAlerts(
                content: withPresentationLayers(
                    content: mainScreenContent
                )
            )
        )
        .modifier(BlindBoxSilentTicketRefresh())
        .adaptivePadBottomHalfSheet(
            isPresented: $isThemePickerSheetPresented,
            usePadPresentation: usesPadBottomHalfSheets,
            backgroundColor: NeumorphicColors.background,
            contentMaxWidth: 720,
            maximumPadHeight: 210
        ) {
            HomeThemePickerSheet(
                themeRawValue: $themeRawValue,
                isPadLayout: isPadLayout
            )
            .presentationDetents([.height(isPadLayout ? 158 : 138)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isICloudSyncPresented) {
            NativeICloudSettingsView(
                isPadLayout: isPadLayout,
                themeColor: activeThemeColor
            )
                .environmentObject(iCloudSyncCoordinator)
        }
        .onAppear {
            resetLimitedOfferStateForDebugIfNeeded()
            clearLimitedOfferEntryIfPremium()
        }
        .onChange(of: subscriptionManager.hasPremiumAccess) { _, hasPremiumAccess in
            clearLimitedOfferEntryIfPremium()
            if hasPremiumAccess {
                restorePendingPremiumBoardRulesDraftIfNeeded()
            }
        }
        .onChange(of: selectedMainTab) { _, newValue in
            if newValue == .me {
                meGreetingIndex = MeGreeting.randomIndex(excluding: meGreetingIndex)
            }
            if newValue != .me {
                isMeSettingsPresented = false
            }
            if newValue != .points {
                isPointsTabSubpagePresented = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .limitedOfferEligibilityDidChange)) { _ in
            Task {
                await refreshLimitedTimeOfferConfig()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nativeICloudPrimaryProjectionDidChange)) { _ in
            // A remote projection replaces the durable board atomically. It is not
            // a sequence of user taps, so per-cell completion animations would make
            // unchanged neighboring tiles appear to toggle repeatedly while SwiftUI
            // reloads the snapshot.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pointsFeatureStore.reloadAfterExternalDataChange()
                reloadBoardSwitcherSnapshotFromSharedStoreIfNeeded(
                    now: .now,
                    persistViewModelState: false
                )
            }
        }
    }

    private var mainScreenContent: some View {
        GeometryReader { geo in
            let usesPadLayout = isPadLayout && geo.size.width >= 768
            let isPadLandscapeWindow = UIDevice.current.userInterfaceIdiom == .pad
                && geo.size.width > geo.size.height
            let mainTabBarBottomSpacing: CGFloat = isPadLandscapeWindow
                ? max(geo.safeAreaInsets.bottom, 16)
                : 6
            let mainTabBarExtraBottomReserve = isPadLandscapeWindow
                ? max(mainTabBarBottomSpacing - 6, 0)
                : 0
            let horizontalPadding: CGFloat = usesPadLayout ? 30 : 20
            let topLayoutSafeInset: CGFloat = 0
            let layoutLift: CGFloat = -30
            let widthLimitedContent = geo.size.width - (horizontalPadding * 2)
            let heightLimitedContent = geo.size.height
                - max(topLayoutSafeInset, 0)
                - max(geo.safeAreaInsets.bottom, 0)
                - (usesPadLayout ? 250 : 0)
                - mainTabBarExtraBottomReserve
            let contentWidth = usesPadLayout
                ? max(300, min(widthLimitedContent, heightLimitedContent))
                : min(353, widthLimitedContent)

            ZStack(alignment: .top) {
                conciseSurfaceColor
                    .ignoresSafeArea()

                homeThemeBackgroundTint
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if selectedMainTab == .home && isEditActionsExpanded {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isEditActionsExpanded = false
                            }
                        }
                }

                if selectedMainTab == .home {
                    VStack(spacing: 0) {
                    HomeHeaderView(
                        pointsAnimationStore: pointsAnimationStore,
                        isPadLayout: isPadLayout,
                        availablePoints: availablePoints,
                        showsLimitedOffer: shouldShowLimitedOfferEntry,
                        limitedTimeOfferDuration: limitedTimeOfferConfig.offerDuration,
                        limitedTimeOfferCampaignID: limitedTimeOfferConfig.campaignID,
                        themeColor: activeThemeColor,
                        onOpenThemePicker: {
                            DiagnosticLogStore.recordUserAction(
                                "home_header.theme_picker",
                                details: diagnosticHomeStateDetails(source: "home_header")
                            )
                            selectedStickerID = nil
                            isThemePickerSheetPresented = true
                        },
                        onOpenPointsFlow: {
                            DiagnosticLogStore.recordUserAction(
                                "home_header.points_flow",
                                details: diagnosticHomeStateDetails(source: "home_header")
                            )
                            selectedStickerID = nil
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                pointsEntryFromBottomTab = false
                                selectedMainTab = .points
                            }
                        },
                        onOpenLimitedOffer: {
                            DiagnosticLogStore.recordUserAction(
                                "home_header.limited_offer",
                                details: diagnosticHomeStateDetails(source: "home_header")
                            )
                            selectedStickerID = nil
                            presentLimitedTimeDiscount()
                        }
                    )
                        .frame(width: contentWidth)
                        .padding(.top, max(topLayoutSafeInset, 0) + 12)

                    HomeBoardMainContent(
                        viewModel: viewModel,
                        boardSwitchAnimationStore: boardSwitchAnimationStore,
                        namedBoards: namedBoards,
                        selectedBoardID: selectedBoardID,
                        contentWidth: contentWidth,
                        usesPadLayout: usesPadLayout,
                        isPadLayout: isPadLayout,
                        currentTime: countdownNow,
                        shouldShowCenterLongPressHint: firstStepGuideState == .finished,
                        shouldShowBoardEditHint: shouldShowBoardEditHint,
                        shouldReserveBoardEditHintSpace: shouldReserveBoardEditHintSpace,
                        countdownText: boardCountdownText,
                        isEditActionsExpanded: isEditActionsExpanded,
                        surfaceShadowColor: activeTheme.bingoSurfaceShadowColor,
                        themeColor: activeThemeColor,
                        boardSwipeBlockingState: boardSwipeBlockingState,
                        onSelectBoard: selectBoard,
                        onBoardLongPress: beginBoardActions,
                        onCreateBoard: beginCreateBoard,
                        onDismissBoardEditHint: dismissBoardEditHint,
                        onCellCompletionToggled: {
                            commitCellCompletionSnapshot()
                            selectedStickerID = nil
                            reconcileRedemptionsIfPointsInsufficient()
                        },
                        onCountdown: {
                            DiagnosticLogStore.recordUserAction(
                                "board_header.countdown",
                                details: diagnosticHomeStateDetails(source: "board_header")
                            )
                            selectedStickerID = nil
                            isBoardCountdownPresented = true
                        },
                        onEditActionsToggle: {
                            DiagnosticLogStore.recordUserAction(
                                "board_header.edit_actions_toggle",
                                details: diagnosticHomeStateDetails(source: "board_header")
                            )
                            selectedStickerID = nil
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isEditActionsExpanded.toggle()
                            }
                        },
                        onDismissEditActions: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isEditActionsExpanded = false
                            }
                        },
                        onBoardRules: {
                            guard let boardID = selectedBoardID ?? namedBoards.first?.id else {
                                DiagnosticLogStore.recordWarning(
                                    "edit_actions.board_rules_missing_board",
                                    details: diagnosticHomeStateDetails(source: "edit_actions")
                                )
                                return
                            }
                            selectedStickerID = nil
                            beginBoardRules(for: boardID, source: "edit_actions")
                        },
                        onShuffle: {
                            DiagnosticLogStore.recordUserAction(
                                "edit_actions.shuffle",
                                details: diagnosticHomeStateDetails(source: "edit_actions")
                            )
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                viewModel.shuffleBoard()
                            }
                        },
                        onClearBoard: {
                            DiagnosticLogStore.recordUserAction(
                                "edit_actions.clear_board",
                                details: diagnosticHomeStateDetails(source: "edit_actions")
                            )
                            isClearBoardConfirmationPresented = true
                        },
                        onGridSize: {
                            DiagnosticLogStore.recordUserAction(
                                "edit_actions.grid_size",
                                details: diagnosticHomeStateDetails(source: "edit_actions")
                            )
                            isGridSizeSheetPresented = true
                        },
                        onQuickEdit: {
                            DiagnosticLogStore.recordUserAction(
                                "board_header.quick_edit",
                                details: diagnosticHomeStateDetails(source: "board_header")
                            )
                            selectedStickerID = nil
                            isQuickEditPresented = true
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isEditActionsExpanded else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEditActionsExpanded = false
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -layoutLift)

                    HomeStickerLayer(
                    pointsFeatureStore: pointsFeatureStore,
                    selectedStickerID: $selectedStickerID,
                    canvasSize: geo.size
                )

                    HomeFeedbackLayer(
                    viewModel: viewModel,
                    toastStore: toastStore,
                    safeAreaTop: geo.safeAreaInsets.top,
                    contentWidth: contentWidth,
                    isPadLayout: isPadLayout
                )

                    HomePromptLayer(
                    firstStepGuideOverlay: firstStepGuideOverlay,
                    pendingUpdateInfo: pendingUpdateInfo,
                    isUpdatePromptPresented: isUpdatePromptPresented,
                    isAppReviewPromptPresented: isAppReviewPromptPresented,
                    isCustomResetDowngradeAlertPresented: isCustomResetDowngradeAlertPresented,
                    customResetDowngradeBoardNames: customResetDowngradeBoardNames,
                    isPadLayout: isPadLayout,
                    onFirstStepGuideStart: startFirstStepGuide,
                    onFirstStepGuideDismiss: dismissFirstStepGuideOverlay,
                    onUpdateSkip: {
                        dismissUpdatePrompt(markSkipped: true)
                    },
                    onUpdate: openAppStoreForUpdate,
                    onRateApp: requestAppStoreReviewFromPrompt,
                    onOpenFeedbackEmail: openFeedbackEmailFromPrompt,
                    onRejectAppReviewPrompt: rejectAppReviewPrompt,
                    onCloseAppReviewPrompt: closeAppReviewPrompt,
                    onCustomResetDowngradeClose: {
                        isCustomResetDowngradeAlertPresented = false
                        presentPendingAppReviewPromptIfReady()
                    },
                    onCustomResetDowngradeRestore: {
                        isCustomResetDowngradeAlertPresented = false
                        presentPremiumPaywall(source: "custom_reset_time_expired_restore")
                    }
                )

                    HomeBoardActionLayer(
                    boardActionPresentationStore: boardActionPresentationStore,
                    namedBoards: namedBoards,
                    contentWidth: contentWidth,
                    bottomInset: geo.safeAreaInsets.bottom,
                    isPadLayout: isPadLayout,
                    allowsDeletingFirstBoard: subscriptionManager.hasPremiumAccess,
                    onBoardRules: { boardID in
                        beginBoardRules(for: boardID)
                    },
                    onRenameBoard: beginRenameBoard,
                    onDeleteBoard: requestDeleteBoard
                )

                    HomeTimeoutOverlayLayer(
                        viewModel: viewModel,
                    countdownNow: countdownNow,
                    selectedBoardName: selectedBoardName,
                    isPadLayout: isPadLayout,
                    taskTimeoutDelayMinutes: $taskTimeoutDelayMinutes,
                    boardTimeoutDelayMinutes: $boardTimeoutDelayMinutes,
                    timeoutDelayPickerContext: $timeoutDelayPickerContext,
                    timeoutDelayPickerHours: $timeoutDelayPickerHours,
                        timeoutDelayPickerMinutes: $timeoutDelayPickerMinutes,
                        onToast: showCommonTasksToast
                    )
                } else if selectedMainTab == .points {
                    pointsTabContent(bottomInset: geo.safeAreaInsets.bottom)
                } else {
                    meTabContent(bottomInset: geo.safeAreaInsets.bottom)
                }

                if shouldShowMainTabBar {
                    VStack {
                        Spacer()
                        HomeMainTabBarView(
                            selectedTab: Binding(
                                get: { selectedMainTab },
                                set: { tab in
                                    if tab == .points { pointsEntryFromBottomTab = true }
                                    selectedMainTab = tab
                                }
                            ),
                            isPadLayout: isPadLayout
                        )
                        .padding(.bottom, mainTabBarBottomSpacing)
                        .opacity(selectedMainTab == .points ? pointsNavigationOpacity : 1)
                        .allowsHitTesting(selectedMainTab != .points || pointsNavigationOpacity == 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(5)
                }

                if let completionMotion = viewModel.taskCompletionMotion,
                   completionMotion.kind == .bingo {
                    BingoTopCompletionEffect(
                        motion: completionMotion,
                        onFinished: viewModel.dismissTaskCompletionMotion
                    )
                    .zIndex(20)
                }

            }
        }
    }

    private func pointsTabContent(bottomInset: CGFloat) -> some View {
        PointsFlowPresenter(
            isPadLayout: isPadLayout,
            points: availablePoints,
            totalPoints: viewModel.totalPoints,
            pointsFeatureStore: pointsFeatureStore,
            limitedOfferState: limitedOfferStateBinding,
            showsCloseButton: false,
            bottomContentPadding: max(bottomInset, 0) + scaled(116, pad: 136),
            onSubpagePresentationChange: { isPresented in
                isPointsTabSubpagePresented = isPresented
            },
            enteredFromBottomTab: pointsEntryFromBottomTab,
            onNavigationOpacityChange: { pointsNavigationOpacity = $0 },
            onAddStickerToHomeSuccess: {
                selectedStickerID = nil
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    selectedMainTab = .home
                }
            }
        )
    }

    @ViewBuilder
    private func meTabContent(bottomInset: CGFloat) -> some View {
        if isMeSettingsPresented {
            MeSettingsScreen(
                isPadLayout: isPadLayout,
                appShortVersion: appShortVersion,
                iCloudState: iCloudSyncCoordinator.state,
                themeColor: activeThemeColor,
                isICloudSyncEnabled: NativeICloudPreferences.isEnabled,
                isHapticsEnabled: $isHapticsEnabled,
                isSoundEffectsEnabled: $isSoundEffectsEnabled,
                isWidgetGuideExpanded: $isWidgetGuideExpanded,
                onBack: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        isMeSettingsPresented = false
                    }
                },
                onOpenLanguage: openAppSettings,
                onOpenICloud: {
                    isICloudSyncPresented = true
                },
                onSetICloudEnabled: { enabled in
                    Task {
                        await iCloudSyncCoordinator.setEnabled(enabled)
                    }
                },
                onOpenTerms: {
                    openLegalURL("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                },
                onOpenPrivacy: {
                    openLegalURL("https://osmatters.github.io/bingoday-support/privacy")
                },
                onEncourageUs: {
                    DiagnosticLogStore.recordUserAction(
                        "me.settings.encourage_us",
                        details: diagnosticHomeStateDetails(source: "me_settings")
                    )
                    requestAppStoreReviewFromMe(markEntryHidden: false)
                }
            )
            .transition(.opacity)
        } else {
            BingodaysMeScreen(
                isPremiumMember: subscriptionManager.hasPremiumAccess,
                premiumPlanKind: subscriptionManager.currentPlanKind,
                hasReviewedApp: hasRatedAppReviewPrompt,
                streakDays: bingoStreakDays,
                greetingText: MeGreeting.localizedText(at: meGreetingIndex),
                isPadLayout: isPadLayout,
                bottomInset: bottomInset,
                onOpenContact: {
                    DiagnosticLogStore.recordUserAction(
                        "me.contact",
                        details: diagnosticHomeStateDetails(source: "me")
                    )
                    isContactUsPresented = true
                },
                onOpenSettings: {
                    DiagnosticLogStore.recordUserAction(
                        "me.settings",
                        details: diagnosticHomeStateDetails(source: "me")
                    )
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        isMeSettingsPresented = true
                    }
                },
                onLeaveReview: {
                    DiagnosticLogStore.recordUserAction(
                        "me.encourage_us",
                        details: diagnosticHomeStateDetails(source: "me")
                    )
                    requestAppStoreReviewFromMe(markEntryHidden: true)
                },
                onOpenDiary: {
                    DiagnosticLogStore.recordUserAction(
                        "me.diary",
                        details: diagnosticHomeStateDetails(source: "me")
                    )
                    isDiaryPresented = true
                },
                onOpenPremium: {
                    presentPremiumPaywall(source: "me_pro_entry")
                }
            )
            .transition(.opacity)
        }
    }

    private var shouldShowLimitedOfferEntry: Bool {
        LimitedOfferEntryEligibility.shouldShowEntry(
            config: limitedTimeOfferConfig,
            appVersion: appShortVersion,
            hasPremiumAccess: subscriptionManager.hasPremiumAccess,
            hasCompletedEntitlementRefresh: subscriptionManager.hasCompletedEntitlementRefresh,
            hasVisitedPaywallWithoutPurchase: hasVisitedPremiumPaywallWithoutPurchase || AppDebugFlags.forceLimitedOfferEligible,
            hasLegacyExposure: hasLegacyLimitedTimeDiscountExposure,
            startedAt: limitedTimeDiscountStartedAt,
            campaignID: limitedTimeDiscountCampaignID,
            now: countdownNow
        )
    }

    private var hasUnlockedLimitedOfferEntry: Bool {
        LimitedOfferHomeRules.hasUnlockedEntry(
            hasVisitedPaywallWithoutPurchase: hasVisitedPremiumPaywallWithoutPurchase,
            hasLegacyExposure: hasLegacyLimitedTimeDiscountExposure,
            forceEligible: AppDebugFlags.forceLimitedOfferEligible
        )
    }

    private var hasLimitedOfferCountdownExpired: Bool {
        LimitedOfferEntryEligibility.hasCountdownExpired(
            config: limitedTimeOfferConfig,
            startedAt: limitedTimeDiscountStartedAt,
            campaignID: limitedTimeDiscountCampaignID,
            now: countdownNow
        )
    }

    private func clearLimitedOfferEntryIfPremium() {
        applyLimitedOfferHomeState(
            LimitedOfferHomeRules.applyingPremiumAccess(
                to: limitedOfferHomeState,
                hasPremiumAccess: subscriptionManager.hasPremiumAccess
            )
        )
    }

    private func refreshLimitedTimeOfferConfig() async {
        let config = await LimitedTimeOfferRemoteConfigService.fetchOfferConfig()
        await MainActor.run {
            applyLimitedTimeOfferConfig(config)
        }
    }

    private func applyLimitedTimeOfferConfig(_ config: LimitedTimeOfferConfig) {
        resetLimitedOfferStateForDebugIfNeeded()
        migrateLegacyLimitedOfferExposureIfNeeded()
        limitedTimeOfferConfig = config
#if DEBUG
        print(
            "[LimitedOffer] Home config applied",
            "enabledForVersion=\(config.isEnabled(forAppVersion: appShortVersion))",
            "hasPremium=\(subscriptionManager.hasPremiumAccess)",
            "eligible=\(hasUnlockedLimitedOfferEntry)",
            "expired=\(hasLimitedOfferCountdownExpired)",
            "shouldShow=\(shouldShowLimitedOfferEntry)"
        )
#endif
        guard !LimitedOfferHomeRules.shouldDismissPresentedOffer(
            config: config,
            appVersion: appShortVersion,
            hasPremiumAccess: subscriptionManager.hasPremiumAccess
        ) else {
            isLimitedTimeDiscountPresented = false
            return
        }
    }

    private func resetLimitedOfferStateForDebugIfNeeded() {
#if DEBUG
        let shouldReset = AppDebugFlags.consumeLimitedOfferStateResetIfNeeded()
        guard shouldReset else { return }
        applyLimitedOfferHomeState(LimitedOfferHomeRules.applyingDebugReset(
            to: limitedOfferHomeState,
            shouldReset: shouldReset
        ))
#if DEBUG
        print("[LimitedOffer] Debug reset local offer state")
#endif
#endif
    }

    private func migrateLegacyLimitedOfferExposureIfNeeded() {
        applyLimitedOfferHomeState(
            LimitedOfferHomeRules.applyingLegacyExposureMigration(to: limitedOfferHomeState)
        )
    }

    private func syncLimitedTimeOfferCampaignIfNeeded(for config: LimitedTimeOfferConfig) {
        applyLimitedOfferHomeState(
            LimitedOfferHomeRules.applyingCampaignSync(to: limitedOfferHomeState, config: config)
        )
    }

    private var limitedOfferHomeState: LimitedOfferHomeState {
        LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: hasVisitedPremiumPaywallWithoutPurchase,
            hasLegacyExposure: hasLegacyLimitedTimeDiscountExposure,
            startedAt: limitedTimeDiscountStartedAt,
            campaignID: limitedTimeDiscountCampaignID,
            isPresented: isLimitedTimeDiscountPresented
        )
    }

    private var limitedOfferStateBinding: Binding<LimitedOfferHomeState> {
        Binding(
            get: { limitedOfferHomeState },
            set: { applyLimitedOfferHomeState($0) }
        )
    }

    private func applyLimitedOfferHomeState(_ state: LimitedOfferHomeState) {
        guard state != limitedOfferHomeState else { return }
        hasVisitedPremiumPaywallWithoutPurchase = state.hasVisitedPaywallWithoutPurchase
        hasLegacyLimitedTimeDiscountExposure = state.hasLegacyExposure
        limitedTimeDiscountStartedAt = state.startedAt
        limitedTimeDiscountCampaignID = state.campaignID
        isLimitedTimeDiscountPresented = state.isPresented
    }

    private func withPresentationLayers<Content: View>(content: Content) -> some View {
        content
            .modifier(
                HomePrimaryCoversModifier(
                    isQuickEditPresented: $isQuickEditPresented,
                    isPointsFlowPresented: $isPointsFlowPresented,
                    selectedStickerID: $selectedStickerID,
                    isDiaryPresented: $isDiaryPresented,
                    isPremiumPaywallPresented: $isPremiumPaywallPresented,
                    isLimitedTimeDiscountPresented: $isLimitedTimeDiscountPresented,
                    limitedOfferState: limitedOfferStateBinding,
                    viewModel: viewModel,
                    pointsFeatureStore: pointsFeatureStore,
                    isPadLayout: isPadLayout,
                    availablePoints: availablePoints,
                    totalPoints: viewModel.totalPoints,
                    premiumPaywallSource: premiumPaywallSource,
                    limitedTimeOfferConfig: limitedTimeOfferConfig,
                    boardCompletionAnimationID: viewModel.boardCompletionAnimationID,
                    boardCompletionBoardName: selectedBoardName,
                    onQuickEditSuccess: showCommonTasksToast,
                    onQuickEditBoardApplied: syncSelectedBoardSnapshotIfNeeded,
                    onPremiumPaywallDismiss: handlePremiumPaywallDismiss,
                    onBoardCompletionDismiss: handleBoardCompletionAnimationFinished
                )
            )
            .modifier(
                HomeSheetsModifier(
                    isContactUsPresented: $isContactUsPresented,
                    isContactUsCopyToastVisible: $toastStore.isContactUsCopyVisible,
                    isBoardCountdownPresented: $isBoardCountdownPresented,
                    isBoardRulesPresented: $isBoardRulesPresented,
                    boardRulesTargetBoardID: $boardRulesTargetBoardID,
                    isGridSizeSheetPresented: $isGridSizeSheetPresented,
                    namedBoards: namedBoards,
                    restoredBoardRulesDraft: restoredBoardRulesDraft,
                    hasPremiumAccess: subscriptionManager.hasPremiumAccess,
                    boardCountdownEndsAt: viewModel.boardCountdownEndsAt,
                    isPadLayout: isPadLayout,
                    onCopyEmail: showContactUsCopyToast,
                    onOpenBugReportEmail: {
                        openFeedbackEmail(kind: .bugReport, source: "contact_sheet")
                    },
                    onOpenFeatureSuggestionEmail: {
                        openFeedbackEmail(kind: .featureSuggestion, source: "contact_sheet")
                    },
                    onSaveBoardCountdown: { totalMinutes in
                        viewModel.setBoardCountdown(totalMinutes: totalMinutes)
                        isBoardCountdownPresented = false
                    },
                    onCancelBoardCountdown: {
                        isBoardCountdownPresented = false
                    },
                    onBoardRulesPremiumRequired: { draft in
                        pendingPremiumBoardRulesDraft = draft
                        restoredBoardRulesDraft = nil
                        if subscriptionManager.hasPremiumAccess {
                            restorePendingPremiumBoardRulesDraftIfNeeded()
                        } else {
                            presentPremiumPaywall(source: "board_rules_custom_reset_time")
                        }
                    },
                    onBoardRulesDismissed: {
                        restoredBoardRulesDraft = nil
                    },
                    onApplyBoardRulesSettings: { boardID, countdownMinutes, resetMode, customResetMinutes in
                        applyBoardRulesSettings(
                            for: boardID,
                            countdownMinutes: countdownMinutes,
                            resetMode: resetMode,
                            customResetMinutes: customResetMinutes
                        )
                    },
                    gridSizeSheet: {
                        AnyView(
                            HomeGridSizeSheet(
                                gridSize: viewModel.gridSize,
                                isPadLayout: isPadLayout,
                                onDecrease: {
                                    DiagnosticLogStore.recordUserAction(
                                        "grid_size.decrease",
                                        details: diagnosticHomeStateDetails(source: "grid_size_sheet")
                                            .merging([
                                                "current_grid_size": "\(viewModel.gridSize)",
                                                "target_grid_size": "\(viewModel.gridSize - 1)"
                                            ]) { current, _ in current }
                                    )
                                    withAnimation(.spring(response: 0.4)) {
                                        viewModel.resizeGrid(to: viewModel.gridSize - 1)
                                    }
                                    DiagnosticLogStore.recordStateChange(
                                        "grid_size.resized",
                                        details: [
                                            "source": "grid_size_sheet",
                                            "target_grid_size": "\(viewModel.gridSize)"
                                        ]
                                    )
                                },
                                onIncrease: {
                                    withAnimation(.spring(response: 0.4)) {
                                        resizeGridWithPremiumGate(
                                            targetSize: viewModel.gridSize + 1,
                                            source: "grid_size_sheet"
                                        )
                                    }
                                }
                            )
                        )
                    }
                )
            )
    }

    private func withBoardAlerts<Content: View>(content: Content) -> some View {
        content
            .modifier(
                HomeBoardAlertsModifier(
                    isCreateBoardAlertPresented: $boardActionPresentationStore.isCreateAlertPresented,
                    createBoardNameDraft: $boardActionPresentationStore.createNameDraft,
                    isRenameBoardAlertPresented: $boardActionPresentationStore.isRenameAlertPresented,
                    renameBoardNameDraft: $boardActionPresentationStore.renameNameDraft,
                    boardPendingRenameID: $boardActionPresentationStore.pendingRenameID,
                    isBoardDeleteAlertPresented: $boardActionPresentationStore.isDeleteAlertPresented,
                    pendingBoardDeleteID: $boardActionPresentationStore.pendingDeleteID,
                    isClearBoardConfirmationPresented: $isClearBoardConfirmationPresented,
                    pendingBoardDeleteMessage: pendingBoardDeleteMessage,
                    onCreateBoard: createBoard,
                    onRenameBoard: renameBoard,
                    onDeleteBoard: deleteBoard,
                    onClearBoard: clearBoardFromAlert
                )
            )
    }

    private func clearBoardFromAlert() {
        DiagnosticLogStore.recordUserAction(
            "board.clear_confirm",
            details: diagnosticHomeStateDetails(source: "clear_board_alert")
        )
        viewModel.resetBoard()
        syncTaskStartReminders()
        DiagnosticLogStore.recordStateChange(
            "board.cleared",
            details: [
                "selected_board_id": shortDiagnosticID(selectedBoardID),
                "grid_size": "\(viewModel.gridSize)"
            ]
        )
        showCommonTasksToast(L10n.boardClearedSuccess)
    }

    private func withStateObservers<Content: View>(content: Content) -> some View {
        let baseContent = AnyView(content)
        let lifecycleObserved = withLifecycleObservers(content: baseContent)
        let presentationObserved = withPresentationStateObservers(content: lifecycleObserved)
        let boardObserved = withBoardStateObservers(content: presentationObserved)
        return withPointsAndTimeoutObservers(content: boardObserved)
    }

    private func withLifecycleObservers(content: AnyView) -> AnyView {
        AnyView(
            content
                .modifier(
                    HomeLifecycleObserversModifier(
                        hasCheckedAppUpdateOnLaunch: $hasCheckedAppUpdateOnLaunch,
                        hasStartedDeferredHomePreloads: $hasStartedDeferredHomePreloads,
                        hasStartedDeferredSubscriptionRefresh: $hasStartedDeferredSubscriptionRefresh,
                        scenePhase: scenePhase,
                        onProcessLifecycleEvents: processHomeLifecycleEvents,
                        onCheckAppUpdate: checkForAppUpdateIfNeeded,
                        onRefreshLimitedTimeOfferConfig: refreshLimitedTimeOfferConfig,
                        onRefreshAllSubscriptions: subscriptionManager.refreshAll,
                        onRefreshEntitlements: subscriptionManager.refreshEntitlements,
                        onEnforceCustomResetAccess: enforceCustomResetAccessIfNeeded
                    )
                )
        )
    }

    // Shared catch-up pass for launch and foreground return; it coordinates board reset,
    // guide progress, timeout processing, and debug logging in one place.
    private func processHomeLifecycleEvents(
        now: Date,
        force: Bool,
        source: String,
        shouldApplyForegroundCleanup: Bool
    ) {
        let plan = homeLifecycleWorkStore.catchUpPlan(
            now: now,
            force: force,
            source: source,
            shouldApplyForegroundCleanup: shouldApplyForegroundCleanup,
            simulateNextDayBoardRuleReset: AppDebugFlags.simulateNextDayBoardRuleReset
        )
        performHomeLifecycleWorkPlan(plan)
    }

    private func performHomeLifecycleWorkPlan(_ plan: HomeLifecycleWorkPlan) {
        for step in plan.steps {
            performHomeLifecycleWorkStep(step, context: plan.context)
        }
    }

    private func performHomeLifecycleWorkStep(
        _ step: HomeLifecycleWorkStep,
        context: HomeLifecycleWorkContext
    ) {
        switch step {
        case .loadPointsAfterFirstFrame:
            pointsFeatureStore.loadAfterFirstFrameIfNeeded()
        case .ensureBoardSwitcherLoaded:
            ensureBoardSwitcherLoaded()
        case .reloadBoardSwitcherSnapshotFromSharedStore:
            reloadBoardSwitcherSnapshotFromSharedStoreIfNeeded(now: context.now)
        case .handleBoardResetLifecycle:
            handleBoardResetLifecycle(
                now: context.now,
                force: context.force,
                source: context.source,
                shouldApplyForegroundCleanup: context.shouldApplyForegroundCleanup
            )
        case .forceApplyDebugBoardReset:
            forceApplyBoardTaskResetRulesForDebug(now: context.now)
        case .evaluateFirstStepGuideEntry:
            evaluateFirstStepGuideEntryIfNeeded()
        case .updateCountdownClock:
            countdownNow = context.now
        case .processTimeoutWork:
            processHomeTimeoutWork(now: context.now, refreshVisibilityWindows: false)
        case .syncTaskStartReminders:
            syncTaskStartReminders()
        case .evaluateAppReviewPromptOpportunity:
            evaluateAppReviewPromptOpportunity()
        case .debugTileGestureBlockers:
            debugTileGestureBlockers(source: context.source)
        case .refreshCountdownTickSchedule:
            refreshCountdownTickSchedule(now: context.now)
        }
    }

    private func withPresentationStateObservers(content: AnyView) -> AnyView {
        AnyView(
            content
                .modifier(
                    HomePresentationStateObserversModifier(
                        isEditActionsExpanded: $isEditActionsExpanded,
                        boardRulesTargetBoardID: $boardRulesTargetBoardID,
                        isQuickEditPresented: isQuickEditPresented,
                        isBoardCountdownPresented: isBoardCountdownPresented,
                        isBoardRulesPresented: isBoardRulesPresented,
                        isGridSizeSheetPresented: isGridSizeSheetPresented,
                        isSidebarPresented: isSidebarPresented,
                        firstStepGuideOverlay: firstStepGuideOverlay,
                        isUpdatePromptPresented: isUpdatePromptPresented,
                        boardActionSheetBoardID: boardActionPresentationStore.actionSheetBoardID,
                        onDebugTileGestureBlockers: debugTileGestureBlockers
                    )
                )
        )
    }

    private func withBoardStateObservers(content: AnyView) -> AnyView {
        AnyView(
            content
                .modifier(
                    HomeBoardStateObserversModifier(
                        cells: viewModel.cells,
                        gridSize: viewModel.gridSize,
                        completedLines: viewModel.completedLines,
                        boardCountdownEndsAt: viewModel.boardCountdownEndsAt,
                        hasCompletedEntitlementRefresh: subscriptionManager.hasCompletedEntitlementRefresh,
                        hasPremiumAccess: subscriptionManager.hasPremiumAccess,
                        onSyncSelectedBoardSnapshot: syncSelectedBoardSnapshotAfterBoardStateChange,
                        onEvaluateFirstStepGuideProgress: evaluateFirstStepGuideProgressIfNeeded,
                        onEvaluateAppReviewPromptOpportunity: scheduleAppReviewPromptEvaluation,
                        onReconcileStickerOwnership: reconcileRedemptionsIfPointsInsufficient,
                        onEnforceCustomResetAccess: enforceCustomResetAccessIfNeeded
                    )
                )
        )
    }

    private func withPointsAndTimeoutObservers(content: AnyView) -> AnyView {
        AnyView(
            content
                .modifier(
                    HomePointsAndTimeoutObserversModifier(
                        totalPoints: viewModel.totalPoints,
                        availablePoints: availablePoints,
                        dailyResetNoticeID: viewModel.dailyResetNoticeID,
                        countdownTicker: countdownTicker,
                        expiredTaskEventID: viewModel.expiredTaskEvent?.id,
                        expiredBoardCountdownEventID: viewModel.expiredBoardCountdownEvent?.id,
                        onReconcileStickerOwnership: reconcileRedemptionsIfPointsInsufficient,
                        onAvailablePointsChange: { oldValue, newValue in
                            DiagnosticLogStore.recordStateChange(
                                "points.available_changed",
                                details: [
                                    "old_available": "\(oldValue)",
                                    "new_available": "\(newValue)",
                                    "total": "\(viewModel.totalPoints)",
                                    "derived_spent": "\(max(viewModel.totalPoints - newValue, 0))"
                                ]
                            )
                            // A Bingo has a dedicated celebration track. Keep the normal point
                            // chime for ordinary task completion, but never layer it before the
                            // single-line or full-board Bingo sound begins.
                            let isBingoCelebration = viewModel.taskCompletionMotion?.kind == .bingo
                                || viewModel.showBoardCompletionAnimation
                            pointsAnimationStore.handleAvailablePointsChange(
                                from: oldValue,
                                to: newValue,
                                playsSoundEffect: !isBingoCelebration
                            )
                        },
                        onShowDailyReset: toastStore.showDailyReset,
                        onTick: handleCountdownTick,
                        onExpiredTaskEventChange: resetTaskTimeoutDelayPicker,
                        onExpiredBoardCountdownEventChange: resetBoardTimeoutDelayPicker
                    )
                )
        )
    }

    private func handleCountdownTick(now: Date) {
        let shouldRunMaintenance = shouldRunCountdownTickMaintenance(now: now)
        guard let plan = homeTimeoutWorkStore.tickPlan(
            now: now,
            shouldRunMaintenance: shouldRunMaintenance,
            requiresLiveCountdownTicks: viewModel.requiresLiveCountdownTicks(now: now),
            hasTimeoutDelayPicker: timeoutDelayPickerContext != nil
        ) else {
            return
        }
        performHomeTimeoutWorkPlan(plan)
    }

    private func performHomeTimeoutWorkPlan(_ plan: HomeTimeoutWorkPlan) {
        for step in plan.steps {
            performHomeTimeoutWorkStep(step, context: plan.context)
        }
    }

    private func performHomeTimeoutWorkStep(
        _ step: HomeTimeoutWorkStep,
        context: HomeTimeoutWorkContext
    ) {
        switch step {
        case .updateCountdownClock:
            countdownNow = context.now
        case .handleBoardResetLifecycle:
            handleBoardResetLifecycle(now: context.now, source: "ticker")
        case .processTimeoutWork(let refreshVisibilityWindows):
            processHomeTimeoutWork(
                now: context.now,
                refreshVisibilityWindows: refreshVisibilityWindows
            )
        case .refreshCountdownTickSchedule:
            refreshCountdownTickSchedule(now: context.now)
        }
    }

    private func processHomeTimeoutWork(now: Date, refreshVisibilityWindows: Bool) {
        if refreshVisibilityWindows {
            _ = viewModel.refreshVisibilityWindowsIfNeeded(now: now)
        }
        viewModel.processExpiredCountdowns(now: now)
        viewModel.processExpiredTaskCountdowns(now: now)
        viewModel.processScheduledTaskReplacementConflicts(now: now)
        processExpiredTimeoutsOnOtherBoards(now: now)
    }

    private func shouldRunCountdownTickMaintenance(now: Date) -> Bool {
        homeTimeoutWorkStore.shouldRunMaintenance(
            now: now,
            hasComputedSchedule: hasComputedCountdownTickSchedule,
            nextWorkDate: nextCountdownTickWorkDate
        )
    }

    private func refreshCountdownTickSchedule(now: Date) {
        nextCountdownTickWorkDate = homeTimeoutWorkStore.nextCountdownTickWorkDate(
            after: now,
            activeBoardNextUpdateDate: viewModel.nextTimeSensitiveUpdateDate(now: now),
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            lastBoardRulesEvaluationDateKey: lastBoardRulesEvaluationDateKey,
            hasAppliedDebugSimulatedResetThisLaunch: hasAppliedDebugSimulatedResetThisLaunch,
            simulateNextDayBoardRuleReset: AppDebugFlags.simulateNextDayBoardRuleReset
        )
        hasComputedCountdownTickSchedule = true
    }

    private func invalidateCountdownTickSchedule() {
        nextCountdownTickWorkDate = nil
        hasComputedCountdownTickSchedule = false
    }

    private func resetTaskTimeoutDelayPicker() {
        taskTimeoutDelayMinutes = 10
        timeoutDelayPickerContext = nil
    }

    private func resetBoardTimeoutDelayPicker() {
        boardTimeoutDelayMinutes = 10
        timeoutDelayPickerContext = nil
    }

    @MainActor
    private func checkForAppUpdateIfNeeded() async {
        if let cachedInfo = AppUpdateService.cachedUpdateInfo(currentVersion: appShortVersion),
           (AppDebugFlags.forceUpdatePrompt || cachedInfo.latestVersion != skippedUpdateVersion),
           (AppDebugFlags.forceUpdatePrompt || cachedInfo.latestVersion != lastPromptedUpdateVersion) {
            presentUpdatePrompt(with: cachedInfo)
        }

        if let info = await AppUpdateService.fetchUpdateInfo(currentVersion: appShortVersion) {
            if !AppDebugFlags.forceUpdatePrompt && info.latestVersion == skippedUpdateVersion {
                return
            }
            if !AppDebugFlags.forceUpdatePrompt && info.latestVersion == lastPromptedUpdateVersion {
                return
            }
            presentUpdatePrompt(with: info)
            return
        }

#if DEBUG
        if AppDebugFlags.forceUpdatePrompt {
            presentUpdatePrompt(with: AppUpdateService.debugMockUpdateInfo(currentVersion: appShortVersion))
        }
#endif
    }

    private func presentUpdatePrompt(with info: AppUpdateInfo) {
        pendingUpdateInfo = info
        lastPromptedUpdateVersion = info.latestVersion
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isUpdatePromptPresented = true
        }
    }

    private func dismissUpdatePrompt(markSkipped: Bool = false) {
        if markSkipped, let latestVersion = pendingUpdateInfo?.latestVersion, !latestVersion.isEmpty {
            skippedUpdateVersion = latestVersion
        }
        withAnimation(.easeOut(duration: 0.2)) {
            isUpdatePromptPresented = false
        }
        presentPendingAppReviewPromptIfReady()
    }

    private func evaluateFirstStepGuideEntryIfNeeded() {
        guard let nextState = FirstStepGuideStore.introState(
            state: firstStepGuideState,
            currentOverlay: firstStepGuideOverlay,
            milestoneShown: firstStepGuideMilestoneShown,
            hasTaskPoolTasks: !viewModel.currentTaskPoolTasks().isEmpty
        ) else { return }

        applyFirstStepGuideState(nextState)
    }

    private func startFirstStepGuide() {
        ensureBoardSwitcherLoaded()
        guard boardManagementStore.markSelectedBoardAsStarterGuide() else {
            showCommonTasksToast(
                L10n.tr(
                    "Could not start the guide. Please try again.",
                    zhHans: "新手引导启动失败，请重试。",
                    zhHant: "新手引導啟動失敗，請重試。",
                    ja: "ガイドを開始できませんでした。もう一度お試しください。"
                )
            )
            return
        }
        FirstStepGuideStore.installSeedTasks(in: viewModel)
        applyFirstStepGuideState(FirstStepGuideStore.startedState)
    }

    private func skipFirstStepGuide() {
        applyFirstStepGuideState(FirstStepGuideStore.skippedState)
    }

    private func evaluateFirstStepGuideProgressIfNeeded() {
        let completedCount = FirstStepGuideStore.completedTaskCount(in: viewModel.cells)
        guard let nextState = FirstStepGuideStore.progressState(
            completedCount: completedCount,
            state: firstStepGuideState,
            currentOverlay: firstStepGuideOverlay,
            milestoneShown: firstStepGuideMilestoneShown
        ) else { return }

        applyFirstStepGuideState(nextState)
    }

    private func dismissFirstStepGuideOverlay() {
        applyFirstStepGuideState(
            FirstStepGuideStore.dismissedState(
                state: firstStepGuideState,
                milestoneShown: firstStepGuideMilestoneShown,
                overlay: firstStepGuideOverlay
            )
        )
    }

    private func applyFirstStepGuideState(_ nextState: FirstStepGuideStore.StorageState) {
        if nextState.overlay == .intro {
            FirstStepGuideDeviceStateStore.markGuideShownOnThisDevice()
        }
        firstStepGuideStateRawValue = nextState.state.rawValue
        firstStepGuideMilestoneShown = nextState.milestoneShown
        firstStepGuideOverlay = nextState.overlay
        if nextState.overlay == nil {
            presentPendingAppReviewPromptIfReady()
        }
    }

    private func openAppStoreForUpdate() {
        guard let info = pendingUpdateInfo else { return }
        dismissUpdatePrompt()
        openURL(info.trackViewURL) { accepted in
            if !accepted {
                showCommonTasksToast(L10n.updateStoreOpenFailed)
            }
        }
    }

    private func handleBoardCompletionAnimationFinished(animationID: UUID) {
        guard viewModel.dismissBoardCompletionAnimation(id: animationID) else { return }
        evaluateAppReviewPromptOpportunity(trigger: .secondFullBoard)
    }

    private func scheduleAppReviewPromptEvaluation(trigger: AppReviewPromptCandidate) {
        appReviewEvaluationStore.scheduleEvaluation(
            trigger: trigger,
            boardID: selectedBoardID ?? namedBoards.first?.id,
            currentBoardID: { selectedBoardID ?? namedBoards.first?.id }
        ) { trigger in
            evaluateAppReviewPromptOpportunity(trigger: trigger)
        }
    }

    private func evaluateAppReviewPromptOpportunity(trigger: AppReviewPromptCandidate? = nil) {
        if let candidate = appReviewPromptCandidate(for: trigger) {
            pendingAppReviewPromptCandidate = candidate
        }
        presentPendingAppReviewPromptIfReady()
    }

    private func appReviewPromptCandidate(for trigger: AppReviewPromptCandidate?) -> AppReviewPromptCandidate? {
        let now = Date()
        return homeAppReviewPromptStore.candidate(
            trigger: trigger,
            state: AppReviewPromptEvaluationState(
                now: now,
                todayKey: appReviewDayKey(for: now),
                forceDebugPrompt: AppDebugFlags.forceAppReviewPrompt,
                hasPresentedDebugPromptThisLaunch: hasPresentedDebugAppReviewPromptThisLaunch,
                hasRatedPrompt: hasRatedAppReviewPrompt,
                lifetimeShownCount: appReviewPromptLifetimeShownCount,
                cooldownUntil: appReviewPromptCooldownUntil,
                stage: appReviewPromptStage,
                lastShownDay: appReviewPromptLastShownDay,
                completedLineCount: currentCompletedLineCount,
                isBoardFullyCompleted: isCurrentBoardFullyCompleted,
                consecutiveTaskCompletionDays: BingoDiaryStore.consecutiveTaskCompletionDays()
            )
        )
    }

    private func presentPendingAppReviewPromptIfReady() {
        guard let candidate = pendingAppReviewPromptCandidate,
              canPresentAppReviewPrompt(candidate: candidate) else {
            return
        }

        pendingAppReviewPromptCandidate = nil
        if let stage = candidate.stageToRecord {
            appReviewPromptStage = max(appReviewPromptStage, stage)
            appReviewPromptLifetimeShownCount += 1
            appReviewPromptLastShownDay = appReviewDayKey()
        }
#if DEBUG
        if candidate == .debug {
            hasPresentedDebugAppReviewPromptThisLaunch = true
        }
#endif

        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isAppReviewPromptPresented = true
        }
    }

    private func canPresentAppReviewPrompt(candidate: AppReviewPromptCandidate) -> Bool {
#if DEBUG
        let debugBypassesBlockers = true
#else
        let debugBypassesBlockers = false
#endif
        return homeAppReviewPromptStore.canPresent(
            candidate: candidate,
            state: AppReviewPromptPresentationState(
                isPromptPresented: isAppReviewPromptPresented,
                debugBypassesBlockers: debugBypassesBlockers,
                hasFirstStepGuideOverlay: firstStepGuideOverlay != nil,
                isUpdatePromptPresented: isUpdatePromptPresented,
                isCustomResetDowngradeAlertPresented: isCustomResetDowngradeAlertPresented,
                isSidebarPresented: isSidebarPresented,
                isQuickEditPresented: isQuickEditPresented,
                isContactUsPresented: isContactUsPresented,
                isPointsFlowPresented: isPointsFlowPresented,
                isBoardCountdownPresented: isBoardCountdownPresented,
                isBoardRulesPresented: isBoardRulesPresented,
                isGridSizeSheetPresented: isGridSizeSheetPresented,
                isShowingCelebration: viewModel.showCelebration,
                isShowingBoardCompletionAnimation: viewModel.showBoardCompletionAnimation,
                hasBoardActionSheet: boardActionPresentationStore.actionSheetBoardID != nil,
                hasTimeoutDelayPicker: timeoutDelayPickerContext != nil,
                hasExpiredTaskEvent: viewModel.expiredTaskEvent != nil,
                hasExpiredBoardCountdownEvent: viewModel.expiredBoardCountdownEvent != nil,
                hasScheduledTaskReplacementEvent: viewModel.scheduledTaskReplacementEvent != nil
            )
        )
    }

    private func requestAppStoreReviewFromPrompt() {
        DiagnosticLogStore.recordUserAction(
            "app_review_prompt.rate",
            details: diagnosticHomeStateDetails(source: "app_review_prompt")
        )
        hasRatedAppReviewPrompt = true
        dismissAppReviewPrompt(cooldownDays: nil)
        requestReview()
    }

    private func requestAppStoreReviewFromSidebar() {
        DiagnosticLogStore.recordUserAction(
            "app_review.request",
            details: diagnosticHomeStateDetails(source: "sidebar")
        )
        hasRatedAppReviewPrompt = true
        requestReview()
    }

    private func requestAppStoreReviewFromMe(markEntryHidden: Bool) {
        DiagnosticLogStore.recordUserAction(
            "app_review.request",
            details: diagnosticHomeStateDetails(source: "me")
        )
        if markEntryHidden {
            hasRatedAppReviewPrompt = true
        }
        requestReview()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func openLegalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    private func openFeedbackEmailFromPrompt() {
        dismissAppReviewPrompt(cooldownDays: 30)
        openFeedbackEmail(kind: .bugReport, source: "app_review_prompt")
    }

    private func rejectAppReviewPrompt() {
        DiagnosticLogStore.recordUserAction(
            "app_review_prompt.reject",
            details: diagnosticHomeStateDetails(source: "app_review_prompt")
        )
        dismissAppReviewPrompt(cooldownDays: 90)
    }

    private func closeAppReviewPrompt() {
        DiagnosticLogStore.recordUserAction(
            "app_review_prompt.close",
            details: diagnosticHomeStateDetails(source: "app_review_prompt")
        )
        dismissAppReviewPrompt(cooldownDays: 30)
    }

    private func dismissAppReviewPrompt(cooldownDays: Int?) {
        if let cooldownDays {
            appReviewPromptCooldownUntil = Calendar.current
                .date(byAdding: .day, value: cooldownDays, to: Date())?
                .timeIntervalSince1970 ?? Date().timeIntervalSince1970
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            isAppReviewPromptPresented = false
        }
    }

    private var currentCompletedLineCount: Int {
        viewModel.completedLines.count
    }

    private var isCurrentBoardFullyCompleted: Bool {
        let allCells = viewModel.cells.flatMap { $0 }
        return !allCells.isEmpty && allCells.allSatisfy { !$0.isEmpty && $0.isCompleted }
    }

    private func appReviewDayKey(for date: Date = .now) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func openFeedbackEmail(kind: FeedbackEmailKind, source: String) {
        var details = diagnosticHomeStateDetails(source: source)
        details["kind"] = kind.logValue
        DiagnosticLogStore.recordUserAction(
            "feedback_email.open",
            details: details
        )
        guard let url = feedbackMailURL(for: kind) else {
            DiagnosticLogStore.recordWarning(
                "feedback_email.url_failed",
                details: ["source": source, "kind": kind.logValue]
            )
            showCommonTasksToast(L10n.feedbackMailOpenFailed)
            isContactUsPresented = true
            return
        }

        openURL(url) { accepted in
            guard !accepted else {
                DiagnosticLogStore.recordStateChange(
                    "feedback_email.accepted",
                    details: ["source": source, "kind": kind.logValue]
                )
                return
            }
            DispatchQueue.main.async {
                DiagnosticLogStore.recordWarning(
                    "feedback_email.rejected",
                    details: ["source": source, "kind": kind.logValue]
                )
                showCommonTasksToast(L10n.feedbackMailOpenFailed)
                isContactUsPresented = true
            }
        }
    }

    private func feedbackMailURL(for kind: FeedbackEmailKind) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = L10n.contactUsEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: feedbackMailSubject(for: kind)),
            URLQueryItem(name: "body", value: feedbackMailBody(for: kind))
        ]
        return components.url
    }

    private func feedbackMailSubject(for kind: FeedbackEmailKind) -> String {
        switch kind {
        case .bugReport:
            return L10n.appReviewFeedbackEmailSubject
        case .featureSuggestion:
            return L10n.featureSuggestionEmailSubject
        }
    }

    private func feedbackMailBody(for kind: FeedbackEmailKind) -> String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let version = build.isEmpty ? appShortVersion : "\(appShortVersion) (\(build))"
        let system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        switch kind {
        case .bugReport:
            return L10n.appReviewFeedbackEmailBody(
                appVersion: version,
                device: UIDevice.current.model,
                system: system,
                diagnosticLog: DiagnosticLogStore.exportText()
            )
        case .featureSuggestion:
            return L10n.featureSuggestionEmailBody(
                appVersion: version,
                device: UIDevice.current.model,
                system: system
            )
        }
    }

    private func showCommonTasksToast(_ message: String) {
        toastStore.showCommon(message)
    }

    private func showContactUsCopyToast() {
        DiagnosticLogStore.recordUserAction(
            "contact.copy_email",
            details: diagnosticHomeStateDetails(source: "contact_sheet")
        )
        toastStore.showContactUsCopy()
    }

    private func dismissBoardEditHint() {
        hasDismissedBoardEditHintThisLaunch = true
        hasAcknowledgedBoardEditHint = true
    }

    private func markBoardPanelInteracted() {
        if !hasInteractedWithBoardPanel {
            hasInteractedWithBoardPanel = true
        }
    }

    private func beginBoardActions(for boardID: UUID) {
        DiagnosticLogStore.recordUserAction(
            "board.actions",
            details: diagnosticHomeStateDetails(source: "board_panel")
                .merging(["board_id": shortDiagnosticID(boardID)]) { current, _ in current }
        )
        markBoardPanelInteracted()
        focusedEditingResetForBoardActions()
        boardActionPresentationStore.presentActions(for: boardID)
    }

    private func beginBoardRules(for boardID: UUID, source: String = "board_actions") {
        DiagnosticLogStore.recordUserAction(
            "board.rules",
            details: diagnosticHomeStateDetails(source: source)
                .merging(["board_id": shortDiagnosticID(boardID)]) { current, _ in current }
        )
        markBoardPanelInteracted()
        restoredBoardRulesDraft = nil
        boardRulesTargetBoardID = boardID
        isBoardRulesPresented = true
    }

    private func handlePremiumPaywallDismiss() {
        guard premiumPaywallSource == "board_rules_custom_reset_time",
              pendingPremiumBoardRulesDraft != nil else {
            return
        }
        guard subscriptionManager.hasPremiumAccess else {
            pendingPremiumBoardRulesDraft = nil
            return
        }
        restorePendingPremiumBoardRulesDraftIfNeeded()
    }

    private func restorePendingPremiumBoardRulesDraftIfNeeded() {
        guard !isPremiumPaywallPresented,
              !isBoardRulesPresented,
              let pendingDraft = pendingPremiumBoardRulesDraft else {
            return
        }
        let availableBoardIDs = Set(namedBoards.map(\.id))
        guard let draft = BoardRulesPremiumReturnRules.restorableDraft(
            from: pendingDraft,
            hasPremiumAccess: subscriptionManager.hasPremiumAccess,
            availableBoardIDs: availableBoardIDs
        ) else {
            guard subscriptionManager.hasPremiumAccess else { return }
            pendingPremiumBoardRulesDraft = nil
            showCommonTasksToast(
                L10n.tr(
                    "The board is no longer available.",
                    zhHans: "该面板已不存在",
                    zhHant: "該面板已不存在",
                    ja: "このボードは利用できません。"
                )
            )
            return
        }

        pendingPremiumBoardRulesDraft = nil
        restoredBoardRulesDraft = draft
        boardRulesTargetBoardID = draft.boardID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard subscriptionManager.hasPremiumAccess,
                  restoredBoardRulesDraft?.boardID == draft.boardID else {
                return
            }
            isBoardRulesPresented = true
        }
    }

    private func focusedEditingResetForBoardActions() {
        isEditActionsExpanded = false
        selectedStickerID = nil
    }

    private func applyBoardRulesSettings(
        for boardID: UUID,
        countdownMinutes: Int?,
        resetMode: BoardTaskResetMode,
        customResetMinutes: Int?
    ) -> Bool {
        guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else {
            DiagnosticLogStore.recordWarning(
                "board_rules.save_missing_board",
                details: ["board_id": shortDiagnosticID(boardID)]
            )
            showCommonTasksToast(
                L10n.tr(
                    "Failed to save board rules. Please try again.",
                    zhHans: "面板规则保存失败，请重试",
                    zhHant: "面板規則儲存失敗，請重試",
                    ja: "ボードルールを保存できませんでした。もう一度お試しください。"
                )
            )
            return false
        }
        let originalBoard = namedBoards[boardIndex]
        let originalActiveCountdownEndsAt = selectedBoardID == boardID
            ? viewModel.boardCountdownEndsAt
            : nil
        let now = Date()
        let resolvedMinutes = countdownMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }
        let countdownEndsAt = resolvedMinutes.map { now.addingTimeInterval(Double($0 * 60)) }

        let normalizedResetMode: BoardTaskResetMode = (resetMode == .customResetStatusTime) ? .resetStatusNextDay : resetMode
        let normalizedCustomResetMinutes = BoardResetRuleEngine.normalizedCustomResetMinutes(
            customResetMinutes,
            mode: normalizedResetMode
        )
        namedBoards[boardIndex].taskResetMode = normalizedResetMode
        namedBoards[boardIndex].customResetMinutes = normalizedCustomResetMinutes
        namedBoards[boardIndex].countdownEndsAt = countdownEndsAt
        namedBoards[boardIndex].lastTaskResetAppliedAt = BoardRulesSaveRules.resolvedLastResetAppliedAt(
            previousMode: originalBoard.taskResetMode,
            previousCustomResetMinutes: originalBoard.customResetMinutes,
            previousLastResetAppliedAt: originalBoard.lastTaskResetAppliedAt,
            newMode: normalizedResetMode,
            newCustomResetMinutes: normalizedCustomResetMinutes,
            now: now
        )
        namedBoards[boardIndex].updatedAt = now

        if selectedBoardID == boardID {
            viewModel.setBoardCountdown(totalMinutes: resolvedMinutes)
            namedBoards[boardIndex].board = viewModel.makeSavedBoardSnapshot()
            namedBoards[boardIndex].countdownEndsAt = viewModel.boardCountdownEndsAt
        }

        markBoardPanelInteracted()
        let persistenceResult = persistNamedBoardsSnapshot()
        guard persistenceResult.didChangeSnapshot else {
            namedBoards[boardIndex] = originalBoard
            if selectedBoardID == boardID {
                viewModel.setBoardCountdownEndsAt(originalActiveCountdownEndsAt)
            }
            DiagnosticLogStore.recordWarning(
                "board_rules.save_failed",
                details: ["board_id": shortDiagnosticID(boardID)]
            )
            showCommonTasksToast(
                L10n.tr(
                    "Failed to save board rules. Please try again.",
                    zhHans: "面板规则保存失败，请重试",
                    zhHant: "面板規則儲存失敗，請重試",
                    ja: "ボードルールを保存できませんでした。もう一度お試しください。"
                )
            )
            return false
        }
        DiagnosticLogStore.recordStateChange(
            "board_rules.saved",
            details: [
                "board_id": shortDiagnosticID(boardID),
                "has_countdown": "\(resolvedMinutes != nil)",
                "reset_mode": normalizedResetMode.rawValue,
                "has_custom_reset": "\(normalizedCustomResetMinutes != nil)"
            ]
        )
        showCommonTasksToast(L10n.tr("Board rules saved", zhHans: "面板规则已保存", zhHant: "面板規則已儲存"))
        return true
    }

    private func enforceCustomResetAccessIfNeeded() {
        guard subscriptionManager.hasCompletedEntitlementRefresh else { return }
        guard !subscriptionManager.hasPremiumAccess else { return }

        ensureBoardSwitcherLoaded()
        let now = Date()
        var didRevokeCustomResetTime = false
        var revokedBoardNames: [String] = []

        for index in namedBoards.indices {
            let hasCustomReset = BoardResetRuleEngine.normalizedCustomResetMinutes(
                namedBoards[index].customResetMinutes,
                mode: namedBoards[index].taskResetMode
            ) != nil ||
                namedBoards[index].taskResetMode == .customResetStatusTime
            guard hasCustomReset else { continue }

            revokedBoardNames.append(namedBoards[index].name)
            if namedBoards[index].taskResetMode == .customResetStatusTime {
                namedBoards[index].taskResetMode = .resetStatusNextDay
            }
            namedBoards[index].customResetMinutes = nil
            namedBoards[index].updatedAt = now
            didRevokeCustomResetTime = true
        }

        guard didRevokeCustomResetTime else { return }
        persistNamedBoardsSnapshot()
        handleBoardResetLifecycle(
            now: now,
            force: true,
            source: "entitlementDowngrade"
        )
        customResetDowngradeBoardNames = revokedBoardNames
        isCustomResetDowngradeAlertPresented = true
    }

    private func handleBoardResetLifecycle(
        now: Date,
        force: Bool = false,
        source: String,
        shouldApplyForegroundCleanup: Bool = false
    ) {
        if shouldApplyForegroundCleanup {
            viewModel.applyForegroundCleanup()
        }

        let activeBoardID = selectedBoardID ?? namedBoards.first?.id
        let didBoardCountdownExist = activeBoardID
            .flatMap { boardID in
                namedBoards.first(where: { $0.id == boardID })?.countdownEndsAt != nil
            } ?? false

        var coordinator = makeBoardResetCoordinator()
        let result = coordinator.evaluate(now: now, force: force, source: source)
        commitBoardResetCoordinator(coordinator, shouldPersist: result.didReset)

        guard result.didResetActiveBoard else { return }
        refreshActiveBoardAfterReset(
            activeBoardID: activeBoardID,
            now: now,
            didBoardCountdownExist: didBoardCountdownExist,
            clearedCompletedTaskCount: result.clearedCompletedTaskCount
        )
    }

    private func forceApplyBoardTaskResetRulesForDebug(now: Date) {
    #if DEBUG
        let activeBoardID = selectedBoardID ?? namedBoards.first?.id
        let didBoardCountdownExist = activeBoardID
            .flatMap { boardID in
                namedBoards.first(where: { $0.id == boardID })?.countdownEndsAt != nil
            } ?? false

        var coordinator = makeBoardResetCoordinator()
        let result = coordinator.forceApplyForDebug(now: now)
        commitBoardResetCoordinator(coordinator, shouldPersist: result?.didReset == true)

        guard let result, result.didResetActiveBoard else { return }
        refreshActiveBoardAfterReset(
            activeBoardID: activeBoardID,
            now: now,
            didBoardCountdownExist: didBoardCountdownExist,
            clearedCompletedTaskCount: result.clearedCompletedTaskCount
        )
    #else
        _ = now
    #endif
    }

    private func makeBoardResetCoordinator() -> BoardResetCoordinator {
        BoardResetCoordinator(
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            lastEvaluationDateKey: lastBoardRulesEvaluationDateKey,
            hasAppliedDebugSimulatedResetThisLaunch: hasAppliedDebugSimulatedResetThisLaunch,
            lastCustomResetDebugToastKey: lastCustomResetDebugToastKey,
            debugConfiguration: BoardResetDebugConfiguration(
                simulateNextDayReset: AppDebugFlags.simulateNextDayBoardRuleReset,
                prepareStreakTest: AppDebugFlags.prepareStreakTest,
                showCustomResetToast: AppDebugFlags.showCustomResetToast
            )
        )
    }

    private func commitBoardResetCoordinator(_ coordinator: BoardResetCoordinator, shouldPersist: Bool) {
        namedBoards = coordinator.namedBoards
        lastBoardRulesEvaluationDateKey = coordinator.lastEvaluationDateKey
        hasAppliedDebugSimulatedResetThisLaunch = coordinator.hasAppliedDebugSimulatedResetThisLaunch
        lastCustomResetDebugToastKey = coordinator.lastCustomResetDebugToastKey

    #if DEBUG
        for message in coordinator.debugLogs {
            print("[BoardResetDebug] \(message)")
        }
        for message in coordinator.resetDebugToasts {
            showCommonTasksToast("DEBUG reset: \(message)")
        }
        for message in coordinator.customResetDebugToasts {
            showCommonTasksToast(message)
        }
    #endif

        if shouldPersist {
            persistNamedBoardsSnapshot()
        }
    }

    private func refreshActiveBoardAfterReset(
        activeBoardID: UUID?,
        now: Date,
        didBoardCountdownExist: Bool,
        clearedCompletedTaskCount: Int
    ) {
        if let activeBoardID {
            if selectedBoardID == nil {
                selectedBoardID = activeBoardID
            }
            if let selectedBoard = namedBoards.first(where: { $0.id == activeBoardID }) {
                let beforeCompleted = viewModel.cells.flatMap(\.self).filter { $0.isCompleted && !$0.isEmpty }.count
                viewModel.applySavedBoardSnapshot(
                    selectedBoard.board,
                    countdownEndsAt: selectedBoard.countdownEndsAt,
                    referenceDate: now
                )
                let afterCompleted = viewModel.cells.flatMap(\.self).filter { $0.isCompleted && !$0.isEmpty }.count
                #if DEBUG
                print("[BoardResetDebug] ui.refresh boardID=\(activeBoardID.uuidString) beforeCompleted=\(beforeCompleted) afterCompleted=\(afterCompleted)")
                #endif
            } else {
                #if DEBUG
                print("[BoardResetDebug] ui.refresh skipped: missing active board after reset")
                #endif
            }
        } else {
            #if DEBUG
            print("[BoardResetDebug] ui.refresh skipped: no active board id")
            #endif
        }

        viewModel.finalizePostResetState(
            now: now,
            didBoardCountdownExist: didBoardCountdownExist,
            clearedCompletedTaskCount: clearedCompletedTaskCount
        )
    }

    private func debugTileGestureBlockers(source: String) {
        TileGestureDebugLogger.logOverlayBlockers(source: source, state: tileGestureOverlayDebugState)
    }

    private func boardName(for boardID: UUID) -> String {
        guard let board = namedBoards.first(where: { $0.id == boardID }) else {
            return L10n.boardDefaultName(1)
        }
        return board.name
    }

    private func requestDeleteBoard(_ boardID: UUID) {
        DiagnosticLogStore.recordUserAction(
            "board.delete_request",
            details: diagnosticHomeStateDetails(source: "board_actions")
                .merging(["board_id": shortDiagnosticID(boardID)]) { current, _ in current }
        )
        markBoardPanelInteracted()
        switch BoardActionPresentationStore.deleteAvailability(
            for: boardID,
            namedBoards: namedBoards,
            allowsDeletingFirstBoard: subscriptionManager.hasPremiumAccess
        ) {
        case .allowed:
            boardActionPresentationStore.beginDelete(boardID: boardID)
        case .blocked(let message):
            DiagnosticLogStore.recordWarning(
                "board.delete_blocked",
                details: [
                    "board_id": shortDiagnosticID(boardID),
                    "board_count": "\(namedBoards.count)",
                    "has_premium": "\(subscriptionManager.hasPremiumAccess)",
                    "is_first_board": "\(namedBoards.first?.id == boardID)"
                ]
            )
            showCommonTasksToast(message)
        }
    }

    private func deleteBoard(_ boardID: UUID) {
        defer {
            boardActionPresentationStore.clearPendingDelete()
        }

        guard BoardActionPresentationStore.canDeleteBoard(
            boardID,
            namedBoards: namedBoards,
            allowsDeletingFirstBoard: subscriptionManager.hasPremiumAccess
        ) else {
            DiagnosticLogStore.recordWarning(
                "board.delete_guard_failed",
                details: [
                    "board_id": shortDiagnosticID(boardID),
                    "board_count": "\(namedBoards.count)",
                    "has_premium": "\(subscriptionManager.hasPremiumAccess)"
                ]
            )
            return
        }
        markBoardPanelInteracted()

        guard let boardToDelete = namedBoards.first(where: { $0.id == boardID }) else {
            return
        }
        guard TaskHistoryStore.archive(board: boardToDelete.board) else {
            DiagnosticLogStore.recordWarning(
                "board.delete_history_archive_failed",
                details: ["board_id": shortDiagnosticID(boardID)]
            )
            showCommonTasksToast(
                L10n.tr(
                    "Could not save this board's task history. Please try again.",
                    zhHans: "任务历史保存失败，请重试。",
                    zhHant: "任務歷史儲存失敗，請重試。",
                    ja: "タスク履歴を保存できませんでした。もう一度お試しください。"
                )
            )
            return
        }

        guard let deletion = boardManagementStore.deleteBoard(
            boardID,
            allowsDeletingFirstBoard: subscriptionManager.hasPremiumAccess
        ) else {
            DiagnosticLogStore.recordWarning(
                "board.delete_failed",
                details: ["board_id": shortDiagnosticID(boardID)]
            )
            showCommonTasksToast(
                L10n.tr(
                    "Could not delete the board. Please try again.",
                    zhHans: "面板删除失败，请重试。",
                    zhHant: "面板刪除失敗，請重試。",
                    ja: "ボードを削除できませんでした。もう一度お試しください。"
                )
            )
            return
        }

        viewModel.applySavedBoardSnapshot(
            deletion.selectedBoard.board,
            countdownEndsAt: deletion.selectedBoard.countdownEndsAt,
            referenceDate: .now
        )

        applyBoardManagementMutationResult(deletion)
        NativeICloudLocalChangeReporter.primaryStateDidChange()
        DiagnosticLogStore.recordStateChange(
            "board.deleted",
            details: [
                "board_id": shortDiagnosticID(boardID),
                "selected_board_id": shortDiagnosticID(deletion.selectedBoard.id),
                "board_count": "\(namedBoards.count)"
            ]
        )
        showCommonTasksToast(L10n.tr("Board deleted", zhHans: "棋盘已删除", zhHant: "棋盤已刪除"))
    }


    private var pendingBoardDeleteMessage: String {
        let targetBoardName = boardActionPresentationStore.pendingDeleteID.flatMap { boardName(for: $0) } ?? ""
        return BoardActionPresentationStore.pendingDeleteMessage(boardName: targetBoardName)
    }

    private func ensureBoardSwitcherLoaded() {
        let wasAlreadyLoaded = boardManagementStore.hasLoadedBoardSwitcherState
        guard let selectedBoard = boardManagementStore.loadIfNeeded(
            initialBoard: viewModel.makeSavedBoardSnapshot(),
            countdownEndsAt: viewModel.boardCountdownEndsAt
        ) else { return }
        guard !wasAlreadyLoaded else { return }

        viewModel.applySavedBoardSnapshot(
            selectedBoard.board,
            countdownEndsAt: selectedBoard.countdownEndsAt,
            referenceDate: .now,
            reloadPersistedPoints: true
        )
        syncSelectedBoardSnapshotIfNeeded()
    }

    private func reloadBoardSwitcherSnapshotFromSharedStoreIfNeeded(
        now: Date,
        persistViewModelState: Bool = true
    ) {
        guard let selectedBoard = boardManagementStore.reloadPersistedSnapshot() else {
            return
        }

        viewModel.applySavedBoardSnapshot(
            selectedBoard.board,
            countdownEndsAt: selectedBoard.countdownEndsAt,
            referenceDate: now,
            reloadPersistedPoints: true,
            persist: persistViewModelState
        )
    }

    @discardableResult
    private func persistNamedBoardsSnapshot() -> HomeBoardSnapshotSyncResult {
        let result = homeBoardSnapshotSyncStore.persistNamedBoardsSnapshot(
            boardManagementStore: boardManagementStore
        )
        applyBoardSnapshotSyncResult(result)
        return result
    }

    private func persistBoardState(for boardID: UUID, save: Bool = true) {
        boardManagementStore.persistBoardState(
            for: boardID,
            board: viewModel.makeSavedBoardSnapshot(),
            countdownEndsAt: viewModel.boardCountdownEndsAt,
            save: save
        )
    }

    private func syncSelectedBoardSnapshotIfNeeded() {
        syncSelectedBoardSnapshotIfNeeded(syncTaskReminders: true)
    }

    private func syncSelectedBoardSnapshotAfterBoardStateChange(_ change: HomeBoardStateChange) {
        syncSelectedBoardSnapshotIfNeeded(syncTaskReminders: change.affectsTaskReminders)
    }

    private func commitCellCompletionSnapshot() {
        let result = homeBoardSnapshotSyncStore.commitCellCompletionSnapshot(
            boardManagementStore: boardManagementStore,
            board: viewModel.makeSavedBoardSnapshot(),
            countdownEndsAt: viewModel.boardCountdownEndsAt
        )
        applyBoardSnapshotSyncResult(result)
    }

    private func syncSelectedBoardSnapshotIfNeeded(syncTaskReminders: Bool) {
        let result = homeBoardSnapshotSyncStore.syncSelectedBoardSnapshot(
            boardManagementStore: boardManagementStore,
            board: viewModel.makeSavedBoardSnapshot(),
            countdownEndsAt: viewModel.boardCountdownEndsAt,
            syncTaskReminders: syncTaskReminders
        )
        applyBoardSnapshotSyncResult(result)
    }

    private func applyBoardSnapshotSyncResult(_ result: HomeBoardSnapshotSyncResult) {
        applyBoardSideEffects(
            shouldInvalidateCountdownTickSchedule: result.shouldInvalidateCountdownTickSchedule,
            shouldSyncTaskReminders: result.shouldSyncTaskReminders
        )
    }

    private func syncTaskStartReminders() {
        taskStartReminderSyncStore.scheduleSync(
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            activeBoard: viewModel.makeSavedBoardSnapshot()
        )
    }

    private func processExpiredTimeoutsOnOtherBoards(now: Date) {
        guard viewModel.expiredTaskEvent == nil,
              viewModel.expiredBoardCountdownEvent == nil,
              viewModel.scheduledTaskReplacementEvent == nil,
              timeoutDelayPickerContext == nil else {
            return
        }
        guard namedBoards.count > 1 else { return }
        guard let activeBoardID = selectedBoardID ?? namedBoards.first?.id else { return }
        guard let targetBoardID = homeTimeoutWorkStore.nextBoardWithExpiredTimeout(
            in: namedBoards,
            excluding: activeBoardID,
            now: now
        ) else {
            return
        }

        guard let selection = boardManagementStore.selectBoard(
            targetBoardID,
            currentBoard: viewModel.makeSavedBoardSnapshot(),
            currentCountdownEndsAt: viewModel.boardCountdownEndsAt
        ) else {
            return
        }

        viewModel.applySavedBoardSnapshot(
            selection.selectedBoard.board,
            countdownEndsAt: selection.selectedBoard.countdownEndsAt,
            referenceDate: now
        )
        _ = viewModel.refreshVisibilityWindowsIfNeeded(now: now)
        viewModel.processExpiredCountdowns(now: now)
        viewModel.processExpiredTaskCountdowns(now: now)
        applyBoardManagementMutationResult(selection)
    }

    private func selectBoard(_ boardID: UUID) {
        DiagnosticLogStore.recordUserAction(
            "board.select",
            details: diagnosticHomeStateDetails(source: "board_panel")
                .merging(["target_board_id": shortDiagnosticID(boardID)]) { current, _ in current }
        )
        selectedStickerID = nil
        guard selectedBoardID != boardID else {
            DiagnosticLogStore.recordStateChange(
                "board.select_ignored_current",
                details: ["board_id": shortDiagnosticID(boardID)]
            )
            return
        }
        guard boardSwitchAnimationStore.beginSelection() else {
            DiagnosticLogStore.recordWarning(
                "board.select_blocked_animation",
                details: ["board_id": shortDiagnosticID(boardID)]
            )
            return
        }
        markBoardPanelInteracted()

        guard let selection = boardManagementStore.selectBoard(
            boardID,
            currentBoard: viewModel.makeSavedBoardSnapshot(),
            currentCountdownEndsAt: viewModel.boardCountdownEndsAt
        ) else {
            DiagnosticLogStore.recordWarning(
                "board.select_failed",
                details: ["board_id": shortDiagnosticID(boardID)]
            )
            return
        }

        viewModel.applySavedBoardSnapshot(
            selection.selectedBoard.board,
            countdownEndsAt: selection.selectedBoard.countdownEndsAt,
            referenceDate: .now
        )
        applyBoardManagementMutationResult(selection)
        DiagnosticLogStore.recordStateChange(
            "board.selected",
            details: [
                "board_id": shortDiagnosticID(selection.selectedBoard.id),
                "grid_size": "\(viewModel.gridSize)"
            ]
        )
    }

    private func applyBoardManagementMutationResult(_ result: BoardManagementMutationResult) {
        if result.commitResult.failedToSaveBoard {
            DiagnosticLogStore.recordWarning(
                "board.active_mirror_save_failed",
                details: [
                    "selected_board_id": shortDiagnosticID(result.selectedBoard.id),
                    "named_boards_saved": "\(result.commitResult.savedNamedBoards)"
                ]
            )
        }
        applyBoardSideEffects(
            shouldInvalidateCountdownTickSchedule: result.shouldInvalidateCountdownTickSchedule,
            shouldSyncTaskReminders: result.shouldSyncTaskReminders
        )
    }

    private func applyBoardSideEffects(
        shouldInvalidateCountdownTickSchedule: Bool,
        shouldSyncTaskReminders: Bool
    ) {
        if shouldInvalidateCountdownTickSchedule {
            invalidateCountdownTickSchedule()
        }
        if shouldSyncTaskReminders {
            syncTaskStartReminders()
        }
    }

    private func beginCreateBoard() {
        DiagnosticLogStore.recordUserAction(
            "board.create_begin",
            details: diagnosticHomeStateDetails(source: "board_panel")
        )
        selectedStickerID = nil
        markBoardPanelInteracted()
        guard canCreateAdditionalBoard else {
            DiagnosticLogStore.recordWarning(
                "board.create_blocked_limit",
                details: [
                    "board_count": "\(namedBoards.count)",
                    "has_premium": "\(subscriptionManager.hasPremiumAccess)"
                ]
            )
            AnalyticsService.logPremiumBoardsLimitHit(
                currentBoardCount: namedBoards.count,
                source: "boards_limit"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                presentPremiumPaywall(source: "boards_limit")
            }
            return
        }

        boardActionPresentationStore.beginCreate(defaultName: L10n.boardDefaultName(namedBoards.count + 1))
    }

    private func createBoard() {
        guard canCreateAdditionalBoard else {
            DiagnosticLogStore.recordWarning(
                "board.create_guard_failed_limit",
                details: [
                    "board_count": "\(namedBoards.count)",
                    "has_premium": "\(subscriptionManager.hasPremiumAccess)"
                ]
            )
            AnalyticsService.logPremiumBoardsLimitHit(
                currentBoardCount: namedBoards.count,
                source: "boards_limit"
            )
            return
        }
        markBoardPanelInteracted()

        guard let creation = boardManagementStore.createBoard(
            nameDraft: boardActionPresentationStore.createNameDraft,
            currentBoard: viewModel.makeSavedBoardSnapshot(),
            currentCountdownEndsAt: viewModel.boardCountdownEndsAt
        ) else {
            DiagnosticLogStore.recordWarning(
                "board.create_failed",
                details: diagnosticHomeStateDetails(source: "board_create_alert")
            )
            return
        }

        viewModel.applySavedBoardSnapshot(
            creation.selectedBoard.board,
            countdownEndsAt: creation.selectedBoard.countdownEndsAt,
            referenceDate: .now
        )
        applyBoardManagementMutationResult(creation)
        boardActionPresentationStore.clearCreateDraft()
        DiagnosticLogStore.recordStateChange(
            "board.created",
            details: [
                "selected_board_id": shortDiagnosticID(creation.selectedBoard.id),
                "board_count": "\(namedBoards.count)"
            ]
        )
    }

    private func beginRenameSelectedBoard() {
        guard let selectedNamedBoardIndex else {
            DiagnosticLogStore.recordWarning(
                "board.rename_selected_missing",
                details: diagnosticHomeStateDetails(source: "board_panel")
            )
            return
        }
        let board = namedBoards[selectedNamedBoardIndex]
        DiagnosticLogStore.recordUserAction(
            "board.rename_selected_begin",
            details: diagnosticHomeStateDetails(source: "board_panel")
                .merging(["board_id": shortDiagnosticID(board.id)]) { current, _ in current }
        )
        markBoardPanelInteracted()
        boardActionPresentationStore.beginRename(board: board)
    }

    private func beginRenameBoard(_ boardID: UUID) {
        DiagnosticLogStore.recordUserAction(
            "board.rename_begin",
            details: diagnosticHomeStateDetails(source: "board_actions")
                .merging(["board_id": shortDiagnosticID(boardID)]) { current, _ in current }
        )
        guard let board = namedBoards.first(where: { $0.id == boardID }) else {
            DiagnosticLogStore.recordWarning(
                "board.rename_missing_board",
                details: ["board_id": shortDiagnosticID(boardID)]
            )
            return
        }
        markBoardPanelInteracted()
        boardActionPresentationStore.beginRename(board: board)
    }

    private func renameBoard() {
        defer {
            boardActionPresentationStore.clearRenameDraft()
        }

        guard let boardPendingRenameID = boardActionPresentationStore.pendingRenameID else {
            DiagnosticLogStore.recordWarning(
                "board.rename_missing_pending_id",
                details: diagnosticHomeStateDetails(source: "board_rename_alert")
            )
            return
        }

        markBoardPanelInteracted()
        let result = boardManagementStore.renameBoard(
            boardPendingRenameID,
            nameDraft: boardActionPresentationStore.renameNameDraft
        )
        guard result == .renamed else {
            if result == .persistenceFailed {
                DiagnosticLogStore.recordWarning(
                    "board.rename_save_failed",
                    details: ["board_id": shortDiagnosticID(boardPendingRenameID)]
                )
            }
            return
        }
        DiagnosticLogStore.recordStateChange(
            "board.renamed",
            details: ["board_id": shortDiagnosticID(boardPendingRenameID)]
        )
    }

    private var boardCountdownText: String? {
        guard let endsAt = viewModel.boardCountdownEndsAt, endsAt > countdownNow else {
            return nil
        }

        let remainingSeconds = max(Int(endsAt.timeIntervalSince(countdownNow)), 0)
        return Self.compactCountdownText(remainingSeconds: remainingSeconds)
    }

    private static func compactCountdownText(remainingSeconds: Int) -> String {
        let days = remainingSeconds / 86400
        let hours = (remainingSeconds % 86400) / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m \(seconds)s"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func reconcileRedemptionsIfPointsInsufficient() {
        let result = pointsFeatureStore.reconcileRedemptionsIfPointsInsufficient(
            totalPoints: viewModel.totalPoints
        )
        guard result.didChange else {
            return
        }
        showCommonTasksToast(L10n.pointRedemptionsRevokedDueToPoints)

        if let selectedStickerID, !pointsFeatureStore.containsPlacement(id: selectedStickerID) {
            self.selectedStickerID = nil
        }
    }
}
