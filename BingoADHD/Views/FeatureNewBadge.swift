import SwiftUI

struct FeatureNewBadge: View {
    @AppStorage(AppSettings.newBadgeExistingUserKey) private var isExistingUser = false

    var body: some View {
        if isExistingUser {
            Text(verbatim: "NEW")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.red, in: Capsule())
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

enum FeatureNewBadgeEligibility {
    static func initializeIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: AppSettings.newBadgeExistingUserKey) == nil else { return }
        // Capture the install's state before this version can complete onboarding.
        let hasCompletedOnboarding = defaults.bool(forKey: AppSettings.hasSeenOnboardingKey)
        defaults.set(hasCompletedOnboarding, forKey: AppSettings.newBadgeExistingUserKey)
    }
}
