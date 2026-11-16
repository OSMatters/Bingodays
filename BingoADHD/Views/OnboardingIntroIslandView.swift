import SwiftUI

/// Separates the star at display time so the original illustration stays intact.
struct OnboardingIntroIslandView: View {
    private let artworkSize = CGSize(width: 1221, height: 1289)
    private let starBounds = CGRect(x: 734, y: 122, width: 164, height: 160)
    private let movementCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.77, y: 0),
        endControlPoint: UnitPoint(x: 0.175, y: 1)
    )

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / artworkSize.width
            let star = CGRect(
                x: starBounds.minX * scale,
                y: starBounds.minY * scale,
                width: starBounds.width * scale,
                height: starBounds.height * scale
            )

            ZStack(alignment: .topLeading) {
                Image(decorative: "OnboardingIntroIsland")
                    .resizable()
                    .interpolation(.high)
                    .mask {
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: geometry.size))
                            path.addRect(star)
                        }
                        .fill(style: FillStyle(eoFill: true))
                    }

                DecorativeAnimationTimeline { time in
                    // Hop up and down, spin in place, then rest before repeating.
                    let phase = (time ?? 0).truncatingRemainder(dividingBy: 3.4)
                    let hopProgress = phase < 0.5 ? phase / 0.5 : (1 - phase) / 0.5
                    let hop = movementCurve.value(at: min(1, max(0, hopProgress)))
                    let spinProgress = min(1, max(0, (phase - 1.25) / 1.25))
                    let rotation = movementCurve.value(at: spinProgress) * 360

                    Image(decorative: "OnboardingIntroIsland")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(x: -star.minX, y: -star.minY)
                        .frame(width: star.width, height: star.height, alignment: .topLeading)
                        .clipped()
                        .rotationEffect(.degrees(rotation))
                        .offset(y: -36 * scale * hop)
                        .position(x: star.midX, y: star.midY)
                }
            }
        }
        .aspectRatio(artworkSize.width / artworkSize.height, contentMode: .fit)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
