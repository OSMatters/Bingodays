import SwiftUI
import AVFoundation
#if canImport(WidgetKit)
import WidgetKit
#endif

final class PointsSoundPlayer {
    static let shared = PointsSoundPlayer()

    private var player: AVAudioPlayer?

    func preload() {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard player == nil,
              let url = Bundle.main.url(forResource: "get1point", withExtension: "aiff") else { return }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            player = audioPlayer
        } catch {
            player = nil
        }
    }

    func play() {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

struct NineTenthsSheetContainer<Content: View>: View {
    let contentMaxWidth: CGFloat
    let content: Content

    init(contentMaxWidth: CGFloat = 920, @ViewBuilder content: () -> Content) {
        self.contentMaxWidth = contentMaxWidth
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(NeumorphicColors.text.opacity(0.22))
                        .frame(width: 54, height: 6)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    content
                        .frame(maxWidth: min(contentMaxWidth, geo.size.width - 32), maxHeight: .infinity)
                }
                .frame(
                    width: min(max(geo.size.width - 24, 0), contentMaxWidth + 32),
                    height: geo.size.height * 0.9,
                    alignment: .top
                )
                .background(NeumorphicColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: -2)
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = BingoViewModel()
    @State private var isSidebarPresented = false
    @State private var isSettingsExpanded = true
    @State private var isWidgetGuideExpanded = false
    @State private var isThemePickerExpanded = false
    @State private var isPointsDetailsPresented = false
    @State private var isBoardCountdownPresented = false
    @State private var selectedStickerID: UUID?
    @State private var isDiaryPresented = false
    @State private var isQuickEditPresented = false
    @State private var isBlackBoxModePresented = false
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
    @State private var isUpdatePromptPresented = false
    @State private var hasCheckedAppUpdateOnLaunch = false
    @State private var pendingUpdateInfo: AppUpdateInfo?
    @State private var stickerInventoryCounts = StickerStore.loadInventoryCounts()
    @State private var homeStickerPlacements = StickerStore.loadPlacements()
    @State private var customRewards = RewardStore.loadRewards()
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppSettings.soundEffectsEnabledKey) private var isSoundEffectsEnabled = true
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.sky.rawValue
    private let countdownTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var countdownNow = Date()
    private var bingoStreakDays: Int { BingoDiaryStore.consecutiveBingoDays() }
    private var streakGoals: [Int] { bingoStreakDays >= 60 ? [60, 180, 270, 365] : [7, 14, 30, 60] }
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .sky }
    private var activeThemeColor: Color { activeTheme.color }
    private var conciseSurfaceColor: Color { Color(hex: "EBF0F7") }
    private var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    private var releaseNotesItems: [String] {
        [
            L10n.updateItemQuickEdit,
            L10n.updateItemCountdown,
            L10n.updateItemPoints,
            L10n.updateItemLayout
        ]
    }
    private var spentStickerPoints: Int {
        stickerInventoryCounts.reduce(0) { partial, entry in
            partial + (entry.key.requiredPoints * entry.value)
        }
    }
    private var spentRewardPoints: Int {
        customRewards.reduce(0) { partial, reward in
            partial + reward.totalSpentPoints
        }
    }
    private var availablePoints: Int { max(viewModel.totalPoints - spentStickerPoints - spentRewardPoints, 0) }
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

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }

    var body: some View {
        GeometryReader { geo in
            let usesPadLayout = isPadLayout && geo.size.width >= 768
            let horizontalPadding: CGFloat = usesPadLayout ? 30 : 20
            let widthLimitedContent = geo.size.width - (horizontalPadding * 2)
            let heightLimitedContent = geo.size.height
                - max(geo.safeAreaInsets.top, 0)
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
                        .padding(.top, max(geo.safeAreaInsets.top, 0) + 12)

                    VStack(spacing: 16) {
                        gridControls

                        BingoBoardView(viewModel: viewModel, currentTime: countdownNow)
                            .frame(width: contentWidth, height: contentWidth)

                        HStack(spacing: 12) {
                            boardCountdownTrigger
                            Spacer(minLength: 0)
                            quickEditTrigger
                        }
                        .padding(.top, 4)

                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            blackBoxModeTrigger
                        }
                    }
                    .frame(width: contentWidth)
                    .padding(.top, 62)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                homeStickerLayer(
                    canvasSize: geo.size,
                    topInset: geo.safeAreaInsets.top,
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
                    topInset: geo.safeAreaInsets.top,
                    bottomInset: geo.safeAreaInsets.bottom
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .offset(x: isSidebarPresented ? 0 : -(usesPadLayout ? min(geo.size.width * 0.42, 420) : min(geo.size.width * 0.8, 320)))
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
                    dailyResetToast
                        .frame(maxWidth: min(contentWidth, 620), maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(geo.safeAreaInsets.top, 18) + 44)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if let commonTasksToastMessage, isCommonTasksToastVisible {
                    commonTasksToast(message: commonTasksToastMessage)
                        .frame(maxWidth: min(contentWidth, 520), maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(geo.safeAreaInsets.top, 18) + 96)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if isUpdatePromptPresented, pendingUpdateInfo != nil {
                    updatePromptOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if isClearBoardConfirmationPresented {
                    clearBoardConfirmationOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if let expiredTaskEvent = viewModel.expiredTaskEvent {
                    taskTimeoutOverlay(for: expiredTaskEvent)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if let expiredBoardEvent = viewModel.expiredBoardCountdownEvent {
                    boardTimeoutOverlay(for: expiredBoardEvent)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .fullScreenCover(isPresented: $isQuickEditPresented) {
            QuickEditView(viewModel: viewModel) { message in
                showCommonTasksToast(message)
            }
        }
        .fullScreenCover(isPresented: $isBlackBoxModePresented) {
            BlackBoxModeEntryView()
        }
        .sheet(isPresented: Binding(
            get: { !isPadLayout && isPointsDetailsPresented },
            set: { isPointsDetailsPresented = $0 }
        )) {
            PointsDetailSheet(
                points: availablePoints,
                inventoryCounts: stickerInventoryCounts,
                usedCounts: currentStickerUsageCounts,
                rewards: customRewards.filter { !$0.isArchived },
                onRedeem: { kind in
                    redeemSticker(kind)
                },
                onAddToHome: { kind in
                    addStickerToHome(kind)
                },
                onCreateReward: { title, requiredPoints in
                    createReward(title: title, requiredPoints: requiredPoints)
                },
                onUpdateReward: { reward in
                    updateReward(reward)
                },
                onDeleteReward: { reward in
                    archiveReward(reward)
                },
                onRedeemReward: { reward in
                    redeemReward(reward)
                }
            )
                .presentationDetents([.fraction(0.9)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: Binding(
            get: { isPadLayout && isPointsDetailsPresented },
            set: { isPointsDetailsPresented = $0 }
        )) {
            NineTenthsSheetContainer(contentMaxWidth: 960) {
                PointsDetailSheet(
                    points: availablePoints,
                    inventoryCounts: stickerInventoryCounts,
                    usedCounts: currentStickerUsageCounts,
                    rewards: customRewards.filter { !$0.isArchived },
                    onRedeem: { kind in
                        redeemSticker(kind)
                    },
                    onAddToHome: { kind in
                        addStickerToHome(kind)
                    },
                    onCreateReward: { title, requiredPoints in
                        createReward(title: title, requiredPoints: requiredPoints)
                    },
                    onUpdateReward: { reward in
                        updateReward(reward)
                    },
                    onDeleteReward: { reward in
                        archiveReward(reward)
                    },
                    onRedeemReward: { reward in
                        redeemReward(reward)
                    }
                )
            }
            .background(Color.clear)
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
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isDiaryPresented) {
            BingoDiaryScreen()
        }
        .onAppear {
            countdownNow = Date()
            viewModel.processExpiredCountdowns(now: countdownNow)
            viewModel.processExpiredTaskCountdowns(now: countdownNow)
            viewModel.processDailyCompletionReset(now: countdownNow)
            PAGCompletionView.preload(resourceName: "cat_bmp")
            PointsSoundPlayer.shared.preload()
            if !hasCheckedAppUpdateOnLaunch {
                hasCheckedAppUpdateOnLaunch = true
                Task {
                    await checkForAppUpdateIfNeeded()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            countdownNow = Date()
            viewModel.processExpiredCountdowns(now: countdownNow)
            viewModel.processExpiredTaskCountdowns(now: countdownNow)
            viewModel.processDailyCompletionReset(now: countdownNow)
        }
        .onChange(of: availablePoints) { oldValue, newValue in
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
            viewModel.processExpiredCountdowns(now: countdownNow)
            viewModel.processExpiredTaskCountdowns(now: countdownNow)
            viewModel.processDailyCompletionReset(now: countdownNow)
        }
        .onChange(of: viewModel.expiredTaskEvent?.id) { _, _ in
            taskTimeoutDelayMinutes = 10
        }
        .onChange(of: viewModel.expiredBoardCountdownEvent?.id) { _, _ in
            boardTimeoutDelayMinutes = 10
        }
    }

    private var shouldForceShowUpdatePromptInDebug: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    @MainActor
    private func checkForAppUpdateIfNeeded() async {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.bingoday.app"
        let countryCode = Locale.current.region?.identifier

        if let info = await AppUpdateService.fetchUpdateInfo(
            currentVersion: appShortVersion,
            bundleIdentifier: bundleIdentifier,
            countryCode: countryCode
        ) {
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
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isUpdatePromptPresented = true
        }
    }

    private func dismissUpdatePrompt() {
        withAnimation(.easeOut(duration: 0.2)) {
            isUpdatePromptPresented = false
        }
    }

    private func updatePromptItems(for info: AppUpdateInfo) -> [String] {
        if let notes = info.releaseNotes, !notes.isEmpty {
            let lines = notes
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                return Array(lines.prefix(4))
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
    private var updatePromptOverlay: some View {
        if let info = pendingUpdateInfo {
            ZStack {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissUpdatePrompt()
                    }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.updateWhatsNewTitle)
                            .font(.system(size: scaled(20, pad: 26), weight: .heavy, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(updatePromptItems(for: info).enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: scaled(11, pad: 13), weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: scaled(20, pad: 24), height: scaled(20, pad: 24))
                                    .background(
                                        Circle()
                                            .fill(NeumorphicColors.accent)
                                            .shadow(color: NeumorphicColors.accent.opacity(0.28), radius: 6, x: 0, y: 3)
                                    )
                                    .padding(.top, 1)

                                Text(item)
                                    .font(.system(size: scaled(13, pad: 16), weight: .medium, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            dismissUpdatePrompt()
                        } label: {
                            Text(L10n.updateSecondaryAction)
                                .font(.system(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.72))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.clear.neumorphicConvex(radius: 18))
                        }
                        .buttonStyle(.plain)

                        Button {
                            openAppStoreForUpdate()
                        } label: {
                            Text(L10n.updatePrimaryAction)
                                .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(NeumorphicColors.bingoAccent)
                                        .shadow(color: NeumorphicColors.bingoAccent.opacity(0.24), radius: 10, x: 0, y: 4)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
                .padding(22)
                .frame(maxWidth: isPadLayout ? 560 : 350)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(NeumorphicColors.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                        )
                        .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                        .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    private var dailyResetToast: some View {
        Text(L10n.newDayResetMessage)
            .font(.system(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.96))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(NeumorphicColors.accent.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.28), lineWidth: 1)
                    )
            )
            .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
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

    private func commonTasksToast(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: scaled(18, pad: 21), weight: .bold))
                .foregroundColor(.white.opacity(0.96))

            Text(message)
                .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.96))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NeumorphicColors.accent.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                )
        )
        .shadow(color: NeumorphicColors.darkShadow.opacity(0.22), radius: 16, x: 0, y: 8)
        .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
    }

    private var taskTimeoutDelayOptions: [Int] {
        [5, 10, 15, 20, 30, 45, 60, 90, 120]
    }

    @ViewBuilder
    private func taskTimeoutOverlay(for event: BingoViewModel.ExpiredTaskEvent) -> some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)

                Text(
                    L10n.taskTimedOutHeadline(
                        task: event.taskText.isEmpty ? L10n.task : event.taskText,
                        seconds: overtimeSeconds
                    )
                )
                .font(.system(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        if let message = viewModel.resolveExpiredTask(.markAsCompleted, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    } label: {
                        Text(L10n.markAsCompleted)
                            .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(NeumorphicColors.accent)
                                    .shadow(color: NeumorphicColors.accent.opacity(0.25), radius: 10, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(taskTimeoutDelayOptions, id: \.self) { minute in
                            Button(L10n.postponeTaskByMinutes(minute)) {
                                taskTimeoutDelayMinutes = minute
                                if let message = viewModel.resolveExpiredTask(.postpone(minutes: minute), now: countdownNow) {
                                    showCommonTasksToast(message)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(L10n.postponeTaskByMinutes(taskTimeoutDelayMinutes))
                                .font(.system(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.76))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: scaled(10, pad: 12), weight: .semibold))
                                .foregroundColor(NeumorphicColors.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color.clear.neumorphicConvex(radius: 17))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let message = viewModel.resolveExpiredTask(.abandon, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: scaled(15, pad: 17), weight: .bold))
                            .foregroundColor(NeumorphicColors.text.opacity(0.74))
                            .frame(width: 46, height: 42)
                            .background(Color.clear.neumorphicConvex(radius: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 380)
            .frame(minHeight: 196)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NeumorphicColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                    .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
            )
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func boardTimeoutOverlay(for event: BingoViewModel.ExpiredBoardCountdownEvent) -> some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)

                Text(L10n.boardTimedOutHeadline(seconds: overtimeSeconds))
                    .font(.system(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        if let message = viewModel.resolveExpiredBoardCountdown(.markAsCompleted, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    } label: {
                        Text(L10n.markAsCompleted)
                            .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(NeumorphicColors.accent)
                                    .shadow(color: NeumorphicColors.accent.opacity(0.25), radius: 10, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(taskTimeoutDelayOptions, id: \.self) { minute in
                            Button(L10n.postponeTaskByMinutes(minute)) {
                                boardTimeoutDelayMinutes = minute
                                if let message = viewModel.resolveExpiredBoardCountdown(.postpone(minutes: minute), now: countdownNow) {
                                    showCommonTasksToast(message)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(L10n.postponeTaskByMinutes(boardTimeoutDelayMinutes))
                                .font(.system(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.76))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: scaled(10, pad: 12), weight: .semibold))
                                .foregroundColor(NeumorphicColors.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color.clear.neumorphicConvex(radius: 17))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let message = viewModel.resolveExpiredBoardCountdown(.abandon, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: scaled(15, pad: 17), weight: .bold))
                            .foregroundColor(NeumorphicColors.text.opacity(0.74))
                            .frame(width: 46, height: 42)
                            .background(Color.clear.neumorphicConvex(radius: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 380)
            .frame(minHeight: 196)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NeumorphicColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                    .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
            )
            .padding(.horizontal, 24)
        }
    }

    private func conciseRaisedSurface(cornerRadius: CGFloat, shadowRadius: CGFloat, offset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(conciseSurfaceColor)
            .shadow(color: Color.white.opacity(0.72), radius: shadowRadius, x: -offset, y: -offset)
            .shadow(color: Color(hex: "CFD4DA").opacity(0.72), radius: shadowRadius, x: offset, y: offset)
    }

    private var quickEditTrigger: some View {
        return Button {
            isQuickEditPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(L10n.quickEdit)
                    .font(.system(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Image(systemName: "square.and.pencil")
                    .font(.system(size: scaled(13, pad: 15), weight: .bold))
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
                    .font(.system(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Image(systemName: "cube.fill")
                    .font(.system(size: scaled(13, pad: 15), weight: .bold))
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
                    .font(.system(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: scaled(11, pad: 12), weight: .semibold))
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
                .font(.system(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(NeumorphicColors.accent)
        }
        .frame(height: 38)
        .frame(width: 180, alignment: .leading)
    }

    private var boardCountdownText: String? {
        guard let endsAt = viewModel.boardCountdownEndsAt, endsAt > countdownNow else {
            return nil
        }

        let remainingSeconds = max(Int(endsAt.timeIntervalSince(countdownNow)), 0)
        let hours = min(remainingSeconds / 3600, 99)
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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

            ForEach(homeStickerPlacements) { placement in
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
                        updateStickerPlacement(updatedPlacement)
                    },
                    onDelete: {
                        deleteStickerPlacement(id: placement.id)
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
                    .font(.system(size: scaled(20, pad: 23), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: iconSize, height: iconSize)
                    .background(
                        conciseRaisedSurface(
                            cornerRadius: iconSize / 2,
                            shadowRadius: isPadLayout ? 14 : 12,
                            offset: isPadLayout ? 7 : 6
                        )
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            ZStack(alignment: .topTrailing) {
                Button {
                    isPointsDetailsPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: scaled(20, pad: 22), weight: .semibold))
                            .foregroundColor(NeumorphicColors.accent)
                            .symbolEffect(.bounce, value: pointsAnimationTrigger)

                        Text("\(availablePoints)")
                            .font(.system(size: scaled(18, pad: 20), weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: availablePoints)
                    }
                    .padding(.horizontal, isPadLayout ? 22 : 20)
                    .frame(height: isPadLayout ? 52 : 48)
                    .background(
                        conciseRaisedSurface(
                            cornerRadius: isPadLayout ? 26 : 24,
                            shadowRadius: isPadLayout ? 14 : 12,
                            offset: isPadLayout ? 7 : 6
                        )
                    )
                }
                .buttonStyle(.plain)

                if let floatingPointsDelta {
                    Text(floatingPointsDelta > 0 ? "+\(floatingPointsDelta)" : "\(floatingPointsDelta)")
                        .font(.system(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isDiaryPresented = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar")
                                .font(.system(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.bingoDiary)
                                .font(.system(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
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
                                .font(.system(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.setting)
                                .font(.system(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.system(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .rotationEffect(.degrees(isSettingsExpanded ? 0 : -90))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

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
        .ignoresSafeArea(edges: .vertical)
    }

    private func sidebarRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: 40, height: 40)
                .neumorphicConvex(radius: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Text(value)
                    .font(.system(size: scaled(16, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.72))
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
                    .font(.system(size: scaled(40, pad: 52), weight: .bold, design: .rounded))
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
                    .font(.system(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(activeThemeColor.opacity(0.24))
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)

                Image(systemName: "flame.fill")
                    .font(.system(size: scaled(44, pad: 54), weight: .bold))
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
                .font(.system(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
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
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.22), radius: 8, x: 4, y: 4)
                .shadow(color: Color.white.opacity(0.65), radius: 8, x: -3, y: -3)
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
                    : NeumorphicColors.background.opacity(isCurrent ? 0.99 : 0.98)
                )
                .frame(width: 44, height: 48)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isAchieved ? activeThemeColor.opacity(0.72) : NeumorphicColors.darkShadow.opacity(isCurrent ? 0.22 : 0.18))
                        .frame(width: 34, height: 10)
                        .padding(.top, 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isAchieved ? activeThemeColor.opacity(0.9) : NeumorphicColors.darkShadow.opacity(isCurrent ? 0.28 : 0.22), lineWidth: 1.2)
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
                        .fill((isAchieved ? activeThemeColor : NeumorphicColors.darkShadow).opacity(isCurrent ? 0.2 : 0.16))
                        .frame(width: 28, height: 1)
                        .offset(y: -6)
                }
                .shadow(
                    color: isAchieved ? activeThemeColor.opacity(0.18) : NeumorphicColors.darkShadow.opacity(isCurrent ? 0.1 : 0.08),
                    radius: 3,
                    x: 1.5,
                    y: 1.5
                )
                .shadow(
                    color: Color.white.opacity(0.72),
                    radius: 3,
                    x: -1.5,
                    y: -1.5
                )

            Text("\(goal)")
                .font(.system(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
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
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Text(value)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.72))
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
                .font(.system(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
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
                    .font(.system(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
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
            .font(.system(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
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
                .font(.system(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
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
                        .font(.system(size: iconSize, weight: .bold))
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
                    .font(.system(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(width: isPadLayout ? 72 : 62)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation(.spring(response: 0.4)) {
                        viewModel.resizeGrid(to: viewModel.gridSize + 1)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: iconSize, weight: .bold))
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
                        .font(.system(size: isPadLayout ? 16 : 14, weight: .semibold))
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
                        .font(.system(size: isPadLayout ? 17 : 15, weight: .semibold))
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

    @ViewBuilder
    private var clearBoardConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    isClearBoardConfirmationPresented = false
                }

            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Text(L10n.clearBoardConfirmationTitle)
                        .font(.system(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Text(L10n.clearBoardConfirmationMessage)
                        .font(.system(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button {
                        isClearBoardConfirmationPresented = false
                    } label: {
                        Text(L10n.cancel)
                            .font(.system(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.clear.neumorphicConvex(radius: 18))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isClearBoardConfirmationPresented = false
                        viewModel.resetBoard()
                        showCommonTasksToast(L10n.boardClearedSuccess)
                    } label: {
                        Text(L10n.clearBoard)
                            .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(NeumorphicColors.bingoAccent)
                                    .shadow(color: NeumorphicColors.bingoAccent.opacity(0.25), radius: 10, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NeumorphicColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                    .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
            )
            .padding(.horizontal, 28)
        }
    }

    private func redeemSticker(_ kind: StickerKind) {
        guard availablePoints >= kind.requiredPoints else { return }
        guard stickerInventoryCounts[kind] != 1 else { return }
        stickerInventoryCounts[kind] = 1
        StickerStore.saveInventoryCounts(stickerInventoryCounts)
        AnalyticsService.logStickerRedeemed(kind)
    }

    private func addStickerToHome(_ kind: StickerKind) {
        guard availableStickerCount(for: kind) > 0 else { return }

        let placement = HomeStickerPlacement(
            kind: kind,
            xRatio: kind.defaultPlacement.xRatio,
            yRatio: kind.defaultPlacement.yRatio
        )
        homeStickerPlacements.append(placement)
        StickerStore.savePlacements(homeStickerPlacements)
        isPointsDetailsPresented = false
        selectedStickerID = nil
    }

    private func updateStickerPlacement(_ placement: HomeStickerPlacement) {
        guard let index = homeStickerPlacements.firstIndex(where: { $0.id == placement.id }) else { return }
        homeStickerPlacements[index] = placement
        StickerStore.savePlacements(homeStickerPlacements)
    }

    private func deleteStickerPlacement(id: UUID) {
        homeStickerPlacements.removeAll { $0.id == id }
        StickerStore.savePlacements(homeStickerPlacements)
        if selectedStickerID == id {
            selectedStickerID = nil
        }
    }

    private var currentStickerUsageCounts: [StickerKind: Int] {
        homeStickerPlacements.reduce(into: [:]) { partial, placement in
            partial[placement.kind, default: 0] += 1
        }
    }

    private func availableStickerCount(for kind: StickerKind) -> Int {
        max((stickerInventoryCounts[kind] ?? 0) - (currentStickerUsageCounts[kind] ?? 0), 0)
    }

    private func createReward(title: String, requiredPoints: Int) {
        let trimmedTitle = String(title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPoints = min(max(requiredPoints, 1), 9_999)
        guard !trimmedTitle.isEmpty else { return }

        customRewards.append(
            CustomReward(
                title: trimmedTitle,
                requiredPoints: normalizedPoints
            )
        )
        RewardStore.saveRewards(customRewards)
    }

    private func updateReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        let trimmedTitle = String(reward.title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        customRewards[index].title = trimmedTitle
        customRewards[index].requiredPoints = min(max(reward.requiredPoints, 1), 9_999)
        RewardStore.saveRewards(customRewards)
    }

    private func archiveReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        customRewards[index].isArchived = true
        RewardStore.saveRewards(customRewards)
    }

    private func redeemReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        let requiredPoints = customRewards[index].requiredPoints
        guard availablePoints >= requiredPoints else { return }

        customRewards[index].redemptionCount += 1
        customRewards[index].totalSpentPoints += requiredPoints
        RewardStore.saveRewards(customRewards)
    }
}

private struct BlackBoxModeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenBlackBoxRules") private var hasSeenBlackBoxRules = false
    @State private var showRulesAlert = false

    @State private var selectedTheme: BlackBoxTheme = .health
    @State private var selectedGridSize: Int = 4
    @State private var gameState = BlackBoxGameState(theme: .health, size: 4)

    var body: some View {
        ZStack {
            BlackBoxClassicPalette.background.ignoresSafeArea()

            BlackBoxModeGameView(
                game: $gameState,
                selectedTheme: $selectedTheme,
                selectedGridSize: $selectedGridSize,
                onRestart: {
                    gameState = BlackBoxGameState(theme: selectedTheme, size: selectedGridSize)
                },
                onBackToIntro: {
                    dismiss()
                },
                onShowRules: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showRulesAlert = true
                    }
                }
            )

            if showRulesAlert {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRulesAlert = false
                        }
                    }

                VStack(spacing: 20) {
                    Text("玩法说明")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(BlackBoxClassicPalette.text)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("• 选择主题，系统将按照主题生成对应的任务")
                        Text("• 点击格子完成任务，完成的格子任务可按照2048规则滑动合并")
                        Text("• 看看你最后能获得多少分吧！")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRulesAlert = false
                        }
                    } label: {
                        Text("知道了")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                    .fill(BlackBoxClassicPalette.restart)
                                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.4), radius: 4, x: 0, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                        .fill(BlackBoxClassicPalette.background)
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                )
                .padding(.horizontal, 40)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .onAppear {
            if !hasSeenBlackBoxRules {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showRulesAlert = true
                }
                hasSeenBlackBoxRules = true
            }
        }
    }
}

private enum BlackBoxDirection {
    case up
    case down
    case left
    case right
}

private enum BlackBoxTheme: String, CaseIterable, Identifiable {
    case health
    case focus
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health:
            return L10n.blackBoxModeHealthTheme
        case .focus:
            return L10n.blackBoxModeFocusTheme
        case .home:
            return L10n.blackBoxModeHomeTheme
        }
    }

    var taskDefinitions: [BlackBoxTaskDefinition] {
        switch self {
        case .health:
            return [
                BlackBoxTaskDefinition(
                    id: "health_drink_water",
                    baseScore: 2,
                    baseTitle: L10n.tr("Drink 1 cup of water", zhHans: "喝1杯水"),
                    maxCount: 8
                ),
                BlackBoxTaskDefinition(
                    id: "health_breakfast",
                    baseScore: 2,
                    baseTitle: L10n.tr("Eat breakfast", zhHans: "吃早餐"),
                    maxCount: 1
                ),
                BlackBoxTaskDefinition(
                    id: "health_walk_10",
                    baseScore: 4,
                    baseTitle: L10n.tr("Walk 10 minutes", zhHans: "散步10分钟"),
                    maxCount: 3
                ),
                BlackBoxTaskDefinition(
                    id: "health_stretch_10",
                    baseScore: 4,
                    baseTitle: L10n.tr("Stretch 10 minutes", zhHans: "拉伸10分钟"),
                    maxCount: 2
                ),
                BlackBoxTaskDefinition(
                    id: "health_sleep_2330",
                    baseScore: 4,
                    baseTitle: L10n.tr("Sleep before 23:30", zhHans: "23:30前睡觉"),
                    maxCount: 1
                ),
                BlackBoxTaskDefinition(
                    id: "health_fruit",
                    baseScore: 2,
                    baseTitle: L10n.tr("Eat fruit", zhHans: "吃水果"),
                    maxCount: 2
                )
            ]
        case .focus:
            return [
                BlackBoxTaskDefinition(id: "focus_pomodoro", baseScore: 2, baseTitle: L10n.tr("Pomodoro 25 min", zhHans: "番茄专注25分钟"), maxCount: 4),
                BlackBoxTaskDefinition(id: "focus_read", baseScore: 2, baseTitle: L10n.tr("Read 10 pages", zhHans: "阅读10页"), maxCount: 3),
                BlackBoxTaskDefinition(id: "focus_plan", baseScore: 4, baseTitle: L10n.tr("Write task plan", zhHans: "写任务计划"), maxCount: 1),
                BlackBoxTaskDefinition(id: "focus_finish_one", baseScore: 4, baseTitle: L10n.tr("Finish one small task", zhHans: "完成一个小任务"), maxCount: 3),
                BlackBoxTaskDefinition(id: "focus_no_social", baseScore: 4, baseTitle: L10n.tr("No social app 30 min", zhHans: "30分钟不刷社媒"), maxCount: 2)
            ]
        case .home:
            return [
                BlackBoxTaskDefinition(id: "home_trash", baseScore: 2, baseTitle: L10n.tr("Take out trash", zhHans: "倒垃圾"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_dishes", baseScore: 2, baseTitle: L10n.tr("Wash dishes", zhHans: "洗碗"), maxCount: 2),
                BlackBoxTaskDefinition(id: "home_wipe", baseScore: 2, baseTitle: L10n.tr("Wipe desk", zhHans: "擦桌子"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_laundry", baseScore: 4, baseTitle: L10n.tr("Laundry 1 cycle", zhHans: "洗衣1轮"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_drawer", baseScore: 4, baseTitle: L10n.tr("Organize one drawer", zhHans: "整理一个抽屉"), maxCount: 2)
            ]
        }
    }

    var definitionMap: [String: BlackBoxTaskDefinition] {
        Dictionary(uniqueKeysWithValues: taskDefinitions.map { ($0.id, $0) })
    }

    func mergedTitle(score: Int) -> String {
        title
    }
}

private enum BlackBoxClassicPalette {
    static let edgeRadius: CGFloat = 2
    static let background = Color(hex: "FAF8EF")
    static let board = Color(hex: "BBADA0")
    static let boardShadow = Color(hex: "A89C90")
    static let boardHighlight = Color(hex: "D7CCBF")
    static let emptyTile = Color(hex: "CDC1B4")
    static let text = Color(hex: "776E65")
    static let darkText = Color(hex: "F9F6F2")
    static let restart = Color(hex: "8F7A66")
}

private struct BlackBoxTaskDefinition: Identifiable, Hashable {
    let id: String
    let baseScore: Int
    let baseTitle: String
    let maxCount: Int

    init(id: String, baseScore: Int, baseTitle: String, maxCount: Int = 99) {
        self.id = id
        self.baseScore = baseScore
        self.baseTitle = baseTitle
        self.maxCount = maxCount
    }

    func title(forCount count: Int) -> String {
        guard count > 1 else { return baseTitle }
        switch id {
        case "health_drink_water":
            return L10n.tr("Drink \(count) cups of water", zhHans: "喝\(count)杯水")
        default:
            return L10n.tr("\(baseTitle) x\(count)", zhHans: "\(baseTitle) x\(count)")
        }
    }
}

private struct BlackBoxTile: Identifiable, Equatable {
    var id = UUID()
    var displayTitle: String
    var score: Int
    var isCompleted: Bool
    var components: [String: Int]
}

private struct BlackBoxLineResult {
    let line: [BlackBoxTile?]
    let mergeCount: Int
}

private struct BlackBoxGameSnapshot {
    let board: [[BlackBoxTile?]]
    let moveCount: Int
    let mergeCount: Int
    let bingoCount: Int
    let isGameOver: Bool
}

private struct BlackBoxGameState {
    let theme: BlackBoxTheme
    let size: Int
    var board: [[BlackBoxTile?]]
    var moveCount: Int
    var mergeCount: Int
    var bingoCount: Int
    var isGameOver: Bool
    var history: [BlackBoxGameSnapshot]

    init(theme: BlackBoxTheme, size: Int) {
        self.theme = theme
        self.size = size
        self.board = Array(repeating: Array(repeating: nil, count: size), count: size)
        self.moveCount = 0
        self.mergeCount = 0
        self.bingoCount = 0
        self.isGameOver = false
        self.history = []
        spawnRandomTile()
        spawnRandomTile()
    }

    mutating func toggleCompletion(row: Int, col: Int) {
        guard row >= 0, row < size, col >= 0, col < size else { return }
        guard var tile = board[row][col] else { return }
        pushHistory()
        let wasCompleted = tile.isCompleted
        tile.isCompleted.toggle()
        board[row][col] = tile
        if !wasCompleted, tile.isCompleted {
            spawnStrategicTile(preferredScore: tile.score)
        }
        isGameOver = !hasMoveAvailable()
    }

    mutating func undoLastAction() {
        guard let snapshot = history.popLast() else { return }
        board = snapshot.board
        moveCount = snapshot.moveCount
        mergeCount = snapshot.mergeCount
        bingoCount = snapshot.bingoCount
        isGameOver = snapshot.isGameOver
    }

    mutating func swipe(_ direction: BlackBoxDirection) {
        guard !isGameOver else { return }

        var nextBoard = board
        var mergedTiles = 0

        switch direction {
        case .left, .right:
            for row in 0..<size {
                let processed = processLine(board[row], reverse: direction == .right)
                nextBoard[row] = processed.line
                mergedTiles += processed.mergeCount
            }
        case .up, .down:
            for col in 0..<size {
                let line = (0..<size).map { board[$0][col] }
                let processed = processLine(line, reverse: direction == .down)
                for row in 0..<size {
                    nextBoard[row][col] = processed.line[row]
                }
                mergedTiles += processed.mergeCount
            }
        }

        guard nextBoard != board else { return }

        pushHistory()
        board = nextBoard
        moveCount += 1
        mergeCount += mergedTiles
        bingoCount += mergedTiles
        spawnStrategicTile()
        isGameOver = !hasMoveAvailable()
    }

    mutating func refreshPendingTiles() {
        var targets: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size {
                guard let tile = board[row][col] else { continue }
                // Keep merged or completed tiles untouched.
                if tile.isCompleted || tile.components.count > 1 {
                    continue
                }
                targets.append((row, col))
            }
        }

        guard !targets.isEmpty else { return }
        pushHistory()

        for target in targets {
            guard let tile = board[target.row][target.col] else { continue }
            let task = taskDefinition(forScore: tile.score)
            board[target.row][target.col] = BlackBoxTile(
                displayTitle: task.title(forCount: 1),
                score: task.baseScore,
                isCompleted: false,
                components: [task.id: 1]
            )
        }
        isGameOver = !hasMoveAvailable()
    }

    private mutating func spawnRandomTile() {
        spawnStrategicTile(preferredScore: theme.taskDefinitions.map(\.baseScore).min())
    }

    private mutating func spawnStrategicTile(preferredScore: Int? = nil) {
        let emptyCoordinates = allEmptyCoordinates()
        guard !emptyCoordinates.isEmpty else { return }

        let targetScore = chooseSpawnScore(preferredScore: preferredScore)
        let preferredCoordinates = preferredScore.map { preferredSpawnCoordinates(for: $0) } ?? []
        let targetCoordinates = preferredCoordinates.isEmpty ? emptyCoordinates : preferredCoordinates
        guard let randomCoordinate = targetCoordinates.randomElement() else { return }

        let task = taskDefinition(forScore: targetScore)
        board[randomCoordinate.row][randomCoordinate.col] = BlackBoxTile(
            displayTitle: task.title(forCount: 1),
            score: task.baseScore,
            isCompleted: false,
            components: [task.id: 1]
        )
    }

    private func allEmptyCoordinates() -> [(row: Int, col: Int)] {
        var result: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size where board[row][col] == nil {
                result.append((row, col))
            }
        }
        return result
    }

    private func hasMoveAvailable() -> Bool {
        if board.flatMap(\.self).contains(where: { $0 == nil }) {
            return true
        }

        for row in 0..<size {
            for col in 0..<size {
                guard let current = board[row][col] else { continue }
                if row + 1 < size,
                   let nextRow = board[row + 1][col],
                   nextRow.score == current.score,
                   current.isCompleted,
                   nextRow.isCompleted {
                    return true
                }
                if col + 1 < size,
                   let nextCol = board[row][col + 1],
                   nextCol.score == current.score,
                   current.isCompleted,
                   nextCol.isCompleted {
                    return true
                }
            }
        }

        return false
    }

    private mutating func pushHistory() {
        history.append(
            BlackBoxGameSnapshot(
                board: board,
                moveCount: moveCount,
                mergeCount: mergeCount,
                bingoCount: bingoCount,
                isGameOver: isGameOver
            )
        )
        if history.count > 24 {
            history.removeFirst(history.count - 24)
        }
    }

    private func chooseSpawnScore(preferredScore: Int? = nil) -> Int {
        let completedCounts = completedScoreCounts()
        if let preferredScore, completedCounts[preferredScore] != nil {
            return preferredScore
        }

        if let bestExisting = completedCounts
            .sorted(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            })
            .first?
            .key {
            return bestExisting
        }

        return theme.taskDefinitions.map(\.baseScore).min() ?? 2
    }

    private func completedScoreCounts() -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for row in board {
            for case let tile? in row where tile.isCompleted {
                counts[tile.score, default: 0] += 1
            }
        }
        return counts
    }

    private func preferredSpawnCoordinates(for score: Int) -> [(row: Int, col: Int)] {
        var coordinates: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size {
                guard let tile = board[row][col], tile.isCompleted, tile.score == score else { continue }
                coordinates.append(contentsOf: adjacentEmptyCoordinates(row: row, col: col))
            }
        }
        return uniqueCoordinates(coordinates)
    }

    private func adjacentEmptyCoordinates(row: Int, col: Int) -> [(row: Int, col: Int)] {
        var result: [(row: Int, col: Int)] = []
        let neighbors = [
            (row - 1, col),
            (row + 1, col),
            (row, col - 1),
            (row, col + 1)
        ]

        for neighbor in neighbors where neighbor.0 >= 0 && neighbor.0 < size && neighbor.1 >= 0 && neighbor.1 < size {
            if board[neighbor.0][neighbor.1] == nil {
                result.append(neighbor)
            }
        }

        return result
    }

    private func uniqueCoordinates(_ coordinates: [(row: Int, col: Int)]) -> [(row: Int, col: Int)] {
        var seen = Set<String>()
        var result: [(row: Int, col: Int)] = []
        for coordinate in coordinates {
            let key = "\(coordinate.row)-\(coordinate.col)"
            if seen.insert(key).inserted {
                result.append(coordinate)
            }
        }
        return result
    }

    private func taskDefinition(forScore score: Int) -> BlackBoxTaskDefinition {
        let boardTaskCounts = boardTaskCounts()
        let matches = theme.taskDefinitions.filter { $0.baseScore == score }
        let available = matches.filter { def in
            let currentCount = boardTaskCounts[def.id] ?? 0
            return currentCount < def.maxCount
        }
        return available.randomElement() ?? matches.randomElement() ?? theme.taskDefinitions.first ?? BlackBoxTaskDefinition(
            id: "fallback",
            baseScore: score,
            baseTitle: L10n.tr("Task", zhHans: "任务")
        )
    }

    private func boardTaskCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in board {
            for case let tile? in row {
                for (taskID, count) in tile.components {
                    counts[taskID, default: 0] += count
                }
            }
        }
        return counts
    }

    private func processLine(_ line: [BlackBoxTile?], reverse: Bool) -> BlackBoxLineResult {
        let normalizedLine = reverse ? Array(line.reversed()) : line
        let compacted = normalizedLine.compactMap { $0 }

        var mergedLine: [BlackBoxTile] = []
        var mergeCount = 0
        var index = 0

        while index < compacted.count {
            if index + 1 < compacted.count {
                let first = compacted[index]
                let second = compacted[index + 1]
                if first.score == second.score, first.isCompleted, second.isCompleted {
                    let mergedComponents = mergeComponents(first.components, second.components)
                    let mergedScore = first.score * 2
                    mergedLine.append(
                        BlackBoxTile(
                            displayTitle: titleForMergedTile(components: mergedComponents, score: mergedScore),
                            score: mergedScore,
                            isCompleted: true,
                            components: mergedComponents
                        )
                    )
                    mergeCount += 1
                    index += 2
                    continue
                }
            }

            mergedLine.append(compacted[index])
            index += 1
        }

        var filledLine: [BlackBoxTile?] = mergedLine.map { $0 }
        while filledLine.count < size {
            filledLine.append(nil)
        }

        if reverse {
            filledLine.reverse()
        }

        return BlackBoxLineResult(line: filledLine, mergeCount: mergeCount)
    }

    private func mergeComponents(_ lhs: [String: Int], _ rhs: [String: Int]) -> [String: Int] {
        var merged = lhs
        for (key, value) in rhs {
            merged[key, default: 0] += value
        }
        return merged
    }

    private func titleForMergedTile(components: [String: Int], score: Int) -> String {
        if components.count == 1, let (taskID, count) = components.first, let definition = theme.definitionMap[taskID] {
            return definition.title(forCount: count)
        }
        return theme.mergedTitle(score: score)
    }
}

private struct BlackBoxHistoryRecord: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let themeRawValue: String
    let gridSize: Int
    let score: Int
    let moves: Int
    let merges: Int
    let completedTiles: Int

    var themeTitle: String {
        BlackBoxTheme(rawValue: themeRawValue)?.title ?? themeRawValue
    }
}

private enum BlackBoxHistoryStore {
    private static let key = "blackBox2048HistoryRecords.v1"

    static func load() -> [BlackBoxHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BlackBoxHistoryRecord].self, from: data)) ?? []
    }

    static func append(_ record: BlackBoxHistoryRecord, keep maxCount: Int = 50) {
        var records = load()
        records.insert(record, at: 0)
        if records.count > maxCount {
            records.removeLast(records.count - maxCount)
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct BlackBoxModeGameView: View {
    private enum ConfirmAction: Identifiable {
        case exit
        case restart
        case switchTheme(BlackBoxTheme)
        case showRules
        case refreshPendingTasks

        var id: String {
            switch self {
            case .exit:
                return "exit"
            case .restart:
                return "restart"
            case .switchTheme(let theme):
                return "theme-\(theme.rawValue)"
            case .showRules:
                return "rules"
            case .refreshPendingTasks:
                return "refresh-pending"
            }
        }

        var title: String {
            switch self {
            case .exit:
                return "确认退出?"
            case .restart:
                return "确认重开?"
            case .switchTheme(let theme):
                return "切换到\(theme.title)?"
            case .showRules:
                return "查看玩法说明?"
            case .refreshPendingTasks:
                return "刷新未完成任务?"
            }
        }

        var message: String {
            switch self {
            case .exit:
                return "会离开 2048 模式，当前棋盘进度不会保留。"
            case .restart:
                return "会清空当前棋盘并重新生成任务。"
            case .switchTheme:
                return "会切换主题并重置当前棋盘。"
            case .showRules:
                return "将打开玩法说明弹窗。"
            case .refreshPendingTasks:
                return "仅刷新未完成且未合并的任务格。"
            }
        }

        var confirmTitle: String {
            switch self {
            case .exit:
                return "退出"
            case .restart:
                return "重开"
            case .switchTheme:
                return "切换"
            case .showRules:
                return "查看"
            case .refreshPendingTasks:
                return "刷新"
            }
        }
    }

    @Binding var game: BlackBoxGameState
    @Binding var selectedTheme: BlackBoxTheme
    @Binding var selectedGridSize: Int
    let onRestart: () -> Void
    let onBackToIntro: () -> Void
    let onShowRules: () -> Void
    @State private var selectedDetail: BlackBoxTileDetailContext?
    @State private var confirmAction: ConfirmAction?
    @State private var isHistoryPresented = false
    @State private var historyRecords: [BlackBoxHistoryRecord] = BlackBoxHistoryStore.load()

    private var currentScore: Int {
        game.board.flatMap { $0 }.compactMap { $0 }.filter { $0.isCompleted }.reduce(0) { $0 + $1.score }
    }

    var body: some View {
        GeometryReader { geo in
            let safeBoardSide = min(geo.size.width - 32, geo.size.height * 0.55)

            ZStack {
                VStack(spacing: 24) {
                    Spacer(minLength: 16)

                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            Text("2048")
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .padding(.vertical, 8)

                            Button {
                                requestConfirmation(.showRules)
                            } label: {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.3))
                            }

                            Button {
                                historyRecords = BlackBoxHistoryStore.load()
                                isHistoryPresented = true
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 21, weight: .bold))
                                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.3))
                            }
                        }

                        Spacer()

                        scoreBox(title: "分数", value: "\(currentScore)")
                    }

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            neumorphicButton(title: "退出", action: {
                                requestConfirmation(.exit)
                            })
                            Spacer()
                            neumorphicButton(title: "撤销", action: {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.92)) {
                                    game.undoLastAction()
                                }
                            })
                            neumorphicButton(title: "重新开始", action: {
                                requestConfirmation(.restart)
                            })
                        }

                        HStack(spacing: 10) {
                            ForEach(BlackBoxTheme.allCases) { theme in
                                Button {
                                    guard selectedTheme != theme else { return }
                                    requestConfirmation(.switchTheme(theme))
                                } label: {
                                    Text(theme.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(selectedTheme == theme ? .white : BlackBoxClassicPalette.darkText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .fill(selectedTheme == theme ? BlackBoxClassicPalette.restart : BlackBoxClassicPalette.emptyTile)
                                                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(selectedTheme == theme ? 0.4 : 0.1), radius: 4, x: 0, y: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    VStack(spacing: 8) {
                        BlackBoxBoardGridView(game: $game) { row, col, tile in
                            if tile.components.count > 1 {
                                selectedDetail = BlackBoxTileDetailContext(tile: tile, theme: game.theme)
                            } else {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                                    game.toggleCompletion(row: row, col: col)
                                }
                            }
                        }
                        .frame(width: safeBoardSide, height: safeBoardSide)
                        .gesture(
                            DragGesture(minimumDistance: 22)
                                .onEnded { value in
                                    guard let direction = swipeDirection(for: value.translation) else { return }
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                                        game.swipe(direction)
                                    }
                                }
                        )

                        if game.isGameOver {
                            Text(L10n.blackBoxModeGameOver)
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .padding(.top, 8)
                        }
                    }
                    .offset(y: -45)

                    HStack {
                        HStack(spacing: 8) {
                            ForEach([3, 4, 5], id: \.self) { size in
                                Button {
                                    saveCurrentHistoryIfNeeded()
                                    selectedGridSize = size
                                    onRestart()
                                } label: {
                                    Text("\(size)x\(size)")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(selectedGridSize == size ? .white : BlackBoxClassicPalette.darkText)
                                        .frame(width: 52, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .fill(selectedGridSize == size ? BlackBoxClassicPalette.restart : BlackBoxClassicPalette.emptyTile)
                                                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(selectedGridSize == size ? 0.4 : 0.1), radius: 4, x: 0, y: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        Button {
                            requestConfirmation(.refreshPendingTasks)
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundColor(BlackBoxClassicPalette.darkText)
                                .frame(width: 42, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                        .fill(BlackBoxClassicPalette.restart)
                                        .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.65), radius: 5, x: -2, y: -2)
                                        .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.35), radius: 5, x: 2, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: safeBoardSide)
                    .offset(y: -34)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .sheet(item: $selectedDetail) { context in
                    BlackBoxTileDetailSheet(context: context)
                        .presentationDetents([.fraction(0.44), .medium])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isHistoryPresented) {
                    BlackBoxHistorySheet(records: historyRecords)
                        .presentationDetents([.fraction(0.4), .medium, .large])
                        .presentationDragIndicator(.visible)
                }

                if let action = confirmAction {
                    confirmOverlay(for: action)
                }
            }
        }
    }

    private func swipeDirection(for translation: CGSize) -> BlackBoxDirection? {
        let x = translation.width
        let y = translation.height
        guard max(abs(x), abs(y)) > 24 else { return nil }
        if abs(x) > abs(y) { return x > 0 ? .right : .left }
        return y > 0 ? .down : .up
    }

    private func neumorphicButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(BlackBoxClassicPalette.darkText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                        .fill(BlackBoxClassicPalette.restart)
                        .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.65), radius: 5, x: -2, y: -2)
                        .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.35), radius: 5, x: 2, y: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func scoreBox(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
        }
        .frame(minWidth: 88)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                .fill(BlackBoxClassicPalette.board)
                .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.5), radius: 4, x: -2, y: -2)
                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.2), radius: 4, x: 2, y: 2)
        )
    }

    private func requestConfirmation(_ action: ConfirmAction) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            confirmAction = action
        }
    }

    private func dismissConfirmation() {
        withAnimation(.easeInOut(duration: 0.18)) {
            confirmAction = nil
        }
    }

    private func performConfirmedAction(_ action: ConfirmAction) {
        dismissConfirmation()
        switch action {
        case .exit:
            saveCurrentHistoryIfNeeded()
            onBackToIntro()
        case .restart:
            saveCurrentHistoryIfNeeded()
            selectedDetail = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                onRestart()
            }
        case .switchTheme(let theme):
            saveCurrentHistoryIfNeeded()
            selectedTheme = theme
            onRestart()
        case .showRules:
            onShowRules()
        case .refreshPendingTasks:
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                game.refreshPendingTiles()
            }
        }
    }

    private func saveCurrentHistoryIfNeeded() {
        let completedTiles = game.board.flatMap { $0 }.compactMap { $0 }.filter { $0.isCompleted }.count
        let hasProgress = game.moveCount > 0 || game.mergeCount > 0 || currentScore > 0 || completedTiles > 0
        guard hasProgress else { return }

        BlackBoxHistoryStore.append(
            BlackBoxHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                themeRawValue: game.theme.rawValue,
                gridSize: game.size,
                score: currentScore,
                moves: game.moveCount,
                merges: game.mergeCount,
                completedTiles: completedTiles
            )
        )
    }

    @ViewBuilder
    private func confirmOverlay(for action: ConfirmAction) -> some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissConfirmation()
                }

            VStack(spacing: 16) {
                Text(action.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(BlackBoxClassicPalette.text)

                Text(action.message)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        dismissConfirmation()
                    } label: {
                        Text(L10n.cancel)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.darkText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                    .fill(BlackBoxClassicPalette.board)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        performConfirmedAction(action)
                    } label: {
                        Text(action.confirmTitle)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.darkText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                    .fill(BlackBoxClassicPalette.restart)
                                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.4), radius: 4, x: 0, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(BlackBoxClassicPalette.background)
                    .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.65), radius: 6, x: -3, y: -3)
                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.22), radius: 8, x: 4, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                            .stroke(BlackBoxClassicPalette.board.opacity(0.28), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)
        }
        .zIndex(50)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct BlackBoxBoardGridView: View {
    @Binding var game: BlackBoxGameState
    let onTileTap: (_ row: Int, _ col: Int, _ tile: BlackBoxTile) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let outerPadding: CGFloat = 10
            let totalSpacing = CGFloat(game.size - 1) * spacing
            let side = min(geo.size.width, geo.size.height)
            let cellSide = (side - (outerPadding * 2) - totalSpacing) / CGFloat(game.size)

            ZStack {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(BlackBoxClassicPalette.board)
                    .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.72), radius: 8, x: -4, y: -4)
                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.32), radius: 8, x: 4, y: 4)

                VStack(spacing: spacing) {
                    ForEach(0..<game.size, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<game.size, id: \.self) { col in
                                BlackBoxTileCellView(tile: game.board[row][col])
                                    .frame(width: cellSide, height: cellSide)
                                    .contentShape(RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous))
                                    .onTapGesture {
                                        guard let tile = game.board[row][col] else { return }
                                        onTileTap(row, col, tile)
                                    }
                            }
                        }
                    }
                }
                .padding(outerPadding)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct BlackBoxTileCellView: View {
    let tile: BlackBoxTile?

    var body: some View {
        ZStack {
            if let tile {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(tileBackground(for: tile))
                    .shadow(color: tile.isCompleted ? BlackBoxClassicPalette.boardShadow.opacity(0.2) : BlackBoxClassicPalette.boardShadow.opacity(0.1), radius: 4, x: 0, y: 2)

                VStack(spacing: 2) {
                    Text("\(tile.score)")
                        .font(.system(size: tile.score >= 1000 ? 24 : 32, weight: .heavy, design: .rounded))
                        .foregroundColor(tileTextColor(for: tile))
                        .minimumScaleFactor(0.5)

                    if tile.score < 2048 {
                        Text(tile.displayTitle)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(tileTextColor(for: tile).opacity(0.8))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(BlackBoxClassicPalette.emptyTile)
                    .shadow(color: Color.white.opacity(0.3), radius: 4, x: -2, y: -2)
                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.1), radius: 4, x: 2, y: 2)
            }
        }
    }

    private func tileBackground(for tile: BlackBoxTile) -> Color {
        guard tile.isCompleted else { return BlackBoxClassicPalette.emptyTile.opacity(0.9) }
        switch tile.score {
        case ..<4:
            return Color(hex: "EEE4DA")
        case 4:
            return Color(hex: "EDE0C8")
        case 8:
            return Color(hex: "F2B179")
        case 16:
            return Color(hex: "F59563")
        case 32:
            return Color(hex: "F67C5F")
        case 64:
            return Color(hex: "F65E3B")
        case 128:
            return Color(hex: "EDCF72")
        case 256:
            return Color(hex: "EDCC61")
        case 512:
            return Color(hex: "EDC850")
        case 1024:
            return Color(hex: "EDC53F")
        case 2048:
            return Color(hex: "EDC22E")
        default:
            return Color(hex: "3C3A32")
        }
    }

    private func tileTextColor(for tile: BlackBoxTile) -> Color {
        if !tile.isCompleted {
            return BlackBoxClassicPalette.text
        }
        return tile.score >= 8 ? BlackBoxClassicPalette.darkText : BlackBoxClassicPalette.text
    }
}

private struct BlackBoxTileDetailContext: Identifiable {
    let id = UUID()
    let tile: BlackBoxTile
    let theme: BlackBoxTheme
}

private struct BlackBoxTileDetailSheet: View {
    let context: BlackBoxTileDetailContext

    var body: some View {
        NavigationStack {
            ZStack {
                BlackBoxClassicPalette.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(context.tile.displayTitle)
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .lineLimit(2)
                        }

                        Spacer()
                    }

                    Text(L10n.blackBoxModeContainsTasks)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(BlackBoxClassicPalette.text.opacity(0.84))

                    ForEach(componentRows, id: \.id) { row in
                        HStack {
                            Text(row.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                            Spacer()
                            Text("x\(row.count)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.restart)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                .fill(Color.white.opacity(0.32))
                        )
                    }

                    Divider()
                        .overlay(BlackBoxClassicPalette.text.opacity(0.15))

                    HStack {
                        Text(L10n.blackBoxModeCompletionCount)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.84))
                        Spacer()
                        Text("\(L10n.blackBoxModeTotalCompletions) \(totalCompletions)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle(L10n.blackBoxModeTileDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var componentRows: [(id: String, title: String, count: Int)] {
        context.tile.components
            .sorted { $0.key < $1.key }
            .map { key, count in
                let title = context.theme.definitionMap[key]?.baseTitle ?? key
                return (id: key, title: title, count: count)
            }
    }

    private var totalCompletions: Int {
        context.tile.components.values.reduce(0, +)
    }
}

private struct BlackBoxHistorySheet: View {
    let records: [BlackBoxHistoryRecord]

    var body: some View {
        NavigationStack {
            ZStack {
                BlackBoxClassicPalette.background
                    .ignoresSafeArea()

                if records.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.5))
                        Text("暂无历史记录")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.75))
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(records) { record in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.themeTitle)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text)
                                        Text("\(record.gridSize)x\(record.gridSize) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.7))
                                    }

                                    Spacer(minLength: 8)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("分数 \(record.score)")
                                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.restart)
                                        Text("步数 \(record.moves) · 合并 \(record.merges)")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.72))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                        .fill(BlackBoxClassicPalette.board.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .stroke(BlackBoxClassicPalette.board.opacity(0.24), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PointsDetailSheet: View {
    private enum PointsTab: String, CaseIterable, Identifiable {
        case stickers
        case rewards

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stickers:
                return L10n.stickers
            case .rewards:
                return L10n.myRewards
            }
        }
    }

    let points: Int
    let inventoryCounts: [StickerKind: Int]
    let usedCounts: [StickerKind: Int]
    let rewards: [CustomReward]
    let onRedeem: (StickerKind) -> Void
    let onAddToHome: (StickerKind) -> Void
    let onCreateReward: (String, Int) -> Void
    let onUpdateReward: (CustomReward) -> Void
    let onDeleteReward: (CustomReward) -> Void
    let onRedeemReward: (CustomReward) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var creatingReward = false
    @State private var editingReward: CustomReward?
    @State private var selectedTab: PointsTab = .stickers

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var contentMaxWidth: CGFloat {
        isPadLayout ? 820 : .infinity
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var stickerGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: isPadLayout ? 3 : 2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .center, spacing: 14) {
                            Text(L10n.myPoints)
                                .font(.system(size: scaled(17, pad: 21), weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.76))

                            HStack(spacing: 10) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: scaled(20, pad: 24), weight: .bold))
                                    .foregroundColor(NeumorphicColors.accent)

                                Text("\(points)")
                                    .font(.system(size: scaled(34, pad: 44), weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        tabSelector

                        if selectedTab == .stickers {
                            VStack(alignment: .leading, spacing: 14) {
                                LazyVGrid(
                                    columns: stickerGridColumns,
                                    spacing: 16
                                ) {
                                    ForEach(StickerKind.allCases) { kind in
                                        stickerCard(kind)
                                    }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                if rewards.isEmpty {
                                    Text(L10n.noRewardsYet)
                                        .font(.system(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                                        .foregroundColor(NeumorphicColors.text.opacity(0.62))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 4)
                                }

                                LazyVGrid(columns: stickerGridColumns, spacing: 16) {
                                    ForEach(rewards) { reward in
                                        rewardCard(reward)
                                    }
                                    addRewardCard
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
        .sheet(isPresented: phoneCreatingRewardBinding) {
            rewardEditorSheet(for: nil)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: padCreatingRewardBinding) {
            NineTenthsSheetContainer(contentMaxWidth: 700) {
                rewardEditorSheet(for: nil)
            }
            .background(Color.clear)
        }
        .sheet(item: phoneEditingRewardBinding) { reward in
            rewardEditorSheet(for: reward)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: padEditingRewardBinding) { reward in
            NineTenthsSheetContainer(contentMaxWidth: 700) {
                rewardEditorSheet(for: reward)
            }
            .background(Color.clear)
        }
    }

    private var phoneCreatingRewardBinding: Binding<Bool> {
        Binding(
            get: { !isPadLayout && creatingReward },
            set: { creatingReward = $0 }
        )
    }

    private var padCreatingRewardBinding: Binding<Bool> {
        Binding(
            get: { isPadLayout && creatingReward },
            set: { creatingReward = $0 }
        )
    }

    private var phoneEditingRewardBinding: Binding<CustomReward?> {
        Binding(
            get: { isPadLayout ? nil : editingReward },
            set: { editingReward = $0 }
        )
    }

    private var padEditingRewardBinding: Binding<CustomReward?> {
        Binding(
            get: { isPadLayout ? editingReward : nil },
            set: { editingReward = $0 }
        )
    }

    private func rewardEditorSheet(for reward: CustomReward?) -> some View {
        RewardEditorSheet(
            reward: reward,
            onSave: { title, requiredPoints in
                if let reward {
                    onUpdateReward(
                        CustomReward(
                            id: reward.id,
                            title: title,
                            requiredPoints: requiredPoints,
                            redemptionCount: reward.redemptionCount,
                            totalSpentPoints: reward.totalSpentPoints,
                            isArchived: reward.isArchived
                        )
                    )
                    editingReward = nil
                } else {
                    onCreateReward(title, requiredPoints)
                    creatingReward = false
                }
            },
            onDelete: reward.map { existingReward in
                {
                    onDeleteReward(existingReward)
                    editingReward = nil
                }
            },
            onCancel: {
                if reward != nil {
                    editingReward = nil
                } else {
                    creatingReward = false
                }
            }
        )
    }

    private var tabSelector: some View {
        HStack(spacing: 12) {
            ForEach(PointsTab.allCases) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: PointsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.title)
                .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: isPadLayout ? 46 : 40)
                .background(tabBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    private func tabBackground(isSelected: Bool) -> some View {
        let base = Capsule(style: .continuous)
            .fill(isSelected ? NeumorphicColors.background : NeumorphicColors.background.opacity(0.48))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected
                            ? NeumorphicColors.accent.opacity(0.24)
                            : NeumorphicColors.lightShadow.opacity(0.24),
                        lineWidth: 1
                    )
            )

        return Group {
            if isSelected {
                base.neumorphicConvex(radius: 20)
            } else {
                base
            }
        }
    }

    private func stickerCard(_ sticker: StickerKind) -> some View {
        let inventoryCount = inventoryCounts[sticker] ?? 0
        let usedCount = usedCounts[sticker] ?? 0
        let isPlacedOnHome = usedCount > 0
        let hasOwned = inventoryCount > 0
        let canRedeem = points >= sticker.requiredPoints

        return VStack(spacing: 12) {
            Image((hasOwned || canRedeem) ? sticker.unlockedImageName : sticker.lockedImageName)
                .resizable()
                .scaledToFit()
                .frame(height: isPadLayout ? 120 : 100)

            VStack(spacing: 4) {
                Text("\(sticker.requiredPoints) \(L10n.pointsUnit)")
                    .font(.system(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor((hasOwned || canRedeem) ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.58))

                if inventoryCount > 0 {
                    Text(L10n.ownedCount(inventoryCount))
                    .font(.system(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                }
            }

            Button {
                if hasOwned {
                    onAddToHome(sticker)
                } else {
                    onRedeem(sticker)
                }
            } label: {
                Text(hasOwned ? (isPlacedOnHome ? L10n.onHome : L10n.addToHome) : L10n.redeem)
                    .font(.system(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                    .foregroundColor((canRedeem || hasOwned) ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.42))
                    .frame(maxWidth: .infinity)
                    .frame(height: isPadLayout ? 38 : 34)
                    .background(Color.clear.neumorphicConvex(radius: isPadLayout ? 19 : 17))
                    .opacity((canRedeem || hasOwned) ? 1 : 0.68)
            }
            .buttonStyle(.plain)
            .disabled((!canRedeem && !hasOwned) || isPlacedOnHome)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color.clear.neumorphicConvex(radius: 22))
        .opacity((hasOwned || canRedeem) ? 1 : 0.9)
    }

    private func rewardCard(_ reward: CustomReward) -> some View {
        let canRedeem = points >= reward.requiredPoints

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: isPadLayout ? 14 : 10)

                Text(reward.title)
                    .font(.system(size: scaled(16, pad: 20), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 8)
                    .offset(y: 20)

                Spacer(minLength: isPadLayout ? 12 : 10)

                VStack(spacing: 4) {
                    Text("\(reward.requiredPoints) \(L10n.pointsUnit)")
                        .font(.system(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                        .foregroundColor(canRedeem ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.58))

                    if reward.redemptionCount > 0 {
                        Text(L10n.redeemedCount(reward.redemptionCount))
                            .font(.system(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity)
                .offset(y: 20)

                Spacer(minLength: isPadLayout ? 12 : 10)

                Button {
                    onRedeemReward(reward)
                } label: {
                    Text(L10n.redeem)
                        .font(.system(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                        .foregroundColor(canRedeem ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .frame(height: isPadLayout ? 38 : 34)
                        .background(Color.clear.neumorphicConvex(radius: isPadLayout ? 19 : 17))
                        .opacity(canRedeem ? 1 : 0.68)
                }
                .buttonStyle(.plain)
                .disabled(!canRedeem)
                .padding(.top, isPadLayout ? 8 : 6)
            }

            Button {
                editingReward = reward
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: scaled(12, pad: 14), weight: .bold))
                    .foregroundColor(NeumorphicColors.text.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(Color.clear.neumorphicConvex(radius: 15))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: isPadLayout ? 192 : 176, alignment: .top)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color.clear.neumorphicConvex(radius: 22))
        .opacity(canRedeem ? 1 : 0.9)
    }

    private var addRewardCard: some View {
        Button {
            creatingReward = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: scaled(34, pad: 40), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)

                Text(L10n.addReward)
                    .font(.system(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }
            .frame(maxWidth: .infinity, minHeight: isPadLayout ? 192 : 176)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(Color.clear.neumorphicConvex(radius: 22))
        }
        .buttonStyle(.plain)
    }
}

private struct RewardEditorSheet: View {
    let reward: CustomReward?
    let onSave: (String, Int) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var titleText: String
    @State private var pointsText: String
    @FocusState private var focusedField: FocusedField?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    private enum FocusedField: Hashable {
        case title
        case points
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(
        reward: CustomReward?,
        onSave: @escaping (String, Int) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.reward = reward
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _titleText = State(initialValue: reward?.title ?? "")
        _pointsText = State(initialValue: reward.map { String($0.requiredPoints) } ?? "")
    }

    private var normalizedTitle: String {
        String(titleText.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPoints: Int? {
        guard let points = Int(pointsText), points > 0 else { return nil }
        return min(points, 9_999)
    }

    private var canSave: Bool {
        !normalizedTitle.isEmpty && normalizedPoints != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedField = nil
                    }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.rewardTitle)
                            .font(.system(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.74))

                        TextField(L10n.rewardExampleHint, text: $titleText)
                            .font(.system(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .padding(.horizontal, 16)
                            .frame(height: isPadLayout ? 56 : 50)
                            .background(Color.clear.neumorphicConvex(radius: isPadLayout ? 18 : 16))
                            .focused($focusedField, equals: .title)
                            .submitLabel(.done)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.rewardPoints)
                            .font(.system(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.74))

                        TextField(L10n.rewardPointsHint, text: $pointsText)
                            .keyboardType(.numberPad)
                            .font(.system(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .padding(.horizontal, 16)
                            .frame(height: isPadLayout ? 56 : 50)
                            .background(Color.clear.neumorphicConvex(radius: isPadLayout ? 18 : 16))
                            .focused($focusedField, equals: .points)
                    }

                    if let onDelete {
                        Button {
                            onDelete()
                        } label: {
                            Text(L10n.deleteReward)
                                .font(.system(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.bingoAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: isPadLayout ? 50 : 46)
                                .background(Color.clear.neumorphicConvex(radius: isPadLayout ? 20 : 18))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(reward == nil ? L10n.addReward : L10n.editReward)
                        .font(.system(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        onCancel()
                    }
                    .foregroundColor(NeumorphicColors.text.opacity(0.72))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        guard let requiredPoints = normalizedPoints else { return }
                        onSave(normalizedTitle, requiredPoints)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(canSave ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.38))
                    .disabled(!canSave)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button(L10n.done) {
                        focusedField = nil
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }
}

private struct EditableHomeStickerView: View {
    let placement: HomeStickerPlacement
    let canvasSize: CGSize
    let isEditing: Bool
    let onSelect: () -> Void
    let onUpdate: (HomeStickerPlacement) -> Void
    let onDelete: () -> Void

    @State private var dragStartPlacement: HomeStickerPlacement?
    @State private var magnifyStartScale: Double?

    private var baseStickerWidth: CGFloat {
        placement.kind.homeDisplayWidth
    }

    private var stickerWidth: CGFloat {
        baseStickerWidth * placement.scale
    }

    private var horizontalInsetRatio: Double {
        let inset = stickerWidth / 2
        return clampRatio(inset / max(canvasSize.width, 1))
    }

    private var verticalInsetRatio: Double {
        let inset = stickerWidth / 2
        return clampRatio(inset / max(canvasSize.height, 1))
    }

    var body: some View {
        let position = CGPoint(
            x: canvasSize.width * placement.xRatio,
            y: canvasSize.height * placement.yRatio
        )

        ZStack(alignment: .topTrailing) {
            Image(placement.kind.unlockedImageName)
                .resizable()
                .scaledToFit()
                .frame(width: stickerWidth)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.16), radius: 6, x: 3, y: 4)
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(NeumorphicColors.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .padding(2)
                    }
                }

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(NeumorphicColors.accent))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .contentShape(Rectangle())
        .position(position)
        .onTapGesture {
            onSelect()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard isEditing else { return }

                    let baseline = dragStartPlacement ?? placement
                    if dragStartPlacement == nil {
                        dragStartPlacement = placement
                    }

                    let newX = clamp(
                        baseline.xRatio + value.translation.width / max(canvasSize.width, 1),
                        min: horizontalInsetRatio,
                        max: 1 - horizontalInsetRatio
                    )
                    let newY = clamp(
                        baseline.yRatio + value.translation.height / max(canvasSize.height, 1),
                        min: verticalInsetRatio,
                        max: 1 - verticalInsetRatio
                    )

                    onUpdate(
                        HomeStickerPlacement(
                            id: placement.id,
                            kind: placement.kind,
                            xRatio: newX,
                            yRatio: newY,
                            scale: placement.scale
                        )
                    )
                }
                .onEnded { _ in
                    dragStartPlacement = nil
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    guard isEditing else { return }

                    let baseline = magnifyStartScale ?? placement.scale
                    if magnifyStartScale == nil {
                        magnifyStartScale = placement.scale
                    }

                    let newScale = clamp(baseline * value.magnification, min: 0.5, max: 1.6)
                    onUpdate(
                        HomeStickerPlacement(
                            id: placement.id,
                            kind: placement.kind,
                            xRatio: placement.xRatio,
                            yRatio: placement.yRatio,
                            scale: newScale
                        )
                    )
                }
                .onEnded { _ in
                    magnifyStartScale = nil
                }
        )
    }

    private func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }

    private func clampRatio(_ value: CGFloat) -> Double {
        let normalized = Double(value)
        return Swift.max(0.02, Swift.min(normalized, 0.48))
    }
}

private struct QuickEditView: View {
    @ObservedObject var viewModel: BingoViewModel
    let onSaveSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var library = CommonTasksStore.loadLibrary()
    @State private var lastTrackedLibrary = CommonTasksStore.loadLibrary()
    @FocusState private var focusedField: FocusedMyTaskField?
    @State private var deleteConfirmationTarget: DeleteTarget?
    @State private var localToastMessage: String?
    @State private var isLocalToastVisible = false
    @State private var hideLocalToastWorkItem: DispatchWorkItem?
    @State private var selectedTaskKeys: [String] = []
    @State private var targetGridSize = 4
    @State private var didApplyToBoard = false
    @State private var pendingApplyPlan: ApplyPlan?

    private enum FocusedMyTaskField: Hashable {
        case task(Int)
        case groupName(UUID)
        case groupTask(UUID, Int)
    }

    private enum DeleteTarget: Equatable {
        case task(Int)
        case group(UUID)
        case groupTask(UUID, Int)

        var title: String {
            L10n.deleteConfirmationTitle
        }

        var message: String {
            switch self {
            case .task:
                return L10n.deleteTaskConfirmationMessage
            case .groupTask:
                return L10n.deleteTaskConfirmationMessage
            case .group:
                return L10n.deleteGroupConfirmationMessage
            }
        }

        var successMessage: String {
            switch self {
            case .task:
                return L10n.taskDeletedSuccess
            case .groupTask:
                return L10n.taskDeletedSuccess
            case .group:
                return L10n.groupDeletedSuccess
            }
        }
    }

    private struct TaskCandidate: Identifiable {
        let id: String
        let text: String
    }

    private struct ApplyPlan: Equatable {
        let tasks: [String]
        let targetGridSize: Int
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var groupColumns: [GridItem] {
        if isPadLayout {
            return [GridItem(.flexible(), spacing: 18)]
        }
        return [GridItem(.flexible(), spacing: 14)]
    }

    private var taskItemColumns: [GridItem] {
        let spacing: CGFloat = isPadLayout ? 12 : 10
        let count = isPadLayout ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    private var hasExistingBoardTasks: Bool {
        !viewModel.currentTaskPoolTasks().isEmpty
    }

    private var allTaskCandidates: [TaskCandidate] {
        var candidates: [TaskCandidate] = []

        for index in library.tasks.indices {
            let text = library.tasks[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            candidates.append(TaskCandidate(id: "task-\(index)", text: text))
        }

        for group in library.groups {
            for index in group.tasks.indices {
                let text = group.tasks[index].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                candidates.append(TaskCandidate(id: "group-\(group.id.uuidString)-\(index)", text: text))
            }
        }

        return candidates
    }

    private var selectedTasks: [String] {
        let candidateMap = Dictionary(uniqueKeysWithValues: allTaskCandidates.map { ($0.id, $0.text) })
        return selectedTaskKeys.compactMap { key in
            guard let text = candidateMap[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedField = nil
                    }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        quickEditControlsCard
                        tasksSection
                            .padding(.top, -30)
                        groupsSection
                        hintCard
                    }
                    .frame(maxWidth: isPadLayout ? 760 : .infinity, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)

                if isLocalToastVisible, let localToastMessage {
                    VStack {
                        Text(localToastMessage)
                            .font(.system(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.96))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(NeumorphicColors.accent.opacity(0.92))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(.white.opacity(0.28), lineWidth: 1)
                                    )
                            )
                            .shadow(color: NeumorphicColors.darkShadow.opacity(0.12), radius: 8, x: 0, y: 4)
                            .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
                        Spacer()
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                }

                if let deleteConfirmationTarget {
                    deleteConfirmationOverlay(for: deleteConfirmationTarget)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if let pendingApplyPlan {
                    applyConfirmationOverlay(for: pendingApplyPlan)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.quickEdit)
                        .font(.system(size: scaled(20, pad: 23), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        handleDoneTap()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button(L10n.done) {
                        focusedField = nil
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
        .onDisappear {
            guard !didApplyToBoard else { return }
            finalizeLibrary()
        }
        .onAppear {
            migrateStandaloneTasksIntoGroupsIfNeeded()
            targetGridSize = viewModel.gridSize
            selectedTaskKeys = initialSelectedKeys(
                from: viewModel.currentTaskPoolTasks(),
                candidates: allTaskCandidates
            )
        }
        .onChange(of: library) { _, _ in
            syncSelectedTaskKeysWithCurrentLibrary()
        }
    }

    private var quickEditControlsCard: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    quickActionButton(title: L10n.selectAll) {
                        selectedTaskKeys = allTaskCandidates.map(\.id)
                    }

                    quickActionButton(title: L10n.deselectAll) {
                        selectedTaskKeys = []
                    }

                    quickActionButton(title: L10n.random) {
                        selectedTaskKeys = allTaskCandidates.map(\.id).shuffled()
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    let controlSize: CGFloat = isPadLayout ? 38 : 32
                    let iconSize: CGFloat = isPadLayout ? 18 : 16

                    HStack(spacing: isPadLayout ? 14 : 11) {
                        Button {
                            targetGridSize = max(2, targetGridSize - 1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: iconSize, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: controlSize, height: controlSize)
                                .background(Color.clear.neumorphicConvex(radius: controlSize / 2))
                        }
                        .buttonStyle(.plain)
                        .disabled(targetGridSize <= 2)
                        .opacity(targetGridSize <= 2 ? 0.45 : 1)

                        Text("\(targetGridSize) × \(targetGridSize)")
                            .font(.system(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .frame(width: isPadLayout ? 72 : 62)
                            .multilineTextAlignment(.center)

                        Button {
                            targetGridSize = min(5, targetGridSize + 1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: iconSize, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: controlSize, height: controlSize)
                                .background(Color.clear.neumorphicConvex(radius: controlSize / 2))
                        }
                        .buttonStyle(.plain)
                        .disabled(targetGridSize >= 5)
                        .opacity(targetGridSize >= 5 ? 0.45 : 1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
            }
        }
    }

    private func quickActionButton(title: String, isAccent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                .foregroundColor(isAccent ? .white : NeumorphicColors.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Capsule(style: .continuous)
                        .fill(isAccent ? NeumorphicColors.accent : NeumorphicColors.background)
                        .shadow(color: Color.white.opacity(0.68), radius: 6, x: -3, y: -3)
                        .shadow(color: Color(hex: "CFD4DA").opacity(0.7), radius: 6, x: 3, y: 3)
                )
        }
        .buttonStyle(.plain)
    }

    private var tasksSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: L10n.tasks,
                    subtitle: "",
                    detail: "\(library.tasks.count)/\(AppSettings.maxCommonTasks)",
                    actionTitle: library.tasks.count < AppSettings.maxCommonTasks ? L10n.addTask : nil,
                    action: library.tasks.count < AppSettings.maxCommonTasks ? appendTask : nil
                )

                LazyVGrid(columns: taskItemColumns, spacing: 10) {
                    ForEach(library.tasks.indices, id: \.self) { index in
                        taskCard(for: index)
                    }
                }
            }
        }
    }

    private var groupsSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: L10n.groups,
                    subtitle: "",
                    detail: "\(library.groups.count)/\(AppSettings.maxTaskGroups)",
                    actionTitle: library.groups.count < AppSettings.maxTaskGroups ? L10n.addGroup : nil,
                    action: library.groups.count < AppSettings.maxTaskGroups ? appendGroup : nil
                )

                LazyVGrid(columns: groupColumns, spacing: 14) {
                    ForEach(library.groups.indices, id: \.self) { index in
                        groupCard(for: index)
                    }
                }
            }
        }
    }

    private func taskCard(for index: Int) -> some View {
        let key = "task-\(index)"
        let isSelected = selectedTaskKeys.contains(key)

        return HStack(spacing: 8) {
            TextField(L10n.taskNumber(index + 1), text: taskBinding(for: index))
                .font(.system(size: scaled(13, pad: 17), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($focusedField, equals: .task(index))

            Button {
                toggleSelection(for: key)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: scaled(13, pad: 15), weight: .bold))
                    .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.45))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Button {
                focusedField = nil
                deleteConfirmationTarget = .task(index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: scaled(9, pad: 10), weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: 18, height: 18)
                    .neumorphicConvex(radius: 9)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(Color.clear.neumorphicConvex(radius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NeumorphicColors.accent.opacity(isSelected ? 0.12 : 0))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NeumorphicColors.accent.opacity(isSelected ? 0.4 : 0), lineWidth: 1.2)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            toggleSelection(for: key)
        }
    }

    private func groupCard(for index: Int) -> some View {
        let group = library.groups[index]
        let groupSelected = isGroupSelected(group)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                TextField(L10n.groupName, text: groupNameBinding(for: group.id))
                    .font(.system(size: scaled(16, pad: 22), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .focused($focusedField, equals: .groupName(group.id))

                Button {
                    toggleGroupSelection(group)
                } label: {
                    Image(systemName: groupSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: scaled(15, pad: 17), weight: .bold))
                        .foregroundColor(groupSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.45))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(groupSelectableTaskKeys(group).isEmpty)
                .opacity(groupSelectableTaskKeys(group).isEmpty ? 0.35 : 1)
                .offset(x: 5)

                Button {
                    focusedField = nil
                    deleteConfirmationTarget = .group(group.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: scaled(9, pad: 10), weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: 18, height: 18)
                        .neumorphicConvex(radius: 9)
                }
                .buttonStyle(.plain)
            }

            if group.tasks.isEmpty {
                Text(L10n.addTask)
                    .font(.system(size: scaled(13, pad: 17), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.52))
            }

            LazyVGrid(columns: taskItemColumns, spacing: 10) {
                ForEach(group.tasks.indices, id: \.self) { taskIndex in
                    groupTaskChip(groupID: group.id, index: taskIndex)
                }

                if group.tasks.count < AppSettings.maxTasksPerGroup {
                    addGroupTaskChip(groupID: group.id)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.clear.neumorphicConvex(radius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NeumorphicColors.accent.opacity(groupSelected ? 0.12 : 0))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NeumorphicColors.accent.opacity(groupSelected ? 0.4 : 0), lineWidth: 1.2)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            toggleGroupSelection(group)
        }
    }

    private func groupTaskChip(groupID: UUID, index: Int) -> some View {
        return HStack(spacing: 8) {
            TextField(L10n.task, text: groupTaskBinding(groupID: groupID, index: index))
                .font(.system(size: scaled(13, pad: 17), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($focusedField, equals: .groupTask(groupID, index))

            Button {
                focusedField = nil
                deleteConfirmationTarget = .groupTask(groupID, index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: scaled(9, pad: 10), weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: 18, height: 18)
                    .neumorphicConvex(radius: 9)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(Color.clear.neumorphicConvex(radius: 14))
    }

    private func addGroupTaskChip(groupID: UUID) -> some View {
        Button {
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else { return }
            library.groups[groupIndex].tasks.append("")
            let newIndex = library.groups[groupIndex].tasks.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .groupTask(groupID, newIndex)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: scaled(10, pad: 13), weight: .bold))
                Text(L10n.addTask)
                    .font(.system(size: scaled(13, pad: 17), weight: .semibold, design: .rounded))
            }
            .foregroundColor(NeumorphicColors.accent)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color.clear.neumorphicConvex(radius: 14))
        }
        .buttonStyle(.plain)
    }

    private func taskBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard library.tasks.indices.contains(index) else { return "" }
                return library.tasks[index]
            },
            set: { newValue in
                guard library.tasks.indices.contains(index) else { return }
                library.tasks[index] = String(newValue.prefix(AppSettings.maxTaskLength))
            }
        )
    }

    private func groupNameBinding(for groupID: UUID) -> Binding<String> {
        Binding(
            get: {
                library.groups.first(where: { $0.id == groupID })?.name ?? ""
            },
            set: { newValue in
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else { return }
                library.groups[groupIndex].name = String(newValue.prefix(AppSettings.maxTaskLength))
            }
        )
    }

    private func groupTaskBinding(groupID: UUID, index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return "" }
                return library.groups[groupIndex].tasks[index]
            },
            set: { newValue in
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return }
                library.groups[groupIndex].tasks[index] = String(newValue.prefix(AppSettings.maxTaskLength))
            }
        )
    }

    private func toggleSelection(for key: String) {
        if let index = selectedTaskKeys.firstIndex(of: key) {
            selectedTaskKeys.remove(at: index)
        } else {
            selectedTaskKeys.append(key)
        }
    }

    private func groupSelectableTaskKeys(_ group: MyTaskGroup) -> [String] {
        group.tasks.indices.compactMap { index in
            let text = group.tasks[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "group-\(group.id.uuidString)-\(index)"
        }
    }

    private func isGroupSelected(_ group: MyTaskGroup) -> Bool {
        let keys = groupSelectableTaskKeys(group)
        guard !keys.isEmpty else { return false }
        return keys.allSatisfy { selectedTaskKeys.contains($0) }
    }

    private func toggleGroupSelection(_ group: MyTaskGroup) {
        let keys = groupSelectableTaskKeys(group)
        guard !keys.isEmpty else { return }

        if isGroupSelected(group) {
            let keySet = Set(keys)
            selectedTaskKeys.removeAll { keySet.contains($0) }
        } else {
            for key in keys where !selectedTaskKeys.contains(key) {
                selectedTaskKeys.append(key)
            }
        }
    }

    private func handleDoneTap() {
        focusedField = nil
        finalizeLibrary(showSuccessToast: false, emitChangeToast: false)
        let plan = ApplyPlan(tasks: selectedTasks, targetGridSize: targetGridSize)

        guard !plan.tasks.isEmpty else {
            didApplyToBoard = true
            onSaveSuccess(L10n.quickEditKeptBoardWithoutSelection)
            dismiss()
            return
        }

        if hasExistingBoardTasks {
            pendingApplyPlan = plan
            return
        }

        applySelectionToBoard(plan)
    }

    private func applySelectionToBoard(_ plan: ApplyPlan) {
        viewModel.applyTaskPool(plan.tasks, targetGridSize: plan.targetGridSize)
        didApplyToBoard = true
        onSaveSuccess(L10n.quickEditAppliedSuccess(min(plan.tasks.count, plan.targetGridSize * plan.targetGridSize)))
        dismiss()
    }

    private func initialSelectedKeys(from taskTexts: [String], candidates: [TaskCandidate]) -> [String] {
        var pendingByText = Dictionary(grouping: candidates, by: \.text)
        var resolved: [String] = []

        for text in taskTexts {
            guard var list = pendingByText[text], let candidate = list.first else { continue }
            resolved.append(candidate.id)
            list.removeFirst()
            pendingByText[text] = list
        }

        return resolved
    }

    private func syncSelectedTaskKeysWithCurrentLibrary() {
        let validKeys = Set(allTaskCandidates.map(\.id))
        selectedTaskKeys = selectedTaskKeys.filter { validKeys.contains($0) }
    }

    private func migrateStandaloneTasksIntoGroupsIfNeeded() {
        let legacyTasks = library.tasks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !legacyTasks.isEmpty else { return }

        var remaining = legacyTasks

        for index in library.groups.indices where !remaining.isEmpty {
            let capacity = max(AppSettings.maxTasksPerGroup - library.groups[index].tasks.count, 0)
            guard capacity > 0 else { continue }
            let chunk = Array(remaining.prefix(capacity))
            library.groups[index].tasks.append(contentsOf: chunk)
            remaining.removeFirst(chunk.count)
        }

        while !remaining.isEmpty && library.groups.count < AppSettings.maxTaskGroups {
            let chunk = Array(remaining.prefix(AppSettings.maxTasksPerGroup))
            library.groups.append(MyTaskGroup(name: L10n.groupDefaultName, tasks: chunk))
            remaining.removeFirst(chunk.count)
        }

        library.tasks = []
    }

    private func finalizeLibrary(showSuccessToast: Bool = false, emitChangeToast: Bool = true) {
        let previousLibrary = lastTrackedLibrary
        CommonTasksStore.saveLibrary(library)
        let savedLibrary = CommonTasksStore.loadLibrary()
        library = savedLibrary

        if showSuccessToast {
            onSaveSuccess(L10n.tasksSavedSuccess)
        } else if emitChangeToast,
                  savedLibrary != lastTrackedLibrary,
                  let message = saveSuccessMessage(previous: previousLibrary, current: savedLibrary) {
            onSaveSuccess(message)
        }
        AnalyticsService.syncMyTasksLibrary(savedLibrary)
        lastTrackedLibrary = savedLibrary
    }

    private func saveAndDismiss() {
        focusedField = nil
        finalizeLibrary(showSuccessToast: true)
        dismiss()
    }

    private func appendTask() {
        library.tasks.append("")
        let newIndex = library.tasks.count - 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = .task(newIndex)
        }
    }

    private func appendGroup() {
        let newGroup = MyTaskGroup(name: "", tasks: [""])
        library.groups.append(newGroup)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = .groupName(newGroup.id)
        }
    }

    private func confirmDelete(_ target: DeleteTarget) {
        switch target {
        case .task(let index):
            guard library.tasks.indices.contains(index) else { return }
            library.tasks.remove(at: index)
        case .group(let groupID):
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else { return }
            library.groups.remove(at: groupIndex)
        case .groupTask(let groupID, let index):
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                  library.groups[groupIndex].tasks.indices.contains(index) else { return }
            library.groups[groupIndex].tasks.remove(at: index)
        }

        showLocalToast(target.successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    }

    private func saveSuccessMessage(previous: MyTasksLibrary, current: MyTasksLibrary) -> String? {
        let taskDelta = current.tasks.count - previous.tasks.count
        let groupDelta = current.groups.count - previous.groups.count

        if taskDelta > 0 && groupDelta > 0 {
            return L10n.tasksAndGroupsAddedSuccess
        }
        if taskDelta > 0 {
            return L10n.taskAddedSuccess
        }
        if groupDelta > 0 {
            return L10n.groupAddedSuccess
        }
        if taskDelta < 0 && groupDelta < 0 {
            return L10n.tasksAndGroupsDeletedSuccess
        }
        if taskDelta < 0 {
            return L10n.taskDeletedSuccess
        }
        if groupDelta < 0 {
            return L10n.groupDeletedSuccess
        }

        return nil
    }

    private func showLocalToast(_ message: String) {
        hideLocalToastWorkItem?.cancel()
        localToastMessage = message

        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            isLocalToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.22)) {
                isLocalToastVisible = false
            }
        }
        hideLocalToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    @ViewBuilder
    private func applyConfirmationOverlay(for plan: ApplyPlan) -> some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    pendingApplyPlan = nil
                }

            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Text(L10n.quickEditReplaceConfirmationTitle)
                        .font(.system(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Text(L10n.quickEditReplaceConfirmationMessage)
                        .font(.system(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button {
                        pendingApplyPlan = nil
                    } label: {
                        Text(L10n.cancel)
                            .font(.system(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.clear.neumorphicConvex(radius: 18))
                    }
                    .buttonStyle(.plain)

                    Button {
                        pendingApplyPlan = nil
                        applySelectionToBoard(plan)
                    } label: {
                        Text(L10n.apply)
                            .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(NeumorphicColors.bingoAccent)
                                    .shadow(color: NeumorphicColors.bingoAccent.opacity(0.25), radius: 10, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NeumorphicColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                    .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
            )
            .padding(.horizontal, 28)
        }
    }

    @ViewBuilder
    private func deleteConfirmationOverlay(for target: DeleteTarget) -> some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    deleteConfirmationTarget = nil
                }

            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Text(target.title)
                        .font(.system(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Text(target.message)
                        .font(.system(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button {
                        deleteConfirmationTarget = nil
                    } label: {
                        Text(L10n.cancel)
                            .font(.system(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.clear.neumorphicConvex(radius: 18))
                    }
                    .buttonStyle(.plain)

                    Button {
                        confirmDelete(target)
                    } label: {
                        Text(target.title)
                            .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(NeumorphicColors.bingoAccent)
                                    .shadow(color: NeumorphicColors.bingoAccent.opacity(0.25), radius: 10, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NeumorphicColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                    .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
            )
            .padding(.horizontal, 28)
        }
    }

    private func sectionHeader(title: String, subtitle: String, detail: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: subtitle.isEmpty ? 0 : 4) {
                    Text("\(title) (\(detail))")
                        .font(.system(size: scaled(18, pad: 30), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: scaled(12, pad: 16), weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.56))
                    }
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: scaled(11, pad: 14), weight: .bold))
                        Text(actionTitle)
                            .font(.system(size: scaled(13, pad: 18), weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(NeumorphicColors.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.clear.neumorphicConvex(radius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(isPadLayout ? 22 : 18)
            .background(Color.clear.neumorphicConcave(radius: isPadLayout ? 30 : 26))
    }

    private func emptyStateCard(title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: scaled(16, pad: 22), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Text(message)
                .font(.system(size: scaled(13, pad: 17), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: scaled(12, pad: 14), weight: .bold))
                    Text(actionTitle)
                        .font(.system(size: scaled(14, pad: 18), weight: .semibold, design: .rounded))
                }
                .foregroundColor(NeumorphicColors.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.clear.neumorphicConvex(radius: 18))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isPadLayout ? 22 : 18)
        .background(Color.clear.neumorphicConvex(radius: 24))
    }

    private var hintCard: some View {
        Text(L10n.myTasksHint)
            .font(.system(size: scaled(13, pad: 17), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.66))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear.neumorphicConcave(radius: 22))
    }
}

private struct BingoDiaryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var displayedMonth = Date()
    @State private var selectedEntry: BingoDiaryEntry?
    @State private var statsRange: BingoDiaryStatsRange = .week
    @State private var statsMode: BingoDiaryStatsMode = .completed
    private typealias DiaryTaskStat = (
        task: String,
        totalCount: Int,
        activeDays: Int,
        completionRate: Double,
        dailyCounts: [Int]
    )

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    var body: some View {
        let calendar = Calendar.current
        let startDate = BingoBoardStore.firstSeenDate()
        let today = calendar.startOfDay(for: .now)
        let entries = BingoDiaryStore.entries(inMonthContaining: displayedMonth)
        let entriesByKey = Dictionary(uniqueKeysWithValues: entries.map { (dateKey(for: $0.date), $0) })
        let days = calendarDays(for: displayedMonth, startDate: startDate, endDate: today)
        let weeks = calendarWeeks(from: days)
        let taskStats = BingoDiaryStore.taskCompletionStats(lastDays: statsRange.days, referenceDate: today)
        let timeoutStats = BingoTimeoutStore.taskTimeoutStats(lastDays: statsRange.days, referenceDate: today)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
        let canGoToPreviousMonth = calendar.compare(previousMonth, to: startDate, toGranularity: .month) != .orderedAscending
        let canGoToNextMonth = calendar.compare(nextMonth, to: today, toGranularity: .month) != .orderedDescending

        return NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        calendarSection(
                            weeks: weeks,
                            entriesByKey: entriesByKey,
                            canGoToPreviousMonth: canGoToPreviousMonth,
                            canGoToNextMonth: canGoToNextMonth,
                            previousMonth: previousMonth,
                            nextMonth: nextMonth
                        )

                        taskStatsSection(taskStats: taskStats, timeoutStats: timeoutStats)
                    }
                    .frame(maxWidth: isPadLayout ? 920 : .infinity, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 88)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(L10n.diaryHint)
                    .font(.system(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.66))
                    .frame(maxWidth: isPadLayout ? 920 : .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .background(NeumorphicColors.background)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text(L10n.bingoDiary)
                        .font(.system(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            BingoDiaryDetailView(entry: entry)
                .presentationDetents([.height(480)])
                .presentationDragIndicator(.visible)
        }
    }

    private func calendarSection(
        weeks: [[DiaryCalendarDay]],
        entriesByKey: [String: BingoDiaryEntry],
        canGoToPreviousMonth: Bool,
        canGoToNextMonth: Bool,
        previousMonth: Date,
        nextMonth: Date
    ) -> some View {
        VStack(spacing: 22) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = previousMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: scaled(13, pad: 15), weight: .bold))
                        .foregroundColor(canGoToPreviousMonth ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.28))
                        .frame(width: isPadLayout ? 34 : 30, height: isPadLayout ? 34 : 30)
                        .neumorphicConvex(radius: isPadLayout ? 17 : 15)
                }
                .buttonStyle(.plain)
                .disabled(!canGoToPreviousMonth)

                Spacer()

                Text(monthTitle(for: displayedMonth))
                    .font(.system(size: scaled(18, pad: 24), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = nextMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: scaled(13, pad: 15), weight: .bold))
                        .foregroundColor(canGoToNextMonth ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.28))
                        .frame(width: isPadLayout ? 34 : 30, height: isPadLayout ? 34 : 30)
                        .neumorphicConvex(radius: isPadLayout ? 17 : 15)
                }
                .buttonStyle(.plain)
                .disabled(!canGoToNextMonth)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(weekdaySymbols(), id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: scaled(12, pad: 15), weight: .bold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.52))
                            .frame(maxWidth: .infinity)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        HStack(spacing: 10) {
                            ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                                let day = weeks[weekIndex][dayIndex]
                                let entry = entriesByKey[dateKey(for: day.date)]

                                calendarDayCell(for: day, entry: entry)
                            }
                        }
                    }
                }
            }
        }
    }

    private func taskStatsSection(taskStats: [DiaryTaskStat], timeoutStats: [DiaryTaskStat]) -> some View {
        let displayedStats = statsMode == .completed ? taskStats : timeoutStats

        return VStack(alignment: .leading, spacing: 14) {
            statsModePicker
            HStack {
                Spacer()
                statsRangePicker
            }

            if displayedStats.isEmpty {
                Text(statsMode == .completed ? L10n.noTaskCompletions : L10n.noTimeoutUnfinishedTasks)
                    .font(.system(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(displayedStats.prefix(6)), id: \.task) { item in
                        taskStatsCard(item)
                    }
                }
            }
        }
    }

    private func taskStatsCard(_ item: DiaryTaskStat) -> some View {
        let heatValues = statsHeatValues(for: item.dailyCounts)
        let columnsCount = statsHeatColumnCount
        let paddedValues = paddedHeatValues(heatValues, columns: columnsCount)
        let maxHeatValue = heatValues.max() ?? 0
        let columns = Array(repeating: GridItem(.fixed(statsHeatCellSize), spacing: statsHeatSpacing), count: columnsCount)

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.task)
                        .font(.system(size: scaled(16, pad: 20), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(L10n.completedTimesCompact(item.totalCount))
                        .font(.system(size: scaled(14, pad: 17), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: statsHeatSpacing) {
                ForEach(Array(paddedValues.enumerated()), id: \.offset) { _, value in
                    statsHeatCell(value, maxValue: maxHeatValue)
                }
            }
            .frame(width: CGFloat(columnsCount) * statsHeatCellSize + CGFloat(max(columnsCount - 1, 0)) * statsHeatSpacing, alignment: .trailing)
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .neumorphicConvex(radius: 20)
    }

    private var statsHeatColumnCount: Int {
        switch statsRange {
        case .year:
            return 6
        case .week, .month:
            return 7
        }
    }

    private var statsHeatCellSize: CGFloat {
        switch statsRange {
        case .year:
            return scaled(20, pad: 24)
        case .week, .month:
            return scaled(20, pad: 24)
        }
    }

    private var statsHeatSpacing: CGFloat {
        switch statsRange {
        case .year:
            return 4
        case .week, .month:
            return 6
        }
    }

    private func statsHeatValues(for dailyCounts: [Int]) -> [Int] {
        switch statsRange {
        case .week, .month:
            return dailyCounts
        case .year:
            return yearlyMonthValues(from: dailyCounts)
        }
    }

    private func yearlyMonthValues(from dailyCounts: [Int]) -> [Int] {
        let calendar = Calendar.current
        let referenceDate = calendar.startOfDay(for: .now)
        guard let startDate = calendar.date(byAdding: .day, value: -(max(statsRange.days, 1) - 1), to: referenceDate) else {
            return Array(repeating: 0, count: 12)
        }
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)),
              let earliestMonthStart = calendar.date(byAdding: .month, value: -11, to: currentMonthStart) else {
            return Array(repeating: 0, count: 12)
        }

        var monthValues = Array(repeating: 0, count: 12)
        for (index, value) in dailyCounts.enumerated() where value > 0 {
            guard let day = calendar.date(byAdding: .day, value: index, to: startDate),
                  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) else {
                continue
            }

            let monthOffset = calendar.dateComponents([.month], from: earliestMonthStart, to: monthStart).month ?? -1
            guard monthOffset >= 0 && monthOffset < 12 else { continue }
            monthValues[monthOffset] += value
        }

        return monthValues
    }

    private func paddedHeatValues(_ values: [Int], columns: Int) -> [Int?] {
        guard columns > 0 else { return values.map(Optional.some) }
        let remainder = values.count % columns
        let padding = remainder == 0 ? 0 : columns - remainder
        return values.map(Optional.some) + Array(repeating: nil, count: padding)
    }

    @ViewBuilder
    private func statsHeatCell(_ value: Int?, maxValue: Int) -> some View {
        let cornerRadius = statsRange == .year ? CGFloat(4) : CGFloat(6)

        if let value {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(statsHeatFillColor(value: value, maxValue: maxValue))

                if value > 0 {
                    Text(statsHeatLabel(for: value))
                        .font(.system(size: statsRange == .year ? scaled(7, pad: 8) : scaled(9, pad: 11), weight: .bold, design: .rounded))
                        .foregroundColor(statsHeatTextColor(value: value, maxValue: maxValue))
                }
            }
            .frame(width: statsHeatCellSize, height: statsHeatCellSize)
        } else {
            Color.clear
                .frame(width: statsHeatCellSize, height: statsHeatCellSize)
        }
    }

    private var statsModePicker: some View {
        HStack(spacing: 0) {
            ForEach(BingoDiaryStatsMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        statsMode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.system(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                        .foregroundColor(statsMode == mode ? .white : NeumorphicColors.text.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: scaled(42, pad: 50))
                        .background(
                            Group {
                                if statsMode == mode {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(NeumorphicColors.accent)
                                        .shadow(color: NeumorphicColors.accent.opacity(0.26), radius: 8, x: 0, y: 4)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.14), radius: 8, x: 4, y: 4)
                .shadow(color: Color.white.opacity(0.7), radius: 7, x: -4, y: -4)
        )
    }

    private func statsHeatFillColor(value: Int, maxValue: Int) -> Color {
        guard value > 0 else {
            return NeumorphicColors.text.opacity(0.08)
        }

        let normalizedMax = max(maxValue, 1)
        let ratio = Double(value) / Double(normalizedMax)

        switch ratio {
        case ..<0.25:
            return NeumorphicColors.accent.opacity(0.38)
        case ..<0.5:
            return NeumorphicColors.accent.opacity(0.52)
        case ..<0.75:
            return NeumorphicColors.accent.opacity(0.68)
        default:
            return NeumorphicColors.accent.opacity(0.84)
        }
    }

    private func statsHeatLabel(for value: Int) -> String {
        if value > 99 {
            return "99+"
        }
        return "\(value)"
    }

    private func statsHeatTextColor(value: Int, maxValue: Int) -> Color {
        guard value > 0 else { return .clear }
        let normalizedMax = max(maxValue, 1)
        let ratio = Double(value) / Double(normalizedMax)
        return ratio >= 0.58 ? .white : NeumorphicColors.text.opacity(0.86)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date)
    }

    private func weekdaySymbols() -> [String] {
        var calendar = Calendar.current
        calendar.locale = AppLanguage.displayLocale
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? calendar.shortStandaloneWeekdaySymbols
        let firstWeekdayIndex = max(calendar.firstWeekday - 1, 0)
        let reordered = Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])

        if AppLanguage.current == .english {
            return reordered.map { $0.uppercased(with: AppLanguage.displayLocale) }
        }

        return reordered
    }

    private func calendarDays(for month: Date, startDate: Date, endDate: Date) -> [DiaryCalendarDay] {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)

        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastDayOfMonth) else {
            return []
        }

        let gridStart = firstWeek.start
        let gridEnd = calendar.date(byAdding: .day, value: 7, to: lastWeek.start) ?? lastWeek.end
        var days: [DiaryCalendarDay] = []
        var cursor = gridStart

        while cursor < gridEnd {
            let normalizedDate = calendar.startOfDay(for: cursor)
            days.append(
                DiaryCalendarDay(
                    date: normalizedDate,
                    isCurrentMonth: calendar.isDate(normalizedDate, equalTo: monthInterval.start, toGranularity: .month),
                    isWithinVisibleRange: normalizedDate >= normalizedStart && normalizedDate <= normalizedEnd
                )
            )
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd
        }

        return days
    }

    private func calendarWeeks(from days: [DiaryCalendarDay]) -> [[DiaryCalendarDay]] {
        stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<min(index + 7, days.count)])
        }
    }

    private func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private var statsRangePicker: some View {
        HStack(spacing: 12) {
            ForEach(BingoDiaryStatsRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        statsRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                        .foregroundColor(statsRange == range ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.64))
                        .padding(.horizontal, 2)
                        .padding(.bottom, 6)
                        .overlay(alignment: .bottom) {
                            Capsule(style: .continuous)
                                .fill(statsRange == range ? NeumorphicColors.accent : Color.clear)
                                .frame(height: 3)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func calendarDayCell(for day: DiaryCalendarDay, entry: BingoDiaryEntry?) -> some View {
        if let entry {
            Button {
                selectedEntry = entry
            } label: {
                calendarDayLabel(for: day, entry: entry)
            }
            .buttonStyle(.plain)
        } else {
            calendarDayLabel(for: day, entry: nil)
        }
    }

    private func calendarDayLabel(for day: DiaryCalendarDay, entry: BingoDiaryEntry?) -> some View {
        let isCompleted = entry?.allTasksCompleted == true
        let hasEntry = entry != nil
        let dayNumber = Calendar.current.component(.day, from: day.date)

        return ZStack {
            if isCompleted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NeumorphicColors.accent)
                    .frame(width: 40, height: 40)
                    .shadow(color: NeumorphicColors.accent.opacity(0.22), radius: 8, x: 0, y: 4)
                    .shadow(color: Color.white.opacity(0.28), radius: 3, x: 0, y: -1)
            }

            Text("\(dayNumber)")
                .font(.system(size: scaled(14, pad: 17), weight: isCompleted ? .bold : .semibold, design: .rounded))
                .foregroundColor(calendarDayTextColor(for: day, hasEntry: hasEntry, isCompleted: isCompleted))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .contentShape(Rectangle())
    }

    private func calendarDayTextColor(for day: DiaryCalendarDay, hasEntry: Bool, isCompleted: Bool) -> Color {
        if isCompleted {
            return .white
        }

        if hasEntry {
            return NeumorphicColors.text
        }

        if day.isCurrentMonth && day.isWithinVisibleRange {
            return NeumorphicColors.text.opacity(0.34)
        }

        return NeumorphicColors.text.opacity(0.18)
    }
}

private struct DiaryCalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool
    let isWithinVisibleRange: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}

private enum BingoDiaryStatsRange: CaseIterable {
    case week
    case month
    case year

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }

    var title: String {
        switch self {
        case .week: return L10n.statsWeekShort
        case .month: return L10n.statsMonthShort
        case .year: return L10n.statsYearShort
        }
    }
}

private enum BingoDiaryStatsMode: CaseIterable {
    case completed
    case timeoutUnfinished

    var title: String {
        switch self {
        case .completed:
            return L10n.taskCompletions
        case .timeoutUnfinished:
            return L10n.timeoutUnfinishedStats
        }
    }
}

private struct BingoDiaryDetailView: View {
    let entry: BingoDiaryEntry
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    BingoDiaryBoardView(board: entry.board)
                        .frame(maxWidth: isPadLayout ? 720 : .infinity)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text(detailTitle)
                        .font(.system(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }
            }
        }
    }

    private var detailTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.dateStyle = .long
        return formatter.string(from: entry.date)
    }
}

private struct BingoDiaryBoardView: View {
    let board: SavedBoard

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let totalSpacing = spacing * CGFloat(max(board.gridSize - 1, 0))
            let cellSize = (geo.size.width - 24 - totalSpacing) / CGFloat(max(board.gridSize, 1))

            VStack(spacing: spacing) {
                ForEach(0..<board.gridSize, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<board.gridSize, id: \.self) { col in
                            if row < board.cells.count && col < board.cells[row].count {
                                BingoDiaryCellView(
                                    cell: board.cells[row][col],
                                    isInBingoLine: isInCompletedLine(row: row, col: col),
                                    isLocked: isLocked(row: row, col: col),
                                    cellSize: cellSize
                                )
                            }
                        }
                    }
                }
            }
            .padding(8)
            .padding(12)
            .neumorphicConvex(radius: 20)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func isInCompletedLine(row: Int, col: Int) -> Bool {
        for line in board.completedLines {
            switch line {
            case .row(let r): if r == row { return true }
            case .column(let c): if c == col { return true }
            case .diagonalMain: if row == col { return true }
            case .diagonalAnti: if row + col == board.gridSize - 1 { return true }
            }
        }
        return false
    }

    private func isLocked(row: Int, col: Int) -> Bool {
        let activeForced = activeForcedPositions
        guard !activeForced.isEmpty else { return false }
        return !activeForced.contains(DiaryPosition(row: row, col: col))
    }

    private var activeForcedPositions: Set<DiaryPosition> {
        var positions: Set<DiaryPosition> = []

        for row in board.cells.indices {
            for col in board.cells[row].indices {
                let cell = board.cells[row][col]
                if cell.isForced && !cell.isCompleted && !cell.isEmpty {
                    positions.insert(DiaryPosition(row: row, col: col))
                }
            }
        }

        return positions
    }

    private struct DiaryPosition: Hashable {
        let row: Int
        let col: Int
    }
}

private struct BingoDiaryCellView: View {
    let cell: BingoCell
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat

    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.sky.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .sky }
    private var bingoSurfaceColor: Color { activeTheme.bingoSurfaceColor }
    private var bingoSurfaceShadowColor: Color { activeTheme.bingoSurfaceShadowColor }
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            backgroundSurface

            if isInBingoLine {
                bingoLineContent
            } else if !cell.isEmpty {
                VStack(spacing: 2) {
                    Text(cell.text)
                        .font(.system(size: dynamicFontSize, weight: .medium))
                        .foregroundColor(isLocked ? NeumorphicColors.text.opacity(0.35) : NeumorphicColors.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(8)

                    if cell.isCompleted && !isLocked {
                        completionIcon(isLarge: false)
                    }
                }
            }

            if isLocked {
                lockOverlay
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var dynamicFontSize: CGFloat {
        let maxBaseSize: CGFloat = isPadLayout ? 22.0 : 16.0
        let minimumSize: CGFloat = isPadLayout ? 11.0 : 9.0
        let baseSize = min(cellSize * (isPadLayout ? 0.24 : 0.22), maxBaseSize)
        return cell.text.count > 6 ? max(baseSize * (isPadLayout ? 0.84 : 0.8), minimumSize) : baseSize
    }

    private var bingoLineContent: some View {
        VStack(spacing: 4) {
            Text(cell.text)
                .font(.system(size: dynamicFontSize, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            if !isLocked {
                completionIcon(isLarge: false, usesGoldSurface: true)
            }
        }
    }

    private var backgroundSurface: some View {
        Group {
            if isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(bingoSurfaceColor)
                    .shadow(color: bingoSurfaceShadowColor.opacity(0.28), radius: 7, x: 4, y: 4)
                    .shadow(color: Color.white.opacity(0.42), radius: 7, x: -4, y: -4)
            } else if cell.isCompleted {
                Color.clear
                    .neumorphicConcave(radius: 12)
            } else {
                Color.clear
                    .neumorphicConvex(radius: 12)
            }
        }
        .overlay {
            if isLocked && !isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(NeumorphicColors.background.opacity(0.62))
            }
        }
    }

    private func completionIcon(isLarge: Bool, usesGoldSurface: Bool = false) -> some View {
        let size = isLarge
            ? min(max(cellSize * 0.42, 34), 52)
            : min(max(cellSize * 0.16, 16), 22)

        return ZStack {
            Circle()
                .fill(isLarge || usesGoldSurface ? bingoSurfaceColor : NeumorphicColors.background)
                .shadow(
                    color: ((isLarge || usesGoldSurface) ? bingoSurfaceShadowColor : NeumorphicColors.darkShadow).opacity(0.3),
                    radius: isLarge ? 6 : 4,
                    x: isLarge ? 4 : 3,
                    y: isLarge ? 4 : 3
                )
                .shadow(
                    color: ((isLarge || usesGoldSurface) ? Color.white : NeumorphicColors.lightShadow).opacity(0.85),
                    radius: isLarge ? 6 : 4,
                    x: isLarge ? -4 : -3,
                    y: isLarge ? -4 : -3
                )

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor((isLarge || usesGoldSurface) ? .white : activeTheme.color)
        }
        .frame(width: size, height: size)
        .padding(.top, isLarge ? 0 : 6)
    }

    private var lockOverlay: some View {
        let size = min(max(cellSize * 0.22, 20), 28)

        return ZStack {
            Circle()
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.25), radius: 4, x: 2, y: 2)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.85), radius: 4, x: -2, y: -2)

            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
        }
        .frame(width: size, height: size)
    }
}

private struct SidebarGlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.interpolatingSpring(stiffness: 210, damping: 18)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? NeumorphicColors.accent.opacity(0.78) : Color.white.opacity(0.18))
                    .frame(width: 42, height: 24)
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(configuration.isOn ? 0.22 : 0.12),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.12), radius: 4, x: 1, y: 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.58), lineWidth: 0.6)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.14), radius: 4, x: 1.5, y: 1.5)
                    .shadow(color: Color.white.opacity(0.28), radius: 1.5, x: -0.8, y: -0.8)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BoardCountdownSheet: View {
    let countdownEndsAt: Date?
    let onSave: (Int?) -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isCountdownEnabled: Bool
    @State private var countdownHours: Int
    @State private var countdownMinutes: Int
    private let initialCountdownTotalMinutes: Int?

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(countdownEndsAt: Date?, onSave: @escaping (Int?) -> Void, onCancel: @escaping () -> Void) {
        let countdownTotalMinutes = Self.remainingMinutes(until: countdownEndsAt)
        self.countdownEndsAt = countdownEndsAt
        self.onSave = onSave
        self.onCancel = onCancel
        initialCountdownTotalMinutes = countdownTotalMinutes

        let initialTotalMinutes = countdownTotalMinutes ?? 60
        _isCountdownEnabled = State(initialValue: countdownTotalMinutes != nil)
        _countdownHours = State(initialValue: min(initialTotalMinutes / 60, 24))
        _countdownMinutes = State(initialValue: initialTotalMinutes % 60)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.boardCountdownTitle)
                                    .font(.system(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)

                                Text(L10n.boardCountdownDescription)
                                    .font(.system(size: scaled(12, pad: 14), design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.6))
                            }

                            Spacer()

                            Toggle("", isOn: $isCountdownEnabled)
                                .labelsHidden()
                                .toggleStyle(NeumorphicSwitchToggleStyle())
                        }

                        if isCountdownEnabled {
                            HStack(spacing: 12) {
                                countdownValuePicker(title: L10n.hours, valueText: L10n.hourValue(countdownHours)) {
                                    ForEach(0...24, id: \.self) { hour in
                                        Button(L10n.hourValue(hour)) {
                                            countdownHours = hour
                                            if countdownHours == 24 {
                                                countdownMinutes = 0
                                            }
                                        }
                                    }
                                }

                                countdownValuePicker(title: L10n.minutes, valueText: L10n.minuteValue(countdownMinutes)) {
                                    ForEach(minuteOptions, id: \.self) { minute in
                                        Button(L10n.minuteValue(minute)) {
                                            countdownMinutes = minute
                                        }
                                        .disabled(countdownHours == 24 && minute != 0)
                                    }
                                }
                            }

                            Text(countdownSummaryText)
                                .font(.system(size: scaled(12, pad: 14), design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.62))
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { onCancel() }
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) { onSave(resolvedTotalMinutes) }
                        .fontWeight(.semibold)
                        .foregroundColor(NeumorphicColors.accent)
                }
            }
            .onChange(of: countdownHours) { _, newHours in
                if newHours == 24 {
                    countdownMinutes = 0
                }
            }
        }
    }

    private var minuteOptions: [Int] {
        countdownHours == 24 ? [0] : Array(stride(from: 0, through: 55, by: 5))
    }

    private var totalMinutes: Int {
        min((countdownHours * 60) + countdownMinutes, BingoViewModel.maxCountdownMinutes)
    }

    private var resolvedTotalMinutes: Int? {
        guard isCountdownEnabled else { return nil }
        return max(totalMinutes, 1)
    }

    private var countdownSummaryText: String {
        if totalMinutes == BingoViewModel.maxCountdownMinutes {
            return L10n.boardWillClearIn24Hours
        }
        return L10n.boardWillClearIn(hours: countdownHours, minutes: countdownMinutes)
    }

    @ViewBuilder
    private func countdownValuePicker(title: String, valueText: String, @ViewBuilder content: () -> some View) -> some View {
        Menu {
            content()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.66))

                HStack {
                    Text(valueText)
                        .font(.system(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: scaled(11, pad: 13), weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.clear.neumorphicConvex(radius: 12))
            }
        }
        .buttonStyle(.plain)
    }

    private static func remainingMinutes(until date: Date?) -> Int? {
        guard let date, date > Date() else { return nil }
        let seconds = date.timeIntervalSinceNow
        let totalMinutes = Int(ceil(seconds / 60))
        return min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }
}

// MARK: - Celebration View
struct CelebrationView: View {
    @State private var confettiItems: [ConfettiItem] = []

    struct ConfettiItem: Identifiable {
        let id: Int
        let emoji: String
        let fontSize: CGFloat
        let startX: CGFloat
        let endX: CGFloat
        let duration: Double
        let delay: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(confettiItems) { item in
                    ConfettiPiece(item: item, height: geo.size.height)
                }
            }
            .onAppear { generateConfetti(in: geo.size) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func generateConfetti(in size: CGSize) {
        let emojis = ["🎉", "⭐️", "✨", "🎊", "💫", "🌟", "🎯", "🏆"]
        confettiItems = (0..<25).map { i in
            ConfettiItem(
                id: i,
                emoji: emojis[i % emojis.count],
                fontSize: CGFloat.random(in: 18...34),
                startX: CGFloat.random(in: 0...size.width),
                endX: CGFloat.random(in: -60...60),
                duration: Double.random(in: 1.2...2.2),
                delay: Double.random(in: 0...0.6)
            )
        }
    }
}

struct ConfettiPiece: View {
    let item: CelebrationView.ConfettiItem
    let height: CGFloat
    @State private var animate = false

    var body: some View {
        Text(item.emoji)
            .font(.system(size: item.fontSize))
            .offset(
                x: item.startX + (animate ? item.endX : 0),
                y: animate ? height + 50 : -50
            )
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: item.duration).delay(item.delay)) {
                    animate = true
                }
            }
    }
}
