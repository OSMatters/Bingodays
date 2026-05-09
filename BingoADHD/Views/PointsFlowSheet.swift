import SwiftUI
import UIKit

struct PointsFlowPresenter: View {
    let isPadLayout: Bool
    let points: Int
    let totalPoints: Int
    @ObservedObject var pointsFeatureStore: PointsFeatureStore
    let onAddStickerToHomeSuccess: () -> Void

    var body: some View {
        PointsFlowSheet(
            isPadLayout: isPadLayout,
            points: points,
            inventoryCounts: pointsFeatureStore.stickerInventoryCounts,
            usedCounts: pointsFeatureStore.currentStickerUsageCounts,
            rewards: pointsFeatureStore.activeRewards,
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
            onCreateReward: { title, requiredPoints, emoji in
                pointsFeatureStore.createReward(title: title, requiredPoints: requiredPoints, emoji: emoji)
            },
            onUpdateReward: { reward, title, requiredPoints, emoji in
                pointsFeatureStore.updateReward(
                    CustomReward(
                        id: reward.id,
                        title: title,
                        requiredPoints: requiredPoints,
                        emoji: emoji,
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
    let onRedeemSticker: (StickerKind) -> Void
    let onAddStickerToHome: (StickerKind) -> Void
    let onDeleteReward: (CustomReward) -> Void
    let onRedeemReward: (CustomReward) -> Void
    let onCreateReward: (String, Int, String) -> Void
    let onUpdateReward: (CustomReward, String, Int, String) -> Void

    @State private var screen: Screen = .details

    var body: some View {
        Group {
            switch screen {
            case .details:
                detailsContent
            case .rewardEditor(let reward):
                RewardEditorSheet(
                    reward: reward,
                    onSave: { title, requiredPoints, emoji in
                        if let reward {
                            onUpdateReward(reward, title, requiredPoints, emoji)
                        } else {
                            onCreateReward(title, requiredPoints, emoji)
                        }
                        screen = .details
                    },
                    onDelete: reward.map { reward in
                        {
                            onDeleteReward(reward)
                            screen = .details
                        }
                    },
                    onCancel: {
                        screen = .details
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var detailsContent: some View {
        let content = PointsDetailSheet(
            points: points,
            inventoryCounts: inventoryCounts,
            usedCounts: usedCounts,
            rewards: rewards,
            onRedeem: onRedeemSticker,
            onAddToHome: onAddStickerToHome,
            onDeleteReward: onDeleteReward,
            onRedeemReward: onRedeemReward,
            onRequestCreateReward: {
                screen = .rewardEditor(nil)
            },
            onRequestEditReward: { reward in
                screen = .rewardEditor(reward)
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
    let onDeleteReward: (CustomReward) -> Void
    let onRedeemReward: (CustomReward) -> Void
    let onRequestCreateReward: () -> Void
    let onRequestEditReward: (CustomReward) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PointsTab = .stickers
    @State private var selectedSticker: StickerKind?

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
        Array(repeating: GridItem(.flexible(), spacing: scaled(18, pad: 28)), count: 3)
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
            .toyPoodle
        ]
    }

    var body: some View {
        pointsContent
    }

    private var pointsContent: some View {
        NavigationStack {
            ZStack {
                PointsRewardBackground()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: scaled(20, pad: 28)) {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.appSystem(size: scaled(18, pad: 22), weight: .semibold))
                                    .foregroundColor(NeumorphicColors.text)
                                    .frame(width: scaled(40, pad: 46), height: scaled(40, pad: 46))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Image(systemName: "list.bullet.rectangle.fill")
                                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold))
                                .foregroundColor(NeumorphicColors.text)
                                .frame(width: scaled(40, pad: 46), height: scaled(40, pad: 46))
                        }
                        .padding(.top, scaled(12, pad: 18))

                        VStack(spacing: scaled(2, pad: 4)) {
                            HStack(alignment: .center, spacing: scaled(8, pad: 10)) {
                                Text("\(points)")
                                    .font(.appSystem(size: scaled(50, pad: 64), weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)

                                Image(systemName: "star.fill")
                                    .font(.appSystem(size: scaled(21, pad: 26), weight: .bold))
                                    .foregroundColor(Color(red: 0.73, green: 0.52, blue: 0.37))
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
                            LazyVGrid(columns: stickerGridColumns, spacing: 16) {
                                ForEach(rewards) { reward in
                                    rewardCard(reward)
                                }
                                addRewardCard
                            }
                            .padding(.top, scaled(8, pad: 12))
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, scaled(20, pad: 32))
                    .padding(.bottom, 32)
                }

                if let selectedSticker {
                    PointsStickerActionOverlay(
                        sticker: selectedSticker,
                        isOwned: (inventoryCounts[selectedSticker] ?? 0) > 0,
                        isPlacedOnHome: (usedCounts[selectedSticker] ?? 0) > 0,
                        canRedeem: points >= selectedSticker.requiredPoints,
                        isPadLayout: isPadLayout,
                        onPrimary: {
                            if (inventoryCounts[selectedSticker] ?? 0) > 0 {
                                onAddToHome(selectedSticker)
                                self.selectedSticker = nil
                            } else {
                                onRedeem(selectedSticker)
                            }
                        },
                        onCancel: {
                            self.selectedSticker = nil
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(2)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
                .fill(Color(red: 0.91, green: 0.80, blue: 0.70).opacity(0.5))
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
            .fill(isSelected ? Color(red: 0.82, green: 0.65, blue: 0.49) : .clear)
    }

    private func stickerCard(_ sticker: StickerKind) -> some View {
        let inventoryCount = inventoryCounts[sticker] ?? 0
        let hasOwned = inventoryCount > 0

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedSticker = sticker
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

                    VStack(spacing: scaled(10, pad: 12)) {
                        Text("\(sticker.requiredPoints) \(L10n.pointsUnit)")
                            .font(.appSystem(size: scaled(14, pad: 17), weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Circle()
                            .fill(.white.opacity(0.14))
                            .frame(width: scaled(12, pad: 15), height: scaled(12, pad: 15))
                    }
                    .offset(y: scaled(12, pad: 16))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: scaled(120, pad: 158))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyRewardsState: some View {
        VStack(spacing: scaled(28, pad: 34)) {
            Image("CustomRewardEmpty")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: scaled(185, pad: 240), height: scaled(142, pad: 184))

            Text(L10n.emptyCustomRewardsMessage)
                .font(.appSystem(size: scaled(19, pad: 23), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, scaled(18, pad: 24))

            Button {
                onRequestCreateReward()
            } label: {
                Text(L10n.addRewards)
                    .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(width: scaled(199, pad: 240), height: scaled(53, pad: 62))
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.99, green: 0.97, blue: 0.93))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(.white, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func rewardCard(_ reward: CustomReward) -> some View {
        let canRedeem = points >= reward.requiredPoints

        return ZStack(alignment: .topTrailing) {
            Image("CustomRewardDefaultCard")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .shadow(color: Color(red: 0.67, green: 0.48, blue: 0.23).opacity(0.14), radius: 12, x: 0, y: 8)

            VStack(spacing: 0) {
                Text(reward.emoji)
                    .font(.system(size: scaled(48, pad: 62)))
                    .frame(height: scaled(74, pad: 96))
                    .padding(.top, scaled(16, pad: 22))

                Spacer(minLength: scaled(8, pad: 10))

                Text(reward.title)
                    .font(.appSystem(size: scaled(13, pad: 16), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, scaled(14, pad: 18))

                Text("\(reward.requiredPoints) pts")
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                    .foregroundColor(canRedeem ? Color(red: 0.72, green: 0.50, blue: 0.34) : NeumorphicColors.text.opacity(0.45))
                    .padding(.top, scaled(4, pad: 5))

                if reward.redemptionCount > 0 {
                    Text(L10n.redeemedCount(reward.redemptionCount))
                        .font(.appSystem(size: scaled(10, pad: 12), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.55))
                        .padding(.top, 2)
                }

                Spacer(minLength: scaled(8, pad: 10))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Menu {
                Button(L10n.redeem) {
                    onRedeemReward(reward)
                }
                .disabled(!canRedeem)

                Button(L10n.editReward) {
                    onRequestEditReward(reward)
                }

                Button(L10n.deleteReward, role: .destructive) {
                    onDeleteReward(reward)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .bold))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                    .frame(width: scaled(28, pad: 34), height: scaled(28, pad: 34))
            }
            .padding(.top, scaled(6, pad: 8))
            .padding(.trailing, scaled(4, pad: 6))
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(187.0 / 227.0, contentMode: .fit)
        .opacity(canRedeem ? 1 : 0.82)
    }

    private var addRewardCard: some View {
        Button {
            onRequestCreateReward()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.appSystem(size: scaled(34, pad: 40), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)

                Text(L10n.addReward)
                    .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }
            .frame(maxWidth: .infinity, minHeight: isPadLayout ? 192 : 176)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(themedOutlineSurface(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private func themedOutlineSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(NeumorphicColors.background.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
            )
    }

    private func flatStickerCardSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(NeumorphicColors.background.opacity(0.78))
    }

    private func flatStickerButtonSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(NeumorphicColors.background.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NeumorphicColors.text.opacity(0.08), lineWidth: 0.8)
            )
    }

}

private struct PointsRewardBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.89, blue: 0.70),
                Color(red: 1.0, green: 0.95, blue: 0.86)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            GeometryReader { proxy in
                let spacing: CGFloat = 36
                Canvas { context, size in
                    var x: CGFloat = -spacing
                    while x < size.width + spacing {
                        var y: CGFloat = 14
                        while y < size.height + spacing {
                            let rect = CGRect(x: x, y: y, width: 10, height: 10)
                            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.72)))
                            y += spacing
                        }
                        x += spacing
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

private struct PointsStickerActionOverlay: View {
    let sticker: StickerKind
    let isOwned: Bool
    let isPlacedOnHome: Bool
    let canRedeem: Bool
    let isPadLayout: Bool
    let onPrimary: () -> Void
    let onCancel: () -> Void

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var primaryTitle: String {
        isOwned ? L10n.addToHome : L10n.redeem
    }

    private var isPrimaryEnabled: Bool {
        isOwned ? !isPlacedOnHome : canRedeem
    }

    private var showsPrimaryButton: Bool {
        !(isOwned && isPlacedOnHome)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .blur(radius: 24)
                .ignoresSafeArea()

            Color(red: 0.19, green: 0.17, blue: 0.12)
                .opacity(0.86)
                .ignoresSafeArea()

            VStack(spacing: scaled(28, pad: 38)) {
                Spacer(minLength: scaled(96, pad: 130))

                ZStack {
                    if isOwned {
                        StickerRays()
                            .fill(Color(red: 0.99, green: 0.86, blue: 0.32).opacity(0.24))
                            .frame(width: scaled(320, pad: 410), height: scaled(320, pad: 410))
                            .blur(radius: 1)

                        Image(sticker.unlockedImageName)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: scaled(220, pad: 300), height: scaled(260, pad: 340))
                            .shadow(color: .white.opacity(0.8), radius: 10, x: 0, y: 0)
                            .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 12)
                    } else {
                        Image(sticker.lockedImageName)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: scaled(230, pad: 310), height: scaled(270, pad: 350))

                        Text("\(sticker.requiredPoints) pts")
                            .font(.appSystem(size: scaled(24, pad: 30), weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .offset(y: scaled(18, pad: 24))
                    }
                }
                .frame(maxWidth: .infinity)

                Text("\(sticker.requiredPoints) \(L10n.pointsUnit)")
                    .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(isOwned ? 0 : 1)

                if showsPrimaryButton {
                    Button {
                        guard isPrimaryEnabled else { return }
                        onPrimary()
                    } label: {
                        Text(primaryTitle)
                            .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: scaled(164, pad: 210), height: scaled(43, pad: 52))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(red: 0.86, green: 0.67, blue: 0.49))
                            )
                            .opacity(isPrimaryEnabled ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPrimaryEnabled)
                }

                Button {
                    onCancel()
                } label: {
                    Text(L10n.cancel)
                        .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(height: scaled(36, pad: 44))
                }
                .buttonStyle(.plain)

                Spacer(minLength: scaled(90, pad: 120))
            }
            .padding(.horizontal, scaled(32, pad: 64))
        }
    }
}

private struct StickerRays: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.52
        let inner = min(rect.width, rect.height) * 0.18
        let rayCount = 16

        for index in 0..<rayCount {
            let startAngle = CGFloat(index) * (.pi * 2 / CGFloat(rayCount))
            let endAngle = startAngle + (.pi * 2 / CGFloat(rayCount)) * 0.48
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(startAngle) * inner, y: center.y + sin(startAngle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(endAngle) * outer, y: center.y + sin(endAngle) * outer))
            path.closeSubpath()
        }

        return path
    }
}

private struct RewardEditorSheet: View {
    let reward: CustomReward?
    let onSave: (String, Int, String) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var titleText: String
    @State private var pointsText: String
    @State private var selectedEmoji: String
    @State private var emojiInputBuffer = ""
    @State private var isEmojiKeyboardPresented = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(
        reward: CustomReward?,
        onSave: @escaping (String, Int, String) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.reward = reward
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _titleText = State(initialValue: reward?.title ?? "")
        _pointsText = State(initialValue: reward.map { String($0.requiredPoints) } ?? "")
        _selectedEmoji = State(initialValue: reward?.emoji ?? "😊")
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
        ZStack(alignment: .bottom) {
            PointsRewardBackground()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }

            if isEmojiKeyboardPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissKeyboard()
                    }
            }

            VStack(spacing: 0) {
                editorHeader
                    .padding(.top, scaled(48, pad: 62))
                    .padding(.horizontal, scaled(24, pad: 34))

                rewardTicketPreview
                    .frame(width: scaled(280, pad: 360), height: scaled(347, pad: 446))
                    .padding(.top, scaled(12, pad: 22))

                Spacer(minLength: scaled(24, pad: 34))
            }
            .frame(maxWidth: isPadLayout ? 620 : .infinity)
            .frame(maxWidth: .infinity)
            .offset(y: scaled(-30, pad: -36))
            .zIndex(1)

            cardSkinPanel
                .zIndex(1)

            if isEmojiKeyboardPresented {
                EmojiKeyboardHost(text: $emojiInputBuffer, isPresented: $isEmojiKeyboardPresented)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: selectedEmoji) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstCluster = trimmed.first.map(String.init) ?? ""
            if selectedEmoji != firstCluster {
                selectedEmoji = firstCluster
            }
        }
        .onChange(of: emojiInputBuffer) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstCluster = trimmed.first.map(String.init) ?? ""
            guard !firstCluster.isEmpty else { return }
            selectedEmoji = firstCluster
        }
    }

    private var editorHeader: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appSystem(size: scaled(18, pad: 22), weight: .semibold))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(width: scaled(40, pad: 48), height: scaled(40, pad: 48))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.rewardCard)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Spacer()

            Button {
                guard let requiredPoints = normalizedPoints else { return }
                onSave(normalizedTitle, requiredPoints, selectedEmoji)
            } label: {
                Text(L10n.save)
                    .font(.appSystem(size: scaled(16, pad: 19), weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: scaled(60, pad: 72), height: scaled(40, pad: 46))
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.82, green: 0.64, blue: 0.48))
                    )
                    .opacity(canSave ? 1 : 0.52)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
    }

    private var rewardTicketPreview: some View {
        ZStack {
            Image("CustomRewardDefaultCard")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .shadow(color: Color(red: 0.66, green: 0.48, blue: 0.22).opacity(0.16), radius: 18, x: 0, y: 12)

            VStack(spacing: 0) {
                Text(selectedEmoji)
                    .font(.system(size: scaled(112, pad: 142)))
                    .minimumScaleFactor(0.72)
                    .frame(height: scaled(204, pad: 262))
                    .frame(maxWidth: .infinity)

                titleEditor
                    .frame(height: scaled(44, pad: 56))
                    .padding(.horizontal, scaled(28, pad: 36))

                pointsEditor
                    .frame(height: scaled(42, pad: 52))
                    .padding(.horizontal, scaled(34, pad: 44))

                Spacer(minLength: 0)
            }
            .padding(.top, scaled(12, pad: 16))
        }
    }

    private var titleEditor: some View {
        RewardInlineTextField(
            text: $titleText,
            placeholder: L10n.rewardNamePlaceholder,
            maxLength: AppSettings.maxRewardTitleLength,
            keyboardType: .default,
            allowsOnlyDigits: false,
            font: .systemFont(ofSize: scaled(22, pad: 28), weight: .regular),
            textColor: UIColor(NeumorphicColors.text),
            placeholderColor: UIColor(red: 0.51, green: 0.51, blue: 0.51, alpha: 1),
            textAlignment: .center
        )
        .frame(maxWidth: .infinity)
        .frame(height: scaled(44, pad: 56))
    }

    private var pointsEditor: some View {
        HStack(spacing: scaled(4, pad: 6)) {
            Text(L10n.rewardSetRedeem)
                .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51))

            RewardInlineTextField(
                text: $pointsText,
                placeholder: "0",
                maxLength: 4,
                keyboardType: .numberPad,
                allowsOnlyDigits: true,
                font: .systemFont(ofSize: scaled(18, pad: 22), weight: .medium),
                textColor: UIColor(NeumorphicColors.text),
                placeholderColor: UIColor(red: 0.51, green: 0.51, blue: 0.51, alpha: 1),
                textAlignment: .center
            )
                .frame(width: scaled(64, pad: 80))

            Text("pts")
                .foregroundColor(NeumorphicColors.text)
        }
        .font(.appSystem(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity)
        .frame(height: scaled(42, pad: 52))
    }

    private var cardSkinPanel: some View {
        VStack(spacing: scaled(18, pad: 22)) {
            Text(L10n.cardSkin)
                .font(.appSystem(size: scaled(16, pad: 20), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .padding(.top, scaled(23, pad: 28))

            HStack {
                Text(L10n.emoji)
                    .foregroundColor(.white)
                    .frame(width: scaled(63, pad: 76), height: scaled(20, pad: 24))
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.82, green: 0.64, blue: 0.48))
                    )

                Spacer()

                Text(L10n.rewardTheme)
                    .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51))

                Spacer()

                HStack(spacing: 4) {
                    Text(L10n.customPhoto)

                    Image(systemName: "crown.fill")
                        .font(.appSystem(size: scaled(10, pad: 12), weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.67, blue: 0.23))
                }
                .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51))
            }
            .font(.appSystem(size: scaled(14, pad: 17), weight: .regular, design: .rounded))
            .padding(.horizontal, scaled(14, pad: 26))

            VStack(spacing: scaled(12, pad: 16)) {
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    emojiInputBuffer = ""
                    isEmojiKeyboardPresented = true
                } label: {
                    Text(selectedEmoji.isEmpty ? "🙂" : selectedEmoji)
                        .font(.system(size: scaled(64, pad: 82)))
                        .frame(width: scaled(88, pad: 108), height: scaled(88, pad: 108))
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Text(L10n.rewardEmojiKeyboardHint)
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .regular, design: .rounded))
                    .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, scaled(28, pad: 90))
                    .padding(.bottom, scaled(8, pad: 10))
            }
            .padding(.horizontal, scaled(16, pad: 26))
            .padding(.bottom, scaled(24, pad: 32))
        }
        .frame(maxWidth: isPadLayout ? 620 : .infinity)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: scaled(14, pad: 18),
                topTrailingRadius: scaled(14, pad: 18),
                style: .continuous
            )
            .fill(Color(red: 0.99, green: 0.99, blue: 0.99))
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        emojiInputBuffer = ""
        isEmojiKeyboardPresented = false
    }

}

private struct RewardInlineTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxLength: Int
    let keyboardType: UIKeyboardType
    let allowsOnlyDigits: Bool
    let font: UIFont
    let textColor: UIColor
    let placeholderColor: UIColor
    let textAlignment: NSTextAlignment

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.keyboardType = keyboardType
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartInsertDeleteType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = max(font.pointSize * 0.72, 10)
        textField.inputAccessoryView = context.coordinator.makeAccessoryToolbar(for: textField)
        applyConfiguration(to: textField)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        applyConfiguration(to: uiView)

        if uiView.text != text, uiView.markedTextRange == nil {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func applyConfiguration(to textField: UITextField) {
        textField.font = font
        textField.textColor = textColor
        textField.textAlignment = textAlignment
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RewardInlineTextField

        init(parent: RewardInlineTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if textField.markedTextRange != nil {
                return true
            }

            let currentText = textField.text ?? ""
            guard let textRange = Range(range, in: currentText) else {
                return true
            }

            let proposed = currentText.replacingCharacters(in: textRange, with: string)
            let normalized = normalize(proposed)

            if proposed == normalized {
                return true
            }

            textField.text = normalized
            parent.text = normalized
            return false
        }

        func makeAccessoryToolbar(for textField: UITextField) -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let flexible = UIBarButtonItem(systemItem: .flexibleSpace)
            let done = UIBarButtonItem(title: L10n.done, style: .done, target: textField, action: #selector(UIResponder.resignFirstResponder))
            toolbar.items = [flexible, done]
            return toolbar
        }

        private func syncText(from textField: UITextField) {
            guard textField.markedTextRange == nil else { return }

            let normalized = normalize(textField.text ?? "")
            if textField.text != normalized {
                textField.text = normalized
            }
            parent.text = normalized
        }

        private func normalize(_ rawValue: String) -> String {
            let value = parent.allowsOnlyDigits ? rawValue.filter(\.isNumber) : rawValue
            return String(value.prefix(parent.maxLength))
        }
    }
}

private struct EmojiKeyboardHost: UIViewRepresentable {
    @Binding var text: String
    @Binding var isPresented: Bool

    func makeUIView(context: Context) -> EmojiPreferredTextField {
        let textField = EmojiPreferredTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartInsertDeleteType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.tintColor = .clear
        textField.textColor = .clear
        textField.backgroundColor = .clear
        textField.returnKeyType = .done
        textField.inputAccessoryView = context.coordinator.makeAccessoryToolbar(for: textField)
        return textField
    }

    func updateUIView(_ uiView: EmojiPreferredTextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if isPresented, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !isPresented, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isPresented: $isPresented)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        @Binding private var isPresented: Bool

        init(text: Binding<String>, isPresented: Binding<Bool>) {
            _text = text
            _isPresented = isPresented
        }

        @objc func editingChanged(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            syncText(from: textField)
            isPresented = false
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                guard let currentText = textField.text,
                      let textRange = Range(range, in: currentText) else {
                    return true
                }

                let updatedText = currentText.replacingCharacters(in: textRange, with: string)
                let normalized = normalizedEmoji(from: updatedText)
                textField.text = normalized
                text = normalized
                return false
            }

            let normalized = normalizedEmoji(from: string)
            textField.text = normalized
            text = normalized
            return false
        }

        @objc func doneButtonTapped(_ sender: UIBarButtonItem) {
            (sender.target as? UIResponder)?.resignFirstResponder()
        }

        func makeAccessoryToolbar(for textField: UITextField) -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let flexible = UIBarButtonItem(systemItem: .flexibleSpace)
            let done = UIBarButtonItem(title: L10n.done, style: .done, target: textField, action: #selector(UIResponder.resignFirstResponder))
            toolbar.items = [flexible, done]
            return toolbar
        }

        func syncText(from textField: UITextField) {
            let normalized = normalizedEmoji(from: textField.text ?? "")
            if textField.text != normalized {
                textField.text = normalized
            }
            text = normalized
        }

        private func normalizedEmoji(from rawValue: String) -> String {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.first.map(String.init) ?? ""
        }
    }
}

private final class EmojiPreferredTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first(where: { $0.primaryLanguage == "emoji" }) ?? super.textInputMode
    }
}
