import SwiftUI

enum OnboardingPageMotionPhase: Equatable {
    case hidden
    case visible
    case exiting

    static let exitDuration: TimeInterval = 0.16

    static func animation(duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
}
