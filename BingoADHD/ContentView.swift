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
            .fullScreenCover(isPresented: $isQuickEditPresented) {
                QuickEditView(viewModel: viewModel) { message in
                    showCommonTasksToast(message)
                }
            }
            .fullScreenCover(isPresented: $isBlackBoxModePresented) {
                BlackBoxModeEntryView()
            }
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
            .fullScreenCover(isPresented: $isPointsFlowPresented) {
                PointsFlowPresenter(
                    isPadLayout: isPadLayout,
                    points: availablePoints,
                    totalPoints: viewModel.totalPoints,
                    pointsFeatureStore: pointsFeatureStore,
                    onAddStickerToHomeSuccess: {
                        isPointsFlowPresented = false
                        selectedStickerID = nil
                    }
                )
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
            .fullScreenCover(isPresented: $isDiaryPresented) {
                BingoDiaryScreen()
            }
            .fullScreenCover(isPresented: $isPremiumPaywallPresented) {
                PremiumPaywallView(entrySource: premiumPaywallSource)
            }
    }

    private func withBoardAlerts<Content: View>(content: Content) -> some View {
        content
            .alert(L10n.boardCreateTitle, isPresented: $isCreateBoardAlertPresented) {
                TextField(L10n.boardNamePlaceholder, text: $createBoardNameDraft)
                Button(L10n.cancel, role: .cancel) {
                    createBoardNameDraft = ""
                }
                Button(L10n.boardCreateAction) {
                    createBoard()
                }
            }
            .alert(L10n.boardRenameTitle, isPresented: $isRenameBoardAlertPresented) {
                TextField(L10n.boardNamePlaceholder, text: $renameBoardNameDraft)
                Button(L10n.cancel, role: .cancel) {
                    renameBoardNameDraft = ""
                    boardPendingRenameID = nil
                }
                Button(L10n.boardRenameAction) {
                    renameBoard()
                }
            }
            .alert(
                L10n.tr("Delete board?", zhHans: "删除棋盘？", zhHant: "刪除棋盤？"),
                isPresented: $isBoardDeleteAlertPresented
            ) {
                Button(L10n.cancel, role: .cancel) {
                    pendingBoardDeleteID = nil
                }
                Button(L10n.deleteConfirmationTitle, role: .destructive) {
                    guard let pendingBoardDeleteID else { return }
                    deleteBoard(pendingBoardDeleteID)
                }
            } message: {
                Text(pendingBoardDeleteMessage)
            }
            .alert(
                L10n.clearBoardConfirmationTitle,
                isPresented: $isClearBoardConfirmationPresented
            ) {
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.clearBoard, role: .destructive) {
                    viewModel.resetBoard()
                    showCommonTasksToast(L10n.boardClearedSuccess)
                }
            } message: {
                Text(L10n.clearBoardConfirmationMessage)
            }
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
            timeoutDialogBackdrop

            VStack(spacing: 20) {
                let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)
                let taskText = event.taskText.isEmpty ? L10n.task : event.taskText

                timeoutDialogCard(
                    headline: L10n.taskTimedOutHeadline(task: taskText, seconds: overtimeSeconds),
                    onClose: {
                        viewModel.expiredTaskEvent = nil
                    },
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
            timeoutDialogBackdrop

            VStack(spacing: 20) {
                let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)

                timeoutDialogCard(
                    headline: L10n.boardTimedOutHeadline(seconds: overtimeSeconds),
                    onClose: {
                        viewModel.expiredBoardCountdownEvent = nil
                    },
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
            timeoutDialogBackdrop

            VStack(spacing: 20) {
                scheduledTaskReplacementDialogCard(for: event)
            }
            .padding(.horizontal, 24)
        }
    }

    private var timeoutDialogBackdrop: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .blur(radius: 14)
            Color.black.opacity(0.62)
        }
        .ignoresSafeArea()
    }

    private func timeoutDialogCard(
        headline: String,
        onClose _: @escaping () -> Void,
        onPrimaryAction: @escaping () -> Void,
        onSecondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Image("ClockTimeout")
                .resizable()
                .scaledToFit()
                .frame(width: scaled(150, pad: 172), height: scaled(170, pad: 190))
                .padding(.top, -8)

            Text(headline)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.75)
                .padding(.top, 8)
                .padding(.horizontal, 14)

            Button(action: onPrimaryAction) {
                Text(L10n.markAsCompleted)
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: scaled(56, pad: 62))
                    .background(
                        Capsule(style: .continuous)
                            .fill(NeumorphicColors.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 36)

            Button(action: onSecondaryAction) {
                Text(L10n.tr("Task postpone", zhHans: "任务延期", zhHant: "任務延期"))
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: isPadLayout ? 460 : 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
        )
    }

    private func scheduledTaskReplacementDialogCard(
        for event: BingoViewModel.ScheduledTaskReplacementEvent
    ) -> some View {
        let headline = L10n.tr(
            "A preset task is ready. Replace the current task in this tile?",
            zhHans: "预设任务已到时间，是否替换当前格子任务？",
            zhHant: "預設任務已到時間，是否替換目前格子任務？"
        )

        let detail = L10n.tr(
            "Current: \(event.currentTaskText)\nPreset: \(event.presetTaskText)",
            zhHans: "当前：\(event.currentTaskText)\n预设：\(event.presetTaskText)",
            zhHant: "目前：\(event.currentTaskText)\n預設：\(event.presetTaskText)"
        )

        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    viewModel.dismissScheduledTaskReplacementPrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Image("ClockTimeout")
                .resizable()
                .scaledToFit()
                .frame(width: scaled(132, pad: 148), height: scaled(142, pad: 160))
                .padding(.top, -6)

            Text(headline)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.75)
                .padding(.top, 8)
                .padding(.horizontal, 14)

            Text(detail)
                .font(.appSystem(size: scaled(15, pad: 17), weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
                .padding(.horizontal, 14)

            Button {
                if let message = viewModel.resolveScheduledTaskReplacement(.replaceWithPreset, now: countdownNow) {
                    showCommonTasksToast(message)
                }
            } label: {
                Text(L10n.tr("Replace task", zhHans: "替换任务", zhHant: "替換任務"))
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: scaled(56, pad: 62))
                    .background(
                        Capsule(style: .continuous)
                            .fill(NeumorphicColors.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 32)

            Button {
                if let message = viewModel.resolveScheduledTaskReplacement(.keepCurrentTask, now: countdownNow) {
                    showCommonTasksToast(message)
                }
            } label: {
                Text(L10n.tr("Keep current", zhHans: "保留当前", zhHant: "保留目前"))
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: isPadLayout ? 460 : 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
        )
    }

    @ViewBuilder
    private var timeoutDelayPickerOverlay: some View {
        if timeoutDelayPickerContext != nil {
            ZStack(alignment: .bottom) {
                timeoutDialogBackdrop
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            timeoutDelayPickerContext = nil
                        }
                    }

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            applyTimeoutDelayPickerSelection()
                        } label: {
                            Text(L10n.tr("Apply", zhHans: "应用", zhHant: "套用"))
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(NeumorphicColors.accent)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    HStack(spacing: 10) {
                        timeoutPickerColumn(
                            title: L10n.hours,
                            selection: $timeoutDelayPickerHours,
                            values: Array(0...24),
                            formatter: { L10n.hourValue($0) }
                        )

                        timeoutPickerColumn(
                            title: L10n.minutes,
                            selection: $timeoutDelayPickerMinutes,
                            values: Array(1...60),
                            formatter: { L10n.minuteValue($0) }
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
                }
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 0)
            }
        }
    }

    private func timeoutPickerColumn(
        title: String,
        selection: Binding<Int>,
        values: [Int],
        formatter: @escaping (Int) -> String
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.66))

            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(formatter(value))
                        .foregroundColor(.black)
                        .tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(height: 90)
            .clipped()
            .tint(Color(red: 0.20, green: 0.14, blue: 0.09))
        }
        .frame(maxWidth: .infinity)
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
        let controlSize: CGFloat = isPadLayout ? 56 : 50
        let iconSize: CGFloat = isPadLayout ? 24 : 22

        return GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: isPadLayout ? 20 : 16) {
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
                        .font(.appSystem(size: scaled(30, pad: 36), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .frame(minWidth: isPadLayout ? 140 : 120)
                        .multilineTextAlignment(.center)

                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            resizeGridWithPremiumGate(
                                targetSize: viewModel.gridSize + 1,
                                source: "grid_size_sheet"
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
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height * 0.42)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, isPadLayout ? 28 : 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NeumorphicColors.background)
    }

    private var editActionsFullscreenOverlay: some View {
        ZStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 10)

                Color.black.opacity(0.6)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEditActionsExpanded = false
                }
            }

            VStack(spacing: isPadLayout ? 48 : 40) {
                editActionsTextButton(L10n.tr("Shuffle", zhHans: "随机排序")) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        viewModel.shuffleBoard()
                    }
                }

                editActionsTextButton(L10n.clearBoard) {
                    isClearBoardConfirmationPresented = true
                }

                editActionsTextButton(L10n.tr("Grid Size", zhHans: "格子大小")) {
                    isGridSizeSheetPresented = true
                }

                editActionsTextButton(L10n.quickEdit) {
                    isQuickEditPresented = true
                }

                editActionsTextButton(
                    L10n.cancel,
                    fontWeight: .semibold,
                    color: Color.white.opacity(0.55),
                    extraTopPadding: isPadLayout ? 14 : 8,
                    action: nil
                )
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editActionsTextButton(
        _ title: String,
        fontWeight: Font.Weight = .bold,
        color: Color = .white,
        extraTopPadding: CGFloat = 0,
        action: (() -> Void)?
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isEditActionsExpanded = false
            }
            if let action {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    action()
                }
            }
        } label: {
            Text(title)
                .font(.appSystem(size: scaled(28, pad: 38), weight: fontWeight, design: .rounded))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.top, extraTopPadding)
        }
        .buttonStyle(.plain)
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
    HStack(spacing: 10) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(namedBoards) { board in
                    let isSelected = board.id == selectedBoardID

                    Button {
                        selectBoard(board.id)
                    } label: {
                        Text(board.name)
                            .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(isSelected ? .white : NeumorphicColors.text)
                            .padding(.horizontal, 14)
                            .frame(height: isPadLayout ? 38 : 36)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? NeumorphicColors.accent : NeumorphicColors.background)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(
                                        isSelected ? NeumorphicColors.accent : NeumorphicColors.accent.opacity(0.22),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                beginBoardActions(for: board.id)
                            }
                    )
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button {
            beginCreateBoard()
        } label: {
            Text(L10n.tr("+ add board", zhHans: "+ 添加棋盘", zhHant: "+ 新增棋盤"))
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: isPadLayout ? 38 : 36)
                .background(
                    RoundedRectangle(cornerRadius: isPadLayout ? 19 : 18, style: .continuous)
                        .fill(conciseSurfaceColor)
                        .shadow(color: Color.white.opacity(0.7), radius: isPadLayout ? 8 : 6, x: -4, y: -4)
                        .shadow(color: NeumorphicColors.darkShadow.opacity(0.22), radius: isPadLayout ? 8 : 6, x: 4, y: 4)
                )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
    .frame(width: contentWidth, alignment: .leading)
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
    let canDelete = canDeleteBoardFromActions(board.id)

    return ZStack(alignment: .bottom) {
        Color.black.opacity(0.42)
            .ignoresSafeArea()
            .onTapGesture {
                dismissBoardActions()
            }

        VStack(spacing: 12) {
            Button {
                dismissBoardActions()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    beginBoardRules(for: board.id)
                }
            } label: {
                Text(L10n.tr("Board Rules", zhHans: "面板规则", zhHant: "面板規則"))
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NeumorphicColors.background)
                    )
            }
            .buttonStyle(.plain)

            Button {
                dismissBoardActions()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    beginRenameBoard(board.id)
                }
            } label: {
                Text(L10n.tr("Edit", zhHans: "编辑", zhHant: "編輯"))
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NeumorphicColors.background)
                    )
            }
            .buttonStyle(.plain)

            if canDelete {
                Button {
                    dismissBoardActions()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        requestDeleteBoard(board.id)
                    }
                } label: {
                    Text(L10n.deleteConfirmationTitle)
                        .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                        .foregroundColor(Color.red.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(NeumorphicColors.background)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: min(contentWidth, isPadLayout ? 460 : 353))
        .padding(.bottom, max(bottomInset, 14) + 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
                    sidebarStreakHero
                    sidebarStreakGoals

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            isDiaryPresented = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.bingoDiary)
                                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                        }
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
                        HStack(spacing: 14) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.tr("2048", zhHans: "2048", zhHant: "2048"))
                                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                        }
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
                        HStack(spacing: 14) {
                            Image(systemName: "envelope")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.contactUs)
                                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                        }
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
                        HStack(spacing: 14) {
                            Image(systemName: "gearshape")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.setting)
                                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                                .rotationEffect(.degrees(isSettingsExpanded ? 0 : -90))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    sidebarProEntryRow

                    if isSettingsExpanded {
                        sidebarToggleRow(title: L10n.haptics, isOn: $isHapticsEnabled)
                            .padding(.top, 6)

                        sidebarToggleRow(title: L10n.soundEffects, isOn: $isSoundEffectsEnabled)

                        widgetGuideRow

                        if isWidgetGuideExpanded {
                            widgetGuideTextRow
                        }

                        themePickerTriggerRow

                        if isThemePickerExpanded {
                            themePickerRow
                        }

#if DEBUG
                        pricingDebugInfoRow
#endif

                        if AppFeatureFlags.isAccountEnabled, let profile = accountSession.profile {
                            sidebarAccountSection(profile: profile)
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

    private func sidebarRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.appSystem(size: 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: 40, height: 40)
                .neumorphicConvex(radius: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Text(value)
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var sidebarStreakHero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(bingoStreakDays)")
                    .font(.appSystem(size: scaled(40, pad: 52), weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.72),
                                activeThemeColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 10)

                Text(L10n.dayStreak)
                    .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(activeThemeColor.opacity(0.24))
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)

                Image(systemName: "flame.fill")
                    .font(.appSystem(size: scaled(44, pad: 54), weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.42),
                                activeThemeColor.opacity(0.76),
                                activeThemeColor
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: activeThemeColor.opacity(0.34), radius: 10, x: 0, y: 6)
            }
            .frame(width: isPadLayout ? 90 : 78, height: isPadLayout ? 90 : 78)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 18, leading: 22, bottom: 10, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var sidebarStreakGoals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.streakGoals)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(streakGoals.enumerated()), id: \.offset) { index, goal in
                    streakGoalNode(goal: goal, previousGoal: index == 0 ? 0 : streakGoals[index - 1])

                    if index < streakGoals.count - 1 {
                        streakConnector(
                            from: goal,
                            to: streakGoals[index + 1]
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(activeThemeColor.opacity(0.5), lineWidth: 1)
                )
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 22, bottom: 14, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func streakConnector(from startGoal: Int, to endGoal: Int) -> some View {
        let fillProgress = streakConnectorProgress(from: startGoal, to: endGoal)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(NeumorphicColors.darkShadow.opacity(0.22))
                .frame(height: 8)

            GeometryReader { geo in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.45),
                                activeThemeColor
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                    .frame(width: geo.size.width * fillProgress)
            }
        }
    }

    private func streakGoalNode(goal: Int, previousGoal: Int) -> some View {
        let isAchieved = bingoStreakDays >= goal
        let isCurrent = !isAchieved && bingoStreakDays >= previousGoal

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isAchieved
                    ? activeThemeColor.opacity(0.18)
                    : NeumorphicColors.background.opacity(isCurrent ? 0.96 : 0.92)
                )
                .frame(width: 44, height: 48)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isAchieved ? activeThemeColor.opacity(0.72) : activeThemeColor.opacity(isCurrent ? 0.2 : 0.12))
                        .frame(width: 34, height: 10)
                        .padding(.top, 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isAchieved
                                ? activeThemeColor.opacity(0.9)
                                : activeThemeColor.opacity(isCurrent ? 0.62 : 0.42),
                            lineWidth: 1.2
                        )
                }
                .overlay(alignment: .top) {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                    }
                    .padding(.top, 7)
                }
                .overlay {
                    Rectangle()
                        .fill((isAchieved ? activeThemeColor : activeThemeColor).opacity(isCurrent ? 0.22 : 0.14))
                        .frame(width: 28, height: 1)
                        .offset(y: -6)
                }

            Text("\(goal)")
                .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(isAchieved ? activeThemeColor : NeumorphicColors.text.opacity(isCurrent ? 0.86 : 0.78))
                .padding(.top, 10)
        }
        .frame(width: 44, height: 48)
    }

    private func streakConnectorProgress(from startGoal: Int, to endGoal: Int) -> CGFloat {
        if bingoStreakDays >= endGoal {
            return 1
        }
        if bingoStreakDays <= startGoal {
            return 0
        }

        let progress = CGFloat(bingoStreakDays - startGoal) / CGFloat(max(endGoal - startGoal, 1))
        return min(max(progress, 0), 1)
    }

    private func sidebarMetricRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.appSystem(size: 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Text(value)
                    .font(.appSystem(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func sidebarToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SidebarGlassToggleStyle())
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var widgetGuideRow: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isWidgetGuideExpanded.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                Text(L10n.homeWidget)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .rotationEffect(.degrees(isWidgetGuideExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var widgetGuideTextRow: some View {
        Text(L10n.homeWidgetInstructions)
            .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.6))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 12, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var themePickerTriggerRow: some View {
        HStack(spacing: 14) {
            Text(L10n.themeColor)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isThemePickerExpanded.toggle()
                }
            } label: {
                Image("PickerButton")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var themePickerRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 12), count: 5), spacing: 12) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    guard themeRawValue != theme.rawValue else { return }
                    themeRawValue = theme.rawValue
                    UserDefaults(suiteName: BingoBoardStore.appGroupID)?.set(theme.rawValue, forKey: AppSettings.themeKey)
                    AnalyticsService.logThemeColorSelected(theme)
                    #if canImport(WidgetKit)
                    WidgetCenter.shared.reloadAllTimelines()
                    #endif
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .stroke(themeRawValue == theme.rawValue ? NeumorphicColors.text : .clear, lineWidth: 2)
                        }
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 4, leading: 76, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

#if DEBUG
    private var pricingDebugInfoRow: some View {
        let regionCode = AppLanguage.currentRegionCode
        let languageCode: String
        switch AppLanguage.current {
        case .english:
            languageCode = "en"
        case .simplifiedChinese:
            languageCode = "zh-Hans"
        case .traditionalChinese:
            languageCode = "zh-Hant"
        case .japanese:
            languageCode = "ja"
        }

        let loaded = subscriptionManager.loadedProductIDs.isEmpty ? "none" : subscriptionManager.loadedProductIDs.joined(separator: ", ")
        let missing = subscriptionManager.missingProductIDs.isEmpty ? "none" : subscriptionManager.missingProductIDs.joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 4) {
            Text("Debug")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.6))
            Text("Locale Region: \(regionCode)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Storefront: \(subscriptionManager.storefrontCountryCode) | \(subscriptionManager.storefrontID)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Language: \(languageCode)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Loaded Products: \(loaded)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text("Missing Products: \(missing)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 10, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
#endif

    private var sidebarProEntryRow: some View {
        let cardWidth: CGFloat = 254
        let cardHeight: CGFloat = 75
        let cornerRadius: CGFloat = 16
        let isPremiumMember = subscriptionManager.hasPremiumAccess
        let isEnglish = AppLanguage.current == .english
        let titleText = isPremiumMember ? L10n.proEntryMemberTitle : L10n.proEntryTitle
        let subtitleText = isPremiumMember ? L10n.proEntryMemberSubtitle : L10n.proEntrySubtitle
        let proTitleWidth: CGFloat = {
            if isPremiumMember {
                return isEnglish ? 172 : 132
            }
            return isEnglish ? 70 : 88
        }()
        let subtitleWidth: CGFloat = {
            if isPremiumMember {
                return isEnglish ? 214 : 188
            }
            return 168
        }()
        let proTitleCenterX: CGFloat = 27 + (proTitleWidth / 2)
        let proStarCenterX: CGFloat = {
            if isPremiumMember {
                return proTitleCenterX + (isEnglish ? 71 : 52)
            }
            return isEnglish ? 101.5 : 116.5
        }()
        let titleFrameWidth: CGFloat = isPremiumMember ? 220 : proTitleWidth
        let subtitleFrameWidth: CGFloat = isPremiumMember ? 224 : subtitleWidth
        let titlePositionX: CGFloat = isPremiumMember ? cardWidth / 2 : proTitleCenterX
        let subtitlePositionX: CGFloat = isPremiumMember ? cardWidth / 2 : 111
        let textAlignment: SwiftUI.Alignment = isPremiumMember ? .center : .leading
        let subtitleColor: Color = isPremiumMember ? .white : .white.opacity(0.82)
        let backgroundGradient = LinearGradient(
            colors: [Color(hex: "D3A375"), Color(hex: "DFAE7F")],
            startPoint: .top,
            endPoint: .bottom
        )

        return Button {
            isSidebarPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                presentPremiumPaywall(source: "sidebar_pro_entry")
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundGradient)

                Image("ProEntryCrown")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .frame(width: 140.42, height: 140.42)
                    .rotationEffect(.degrees(-24.92))
                    .blendMode(.screen)
                    .opacity(0.6)
                    .position(x: 103.258, y: 37.5)

                Path { path in
                    path.move(to: CGPoint(x: 4.19505, y: 0.39209))
                    path.addCurve(
                        to: CGPoint(x: 5.17148, y: 0.392089),
                        control1: CGPoint(x: 4.3106, y: -0.130696),
                        control2: CGPoint(x: 5.05593, y: -0.130697)
                    )
                    path.addLine(to: CGPoint(x: 5.58452, y: 2.26079))
                    path.addCurve(
                        to: CGPoint(x: 7.10574, y: 3.78201),
                        control1: CGPoint(x: 5.75247, y: 3.02063),
                        control2: CGPoint(x: 6.34591, y: 3.61406)
                    )
                    path.addLine(to: CGPoint(x: 8.97444, y: 4.19505))
                    path.addCurve(
                        to: CGPoint(x: 8.97444, y: 5.17148),
                        control1: CGPoint(x: 9.49723, y: 4.3106),
                        control2: CGPoint(x: 9.49723, y: 5.05593)
                    )
                    path.addLine(to: CGPoint(x: 7.10575, y: 5.58452))
                    path.addCurve(
                        to: CGPoint(x: 5.58452, y: 7.10574),
                        control1: CGPoint(x: 6.34591, y: 5.75247),
                        control2: CGPoint(x: 5.75247, y: 6.34591)
                    )
                    path.addLine(to: CGPoint(x: 5.17148, y: 8.97444))
                    path.addCurve(
                        to: CGPoint(x: 4.19505, y: 8.97444),
                        control1: CGPoint(x: 5.05593, y: 9.49723),
                        control2: CGPoint(x: 4.3106, y: 9.49723)
                    )
                    path.addLine(to: CGPoint(x: 3.78201, y: 7.10575))
                    path.addCurve(
                        to: CGPoint(x: 2.26079, y: 5.58452),
                        control1: CGPoint(x: 3.61406, y: 6.34591),
                        control2: CGPoint(x: 3.02063, y: 5.75247)
                    )
                    path.addLine(to: CGPoint(x: 0.39209, y: 5.17148))
                    path.addCurve(
                        to: CGPoint(x: 0.392089, y: 4.19505),
                        control1: CGPoint(x: -0.130696, y: 5.05593),
                        control2: CGPoint(x: -0.130697, y: 4.3106)
                    )
                    path.addLine(to: CGPoint(x: 2.26079, y: 3.78201))
                    path.addCurve(
                        to: CGPoint(x: 3.78201, y: 2.26079),
                        control1: CGPoint(x: 3.02063, y: 3.61406),
                        control2: CGPoint(x: 3.61406, y: 3.02063)
                    )
                    path.addLine(to: CGPoint(x: 4.19505, y: 0.39209))
                    path.closeSubpath()
                }
                .fill(Color.white)
                .frame(width: 13, height: 13)
                .position(x: proStarCenterX, y: 21.5)

                Text(titleText)
                    .font(OnboardingFonts.supporting(size: 20, weight: 600))
                    .foregroundColor(.white)
                    .frame(width: titleFrameWidth, height: 25, alignment: textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .position(x: titlePositionX, y: 28.5)

                Text(subtitleText)
                    .font(OnboardingFonts.supporting(size: 14, weight: 500))
                    .foregroundColor(subtitleColor)
                    .frame(width: subtitleFrameWidth, height: 18, alignment: textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .position(x: subtitlePositionX, y: 51)

                if !isPremiumMember {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))

                        Path { path in
                            path.move(to: CGPoint(x: 7.39049, y: 5.25716))
                            path.addLine(to: CGPoint(x: 10.1334, y: 8.00002))
                            path.addLine(to: CGPoint(x: 7.39049, y: 10.7429))
                        }
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 1.06667, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .frame(width: 16, height: 16)
                    .position(x: 227.5, y: 38)
                }
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 10, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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

    private func sidebarAccountSection(profile: AccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account")
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Text(profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                 ? profile.displayName!
                 : (profile.email ?? profile.uid))
                .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            if let email = profile.email, !email.isEmpty {
                Text(email)
                    .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
            }

            Text(profile.providerIDs.map(providerDisplayName).joined(separator: " · "))
                .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.52))

            Button {
                accountSession.signOut()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isSidebarPresented = false
                }
            } label: {
                Text("Sign Out")
                    .font(.appSystem(size: scaled(13.5, pad: 15.5), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(activeThemeColor.opacity(0.92))
                    )
            }
            .buttonStyle(.plain)

            if let errorMessage = accountSession.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.appSystem(size: scaled(11.5, pad: 13), weight: .medium, design: .rounded))
                    .foregroundColor(Color.red.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(activeThemeColor.opacity(0.24), lineWidth: 1)
                )
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 14, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func providerDisplayName(_ providerID: String) -> String {
        switch providerID {
        case "apple.com":
            return "Apple"
        case "google.com":
            return "Google"
        case "password":
            return "Email"
        default:
            return providerID
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
