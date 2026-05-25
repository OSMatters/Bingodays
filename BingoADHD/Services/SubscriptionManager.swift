import SwiftUI
import StoreKit

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
    nonisolated static let lifetimeEarlySupporterProductID = "com.bingodays.app.lifetime.unlock.early20"

    nonisolated static let allProductIDs = [
        monthlyProductID,
        yearlyProductID,
        lifetimeProductID,
        lifetimeEarlySupporterProductID
    ]

    nonisolated static func isLifetimeProductID(_ productID: String) -> Bool {
        productID == lifetimeProductID || productID == lifetimeEarlySupporterProductID
    }

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
    @Published private(set) var hasCompletedEntitlementRefresh = false

    private var updatesTask: Task<Void, Never>?
    private var cachedDisplayPrices: [String: String] = [:]
    private static let cachedDisplayPricesKey = "subscription.cached_display_prices"

    init() {
        if let cached = UserDefaults.standard.dictionary(forKey: Self.cachedDisplayPricesKey) as? [String: String] {
            cachedDisplayPrices = cached
        }
        updatesTask = observeTransactionUpdates()
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

            if Self.isLifetimeProductID(transaction.productID) {
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

#if DEBUG
        if AppDebugFlags.forceNoPremiumAccess {
            collected = []
            resolvedLifetime = false
            resolvedAutoRenewablePlan = nil
            resolvedAutoRenewableExpirationDate = nil
        }
#endif

        activeProductIDs = collected
        hasActiveAutoRenewable = collected.contains(Self.monthlyProductID) || collected.contains(Self.yearlyProductID)
        hasLifetimeAccess = resolvedLifetime
        hasPremiumAccess = hasActiveAutoRenewable || hasLifetimeAccess
        autoRenewablePlanKind = resolvedAutoRenewablePlan
        currentPlanKind = resolvedLifetime ? .lifetime : resolvedAutoRenewablePlan
        currentPlanExpirationDate = resolvedLifetime ? nil : resolvedAutoRenewableExpirationDate
        hasCompletedEntitlementRefresh = true
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

        if let analyticsSource, let analyticsPlan {
            AnalyticsService.logPremiumPurchaseAttempt(
                source: analyticsSource,
                plan: analyticsPlan,
                productID: productID
            )
        }

        guard let product = productsByID[productID] else {
            if let analyticsSource, let analyticsPlan {
                AnalyticsService.logPremiumPurchaseResult(
                    source: analyticsSource,
                    plan: analyticsPlan,
                    productID: productID,
                    result: "product_unavailable"
                )
            }
            return L10n.subscriptionProductUnavailable
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = verified(verification) else {
                    if let analyticsSource, let analyticsPlan {
                        AnalyticsService.logPremiumPurchaseResult(
                            source: analyticsSource,
                            plan: analyticsPlan,
                            productID: productID,
                            result: "verification_failed"
                        )
                    }
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
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseResult(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: transaction.productID,
                        result: activated ? "activated" : "activation_pending"
                    )
                }
                return activated ? L10n.subscriptionPurchaseSucceeded : L10n.subscriptionActivationPending
            case .pending:
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseResult(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: productID,
                        result: "pending"
                    )
                }
                return L10n.subscriptionPurchasePending
            case .userCancelled:
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseResult(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: productID,
                        result: "cancelled"
                    )
                }
                return L10n.subscriptionPurchaseCancelled
            @unknown default:
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseResult(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: productID,
                        result: "unknown"
                    )
                }
                return L10n.subscriptionUnknownResult
            }
        } catch {
            if let analyticsSource, let analyticsPlan {
                AnalyticsService.logPremiumPurchaseResult(
                    source: analyticsSource,
                    plan: analyticsPlan,
                    productID: productID,
                    result: "failed"
                )
            }
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
#if DEBUG
        guard !AppDebugFlags.forceNoPremiumAccess else { return }
#endif

        let now = Date()
        guard transaction.revocationDate == nil else { return }
        if let expirationDate = transaction.expirationDate, expirationDate <= now { return }

        activeProductIDs.insert(transaction.productID)

        if Self.isLifetimeProductID(transaction.productID) {
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

            if Self.isLifetimeProductID(transaction.productID) {
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
