import SwiftUI

struct OnboardingBrandPortalView: View {
    var body: some View {
        GeometryReader { geometry in
            DecorativeAnimationTimeline { time in
                Image(decorative: "OnboardingBrandPortal")
                    .resizable()
                    .interpolation(.high)
                    .colorEffect(
                        ShaderLibrary.onboardingPortalWaves(
                            .float2(geometry.size),
                            .float(Float(time ?? 0))
                        ),
                        isEnabled: time != nil
                    )
            }
        }
        .aspectRatio(1025.0 / 1534.0, contentMode: .fit)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
