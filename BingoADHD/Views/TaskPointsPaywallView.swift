import SwiftUI

/// Adapts the existing paywall's persisted offer state without making the task
/// editor or the reward rules depend on discount campaign behavior.
struct TaskPointsPaywallView: View {
    @AppStorage(AppSettings.hasVisitedPremiumPaywallWithoutPurchaseKey) private var visited = false
    @AppStorage(AppSettings.hasLegacyLimitedTimeDiscountExposureKey) private var legacyExposure = false
    @AppStorage(AppSettings.limitedTimeDiscountStartedAtKey) private var startedAt = 0.0
    @AppStorage(AppSettings.limitedTimeDiscountCampaignIDKey) private var campaignID = ""
    @State private var isOfferPresented = false

    var body: some View {
        PremiumPaywallView(entrySource: "task_completion_points", limitedOfferState: Binding(
            get: { LimitedOfferHomeState(hasVisitedPaywallWithoutPurchase: visited, hasLegacyExposure: legacyExposure, startedAt: startedAt, campaignID: campaignID, isPresented: isOfferPresented) },
            set: { state in
                visited = state.hasVisitedPaywallWithoutPurchase
                legacyExposure = state.hasLegacyExposure
                startedAt = state.startedAt
                campaignID = state.campaignID
                isOfferPresented = state.isPresented
            }
        ))
    }
}
