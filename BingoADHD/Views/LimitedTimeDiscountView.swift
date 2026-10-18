import SwiftUI
import StoreKit

#if canImport(libpag)
import libpag
import UIKit

private final class LimitedTimePAGContainerView: UIView {
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

private struct LimitedTimePAGView: UIViewRepresentable {
    let resourceName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeUIView(context: Context) -> LimitedTimePAGContainerView {
        let container = LimitedTimePAGContainerView()
        let imageView = container.imageView
        imageView.setRenderScale(1)
        imageView.setCacheAllFramesInMemory(true)
        imageView.setRepeatCount(0)

        if let filePath = Bundle.main.path(forResource: resourceName, ofType: "pag") {
            _ = imageView.setPath(filePath, maxFrameRate: 24)
        }

        imageView.setCurrentFrame(0)
        if !reduceMotion && scenePhase == .active { imageView.play() }
        return container
    }

    func updateUIView(_ uiView: LimitedTimePAGContainerView, context: Context) {
        if reduceMotion || scenePhase != .active {
            uiView.imageView.pause()
            if reduceMotion { uiView.imageView.setCurrentFrame(0) }
        } else if !uiView.imageView.isPlaying() {
            uiView.imageView.play()
        }
    }

    static func dismantleUIView(_ uiView: LimitedTimePAGContainerView, coordinator: ()) {
        uiView.imageView.pause()
    }
}
#else
private struct LimitedTimePAGView: View {
    let resourceName: String

    var body: some View {
        Color.clear
    }
}
#endif

struct LimitedTimeDiscountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    let entrySource: String
    let campaignID: String
    let offerDuration: TimeInterval
    @Binding private var limitedOfferState: LimitedOfferHomeState

    @State private var feedbackMessage: String?
    @State private var didLogPaywallView = false

    private let designWidth: CGFloat = 393
    private let designHeight: CGFloat = 852

    init(
        entrySource: String,
        campaignID: String,
        offerDuration: TimeInterval,
        limitedOfferState: Binding<LimitedOfferHomeState>
    ) {
        self.entrySource = entrySource
        self.campaignID = campaignID
        self.offerDuration = offerDuration
        _limitedOfferState = limitedOfferState
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        GeometryReader { geo in
            let scale = limitedTimeScale(for: geo.size)

            ZStack(alignment: .top) {
                limitedTimeBackground
                    .ignoresSafeArea()

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    limitedTimeContent(now: timeline.date)
                        .frame(width: designWidth, height: designHeight, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: geo.size.width, height: max(geo.size.height, designHeight * scale), alignment: .top)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            if closeIfPremium() { return }
            startCountdownIfNeeded()
            logPaywallViewIfNeeded()
        }
        .task {
            if await refreshAndCloseIfPremium() { return }
            await subscriptionManager.warmupProductsForPaywall(
                requiredProductIDs: SubscriptionManager.limitedOfferProductIDs
            )
            _ = closeIfPremium()
        }
        .onChange(of: subscriptionManager.hasPremiumAccess) { _, hasPremiumAccess in
            if hasPremiumAccess {
                _ = closeIfPremium()
            }
        }
    }

    private func limitedTimeScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / designWidth
        let heightScale = size.height / designHeight

        guard isPadLayout else { return widthScale }
        return min(widthScale, heightScale, 1.12)
    }

    private func logPaywallViewIfNeeded() {
        guard !didLogPaywallView else { return }
        didLogPaywallView = true
        AnalyticsService.logPremiumPaywallViewed(
            source: entrySource,
            isMemberCenter: false
        )
    }

    private var limitedTimeBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "734A37"), location: 0),
                .init(color: Color(hex: "1D1002"), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func limitedTimeContent(now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            topAtmosphere

            LimitedTimePAGView(resourceName: "LimitedTime_bmp")
                .frame(width: designWidth, height: 430)
                .position(x: 196.5, y: 310)

            countdownBlock(now: now)
                .position(x: 196, y: 169)

            closeButton
                .position(x: 352, y: 101)

            headlineBlock
                .position(x: 196.5, y: 489)

            lifetimeCard
                .position(x: 192.5, y: 627)

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(width: 320, height: 34)
                    .position(x: 196.5, y: 707)
            }

            purchaseButton
                .position(x: 195, y: 755)

            Text(L10n.paywallLegalOneLine)
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.52))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(width: 314, height: 15)
                .position(x: 196, y: 815.5)
        }
        .frame(width: designWidth, height: designHeight, alignment: .topLeading)
    }

    private var topAtmosphere: some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: "4A2917").opacity(0.28))
                .frame(width: 470, height: 160)
                .position(x: 196, y: 393)
        }
        .frame(width: designWidth, height: 430, alignment: .topLeading)
        .clipped()
    }

    private func countdownBlock(now: Date) -> some View {
        let components = countdownComponents(now: now)

        return VStack(spacing: 20) {
            Text(L10n.limitedDiscountCountdownTitle)
                .font(.appSystem(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 28) {
                countdownBox(components.hours)
                countdownColon
                countdownBox(components.minutes)
                countdownColon
                countdownBox(components.seconds)
            }
            .frame(width: 316, height: 48)
        }
        .frame(width: 316, height: 89)
    }

    private func countdownBox(_ value: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.11))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .frame(width: 60, height: 48)
            .overlay {
                Text(value)
                    .font(.appSystem(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
    }

    private var countdownColon: some View {
        Text(":")
            .font(.appSystem(size: 28, weight: .bold))
            .foregroundStyle(.white.opacity(0.58))
            .frame(width: 10, height: 48)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            Color(hex: "8A6754").opacity(0.50),
                            Color(hex: "5E3C2A").opacity(0.36)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 42
                    )
                )
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.16),
                                    Color.white.opacity(0.56)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.6
                        )
                }
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color.white.opacity(0.12), radius: 4, x: -2, y: -2)
                .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 7)
        }
        .buttonStyle(.plain)
    }

    private var headlineBlock: some View {
        HStack(spacing: headlineWheatSpacing) {
            Image("LimitedTimeWheatFrame")
                .resizable()
                .interpolation(.high)
                .frame(width: 46, height: 68)

            Text(L10n.limitedDiscountHeadline)
                .font(.appSystem(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(width: headlineTextWidth, height: 58)

            Image("LimitedTimeWheatFrame")
                .resizable()
                .interpolation(.high)
                .frame(width: 46, height: 68)
                .scaleEffect(x: -1, y: 1)
        }
        .frame(width: headlineBlockWidth, height: 68)
    }

    private var headlineTextWidth: CGFloat {
        switch AppLanguage.current {
        case .english:
            return 223
        case .simplifiedChinese, .traditionalChinese:
            return 150
        case .japanese:
            return 176
        }
    }

    private var headlineWheatSpacing: CGFloat {
        switch AppLanguage.current {
        case .english:
            return 8
        case .simplifiedChinese, .traditionalChinese:
            return 10
        case .japanese:
            return 9
        }
    }

    private var headlineBlockWidth: CGFloat {
        (46 * 2) + headlineTextWidth + (headlineWheatSpacing * 2)
    }

    private var lifetimeCard: some View {
        ZStack(alignment: .topLeading) {
            Image("LimitedTimeCardBackground")
                .resizable()
                .interpolation(.high)
                .frame(width: 345, height: 144)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))

            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 0,
                topTrailingRadius: 19,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "976B42"),
                        Color(hex: "58320E")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 82, height: 24)
            .overlay {
                Text(L10n.limitedDiscountBadge)
                    .font(.appSystem(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .offset(x: 263, y: 0)

            Text(L10n.paywallLifetime)
                .font(.appSystem(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 145, alignment: .leading)
                .offset(x: 16, y: 17)

            Text(spacedPrice(originalLifetimePrice))
                .font(.appSystem(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "8E8278"))
                .strikethrough(true, color: Color(hex: "8E8278"))
                .frame(width: 140, alignment: .leading)
                .offset(x: 18, y: 63)

            Text(spacedPrice(discountedLifetimePrice))
                .font(.appSystem(size: 40, weight: .bold))
                .foregroundStyle(Color(hex: "3F270F"))
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .frame(width: 178, alignment: .leading)
                .offset(x: 16, y: 88)
        }
        .frame(width: 345, height: 144)
    }

    private var purchaseButton: some View {
        Button {
            Task {
                if await refreshAndCloseIfPremium() { return }
                let outcome = await subscriptionManager.purchase(
                    productID: SubscriptionManager.lifetimeEarlySupporterProductID,
                    analyticsSource: entrySource,
                    analyticsPlan: "limited_time_lifetime"
                )
                if outcome.completedPurchase {
                    clearLimitedOfferStateAfterPurchase()
                    NotificationCenter.default.post(name: .limitedOfferEligibilityDidChange, object: nil)
                    if subscriptionManager.hasPremiumAccess {
                        dismiss()
                    } else {
                        feedbackMessage = outcome.feedbackMessage
                    }
                } else {
                    feedbackMessage = outcome.feedbackMessage
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: "D3A375"))
                .frame(width: 350, height: 56)
                .overlay {
                    LimitedTimePaymentButtonSweep()
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .allowsHitTesting(false)
                }
                .overlay {
                    Text(subscriptionManager.isPurchasing ? L10n.subscriptionPleaseWait : L10n.limitedDiscountButtonTitle)
                        .font(.appSystem(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
        }
        .buttonStyle(.plain)
        .disabled(
            subscriptionManager.isPurchasing
                || !subscriptionManager.isReadyToPurchase(
                    productID: SubscriptionManager.lifetimeEarlySupporterProductID
                )
        )
        .opacity(
            subscriptionManager.isPurchasing
                || !subscriptionManager.isReadyToPurchase(
                    productID: SubscriptionManager.lifetimeEarlySupporterProductID
                )
                ? 0.9
                : 1
        )
    }

    private var originalLifetimePrice: String {
        return subscriptionManager.displayPrice(for: SubscriptionManager.lifetimeProductID)
    }

    private var discountedLifetimePrice: String {
        subscriptionManager.displayPrice(
            for: SubscriptionManager.lifetimeEarlySupporterProductID
        )
    }

    private func startCountdownIfNeeded() {
        limitedOfferState = LimitedOfferHomeRules.applyingDiscountPagePresentation(
            to: limitedOfferState,
            campaignID: campaignID,
            now: .now
        )
    }

    private func countdownComponents(now: Date) -> (hours: String, minutes: String, seconds: String) {
        let storedStartedAt = limitedOfferState.startedAt > 0
            ? limitedOfferState.startedAt
            : now.timeIntervalSince1970
        let startedAt = min(storedStartedAt, now.timeIntervalSince1970)
        let target = Date(timeIntervalSince1970: startedAt + offerDuration)
        let totalSeconds = max(0, Int(ceil(target.timeIntervalSince(now))))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        return (
            twoDigitCountdownValue(hours),
            twoDigitCountdownValue(minutes),
            twoDigitCountdownValue(seconds)
        )
    }

    private func twoDigitCountdownValue(_ value: Int) -> String {
        if value < 10 {
            return "0\(value)"
        }
        return "\(value)"
    }

    private func clearLimitedOfferStateAfterPurchase() {
        limitedOfferState = LimitedOfferHomeRules.applyingConfirmedPurchase(to: limitedOfferState)
    }

    @MainActor
    private func refreshAndCloseIfPremium() async -> Bool {
        if closeIfPremium() { return true }
        await subscriptionManager.refreshEntitlements()
        return closeIfPremium()
    }

    @MainActor
    private func closeIfPremium() -> Bool {
        guard subscriptionManager.hasPremiumAccess else { return false }
        NotificationCenter.default.post(name: .limitedOfferEligibilityDidChange, object: nil)
        dismiss()
        return true
    }

    private func spacedPrice(_ displayPrice: String) -> String {
        guard let firstDigitIndex = displayPrice.firstIndex(where: { $0.isNumber }) else {
            return displayPrice
        }

        let prefix = displayPrice[..<firstDigitIndex]
        if prefix.isEmpty || prefix.last?.isWhitespace == true {
            return displayPrice
        }

        return "\(prefix) \(displayPrice[firstDigitIndex...])"
    }

}

private struct LimitedTimePaymentButtonSweep: View {

    var body: some View {
        DecorativeAnimationTimeline { time in
            let progress = time.map { max(0, ($0.truncatingRemainder(dividingBy: 1.8) - 0.45) / 1.35) }
            GeometryReader { geo in
                let sweepWidth = geo.size.width * 0.34
                let travelDistance = geo.size.width + sweepWidth

                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.62),
                        Color.white.opacity(0.16),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: sweepWidth, height: geo.size.height * 2.4)
                .rotationEffect(.degrees(18))
                .offset(
                    x: progress.map { -sweepWidth * 1.35 + (travelDistance + sweepWidth * 1.35) * $0 } ?? geo.size.width * 0.15,
                    y: -geo.size.height * 0.7
                )
                .blendMode(.screen)
                .opacity(time == nil ? 0.18 : 1)
            }
            .compositingGroup()
        }
    }
}
