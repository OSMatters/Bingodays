import SwiftUI
import UIKit

struct PointsFlowPresenter: View {
    let isPadLayout: Bool
    let totalPoints: Int
    @ObservedObject var pointsFeatureStore: PointsFeatureStore
    @Binding var limitedOfferState: LimitedOfferHomeState
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    var showsCloseButton = true
    var bottomContentPadding: CGFloat = 32
    var onSubpagePresentationChange: (Bool) -> Void = { _ in }
    var enteredFromBottomTab = false
    var isActive = true
    let onAddStickerToHomeSuccess: () -> Void

    @State private var isShowingBlindBoxPremiumPaywall = false
    @State private var blindBoxPurchaseTransactionID: String?
    @State private var rewardsSubpagePresented = false
    @State private var portalPresented = false

    var body: some View {
        rewardsContent
        .fullScreenCover(isPresented: $isShowingBlindBoxPremiumPaywall, onDismiss: {
            NotificationCenter.default.post(name: BlindBoxPremiumPaywallEntry.didDismiss, object: blindBoxPurchaseTransactionID)
            blindBoxPurchaseTransactionID = nil
        }) {
            PremiumPaywallView(
                entrySource: BlindBoxPremiumPaywallEntry.source,
                limitedOfferState: $limitedOfferState,
                onPurchaseCompleted: { blindBoxPurchaseTransactionID = $0 }
            )
        }
        .onChange(of: suppressesTabBar, initial: true) { _, value in
            onSubpagePresentationChange(value)
        }
    }

    private func rewardsPortal(_ content: AnyView) -> AnyView {
        AnyView(
        BlindBoxPullPortal(
            enteredFromBottomTab: enteredFromBottomTab,
            isEnabled: AppDebugFlags.blindBoxLiveFlowEnabled || AppDebugFlags.blindBoxPreviewEnabled,
            isActive: isActive,
            isRewardsSubpagePresented: rewardsSubpagePresented,
            onPresentationChange: { presented in
                portalPresented = presented
            }
        ) {
            content
        } blindBox: { close in
            if AppDebugFlags.blindBoxLiveFlowEnabled {
                BlindBoxLiveFlowView(
                    pointsFeatureStore: pointsFeatureStore,
                    totalPoints: totalPoints,
                    onSelectCustomRewards: close,
                    onShowPremiumPaywall: {
                        isShowingBlindBoxPremiumPaywall = true
                    },
                    isBlindBoxStickerOnHome: pointsFeatureStore.isBlindBoxStickerOnHome,
                    onAddBlindBoxStickerToHome: addBlindBoxStickerToHome
                )
            } else {
                BlindBoxFlowView(
                    previewAvailablePoints: availablePoints,
                    onSelectCustomRewards: close,
                    onShowPremiumPaywall: {
                        isShowingBlindBoxPremiumPaywall = true
                    },
                    isBlindBoxStickerOnHome: pointsFeatureStore.isBlindBoxStickerOnHome,
                    onAddBlindBoxStickerToHome: addBlindBoxStickerToHome
                )
            }
        }
        .onDisappear { portalPresented = false }
        )
    }

    private var suppressesTabBar: Bool {
        isActive && (portalPresented || rewardsSubpagePresented || isShowingBlindBoxPremiumPaywall)
    }

    private var availablePoints: Int {
        pointsFeatureStore.availablePoints(totalPoints: totalPoints)
    }

    private func addBlindBoxStickerToHome(_ sticker: BlindBoxStickerDefinition) -> Bool {
        guard pointsFeatureStore.addBlindBoxStickerToHome(sticker) else { return false }
        onAddStickerToHomeSuccess()
        return true
    }

    private var rewardsContent: some View {
        PointsFlowSheet(
                    isPadLayout: isPadLayout,
                    points: availablePoints,
                    limitedOfferState: $limitedOfferState,
                    showsCloseButton: showsCloseButton,
                    bottomContentPadding: bottomContentPadding,
                    onSubpagePresentationChange: { presented in
                        rewardsSubpagePresented = presented
                    },
                    inventoryCounts: pointsFeatureStore.stickerInventoryCounts,
                    usedCounts: pointsFeatureStore.currentStickerUsageCounts,
                    rewards: pointsFeatureStore.activeRewards,
                    redemptionHistory: pointsFeatureStore.redemptionHistory,
                    onRedeemSticker: { kind in
                        pointsFeatureStore.redeemSticker(kind, totalPoints: totalPoints)
                    },
                    onAddStickerToHome: { kind in
                        if pointsFeatureStore.addStickerToHome(kind) {
                            onAddStickerToHomeSuccess()
                        }
                    },
                    onDeleteReward: { reward in
                        pointsFeatureStore.archiveReward(reward)
                    },
                    onRedeemReward: { reward in
                        pointsFeatureStore.redeemReward(reward, totalPoints: totalPoints)
                    },
                    onCreateReward: { title, requiredPoints, emoji, themeImageName in
                        pointsFeatureStore.createRewardResult(
                            title: title,
                            requiredPoints: requiredPoints,
                            emoji: emoji,
                            themeImageName: themeImageName,
                            hasPremiumAccess: subscriptionManager.hasPremiumAccess
                        )
                    },
                    canCreateReward: {
                        pointsFeatureStore.canCreateReward(hasPremiumAccess: subscriptionManager.hasPremiumAccess)
                    },
                    onUpdateReward: { reward, title, requiredPoints, emoji, themeImageName in
                        pointsFeatureStore.updateReward(
                            CustomReward(
                                id: reward.id,
                                title: title,
                                requiredPoints: requiredPoints,
                                emoji: emoji,
                                themeImageName: themeImageName,
                                cardStyleVersion: CustomReward.currentCardStyleVersion,
                                redemptionCount: reward.redemptionCount,
                                totalSpentPoints: reward.totalSpentPoints,
                                isArchived: reward.isArchived
                            )
                        )
                    },
                    onReorderRewards: { orderedRewards in
                        pointsFeatureStore.reorderRewards(orderedRewards)
                    },
                    wrapDetails: rewardsPortal
                )
    }
}

struct PointsFlowSheet: View {
    private enum Screen {
        case details
        case rewardEditor(CustomReward?)
        case rewardReorder
    }

    let isPadLayout: Bool
    let points: Int
    @Binding var limitedOfferState: LimitedOfferHomeState
    let showsCloseButton: Bool
    let bottomContentPadding: CGFloat
    let onSubpagePresentationChange: (Bool) -> Void
    let inventoryCounts: [StickerKind: Int]
    let usedCounts: [StickerKind: Int]
    let rewards: [CustomReward]
    let redemptionHistory: [PointRedemptionRecord]
    let onRedeemSticker: (StickerKind) -> Void
    let onAddStickerToHome: (StickerKind) -> Void
    let onDeleteReward: (CustomReward) -> Void
    let onRedeemReward: (CustomReward) -> Void
    let onCreateReward: (String, Int, String, String?) -> CustomRewardCreationResult
    let canCreateReward: () -> Bool
    let onUpdateReward: (CustomReward, String, Int, String, String?) -> CustomRewardCreationResult
    let onReorderRewards: ([CustomReward]) -> Bool
    let wrapDetails: (AnyView) -> AnyView

    @State private var screen: Screen = .details
    @State private var detailsInitialTab: PointsTab = .rewards
    @State private var selectedStickerForDetail: StickerKind?
    @State private var selectedRewardForDetail: CustomReward?
    @State private var isPremiumPaywallPresented = false
    @State private var isDetailsPresentationPresented = false
    @State private var premiumPaywallSource = "custom_reward_limit_create"
    @State private var isSavingNewReward = false
    @State private var rewardSaveFailureMessage: String?
    @State private var rewardSaveTask: Task<Void, Never>?
    @State private var rewardSaveOperationID: UUID?
    @State private var pendingCreateAfterPaywall = false
    @State private var paywallPresentationID: UUID?
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        ZStack {
            switch screen {
            case .details:
                wrapDetails(AnyView(detailsContent))
            case .rewardEditor(let reward):
                RewardEditorSheet(
                    reward: reward,
                    isSaving: reward == nil && isSavingNewReward,
                    onSave: { title, requiredPoints, emoji, themeImageName in
                        if let reward {
                            finishRewardSave(onUpdateReward(reward, title, requiredPoints, emoji, themeImageName))
                        } else {
                            saveNewReward(
                                title: title,
                                requiredPoints: requiredPoints,
                                emoji: emoji,
                                themeImageName: themeImageName
                            )
                        }
                    },
                    onDelete: reward.map { reward in
                        {
                            onDeleteReward(reward)
                            detailsInitialTab = .rewards
                            screen = .details
                        }
                    },
                    onCancel: {
                        cancelPendingRewardSave()
                        detailsInitialTab = .rewards
                        screen = .details
                    }
                )
            case .rewardReorder:
                RewardReorderListView(
                    rewards: rewards,
                    isPadLayout: isPadLayout,
                    onSave: { orderedRewards in
                        guard onReorderRewards(orderedRewards) else { return false }
                        detailsInitialTab = .rewards
                        screen = .details
                        return true
                    },
                    onCancel: {
                        detailsInitialTab = .rewards
                        screen = .details
                    }
                )
            }

            if let selectedStickerForDetail {
                PointsStickerActionOverlay(
                    sticker: selectedStickerForDetail,
                    isOwned: (inventoryCounts[selectedStickerForDetail] ?? 0) > 0,
                    isPlacedOnHome: (usedCounts[selectedStickerForDetail] ?? 0) > 0,
                    canRedeem: points >= selectedStickerForDetail.requiredPoints,
                    isPadLayout: isPadLayout,
                    onPrimary: {
                        if (inventoryCounts[selectedStickerForDetail] ?? 0) > 0 {
                            onAddStickerToHome(selectedStickerForDetail)
                            self.selectedStickerForDetail = nil
                        } else {
                            onRedeemSticker(selectedStickerForDetail)
                        }
                    },
                    onCancel: {
                        self.selectedStickerForDetail = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(10)
            }

            if let selectedRewardForDetail {
                PointsRewardRedeemOverlay(
                    reward: selectedRewardForDetail,
                    isPadLayout: isPadLayout,
                    onRedeem: {
                        onRedeemReward(selectedRewardForDetail)
                    },
                    onCancel: {
                        self.selectedRewardForDetail = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(10)
            }
        }
        .fullScreenCover(isPresented: $isPremiumPaywallPresented, onDismiss: resumePendingRewardCreation) {
            PremiumPaywallView(
                entrySource: premiumPaywallSource,
                limitedOfferState: $limitedOfferState
            )
        }
        .alert(
            L10n.tr("Unable to save reward", zhHans: "无法保存奖励", zhHant: "無法儲存獎勵", ja: "報酬を保存できません"),
            isPresented: rewardSaveFailureBinding
        ) {
            Button(L10n.ok, role: .cancel) {
                rewardSaveFailureMessage = nil
            }
        } message: {
            Text(rewardSaveFailureMessage ?? "")
        }
        .onAppear {
            onSubpagePresentationChange(isSubpagePresented)
        }
        .onDisappear { cancelPendingRewardSave() }
        .onChange(of: isSubpagePresented) { _, isPresented in
            onSubpagePresentationChange(isPresented)
        }
    }

    private var isSubpagePresented: Bool {
        switch screen {
        case .details:
            return selectedStickerForDetail != nil || selectedRewardForDetail != nil ||
                isPremiumPaywallPresented || isDetailsPresentationPresented
        case .rewardEditor:
            return true
        case .rewardReorder:
            return true
        }
    }

    private var rewardSaveFailureBinding: Binding<Bool> {
        Binding(
            get: { rewardSaveFailureMessage != nil },
            set: { isPresented in
                if !isPresented {
                    rewardSaveFailureMessage = nil
                }
            }
        )
    }

    private func handleCreateRewardRequest(source: String = "custom_reward_limit_create") {
        DiagnosticLogStore.recordUserAction("custom_reward.add_requested", details: [
            "active_count": "\(rewards.count)", "has_premium": "\(subscriptionManager.hasPremiumAccess)"
        ])
        if canCreateReward() {
            detailsInitialTab = .rewards
            screen = .rewardEditor(nil)
            return
        }

        presentCustomRewardPremiumPaywall(source: source)
    }

    private func saveNewReward(
        title: String,
        requiredPoints: Int,
        emoji: String,
        themeImageName: String?
    ) {
        guard !isSavingNewReward else { return }
        isSavingNewReward = true
        let operationID = UUID()
        rewardSaveOperationID = operationID

        rewardSaveTask = Task { @MainActor in
            defer {
                if rewardSaveOperationID == operationID {
                    isSavingNewReward = false
                    rewardSaveOperationID = nil
                    rewardSaveTask = nil
                }
            }
            guard !Task.isCancelled, rewardSaveOperationID == operationID else { return }

            let initialResult = onCreateReward(title, requiredPoints, emoji, themeImageName)
            guard initialResult == .premiumRequired else {
                finishRewardSave(initialResult)
                return
            }

            // A real device can enter the points flow before RevenueCat has
            // finished applying the cached entitlement. Refresh only after
            // the authoritative store rejects the save, then retry once with
            // the refreshed access state.
            await subscriptionManager.refreshEntitlements()
            guard !Task.isCancelled, rewardSaveOperationID == operationID else { return }

            guard subscriptionManager.hasPremiumAccess else {
                presentCustomRewardPremiumPaywall(source: "custom_reward_limit_save")
                return
            }

            finishRewardSave(onCreateReward(title, requiredPoints, emoji, themeImageName))
        }
    }

    private func cancelPendingRewardSave() {
        rewardSaveTask?.cancel()
        rewardSaveTask = nil
        rewardSaveOperationID = nil
        isSavingNewReward = false
    }

    private func finishRewardSave(_ result: CustomRewardCreationResult) {
        DiagnosticLogStore.recordStateChange("custom_reward.save_result", details: [
            "result": "\(result)", "active_count": "\(rewards.count)",
            "has_premium": "\(subscriptionManager.hasPremiumAccess)"
        ])
        switch result {
        case .created:
            detailsInitialTab = .rewards
            screen = .details
        case .premiumRequired:
            presentCustomRewardPremiumPaywall(source: "custom_reward_limit_save")
        case .invalidInput:
            rewardSaveFailureMessage = L10n.tr("Check the reward name and points.", zhHans: "请检查奖励名称和兑换积分。", zhHant: "請檢查獎勵名稱和兌換積分。", ja: "報酬名と交換ポイントを確認してください。")
        case .rewardUnavailable:
            rewardSaveFailureMessage = L10n.tr("This reward is no longer available. Reopen the reward list.", zhHans: "此奖励已不存在，请重新打开奖励列表。", zhHant: "此獎勵已不存在，請重新開啟獎勵列表。", ja: "この報酬は利用できません。報酬一覧を開き直してください。")
        case .dataChanged:
            rewardSaveFailureMessage = L10n.tr("Rewards changed while you were editing. Your input is kept; please try saving again.", zhHans: "编辑期间奖励数据发生变化，已保留输入，请再次保存。", zhHant: "編輯期間獎勵資料發生變化，已保留輸入，請再次儲存。", ja: "編集中に報酬データが変更されました。入力内容を保持しています。再度保存してください。")
        case .persistenceFailed:
            rewardSaveFailureMessage = L10n.tr("Couldn't save. Your changes are kept here; please try again.", zhHans: "保存失败，已保留当前输入，请重试。", zhHant: "儲存失敗，已保留目前輸入，請重試。", ja: "保存できませんでした。入力内容は保持されています。再試行してください。")
        }
    }

    private func resumePendingRewardCreation() {
        paywallPresentationID = nil
        defer { pendingCreateAfterPaywall = false }
        guard pendingCreateAfterPaywall, subscriptionManager.hasPremiumAccess else { return }
        if case .details = screen {
            detailsInitialTab = .rewards
            screen = .rewardEditor(nil)
        }
        // An existing editor stays mounted so its draft survives the paywall.
    }

    private func presentCustomRewardPremiumPaywall(source: String) {
        AnalyticsService.logPremiumCustomRewardsLimitHit(
            currentRewardCount: rewards.count,
            source: source
        )
        premiumPaywallSource = source
        pendingCreateAfterPaywall = true
        let presentationID = UUID()
        paywallPresentationID = presentationID
        isPremiumPaywallPresented = true
        Task { @MainActor in
            await subscriptionManager.refreshEntitlements()
            guard paywallPresentationID == presentationID, isPremiumPaywallPresented else { return }
            if subscriptionManager.hasPremiumAccess {
                isPremiumPaywallPresented = false
            }
        }
    }

    @ViewBuilder
    private var detailsContent: some View {
        let content = PointsDetailSheet(
            initialTab: detailsInitialTab,
            points: points,
            showsCloseButton: showsCloseButton,
            bottomContentPadding: bottomContentPadding,
            inventoryCounts: inventoryCounts,
            usedCounts: usedCounts,
            rewards: rewards,
            redemptionHistory: redemptionHistory,
            onRedeem: onRedeemSticker,
            onAddToHome: onAddStickerToHome,
            onDeleteReward: onDeleteReward,
            onRedeemReward: onRedeemReward,
            onRequestCreateReward: {
                handleCreateRewardRequest()
            },
            onRequestEditReward: { reward in
                detailsInitialTab = .rewards
                screen = .rewardEditor(reward)
            },
            onRequestReorderRewards: {
                detailsInitialTab = .rewards
                screen = .rewardReorder
            },
            onSelectSticker: { sticker in
                selectedStickerForDetail = sticker
            },
            onSelectReward: { reward in
                selectedRewardForDetail = reward
            },
            onPresentationChange: { isDetailsPresentationPresented = $0 }
        )

        content
    }
}

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

private struct PointsDetailSheet: View {
    let points: Int
    let showsCloseButton: Bool
    let bottomContentPadding: CGFloat
    let inventoryCounts: [StickerKind: Int]
    let usedCounts: [StickerKind: Int]
    let rewards: [CustomReward]
    let redemptionHistory: [PointRedemptionRecord]
    let onRedeem: (StickerKind) -> Void
    let onAddToHome: (StickerKind) -> Void
    let onDeleteReward: (CustomReward) -> Void
    let onRedeemReward: (CustomReward) -> Void
    let onRequestCreateReward: () -> Void
    let onRequestEditReward: (CustomReward) -> Void
    let onRequestReorderRewards: () -> Void
    let onSelectSticker: (StickerKind) -> Void
    let onSelectReward: (CustomReward) -> Void
    let onPresentationChange: (Bool) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PointsTab
    @State private var actionRewardID: UUID?
    @State private var pendingDeleteReward: CustomReward?
    @State private var isDeleteActionSheetPresented = false
    @State private var isHistoryPresented = false

    init(
        initialTab: PointsTab,
        points: Int,
        showsCloseButton: Bool,
        bottomContentPadding: CGFloat,
        inventoryCounts: [StickerKind: Int],
        usedCounts: [StickerKind: Int],
        rewards: [CustomReward],
        redemptionHistory: [PointRedemptionRecord],
        onRedeem: @escaping (StickerKind) -> Void,
        onAddToHome: @escaping (StickerKind) -> Void,
        onDeleteReward: @escaping (CustomReward) -> Void,
        onRedeemReward: @escaping (CustomReward) -> Void,
        onRequestCreateReward: @escaping () -> Void,
        onRequestEditReward: @escaping (CustomReward) -> Void,
        onRequestReorderRewards: @escaping () -> Void,
        onSelectSticker: @escaping (StickerKind) -> Void,
        onSelectReward: @escaping (CustomReward) -> Void,
        onPresentationChange: @escaping (Bool) -> Void
    ) {
        self.points = points
        self.showsCloseButton = showsCloseButton
        self.bottomContentPadding = bottomContentPadding
        self.inventoryCounts = inventoryCounts
        self.usedCounts = usedCounts
        self.rewards = rewards
        self.redemptionHistory = redemptionHistory
        self.onRedeem = onRedeem
        self.onAddToHome = onAddToHome
        self.onDeleteReward = onDeleteReward
        self.onRedeemReward = onRedeemReward
        self.onRequestCreateReward = onRequestCreateReward
        self.onRequestEditReward = onRequestEditReward
        self.onRequestReorderRewards = onRequestReorderRewards
        self.onSelectSticker = onSelectSticker
        self.onSelectReward = onSelectReward
        self.onPresentationChange = onPresentationChange
        _selectedTab = State(initialValue: initialTab)
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var isPadDevice: Bool {
        // Presentation and card sizing follow the active window, not the physical device.
        isPadLayout
    }

    private var usesPadBottomHalfSheet: Bool {
        isPadDevice
    }

    private var contentMaxWidth: CGFloat {
        isPadLayout ? 820 : .infinity
    }

    private var activeTheme: AppTheme { .concise }
    private var themeColor: Color { activeTheme.color }
    private var themeShadowColor: Color { activeTheme.bingoSurfaceShadowColor }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var stickerGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: scaled(18, pad: 28)), count: 3)
    }

    private var rewardGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: scaled(6, pad: 10)), count: 2)
    }

    private var stickerCatalog: [StickerKind] {
        [
            .akita,
            .orangeCat,
            .chineseVillageDog,
            .pomeranian,
            .yorkshire,
            .dachshund,
            .alaskanMalamute,
            .goldenRetriever,
            .maineCoon,
            .toyPoodle,
            .cowCatStar,
            .ragdollCatStar
        ]
    }

    var body: some View {
        pointsContent
    }

    private var pointsContent: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PointsRewardBackground(theme: activeTheme)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: scaled(20, pad: 28)) {
                        VStack(spacing: scaled(2, pad: 4)) {
                            HStack(alignment: .center, spacing: scaled(8, pad: 10)) {
                                Text("\(points)")
                                    .font(.appSystem(size: scaled(50, pad: 64), weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)

                                Image(systemName: "star.fill")
                                    .font(.appSystem(size: scaled(21, pad: 26), weight: .bold))
                                    .foregroundColor(themeColor)
                                    .offset(y: scaled(3, pad: 4))
                            }

                            Text(L10n.myPoints)
                                .font(.appSystem(size: scaled(16, pad: 19), weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.52))
                        }
                        .padding(.top, scaled(-12, pad: -8))

                        if selectedTab == .stickers {
                            LazyVGrid(
                                columns: stickerGridColumns,
                                spacing: scaled(24, pad: 36)
                            ) {
                                ForEach(stickerCatalog) { kind in
                                    stickerCard(kind)
                                }
                            }
                            .padding(.top, scaled(4, pad: 8))
                        } else if rewards.isEmpty {
                            emptyRewardsState
                                .padding(.top, scaled(118, pad: 150))
                        } else {
                            LazyVGrid(columns: rewardGridColumns, spacing: scaled(8, pad: 12)) {
                                addRewardCard

                                ForEach(rewards) { reward in
                                    rewardCard(reward)
                                }
                            }
                            .padding(.top, scaled(8, pad: 12))
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, scaled(20, pad: 32))
                    .padding(.top, scaled(64, pad: 82))
                    .padding(
                        .bottom,
                        max(
                            32,
                            bottomContentPadding
                        )
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: RewardsScrollTopPreference.self,
                                value: geometry.frame(in: .named("rewardsScroll")).minY
                            )
                        }
                    }
                }
                .coordinateSpace(name: "rewardsScroll")
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if actionRewardID != nil {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                                actionRewardID = nil
                            }
                        }
                    }
                )

                pointsHeader
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, scaled(20, pad: 32))
                    .padding(.top, scaled(12, pad: 18))
                    .zIndex(3)
            }
            .confirmationDialog(
                L10n.tr("Delete Reward?", zhHans: "删除奖励？", zhHant: "刪除獎勵？", ja: "報酬を削除しますか？"),
                isPresented: $isDeleteActionSheetPresented,
                titleVisibility: .visible
            ) {
                Button(L10n.deleteReward, role: .destructive) {
                    if let pendingDeleteReward {
                        onDeleteReward(pendingDeleteReward)
                    }
                    pendingDeleteReward = nil
                }
                Button(L10n.cancel, role: .cancel) {
                    pendingDeleteReward = nil
                }
            } message: {
                Text(L10n.tr("This action cannot be undone.", zhHans: "删除后无法恢复。", zhHant: "刪除後無法復原。", ja: "この操作は取り消せません。"))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .adaptivePadBottomHalfSheet(
                isPresented: $isHistoryPresented,
                usePadPresentation: usesPadBottomHalfSheet,
                backgroundColor: NeumorphicColors.background,
                contentMaxWidth: 860
            ) {
                PointsRedemptionHistorySheet(
                    inventoryCounts: inventoryCounts,
                    rewards: rewards,
                    records: redemptionHistory,
                    isPadLayout: isPadLayout,
                    onClose: usesPadBottomHalfSheet ? {
                        isHistoryPresented = false
                    } : nil
                )
            }
            .onChange(of: isHistoryPresented || isDeleteActionSheetPresented || actionRewardID != nil, initial: true) { _, isPresented in
                onPresentationChange(isPresented)
            }
        }
    }

    private var pointsHeader: some View {
        HStack {
            if showsCloseButton {
                Button {
                    dismiss()
                } label: {
                    LiquidGlassIconBadge(
                        systemName: "chevron.left",
                        size: scaled(44, pad: 52),
                        iconSize: scaled(18, pad: 22),
                        foregroundColor: NeumorphicColors.text
                    )
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: scaled(44, pad: 52), height: scaled(44, pad: 52))
            }

            Spacer()

            HStack(spacing: scaled(10, pad: 12)) {
                if selectedTab == .rewards && rewards.count > 1 {
                    Button {
                        onRequestReorderRewards()
                    } label: {
                        LiquidGlassIconBadge(
                            systemName: "arrow.up.arrow.down",
                            size: scaled(44, pad: 52),
                            iconSize: scaled(18, pad: 22),
                            usesLiquidGlass: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.reorderRewards)
                }

                Button {
                    isHistoryPresented = true
                } label: {
                    LiquidGlassIconBadge(
                        imageName: "HistoryIcon",
                        size: scaled(44, pad: 52),
                        iconSize: scaled(26, pad: 30),
                        usesLiquidGlass: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Reward history", zhHans: "奖励历史", zhHant: "獎勵歷史", ja: "報酬履歴"))
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(PointsTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(0)
        .frame(height: scaled(36, pad: 44))
        .background(
            Capsule(style: .continuous)
                .fill(themeColor.opacity(activeTheme == .concise ? 0.12 : 0.14))
        )
    }

    private func tabButton(_ tab: PointsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedTab = tab
            }
        } label: {
                Text(tab.title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : NeumorphicColors.text.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: scaled(36, pad: 44))
                .background(tabBackground(isSelected: isSelected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func tabBackground(isSelected: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isSelected ? themeColor : .clear)
            .shadow(color: isSelected ? themeShadowColor.opacity(0.18) : .clear, radius: 6, x: 0, y: 3)
    }

    private func stickerCard(_ sticker: StickerKind) -> some View {
        let inventoryCount = inventoryCounts[sticker] ?? 0
        let hasOwned = inventoryCount > 0

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                onSelectSticker(sticker)
            }
        } label: {
            ZStack {
                if hasOwned {
                    Image(sticker.unlockedImageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: scaled(116, pad: 150))
                        .shadow(color: Color(red: 0.45, green: 0.29, blue: 0.13).opacity(0.18), radius: 6, x: 0, y: 5)
                } else {
                    Image(sticker.lockedImageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: scaled(116, pad: 150))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: scaled(120, pad: 158))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(0.8)
    }

    private var emptyRewardsState: some View {
        VStack(spacing: scaled(28, pad: 34)) {
            Image("CustomRewardEmpty")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: scaled(185, pad: 240), height: scaled(142, pad: 184))

            Text(L10n.emptyCustomRewardsMessage)
                .font(.appSystem(size: scaled(16, pad: 19), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, scaled(18, pad: 24))

            Button {
                onRequestCreateReward()
            } label: {
                Text(L10n.addRewards)
                    .font(.appSystem(size: scaled(16, pad: 16), weight: .heavy, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(width: scaled(158, pad: 196), height: scaled(42, pad: 52))
                    .appLiquidGlass(in: Capsule(style: .continuous), interactive: true)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func rewardCard(_ reward: CustomReward) -> some View {
        let canRedeem = points >= reward.requiredPoints
        let isShowingActions = actionRewardID == reward.id

        return ZStack(alignment: .top) {
            Image(reward.themeImageName ?? "CustomRewardDefaultCard")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .saturation(canRedeem ? 1 : 0)
                .brightness(canRedeem ? 0 : -0.02)
                .shadow(color: Color(red: 0.67, green: 0.48, blue: 0.23).opacity(0.14), radius: 12, x: 0, y: 8)

            VStack(spacing: 0) {
                if reward.themeImageName != nil {
                    Color.clear
                    .frame(height: scaled(118, pad: 150))
                } else {
                    rewardCardEmoji(reward.displayEmoji, canRedeem: canRedeem)
                }

                Spacer(minLength: scaled(8, pad: 10))

                Text(reward.title)
                    .font(.appSystem(size: scaled(15, pad: 27), weight: .heavy, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, scaled(14, pad: 18))
                    .offset(y: scaled(-11, pad: 34))

                Text("\(reward.requiredPoints) pts")
                    .font(.appSystem(size: scaled(12, pad: 22), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .padding(.top, scaled(4, pad: 15))
                    .offset(y: scaled(-3, pad: 47))

                Spacer(minLength: scaled(8, pad: 10))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if reward.redemptionCount > 0 {
                Text("x\(reward.redemptionCount)")
                    .font(.appSystem(size: scaled(11, pad: 13), weight: .heavy, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
                    .padding(.top, scaled(10, pad: 12))
            }

            if isShowingActions {
                rewardActionOverlay(for: reward)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(187.0 / 227.0, contentMode: .fit)
        .scaleEffect(1.05)
        .opacity(canRedeem ? 1 : 0.82)
        .contentShape(Rectangle())
        .onTapGesture {
            if isShowingActions {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    actionRewardID = nil
                }
            } else if canRedeem {
                onSelectReward(reward)
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            guard actionRewardID != reward.id else { return }
            AppHaptics.control()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                actionRewardID = reward.id
            }
        }
    }

    private var addRewardCard: some View {
        Button(action: onRequestCreateReward) {
            ZStack {
                Image("CustomRewardAddCard")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .shadow(
                        color: Color(red: 0.67, green: 0.48, blue: 0.23).opacity(0.14),
                        radius: 12,
                        x: 0,
                        y: 8
                    )

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: scaled(118, pad: 150))
                        .offset(y: scaled(4, pad: 6))

                    Spacer(minLength: scaled(8, pad: 10))

                    Text(L10n.addRewards)
                        .font(.appSystem(size: scaled(15, pad: 27), weight: .heavy, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, scaled(14, pad: 18))
                        .offset(y: scaled(-3, pad: 42))

                    Spacer(minLength: scaled(32, pad: 40))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(187.0 / 227.0, contentMode: .fit)
            .scaleEffect(1.05)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.addRewards)
    }

    @ViewBuilder
    private func rewardCardEmoji(_ emoji: String, canRedeem: Bool) -> some View {
        if isPadDevice {
            GeometryReader { proxy in
                let artworkHeight = proxy.size.height * 1.3
                let fontSize = min(proxy.size.width * 0.52, artworkHeight * 0.86)
                let verticalOffset: CGFloat = 30

                Text(emoji)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: proxy.size.width, height: artworkHeight)
                    .offset(y: verticalOffset)
                    .frame(
                        width: proxy.size.width,
                        height: artworkHeight + verticalOffset,
                        alignment: .top
                    )
                    .clipped()
            }
            .frame(height: scaled(118, pad: 150))
            .padding(.top, scaled(10, pad: 14))
            .saturation(canRedeem ? 1 : 0)
            .opacity(canRedeem ? 1 : 0.55)
        } else {
            Text(emoji)
                .font(.system(size: scaled(81.2, pad: 225.6)))
                .frame(height: scaled(118, pad: 150))
                .padding(.top, scaled(10, pad: 14))
                .saturation(canRedeem ? 1 : 0)
                .opacity(canRedeem ? 1 : 0.55)
        }
    }

    private func rewardActionOverlay(for reward: CustomReward) -> some View {
        ZStack {
            Color.black.opacity(0.5)

            VStack(spacing: scaled(8, pad: 10)) {
                Button {
                    actionRewardID = nil
                    onRequestEditReward(reward)
                } label: {
                    Text(L10n.editReward)
                        .font(.appSystem(size: scaled(13, pad: 16), weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: scaled(30, pad: 38))
                        .background(
                            Capsule(style: .continuous)
                                .fill(themeColor)
                                .shadow(color: themeShadowColor.opacity(0.22), radius: 6, x: 0, y: 3)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    actionRewardID = nil
                    pendingDeleteReward = reward
                    isDeleteActionSheetPresented = true
                } label: {
                    Text(L10n.deleteReward)
                        .font(.appSystem(size: scaled(13, pad: 16), weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.66, green: 0.18, blue: 0.20))
                        .frame(maxWidth: .infinity)
                        .frame(height: scaled(30, pad: 38))
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.95))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color(red: 0.82, green: 0.20, blue: 0.22), lineWidth: 1.25)
                                )
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, scaled(24, pad: 30))
            .padding(.top, scaled(20, pad: 26))
        }
        .mask {
            Image("CustomRewardDefaultCard")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }

    private func themedOutlineSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(themeColor.opacity(activeTheme == .concise ? 0.08 : 0.1))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(themeShadowColor.opacity(0.28), lineWidth: 1)
            )
    }

    private func flatStickerCardSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(themeColor.opacity(activeTheme == .concise ? 0.07 : 0.09))
    }

    private func flatStickerButtonSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(themeColor.opacity(activeTheme == .concise ? 0.09 : 0.11))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(themeShadowColor.opacity(0.18), lineWidth: 0.8)
            )
    }

}

private struct RewardReorderListView: View {
    let rewards: [CustomReward]
    let isPadLayout: Bool
    let onSave: ([CustomReward]) -> Bool
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftRewards: [CustomReward]
    @State private var draggingRewardID: UUID?
    @State private var dragStartIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var saveErrorMessage: String?

    init(
        rewards: [CustomReward],
        isPadLayout: Bool,
        onSave: @escaping ([CustomReward]) -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.rewards = rewards
        self.isPadLayout = isPadLayout
        self.onSave = onSave
        self.onCancel = onCancel
        _draftRewards = State(initialValue: rewards)
    }

    private var didChangeOrder: Bool {
        draftRewards.map(\.id) != rewards.map(\.id)
    }

    private var rowHeight: CGFloat {
        isPadLayout ? 72 : 64
    }

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.18, extraBounce: 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.rewardOrderHint)
                        .font(.appSystem(size: isPadLayout ? 16 : 14, weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.58))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, isPadLayout ? 24 : 18)
                        .padding(.top, 12)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(draftRewards.enumerated()), id: \.element.id) { index, reward in
                            rewardRow(reward, position: index + 1)
                        }
                    }
                    .padding(.horizontal, isPadLayout ? 16 : 12)
                    .padding(.bottom, 24)
                }
            }
            .scrollDisabled(draggingRewardID != nil)
            .background {
                PointsRewardBackground(theme: .concise)
                    .ignoresSafeArea()
            }
            .coordinateSpace(name: "reward-order-list")
            .navigationTitle(L10n.reorderRewards)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.cancel, action: cancel)
                        .font(.appSystem(size: isPadLayout ? 18 : 16, weight: .regular, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done, action: save)
                        .font(.appSystem(size: isPadLayout ? 18 : 16, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.concise.color)
                }
            }
            .alert(
                L10n.tr("Couldn't save reward order", zhHans: "奖励顺序保存失败", zhHant: "獎勵順序儲存失敗", ja: "報酬の順番を保存できません"),
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented { saveErrorMessage = nil }
                    }
                )
            ) {
                Button(L10n.ok, role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private func rewardRow(_ reward: CustomReward, position: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.appSystem(size: isPadLayout ? 16 : 14, weight: .heavy, design: .rounded))
                .foregroundColor(AppTheme.concise.color)
                .frame(width: isPadLayout ? 26 : 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(reward.title)
                    .font(.appSystem(size: isPadLayout ? 18 : 16, weight: .heavy, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)

                Text("\(reward.requiredPoints) pts")
                    .font(.appSystem(size: isPadLayout ? 15 : 13, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.56))
            }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: isPadLayout ? 20 : 18, weight: .medium))
                .foregroundColor(AppTheme.concise.color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(L10n.dragToReorder)
                .gesture(rewardReorderGesture(for: reward.id))
        }
        .padding(.horizontal, 14)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.38))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.concise.bingoSurfaceShadowColor.opacity(0.16), lineWidth: 1)
                }
        }
        .padding(.vertical, 5)
        .offset(y: verticalOffset(for: reward.id))
        .zIndex(draggingRewardID == reward.id ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.tr(
                "Position \(position), \(reward.title), \(reward.requiredPoints) points",
                zhHans: "第 \(position) 位，\(reward.title)，\(reward.requiredPoints) 积分",
                zhHant: "第 \(position) 位，\(reward.title)，\(reward.requiredPoints) 積分",
                ja: "\(position)番目、\(reward.title)、\(reward.requiredPoints)ポイント"
            )
        )
        .accessibilityHint(L10n.rewardOrderHint)
        .accessibilityAction(named: Text(L10n.moveUp)) {
            moveReward(reward.id, by: -1)
        }
        .accessibilityAction(named: Text(L10n.moveDown)) {
            moveReward(reward.id, by: 1)
        }
    }

    private func rewardReorderGesture(for rewardID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("reward-order-list"))
            .onChanged { value in
                if draggingRewardID == nil {
                    draggingRewardID = rewardID
                    dragStartIndex = draftRewards.firstIndex(where: { $0.id == rewardID })
                    dragTargetIndex = dragStartIndex
                }

                guard draggingRewardID == rewardID,
                      let dragStartIndex else {
                    return
                }

                dragTranslation = value.translation.height
                let targetIndex = targetIndex(
                    startIndex: dragStartIndex,
                    translationInRows: Double(value.translation.height / rowHeight),
                    itemCount: draftRewards.count
                )
                if targetIndex != dragTargetIndex {
                    withAnimation(reorderAnimation) {
                        dragTargetIndex = targetIndex
                    }
                }
            }
            .onEnded { _ in
                finishDragging()
            }
    }

    private func targetIndex(startIndex: Int, translationInRows: Double, itemCount: Int) -> Int {
        guard itemCount > 1 else { return 0 }
        let rowOffset = Int(translationInRows.rounded(.toNearestOrAwayFromZero))
        return min(max(startIndex + rowOffset, 0), itemCount - 1)
    }

    private func verticalOffset(for rewardID: UUID) -> CGFloat {
        guard let rewardIndex = draftRewards.firstIndex(where: { $0.id == rewardID }),
              let dragStartIndex,
              let dragTargetIndex else {
            return 0
        }

        if rewardID == draggingRewardID {
            return dragTranslation
        }

        if dragStartIndex < dragTargetIndex,
           rewardIndex > dragStartIndex,
           rewardIndex <= dragTargetIndex {
            return -rowHeight
        }
        if dragTargetIndex < dragStartIndex,
           rewardIndex >= dragTargetIndex,
           rewardIndex < dragStartIndex {
            return rowHeight
        }
        return 0
    }

    private func finishDragging() {
        guard let dragStartIndex,
              let dragTargetIndex else {
            resetDragState()
            return
        }

        withAnimation(reorderAnimation, completionCriteria: .logicallyComplete) {
            dragTranslation = CGFloat(dragTargetIndex - dragStartIndex) * rowHeight
        } completion: {
            commitDrag(from: dragStartIndex, to: dragTargetIndex)
        }
    }

    private func commitDrag(from sourceIndex: Int, to targetIndex: Int) {
        var reorderedRewards = draftRewards
        if sourceIndex != targetIndex {
            reorderedRewards.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draftRewards = reorderedRewards
            resetDragState()
        }
    }

    private func moveReward(_ rewardID: UUID, by offset: Int) {
        guard draggingRewardID == nil,
              let sourceIndex = draftRewards.firstIndex(where: { $0.id == rewardID }) else {
            return
        }

        let targetIndex = sourceIndex + offset
        guard draftRewards.indices.contains(targetIndex) else { return }

        withAnimation(reorderAnimation) {
            draftRewards.swapAt(sourceIndex, targetIndex)
        }
    }

    private func save() {
        guard onSave(draftRewards) else {
            saveErrorMessage = L10n.tr(
                "Please try again.",
                zhHans: "请稍后重试。",
                zhHant: "請稍後再試。",
                ja: "もう一度お試しください。"
            )
            return
        }
    }

    private func cancel() {
        onCancel()
    }

    private func resetDragState() {
        draggingRewardID = nil
        dragStartIndex = nil
        dragTargetIndex = nil
        dragTranslation = 0
    }
}
