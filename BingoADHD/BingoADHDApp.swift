import SwiftUI
import CoreText
import FirebaseCore
import FirebaseAnalytics
import GoogleSignIn
import StoreKit

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

enum AnalyticsService {
    static func bootstrap() {
        syncThemeUserProperty(AppTheme(rawValue: UserDefaults.standard.string(forKey: AppSettings.themeKey) ?? AppTheme.concise.rawValue) ?? .concise)
        syncMyTasksLibrary(CommonTasksStore.loadLibrary(), shouldLogEvent: false)
    }

    static func logStickerRedeemed(_ kind: StickerKind) {
        Analytics.logEvent("sticker_redeemed", parameters: [
            "sticker_id": kind.rawValue,
            "required_points": kind.requiredPoints
        ])
    }

    static func logBingoCompleted(boardSize: Int, completedLineCount: Int, filledTaskCount: Int) {
        Analytics.logEvent("bingo_completed", parameters: [
            "board_size": boardSize,
            "completed_line_count": completedLineCount,
            "filled_task_count": filledTaskCount
        ])
    }

    static func logThemeColorSelected(_ theme: AppTheme) {
        Analytics.logEvent("theme_color_selected", parameters: [
            "theme_color_id": theme.rawValue
        ])
        syncThemeUserProperty(theme)
    }

    static func logPremiumBoardsLimitHit(currentBoardCount: Int) {
        Analytics.logEvent("premium_limit_boards_hit", parameters: [
            "current_board_count": currentBoardCount
        ])
    }

    static func logPremiumTasksGroupsLimitHit(
        source: String,
        taskCount: Int,
        groupCount: Int,
        groupTaskCount: Int
    ) {
        Analytics.logEvent("premium_limit_tasks_groups_hit", parameters: [
            "source": source,
            "task_count": taskCount,
            "group_count": groupCount,
            "group_task_count": groupTaskCount
        ])
    }

    static func logPremiumGrid5x5LimitHit(currentGridSize: Int, source: String) {
        Analytics.logEvent("premium_limit_grid_5x5_hit", parameters: [
            "current_grid_size": currentGridSize,
            "source": source
        ])
    }

    static func logPremiumFeaturePurchaseSuccess(source: String, plan: String, productID: String) {
        Analytics.logEvent("premium_feature_purchase_success", parameters: [
            "source": source,
            "plan": plan,
            "product_id": productID
        ])
    }

    static func logTemplateShareOpen(source: String, gridSize: Int, isPremium: Bool) {
        Analytics.logEvent("template_share_open", parameters: [
            "source": source,
            "grid_size": gridSize,
            "is_premium": isPremium ? 1 : 0
        ])
    }

    static func logTemplateShareSaveImageClick(source: String, gridSize: Int, isPremium: Bool) {
        Analytics.logEvent("template_share_save_image_click", parameters: [
            "source": source,
            "grid_size": gridSize,
            "is_premium": isPremium ? 1 : 0
        ])
    }

    static func logTemplateImportPageOpen(source: String, gridSize: Int, createsNewBoard: Bool) {
        Analytics.logEvent("template_import_page_open", parameters: [
            "source": source,
            "grid_size": gridSize,
            "creates_new_board": createsNewBoard ? 1 : 0
        ])
    }

    static func logTemplateImportSuccess(source: String, gridSize: Int, createsNewBoard: Bool) {
        Analytics.logEvent("template_import_success", parameters: [
            "source": source,
            "grid_size": gridSize,
            "creates_new_board": createsNewBoard ? 1 : 0
        ])
    }

    static func syncMyTasksLibrary(_ library: MyTasksLibrary, shouldLogEvent: Bool = true) {
        let taskCount = library.tasks.count
        let groupCount = library.groups.count
        let groupTaskCount = library.groups.reduce(0) { $0 + $1.tasks.count }

        if shouldLogEvent {
            Analytics.logEvent("my_tasks_library_updated", parameters: [
                "task_count": taskCount,
                "group_count": groupCount,
                "group_task_count": groupTaskCount
            ])
        }

        Analytics.setUserProperty(String(taskCount), forName: "my_tasks_count")
        Analytics.setUserProperty(String(groupCount), forName: "my_group_count")
        Analytics.setUserProperty(String(groupTaskCount), forName: "my_group_task_count")
    }

    static func logBB2048SessionStart(themeID: String, gridSize: Int) {
        Analytics.logEvent("bb2048_session_start", parameters: [
            "theme_id": themeID,
            "grid_size": gridSize
        ])
    }

    static func logBB2048SessionEnd(
        themeID: String,
        gridSize: Int,
        durationSeconds: Int,
        finalScore: Int,
        maxTileScore: Int,
        moveCount: Int,
        mergeCount: Int,
        bingoCount: Int
    ) {
        Analytics.logEvent("bb2048_session_end", parameters: [
            "theme_id": themeID,
            "grid_size": gridSize,
            "duration_seconds": max(durationSeconds, 0),
            "final_score": finalScore,
            "max_tile_score": maxTileScore,
            "move_count": moveCount,
            "merge_count": mergeCount,
            "bingo_count": bingoCount
        ])
    }

    static func logBB2048ScoreReached(
        themeID: String,
        gridSize: Int,
        score: Int,
        maxTileScore: Int,
        moveCount: Int,
        mergeCount: Int
    ) {
        Analytics.logEvent("bb2048_score_2048", parameters: [
            "theme_id": themeID,
            "grid_size": gridSize,
            "score": score,
            "max_tile_score": maxTileScore,
            "move_count": moveCount,
            "merge_count": mergeCount
        ])
    }

    private static func syncThemeUserProperty(_ theme: AppTheme) {
        Analytics.setUserProperty(theme.rawValue, forName: "selected_theme_color")
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
#endif
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        AppFontRegistrar.registerIfNeeded()
        AnalyticsService.bootstrap()
        return true
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

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

@MainActor
enum PremiumPlanKind: String {
    case monthly
    case yearly
    case lifetime

    var productID: String {
        switch self {
        case .monthly:
            return SubscriptionManager.monthlyProductID
        case .yearly:
            return SubscriptionManager.yearlyProductID
        case .lifetime:
            return SubscriptionManager.lifetimeProductID
        }
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    nonisolated static let monthlyProductID = "com.bingoday.app.premium.monthly"
    nonisolated static let yearlyProductID = "com.bingoday.app.premium.yearly"
    nonisolated static let lifetimeProductID = "com.bingodays.app.lifetime.unlock"

    nonisolated static let allProductIDs = [
        monthlyProductID,
        yearlyProductID,
        lifetimeProductID
    ]

    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var hasActiveAutoRenewable = false
    @Published private(set) var hasLifetimeAccess = false
    @Published private(set) var hasPremiumAccess = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var storefrontCountryCode = "--"
    @Published private(set) var storefrontID = "--"
    @Published private(set) var loadedProductIDs: [String] = []
    @Published private(set) var missingProductIDs: [String] = []
    @Published private(set) var currentPlanKind: PremiumPlanKind?
    @Published private(set) var currentPlanExpirationDate: Date?
    @Published private(set) var autoRenewablePlanKind: PremiumPlanKind?

    private var updatesTask: Task<Void, Never>?
    private var cachedDisplayPrices: [String: String] = [:]
    private static let cachedDisplayPricesKey = "subscription.cached_display_prices"

    init() {
        if let cached = UserDefaults.standard.dictionary(forKey: Self.cachedDisplayPricesKey) as? [String: String] {
            cachedDisplayPrices = cached
        }
        updatesTask = observeTransactionUpdates()
        Task {
            await refreshAll()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refreshAll() async {
        await refreshStorefront()
        await loadProducts()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var collected: Set<String> = []
        let now = Date()
        var resolvedLifetime = false
        var resolvedAutoRenewablePlan: PremiumPlanKind?
        var resolvedAutoRenewableExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = verified(result) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= now { continue }
            collected.insert(transaction.productID)

            if transaction.productID == Self.lifetimeProductID {
                resolvedLifetime = true
                continue
            }

            guard let expirationDate = transaction.expirationDate,
                  let plan = planKind(for: transaction.productID) else {
                continue
            }

            if resolvedAutoRenewableExpirationDate == nil || expirationDate > resolvedAutoRenewableExpirationDate! {
                resolvedAutoRenewablePlan = plan
                resolvedAutoRenewableExpirationDate = expirationDate
            }
        }

        // Sandbox can occasionally lag on currentEntitlements right after purchase.
        // Fallback to latest(for:) so activation does not appear to fail.
        await mergeLatestTransactionsIntoEntitlements(
            now: now,
            collected: &collected,
            resolvedLifetime: &resolvedLifetime,
            resolvedAutoRenewablePlan: &resolvedAutoRenewablePlan,
            resolvedAutoRenewableExpirationDate: &resolvedAutoRenewableExpirationDate
        )

        activeProductIDs = collected
        hasActiveAutoRenewable = collected.contains(Self.monthlyProductID) || collected.contains(Self.yearlyProductID)
        hasLifetimeAccess = resolvedLifetime
        hasPremiumAccess = hasActiveAutoRenewable || hasLifetimeAccess
        autoRenewablePlanKind = resolvedAutoRenewablePlan
        currentPlanKind = resolvedLifetime ? .lifetime : resolvedAutoRenewablePlan
        currentPlanExpirationDate = resolvedLifetime ? nil : resolvedAutoRenewableExpirationDate
    }

    func refreshStorefront() async {
        if let storefront = await Storefront.current {
            storefrontCountryCode = storefront.countryCode
            storefrontID = storefront.id
        } else {
            storefrontCountryCode = "--"
            storefrontID = "--"
        }
    }

    func loadProducts() async {
        if isLoadingProducts { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: Self.allProductIDs)
            var mapped: [String: Product] = [:]
            for product in products {
                mapped[product.id] = product
            }
            productsByID = mapped
            cacheDisplayPrices(from: mapped)
            loadedProductIDs = mapped.keys.sorted()
            missingProductIDs = Self.allProductIDs.filter { mapped[$0] == nil }
        } catch {
            productsByID = [:]
            loadedProductIDs = []
            missingProductIDs = Self.allProductIDs
        }
    }

    func displayPrice(for productID: String) -> String {
        if let livePrice = productsByID[productID]?.displayPrice {
            return livePrice
        }
        return cachedDisplayPrices[productID] ?? "--"
    }

    var hasLoadedAllPaywallProducts: Bool {
        Self.allProductIDs.allSatisfy { productsByID[$0] != nil }
    }

    func warmupProductsForPaywall(maxAttempts: Int = 3) async {
        for attempt in 0..<maxAttempts {
            await refreshAll()
            if hasLoadedAllPaywallProducts { return }
            if attempt < (maxAttempts - 1) {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    func purchase(
        productID: String,
        analyticsSource: String? = nil,
        analyticsPlan: String? = nil
    ) async -> String {
        if isPurchasing {
            return L10n.subscriptionPleaseWait
        }

        isPurchasing = true
        defer { isPurchasing = false }

        if productsByID[productID] == nil {
            await loadProducts()
        }

        guard let product = productsByID[productID] else {
            return L10n.subscriptionProductUnavailable
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = verified(verification) else {
                    return L10n.subscriptionVerificationFailed
                }
                applyImmediateActivation(from: transaction)
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumFeaturePurchaseSuccess(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: transaction.productID
                    )
                }
                await transaction.finish()
                let activated = await confirmPremiumActivationAfterPurchase()
                return activated ? L10n.subscriptionPurchaseSucceeded : L10n.subscriptionActivationPending
            case .pending:
                return L10n.subscriptionPurchasePending
            case .userCancelled:
                return L10n.subscriptionPurchaseCancelled
            @unknown default:
                return L10n.subscriptionUnknownResult
            }
        } catch {
            return L10n.subscriptionPurchaseFailed
        }
    }

    func restorePurchases() async -> String {
        if isPurchasing {
            return L10n.subscriptionPleaseWait
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            let restored = await confirmPremiumActivationAfterPurchase()
            return restored ? L10n.subscriptionRestoreSucceeded : L10n.subscriptionNotFound
        } catch {
            return L10n.subscriptionRestoreFailed
        }
    }

    private func confirmPremiumActivationAfterPurchase() async -> Bool {
        await refreshEntitlements()
        if hasPremiumAccess { return true }

        do {
            try await AppStore.sync()
        } catch {
            // Keep going with local entitlement retries.
        }

        await refreshEntitlements()
        if hasPremiumAccess { return true }

        for delay in [400_000_000, 1_000_000_000] {
            try? await Task.sleep(nanoseconds: UInt64(delay))
            await refreshEntitlements()
            if hasPremiumAccess { return true }
        }

        return false
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    applyImmediateActivation(from: transaction)
                    await transaction.finish()
                }
                await refreshEntitlements()
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            return nil
        }
    }

    private func planKind(for productID: String) -> PremiumPlanKind? {
        switch productID {
        case Self.monthlyProductID:
            return .monthly
        case Self.yearlyProductID:
            return .yearly
        case Self.lifetimeProductID:
            return .lifetime
        default:
            return nil
        }
    }

    private func applyImmediateActivation(from transaction: StoreKit.Transaction) {
        let now = Date()
        guard transaction.revocationDate == nil else { return }
        if let expirationDate = transaction.expirationDate, expirationDate <= now { return }

        activeProductIDs.insert(transaction.productID)

        if transaction.productID == Self.lifetimeProductID {
            hasLifetimeAccess = true
            hasPremiumAccess = true
            currentPlanKind = .lifetime
            currentPlanExpirationDate = nil
            return
        }

        guard let plan = planKind(for: transaction.productID) else { return }
        hasActiveAutoRenewable = true
        hasPremiumAccess = true
        autoRenewablePlanKind = plan
        if !hasLifetimeAccess {
            currentPlanKind = plan
            currentPlanExpirationDate = transaction.expirationDate
        }
    }

    private func mergeLatestTransactionsIntoEntitlements(
        now: Date,
        collected: inout Set<String>,
        resolvedLifetime: inout Bool,
        resolvedAutoRenewablePlan: inout PremiumPlanKind?,
        resolvedAutoRenewableExpirationDate: inout Date?
    ) async {
        for productID in Self.allProductIDs {
            guard let latestResult = await StoreKit.Transaction.latest(for: productID),
                  let transaction = verified(latestResult) else {
                continue
            }

            if transaction.revocationDate != nil { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= now { continue }

            collected.insert(transaction.productID)

            if transaction.productID == Self.lifetimeProductID {
                resolvedLifetime = true
                continue
            }

            guard let expirationDate = transaction.expirationDate,
                  let plan = planKind(for: transaction.productID) else {
                continue
            }

            if resolvedAutoRenewableExpirationDate == nil || expirationDate > resolvedAutoRenewableExpirationDate! {
                resolvedAutoRenewablePlan = plan
                resolvedAutoRenewableExpirationDate = expirationDate
            }
        }
    }

    private func cacheDisplayPrices(from mapped: [String: Product]) {
        for (productID, product) in mapped {
            cachedDisplayPrices[productID] = product.displayPrice
        }
        UserDefaults.standard.set(cachedDisplayPrices, forKey: Self.cachedDisplayPricesKey)
    }
}
