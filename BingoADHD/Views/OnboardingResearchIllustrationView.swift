import SwiftUI

struct OnboardingResearchIllustrationView: View {
    private let artworkSize: CGFloat = 1254
    // Source-pixel bounds follow the rim closely to avoid enlarging adjacent facial features.
    private let lensBounds = CGRect(x: 358, y: 476, width: 247, height: 250)
    private let movementCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.77, y: 0),
        endControlPoint: UnitPoint(x: 0.175, y: 1)
    )

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / artworkSize
            let lens = CGRect(
                x: lensBounds.minX * scale,
                y: lensBounds.minY * scale,
                width: lensBounds.width * scale,
                height: lensBounds.height * scale
            )

            ZStack(alignment: .topLeading) {
                Image(decorative: "OnboardingResearchLaptopFlat")
                    .resizable()
                    .interpolation(.high)

                DecorativeAnimationTimeline { time in
                    if let time {
                        let phase = time.truncatingRemainder(dividingBy: 3.2)
                        let progress = phase < 0.85 ? phase / 0.85 : (1.95 - phase) / 0.85
                        let enlargement = movementCurve.value(at: min(1, max(0, progress)))

                        // Staying at or above the original size covers the baked-in lens.
                        // Its handle and the rest of the character remain stationary.
                        Image(decorative: "OnboardingResearchLaptopFlat")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .offset(x: -lens.minX, y: -lens.minY)
                            .frame(width: lens.width, height: lens.height, alignment: .topLeading)
                            .clipShape(Ellipse())
                            .scaleEffect(1 + 0.16 * enlargement)
                            .position(x: lens.midX, y: lens.midY)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
