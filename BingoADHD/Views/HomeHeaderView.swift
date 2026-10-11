import SwiftUI

struct HomeHeaderView: View {
    @ObservedObject var pointsAnimationStore: PointsAnimationStore

    let isPadLayout: Bool
    let availablePoints: Int
    let showsLimitedOffer: Bool
    let limitedTimeOfferDuration: TimeInterval
    let limitedTimeOfferCampaignID: String
    let themeColor: Color
    let showsSkinNewBadge: Bool
    let onOpenThemePicker: () -> Void
    let onOpenBoardShare: () -> Void
    let onOpenPointsFlow: () -> Void
    let onOpenLimitedOffer: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Button(action: onOpenThemePicker) {
                        Image("HomeSkin")
                            .resizable()
                            .interpolation(.high)
                            .renderingMode(.template)
                            .foregroundColor(themeColor)
                            .scaledToFit()
                            .frame(width: scaled(24, pad: 28), height: scaled(24, pad: 28))
                            .frame(width: headerIconSize, height: headerIconSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showsSkinNewBadge {
                        Text("NEW")
                            .font(.appSystem(size: scaled(7, pad: 8), weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(hex: "E56F5B"))
                            )
                            .offset(x: scaled(8, pad: 10), y: scaled(-7, pad: -9))
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: headerIconSize, height: headerIconSize)
                .offset(y: -20)

                headerIconButton(
                    systemImage: "paperplane.fill",
                    action: onOpenBoardShare
                )

                Spacer()

                ZStack(alignment: .topTrailing) {
                    Button {
                        onOpenPointsFlow()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.appSystem(size: scaled(20, pad: 22), weight: .semibold))
                                .foregroundColor(NeumorphicColors.accent)
                                .symbolEffect(.bounce, value: pointsAnimationStore.animationTrigger)

                            Text("\(availablePoints)")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .medium, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: availablePoints)
                        }
                        .padding(.horizontal, isPadLayout ? 22 : 20)
                        .frame(height: isPadLayout ? 52 : 48)
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .offset(y: -20)

                    if let floatingPointsDelta = pointsAnimationStore.floatingDelta {
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
        isPadLayout ? 44 : 40
    }

    private func headerIconButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.appSystem(size: scaled(19, pad: 22), weight: .semibold))
                .foregroundColor(themeColor)
                .frame(width: headerIconSize, height: headerIconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: -20)
    }
}
