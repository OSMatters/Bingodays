import SwiftUI

struct HomeHeaderView: View {
    @ObservedObject var pointsAnimationStore: PointsAnimationStore
    @AppStorage(AppSettings.limitedTimeDiscountStartedAtKey) private var limitedTimeDiscountStartedAt = 0.0

    let isPadLayout: Bool
    let availablePoints: Int
    let showsLimitedOffer: Bool
    let onToggleSidebar: () -> Void
    let onOpenPointsFlow: () -> Void
    let onOpenLimitedOffer: () -> Void

    var body: some View {
        let iconSize: CGFloat = isPadLayout ? 52 : 48

        ZStack {
            HStack {
                Button {
                    onToggleSidebar()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.appSystem(size: scaled(20, pad: 23), weight: .semibold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: iconSize, height: iconSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: -20)

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
                ZStack {
                    HomeLimitedOfferBannerView(
                        isPadLayout: isPadLayout,
                        onTap: onOpenLimitedOffer
                    )

                    if shouldShowLimitedOfferCountdownLabel {
                        Text(L10n.limitedOfferCountdownLabel)
                            .font(.appSystem(size: isPadLayout ? 10 : 9, weight: .bold))
                            .foregroundColor(Color(hex: "D3A375"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(height: isPadLayout ? 12 : 11)
                            .offset(y: isPadLayout ? -31 : -26)
                    }
                }
                .offset(y: -20)
            }
        }
    }

    private var shouldShowLimitedOfferCountdownLabel: Bool {
        limitedTimeDiscountStartedAt > 0
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}
