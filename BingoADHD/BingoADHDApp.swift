import SwiftUI
import CoreText
import FirebaseCore
import GoogleSignIn
import UserNotifications

enum AppFeatureFlags {
    // Soft-off account capabilities for review builds.
    // Set to true to restore account features later.
    static let isAccountEnabled = false

    // Soft-off template sharing capabilities.
    // Set to true to restore share/import template flows later.
    static let isTemplateSharingEnabled = true
}

enum AppFontRegistrar {
    private static var hasRegisteredFonts = false

    static func registerIfNeeded() {
        guard !hasRegisteredFonts else { return }

        let fontFileNames = [
            "ArchivoBlack-Regular.ttf",
            "Outfit-wght.ttf",
            "Schoolbell-Regular.ttf"
        ]

        for fileName in fontFileNames {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        hasRegisteredFonts = true
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private func clearLegacyNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    private func scheduleLegacyNotificationCleanup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.clearLegacyNotifications()
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
#endif
        FirebaseApp.configure()
        AnalyticsService.setCollectionEnabled(true)
        AppFontRegistrar.registerIfNeeded()
        AnalyticsService.bootstrap()
        scheduleLegacyNotificationCleanup()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        scheduleLegacyNotificationCleanup()
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        guard AppFeatureFlags.isTemplateSharingEnabled else {
            return false
        }
        return BoardTemplateImportCoordinator.shared.handleIncomingURL(url)
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard AppFeatureFlags.isTemplateSharingEnabled else {
            return false
        }
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }
        return BoardTemplateImportCoordinator.shared.handleIncomingURL(url)
    }
}

@main
struct BingoADHDApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var subscriptionManager = SubscriptionManager()
    @State private var hasStartedDeferredBootstrap = false

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(subscriptionManager)
                .task {
                    guard !hasStartedDeferredBootstrap else { return }
                    hasStartedDeferredBootstrap = true
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await subscriptionManager.refreshEntitlements()
                }
        }
    }
}
