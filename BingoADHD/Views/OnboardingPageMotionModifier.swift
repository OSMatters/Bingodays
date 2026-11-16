import SwiftUI

struct OnboardingPageMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let phase: OnboardingPageMotionPhase
    let role: OnboardingPageMotionRole

    private var animation: Animation? {
        guard !reduceMotion else { return nil }
        switch phase {
        case .hidden:
            return nil
        case .visible:
            return OnboardingPageMotionPhase.animation(duration: 0.28)
                .delay(Double(role.rawValue) * 0.055)
        case .exiting:
            return OnboardingPageMotionPhase.animation(duration: OnboardingPageMotionPhase.exitDuration)
                .delay(Double(OnboardingPageMotionRole.action.rawValue - role.rawValue) * 0.018)
        }
    }

    private var verticalOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        switch phase {
        case .hidden: return role == .artwork ? 18 : 12
        case .visible: return 0
        case .exiting: return role == .artwork ? -10 : -6
        }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: verticalOffset)
            .animation(animation, value: phase)
    }
}

extension View {
    func onboardingPageMotion(
        _ phase: OnboardingPageMotionPhase,
        role: OnboardingPageMotionRole
    ) -> some View {
        modifier(OnboardingPageMotionModifier(phase: phase, role: role))
    }
}
