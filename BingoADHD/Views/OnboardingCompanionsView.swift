import SwiftUI

/// The original onboarding collage: three characters above, two below, with edge bleed.
struct OnboardingCompanionsView: View {
    private let poses: [(asset: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, duration: Double)] = [
        ("OnboardingJuanjuanHugFlat", -38, 20, 142, 138, 1.85),
        ("OnboardingJuanjuanSunFlat", 112.5, -14, 180, 176, 2.0),
        ("OnboardingJuanjuanYawnFlat", 299, 20, 138, 138, 2.15),
        ("OnboardingJuanjuanBlanketFlat", 9, 168, 184, 176, 1.9),
        ("OnboardingJuanjuanCookieFlat", 227, 204, 137, 139, 2.05)
    ]

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 393

            DecorativeAnimationTimeline { time in
                ZStack(alignment: .topLeading) {
                    ForEach(poses.indices, id: \.self) { index in
                        let pose = poses[index]
                        let phase = time.map { .pi * $0 / pose.duration + Double(index) * 0.9 }

                        Image(decorative: pose.asset)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: pose.width * scale, height: pose.height * scale, alignment: .bottom)
                            .rotationEffect(
                                .degrees(phase.map { sin($0) * 1.8 } ?? 0),
                                anchor: .bottom
                            )
                            .offset(x: phase.map { CGFloat(cos($0)) * 2.5 * scale } ?? 0)
                            .position(
                                x: (pose.x + pose.width / 2) * scale,
                                y: (pose.y + pose.height / 2) * scale
                            )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .aspectRatio(393.0 / 370.0, contentMode: .fit)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
