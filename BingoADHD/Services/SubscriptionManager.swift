import SwiftUI
import StoreKit
import RevenueCat

enum SubscriptionPurchaseOutcome: Equatable {
    case activated
    case pending
    case cancelled
    case failed
    case productUnavailable
    case inProgress

    var feedbackMessage: String {
        switch self {
        case .activated:
            return L10n.subscriptionPurchaseSucceeded
        case .pending:
            return L10n.subscriptionActivationPending
        case .cancelled:
            return L10n.subscriptionPurchaseCancelled
        case .failed:
            return L10n.subscriptionPurchaseFailed
        case .productUnavailable:
            return L10n.subscriptionProductUnavailable
        case .inProgress:
            return L10n.subscriptionPleaseWait
        }
    }

    var completedPurchase: Bool {
        self == .activated
    }

    var analyticsResult: String {
        switch self {
        case .activated: return "activated"
        case .pending: return "pending"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        case .productUnavailable: return "product_unavailable"
        case .inProgress: return "in_progress"
        }
    }
}

enum PaywallPriceCatalogState: Equatable {
    case idle
    case loading
    case refreshing
    case ready
    case partiallyReady
    case unavailable

    var isLoading: Bool {
        self == .loading || self == .refreshing
    }
}

struct PaywallProductSnapshot: Equatable {
    let productID: String
    let displayPrice: String
    let price: Decimal
    let currencyCode: String
    let priceSource: String
    let packageIdentifier: String
    let offeringIdentifier: String
    let storefrontID: String
    let storefrontCountryCode: String
}

struct PaywallStoreProductPriceSnapshot: Equatable {
    let displayPrice: String
    let price: Decimal
    let currencyCode: String
    let source: String
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
    private static let revenueCatAPIKey = "appl_egWkNCljyLRHddIlFQGmnxEsPiL"
    private static let premiumEntitlementID = "premium"
    private static let defaultOfferingID = "default"
    private static let limitedOfferOfferingID = "limited_offer"
    private static let migrationSyncCompletedKey = "revenuecat.migration_sync_completed"
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

    nonisolated static let defaultPaywallProductIDs = [
        monthlyProductID,
        yearlyProductID,
        lifetimeProductID
    ]

    nonisolated static let limitedOfferProductIDs = [
        lifetimeProductID,
        lifetimeEarlySupporterProductID
    ]

    nonisolated static func isLifetimeProductID(_ productID: String) -> Bool {
        productID == lifetimeProductID || productID == lifetimeEarlySupporterProductID
    }

    @Published private(set) var productsByID: [String: PaywallProductSnapshot] = [:]
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var hasActiveAutoRenewable = false
    @Published private(set) var hasLifetimeAccess = false
    @Published private(set) var hasPremiumAccess = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    private(set) var lastCompletedPurchaseTransactionID: String?
    @Published private(set) var storefrontCountryCode = "--"
    @Published private(set) var storefrontCurrencyCode = "--"
    @Published private(set) var storefrontID = "--"
    @Published private(set) var loadedProductIDs: [String] = []
    @Published private(set) var missingProductIDs: [String] = []
    @Published private(set) var priceCatalogState: PaywallPriceCatalogState = .idle
    @Published private(set) var currentPlanKind: PremiumPlanKind?
    @Published private(set) var currentPlanExpirationDate: Date?
    @Published private(set) var autoRenewablePlanKind: PremiumPlanKind?
    @Published private(set) var hasCompletedEntitlementRefresh = false

    private var bootstrapTask: Task<Void, Never>?
    private var customerInfoUpdatesTask: Task<Void, Never>?
    private var storefrontUpdatesTask: Task<Void, Never>?
    private var entitlementRefreshTask: Task<Void, Never>?
    private var legacyPurchaseMigrationTask: Task<Void, Never>?
    private var hasCompletedBootstrap = false
    private var packagesByProductID: [String: Package] = [:]
    private static let pendingPurchaseAttributionKey = "subscription.pending_purchase_attribution"

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

    private struct StoreKitEntitlement {
        let productID: String
        let expirationDate: Date?
    }

    deinit {
        bootstrapTask?.cancel()
        customerInfoUpdatesTask?.cancel()
        storefrontUpdatesTask?.cancel()
    }

    func bootstrap() async {
        if hasCompletedBootstrap {
            return
        }
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performBootstrap()
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    private func performBootstrap() async {
        DiagnosticLogStore.recordStateChange("subscription.bootstrap_started")
        await refreshStorefront()
        configureRevenueCatIfNeeded()
        await refreshPriceCatalog()
        await refreshEntitlementsAfterConfiguration()
        hasCompletedBootstrap = true
        DiagnosticLogStore.recordStateChange(
            "subscription.bootstrap_completed",
            details: [
                "paywall_product_count": "\(productsByID.count)",
                "revenuecat_package_count": "\(packagesByProductID.count)"
            ]
        )
    }

    private func configureRevenueCatIfNeeded() {
        DiagnosticLogStore.recordStateChange(
            "subscription.revenuecat_configuration_started",
            details: [
                "storefront_country": storefrontCountryCode,
                "storefront_id": storefrontID
            ]
        )
        if !Purchases.isConfigured {
            let configuration = Configuration.Builder(withAPIKey: Self.revenueCatAPIKey).build()
            Purchases.configure(with: configuration)
        }
        startCustomerInfoUpdatesIfNeeded()
        startStorefrontUpdatesIfNeeded()
        DiagnosticLogStore.recordStateChange("subscription.revenuecat_configuration_completed")
    }

    private func startCustomerInfoUpdatesIfNeeded() {
        guard customerInfoUpdatesTask == nil else { return }
        customerInfoUpdatesTask = Task { [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                self?.apply(customerInfo: customerInfo)
            }
        }
    }

    private func startStorefrontUpdatesIfNeeded() {
        guard storefrontUpdatesTask == nil else { return }
        storefrontUpdatesTask = Task { [weak self] in
            for await storefront in StoreKit.Storefront.updates {
                guard let self else { return }
                guard self.applyStorefront(storefront) else { continue }
                await self.reloadPriceCatalogAfterStorefrontChange()
            }
        }
    }

    func refreshAll() async {
        let requiresBootstrap = !hasCompletedBootstrap
        await bootstrap()
        if requiresBootstrap {
            return
        }
        await refreshPriceCatalog()
        await refreshEntitlementsAfterConfiguration()
    }

    func refreshEntitlements() async {
        if !hasCompletedBootstrap {
            await bootstrap()
            return
        }
        await refreshEntitlementsAfterConfiguration()
    }

    private func refreshEntitlementsAfterConfiguration() async {
        if let entitlementRefreshTask {
            await entitlementRefreshTask.value
            return
        }

        let refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performEntitlementRefresh()
        }
        entitlementRefreshTask = refreshTask
        await refreshTask.value
        entitlementRefreshTask = nil
    }

    private func performEntitlementRefresh() async {
        do {
            apply(
                customerInfo: try await Purchases.shared.customerInfo(),
                marksRefreshComplete: false
            )
        } catch {
            // Keep the last known CustomerInfo cache during transient network failures.
        }

        await resolveLegacyStoreKitEntitlementIfNeeded()
        hasCompletedEntitlementRefresh = true
    }

    @discardableResult
    func refreshStorefront() async -> Bool {
        applyStorefront(await StoreKit.Storefront.current)
    }

    @discardableResult
    private func applyStorefront(_ storefront: StoreKit.Storefront?) -> Bool {
        guard let storefront else {
            DiagnosticLogStore.recordWarning(
                "subscription.storefront_unavailable",
                details: ["retained_storefront_id": storefrontID]
            )
            return false
        }

        let previousStorefrontID = storefrontID
        storefrontCountryCode = storefront.countryCode
        storefrontCurrencyCode = storefront.currency?.identifier.uppercased()
            ?? Self.expectedCurrencyCode(forStorefrontCountryCode: storefront.countryCode)
            ?? "--"
        storefrontID = storefront.id
        let didChange = Self.didStorefrontChange(
            previousStorefrontID: previousStorefrontID,
            currentStorefrontID: storefrontID
        )
        let didResolveInitialStorefront = previousStorefrontID == "--" && storefrontID != "--"
        if didChange {
            invalidateStorefrontBoundProducts()
        }
        DiagnosticLogStore.recordStateChange(
            "subscription.storefront_resolved",
            details: [
                "country": storefrontCountryCode,
                "currency": storefrontCurrencyCode,
                "storefront_id": storefrontID,
                "changed": "\(didChange)"
            ]
        )
        return didChange || didResolveInitialStorefront
    }

    func loadProducts() async {
        if !hasCompletedBootstrap {
            await bootstrap()
            return
        }
        await refreshPriceCatalog()
    }

    private func refreshPriceCatalog() async {
        let resolvedStorefront = await refreshStorefront()
        if resolvedStorefront && storefrontID != "--" {
            priceCatalogState = productsByID.isEmpty ? .loading : .refreshing
        } else if productsByID.isEmpty {
            priceCatalogState = .loading
        }

        await loadOfferings()
        updatePriceCatalogState()
    }

    private func reloadPriceCatalogAfterStorefrontChange() async {
        priceCatalogState = .loading
        await loadOfferings()
        updatePriceCatalogState()
    }

    private func loadOfferings(maxAttempts: Int = 3) async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        for attempt in 0..<maxAttempts {
            let loadedAllProducts = await loadOfferingsAttempt(forceCurrentFetch: attempt > 0)
            if loadedAllProducts {
                return
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    @discardableResult
    private func loadOfferingsAttempt(forceCurrentFetch: Bool) async -> Bool {
        do {
            let offerings = try await fetchOfferings(forceCurrentFetch: forceCurrentFetch)
            let relevantOfferings = [
                offerings.offering(identifier: Self.defaultOfferingID),
                offerings.offering(identifier: Self.limitedOfferOfferingID)
            ].compactMap { $0 }
            var availablePackages: [String: Package] = [:]
            var availableProducts: [String: PaywallProductSnapshot] = [:]
            let retainedProducts = productsByID.filter { $0.value.storefrontID == storefrontID }
            let retainedPackages = packagesByProductID.filter { retainedProducts[$0.key] != nil }
            for package in relevantOfferings.flatMap(\.availablePackages) {
                let productID = package.storeProduct.productIdentifier
                guard Self.allProductIDs.contains(productID) else { continue }

                guard let productSnapshot = Self.productSnapshot(
                    from: package,
                    storefrontID: storefrontID,
                    storefrontCountryCode: storefrontCountryCode
                ) else {
                    DiagnosticLogStore.recordWarning(
                        "subscription.revenuecat_product_price_unavailable",
                        details: [
                            "product_id": productID,
                            "offering_id": package.presentedOfferingContext.offeringIdentifier,
                            "package_id": package.identifier
                        ]
                    )
                    continue
                }

                availablePackages[productID] = package
                availableProducts[productID] = productSnapshot
            }

            let mergedProducts = retainedProducts.merging(availableProducts) { _, new in new }
            let mergedPackages = retainedPackages.merging(availablePackages) { _, new in new }

            if !mergedProducts.isEmpty {
                packagesByProductID = mergedPackages
                productsByID = mergedProducts
                loadedProductIDs = mergedProducts.keys.sorted()
                missingProductIDs = Self.allProductIDs.filter { mergedProducts[$0] == nil }
            } else {
                packagesByProductID = [:]
                loadedProductIDs = []
                missingProductIDs = Self.allProductIDs
            }
            recordRevenueCatProductDiagnostics()
            return Self.allProductIDs.allSatisfy { mergedProducts[$0] != nil }
        } catch {
            // A temporary Offering failure must not erase a package that was
            // already usable during this app session.
            if productsByID.isEmpty {
                packagesByProductID = [:]
                loadedProductIDs = []
                missingProductIDs = Self.allProductIDs
            }
            DiagnosticLogStore.recordWarning(
                "subscription.revenuecat_offerings_failed",
                details: [
                    "error": error.localizedDescription,
                    "retained_product_count": "\(productsByID.count)"
                ]
            )
            return false
        }
    }

    private func fetchOfferings(forceCurrentFetch: Bool) async throws -> Offerings {
        if forceCurrentFetch,
           let offerings = try await Purchases.shared.syncAttributesAndOfferingsIfNeeded() {
            return offerings
        }
        return try await Purchases.shared.offerings()
    }

    private func recordRevenueCatProductDiagnostics() {
        for productID in Self.allProductIDs {
            guard let package = packagesByProductID[productID] else {
                DiagnosticLogStore.recordWarning(
                    "subscription.revenuecat_product_missing",
                    details: ["product_id": productID]
                )
                continue
            }

            let storeProduct = package.storeProduct
            let snapshot = productsByID[productID]
            let priceSource = snapshot?.priceSource ?? "--"
            let accepted = String(snapshot != nil)
            let revenueCatAmount = NSDecimalNumber(decimal: storeProduct.price).stringValue
            let revenueCatCurrency = storeProduct.currencyCode ?? "--"
            let revenueCatPrice = storeProduct.localizedPriceString
            let selectedAmount = snapshot.map { NSDecimalNumber(decimal: $0.price).stringValue } ?? "--"
            let selectedCurrency = snapshot?.currencyCode ?? "--"
            let selectedPrice = snapshot?.displayPrice ?? "--"
            let details: [String: String] = [
                "accepted": accepted,
                "amount": revenueCatAmount,
                "currency": revenueCatCurrency,
                "price": revenueCatPrice,
                "price_source": priceSource,
                "selected_amount": selectedAmount,
                "selected_currency": selectedCurrency,
                "selected_price": selectedPrice,
                "product_id": productID,
                "package_id": package.identifier,
                "offering_id": package.presentedOfferingContext.offeringIdentifier,
                "storefront_country": storefrontCountryCode,
                "storefront_currency": storefrontCurrencyCode,
                "storefront_id": storefrontID
            ]
            DiagnosticLogStore.recordStateChange(
                "subscription.revenuecat_product_loaded",
                details: details
            )
        }
    }

    private func resolveLegacyStoreKitEntitlementIfNeeded() async {
        guard !hasPremiumAccess,
              !UserDefaults.standard.bool(forKey: Self.migrationSyncCompletedKey) else {
            return
        }

        guard let entitlement = await activeStoreKitEntitlement() else {
            // There is no legacy purchase on this Apple account, so no receipt import is needed.
            UserDefaults.standard.set(true, forKey: Self.migrationSyncCompletedKey)
            return
        }

        // RevenueCat remains the durable source of truth. StoreKit is used only to
        // prevent existing purchasers being treated as free users while their
        // pre-RevenueCat receipt is imported in the background.
        applyLegacyStoreKitEntitlement(entitlement)
        startLegacyPurchaseMigration()
    }

    private func startLegacyPurchaseMigration() {
        guard !UserDefaults.standard.bool(forKey: Self.migrationSyncCompletedKey),
              legacyPurchaseMigrationTask == nil else {
            return
        }

        legacyPurchaseMigrationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.legacyPurchaseMigrationTask = nil }

            do {
                let customerInfo = try await Purchases.shared.syncPurchases()
                UserDefaults.standard.set(true, forKey: Self.migrationSyncCompletedKey)
                self.apply(customerInfo: customerInfo)
                DiagnosticLogStore.recordStateChange("subscription.legacy_receipt_imported")
            } catch {
                // Keep the StoreKit safety-net state for this run and retry on a later launch.
                DiagnosticLogStore.recordWarning(
                    "subscription.legacy_receipt_import_failed",
                    details: ["error": error.localizedDescription]
                )
            }
        }
    }

    private func activeStoreKitEntitlement() async -> StoreKitEntitlement? {
        let now = Date()
        var activeSubscription: StoreKitEntitlement?

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  Self.allProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else {
                continue
            }
            if let expirationDate = transaction.expirationDate, expirationDate <= now {
                continue
            }

            let entitlement = StoreKitEntitlement(
                productID: transaction.productID,
                expirationDate: transaction.expirationDate
            )
            if Self.isLifetimeProductID(transaction.productID) {
                return entitlement
            }
            let shouldUseSubscription = activeSubscription.map { existing in
                guard let currentExpiration = entitlement.expirationDate else { return false }
                guard let existingExpiration = existing.expirationDate else { return true }
                return currentExpiration > existingExpiration
            } ?? true
            if shouldUseSubscription {
                activeSubscription = entitlement
            }
        }

        return activeSubscription
    }

    private func applyLegacyStoreKitEntitlement(_ entitlement: StoreKitEntitlement) {
        guard !AppDebugFlags.forceNoPremiumAccess else { return }
        let isLifetime = Self.isLifetimeProductID(entitlement.productID)
        let plan = isLifetime ? nil : planKind(for: entitlement.productID)

        activeProductIDs = [entitlement.productID]
        hasLifetimeAccess = isLifetime
        hasActiveAutoRenewable = !isLifetime && plan != nil
        hasPremiumAccess = isLifetime || plan != nil
        autoRenewablePlanKind = plan
        currentPlanKind = isLifetime ? .lifetime : plan
        currentPlanExpirationDate = isLifetime ? nil : entitlement.expirationDate
    }

    private func apply(customerInfo: CustomerInfo, marksRefreshComplete: Bool = true) {
        if AppDebugFlags.forceNoPremiumAccess {
            activeProductIDs = []
            hasLifetimeAccess = false
            hasActiveAutoRenewable = false
            hasPremiumAccess = false
            autoRenewablePlanKind = nil
            currentPlanKind = nil
            currentPlanExpirationDate = nil
            if marksRefreshComplete { hasCompletedEntitlementRefresh = true }
            return
        }
        let previousHasPremiumAccess = hasPremiumAccess
        let previousProductID = activeProductIDs.first
        let entitlement = customerInfo.entitlements[Self.premiumEntitlementID]
        let productID = entitlement?.isActive == true ? entitlement?.productIdentifier : nil
        let hasLifetime = productID.map(Self.isLifetimeProductID) ?? false
        let autoRenewablePlan = productID.flatMap(planKind(for:))

        activeProductIDs = productID.map { [$0] } ?? []
        hasLifetimeAccess = hasLifetime
        hasActiveAutoRenewable = !hasLifetime && autoRenewablePlan != nil
        hasPremiumAccess = entitlement?.isActive == true
        autoRenewablePlanKind = hasLifetime ? nil : autoRenewablePlan
        currentPlanKind = hasLifetime ? .lifetime : autoRenewablePlan
        currentPlanExpirationDate = hasLifetime ? nil : entitlement?.expirationDate
        if marksRefreshComplete {
            hasCompletedEntitlementRefresh = true
        }
        if previousHasPremiumAccess != hasPremiumAccess || previousProductID != productID {
            DiagnosticLogStore.recordStateChange(
                "subscription.entitlement_transition",
                details: [
                    "active": "\(hasPremiumAccess)",
                    "expiration": entitlement?.expirationDate?.ISO8601Format() ?? "--",
                    "previous_active": "\(previousHasPremiumAccess)",
                    "previous_product_id": previousProductID ?? "--",
                    "product_id": productID ?? "--"
                ]
            )
        }
    }

    func displayPrice(for productID: String) -> String {
        if let product = productsByID[productID] {
            return product.displayPrice
        }
        return priceCatalogState.isLoading
            ? L10n.subscriptionPriceLoading
            : L10n.subscriptionPriceUnavailable
    }

    func price(for productID: String) -> Decimal? {
        if let product = productsByID[productID] {
            return product.price
        }
        return nil
    }

    func currencyCode(for productID: String) -> String? {
        if let product = productsByID[productID] {
            return product.currencyCode
        }
        return nil
    }

    func isReadyToPurchase(productID: String) -> Bool {
        packagesByProductID[productID] != nil
    }

    nonisolated static func revenueCatDisplayPrice(from localizedPriceString: String) -> String {
        localizedPriceString
    }

    nonisolated static func productSnapshot(
        from package: Package,
        storefrontID: String,
        storefrontCountryCode: String
    ) -> PaywallProductSnapshot? {
        let storeProduct = package.storeProduct
        guard let priceSnapshot = revenueCatPriceSnapshot(from: storeProduct) else {
            return nil
        }

        return PaywallProductSnapshot(
            productID: storeProduct.productIdentifier,
            displayPrice: priceSnapshot.displayPrice,
            price: priceSnapshot.price,
            currencyCode: priceSnapshot.currencyCode,
            priceSource: priceSnapshot.source,
            packageIdentifier: package.identifier,
            offeringIdentifier: package.presentedOfferingContext.offeringIdentifier,
            storefrontID: storefrontID,
            storefrontCountryCode: storefrontCountryCode
        )
    }

    nonisolated static func revenueCatPriceSnapshot(
        from storeProduct: StoreProduct
    ) -> PaywallStoreProductPriceSnapshot? {
        let displayPrice = revenueCatDisplayPrice(from: storeProduct.localizedPriceString)
        guard hasUsableDisplayPrice(displayPrice) else {
            return nil
        }

        return PaywallStoreProductPriceSnapshot(
            displayPrice: revenueCatDisplayPrice(from: storeProduct.localizedPriceString),
            price: storeProduct.price,
            currencyCode: storeProduct.currencyCode?.uppercased() ?? "--",
            source: "revenuecat_store_product"
        )
    }

    nonisolated static func hasUsableDisplayPrice(_ displayPrice: String) -> Bool {
        let trimmed = displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "--"
    }

    nonisolated private static func normalizedCurrencyCode(_ currencyCode: String?) -> String? {
        guard let currencyCode else { return nil }
        let normalized = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty || normalized == "--" ? nil : normalized
    }

    nonisolated private static func expectedCurrencyCode(
        forStorefrontCountryCode storefrontCountryCode: String
    ) -> String? {
        switch storefrontCountryCode.uppercased() {
        case "TWN": return "TWD"
        case "USA": return "USD"
        case "CHN": return "CNY"
        case "HKG": return "HKD"
        default: return nil
        }
    }

    nonisolated static func isRevenueCatConfigurationAllowed() -> Bool {
        true
    }

    nonisolated static func didStorefrontChange(
        previousStorefrontID: String,
        currentStorefrontID: String
    ) -> Bool {
        !previousStorefrontID.isEmpty
            && previousStorefrontID != "--"
            && previousStorefrontID != currentStorefrontID
    }

    var hasLoadedAllPaywallProducts: Bool {
        hasDisplayPrices(for: Self.allProductIDs)
    }

    func hasDisplayPrices(for productIDs: [String]) -> Bool {
        productIDs.allSatisfy { productID in
            productsByID[productID] != nil
        }
    }

    func warmupProductsForPaywall(
        requiredProductIDs: [String]? = nil,
        maxAttempts: Int = 3
    ) async {
        let requiredProductIDs = requiredProductIDs ?? Self.allProductIDs
        for attempt in 0..<maxAttempts {
            await refreshAll()
            if hasDisplayPrices(for: requiredProductIDs) { return }
            if attempt < (maxAttempts - 1) {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    func purchase(
        productID: String,
        analyticsSource: String? = nil,
        analyticsPlan: String? = nil
    ) async -> SubscriptionPurchaseOutcome {
        await bootstrap()
        if isPurchasing {
            return .inProgress
        }

        isPurchasing = true
        defer { isPurchasing = false }

        if packagesByProductID[productID] == nil {
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

        guard let package = packagesByProductID[productID] else {
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
            return .productUnavailable
        }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            apply(customerInfo: result.customerInfo)
            let activated = result.customerInfo.entitlements[Self.premiumEntitlementID]?.isActive == true
            let outcome = Self.purchaseOutcome(
                userCancelled: result.userCancelled,
                hasActivePremiumEntitlement: activated
            )
            if outcome.completedPurchase {
                lastCompletedPurchaseTransactionID = result.transaction?.transactionIdentifier
            }
            if let analyticsSource, let analyticsPlan {
                if outcome.completedPurchase {
                    AnalyticsService.logPremiumFeaturePurchaseSuccess(
                        source: analyticsSource,
                        plan: analyticsPlan,
                        productID: productID,
                        transactionID: result.transaction?.transactionIdentifier,
                        purchaseAttemptID: purchaseAttribution?.attemptID,
                        attributionAgeSeconds: purchaseAttribution?.ageSeconds,
                        value: price(for: productID).map { NSDecimalNumber(decimal: $0).doubleValue },
                        currency: currencyCode(for: productID)
                    )
                }
                AnalyticsService.logPremiumPurchaseResult(
                    source: analyticsSource,
                    plan: analyticsPlan,
                    productID: productID,
                    result: outcome.analyticsResult,
                    purchaseAttemptID: purchaseAttribution?.attemptID,
                    attributionAgeSeconds: purchaseAttribution?.ageSeconds
                )
            }
            clearPurchaseAttribution(purchaseAttribution)
            DiagnosticLogStore.recordStateChange(
                "subscription.purchase_result",
                details: [
                    "activated": "\(activated)",
                    "product_id": productID,
                    "result": outcome.analyticsResult,
                    "transaction_id": result.transaction?.transactionIdentifier ?? "--",
                    "transaction_product_id": result.transaction?.productIdentifier ?? "--",
                    "user_cancelled": "\(result.userCancelled)"
                ]
            )
            return outcome
        } catch {
            let outcome: SubscriptionPurchaseOutcome = (error as PublicError).asErrorCode == .purchaseCancelledError
                ? .cancelled
                : .failed
            if let analyticsSource, let analyticsPlan {
                AnalyticsService.logPremiumPurchaseResult(
                    source: analyticsSource,
                    plan: analyticsPlan,
                    productID: productID,
                    result: outcome.analyticsResult,
                    purchaseAttemptID: purchaseAttribution?.attemptID,
                    attributionAgeSeconds: purchaseAttribution?.ageSeconds
                )
            }
            clearPurchaseAttribution(purchaseAttribution)
            DiagnosticLogStore.recordStateChange(
                "subscription.purchase_result",
                details: [
                    "product_id": productID,
                    "result": outcome.analyticsResult
                ]
            )
            return outcome
        }
    }

    nonisolated static func purchaseOutcome(
        userCancelled: Bool,
        hasActivePremiumEntitlement: Bool
    ) -> SubscriptionPurchaseOutcome {
        if userCancelled {
            return .cancelled
        }
        return hasActivePremiumEntitlement ? .activated : .pending
    }

    func restorePurchases() async -> String {
        await bootstrap()
        if isPurchasing {
            return L10n.subscriptionPleaseWait
        }

        isPurchasing = true
        defer { isPurchasing = false }
        AnalyticsService.logPremiumRestoreStarted()

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            apply(customerInfo: customerInfo)
            let restored = customerInfo.entitlements[Self.premiumEntitlementID]?.isActive == true
            AnalyticsService.logPremiumRestoreResult(restored ? "restored" : "not_found")
            return restored ? L10n.subscriptionRestoreSucceeded : L10n.subscriptionNotFound
        } catch {
            AnalyticsService.logPremiumRestoreResult("failed")
            return L10n.subscriptionRestoreFailed
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

    private func clearPurchaseAttribution(_ attribution: PurchaseAttribution?) {
        guard let attribution,
              let data = UserDefaults.standard.data(forKey: Self.pendingPurchaseAttributionKey),
              let stored = try? JSONDecoder().decode(PurchaseAttribution.self, from: data),
              stored.attemptID == attribution.attemptID else {
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingPurchaseAttributionKey)
    }

    private func updatePriceCatalogState() {
        guard !productsByID.isEmpty else {
            priceCatalogState = .unavailable
            return
        }

        priceCatalogState = productsByID.count == Self.allProductIDs.count
            ? .ready
            : .partiallyReady
    }

    private func invalidateStorefrontBoundProducts() {
        packagesByProductID = [:]
        productsByID = [:]
        loadedProductIDs = []
        missingProductIDs = Self.allProductIDs
        priceCatalogState = .loading
    }
}
