import SwiftUI

struct PointsFlowPresenter: View {
    let isPadLayout: Bool
    let points: Int
    let totalPoints: Int
    @ObservedObject var pointsFeatureStore: PointsFeatureStore
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let onAddStickerToHomeSuccess: () -> Void
    var body: some View {
        PointsFlowSheet(
            isPadLayout: isPadLayout,
            points: points,
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
                pointsFeatureStore.createReward(
                    title: title,
                    requiredPoints: requiredPoints,
                    emoji: emoji,
                    themeImageName: themeImageName,
                    hasPremiumAccess: subscriptionManager.hasPremiumAccess
                )
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
            }
        )
    }
}

struct PointsFlowSheet: View {
    private enum Screen {
        case details
        case rewardEditor(CustomReward?)
    }

    let isPadLayout: Bool
    let points: Int
    let inventoryCounts: [StickerKind: Int]
    let usedCounts: [StickerKind: Int]
    let rewards: [CustomReward]
    let redemptionHistory: [PointRedemptionRecord]
    let onRedeemSticker: (StickerKind) -> Void
    let onAddStickerToHome: (StickerKind) -> Void
    let onDeleteReward: (CustomReward) -> Void
    let onRedeemReward: (CustomReward) -> Void
    let onCreateReward: (String, Int, String, String?) -> Bool
    let onUpdateReward: (CustomReward, String, Int, String, String?) -> Void

    @State private var screen: Screen = .details
    @State private var detailsInitialTab: PointsTab = .stickers
    @State private var selectedStickerForDetail: StickerKind?
    @State private var selectedRewardForDetail: CustomReward?
    @State private var isPremiumPaywallPresented = false
    @State private var premiumPaywallSource = "custom_reward_limit_create"
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        ZStack {
            switch screen {
            case .details:
                detailsContent
            case .rewardEditor(let reward):
                RewardEditorSheet(
                    reward: reward,
                    onSave: { title, requiredPoints, emoji, themeImageName in
                        if let reward {
                            onUpdateReward(reward, title, requiredPoints, emoji, themeImageName)
                            detailsInitialTab = .rewards
                            screen = .details
                        } else if onCreateReward(title, requiredPoints, emoji, themeImageName) {
                            detailsInitialTab = .rewards
                            screen = .details
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
        .fullScreenCover(isPresented: $isPremiumPaywallPresented) {
            PremiumPaywallView(entrySource: premiumPaywallSource)
        }
    }

    private var canCreateAnotherReward: Bool {
        subscriptionManager.hasPremiumAccess || rewards.count < AppSettings.maxFreeCustomRewards
    }

    private func handleCreateRewardRequest(source: String = "custom_reward_limit_create") {
        guard canCreateAnotherReward else {
            presentCustomRewardPremiumPaywall(source: source)
            return
        }
        detailsInitialTab = .rewards
        screen = .rewardEditor(nil)
    }

    private func presentCustomRewardPremiumPaywall(source: String) {
        AnalyticsService.logPremiumCustomRewardsLimitHit(
            currentRewardCount: rewards.count,
            source: source
        )
        premiumPaywallSource = source
        Task { @MainActor in
            isPremiumPaywallPresented = true
            await subscriptionManager.warmupProductsForPaywall()
        }
    }

    @ViewBuilder
    private var detailsContent: some View {
        let content = PointsDetailSheet(
            initialTab: detailsInitialTab,
            points: points,
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
            onSelectSticker: { sticker in
                selectedStickerForDetail = sticker
            },
            onSelectReward: { reward in
                selectedRewardForDetail = reward
            }
        )

        if isPadLayout {
            NineTenthsSheetContainer(contentMaxWidth: 960) {
                content
            }
            .background(Color.clear)
        } else {
            content
        }
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
    let onSelectSticker: (StickerKind) -> Void
    let onSelectReward: (CustomReward) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PointsTab
    @State private var actionRewardID: UUID?
    @State private var pendingDeleteReward: CustomReward?
    @State private var isDeleteActionSheetPresented = false
    @State private var isDeleteSecondConfirmPresented = false
    @State private var isHistoryPresented = false
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue

    init(
        initialTab: PointsTab,
        points: Int,
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
        onSelectSticker: @escaping (StickerKind) -> Void,
        onSelectReward: @escaping (CustomReward) -> Void
    ) {
        self.points = points
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
        self.onSelectSticker = onSelectSticker
        self.onSelectReward = onSelectReward
        _selectedTab = State(initialValue: initialTab)
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var contentMaxWidth: CGFloat {
        isPadLayout ? 820 : .infinity
    }

    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
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

                        tabSelector

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
                    .padding(.bottom, selectedTab == .rewards && !rewards.isEmpty ? scaled(112, pad: 132) : 32)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if actionRewardID != nil {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                                actionRewardID = nil
                            }
                        }
                    }
                )

                if selectedTab == .rewards && !rewards.isEmpty {
                    VStack {
                        Spacer()
                        floatingAddRewardButton
                            .padding(.bottom, scaled(26, pad: 34))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                        .zIndex(1)
                }

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
                    isDeleteSecondConfirmPresented = true
                }
                Button(L10n.cancel, role: .cancel) {
                    pendingDeleteReward = nil
                }
            } message: {
                Text(L10n.tr("This action cannot be undone.", zhHans: "删除后无法恢复。", zhHant: "刪除後無法復原。", ja: "この操作は取り消せません。"))
            }
            .alert(
                L10n.tr("Confirm Delete", zhHans: "再次确认删除", zhHant: "再次確認刪除", ja: "削除の確認"),
                isPresented: $isDeleteSecondConfirmPresented,
                actions: {
                    Button(L10n.cancel, role: .cancel) {
                        pendingDeleteReward = nil
                    }
                    Button(L10n.deleteReward, role: .destructive) {
                        if let pendingDeleteReward {
                            onDeleteReward(pendingDeleteReward)
                        }
                        pendingDeleteReward = nil
                    }
                },
                message: {
                    Text(L10n.tr("Are you sure you want to permanently delete this reward?", zhHans: "确定要永久删除这个奖励吗？", zhHant: "確定要永久刪除這個獎勵嗎？", ja: "この報酬を完全に削除してもよろしいですか？"))
                }
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isHistoryPresented) {
                PointsRedemptionHistorySheet(
                    inventoryCounts: inventoryCounts,
                    rewards: rewards,
                    records: redemptionHistory,
                    isPadLayout: isPadLayout
                )
            }
        }
    }

    private var pointsHeader: some View {
        HStack {
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

            Spacer()

            Button {
                isHistoryPresented = true
            } label: {
                LiquidGlassIconBadge(
                    imageName: "HistoryIcon",
                    size: scaled(44, pad: 52),
                    iconSize: scaled(26, pad: 30)
                )
            }
            .buttonStyle(.plain)
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
        }
        .buttonStyle(.plain)
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

                    Text("\(sticker.requiredPoints) \(L10n.pointsUnit)")
                        .font(.appSystem(size: scaled(14, pad: 17), weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .offset(y: scaled(12, pad: 16))
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
                    Text(reward.displayEmoji)
                        .font(.system(size: scaled(81.2, pad: 225.6)))
                        .frame(height: scaled(118, pad: 150))
                        .padding(.top, scaled(10, pad: 14))
                        .saturation(canRedeem ? 1 : 0)
                        .opacity(canRedeem ? 1 : 0.55)
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
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                actionRewardID = reward.id
            }
        }
    }

    private var floatingAddRewardButton: some View {
        Button {
            onRequestCreateReward()
        } label: {
            HStack(spacing: scaled(8, pad: 10)) {
                Text(L10n.addRewards)
                    .font(.appSystem(size: scaled(16, pad: 16), weight: .heavy, design: .rounded))
            }
            .foregroundColor(NeumorphicColors.text)
            .frame(width: scaled(158, pad: 196), height: scaled(42, pad: 52))
            .appLiquidGlass(in: Capsule(style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
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
