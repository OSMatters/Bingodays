import SwiftUI

/// Only the ordinary launch builds this view. The App still owns the shared
/// services and supplies its scene phase, preserving the existing lifecycle scope.
struct BingodaysProductionRoot: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    @ObservedObject var appIconManager: AppIconManager
    @ObservedObject var iCloudSyncCoordinator: NativeICloudSyncCoordinator
    let scenePhase: ScenePhase
    @Binding var hasStartedDeferredBootstrap: Bool

    var body: some View {
        AppRootView()
            .tint(NeumorphicColors.modalAccent)
            .environmentObject(subscriptionManager)
            .environmentObject(appIconManager)
            .environmentObject(iCloudSyncCoordinator)
            .task {
                AppOpenStreakStore.shared.recordOpen()
                iCloudSyncCoordinator.startIfEnabled()
                guard !hasStartedDeferredBootstrap else { return }
                hasStartedDeferredBootstrap = true
                await subscriptionManager.bootstrap()
            }
            .task(id: scenePhase == .active && subscriptionManager.hasConfirmedNoPremiumAccess) {
                guard scenePhase == .active, subscriptionManager.hasConfirmedNoPremiumAccess else { return }
                await appIconManager.restoreDefaultIfPremiumExpired()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await appIconManager.migrateSeasonalIconIfNeeded()
            }
            .onChange(of: subscriptionManager.hasPremiumAccess) { _, hasAccess in
                if hasAccess { appIconManager.premiumAccessRestored() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                appIconManager.refresh()
                guard newPhase == .active else { return }
                AppOpenStreakStore.shared.recordOpen()
                Task {
                    await subscriptionManager.refreshEntitlements()
                    await iCloudSyncCoordinator.refreshWhenAppBecomesActive()
                }
            }
    }
}
