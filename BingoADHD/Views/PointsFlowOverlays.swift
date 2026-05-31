import SwiftUI
import UIKit

struct PointsRewardBackground: View {
    var theme: AppTheme = .current

    var body: some View {
        theme.backgroundColor
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

struct PointsStickerActionOverlay: View {
    private enum Phase {
        case detail
        case success
    }

    let sticker: StickerKind
    let isOwned: Bool
    let isPlacedOnHome: Bool
    let canRedeem: Bool
    let isPadLayout: Bool
    let onPrimary: () -> Void
    let onCancel: () -> Void
    @State private var phase: Phase = .detail
    @State private var isRedeeming = false
    @State private var stickerFlipDegrees = 0.0
    @State private var hasRevealedRedeemedSticker = false
    @State private var backgroundMaterialOpacity = 0.0
    @State private var backgroundMaterialScale = 0.96
    private let redeemAnimationDuration = 0.92

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var primaryTitle: String {
        if phase == .success {
            return L10n.ok
        }
        return isOwned ? L10n.addToHome : L10n.redeem
    }

    private var isPrimaryEnabled: Bool {
        guard !isRedeeming else { return false }
        if phase == .success {
            return true
        }
        return isOwned ? !isPlacedOnHome : canRedeem
    }

    private var showsPrimaryButton: Bool {
        if phase == .success {
            return true
        }
        return !(isOwned && isPlacedOnHome)
    }

    private var activeTheme: AppTheme { .current }
    private var previewShowsUnlocked: Bool {
        isOwned || hasRevealedRedeemedSticker || phase == .success
    }
    private var previewLightOpacity: Double {
        previewShowsUnlocked ? max(backgroundMaterialOpacity, isOwned ? 0.92 : 0) : backgroundMaterialOpacity
    }
    private var stickerFlipRadians: CGFloat {
        CGFloat(stickerFlipDegrees * .pi / 180)
    }
    private var stickerDepthShadowX: CGFloat {
        sin(stickerFlipRadians) * scaled(14, pad: 20)
    }
    private var stickerDepthShadowY: CGFloat {
        isRedeeming ? scaled(18, pad: 24) : scaled(10, pad: 14)
    }
    private var stickerDepthShadowRadius: CGFloat {
        isRedeeming ? scaled(28, pad: 36) : scaled(18, pad: 24)
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

            GeometryReader { proxy in
                let centerX = proxy.size.width / 2
                let stickerCenterY = proxy.size.height * (isPadLayout ? 0.38 : 0.40)
                let pointsY = stickerCenterY + scaled(252, pad: 320)
                let primaryY = pointsY + scaled(58, pad: 72)
                let cancelY = primaryY + scaled(62, pad: 76)
                let effectWidth = proxy.size.width * (isPadLayout ? 0.9 : 1.24)
                let effectHeight = effectWidth * (902.0 / 1140.0)
                let effectCenterY = stickerCenterY + scaled(36, pad: 48)

                ZStack {
                    redeemLightEffect(width: effectWidth, height: effectHeight)
                        .position(x: centerX, y: effectCenterY)
                        .scaleEffect(backgroundMaterialScale)
                        .opacity(previewLightOpacity)
                        .allowsHitTesting(false)

                    stickerPreview
                        .frame(width: proxy.size.width, height: scaled(340, pad: 430))
                        .position(x: centerX, y: stickerCenterY)
                        .rotation3DEffect(
                            .degrees(stickerFlipDegrees),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.78
                        )
                        .compositingGroup()
                        .shadow(
                            color: .black.opacity(isRedeeming ? 0.34 : 0.22),
                            radius: stickerDepthShadowRadius,
                            x: stickerDepthShadowX,
                            y: stickerDepthShadowY
                        )
                        .scaleEffect(isRedeeming ? 1.06 : (phase == .success ? 1.03 : 1))

                    Text("\(sticker.requiredPoints) \(L10n.pointsUnit)")
                        .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity((previewShowsUnlocked || phase == .success) ? 0 : 1)
                        .frame(height: scaled(28, pad: 34))
                        .position(x: centerX, y: pointsY)

                    if phase == .success {
                        Text(L10n.tr("Congrats! You've redeemed your sticker!", zhHans: "恭喜！你已成功兑换贴纸！", zhHant: "恭喜！你已成功兌換貼紙！", ja: "おめでとう！ステッカーの交換が完了しました！"))
                            .font(.appSystem(size: scaled(16, pad: 20), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, scaled(24, pad: 40))
                            .position(x: centerX, y: pointsY)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if showsPrimaryButton {
                        primaryButton
                            .position(x: centerX, y: primaryY)
                    }

                    if phase == .detail && !isRedeeming {
                        cancelButton
                            .position(x: centerX, y: cancelY)
                    }
                }
            }
            .padding(.horizontal, scaled(32, pad: 64))
        }
    }

    @ViewBuilder
    private var stickerPreview: some View {
        ZStack {
            if previewShowsUnlocked {
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
    }

    private var primaryButton: some View {
        Button {
            guard isPrimaryEnabled else { return }
            if phase == .success {
                onCancel()
            } else if isOwned {
                onPrimary()
            } else {
                startRedeemAnimation()
            }
        } label: {
            Text(primaryTitle)
                .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: scaled(164, pad: 210), height: scaled(43, pad: 52))
                .background(
                    Capsule(style: .continuous)
                        .fill(activeTheme.color)
                        .shadow(color: activeTheme.bingoSurfaceShadowColor.opacity(0.22), radius: 8, x: 0, y: 4)
                )
                .opacity(isRedeeming ? 0.68 : (isPrimaryEnabled ? 1 : 0.55))
        }
        .buttonStyle(.plain)
        .disabled(!isPrimaryEnabled)
    }

    private var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            Text(L10n.cancel)
                .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(height: scaled(36, pad: 44))
        }
        .buttonStyle(.plain)
    }

    private func redeemLightEffect(width: CGFloat, height: CGFloat) -> some View {
        Image("RedeemLightEffect")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: width, height: height)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height * 0.22)

                    Rectangle()
                        .fill(.white)

                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height * 0.12)
                }
                .frame(width: width, height: height)
            }
    }

    private func startRedeemAnimation() {
        guard !isRedeeming, canRedeem else { return }
        isRedeeming = true
        PointsSoundPlayer.shared.playRewardRedeemed()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.timingCurve(0.2, 0.72, 0.24, 1.0, duration: redeemAnimationDuration)) {
            stickerFlipDegrees += 360
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + redeemAnimationDuration * 0.46) {
            guard isRedeeming else { return }
            withAnimation(.easeInOut(duration: 0.12)) {
                hasRevealedRedeemedSticker = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + redeemAnimationDuration) {
            guard isRedeeming else { return }
            onPrimary()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                phase = .success
                isRedeeming = false
                hasRevealedRedeemedSticker = true
                backgroundMaterialOpacity = 0.92
                backgroundMaterialScale = 1.04
            }
        }
    }
}

struct PointsRewardRedeemOverlay: View {
    private enum Phase {
        case detail
        case success
    }

    let reward: CustomReward
    let isPadLayout: Bool
    let onRedeem: () -> Void
    let onCancel: () -> Void
    @State private var phase: Phase = .detail
    @State private var isRedeeming = false
    @State private var cardFlipDegrees = 0.0
    @State private var backgroundMaterialOpacity = 0.0
    @State private var backgroundMaterialScale = 0.96
    private var activeTheme: AppTheme { .current }
    private let redeemAnimationDuration = 0.92

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var cardWidth: CGFloat {
        scaled(250, pad: 320)
    }

    private var cardHeight: CGFloat {
        cardWidth * (227.0 / 187.0)
    }

    private var cardTop: CGFloat {
        scaled(205, pad: 178)
    }

    private var cardCenterY: CGFloat {
        cardTop + cardHeight / 2
    }

    private var contentLift: CGFloat {
        -30
    }

    private var cardFlipRadians: CGFloat {
        CGFloat(cardFlipDegrees * .pi / 180)
    }

    private var cardDepthShadowX: CGFloat {
        sin(cardFlipRadians) * scaled(18, pad: 24)
    }

    private var cardDepthShadowY: CGFloat {
        isRedeeming ? scaled(18, pad: 24) : scaled(12, pad: 16)
    }

    private var cardDepthShadowRadius: CGFloat {
        isRedeeming ? scaled(28, pad: 36) : scaled(18, pad: 24)
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

            rewardBackgroundMaterial
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .offset(y: contentLift)

            ZStack {
                ZStack {
                    Image(reward.themeImageName ?? "CustomRewardDefaultCard")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: cardWidth, height: cardHeight)
                        .shadow(color: phase == .success ? .white.opacity(0.72) : .white.opacity(0.28), radius: 10, x: 0, y: 0)
                        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 12)

                    VStack(spacing: 0) {
                        if reward.themeImageName != nil {
                            Color.clear
                                .frame(height: cardWidth * CustomRewardThemeCardImage.contentTopRatio)
                        } else {
                            Text(reward.displayEmoji)
                                .font(.system(size: scaled(81.2, pad: 225.6)))
                                .frame(height: scaled(116, pad: 148))
                                .padding(.top, scaled(42, pad: 54))
                        }

                        Spacer(minLength: scaled(8, pad: 12))

                        Text(reward.title)
                            .font(.appSystem(size: scaled(23, pad: 29), weight: .heavy, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, scaled(28, pad: 36))

                        Text("\(reward.requiredPoints) \(L10n.pointsUnit)")
                            .font(.appSystem(size: scaled(18, pad: 22), weight: .bold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .padding(.top, scaled(4, pad: 6))

                        Spacer(minLength: scaled(18, pad: 24))
                    }
                    .frame(width: cardWidth, height: cardHeight)
                }
                .rotation3DEffect(
                    .degrees(cardFlipDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.78
                )
                .compositingGroup()
                .shadow(
                    color: .black.opacity(isRedeeming ? 0.36 : 0.24),
                    radius: cardDepthShadowRadius,
                    x: cardDepthShadowX,
                    y: cardDepthShadowY
                )
                .scaleEffect(isRedeeming ? 1.06 : (phase == .success ? 1.03 : 1))
                .position(x: UIScreen.main.bounds.width / 2, y: cardCenterY)

                VStack(spacing: scaled(14, pad: 20)) {
                    Spacer()
                        .frame(height: cardTop + cardHeight + scaled(34, pad: 44))

                    if phase == .detail {
                        Color.clear
                            .frame(height: scaled(28, pad: 34))
                    } else {
                        Text(L10n.tr("Congrats! You've redeemed your reward!", zhHans: "恭喜！你已成功兑换奖励！", zhHant: "恭喜！你已成功兌換獎勵！", ja: "おめでとう！報酬の交換が完了しました！"))
                            .font(.appSystem(size: scaled(16, pad: 20), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, scaled(24, pad: 40))
                            .offset(y: -10)
                    }

                    Button {
                        if phase == .detail && !isRedeeming {
                            startRedeemAnimation()
                        } else {
                            onCancel()
                        }
                    } label: {
                        Text(phase == .detail ? L10n.redeem : L10n.ok)
                            .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: scaled(164, pad: 210), height: scaled(42, pad: 52))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(activeTheme.color)
                                    .shadow(color: activeTheme.bingoSurfaceShadowColor.opacity(0.24), radius: 8, x: 0, y: 4)
                            )
                            .opacity(isRedeeming ? 0.68 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRedeeming)

                    if phase == .detail && !isRedeeming {
                        Button {
                            onCancel()
                        } label: {
                            Text(L10n.cancel)
                                .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(height: scaled(36, pad: 44))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, scaled(32, pad: 64))
            }
            .offset(y: contentLift)
        }
    }

    private var rewardBackgroundMaterial: some View {
        GeometryReader { proxy in
            let effectWidth = proxy.size.width * (isPadLayout ? 0.9 : 1.24)
            let effectHeight = effectWidth * (902.0 / 1140.0)
            let effectCenterY = cardCenterY + scaled(54, pad: 70)

            Image("RedeemLightEffect")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: effectWidth, height: effectHeight)
                .position(x: proxy.size.width / 2, y: effectCenterY)
                .scaleEffect(backgroundMaterialScale)
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: effectHeight * 0.22)

                        Rectangle()
                            .fill(.white)

                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: effectHeight * 0.12)
                    }
                    .frame(width: effectWidth, height: effectHeight)
                    .position(x: proxy.size.width / 2, y: effectCenterY)
                }
                .opacity(backgroundMaterialOpacity)
        }
    }

    private func startRedeemAnimation() {
        guard !isRedeeming else { return }
        isRedeeming = true
        PointsSoundPlayer.shared.playRewardRedeemed()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.timingCurve(0.2, 0.72, 0.24, 1.0, duration: redeemAnimationDuration)) {
            cardFlipDegrees += 360
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + redeemAnimationDuration) {
            guard isRedeeming else { return }
            onRedeem()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                phase = .success
                isRedeeming = false
                backgroundMaterialOpacity = 0.92
                backgroundMaterialScale = 1.04
            }
        }
    }
}
