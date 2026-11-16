import Combine

/// App-scoped ownership keeps one icon gate across windows, while the diagnostic
/// launch constructs none of the production services (including their observers).
@MainActor
final class AppServices: ObservableObject {
    @MainActor
    struct Production {
        let subscriptionManager: SubscriptionManager
        let appIconManager: AppIconManager
        let iCloudSyncCoordinator = NativeICloudSyncCoordinator.shared

        init() {
            let subscriptions = SubscriptionManager()
            subscriptionManager = subscriptions
            appIconManager = AppIconManager(hasPremiumAccess: { [weak subscriptions] in
                subscriptions?.hasPremiumAccess ?? false
            })
        }
    }

    let production: Production?

    init(
        isIconProbe: Bool = AppDebugFlags.appIconProbeEnabled,
        makeProduction: @MainActor () -> Production = { Production() }
    ) {
#if DEBUG && targetEnvironment(simulator)
        UITestBootstrap.prepareIfNeeded()
#endif
        if !isIconProbe {
            MeSkinMigration.applyIfNeeded()
            _ = AppIconEntitlementStore.shared
        }
        production = isIconProbe ? nil : makeProduction()
#if DEBUG
        if isIconProbe { print("[IconProbeIsolation] Production service construction skipped") }
#endif
    }
}
