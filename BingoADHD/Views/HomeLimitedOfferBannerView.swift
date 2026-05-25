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
        imageView.play()
        return container
    }

    func updateUIView(_ uiView: PAGLoopContainerView, context: Context) {
    }

    static func dismantleUIView(_ uiView: PAGLoopContainerView, coordinator: ()) {
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
    let onTap: () -> Void

    @AppStorage(AppSettings.limitedTimeDiscountStartedAtKey) private var limitedTimeDiscountStartedAt = 0.0

    private let offerDuration: TimeInterval = 48 * 60 * 60

    private var bannerWidth: CGFloat {
        isPadLayout ? 178 : 136
    }

    private var bannerHeight: CGFloat {
        isPadLayout ? 42 : 32
    }

    private var animationSize: CGFloat {
        isPadLayout ? 62 : 48
    }

    private var titleFontSize: CGFloat {
        isPadLayout ? 15 : 12
    }

    private var titleVerticalAdjustment: CGFloat {
        isPadLayout ? 9 : 8
    }

    private var capsuleHorizontalInset: CGFloat {
        0
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack(alignment: .leading) {
                limitedOfferCapsule
                    .padding(.horizontal, capsuleHorizontalInset)

                PAGLoopView(resourceName: "limited_home_bmp")
                    .frame(width: animationSize, height: animationSize)
                    .offset(x: isPadLayout ? 3 : 2, y: isPadLayout ? -3 : -2)
                    .allowsHitTesting(false)

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(bannerTitle(now: timeline.date))
                        .font(.appSystem(size: titleFontSize, weight: .semibold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                        .frame(width: isPadLayout ? 94 : 74, height: 19, alignment: .center)
                }
                .position(x: isPadLayout ? 99 : 76, y: (bannerHeight / 2) + titleVerticalAdjustment)

                Image("LimitedOfferStar")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .frame(width: isPadLayout ? 17 : 12, height: isPadLayout ? 17 : 12)
                    .position(x: isPadLayout ? 151 : 116, y: isPadLayout ? 13 : 10)

                Image("LimitedOfferStar")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .frame(width: isPadLayout ? 10 : 8, height: isPadLayout ? 10 : 8)
                    .position(x: isPadLayout ? 162 : 125, y: isPadLayout ? 27 : 22)
            }
            .frame(width: bannerWidth, height: bannerHeight, alignment: .leading)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: bannerWidth, height: bannerHeight)
        .padding(.bottom, 8)
    }

    private var limitedOfferCapsule: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "BB814C"),
                        Color(hex: "8F5C2F"),
                        Color(hex: "5A351B")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color(hex: "D8A36B"), lineWidth: 2)
            }
            .shadow(color: Color(hex: "6F3916").opacity(0.26), radius: 11, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.08), radius: 7, x: 0, y: 3)
            .frame(width: bannerWidth - (capsuleHorizontalInset * 2), height: bannerHeight)
    }

    private func bannerTitle(now: Date) -> String {
        guard limitedTimeDiscountStartedAt > 0 else {
            return L10n.limitedOfferHomeTitle
        }

        let target = Date(timeIntervalSince1970: limitedTimeDiscountStartedAt + offerDuration)
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
