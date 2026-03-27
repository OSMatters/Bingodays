import SwiftUI
import CoreText
import FirebaseCore
import FirebaseAnalytics
import GoogleSignIn
import StoreKit

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
        GIDSignIn.sharedInstance.handle(url)
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
final class SubscriptionManager: ObservableObject {
    static let monthlyProductID = "com.bingoday.app.premium.monthly"
    static let yearlyProductID = "com.bingoday.app.premium.yearly"
    static let lifetimeProductID = "com.bingodays.app.lifetime.unlock"

    static let allProductIDs = [
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

    private var updatesTask: Task<Void, Never>?

    init() {
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

        for await result in Transaction.currentEntitlements {
            guard let transaction = verified(result) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= now { continue }
            collected.insert(transaction.productID)
        }

        activeProductIDs = collected
        hasActiveAutoRenewable = collected.contains(Self.monthlyProductID) || collected.contains(Self.yearlyProductID)
        hasLifetimeAccess = collected.contains(Self.lifetimeProductID)
        hasPremiumAccess = hasActiveAutoRenewable || hasLifetimeAccess
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
            loadedProductIDs = mapped.keys.sorted()
            missingProductIDs = Self.allProductIDs.filter { mapped[$0] == nil }
        } catch {
            productsByID = [:]
            loadedProductIDs = []
            missingProductIDs = Self.allProductIDs
        }
    }

    func displayPrice(for productID: String) -> String {
        productsByID[productID]?.displayPrice ?? "--"
    }

    func purchase(productID: String) async -> String {
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
                await transaction.finish()
                await refreshEntitlements()
                return L10n.subscriptionPurchaseSucceeded
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
            await refreshEntitlements()
            return hasPremiumAccess ? L10n.subscriptionRestoreSucceeded : L10n.subscriptionNotFound
        } catch {
            return L10n.subscriptionRestoreFailed
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
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
}
