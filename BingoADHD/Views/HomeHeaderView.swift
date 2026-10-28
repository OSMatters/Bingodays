import SwiftUI

struct HomeHeaderView: View {
    @ObservedObject var pointsAnimationStore: PointsAnimationStore
    @State private var pointsCapsuleWidth: CGFloat = 0

    let isPadLayout: Bool
    let availablePoints: Int
    let showsLimitedOffer: Bool
    let limitedTimeOfferDuration: TimeInterval
    let limitedTimeOfferCampaignID: String
    let themeColor: Color
    let isDarkBackground: Bool
    let showsSkinNewBadge: Bool
    let onOpenThemePicker: () -> Void
    let onOpenBoardShare: () -> Void
    let onOpenPointsFlow: () -> Void
    let onOpenLimitedOffer: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                HStack(spacing: headerButtonSpacing) {
                    Button(action: onOpenThemePicker) {
                        Image("HomeSkin")
                            .resizable()
                            .interpolation(.high)
                            .renderingMode(.template)
                            .foregroundStyle(headerForeground)
                            .scaledToFit()
                            .frame(width: scaled(20, pad: 22), height: scaled(20, pad: 22))
                            .frame(width: headerSegmentWidth, height: headerCapsuleHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Skin", zhHans: "皮肤", zhHant: "皮膚"))

                    Button(action: onOpenBoardShare) {
                        Image(systemName: "paperplane.fill")
                            .font(.appSystem(size: scaled(17, pad: 19), weight: .semibold))
                            .foregroundStyle(headerForeground)
                            .frame(width: headerSegmentWidth, height: headerCapsuleHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Share", zhHans: "分享", zhHant: "分享"))
                }
                .homeActionGlass(isDarkBackground: isDarkBackground)
                .overlay(alignment: .topLeading) {
                    if showsSkinNewBadge {
                        FeatureNewBadge()
                            .scaleEffect(0.8, anchor: .bottomLeading)
                            .offset(x: headerSegmentWidth - 10, y: -9)
                    }
                }
                .zIndex(1)
                .offset(y: -20)

                Spacer()

                ZStack(alignment: .topTrailing) {
                    Button {
                        onOpenPointsFlow()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.appSystem(size: scaled(17, pad: 19), weight: .semibold))
                                .foregroundStyle(isDarkBackground ? Color.white : NeumorphicColors.accent)
                                .symbolEffect(.bounce, value: pointsAnimationStore.animationTrigger)

                            Text("\(availablePoints)")
                                .font(.appSystem(size: scaled(16, pad: 18), weight: .medium, design: .rounded))
                                .foregroundStyle(isDarkBackground ? Color.white : NeumorphicColors.text)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: availablePoints)
                        }
                        .padding(.horizontal, isPadLayout ? 16 : 14)
                        .frame(minWidth: headerIconSize * 2 + headerButtonSpacing)
                        .frame(height: headerCapsuleHeight)
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        pointsCapsuleWidth = width
                    }
                    .homeActionGlass(isDarkBackground: isDarkBackground)
                    .offset(y: -20)

                    if let floatingPointsDelta = pointsAnimationStore.floatingDelta {
                        Text(floatingPointsDelta > 0 ? "+\(floatingPointsDelta)" : "\(floatingPointsDelta)")
                            .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                            .foregroundStyle(isDarkBackground ? Color.white : (floatingPointsDelta > 0 ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.72)))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isDarkBackground ? Color.black.opacity(0.72) : NeumorphicColors.background.opacity(0.96))
                                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.16), radius: 5, x: 2, y: 2)
                                    .shadow(color: Color.white.opacity(0.72), radius: 4, x: -2, y: -2)
                            )
                            .offset(x: -4, y: pointsAnimationStore.isFloatingDeltaVisible ? -30 : -8)
                            .opacity(pointsAnimationStore.isFloatingDeltaVisible ? 1 : 0)
                    }
                }
            }

            if showsLimitedOffer {
                HomeLimitedOfferBannerView(
                    isPadLayout: isPadLayout,
                    offerDuration: limitedTimeOfferDuration,
                    campaignID: limitedTimeOfferCampaignID,
                    onTap: onOpenLimitedOffer
                )
                .offset(y: -20)
            }
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }

    private var headerIconSize: CGFloat {
        isPadLayout ? 38 : 34
    }

    private var headerCapsuleHeight: CGFloat {
        isPadLayout ? 42 : 38
    }

    private var headerButtonSpacing: CGFloat { 16 }

    private var headerSegmentWidth: CGFloat {
        pointsCapsuleWidth > 0
            ? (pointsCapsuleWidth - headerButtonSpacing) / 2
            : headerIconSize
    }

    private var headerForeground: Color {
        isDarkBackground ? .white : themeColor
    }
}
