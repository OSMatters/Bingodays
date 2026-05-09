import SwiftUI
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

extension Font {
    static func appSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        switch AppLanguage.current {
        case .english:
            return .custom("Outfit", size: size).weight(weight)
        case .simplifiedChinese, .traditionalChinese, .japanese:
            return .system(size: size, weight: weight, design: design)
        }
    }
}


struct ContentView: View {
    private enum FirstStepGuideState: Int {
        case notStarted = 0
        case tracking = 1
        case finished = 2
    }

    private enum TimeoutDelayPickerContext {
        case task
        case board
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var accountSession: AccountSession
    @EnvironmentObject private var boardTemplateImportCoordinator: BoardTemplateImportCoordinator
    @StateObject private var viewModel = BingoViewModel()
    @StateObject private var boardManagementStore = BoardManagementStore()
    @StateObject private var templateImportFlowStore = TemplateImportFlowStore()
    @StateObject private var pointsFeatureStore = PointsFeatureStore()
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
    @State private var premiumPaywallSource = "unknown"
    @State private var isQuickEditPresented = false
    @State private var isBlackBoxModePresented = false
    @State private var isContactUsPresented = false
    @State private var isContactUsCopyToastVisible = false
    @State private var contactUsCopyToastWorkItem: DispatchWorkItem?
    @State private var isEditActionsExpanded = false
    @State private var isGridSizeSheetPresented = false
    @State private var isClearBoardConfirmationPresented = false
    @State private var commonTasksToastMessage: String?
    @State private var isCommonTasksToastVisible = false
    @State private var hideCommonTasksToastWorkItem: DispatchWorkItem?
    @State private var pointsAnimationTrigger = 0
    @State private var floatingPointsDelta: Int?
    @State private var isFloatingPointsDeltaVisible = false
    @State private var isDailyResetToastVisible = false
    @State private var taskTimeoutDelayMinutes = 10
    @State private var boardTimeoutDelayMinutes = 10
    @State private var timeoutDelayPickerContext: TimeoutDelayPickerContext?
    @State private var timeoutDelayPickerHours = 0
    @State private var timeoutDelayPickerMinutes = 10
    @State private var isUpdatePromptPresented = false
    @State private var hasCheckedAppUpdateOnLaunch = false
    @State private var pendingUpdateInfo: AppUpdateInfo?
    @State private var hasStartedDeferredHomePreloads = false
    @State private var hasStartedDeferredSubscriptionRefresh = false
    @State private var firstStepGuideOverlay: FirstStepGuideOverlay?
    @State private var isCreateBoardAlertPresented = false
    @State private var createBoardNameDraft = ""
    @State private var isRenameBoardAlertPresented = false
    @State private var renameBoardNameDraft = ""
    @State private var boardPendingRenameID: UUID?
    @State private var boardActionSheetBoardID: UUID?
    @State private var pendingBoardDeleteID: UUID?
    @State private var isBoardDeleteAlertPresented = false
    @State private var boardTemplateShareDraft: BoardTemplatePayload?
    @State private var isTemplateShareComposerPresented = false
    @State private var lastBoardRulesEvaluationDateKey = ""
    @State private var hasAppliedDebugSimulatedResetThisLaunch = false
    @State private var lastCustomResetDebugToastKey = ""
    @State private var boardSwitchTransitionDirection: CGFloat = 1
    @GestureState private var boardDragTranslationX: CGFloat = 0
    @State private var isBoardSwitchAnimating = false
    @State private var boardSwitchAnimationOffsetX: CGFloat = 0
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppSettings.soundEffectsEnabledKey) private var isSoundEffectsEnabled = true
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue
    @AppStorage(AppSettings.lastPromptedUpdateVersionKey) private var lastPromptedUpdateVersion = ""
    @AppStorage(AppSettings.skippedUpdateVersionKey) private var skippedUpdateVersion = ""
    @AppStorage(AppSettings.firstStepGuideStateKey) private var firstStepGuideStateRawValue = FirstStepGuideState.notStarted.rawValue
    @AppStorage(AppSettings.firstStepGuideMilestoneKey) private var firstStepGuideMilestoneShown = 0
    private let countdownTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var countdownNow = Date()
    private var bingoStreakDays: Int { BingoDiaryStore.consecutiveBingoDays() }
    private var streakGoals: [Int] { bingoStreakDays >= 60 ? [60, 180, 270, 365] : [7, 14, 30, 60] }
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var activeThemeColor: Color { activeTheme.color }
    private var conciseSurfaceColor: Color { NeumorphicColors.background }
    private var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    private var releaseNotesItems: [String] {
        [
            L10n.updateItemQuickEditImproved,
            L10n.updateItemKnownIssuesFixed
        ]
    }
    private var availablePoints: Int {
        pointsFeatureStore.availablePoints(totalPoints: viewModel.totalPoints)
    }
    private var filledTaskCount: Int {
        viewModel.cells.flatMap(\.self).filter { !$0.isEmpty }.count
    }
    private var completedTaskCount: Int {
        viewModel.cells.flatMap(\.self).filter { !$0.isEmpty && $0.isCompleted }.count
    }
    private var completionProgress: Double {
        guard filledTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(filledTaskCount)
    }
    private var completionPercent: Int {
        Int((completionProgress * 100).rounded())
    }

    private var firstStepGuideState: FirstStepGuideState {
        FirstStepGuideState(rawValue: firstStepGuideStateRawValue) ?? .notStarted
    }

    private func normalizedStarterTaskText(_ text: String) -> String {
        String(text.prefix(BingoViewModel.maxTaskLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var starterSeedTasks: [String] {
        [
            L10n.tr("Drink a glass of water", zhHans: "喝一杯水", zhHant: "喝一杯水"),
            L10n.tr("Stand for 1 minute", zhHans: "站立1分钟", zhHant: "站立1分鐘"),
            L10n.tr("Stretch your body", zhHans: "拉伸身体", zhHant: "拉伸身體")
        ]
    }

    private var starterSeedTaskKeys: [String] {
        starterSeedTasks.map(normalizedStarterTaskText)
    }

    private var starterIntroTitle: String {
        L10n.tr("Welcome to Bingodays 👋", zhHans: "欢迎来到 Bingodays 👋", zhHant: "歡迎來到 Bingodays 👋")
    }

    private var starterIntroDescription: String {
        L10n.tr(
            "Complete these starter tasks to feel the Bingo flow.",
            zhHans: "先完成这几个任务，体验Bingo的乐趣",
            zhHant: "先完成這幾個任務，體驗 Bingo 的樂趣"
        )
    }

    private func starterMilestoneMessage(for overlay: FirstStepGuideOverlay) -> String {
        switch overlay {
        case .intro:
            return ""
        case .milestoneOne:
            return L10n.tr(
                "Nice! First step completed, keep going 💪",
                zhHans: "Nice！第一步已完成，继续冲吧 💪",
                zhHant: "Nice！第一步已完成，繼續衝吧 💪"
            )
        case .milestoneTwo:
            return L10n.tr(
                "One step away from Bingo. Keep it up 🚀",
                zhHans: "离Bingo就差一个了！继续加油 🚀",
                zhHant: "離 Bingo 就差一個了！繼續加油 🚀"
            )
        case .milestoneThree:
            return L10n.tr(
                "Amazing! You unlocked your first Bingo 🎉 Long-press a tile to edit tasks and start your next round!",
                zhHans: "太厉害了！你解锁了第一个Bingo🎉 长按格子编辑任务，开启下一轮挑战吧！",
                zhHant: "太厲害了！你解鎖了第一個 Bingo🎉 長按格子編輯任務，開啟下一輪挑戰吧！"
            )
        }
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
private var selectedBoardName: String {
    boardManagementStore.selectedBoardName
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
        premiumPaywallSource = source
        Task { @MainActor in
            isPremiumPaywallPresented = true
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

                VStack(spacing: 0) {
                    headerView
                        .frame(width: contentWidth)
                        .padding(.top, max(topLayoutSafeInset, 0) + 12)

                    boardMainContent(contentWidth: contentWidth, usesPadLayout: usesPadLayout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -layoutLift)

                homeStickerLayer(
                    canvasSize: geo.size,
                    topInset: topLayoutSafeInset,
                    bottomInset: geo.safeAreaInsets.bottom
                )

                if isSidebarPresented {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                isSidebarPresented = false
                            }
                        }
                }

                sidebarView(
                    width: usesPadLayout ? min(geo.size.width * 0.42, 420) : min(geo.size.width * 0.8, 332),
                    topInset: topLayoutSafeInset,
                    bottomInset: geo.safeAreaInsets.bottom
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: isSidebarPresented ? 0 : -(usesPadLayout ? min(geo.size.width * 0.42, 420) : min(geo.size.width * 0.8, 320)))
                .allowsHitTesting(isSidebarPresented)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSidebarPresented)

                if viewModel.showCelebration {
                    CelebrationView()
                }

                if viewModel.showBoardCompletionAnimation {
                    PAGCompletionView(resourceName: "cat_bmp") {
                        viewModel.dismissBoardCompletionAnimation()
                    }
                    .frame(width: min(geo.size.width * 0.5, 220), height: min(geo.size.width * 0.5, 220))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                if isDailyResetToastVisible {
                    DailyResetToastView(isPadLayout: isPadLayout)
                        .frame(maxWidth: min(contentWidth, 620), maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(geo.safeAreaInsets.top, 18) + 44)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if let commonTasksToastMessage, isCommonTasksToastVisible {
                    CommonTasksToastView(message: commonTasksToastMessage, isPadLayout: isPadLayout)
                        .frame(maxWidth: min(contentWidth, 520), maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(geo.safeAreaInsets.top, 18) + 96)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if let firstStepGuideOverlay {
                    FirstStepGuideOverlayView(
                        overlay: firstStepGuideOverlay,
                        isPadLayout: isPadLayout,
                        starterSeedTasks: starterSeedTasks,
                        introTitle: starterIntroTitle,
                        introDescription: starterIntroDescription,
                        milestoneMessage: starterMilestoneMessage,
                        onStart: startFirstStepGuide,
                        onDismiss: dismissFirstStepGuideOverlay
                    )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(40)
                }

                if isUpdatePromptPresented, pendingUpdateInfo != nil {
                    updatePromptOverlayView
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                boardActionLayer(contentWidth: contentWidth, bottomInset: geo.safeAreaInsets.bottom)

                if isEditActionsExpanded {
                    editActionsFullscreenOverlay
                        .transition(.opacity)
                        .zIndex(12)
                }

                if let expiredTaskEvent = viewModel.expiredTaskEvent {
                    taskTimeoutOverlay(for: expiredTaskEvent)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(30)
                }

                if let expiredBoardEvent = viewModel.expiredBoardCountdownEvent {
                    boardTimeoutOverlay(for: expiredBoardEvent)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(30)
                }

                if let scheduledEvent = viewModel.scheduledTaskReplacementEvent {
                    scheduledTaskReplacementOverlay(for: scheduledEvent)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(30)
                }

                if timeoutDelayPickerContext != nil {
                    timeoutDelayPickerOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(40)
                }

            }
        }
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
                    viewModel: viewModel,
                    pointsFeatureStore: pointsFeatureStore,
                    isPadLayout: isPadLayout,
                    availablePoints: availablePoints,
                    totalPoints: viewModel.totalPoints,
                    premiumPaywallSource: premiumPaywallSource,
                    onQuickEditSuccess: showCommonTasksToast
                )
            )
            .sheet(isPresented: $isContactUsPresented) {
                ContactUsSheet(
                    isPresented: $isContactUsPresented,
                    isPadLayout: isPadLayout,
                    isCopyToastVisible: isContactUsCopyToastVisible,
                    onCopyEmail: showContactUsCopyToast
                )
            }
            .fullScreenCover(isPresented: $isTemplateShareComposerPresented) {
                if let template = boardTemplateShareDraft {
                    BoardTemplateShareComposerView(template: template)
                }
            }
            .sheet(isPresented: isTemplateImportPreviewBinding) {
                if let template = boardTemplateImportPreviewDraft {
                    BoardTemplateImportPreviewView(
                        template: template,
                        createsNewBoard: shouldImportTemplateAsNewBoard,
                        onImport: {
                            applyImportedTemplate(template)
                        },
                        onClose: {
                            templateImportFlowStore.dismissPreview()
                        }
                    )
                    .presentationDetents([.height(templateImportSheetHeight(for: template.gridSize))])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $isBoardCountdownPresented) {
                BoardCountdownSheet(
                    countdownEndsAt: viewModel.boardCountdownEndsAt,
                    onSave: { totalMinutes in
                        viewModel.setBoardCountdown(totalMinutes: totalMinutes)
                        isBoardCountdownPresented = false
                    },
                    onCancel: {
                        isBoardCountdownPresented = false
                    }
                )
                .presentationDetents([.height(410)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isBoardRulesPresented) {
                if let boardRulesTargetBoardID,
                   let board = namedBoards.first(where: { $0.id == boardRulesTargetBoardID }) {
                    BoardRulesSheet(
                        countdownEndsAt: board.countdownEndsAt,
                        initialResetMode: board.taskResetMode,
                        initialCustomResetMinutes: board.customResetMinutes,
                        onSave: { totalMinutes, resetMode, customResetMinutes in
                            if customResetMinutes != nil, !subscriptionManager.hasPremiumAccess {
                                isBoardRulesPresented = false
                                presentPremiumPaywall(source: "board_rules_custom_reset_time")
                                return
                            }
                            applyBoardRulesSettings(
                                for: board.id,
                                countdownMinutes: totalMinutes,
                                resetMode: resetMode,
                                customResetMinutes: customResetMinutes
                            )
                            isBoardRulesPresented = false
                        },
                        onCancel: {
                            isBoardRulesPresented = false
                        }
                    )
                    .presentationDetents([.height(560)])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $isGridSizeSheetPresented) {
                gridSizeAdjustmentSheet
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(NeumorphicColors.background)
            }
    }

    private func withBoardAlerts<Content: View>(content: Content) -> some View {
        content
            .modifier(
                HomeBoardAlertsModifier(
                    isCreateBoardAlertPresented: $isCreateBoardAlertPresented,
                    createBoardNameDraft: $createBoardNameDraft,
                    isRenameBoardAlertPresented: $isRenameBoardAlertPresented,
                    renameBoardNameDraft: $renameBoardNameDraft,
                    boardPendingRenameID: $boardPendingRenameID,
                    isBoardDeleteAlertPresented: $isBoardDeleteAlertPresented,
                    pendingBoardDeleteID: $pendingBoardDeleteID,
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
            .onAppear {
                if !AppFeatureFlags.isTemplateSharingEnabled {
                    boardTemplateShareDraft = nil
                    isTemplateShareComposerPresented = false
                templateImportFlowStore.dismissPreview()
                boardTemplateImportCoordinator.dismissPendingTemplate()
                }
                pointsFeatureStore.loadAfterFirstFrameIfNeeded()
                ensureBoardSwitcherLoaded()
                handleBoardResetLifecycle(now: Date(), force: true, source: "onAppear", shouldApplyForegroundCleanup: true)
                if shouldSimulateNextDayBoardRuleResetInDebug {
                    forceApplyBoardTaskResetRulesForDebug(now: Date())
                }
                evaluateFirstStepGuideEntryIfNeeded()
                countdownNow = Date()
                viewModel.processExpiredCountdowns(now: countdownNow)
                viewModel.processExpiredTaskCountdowns(now: countdownNow)
                viewModel.processScheduledTaskReplacementConflicts(now: countdownNow)
                if !hasStartedDeferredHomePreloads {
                    hasStartedDeferredHomePreloads = true
                    Task(priority: .utility) {
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        PAGCompletionView.preload(resourceName: "cat_bmp")
                        PointsSoundPlayer.shared.preload()
                    }
                }
                if !hasCheckedAppUpdateOnLaunch {
                    hasCheckedAppUpdateOnLaunch = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        await checkForAppUpdateIfNeeded()
                    }
                }
                if !hasStartedDeferredSubscriptionRefresh {
                    hasStartedDeferredSubscriptionRefresh = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        await subscriptionManager.refreshAll()
                    }
                }
                debugTileGestureBlockers(source: "onAppear")
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                ensureBoardSwitcherLoaded()
                handleBoardResetLifecycle(now: Date(), force: true, source: "sceneActive", shouldApplyForegroundCleanup: true)
                if shouldSimulateNextDayBoardRuleResetInDebug {
                    forceApplyBoardTaskResetRulesForDebug(now: Date())
                }
                evaluateFirstStepGuideEntryIfNeeded()
                countdownNow = Date()
                viewModel.processExpiredCountdowns(now: countdownNow)
                viewModel.processExpiredTaskCountdowns(now: countdownNow)
                viewModel.processScheduledTaskReplacementConflicts(now: countdownNow)
                Task {
                    await subscriptionManager.refreshEntitlements()
                }
                Task {
                    await checkForAppUpdateIfNeeded()
                }
                debugTileGestureBlockers(source: "sceneActive")
            }
        )
    }

    private func withPresentationStateObservers(content: AnyView) -> AnyView {
        AnyView(
            content
            .onChange(of: isQuickEditPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: boardTemplateImportCoordinator.pendingTemplate) { _, incomingTemplate in
                guard AppFeatureFlags.isTemplateSharingEnabled else { return }
                guard let incomingTemplate else { return }
                presentImportPreview(
                    template: incomingTemplate,
                    source: boardTemplateImportCoordinator.pendingTemplateSource
                )
                boardTemplateImportCoordinator.dismissPendingTemplate()
            }
            .onChange(of: isTemplateShareComposerPresented) { _, isPresented in
                if !isPresented {
                    boardTemplateShareDraft = nil
                }
            }
            .onChange(of: isTemplateImportPreviewPresented) { _, isPresented in
                if !isPresented { templateImportFlowStore.clearPreviewIfNotPresented() }
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
                debugTileGestureBlockers(source: "sidebar")
            }
            .onChange(of: isEditActionsExpanded) { _, _ in
                debugTileGestureBlockers(source: "quickEditOverlay")
            }
            .onChange(of: firstStepGuideOverlay) { _, _ in
                debugTileGestureBlockers(source: "firstStepGuide")
            }
            .onChange(of: isUpdatePromptPresented) { _, _ in
                debugTileGestureBlockers(source: "updatePrompt")
            }
            .onChange(of: boardActionSheetBoardID) { _, _ in
                debugTileGestureBlockers(source: "boardActionSheet")
            }
        )
    }

    private func withBoardStateObservers(content: AnyView) -> AnyView {
        AnyView(
            content
            .onChange(of: viewModel.cells) { _, _ in
                syncSelectedBoardSnapshotIfNeeded()
                evaluateFirstStepGuideProgressIfNeeded()
                reconcileStickerOwnershipIfPointsInsufficient()
            }
            .onChange(of: viewModel.gridSize) { _, _ in
                syncSelectedBoardSnapshotIfNeeded()
            }
            .onChange(of: viewModel.completedLines) { _, _ in
                syncSelectedBoardSnapshotIfNeeded()
            }
            .onChange(of: viewModel.boardCountdownEndsAt) { _, _ in
                syncSelectedBoardSnapshotIfNeeded()
            }
        )
    }

    private func withPointsAndTimeoutObservers(content: AnyView) -> AnyView {
        AnyView(
            content
            .onAppear {
                reconcileStickerOwnershipIfPointsInsufficient()
            }
            .onChange(of: viewModel.totalPoints) { _, _ in
                reconcileStickerOwnershipIfPointsInsufficient()
            }
            .onChange(of: availablePoints) { oldValue, newValue in
                reconcileStickerOwnershipIfPointsInsufficient()

                let delta = newValue - oldValue
                guard delta != 0 else { return }

                pointsAnimationTrigger += 1
                floatingPointsDelta = delta

                if delta > 0 {
                    PointsSoundPlayer.shared.play()
                }

                withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                    isFloatingPointsDeltaVisible = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                    withAnimation(.easeOut(duration: 0.32)) {
                        isFloatingPointsDeltaVisible = false
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.08) {
                    if !isFloatingPointsDeltaVisible {
                        floatingPointsDelta = nil
                    }
                }
            }
            .onChange(of: viewModel.dailyResetNoticeID) { _, newValue in
                guard newValue > 0 else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isDailyResetToastVisible = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeOut(duration: 0.28)) {
                        isDailyResetToastVisible = false
                    }
                }
            }
            .onReceive(countdownTicker) { _ in
                countdownNow = Date()
                handleBoardResetLifecycle(now: countdownNow, source: "ticker")
                _ = viewModel.refreshVisibilityWindowsIfNeeded(now: countdownNow)
                viewModel.processExpiredCountdowns(now: countdownNow)
                viewModel.processExpiredTaskCountdowns(now: countdownNow)
                viewModel.processScheduledTaskReplacementConflicts(now: countdownNow)
            }
            .onChange(of: viewModel.expiredTaskEvent?.id) { _, _ in
                taskTimeoutDelayMinutes = 10
                timeoutDelayPickerContext = nil
            }
            .onChange(of: viewModel.expiredBoardCountdownEvent?.id) { _, _ in
                boardTimeoutDelayMinutes = 10
                timeoutDelayPickerContext = nil
            }
        )
    }

    private var shouldForceShowUpdatePromptInDebug: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ForceUpdatePrompt")
#else
        false
#endif
    }

    private var shouldSimulateNextDayBoardRuleResetInDebug: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-SimulateNextDayBoardRuleReset")
#else
        false
#endif
    }

    private var shouldPrepareStreakTestInDebug: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugStreakReady")
#else
        false
#endif
    }

    private var shouldShowCustomResetDebugToastInDebug: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugCustomResetToast")
#else
        false
#endif
    }

    @MainActor
    private func checkForAppUpdateIfNeeded() async {
        if let cachedInfo = AppUpdateService.cachedUpdateInfo(currentVersion: appShortVersion),
           (shouldForceShowUpdatePromptInDebug || cachedInfo.latestVersion != skippedUpdateVersion),
           (shouldForceShowUpdatePromptInDebug || cachedInfo.latestVersion != lastPromptedUpdateVersion) {
            presentUpdatePrompt(with: cachedInfo)
        }

        if let info = await AppUpdateService.fetchUpdateInfo(currentVersion: appShortVersion) {
            if !shouldForceShowUpdatePromptInDebug && info.latestVersion == skippedUpdateVersion {
                return
            }
            if !shouldForceShowUpdatePromptInDebug && info.latestVersion == lastPromptedUpdateVersion {
                return
            }
            presentUpdatePrompt(with: info)
            return
        }

#if DEBUG
        if shouldForceShowUpdatePromptInDebug {
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
    }

    private func evaluateFirstStepGuideEntryIfNeeded() {
        guard firstStepGuideState == .notStarted else { return }
        guard firstStepGuideOverlay == nil else { return }
        guard viewModel.currentTaskPoolTasks().isEmpty else { return }
        firstStepGuideOverlay = .intro
    }

    private func startFirstStepGuide() {
        if viewModel.gridSize < 3 {
            viewModel.resizeGrid(to: 3)
        }

        let seedTasks = starterSeedTaskKeys
        for (col, task) in seedTasks.enumerated() {
            viewModel.updateTask(
                row: 0,
                col: col,
                text: task,
                isForced: false,
                residentWeekdays: [],
                isOneTimeTask: false
            )
        }

        firstStepGuideStateRawValue = FirstStepGuideState.tracking.rawValue
        firstStepGuideMilestoneShown = 0
        firstStepGuideOverlay = nil
    }

    private func skipFirstStepGuide() {
        firstStepGuideStateRawValue = FirstStepGuideState.finished.rawValue
        firstStepGuideMilestoneShown = 3
        firstStepGuideOverlay = nil
    }

    private func starterCompletedTaskCount() -> Int {
        let allCells = viewModel.cells.flatMap { $0 }

        return starterSeedTaskKeys.reduce(0) { count, task in
            let hasCompleted = allCells.contains {
                $0.isCompleted &&
                normalizedStarterTaskText($0.storedTaskText) == task
            }
            return count + (hasCompleted ? 1 : 0)
        }
    }

    private func evaluateFirstStepGuideProgressIfNeeded() {
        guard firstStepGuideState == .tracking else { return }
        guard firstStepGuideOverlay != .intro else { return }

        let completedCount = starterCompletedTaskCount()
        let targetOverlay: FirstStepGuideOverlay?

        switch completedCount {
        case 3... where firstStepGuideMilestoneShown < 3:
            targetOverlay = .milestoneThree
        case 2 where firstStepGuideMilestoneShown < 2:
            targetOverlay = .milestoneTwo
        case 1 where firstStepGuideMilestoneShown < 1:
            targetOverlay = .milestoneOne
        default:
            targetOverlay = nil
        }

        guard let targetOverlay else { return }
        firstStepGuideOverlay = targetOverlay

        switch targetOverlay {
        case .milestoneOne:
            firstStepGuideMilestoneShown = max(firstStepGuideMilestoneShown, 1)
        case .milestoneTwo:
            firstStepGuideMilestoneShown = max(firstStepGuideMilestoneShown, 2)
        case .milestoneThree:
            firstStepGuideMilestoneShown = max(firstStepGuideMilestoneShown, 3)
        case .intro:
            break
        }
    }

    private func dismissFirstStepGuideOverlay() {
        if firstStepGuideOverlay == .milestoneThree {
            firstStepGuideStateRawValue = FirstStepGuideState.finished.rawValue
        }
        firstStepGuideOverlay = nil
    }

    private func updatePromptItems(for info: AppUpdateInfo) -> [String] {
        if let notes = info.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            let items = notes
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !items.isEmpty {
                return items
            }
        }
        return releaseNotesItems
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

    @ViewBuilder
    private var updatePromptOverlayView: some View {
        if let info = pendingUpdateInfo {
            UpdatePromptOverlayView(
                latestVersion: info.latestVersion,
                items: updatePromptItems(for: info),
                isPadLayout: isPadLayout,
                onSkip: {
                    dismissUpdatePrompt(markSkipped: true)
                },
                onUpdate: openAppStoreForUpdate
            )
        }
    }

    private func showCommonTasksToast(_ message: String) {
        hideCommonTasksToastWorkItem?.cancel()
        commonTasksToastMessage = message

        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            isCommonTasksToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.26)) {
                isCommonTasksToastVisible = false
            }
        }
        hideCommonTasksToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func showContactUsCopyToast() {
        contactUsCopyToastWorkItem?.cancel()

        withAnimation(.easeInOut(duration: 0.2)) {
            isContactUsCopyToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                isContactUsCopyToastVisible = false
            }
        }

        contactUsCopyToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    @ViewBuilder
    private func taskTimeoutOverlay(for event: BingoViewModel.ExpiredTaskEvent) -> some View {
        ZStack {
            TimeoutDialogBackdrop()

            VStack(spacing: 20) {
                let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)
                let taskText = event.taskText.isEmpty ? L10n.task : event.taskText

                TimeoutDialogCard(
                    headline: L10n.taskTimedOutHeadline(task: taskText, seconds: overtimeSeconds),
                    isPadLayout: isPadLayout,
                    onPrimaryAction: {
                        if let message = viewModel.resolveExpiredTask(.markAsCompleted, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    },
                    onSecondaryAction: {
                        openTimeoutDelayPicker(for: .task, presetMinutes: taskTimeoutDelayMinutes)
                    }
                )

                Button {
                    if let message = viewModel.resolveExpiredTask(.abandon, now: countdownNow) {
                        showCommonTasksToast(message)
                    }
                } label: {
                    Text(L10n.tr("Remove task", zhHans: "删除任务", zhHant: "刪除任務"))
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func boardTimeoutOverlay(for event: BingoViewModel.ExpiredBoardCountdownEvent) -> some View {
        ZStack {
            TimeoutDialogBackdrop()

            VStack(spacing: 20) {
                let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)

                TimeoutDialogCard(
                    headline: L10n.boardTimedOutHeadline(seconds: overtimeSeconds),
                    isPadLayout: isPadLayout,
                    onPrimaryAction: {
                        if let message = viewModel.resolveExpiredBoardCountdown(.markAsCompleted, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    },
                    onSecondaryAction: {
                        openTimeoutDelayPicker(for: .board, presetMinutes: boardTimeoutDelayMinutes)
                    }
                )

                Button {
                    if let message = viewModel.resolveExpiredBoardCountdown(.abandon, now: countdownNow) {
                        showCommonTasksToast(message)
                    }
                } label: {
                    Text(L10n.tr("Cancel countdown", zhHans: "取消倒计时", zhHant: "取消倒計時"))
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func scheduledTaskReplacementOverlay(for event: BingoViewModel.ScheduledTaskReplacementEvent) -> some View {
        ZStack {
            TimeoutDialogBackdrop()

            VStack(spacing: 20) {
                ScheduledTaskReplacementDialogCard(
                    currentTaskText: event.currentTaskText,
                    presetTaskText: event.presetTaskText,
                    isPadLayout: isPadLayout,
                    onClose: {
                        viewModel.dismissScheduledTaskReplacementPrompt()
                    },
                    onReplace: {
                        if let message = viewModel.resolveScheduledTaskReplacement(.replaceWithPreset, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    },
                    onKeepCurrent: {
                        if let message = viewModel.resolveScheduledTaskReplacement(.keepCurrentTask, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    }
                )
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var timeoutDelayPickerOverlay: some View {
        if timeoutDelayPickerContext != nil {
            TimeoutDelayPickerOverlay(
                hours: $timeoutDelayPickerHours,
                minutes: $timeoutDelayPickerMinutes,
                isPadLayout: isPadLayout,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        timeoutDelayPickerContext = nil
                    }
                },
                onApply: applyTimeoutDelayPickerSelection
            )
        }
    }

    private func openTimeoutDelayPicker(for context: TimeoutDelayPickerContext, presetMinutes: Int) {
        let clamped = min(max(presetMinutes, 1), BingoViewModel.maxCountdownMinutes)
        if clamped <= 60 {
            timeoutDelayPickerHours = 0
            timeoutDelayPickerMinutes = clamped
        } else {
            let quotient = clamped / 60
            let remainder = clamped % 60
            if remainder == 0 {
                timeoutDelayPickerHours = max(quotient - 1, 0)
                timeoutDelayPickerMinutes = 60
            } else {
                timeoutDelayPickerHours = quotient
                timeoutDelayPickerMinutes = remainder
            }
        }
        timeoutDelayPickerContext = context
    }

    private func applyTimeoutDelayPickerSelection() {
        guard let context = timeoutDelayPickerContext else { return }
        var selectedMinutes = (timeoutDelayPickerHours * 60) + timeoutDelayPickerMinutes
        selectedMinutes = min(max(selectedMinutes, 1), BingoViewModel.maxCountdownMinutes)
        timeoutDelayPickerContext = nil
        let applyNow = Date()

        switch context {
        case .task:
            taskTimeoutDelayMinutes = selectedMinutes
            if let message = viewModel.resolveExpiredTask(.postpone(minutes: selectedMinutes), now: applyNow) {
                showCommonTasksToast(message)
            } else {
                showCommonTasksToast(L10n.tr("Postpone failed. Please try again.", zhHans: "延期失败，请重试", zhHant: "延期失敗，請重試"))
            }
        case .board:
            boardTimeoutDelayMinutes = selectedMinutes
            if let message = viewModel.resolveExpiredBoardCountdown(.postpone(minutes: selectedMinutes), now: applyNow) {
                showCommonTasksToast(message)
            } else {
                showCommonTasksToast(L10n.tr("Postpone failed. Please try again.", zhHans: "延期失败，请重试", zhHant: "延期失敗，請重試"))
            }
        }
    }

    private func conciseRaisedSurface(cornerRadius: CGFloat, shadowRadius: CGFloat, offset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(conciseSurfaceColor)
            .shadow(color: Color.white.opacity(0.72), radius: shadowRadius, x: -offset, y: -offset)
            .shadow(color: NeumorphicColors.darkShadow.opacity(0.72), radius: shadowRadius, x: offset, y: offset)
    }

    private func conciseFlatSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(conciseSurfaceColor)
    }

    private func conciseOutlineSurface(cornerRadius: CGFloat, lineWidth: CGFloat = 1) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(conciseSurfaceColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NeumorphicColors.accent.opacity(0.6), lineWidth: lineWidth)
            )
    }

    @ViewBuilder
    private var templateShareTrigger: some View {
        let buttonSize: CGFloat = isPadLayout ? 66 : 60

        if AppFeatureFlags.isTemplateSharingEnabled {
            Button {
                beginBoardTemplateShare()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.appSystem(size: isPadLayout ? 22 : 20, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(
                        conciseRaisedSurface(
                            cornerRadius: buttonSize / 2,
                            shadowRadius: isPadLayout ? 11 : 9,
                            offset: isPadLayout ? 5 : 4
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(isTemplateShareComposerPresented)
            .accessibilityLabel(L10n.shareBoardTemplate)
        } else {
            Color.clear
                .frame(width: buttonSize, height: buttonSize)
        }
    }

    private var editActionsTrigger: some View {
        let buttonSize: CGFloat = isPadLayout ? 66 : 60
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isEditActionsExpanded.toggle()
            }
        } label: {
            Image(systemName: isEditActionsExpanded ? "xmark" : "square.and.pencil")
                .font(.appSystem(size: isPadLayout ? 28 : 26, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    conciseRaisedSurface(
                        cornerRadius: buttonSize / 2,
                        shadowRadius: isPadLayout ? 11 : 9,
                        offset: isPadLayout ? 5 : 4
                    )
                )
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize, height: buttonSize, alignment: .bottomTrailing)
    }

    private var gridSizeAdjustmentSheet: some View {
        GridSizeAdjustmentSheet(
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
    }

    private var editActionsFullscreenOverlay: some View {
        EditActionsFullscreenOverlay(
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
    }

    private var quickEditTrigger: some View {
        return Button {
            isQuickEditPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(L10n.quickEdit)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Image(systemName: "square.and.pencil")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
            }
            .padding(.horizontal, isPadLayout ? 20 : 16)
            .frame(height: isPadLayout ? 42 : 36)
            .background(
                conciseRaisedSurface(
                    cornerRadius: isPadLayout ? 21 : 18,
                    shadowRadius: isPadLayout ? 12 : 10,
                    offset: isPadLayout ? 6 : 5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var blackBoxModeTrigger: some View {
        Button {
            isBlackBoxModePresented = true
        } label: {
            HStack(spacing: 10) {
                Text(L10n.blackBoxMode)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Image(systemName: "cube.fill")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
            }
            .padding(.horizontal, isPadLayout ? 20 : 16)
            .frame(height: isPadLayout ? 42 : 36)
            .background(
                conciseRaisedSurface(
                    cornerRadius: isPadLayout ? 21 : 18,
                    shadowRadius: isPadLayout ? 12 : 10,
                    offset: isPadLayout ? 6 : 5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var boardCountdownTrigger: some View {
        Button {
            isBoardCountdownPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(boardCountdownText ?? L10n.setBoardCountdown)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: scaled(11, pad: 12), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)
            }
            .padding(.horizontal, isPadLayout ? 20 : 16)
            .frame(height: isPadLayout ? 38 : 32)
            .frame(minWidth: isPadLayout ? 152 : 124)
            .background(
                conciseRaisedSurface(
                    cornerRadius: isPadLayout ? 19 : 16,
                    shadowRadius: isPadLayout ? 12 : 10,
                    offset: isPadLayout ? 6 : 5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var boardCompletionProgressView: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NeumorphicColors.background)
                        .neumorphicConcave(radius: 10)
                        .overlay(
                            Capsule()
                                .stroke(NeumorphicColors.lightShadow.opacity(0.34), lineWidth: 0.8)
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    NeumorphicColors.accent.opacity(0.88),
                                    NeumorphicColors.accent
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: filledTaskCount == 0 ? 14 : max(14, proxy.size.width * completionProgress))
                        .shadow(color: NeumorphicColors.accent.opacity(0.28), radius: 10, x: 0, y: 4)
                        .opacity(filledTaskCount == 0 ? 0.28 : 1)
                }
            }
            .frame(height: 12)

            Text("\(completedTaskCount)/\(filledTaskCount)")
                .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(NeumorphicColors.accent)
        }
        .frame(height: 38)
        .frame(width: 180, alignment: .leading)
    }

private func boardSwitcherControls(contentWidth: CGFloat) -> some View {
    BoardSwitcherControlsView(
        boards: namedBoards,
        selectedBoardID: selectedBoardID,
        contentWidth: contentWidth,
        isPadLayout: isPadLayout,
        onSelectBoard: selectBoard,
        onBoardLongPress: beginBoardActions,
        onCreateBoard: beginCreateBoard
    )
}

private func beginBoardActions(for boardID: UUID) {
    focusedEditingResetForBoardActions()
    withAnimation(.easeInOut(duration: 0.2)) {
        boardActionSheetBoardID = boardID
    }
}

private func beginBoardRules(for boardID: UUID) {
    boardRulesTargetBoardID = boardID
    isBoardRulesPresented = true
}

private func templateImportSheetHeight(for gridSize: Int) -> CGFloat {
    switch gridSize {
    case ...3:
        return 540
    case 4:
        return 620
    default:
        return 700
    }
}

private func dismissBoardActions() {
    withAnimation(.easeInOut(duration: 0.2)) {
        boardActionSheetBoardID = nil
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

    persistNamedBoardsSnapshot()
    showCommonTasksToast(L10n.tr("Board rules saved", zhHans: "面板规则已保存", zhHant: "面板規則已儲存"))
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
            simulateNextDayReset: shouldSimulateNextDayBoardRuleResetInDebug,
            prepareStreakTest: shouldPrepareStreakTestInDebug,
            showCustomResetToast: shouldShowCustomResetDebugToastInDebug
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

private var isTileGestureDebugEnabled: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-DebugTileGestures")
#else
    false
#endif
}

private func debugTileGestureBlockers(source: String) {
#if DEBUG
    guard isTileGestureDebugEnabled else { return }
    let blockers = [
        isSidebarPresented ? "sidebar" : nil,
        isEditActionsExpanded ? "quick_edit_overlay" : nil,
        firstStepGuideOverlay != nil ? "starter_guide" : nil,
        isUpdatePromptPresented ? "update_prompt" : nil,
        boardActionSheetBoardID != nil ? "board_action_sheet" : nil,
        viewModel.expiredTaskEvent != nil ? "task_timeout" : nil,
        viewModel.expiredBoardCountdownEvent != nil ? "board_timeout" : nil,
        viewModel.scheduledTaskReplacementEvent != nil ? "scheduled_replace" : nil,
        timeoutDelayPickerContext != nil ? "timeout_delay_picker" : nil,
        isTemplateImportPreviewPresented ? "template_import_preview" : nil,
        isBoardRulesPresented ? "board_rules_sheet" : nil,
        isBoardCountdownPresented ? "board_countdown_sheet" : nil,
        isGridSizeSheetPresented ? "grid_size_sheet" : nil
    ].compactMap { $0 }

    let summary = blockers.isEmpty ? "none" : blockers.joined(separator: ",")
    print("[TileGestureDebug][Overlay][\(source)] \(summary)")
#else
    _ = source
#endif
}

private func boardName(for boardID: UUID) -> String {
    guard let board = namedBoards.first(where: { $0.id == boardID }) else {
        return L10n.boardDefaultName(1)
    }
    return board.name
}

private func requestDeleteBoard(_ boardID: UUID) {
    guard canDeleteBoardFromActions(boardID) else {
        showCommonTasksToast(boardDeleteBlockedMessage(for: boardID))
        return
    }

    pendingBoardDeleteID = boardID
    isBoardDeleteAlertPresented = true
}

private func canDeleteBoardFromActions(_ boardID: UUID) -> Bool {
    guard namedBoards.count > 1 else { return false }

    if !subscriptionManager.hasPremiumAccess,
       let firstBoardID = namedBoards.first?.id,
       boardID == firstBoardID {
        return false
    }

    return true
}

private func boardDeleteBlockedMessage(for boardID: UUID) -> String {
    if namedBoards.count <= 1 {
        return L10n.tr(
            "At least one board must remain.",
            zhHans: "至少需要保留一个棋盘。",
            zhHant: "至少需要保留一個棋盤。"
        )
    }

    if !subscriptionManager.hasPremiumAccess,
       let firstBoardID = namedBoards.first?.id,
       boardID == firstBoardID {
        return L10n.tr(
            "On Free plan, Board 1 cannot be deleted.",
            zhHans: "非会员模式下，Board 1 不能删除。",
            zhHant: "非會員模式下，Board 1 不能刪除。"
        )
    }

    return L10n.tr(
        "This board cannot be deleted right now.",
        zhHans: "当前无法删除该棋盘。",
        zhHant: "目前無法刪除該棋盤。"
    )
}

private func deleteBoard(_ boardID: UUID) {
    defer {
        pendingBoardDeleteID = nil
    }

    guard canDeleteBoardFromActions(boardID) else {
        return
    }

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

    showCommonTasksToast(L10n.tr("Board deleted", zhHans: "棋盘已删除", zhHant: "棋盤已刪除"))
}


private var pendingBoardDeleteMessage: String {
    let targetBoardName = pendingBoardDeleteID.flatMap { boardName(for: $0) } ?? ""
    return L10n.tr(
        "This will permanently delete \"\(targetBoardName)\" and its progress.",
        zhHans: "将永久删除「\(targetBoardName)」及其进度。",
        zhHant: "將永久刪除「\(targetBoardName)」及其進度。"
    )
}

@ViewBuilder
private func boardActionLayer(contentWidth: CGFloat, bottomInset: CGFloat) -> some View {
    if let boardActionSheetBoardID,
       let board = namedBoards.first(where: { $0.id == boardActionSheetBoardID }) {
        boardActionsOverlay(
            for: board,
            contentWidth: contentWidth,
            bottomInset: bottomInset
        )
        .transition(.opacity)
    }
}

private func boardActionsOverlay(
    for board: BingoBoardStore.NamedBoard,
    contentWidth: CGFloat,
    bottomInset: CGFloat
) -> some View {
    BoardActionsOverlayView(
        canDelete: canDeleteBoardFromActions(board.id),
        contentWidth: contentWidth,
        bottomInset: bottomInset,
        isPadLayout: isPadLayout,
        onDismiss: dismissBoardActions,
        onBoardRules: {
            dismissBoardActions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                beginBoardRules(for: board.id)
            }
        },
        onEdit: {
            dismissBoardActions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                beginRenameBoard(board.id)
            }
        },
        onDelete: {
            dismissBoardActions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                requestDeleteBoard(board.id)
            }
        }
    )
}

private func ensureBoardSwitcherLoaded() {
    guard let selectedBoard = boardManagementStore.loadIfNeeded(
        initialBoard: viewModel.makeSavedBoardSnapshot(),
        countdownEndsAt: viewModel.boardCountdownEndsAt
    ) else { return }

    viewModel.applySavedBoardSnapshot(
        selectedBoard.board,
        countdownEndsAt: selectedBoard.countdownEndsAt,
        referenceDate: .now
    )
    syncSelectedBoardSnapshotIfNeeded()
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
    }

    private func selectBoard(_ boardID: UUID) {
        guard selectedBoardID != boardID else { return }
        guard !isBoardSwitchAnimating else { return }

        isBoardSwitchAnimating = true
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            isBoardSwitchAnimating = false
        }
    }

    private func switchBoardBySwipe(horizontalTranslation: CGFloat, boardWidth: CGFloat) {
        guard namedBoards.count > 1 else { return }
        guard let currentBoardID = selectedBoardID ?? namedBoards.first?.id,
              let currentIndex = namedBoards.firstIndex(where: { $0.id == currentBoardID }) else {
            return
        }

        let targetIndex: Int?
        if horizontalTranslation <= -1 {
            let nextIndex = currentIndex + 1
            targetIndex = namedBoards.indices.contains(nextIndex) ? nextIndex : nil
        } else if horizontalTranslation >= 1 {
            let previousIndex = currentIndex - 1
            targetIndex = namedBoards.indices.contains(previousIndex) ? previousIndex : nil
        } else {
            targetIndex = nil
        }

        guard let targetIndex else { return }
        boardSwitchTransitionDirection = horizontalTranslation < 0 ? 1 : -1
        let offscreenDistance = boardWidth + 40
        let exitOffset = horizontalTranslation < 0 ? -offscreenDistance : offscreenDistance
        let enterOffset = -exitOffset

        withAnimation(.easeOut(duration: 0.16)) {
            boardSwitchAnimationOffsetX = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            selectBoard(namedBoards[targetIndex].id)
            boardSwitchAnimationOffsetX = enterOffset
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.1)) {
                boardSwitchAnimationOffsetX = 0
            }
        }
    }

    private func beginCreateBoard() {
        guard canCreateAdditionalBoard else {
            AnalyticsService.logPremiumBoardsLimitHit(currentBoardCount: namedBoards.count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                presentPremiumPaywall(source: "boards_limit")
            }
            return
        }

        createBoardNameDraft = L10n.boardDefaultName(namedBoards.count + 1)
        isCreateBoardAlertPresented = true
    }

    private func createBoard() {
        guard canCreateAdditionalBoard else {
            AnalyticsService.logPremiumBoardsLimitHit(currentBoardCount: namedBoards.count)
            return
        }

        let newBoard = boardManagementStore.createBoard(
            nameDraft: createBoardNameDraft,
            currentBoard: viewModel.makeSavedBoardSnapshot(),
            currentCountdownEndsAt: viewModel.boardCountdownEndsAt
        )

        viewModel.applySavedBoardSnapshot(
            newBoard.board,
            countdownEndsAt: nil,
            referenceDate: .now
        )
        createBoardNameDraft = ""
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
        if template.gridSize >= 5 && !subscriptionManager.hasPremiumAccess {
            AnalyticsService.logPremiumGrid5x5LimitHit(
                currentGridSize: viewModel.gridSize,
                source: "template_import"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                presentPremiumPaywall(source: "template_import")
            }
            templateImportFlowStore.dismissPreview()
            boardTemplateImportCoordinator.dismissPendingTemplate()
            return
        }

        let savedBoard = template.makeSavedBoard(referenceDate: .now)

        if createsNewBoard {
            let importedBoard = boardManagementStore.importTemplateAsNewBoard(
                nameDraft: template.normalizedTitle,
                savedBoard: savedBoard,
                currentBoard: viewModel.makeSavedBoardSnapshot(),
                currentCountdownEndsAt: viewModel.boardCountdownEndsAt
            )
            viewModel.applySavedBoardSnapshot(
                importedBoard.board,
                countdownEndsAt: nil,
                referenceDate: .now
            )
            templateImportFlowStore.dismissPreview()
            boardTemplateImportCoordinator.dismissPendingTemplate()
            templateImportFlowStore.logImportSuccess(template: template, createsNewBoard: createsNewBoard)
            showCommonTasksToast(L10n.templateImportSuccessCreated)
            return
        }

        guard let importedBoard = boardManagementStore.replaceSelectedBoardWithTemplate(
            nameDraft: template.normalizedTitle,
            savedBoard: savedBoard
        ) else {
            return
        }

        viewModel.applySavedBoardSnapshot(
            importedBoard.board,
            countdownEndsAt: nil,
            referenceDate: .now
        )
        templateImportFlowStore.dismissPreview()
        boardTemplateImportCoordinator.dismissPendingTemplate()
        templateImportFlowStore.logImportSuccess(template: template, createsNewBoard: createsNewBoard)
        showCommonTasksToast(L10n.templateImportSuccessReplaced)
    }

    private func beginRenameSelectedBoard() {
        guard let selectedNamedBoardIndex else { return }
        let board = namedBoards[selectedNamedBoardIndex]
        boardPendingRenameID = board.id
        renameBoardNameDraft = board.name
        isRenameBoardAlertPresented = true
    }

    private func beginRenameBoard(_ boardID: UUID) {
        guard let board = namedBoards.first(where: { $0.id == boardID }) else { return }
        boardPendingRenameID = boardID
        renameBoardNameDraft = board.name
        isRenameBoardAlertPresented = true
    }

    private func renameBoard() {
        defer {
            renameBoardNameDraft = ""
            boardPendingRenameID = nil
        }

        guard let boardPendingRenameID else {
            return
        }

        boardManagementStore.renameBoard(boardPendingRenameID, nameDraft: renameBoardNameDraft)
    }

    private func sanitizedBoardName(_ rawName: String, fallback: String) -> String {
        BoardManagementStore.sanitizedBoardName(rawName, fallback: fallback)
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

    private func homeStickerLayer(canvasSize: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack {
            if selectedStickerID != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedStickerID = nil
                        }
                    }
            }

            ForEach(pointsFeatureStore.homeStickerPlacements) { placement in
                EditableHomeStickerView(
                    placement: placement,
                    canvasSize: canvasSize,
                    isEditing: selectedStickerID == placement.id,
                    onSelect: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedStickerID = placement.id
                        }
                    },
                    onUpdate: { updatedPlacement in
                        pointsFeatureStore.updateStickerPlacement(updatedPlacement)
                    },
                    onDelete: {
                        pointsFeatureStore.deleteStickerPlacement(id: placement.id)
                        if selectedStickerID == placement.id {
                            selectedStickerID = nil
                        }
                    }
                )
            }
        }
    }

    private var headerView: some View {
        let iconSize: CGFloat = isPadLayout ? 52 : 48

        return HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isSidebarPresented.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.appSystem(size: scaled(20, pad: 23), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: iconSize, height: iconSize)
                    .background(
                        conciseFlatSurface(cornerRadius: iconSize / 2)
                    )
            }
            .buttonStyle(.plain)
            .offset(y: -20)

            Spacer()

            ZStack(alignment: .topTrailing) {
                Button {
                    isPointsFlowPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.appSystem(size: scaled(20, pad: 22), weight: .semibold))
                            .foregroundColor(NeumorphicColors.accent)
                            .symbolEffect(.bounce, value: pointsAnimationTrigger)

                        Text("\(availablePoints)")
                            .font(.appSystem(size: scaled(18, pad: 20), weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: availablePoints)
                    }
                    .padding(.horizontal, isPadLayout ? 22 : 20)
                    .frame(height: isPadLayout ? 52 : 48)
                    .background(
                        conciseFlatSurface(cornerRadius: isPadLayout ? 26 : 24)
                    )
                }
                .buttonStyle(.plain)
                .offset(y: -20)

                if let floatingPointsDelta {
                    Text(floatingPointsDelta > 0 ? "+\(floatingPointsDelta)" : "\(floatingPointsDelta)")
                        .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                        .foregroundColor(floatingPointsDelta > 0 ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(NeumorphicColors.background.opacity(0.96))
                                .shadow(color: NeumorphicColors.darkShadow.opacity(0.16), radius: 5, x: 2, y: 2)
                                .shadow(color: Color.white.opacity(0.72), radius: 4, x: -2, y: -2)
                        )
                        .offset(x: -4, y: isFloatingPointsDeltaVisible ? -30 : -8)
                        .opacity(isFloatingPointsDeltaVisible ? 1 : 0)
                }
            }
        }
    }

    private func boardMainContent(contentWidth: CGFloat, usesPadLayout: Bool) -> some View {
        VStack(spacing: 16) {
            boardSwitcherControls(contentWidth: contentWidth)
                .padding(.top, 14)

            ZStack {
                BingoBoardView(
                    viewModel: viewModel,
                    currentTime: countdownNow,
                    shouldShowCenterLongPressHint: firstStepGuideState == .finished,
                    onCellCompletionToggled: {
                        reconcileStickerOwnershipIfPointsInsufficient()
                    }
                )
            }
                .animation(.interactiveSpring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.15), value: selectedBoardID)
                .frame(width: contentWidth, height: contentWidth)
                .padding(.top, 8)
                .offset(x: boardDragTranslationX + boardSwitchAnimationOffsetX)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 28, coordinateSpace: .local)
                        .updating($boardDragTranslationX) { value, state, _ in
                            let horizontal = value.translation.width
                            let vertical = value.translation.height
                            guard abs(horizontal) > abs(vertical) else { return }
                            state = horizontal
                        }
                        .onEnded { value in
                            guard !isSidebarPresented,
                                  !isQuickEditPresented,
                                  !isEditActionsExpanded,
                                  !isBoardCountdownPresented,
                                  !isBoardRulesPresented,
                                  timeoutDelayPickerContext == nil,
                                  viewModel.expiredTaskEvent == nil,
                                  viewModel.expiredBoardCountdownEvent == nil,
                                  viewModel.scheduledTaskReplacementEvent == nil else {
                                return
                            }

                            let horizontal = value.translation.width
                            let vertical = value.translation.height
                            guard abs(horizontal) > abs(vertical) else { return }

                            let swipeThreshold: CGFloat = isPadLayout ? 96 : 68
                            guard abs(horizontal) >= swipeThreshold else { return }
                            switchBoardBySwipe(horizontalTranslation: horizontal, boardWidth: contentWidth)
                        }
                )

            HStack(alignment: .center, spacing: 12) {
                templateShareTrigger
                Spacer(minLength: 0)
                if boardCountdownText != nil {
                    boardCountdownTrigger
                        .offset(y: isPadLayout ? 4 : 3)
                } else {
                    Color.clear
                        .frame(width: isPadLayout ? 170 : 140, height: isPadLayout ? 38 : 32)
                }
                Spacer(minLength: 0)
                editActionsTrigger
            }
            .padding(.top, 10)
        }
        .frame(width: contentWidth)
        .padding(.top, 32)
        .offset(y: usesPadLayout ? -35 : 0)
    }

    private func sidebarView(width: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let sidebarShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 28,
            topTrailingRadius: 28,
            style: .continuous
        )

        return VStack(alignment: .leading, spacing: 0) {
            List {
                Section {
                    SidebarStreakHeroView(
                        streakDays: bingoStreakDays,
                        themeColor: activeThemeColor,
                        isPadLayout: isPadLayout
                    )
                    SidebarStreakGoalsView(
                        streakDays: bingoStreakDays,
                        goals: streakGoals,
                        themeColor: activeThemeColor,
                        isPadLayout: isPadLayout
                    )

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            isDiaryPresented = true
                        }
                    } label: {
                        SidebarMenuRow(icon: "calendar", title: L10n.bingoDiary, isPadLayout: isPadLayout)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isBlackBoxModePresented = true
                        }
                    } label: {
                        SidebarMenuRow(icon: "gamecontroller.fill", title: L10n.tr("2048", zhHans: "2048", zhHant: "2048"), isPadLayout: isPadLayout)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            isContactUsPresented = true
                        }
                    } label: {
                        SidebarMenuRow(icon: "envelope", title: L10n.contactUs, isPadLayout: isPadLayout)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isSettingsExpanded.toggle()
                        }
                    } label: {
                        SidebarMenuRow(
                            icon: "gearshape",
                            title: L10n.setting,
                            isPadLayout: isPadLayout,
                            trailingIcon: "chevron.down",
                            trailingRotation: isSettingsExpanded ? 0 : -90
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    SidebarProEntryRow(isPremiumMember: subscriptionManager.hasPremiumAccess) {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            presentPremiumPaywall(source: "sidebar_pro_entry")
                        }
                    }

                    if isSettingsExpanded {
                        SidebarToggleRowView(title: L10n.haptics, isOn: $isHapticsEnabled, isPadLayout: isPadLayout)
                            .padding(.top, 6)

                        SidebarToggleRowView(title: L10n.soundEffects, isOn: $isSoundEffectsEnabled, isPadLayout: isPadLayout)

                        SidebarDisclosureRow(title: L10n.homeWidget, isExpanded: isWidgetGuideExpanded, isPadLayout: isPadLayout) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                isWidgetGuideExpanded.toggle()
                            }
                        }

                        if isWidgetGuideExpanded {
                            SidebarWidgetGuideTextRow(isPadLayout: isPadLayout)
                        }

                        SidebarThemePickerTriggerRow(isPadLayout: isPadLayout) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                isThemePickerExpanded.toggle()
                            }
                        }

                        if isThemePickerExpanded {
                            SidebarThemePickerRow(themeRawValue: $themeRawValue)
                        }

#if DEBUG
                        SidebarPricingDebugInfoRow(
                            loadedProductIDs: subscriptionManager.loadedProductIDs,
                            missingProductIDs: subscriptionManager.missingProductIDs,
                            storefrontCountryCode: subscriptionManager.storefrontCountryCode,
                            storefrontID: subscriptionManager.storefrontID,
                            isPadLayout: isPadLayout
                        )
#endif

                        if AppFeatureFlags.isAccountEnabled, let profile = accountSession.profile {
                            SidebarAccountSection(
                                profile: profile,
                                errorMessage: accountSession.errorMessage,
                                themeColor: activeThemeColor,
                                isPadLayout: isPadLayout
                            ) {
                                accountSession.signOut()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    isSidebarPresented = false
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 72)
            .padding(.top, max(topInset, 22))
            .padding(.bottom, max(bottomInset, 12))
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            sidebarShape
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.75), radius: 14, x: 10, y: 0)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.8), radius: 8, x: -2, y: 0)
        }
        .overlay {
            sidebarShape
                .stroke(NeumorphicColors.background.opacity(0.95), lineWidth: 1.5)
        }
        .clipShape(sidebarShape)
        .overlay(alignment: .bottomLeading) {
            Text("v\(appShortVersion)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.35))
                .padding(.leading, 22)
                .padding(.bottom, max(bottomInset, 12) + 8)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onEnded { value in
                    guard isSidebarPresented else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) else { return }
                    let dismissThreshold: CGFloat = isPadLayout ? 72 : 54
                    guard horizontal <= -dismissThreshold else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isSidebarPresented = false
                    }
                }
        )
        .ignoresSafeArea(edges: .vertical)
    }

    private var gridControls: some View {
        let controlSize: CGFloat = isPadLayout ? 38 : 32
        let iconSize: CGFloat = isPadLayout ? 18 : 16

        return HStack {
            HStack(spacing: isPadLayout ? 14 : 11) {
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        viewModel.resizeGrid(to: viewModel.gridSize - 1)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.appSystem(size: iconSize, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            conciseRaisedSurface(
                                cornerRadius: controlSize / 2,
                                shadowRadius: isPadLayout ? 10 : 8,
                                offset: isPadLayout ? 5 : 4
                            )
                        )
                }
                .disabled(viewModel.gridSize <= 2)
                .buttonStyle(.plain)
                .opacity(viewModel.gridSize <= 2 ? 0.45 : 1)

                Text("\(viewModel.gridSize) × \(viewModel.gridSize)")
                    .font(.appSystem(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(width: isPadLayout ? 72 : 62)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation(.spring(response: 0.4)) {
                        resizeGridWithPremiumGate(
                            targetSize: viewModel.gridSize + 1,
                            source: "grid_controls"
                        )
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.appSystem(size: iconSize, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            conciseRaisedSurface(
                                cornerRadius: controlSize / 2,
                                shadowRadius: isPadLayout ? 10 : 8,
                                offset: isPadLayout ? 5 : 4
                            )
                        )
                }
                .disabled(viewModel.gridSize >= 5)
                .buttonStyle(.plain)
                .opacity(viewModel.gridSize >= 5 ? 0.45 : 1)
            }

            Spacer()

            HStack(spacing: isPadLayout ? 12 : 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isClearBoardConfirmationPresented = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.appSystem(size: isPadLayout ? 16 : 14, weight: .semibold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            conciseRaisedSurface(
                                cornerRadius: controlSize / 2,
                                shadowRadius: isPadLayout ? 10 : 8,
                                offset: isPadLayout ? 5 : 4
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.clearBoard)

                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        viewModel.shuffleBoard()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.appSystem(size: isPadLayout ? 17 : 15, weight: .semibold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            conciseRaisedSurface(
                                cornerRadius: controlSize / 2,
                                shadowRadius: isPadLayout ? 10 : 8,
                                offset: isPadLayout ? 5 : 4
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
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
