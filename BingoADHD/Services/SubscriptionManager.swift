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
    private static let pendingPurchaseAttributionKey = "subscription.pending_purchase_attribution"
    private static let purchaseAttributionTTL: TimeInterval = 30 * 60

    private struct PurchaseAttribution: Codable {
        let source: String
        let plan: String
        let productID: String
        let attemptID: String
        let startedAt: Date

        var ageSeconds: Int {
            max(Int(Date().timeIntervalSince(startedAt)), 0)
        }
    }

    private struct OptimisticEntitlement {
        let productID: String
        let expirationDate: Date?
    }

    private var optimisticEntitlementsByProductID: [String: OptimisticEntitlement] = [:]

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
            guard let activatedProductID = activatedProductID(from: transaction) else { continue }
            collected.insert(activatedProductID)

            if Self.isLifetimeProductID(activatedProductID) {
                resolvedLifetime = true
                continue
            }

            guard let expirationDate = transaction.expirationDate,
                  let plan = planKind(for: activatedProductID) else {
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
        mergeOptimisticEntitlementsIntoResolvedState(
            now: now,
            collected: &collected,
            resolvedLifetime: &resolvedLifetime,
            resolvedAutoRenewablePlan: &resolvedAutoRenewablePlan,
            resolvedAutoRenewableExpirationDate: &resolvedAutoRenewableExpirationDate
        )

#if DEBUG
        if AppDebugFlags.forceNoPremiumAccess {
            if optimisticEntitlementsByProductID.isEmpty {
                collected = []
                resolvedLifetime = false
                resolvedAutoRenewablePlan = nil
                resolvedAutoRenewableExpirationDate = nil
            } else {
                print("[Subscription] Keeping verified purchase activation despite DebugForceNoPremium.")
            }
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
#if DEBUG
        print(
            "[Subscription] refresh resolved",
            "active=\(activeProductIDs.sorted())",
            "hasPremium=\(hasPremiumAccess)",
            "lifetime=\(hasLifetimeAccess)",
            "autoRenewable=\(hasActiveAutoRenewable)",
            "optimistic=\(optimisticEntitlementsByProductID.keys.sorted())",
            "forceNoPremium=\(AppDebugFlags.forceNoPremiumAccess)"
        )
#endif
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

        let purchaseAttribution: PurchaseAttribution?
        if let analyticsSource, let analyticsPlan {
            let attribution = beginPurchaseAttribution(
                source: analyticsSource,
                plan: analyticsPlan,
                productID: productID
            )
            purchaseAttribution = attribution
            AnalyticsService.logPremiumPurchaseAttempt(
                source: analyticsSource,
                plan: analyticsPlan,
                productID: productID,
                purchaseAttemptID: attribution.attemptID
            )
        } else {
            purchaseAttribution = nil
        }

        guard let product = productsByID[productID] else {
            if let analyticsSource, let analyticsPlan {
                AnalyticsService.logPremiumPurchaseResult(
                    source: analyticsSource,
                    plan: analyticsPlan,
                    productID: productID,
                    result: "product_unavailable",
                    purchaseAttemptID: purchaseAttribution?.attemptID,
                    attributionAgeSeconds: purchaseAttribution?.ageSeconds
                )
            }
            clearPurchaseAttribution(purchaseAttribution)
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
                            result: "verification_failed",
                            purchaseAttemptID: purchaseAttribution?.attemptID,
                            attributionAgeSeconds: purchaseAttribution?.ageSeconds
                        )
                    }
                    clearPurchaseAttribution(purchaseAttribution)
                    return L10n.subscriptionVerificationFailed
                }
                let didApplyImmediateActivation = applyVerifiedPurchaseActivation(from: transaction)
#if DEBUG
                print(
                    "[Subscription] purchase verified",
                    "requested=\(productID)",
                    "transaction=\(transaction.productID)",
                    "activated=\(didApplyImmediateActivation)",
                    "hasPremium=\(hasPremiumAccess)",
                    "forceNoPremium=\(AppDebugFlags.forceNoPremiumAccess)"
                )
#endif
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseSuccess(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        product: product,
                        transaction: transaction,
                        purchaseAttemptID: purchaseAttribution?.attemptID,
                        attributionAgeSeconds: purchaseAttribution?.ageSeconds
                    )
                }
                await transaction.finish()
                if didApplyImmediateActivation {
                    // Treat the verified transaction as the source of truth for the
                    // immediate UI state; entitlement streams can lag in sandbox.
                    applyVerifiedPurchaseActivation(from: transaction)
                    if let analyticsSource, let analyticsPlan {
                        AnalyticsService.logPremiumPurchaseResult(
                            source: analyticsSource,
                            plan: analyticsPlan,
                            productID: activatedProductID(from: transaction) ?? transaction.productID,
                            result: "activated",
                            purchaseAttemptID: purchaseAttribution?.attemptID,
                            attributionAgeSeconds: purchaseAttribution?.ageSeconds
                        )
                    }
                    clearPurchaseAttribution(purchaseAttribution)
                    Task { [weak self] in
                        await self?.refreshEntitlements()
                    }
                    return L10n.subscriptionPurchaseSucceeded
                }
                let activated = await confirmPremiumActivationAfterPurchase()
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseResult(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: activatedProductID(from: transaction) ?? transaction.productID,
                        result: activated ? "activated" : "activation_pending",
                        purchaseAttemptID: purchaseAttribution?.attemptID,
                        attributionAgeSeconds: purchaseAttribution?.ageSeconds
                    )
                }
                clearPurchaseAttribution(purchaseAttribution)
                return activated ? L10n.subscriptionPurchaseSucceeded : L10n.subscriptionActivationPending
            case .pending:
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseResult(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: productID,
                        result: "pending",
                        purchaseAttemptID: purchaseAttribution?.attemptID,
                        attributionAgeSeconds: purchaseAttribution?.ageSeconds
                    )
                }
                return L10n.subscriptionPurchasePending
            case .userCancelled:
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseResult(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: productID,
                        result: "cancelled",
                        purchaseAttemptID: purchaseAttribution?.attemptID,
                        attributionAgeSeconds: purchaseAttribution?.ageSeconds
                    )
                }
                clearPurchaseAttribution(purchaseAttribution)
                return L10n.subscriptionPurchaseCancelled
            @unknown default:
                if let analyticsSource, let analyticsPlan {
                    AnalyticsService.logPremiumPurchaseResult(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: productID,
                        result: "unknown",
                        purchaseAttemptID: purchaseAttribution?.attemptID,
                        attributionAgeSeconds: purchaseAttribution?.ageSeconds
                    )
                }
                clearPurchaseAttribution(purchaseAttribution)
                return L10n.subscriptionUnknownResult
            }
        } catch {
            if let analyticsSource, let analyticsPlan {
                AnalyticsService.logPremiumPurchaseResult(
                    source: analyticsSource,
                    plan: analyticsPlan,
                    productID: productID,
                    result: "failed",
                    purchaseAttemptID: purchaseAttribution?.attemptID,
                    attributionAgeSeconds: purchaseAttribution?.ageSeconds
                )
            }
            clearPurchaseAttribution(purchaseAttribution)
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
                    let attribution = activePurchaseAttribution(for: transaction.productID)
                    let plan = analyticsPlan(for: transaction.productID)
                    let source = attribution?.source ?? "storekit_transaction_update"
                    let analyticsPlan = attribution?.plan ?? plan
                    if let product = productsByID[transaction.productID] {
                        AnalyticsService.logPremiumPurchaseSuccess(
                            source: source,
                            plan: analyticsPlan,
                            product: product,
                            transaction: transaction,
                            purchaseAttemptID: attribution?.attemptID,
                            attributionAgeSeconds: attribution?.ageSeconds
                        )
                    } else {
                        AnalyticsService.logPremiumTransactionUpdate(
                            source: source,
                            plan: analyticsPlan,
                            transaction: transaction,
                            purchaseAttemptID: attribution?.attemptID,
                            attributionAgeSeconds: attribution?.ageSeconds
                        )
                    }
                    clearPurchaseAttribution(attribution)
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

    private func analyticsPlan(for productID: String) -> String {
        switch productID {
        case Self.monthlyProductID:
            return "monthly"
        case Self.yearlyProductID:
            return "yearly"
        case Self.lifetimeProductID:
            return "lifetime"
        case Self.lifetimeEarlySupporterProductID:
            return "limited_time_lifetime"
        default:
            return "unknown"
        }
    }

    private func beginPurchaseAttribution(source: String, plan: String, productID: String) -> PurchaseAttribution {
        let attribution = PurchaseAttribution(
            source: source,
            plan: plan,
            productID: productID,
            attemptID: UUID().uuidString,
            startedAt: Date()
        )
        if let data = try? JSONEncoder().encode(attribution) {
            UserDefaults.standard.set(data, forKey: Self.pendingPurchaseAttributionKey)
        }
        return attribution
    }

    private func activePurchaseAttribution(for productID: String) -> PurchaseAttribution? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingPurchaseAttributionKey),
              let attribution = try? JSONDecoder().decode(PurchaseAttribution.self, from: data) else {
            return nil
        }
        guard Date().timeIntervalSince(attribution.startedAt) <= Self.purchaseAttributionTTL else {
            UserDefaults.standard.removeObject(forKey: Self.pendingPurchaseAttributionKey)
            return nil
        }
        guard attribution.productID == productID else { return nil }
        return attribution
    }

    private func clearPurchaseAttribution(_ attribution: PurchaseAttribution?) {
        guard let attribution,
              let data = UserDefaults.standard.data(forKey: Self.pendingPurchaseAttributionKey),
              let stored = try? JSONDecoder().decode(PurchaseAttribution.self, from: data),
              stored.attemptID == attribution.attemptID else {
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingPurchaseAttributionKey)
    }

    @discardableResult
    private func applyVerifiedPurchaseActivation(from transaction: StoreKit.Transaction) -> Bool {
        guard let productID = activatedProductID(from: transaction) else { return false }
        guard transaction.revocationDate == nil else { return false }
        if let expirationDate = transaction.expirationDate, expirationDate <= Date() { return false }

        return activatePremiumAccess(
            productID: productID,
            expirationDate: transaction.expirationDate
        )
    }

    @discardableResult
    private func applyImmediateActivation(
        from transaction: StoreKit.Transaction
    ) -> Bool {
#if DEBUG
        guard !AppDebugFlags.forceNoPremiumAccess else { return false }
#endif

        let now = Date()
        guard transactionCanActivatePremium(transaction, now: now),
              let productID = activatedProductID(from: transaction) else {
            return false
        }

        return activatePremiumAccess(
            productID: productID,
            expirationDate: transaction.expirationDate
        )
    }

    @discardableResult
    private func activatePremiumAccess(productID: String, expirationDate: Date?) -> Bool {
        activeProductIDs.insert(productID)
        optimisticEntitlementsByProductID[productID] = OptimisticEntitlement(
            productID: productID,
            expirationDate: expirationDate
        )
        hasCompletedEntitlementRefresh = true

        if Self.isLifetimeProductID(productID) {
            hasLifetimeAccess = true
            hasPremiumAccess = true
            currentPlanKind = .lifetime
            currentPlanExpirationDate = nil
#if DEBUG
            print("[Subscription] activated lifetime access", "productID=\(productID)", "hasPremium=\(hasPremiumAccess)")
#endif
            return true
        }

        guard let plan = planKind(for: productID) else { return false }
        hasActiveAutoRenewable = true
        hasPremiumAccess = true
        autoRenewablePlanKind = plan
        if !hasLifetimeAccess {
            currentPlanKind = plan
            currentPlanExpirationDate = expirationDate
        }
#if DEBUG
        print("[Subscription] activated subscription access", "productID=\(productID)", "hasPremium=\(hasPremiumAccess)")
#endif
        return true
    }

    private func transactionCanActivatePremium(
        _ transaction: StoreKit.Transaction,
        now: Date = Date()
    ) -> Bool {
        guard transaction.revocationDate == nil else { return false }
        if let expirationDate = transaction.expirationDate, expirationDate <= now { return false }
        return true
    }

    private func activatedProductID(
        from transaction: StoreKit.Transaction
    ) -> String? {
        if Self.allProductIDs.contains(transaction.productID) {
            return transaction.productID
        }
        return nil
    }

    private func mergeOptimisticEntitlementsIntoResolvedState(
        now: Date,
        collected: inout Set<String>,
        resolvedLifetime: inout Bool,
        resolvedAutoRenewablePlan: inout PremiumPlanKind?,
        resolvedAutoRenewableExpirationDate: inout Date?
    ) {
        var expiredProductIDs: [String] = []
        for (productID, entitlement) in optimisticEntitlementsByProductID {
            if let expirationDate = entitlement.expirationDate, expirationDate <= now {
                expiredProductIDs.append(productID)
                continue
            }

            collected.insert(entitlement.productID)

            if Self.isLifetimeProductID(entitlement.productID) {
                resolvedLifetime = true
                continue
            }

            guard let expirationDate = entitlement.expirationDate,
                  let plan = planKind(for: entitlement.productID) else {
                continue
            }

            if resolvedAutoRenewableExpirationDate == nil || expirationDate > resolvedAutoRenewableExpirationDate! {
                resolvedAutoRenewablePlan = plan
                resolvedAutoRenewableExpirationDate = expirationDate
            }
        }
        for productID in expiredProductIDs {
            optimisticEntitlementsByProductID.removeValue(forKey: productID)
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
            guard let activatedProductID = activatedProductID(from: transaction),
                  activatedProductID == productID else {
                continue
            }

            collected.insert(activatedProductID)

            if Self.isLifetimeProductID(activatedProductID) {
                resolvedLifetime = true
                continue
            }

            guard let expirationDate = transaction.expirationDate,
                  let plan = planKind(for: activatedProductID) else {
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
