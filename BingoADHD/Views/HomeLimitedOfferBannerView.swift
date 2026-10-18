import SwiftUI

#if canImport(libpag)
import libpag
import UIKit

private final class PAGLoopContainerView: UIView {
    let imageView = PAGImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false

        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct PAGLoopView: UIViewRepresentable {
    let resourceName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    final class Coordinator {
        var playbackAllowed = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PAGLoopContainerView {
        let container = PAGLoopContainerView()
        let imageView = container.imageView
        imageView.setRenderScale(0.9)
        imageView.setCacheAllFramesInMemory(true)
        imageView.setRepeatCount(2)

        if let filePath = Bundle.main.path(forResource: resourceName, ofType: "pag") {
            _ = imageView.setPath(filePath, maxFrameRate: 24)
        }

        imageView.setCurrentFrame(0)
        context.coordinator.playbackAllowed = !reduceMotion && scenePhase == .active
        if context.coordinator.playbackAllowed { imageView.play() }
        return container
    }

    func updateUIView(_ uiView: PAGLoopContainerView, context: Context) {
        let allowed = !reduceMotion && scenePhase == .active
        if !allowed {
            uiView.imageView.pause()
            if reduceMotion { uiView.imageView.setCurrentFrame(0) }
        } else if !context.coordinator.playbackAllowed {
            uiView.imageView.play()
        }
        context.coordinator.playbackAllowed = allowed
    }

    static func dismantleUIView(_ uiView: PAGLoopContainerView, coordinator: Coordinator) {
        uiView.imageView.pause()
    }
}
#else
private struct PAGLoopView: View {
    let resourceName: String

    var body: some View {
        Color.clear
    }
}
#endif

struct HomeLimitedOfferBannerView: View {
    let isPadLayout: Bool
    let offerDuration: TimeInterval
    let campaignID: String
    let onTap: () -> Void

    @AppStorage(AppSettings.limitedTimeDiscountStartedAtKey) private var limitedTimeDiscountStartedAt = 0.0

    private var bannerWidth: CGFloat {
        isPadLayout ? 170 : 136
    }

    private var bannerHeight: CGFloat {
        isPadLayout ? 50 : 42
    }

    private var animationSize: CGFloat {
        isPadLayout ? 50 : 40
    }

    private var bubbleWidth: CGFloat {
        isPadLayout ? 128 : 100
    }

    private var bubbleHeight: CGFloat {
        bubbleWidth * 76 / 234
    }

    private var bubbleLeadingOffset: CGFloat {
        isPadLayout ? 41 : 37
    }

    private var bubbleTextLeadingPadding: CGFloat {
        isPadLayout ? 25 : 20
    }

    private var bubbleTextTrailingPadding: CGFloat {
        isPadLayout ? 12 : 8
    }

    private var titleFontSize: CGFloat {
        isPadLayout ? 15 : 11
    }

    private var countdownTitleFontSize: CGFloat {
        isPadLayout ? 13 : 10
    }

    private var countdownFontSize: CGFloat {
        isPadLayout ? 14 : 11
    }

    private var starSize: CGFloat {
        isPadLayout ? 9 : 7
    }

    private var hasStartedCountdown: Bool {
        limitedTimeDiscountStartedAt > 0
    }

    var body: some View {
        Button {
            AnalyticsService.logOfferBannerClicked(
                campaignID: campaignID,
                countdownStarted: hasStartedCountdown
            )
            onTap()
        } label: {
            ZStack(alignment: .leading) {
                limitedOfferBubble

                PAGLoopView(resourceName: "limited_home_bmp")
                    .frame(width: animationSize, height: animationSize)
                    .offset(x: 0, y: isPadLayout ? -1 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: bannerWidth, height: bannerHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: bannerWidth, height: bannerHeight)
        .onAppear {
            AnalyticsService.logOfferBannerViewed(
                campaignID: campaignID,
                countdownStarted: hasStartedCountdown
            )
        }
    }

    private var limitedOfferBubble: some View {
        Image("LimitedOfferBubble")
            .resizable()
            .interpolation(.high)
            .frame(width: bubbleWidth, height: bubbleHeight)
            .overlay {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    bannerText(now: timeline.date)
                        .padding(.leading, bubbleTextLeadingPadding)
                        .padding(.trailing, bubbleTextTrailingPadding)
                        .frame(width: bubbleWidth, height: bubbleHeight)
                }
            }
            .offset(x: bubbleLeadingOffset, y: isPadLayout ? 3 : 2)
            .shadow(color: Color(hex: "6F3916").opacity(0.14), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private func bannerText(now: Date) -> some View {
        if hasStartedCountdown {
            VStack(spacing: isPadLayout ? 1 : 0) {
                titleWithStar(fontSize: countdownTitleFontSize)
                Text(countdownText(now: now))
                    .font(.appSystem(size: countdownFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .offset(x: -7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            titleWithStar(fontSize: titleFontSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func titleWithStar(fontSize: CGFloat) -> some View {
        HStack(spacing: isPadLayout ? 7 : 5) {
            Text(L10n.limitedOfferHomeTitle)
                .font(.appSystem(size: fontSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Image("LimitedOfferStar")
                .resizable()
                .interpolation(.high)
                .renderingMode(.template)
                .foregroundStyle(.white)
                .frame(width: starSize, height: starSize)
        }
    }

    private func countdownText(now: Date) -> String {
        let effectiveStartedAt = min(limitedTimeDiscountStartedAt, now.timeIntervalSince1970)
        let target = Date(timeIntervalSince1970: effectiveStartedAt + offerDuration)
        let totalSeconds = max(0, Int(ceil(target.timeIntervalSince(now))))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        return "\(twoDigitCountdownValue(hours)):\(twoDigitCountdownValue(minutes)):\(twoDigitCountdownValue(seconds))"
    }

    private func twoDigitCountdownValue(_ value: Int) -> String {
        if value < 10 {
            return "0\(value)"
        }

        return "\(value)"
    }
}
