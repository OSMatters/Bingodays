import SwiftUI
import StoreKit
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct ContentView: View {
    private struct TemplateImportResult {
        let board: BingoBoardStore.NamedBoard
        let successMessage: String
    }

    private enum AppReviewPromptCandidate: Equatable {
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

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var accountSession: AccountSession
    @EnvironmentObject private var boardTemplateImportCoordinator: BoardTemplateImportCoordinator
    @StateObject private var viewModel = BingoViewModel()
    @StateObject private var boardManagementStore = BoardManagementStore()
    @StateObject private var templateImportFlowStore = TemplateImportFlowStore()
    @StateObject private var pointsFeatureStore = PointsFeatureStore()
    @StateObject private var toastStore = HomeToastStore()
    @StateObject private var pointsAnimationStore = PointsAnimationStore()
    @StateObject private var boardActionPresentationStore = BoardActionPresentationStore()
    @StateObject private var boardSwitchAnimationStore = BoardSwitchAnimationStore()
    @State private var isSidebarPresented = false
    @State private var isSettingsExpanded = false
    @State private var isWidgetGuideExpanded = false
    @State private var isThemePickerExpanded = false
    @State private var isPointsFlowPresented = false
    @State private var isBoardCountdownPresented = false
    @State private var isBoardRulesPresented = false
    @State private var boardRulesTargetBoardID: UUID?
    @State private var selectedStickerID: UUID?
    @State private var isDiaryPresented = false
    @State private var isPremiumPaywallPresented = false
    @State private var isLimitedTimeDiscountPresented = false
    @State private var premiumPaywallSource = "unknown"
    @State private var isQuickEditPresented = false
    @State private var isBlackBoxModePresented = false
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
    @State private var boardTemplateShareDraft: BoardTemplatePayload?
    @State private var isTemplateShareComposerPresented = false
    @State private var isCustomResetDowngradeAlertPresented = false
    @State private var customResetDowngradeBoardNames: [String] = []
    @State private var lastBoardRulesEvaluationDateKey = ""
    @State private var hasAppliedDebugSimulatedResetThisLaunch = false
    @State private var lastCustomResetDebugToastKey = ""
    @State private var hasDismissedBoardEditHintThisLaunch = false
    @State private var pendingAppReviewPromptCandidate: AppReviewPromptCandidate?
    @State private var hasPresentedDebugAppReviewPromptThisLaunch = false
    @State private var limitedTimeOfferConfig = LimitedTimeOfferConfig.disabled
    @State private var reminderSyncTask: Task<Void, Never>?
    @State private var lastReminderSyncSignature: String?
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
    @AppStorage(AppSettings.limitedTimeDiscountStartedAtKey) private var limitedTimeDiscountStartedAt = 0.0
    @AppStorage(AppSettings.limitedTimeDiscountCampaignIDKey) private var limitedTimeDiscountCampaignID = ""
    @AppStorage(AppSettings.hasAcknowledgedBoardEditHintKey) private var hasAcknowledgedBoardEditHint = false
    @AppStorage(AppSettings.hasInteractedWithBoardPanelKey) private var hasInteractedWithBoardPanel = false
    private let countdownTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var countdownNow = Date()
    private var bingoStreakDays: Int { BingoDiaryStore.consecutiveBingoDays() }
    private var streakGoals: [Int] { bingoStreakDays >= 60 ? [60, 180, 270, 365] : [7, 14, 30, 60] }
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var activeThemeColor: Color { activeTheme.color }
    private let conciseSurfaceColor = Color(hex: "F4F4F4")
    private var homeThemeBackgroundTint: some View {
        Color(hex: "F4F4F4")
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
    private var shouldImportTemplateAsNewBoard: Bool {
        subscriptionManager.hasPremiumAccess || subscriptionManager.hasActiveAutoRenewable || subscriptionManager.hasLifetimeAccess
    }
    private var boardTemplateImportPreviewDraft: BoardTemplatePayload? {
        get { templateImportFlowStore.previewTemplate }
        nonmutating set { templateImportFlowStore.previewTemplate = newValue }
    }
    private var isTemplateImportPreviewPresented: Bool {
        get { templateImportFlowStore.isPreviewPresented }
        nonmutating set { templateImportFlowStore.isPreviewPresented = newValue }
    }
    private var isTemplateImportPreviewBinding: Binding<Bool> {
        Binding(
            get: { templateImportFlowStore.isPreviewPresented },
            set: { templateImportFlowStore.isPreviewPresented = $0 }
        )
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
            isTemplateImportPreviewPresented: isTemplateImportPreviewPresented,
            isBoardRulesPresented: isBoardRulesPresented,
            isBoardCountdownPresented: isBoardCountdownPresented,
            isGridSizeSheetPresented: isGridSizeSheetPresented
        )
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

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }

    private var maxGridSizeForCurrentPlan: Int {
        subscriptionManager.hasPremiumAccess ? 5 : 4
    }

    private func resizeGridWithPremiumGate(targetSize: Int, source: String) {
        guard targetSize > viewModel.gridSize else {
            viewModel.resizeGrid(to: targetSize)
            return
        }

        guard targetSize <= maxGridSizeForCurrentPlan else {
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
    }

    private func presentPremiumPaywall(source: String) {
        if source.lowercased().contains("reset") {
            AnalyticsService.logPremiumCustomResetTimeLimitHit(source: source)
        }
        premiumPaywallSource = source
        Task { @MainActor in
            isPremiumPaywallPresented = true
            await subscriptionManager.warmupProductsForPaywall()
        }
    }

    private func presentLimitedTimeDiscount() {
        guard shouldShowLimitedOfferEntry else { return }
        syncLimitedTimeOfferCampaignIfNeeded(for: limitedTimeOfferConfig)
        Task { @MainActor in
            isLimitedTimeDiscountPresented = true
            await subscriptionManager.warmupProductsForPaywall()
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
        .onAppear {
            clearLimitedOfferEntryIfPremium()
        }
        .onChange(of: subscriptionManager.hasPremiumAccess) { _, _ in
            clearLimitedOfferEntryIfPremium()
        }
    }

    private var mainScreenContent: some View {
        GeometryReader { geo in
            let usesPadLayout = isPadLayout && geo.size.width >= 768
            let horizontalPadding: CGFloat = usesPadLayout ? 30 : 20
            let topLayoutSafeInset: CGFloat = 0
            let layoutLift: CGFloat = -30
            let widthLimitedContent = geo.size.width - (horizontalPadding * 2)
            let heightLimitedContent = geo.size.height
                - max(topLayoutSafeInset, 0)
                - max(geo.safeAreaInsets.bottom, 0)
                - (usesPadLayout ? 250 : 0)
            let contentWidth = usesPadLayout
                ? max(300, min(widthLimitedContent, heightLimitedContent))
                : min(353, widthLimitedContent)

            ZStack(alignment: .top) {
                conciseSurfaceColor
                    .ignoresSafeArea()

                homeThemeBackgroundTint
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HomeHeaderView(
                        pointsAnimationStore: pointsAnimationStore,
                        isPadLayout: isPadLayout,
                        availablePoints: availablePoints,
                        showsLimitedOffer: shouldShowLimitedOfferEntry,
                        onToggleSidebar: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                isSidebarPresented.toggle()
                            }
                        },
                        onOpenPointsFlow: {
                            isPointsFlowPresented = true
                        },
                        onOpenLimitedOffer: {
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
                        countdownText: boardCountdownText,
                        isTemplateShareDisabled: isTemplateShareComposerPresented,
                        isEditActionsExpanded: isEditActionsExpanded,
                        surfaceShadowColor: activeTheme.bingoSurfaceShadowColor,
                        boardSwipeBlockingState: boardSwipeBlockingState,
                        onSelectBoard: selectBoard,
                        onBoardLongPress: beginBoardActions,
                        onCreateBoard: beginCreateBoard,
                        onDismissBoardEditHint: dismissBoardEditHint,
                        onCellCompletionToggled: reconcileStickerOwnershipIfPointsInsufficient,
                        onTemplateShare: beginBoardTemplateShare,
                        onCountdown: {
                            isBoardCountdownPresented = true
                        },
                        onEditActionsToggle: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isEditActionsExpanded.toggle()
                            }
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -layoutLift)

                HomeStickerLayer(
                    pointsFeatureStore: pointsFeatureStore,
                    selectedStickerID: $selectedStickerID,
                    canvasSize: geo.size
                )

                HomeSidebarLayer(
                    canvasWidth: geo.size.width,
                    topInset: topLayoutSafeInset,
                    bottomInset: geo.safeAreaInsets.bottom,
                    streakDays: bingoStreakDays,
                    streakGoals: streakGoals,
                    themeColor: activeThemeColor,
                    isPadLayout: isPadLayout,
                    appShortVersion: appShortVersion,
                    isPresented: $isSidebarPresented,
                    isSettingsExpanded: $isSettingsExpanded,
                    isWidgetGuideExpanded: $isWidgetGuideExpanded,
                    isThemePickerExpanded: $isThemePickerExpanded,
                    isHapticsEnabled: $isHapticsEnabled,
                    isSoundEffectsEnabled: $isSoundEffectsEnabled,
                    themeRawValue: $themeRawValue,
                    onOpenDiary: {
                        isDiaryPresented = true
                    },
                    onOpenBlackBoxMode: {
                        isBlackBoxModePresented = true
                    },
                    onOpenContact: {
                        isContactUsPresented = true
                    },
                    onEncourageUs: {
                        requestAppStoreReviewFromSidebar()
                    },
                    onPresentPremiumPaywall: {
                        presentPremiumPaywall(source: "sidebar_pro_entry")
                    }
                )

                HomeFeedbackLayer(
                    viewModel: viewModel,
                    toastStore: toastStore,
                    canvasSize: geo.size,
                    safeAreaTop: geo.safeAreaInsets.top,
                    contentWidth: contentWidth,
                    isPadLayout: isPadLayout,
                    onBoardCompletionAnimationFinished: handleBoardCompletionAnimationFinished
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
                    onBoardRules: beginBoardRules,
                    onRenameBoard: beginRenameBoard,
                    onDeleteBoard: requestDeleteBoard
                )

                HomeEditActionsLayer(
                    isEditActionsExpanded: isEditActionsExpanded,
                    isPadLayout: isPadLayout,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEditActionsExpanded = false
                        }
                    },
                    onShuffle: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            viewModel.shuffleBoard()
                        }
                    },
                    onClearBoard: {
                        isClearBoardConfirmationPresented = true
                    },
                    onGridSize: {
                        isGridSizeSheetPresented = true
                    },
                    onQuickEdit: {
                        isQuickEditPresented = true
                    }
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

            }
        }
    }

    private var shouldShowLimitedOfferEntry: Bool {
        limitedTimeOfferConfig.isEnabled
            && !subscriptionManager.hasPremiumAccess
            && !hasLimitedOfferCountdownExpired
    }

    private var hasLimitedOfferCountdownExpired: Bool {
        guard limitedTimeDiscountStartedAt > 0 else { return false }
        return countdownNow.timeIntervalSince1970 >= limitedTimeDiscountStartedAt + limitedTimeOfferConfig.offerDuration
    }

    private func clearLimitedOfferEntryIfPremium() {
        if subscriptionManager.hasPremiumAccess {
            hasVisitedPremiumPaywallWithoutPurchase = false
            isLimitedTimeDiscountPresented = false
        }
    }

    private func refreshLimitedTimeOfferConfig() async {
        let config = await LimitedTimeOfferRemoteConfigService.fetchOfferConfig()
        await MainActor.run {
            applyLimitedTimeOfferConfig(config)
        }
    }

    private func applyLimitedTimeOfferConfig(_ config: LimitedTimeOfferConfig) {
        limitedTimeOfferConfig = config
        guard config.isEnabled else {
            isLimitedTimeDiscountPresented = false
            return
        }
        syncLimitedTimeOfferCampaignIfNeeded(for: config)
        if subscriptionManager.hasPremiumAccess {
            isLimitedTimeDiscountPresented = false
        }
    }

    private func syncLimitedTimeOfferCampaignIfNeeded(for config: LimitedTimeOfferConfig) {
        guard limitedTimeDiscountCampaignID != config.campaignID else { return }
        limitedTimeDiscountCampaignID = config.campaignID
        limitedTimeDiscountStartedAt = 0
    }

    private func withPresentationLayers<Content: View>(content: Content) -> some View {
        content
            .modifier(
                HomePrimaryCoversModifier(
                    isQuickEditPresented: $isQuickEditPresented,
                    isBlackBoxModePresented: $isBlackBoxModePresented,
                    isPointsFlowPresented: $isPointsFlowPresented,
                    selectedStickerID: $selectedStickerID,
                    isDiaryPresented: $isDiaryPresented,
                    isPremiumPaywallPresented: $isPremiumPaywallPresented,
                    isLimitedTimeDiscountPresented: $isLimitedTimeDiscountPresented,
                    viewModel: viewModel,
                    pointsFeatureStore: pointsFeatureStore,
                    isPadLayout: isPadLayout,
                    availablePoints: availablePoints,
                    totalPoints: viewModel.totalPoints,
                    premiumPaywallSource: premiumPaywallSource,
                    limitedTimeOfferConfig: limitedTimeOfferConfig,
                    onQuickEditSuccess: showCommonTasksToast,
                    onQuickEditBoardApplied: syncSelectedBoardSnapshotIfNeeded
                )
            )
            .modifier(
                HomeSheetsModifier(
                    isContactUsPresented: $isContactUsPresented,
                    isContactUsCopyToastVisible: $toastStore.isContactUsCopyVisible,
                    isTemplateImportPreviewPresented: isTemplateImportPreviewBinding,
                    isBoardCountdownPresented: $isBoardCountdownPresented,
                    isBoardRulesPresented: $isBoardRulesPresented,
                    boardRulesTargetBoardID: $boardRulesTargetBoardID,
                    isGridSizeSheetPresented: $isGridSizeSheetPresented,
                    isTemplateShareComposerPresented: $isTemplateShareComposerPresented,
                    boardTemplateImportPreviewDraft: boardTemplateImportPreviewDraft,
                    boardTemplateShareDraft: boardTemplateShareDraft,
                    shouldImportTemplateAsNewBoard: shouldImportTemplateAsNewBoard,
                    namedBoards: namedBoards,
                    hasPremiumAccess: subscriptionManager.hasPremiumAccess,
                    boardCountdownEndsAt: viewModel.boardCountdownEndsAt,
                    isPadLayout: isPadLayout,
                    onCopyEmail: showContactUsCopyToast,
                    onOpenFeedbackEmail: openFeedbackEmail,
                    onApplyImportedTemplate: applyImportedTemplate,
                    onDismissTemplatePreview: templateImportFlowStore.dismissPreview,
                    onTemplateImportSheetHeight: TemplateImportFlowStore.previewSheetHeight,
                    onSaveBoardCountdown: { totalMinutes in
                        viewModel.setBoardCountdown(totalMinutes: totalMinutes)
                        isBoardCountdownPresented = false
                    },
                    onCancelBoardCountdown: {
                        isBoardCountdownPresented = false
                    },
                    onPresentPremiumPaywall: presentPremiumPaywall,
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
                                    withAnimation(.spring(response: 0.4)) {
                                        viewModel.resizeGrid(to: viewModel.gridSize - 1)
                                    }
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
        viewModel.resetBoard()
        syncTaskStartReminders()
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
                        boardTemplateShareDraft: $boardTemplateShareDraft,
                        isTemplateShareComposerPresented: $isTemplateShareComposerPresented,
                        hasCheckedAppUpdateOnLaunch: $hasCheckedAppUpdateOnLaunch,
                        hasStartedDeferredHomePreloads: $hasStartedDeferredHomePreloads,
                        hasStartedDeferredSubscriptionRefresh: $hasStartedDeferredSubscriptionRefresh,
                        scenePhase: scenePhase,
                        onDismissTemplateImportPreview: templateImportFlowStore.dismissPreview,
                        onDismissPendingTemplate: boardTemplateImportCoordinator.dismissPendingTemplate,
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
        pointsFeatureStore.loadAfterFirstFrameIfNeeded()
        ensureBoardSwitcherLoaded()
        reloadBoardSwitcherSnapshotFromSharedStoreIfNeeded(now: now)
        handleBoardResetLifecycle(
            now: now,
            force: force,
            source: source,
            shouldApplyForegroundCleanup: shouldApplyForegroundCleanup
        )
        if AppDebugFlags.simulateNextDayBoardRuleReset {
            forceApplyBoardTaskResetRulesForDebug(now: now)
        }
        evaluateFirstStepGuideEntryIfNeeded()
        countdownNow = now
        viewModel.processExpiredCountdowns(now: now)
        viewModel.processExpiredTaskCountdowns(now: now)
        viewModel.processScheduledTaskReplacementConflicts(now: now)
        processExpiredTimeoutsOnOtherBoards(now: now)
        syncTaskStartReminders()
        evaluateAppReviewPromptOpportunity()
        debugTileGestureBlockers(source: source)
    }

    private func withPresentationStateObservers(content: AnyView) -> AnyView {
        AnyView(
            content
                .modifier(
                    HomePresentationStateObserversModifier(
                        isEditActionsExpanded: $isEditActionsExpanded,
                        boardTemplateShareDraft: $boardTemplateShareDraft,
                        boardRulesTargetBoardID: $boardRulesTargetBoardID,
                        isQuickEditPresented: isQuickEditPresented,
                        pendingTemplate: boardTemplateImportCoordinator.pendingTemplate,
                        pendingTemplateSource: boardTemplateImportCoordinator.pendingTemplateSource,
                        isTemplateShareComposerPresented: isTemplateShareComposerPresented,
                        isTemplateImportPreviewPresented: isTemplateImportPreviewPresented,
                        isBoardCountdownPresented: isBoardCountdownPresented,
                        isBoardRulesPresented: isBoardRulesPresented,
                        isBlackBoxModePresented: isBlackBoxModePresented,
                        isGridSizeSheetPresented: isGridSizeSheetPresented,
                        isSidebarPresented: isSidebarPresented,
                        firstStepGuideOverlay: firstStepGuideOverlay,
                        isUpdatePromptPresented: isUpdatePromptPresented,
                        boardActionSheetBoardID: boardActionPresentationStore.actionSheetBoardID,
                        onPresentImportPreview: { template, source in
                            presentImportPreview(template: template, source: source)
                        },
                        onDismissPendingTemplate: boardTemplateImportCoordinator.dismissPendingTemplate,
                        onClearTemplateImportPreview: templateImportFlowStore.clearPreviewIfNotPresented,
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
                        onSyncSelectedBoardSnapshot: syncSelectedBoardSnapshotIfNeeded,
                        onEvaluateFirstStepGuideProgress: evaluateFirstStepGuideProgressIfNeeded,
                        onEvaluateAppReviewTaskCompletionOpportunity: evaluateAppReviewTaskCompletionOpportunity,
                        onEvaluateAppReviewLineCompletionOpportunity: evaluateAppReviewLineCompletionOpportunity,
                        onReconcileStickerOwnership: reconcileStickerOwnershipIfPointsInsufficient,
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
                        onReconcileStickerOwnership: reconcileStickerOwnershipIfPointsInsufficient,
                        onAvailablePointsChange: pointsAnimationStore.handleAvailablePointsChange,
                        onShowDailyReset: toastStore.showDailyReset,
                        onTick: handleCountdownTick,
                        onExpiredTaskEventChange: resetTaskTimeoutDelayPicker,
                        onExpiredBoardCountdownEventChange: resetBoardTimeoutDelayPicker
                    )
                )
        )
    }

    private func handleCountdownTick(now: Date) {
        countdownNow = now
        handleBoardResetLifecycle(now: now, source: "ticker")
        _ = viewModel.refreshVisibilityWindowsIfNeeded(now: now)
        viewModel.processExpiredCountdowns(now: now)
        viewModel.processExpiredTaskCountdowns(now: now)
        viewModel.processScheduledTaskReplacementConflicts(now: now)
        processExpiredTimeoutsOnOtherBoards(now: now)
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

    private func handleBoardCompletionAnimationFinished() {
        viewModel.dismissBoardCompletionAnimation()
        evaluateAppReviewPromptOpportunity(trigger: .secondFullBoard)
    }

    private func evaluateAppReviewTaskCompletionOpportunity() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            evaluateAppReviewPromptOpportunity(trigger: .secondThreeDayStreak)
        }
    }

    private func evaluateAppReviewLineCompletionOpportunity() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            evaluateAppReviewPromptOpportunity(trigger: .firstTwoLines)
        }
    }

    private func evaluateAppReviewPromptOpportunity(trigger: AppReviewPromptCandidate? = nil) {
        if let candidate = appReviewPromptCandidate(for: trigger) {
            pendingAppReviewPromptCandidate = candidate
        }
        presentPendingAppReviewPromptIfReady()
    }

    private func appReviewPromptCandidate(for trigger: AppReviewPromptCandidate?) -> AppReviewPromptCandidate? {
#if DEBUG
        if AppDebugFlags.forceAppReviewPrompt && !hasPresentedDebugAppReviewPromptThisLaunch {
            return .debug
        }
#endif

        guard !hasRatedAppReviewPrompt,
              appReviewPromptLifetimeShownCount < 2,
              Date().timeIntervalSince1970 >= appReviewPromptCooldownUntil else {
            return nil
        }

        if appReviewPromptStage <= 0, currentCompletedLineCount >= 2 {
            return .firstTwoLines
        }

        guard appReviewPromptStage == 1, appReviewPromptLastShownDay != appReviewDayKey() else {
            return nil
        }

        if trigger == .secondFullBoard, isCurrentBoardFullyCompleted {
            return .secondFullBoard
        }

        if trigger == .secondThreeDayStreak || trigger == nil,
           BingoDiaryStore.consecutiveTaskCompletionDays() >= 3 {
            return .secondThreeDayStreak
        }

        if isCurrentBoardFullyCompleted {
            return .secondFullBoard
        }

        return nil
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
        if isAppReviewPromptPresented { return false }

#if DEBUG
        if candidate == .debug {
            return true
        }
#endif

        guard firstStepGuideOverlay == nil,
              !isUpdatePromptPresented,
              !isCustomResetDowngradeAlertPresented,
              !isSidebarPresented,
              !isQuickEditPresented,
              !isBlackBoxModePresented,
              !isContactUsPresented,
              !isPointsFlowPresented,
              !isBoardCountdownPresented,
              !isBoardRulesPresented,
              !isGridSizeSheetPresented,
              !isTemplateImportPreviewPresented,
              !isTemplateShareComposerPresented,
              !viewModel.showCelebration,
              !viewModel.showBoardCompletionAnimation,
              boardActionPresentationStore.actionSheetBoardID == nil,
              timeoutDelayPickerContext == nil,
              viewModel.expiredTaskEvent == nil,
              viewModel.expiredBoardCountdownEvent == nil,
              viewModel.scheduledTaskReplacementEvent == nil else {
            return false
        }

        return true
    }

    private func requestAppStoreReviewFromPrompt() {
        hasRatedAppReviewPrompt = true
        dismissAppReviewPrompt(cooldownDays: nil)
        requestReview()
    }

    private func requestAppStoreReviewFromSidebar() {
        hasRatedAppReviewPrompt = true
        requestReview()
    }

    private func openFeedbackEmailFromPrompt() {
        dismissAppReviewPrompt(cooldownDays: 30)
        openFeedbackEmail()
    }

    private func rejectAppReviewPrompt() {
        dismissAppReviewPrompt(cooldownDays: 90)
    }

    private func closeAppReviewPrompt() {
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

    private func openFeedbackEmail() {
        guard let url = feedbackMailURL else {
            showCommonTasksToast(L10n.feedbackMailOpenFailed)
            isContactUsPresented = true
            return
        }

        openURL(url) { accepted in
            guard !accepted else { return }
            DispatchQueue.main.async {
                showCommonTasksToast(L10n.feedbackMailOpenFailed)
                isContactUsPresented = true
            }
        }
    }

    private var feedbackMailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = L10n.contactUsEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: L10n.appReviewFeedbackEmailSubject),
            URLQueryItem(name: "body", value: feedbackMailBody)
        ]
        return components.url
    }

    private var feedbackMailBody: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let version = build.isEmpty ? appShortVersion : "\(appShortVersion) (\(build))"
        let system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        return L10n.appReviewFeedbackEmailBody(
            appVersion: version,
            device: UIDevice.current.model,
            system: system
        )
    }

    private func showCommonTasksToast(_ message: String) {
        toastStore.showCommon(message)
    }

    private func showContactUsCopyToast() {
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
        markBoardPanelInteracted()
        focusedEditingResetForBoardActions()
        boardActionPresentationStore.presentActions(for: boardID)
    }

    private func beginBoardRules(for boardID: UUID) {
        markBoardPanelInteracted()
        boardRulesTargetBoardID = boardID
        isBoardRulesPresented = true
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
    ) {
        guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else { return }
        let now = Date()
        let resolvedMinutes = countdownMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }
        let countdownEndsAt = resolvedMinutes.map { now.addingTimeInterval(Double($0 * 60)) }

        let normalizedResetMode: BoardTaskResetMode = (resetMode == .customResetStatusTime) ? .resetStatusNextDay : resetMode
        namedBoards[boardIndex].taskResetMode = normalizedResetMode
        namedBoards[boardIndex].customResetMinutes = normalizedResetMode == .resetStatusNextDay
            ? customResetMinutes.map { min(max($0, 0), 23 * 60 + 59) }
            : nil
        namedBoards[boardIndex].countdownEndsAt = countdownEndsAt
        // Start counting "next day reset" from when user saved board rules.
        namedBoards[boardIndex].lastTaskResetAppliedAt = now
        namedBoards[boardIndex].updatedAt = now

        if selectedBoardID == boardID {
            viewModel.setBoardCountdown(totalMinutes: resolvedMinutes)
            namedBoards[boardIndex].board = viewModel.makeSavedBoardSnapshot()
            namedBoards[boardIndex].countdownEndsAt = viewModel.boardCountdownEndsAt
        }

        markBoardPanelInteracted()
        persistNamedBoardsSnapshot()
        showCommonTasksToast(L10n.tr("Board rules saved", zhHans: "面板规则已保存", zhHant: "面板規則已儲存"))
    }

    private func enforceCustomResetAccessIfNeeded() {
        guard subscriptionManager.hasCompletedEntitlementRefresh else { return }
        guard !subscriptionManager.hasPremiumAccess else { return }

        ensureBoardSwitcherLoaded()
        let now = Date()
        var didRevokeCustomResetTime = false
        var revokedBoardNames: [String] = []

        for index in namedBoards.indices {
            let hasCustomReset = namedBoards[index].customResetMinutes != nil ||
                namedBoards[index].taskResetMode == .customResetStatusTime
            guard hasCustomReset else { continue }

            revokedBoardNames.append(namedBoards[index].name)
            namedBoards[index].taskResetMode = .resetStatusNextDay
            namedBoards[index].customResetMinutes = nil
            namedBoards[index].updatedAt = now
            didRevokeCustomResetTime = true
        }

        guard didRevokeCustomResetTime else { return }
        persistNamedBoardsSnapshot()
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

        guard result.didReset else { return }
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

        guard let result, result.didReset else { return }
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
        markBoardPanelInteracted()
        switch BoardActionPresentationStore.deleteAvailability(
            for: boardID,
            namedBoards: namedBoards,
            allowsDeletingFirstBoard: subscriptionManager.hasPremiumAccess
        ) {
        case .allowed:
            boardActionPresentationStore.beginDelete(boardID: boardID)
        case .blocked(let message):
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
            return
        }
        markBoardPanelInteracted()

        if let selectedBoard = boardManagementStore.deleteBoard(
            boardID,
            allowsDeletingFirstBoard: subscriptionManager.hasPremiumAccess
        ) {
            viewModel.applySavedBoardSnapshot(
                selectedBoard.board,
                countdownEndsAt: selectedBoard.countdownEndsAt,
                referenceDate: .now
            )
        }

        syncTaskStartReminders()
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
            referenceDate: .now
        )
        syncSelectedBoardSnapshotIfNeeded()
    }

    private func reloadBoardSwitcherSnapshotFromSharedStoreIfNeeded(now: Date) {
        guard let selectedBoard = boardManagementStore.reloadPersistedSnapshot() else {
            return
        }

        viewModel.applySavedBoardSnapshot(
            selectedBoard.board,
            countdownEndsAt: selectedBoard.countdownEndsAt,
            referenceDate: now
        )
    }

    private func persistNamedBoardsSnapshot() {
        boardManagementStore.persistSnapshot()
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
        boardManagementStore.syncSelectedBoard(
            board: viewModel.makeSavedBoardSnapshot(),
            countdownEndsAt: viewModel.boardCountdownEndsAt
        )
        syncTaskStartReminders()
    }

    private func syncTaskStartReminders() {
        let currentBoards = namedBoards
        let currentSelectedBoardID = selectedBoardID
        let activeBoard = viewModel.makeSavedBoardSnapshot()
        let syncNow = Date()
        let syncSignature = taskStartReminderSyncSignature(
            namedBoards: currentBoards,
            selectedBoardID: currentSelectedBoardID,
            activeBoard: activeBoard,
            now: syncNow
        )

        guard syncSignature != lastReminderSyncSignature else { return }
        lastReminderSyncSignature = syncSignature

        reminderSyncTask?.cancel()
        reminderSyncTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await TaskStartReminderService.syncReminders(
                namedBoards: currentBoards,
                selectedBoardID: currentSelectedBoardID,
                activeBoard: activeBoard,
                now: syncNow
            )
        }
    }

    private func taskStartReminderSyncSignature(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date
    ) -> String {
        var boards = namedBoards
        if let selectedBoardID,
           let activeBoard,
           let selectedIndex = boards.firstIndex(where: { $0.id == selectedBoardID }) {
            boards[selectedIndex].board = activeBoard
        }

        var components: [String] = []
        for board in boards {
            let sourceCells = board.board.fullBoardCells ?? board.board.cells
            for row in sourceCells {
                for cell in row {
                    let taskText = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard cell.startReminderEnabled,
                          !taskText.isEmpty,
                          !cell.isCompleted,
                          let startDate = cell.startVisibleAt,
                          cell.endVisibleAt != nil else {
                        continue
                    }

                    let offsetMinutes = TaskStartReminderService.normalizedOffsetMinutes(cell.startReminderOffsetMinutes)
                    let reminderDate = startDate.addingTimeInterval(Double(-offsetMinutes * 60))
                    guard reminderDate > now else { continue }

                    components.append([
                        board.id.uuidString,
                        board.name,
                        cell.id.uuidString,
                        taskText,
                        String(Int(reminderDate.timeIntervalSince1970)),
                        String(offsetMinutes)
                    ].joined(separator: "|"))
                }
            }
        }
        return components.sorted().joined(separator: "\n")
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
        guard let targetBoardID = nextBoardWithExpiredTimeout(excluding: activeBoardID, now: now) else {
            return
        }

        guard let selectedBoard = boardManagementStore.selectBoard(
            targetBoardID,
            currentBoard: viewModel.makeSavedBoardSnapshot(),
            currentCountdownEndsAt: viewModel.boardCountdownEndsAt
        ) else {
            return
        }

        viewModel.applySavedBoardSnapshot(
            selectedBoard.board,
            countdownEndsAt: selectedBoard.countdownEndsAt,
            referenceDate: now
        )
        _ = viewModel.refreshVisibilityWindowsIfNeeded(now: now)
        viewModel.processExpiredCountdowns(now: now)
        viewModel.processExpiredTaskCountdowns(now: now)
    }

    private func nextBoardWithExpiredTimeout(excluding activeBoardID: UUID, now: Date) -> UUID? {
        for board in namedBoards where board.id != activeBoardID {
            if let boardDeadline = board.countdownEndsAt, boardDeadline <= now {
                return board.id
            }
            if hasExpiredTaskCountdown(in: board, now: now) {
                return board.id
            }
        }
        return nil
    }

    private func hasExpiredTaskCountdown(in namedBoard: BingoBoardStore.NamedBoard, now: Date) -> Bool {
        BoardEngine.expiredTaskCandidate(in: namedBoard.board, now: now) != nil
    }

    private func selectBoard(_ boardID: UUID) {
        guard selectedBoardID != boardID else { return }
        guard boardSwitchAnimationStore.beginSelection() else { return }
        markBoardPanelInteracted()

        if let selectedBoard = boardManagementStore.selectBoard(
            boardID,
            currentBoard: viewModel.makeSavedBoardSnapshot(),
            currentCountdownEndsAt: viewModel.boardCountdownEndsAt
        ) {
            viewModel.applySavedBoardSnapshot(
                selectedBoard.board,
                countdownEndsAt: selectedBoard.countdownEndsAt,
                referenceDate: .now
            )
        }
        syncTaskStartReminders()
    }

    private func beginCreateBoard() {
        markBoardPanelInteracted()
        guard canCreateAdditionalBoard else {
            AnalyticsService.logPremiumBoardsLimitHit(currentBoardCount: namedBoards.count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                presentPremiumPaywall(source: "boards_limit")
            }
            return
        }

        boardActionPresentationStore.beginCreate(defaultName: L10n.boardDefaultName(namedBoards.count + 1))
    }

    private func createBoard() {
        guard canCreateAdditionalBoard else {
            AnalyticsService.logPremiumBoardsLimitHit(currentBoardCount: namedBoards.count)
            return
        }
        markBoardPanelInteracted()

        let newBoard = boardManagementStore.createBoard(
            nameDraft: boardActionPresentationStore.createNameDraft,
            currentBoard: viewModel.makeSavedBoardSnapshot(),
            currentCountdownEndsAt: viewModel.boardCountdownEndsAt
        )

        viewModel.applySavedBoardSnapshot(
            newBoard.board,
            countdownEndsAt: nil,
            referenceDate: .now
        )
        syncTaskStartReminders()
        boardActionPresentationStore.clearCreateDraft()
    }

    private func beginBoardTemplateShare() {
        guard AppFeatureFlags.isTemplateSharingEnabled else { return }
        guard !isTemplateShareComposerPresented else { return }
        guard let template = makeCurrentBoardTemplate() else {
            showCommonTasksToast(L10n.templateShareEmptyBoard)
            return
        }
        AnalyticsService.logTemplateShareOpen(
            source: "board_header",
            gridSize: template.gridSize,
            isPremium: subscriptionManager.hasPremiumAccess
        )
        boardTemplateShareDraft = template
        isTemplateShareComposerPresented = true
    }

    private func beginBoardTemplateImport() {
        guard AppFeatureFlags.isTemplateSharingEnabled else { return }
        if let clipboardText = UIPasteboard.general.string,
           resolveTemplateImport(from: clipboardText, showsErrorToast: false) {
            return
        }
        showCommonTasksToast(L10n.templateImportInvalidLink)
    }

    @discardableResult
    private func resolveTemplateImport(from rawText: String, showsErrorToast: Bool = true) -> Bool {
        guard let template = templateImportFlowStore.resolveTemplate(from: rawText) else {
            if showsErrorToast {
                showCommonTasksToast(L10n.templateImportInvalidLink)
            }
            return false
        }
        presentImportPreview(template: template)
        boardTemplateImportCoordinator.dismissPendingTemplate()
        return true
    }

    private func presentImportPreview(template: BoardTemplatePayload) {
        presentImportPreview(template: template, source: "pasteboard")
    }

    private func presentImportPreview(template: BoardTemplatePayload, source: String) {
        // Delay one run loop when switching between two sheets to avoid presentation races.
        DispatchQueue.main.async {
            templateImportFlowStore.presentPreview(
                template: template,
                source: source,
                createsNewBoard: shouldImportTemplateAsNewBoard
            )
        }
    }

    private func makeCurrentBoardTemplate() -> BoardTemplatePayload? {
        let visibleCells = viewModel.cells
        let template = BoardTemplatePayload(
            title: selectedBoardName,
            gridSize: viewModel.gridSize,
            cells: visibleCells
        )
        return template.hasShareableContent ? template : nil
    }

    private func applyImportedTemplate(_ template: BoardTemplatePayload) {
        Task { @MainActor in
            await subscriptionManager.refreshEntitlements()
            applyImportedTemplateResolved(template, createsNewBoard: shouldImportTemplateAsNewBoard)
        }
    }

    private func applyImportedTemplateResolved(_ template: BoardTemplatePayload, createsNewBoard: Bool) {
        if shouldBlockTemplateImportForPremium(template) {
            handleBlockedTemplateImport(template)
            return
        }

        let savedBoard = template.makeSavedBoard(referenceDate: .now)
        guard let importedResult = importTemplateBoard(
            template: template,
            savedBoard: savedBoard,
            createsNewBoard: createsNewBoard
        ) else {
            return
        }

        applyImportedTemplateBoard(
            importedResult.board,
            template: template,
            createsNewBoard: createsNewBoard,
            successMessage: importedResult.successMessage
        )
    }

    private func shouldBlockTemplateImportForPremium(_ template: BoardTemplatePayload) -> Bool {
        template.gridSize >= 5 && !subscriptionManager.hasPremiumAccess
    }

    private func handleBlockedTemplateImport(_ template: BoardTemplatePayload) {
        AnalyticsService.logPremiumGrid5x5LimitHit(
            currentGridSize: viewModel.gridSize,
            source: "template_import"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            presentPremiumPaywall(source: "template_import")
        }
        dismissTemplateImportFlow()
    }

    private func importTemplateBoard(
        template: BoardTemplatePayload,
        savedBoard: SavedBoard,
        createsNewBoard: Bool
    ) -> TemplateImportResult? {
        if createsNewBoard {
            let importedBoard = boardManagementStore.importTemplateAsNewBoard(
                nameDraft: template.normalizedTitle,
                savedBoard: savedBoard,
                currentBoard: viewModel.makeSavedBoardSnapshot(),
                currentCountdownEndsAt: viewModel.boardCountdownEndsAt
            )
            return TemplateImportResult(
                board: importedBoard,
                successMessage: L10n.templateImportSuccessCreated
            )
        }

        guard let importedBoard = boardManagementStore.replaceSelectedBoardWithTemplate(
            nameDraft: template.normalizedTitle,
            savedBoard: savedBoard
        ) else {
            return nil
        }

        return TemplateImportResult(
            board: importedBoard,
            successMessage: L10n.templateImportSuccessReplaced
        )
    }

    private func applyImportedTemplateBoard(
        _ importedBoard: BingoBoardStore.NamedBoard,
        template: BoardTemplatePayload,
        createsNewBoard: Bool,
        successMessage: String
    ) {
        viewModel.applySavedBoardSnapshot(
            importedBoard.board,
            countdownEndsAt: nil,
            referenceDate: .now
        )
        syncTaskStartReminders()
        finishTemplateImport(
            template: template,
            createsNewBoard: createsNewBoard,
            successMessage: successMessage
        )
    }

    private func finishTemplateImport(
        template: BoardTemplatePayload,
        createsNewBoard: Bool,
        successMessage: String
    ) {
        dismissTemplateImportFlow()
        templateImportFlowStore.logImportSuccess(template: template, createsNewBoard: createsNewBoard)
        showCommonTasksToast(successMessage)
    }

    private func dismissTemplateImportFlow() {
        templateImportFlowStore.dismissPreview()
        boardTemplateImportCoordinator.dismissPendingTemplate()
    }

    private func beginRenameSelectedBoard() {
        guard let selectedNamedBoardIndex else { return }
        let board = namedBoards[selectedNamedBoardIndex]
        markBoardPanelInteracted()
        boardActionPresentationStore.beginRename(board: board)
    }

    private func beginRenameBoard(_ boardID: UUID) {
        guard let board = namedBoards.first(where: { $0.id == boardID }) else { return }
        markBoardPanelInteracted()
        boardActionPresentationStore.beginRename(board: board)
    }

    private func renameBoard() {
        defer {
            boardActionPresentationStore.clearRenameDraft()
        }

        guard let boardPendingRenameID = boardActionPresentationStore.pendingRenameID else {
            return
        }

        markBoardPanelInteracted()
        boardManagementStore.renameBoard(
            boardPendingRenameID,
            nameDraft: boardActionPresentationStore.renameNameDraft
        )
        syncTaskStartReminders()
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

    private func reconcileStickerOwnershipIfPointsInsufficient() {
        guard pointsFeatureStore.reconcileStickerOwnershipIfPointsInsufficient(
            totalPoints: viewModel.totalPoints
        ) else {
            return
        }
        showCommonTasksToast(L10n.stickerRevokedDueToPoints)

        if let selectedStickerID, !pointsFeatureStore.containsPlacement(id: selectedStickerID) {
            self.selectedStickerID = nil
        }
    }
}
