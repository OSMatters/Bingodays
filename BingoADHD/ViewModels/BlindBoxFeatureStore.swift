import CloudKit
import Combine
import Foundation

/// The production-facing Blind Box state owned by the app UI. It intentionally
/// does not own the legacy point wallet: the cross-store point-exchange saga is
/// introduced separately so this store cannot accidentally deduct real points.
@MainActor
final class BlindBoxFeatureStore: ObservableObject {
    enum Availability: Equatable {
        case idle
        case loading
        case ready
        case waitingForICloudInitialImport
        case requiresMigrationReview(unmappedLegacyStickerIDs: [String])
        case failed(message: String)
    }

    @Published private(set) var availability: Availability = .idle
    @Published private(set) var accountState = BlindBoxAccountState.newAccount()
    @Published private(set) var lastMaintenanceResult: BlindBoxAccountMaintenanceResult?

    @Published private(set) var themes: [BlindBoxThemeDefinition]
    @Published private(set) var economyConfiguration: BlindBoxEconomyConfiguration

    private let bootstrapper: BlindBoxCloudKitAccountBootstrapper
    private let accountRepository: BlindBoxCloudKitAccountStateRepository
    private let drawRepository: BlindBoxCloudKitDrawRepository
    private let pointExchangeRepository: BlindBoxCloudKitPointExchangeRepository
    private let legacyInventoryProvider: () -> [String: Int]
    private let catalogRepository: (any BlindBoxCatalogBundleFetching)?
    private let catalogCurrentBuild: Int
    private let catalogCacheRootDirectory: URL?
    private var activeThemeIDs: Set<BlindBoxThemeID>

    convenience init(
        themes: [BlindBoxThemeDefinition] = BlindBoxCatalog.builtInThemes,
        legacyInventoryProvider: @escaping () -> [String: Int] = {
            BlindBoxLegacyInventoryReader.loadInventoryCounts()
        }
    ) {
        let currentBuild = Int(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ) ?? 0
        let cachedRelease = BlindBoxCatalogBundleCache.load(currentBuild: currentBuild)?.release
        let catalogThemes = cachedRelease?.themes ?? themes
        let addsZodiac = !catalogThemes.contains(where: { $0.id == BlindBoxCatalog.zodiac.id })
        let database = BlindBoxCloudKitDatabase(
            database: CKContainer(
                identifier: NativeICloudConfiguration.containerIdentifier
            ).privateCloudDatabase
        )
        self.init(
            themes: catalogThemes + (addsZodiac ? [BlindBoxCatalog.zodiac] : []),
            activeThemeIDs: cachedRelease.map { $0.activeThemeIDs + (addsZodiac ? [BlindBoxCatalog.zodiac.id] : []) },
            economyConfiguration: cachedRelease?.economyConfiguration ?? .defaultValue,
            database: database,
            legacyInventoryProvider: legacyInventoryProvider,
            catalogRepository: BlindBoxCloudKitCatalogRepository(),
            catalogCurrentBuild: currentBuild
        )
    }

    init(
        themes: [BlindBoxThemeDefinition],
        activeThemeIDs: [BlindBoxThemeID]? = nil,
        economyConfiguration: BlindBoxEconomyConfiguration = .defaultValue,
        database: any BlindBoxCloudRecordDatabase,
        legacyInventoryProvider: @escaping () -> [String: Int],
        catalogRepository: (any BlindBoxCatalogBundleFetching)? = nil,
        catalogCurrentBuild: Int = 0,
        catalogCacheRootDirectory: URL? = nil
    ) {
        self.themes = themes
        self.activeThemeIDs = Set(activeThemeIDs ?? themes.map(\.id))
        self.economyConfiguration = economyConfiguration
        self.bootstrapper = BlindBoxCloudKitAccountBootstrapper(database: database)
        self.accountRepository = BlindBoxCloudKitAccountStateRepository(database: database)
        self.drawRepository = BlindBoxCloudKitDrawRepository(database: database)
        self.pointExchangeRepository = BlindBoxCloudKitPointExchangeRepository(database: database)
        self.legacyInventoryProvider = legacyInventoryProvider
        self.catalogRepository = catalogRepository
        self.catalogCurrentBuild = catalogCurrentBuild
        self.catalogCacheRootDirectory = catalogCacheRootDirectory
    }

    func theme(for id: BlindBoxThemeID) -> BlindBoxThemeDefinition? {
        themes.first(where: { $0.id == id })
    }

    func candidates(hasPremiumAccess: Bool) -> [BlindBoxCandidateBatch] {
        Array(accountState.candidateBatches.prefix(
            BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: hasPremiumAccess)
        ))
    }

    /// Retired themes remain visible in My Box, but only active themes define
    /// whether the candidate shelf has reached its current completion state.
    var hasCollectedEveryActiveTheme: Bool {
        guard !candidateThemes.isEmpty else { return false }
        return candidateThemes.allSatisfy {
            BlindBoxCandidateCoordinator.isThemeComplete(
                $0,
                ownedStickerCounts: accountState.ownedStickerCounts
            )
        }
    }

    /// Call only after the app's Native iCloud coordinator has finished its
    /// initial primary import. The store does no CloudKit work while waiting,
    /// which protects old sticker ownership from a stale local cache.
    func refresh(
        hasPremiumAccess: Bool,
        candidateZoneWasPresented: Bool,
        nativeICloudInitialImportComplete: Bool,
        now: Date = .now,
        calendar: Calendar = .current,
        reason: BlindBoxCandidateRefreshReason = .initialLoad
    ) async {
        guard nativeICloudInitialImportComplete else {
            availability = .waitingForICloudInitialImport
            return
        }

        if availability != .ready { availability = .loading }
        do {
            await refreshRemoteCatalogIfAvailable()

            let bootstrapResult = try await bootstrapper.bootstrap(
                legacyInventoryCounts: legacyInventoryProvider()
            )
            if case let .requiresManualReview(unmappedLegacyStickerIDs) = bootstrapResult {
                availability = .requiresMigrationReview(
                    unmappedLegacyStickerIDs: unmappedLegacyStickerIDs
                )
                return
            }

            try await recoverPendingPointExchangeIfNeeded()

            lastMaintenanceResult = try await accountRepository.maintain(
                BlindBoxCloudMaintenanceRequest(
                    themes: candidateThemes,
                    hasPremiumAccess: hasPremiumAccess,
                    candidateZoneWasPresented: candidateZoneWasPresented,
                    isAutomaticOpeningEnabled: economyConfiguration.isBlindBoxOpeningEnabled,
                    now: now,
                    calendar: calendar,
                    reason: reason
                )
            )
            accountState = try await accountRepository.loadAccount().accountState
            availability = .ready
        } catch {
            availability = .failed(message: Self.message(for: error))
        }
    }

    func consumeTicketReceipt() async throws -> BlindBoxTicketReceipt? {
        guard let receipt = accountState.pendingTicketReceipt else { return nil }
        let consumed = try await accountRepository.acknowledgeTicketReceipt(receipt.id)
        if accountState.pendingTicketReceipt?.id == receipt.id {
            accountState.pendingTicketReceipt = nil
        }
        return consumed ? receipt : nil
    }

    func open(
        _ request: BlindBoxDrawRequest,
        hasPremiumAccess: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> BlindBoxOpenResult {
        guard availability == .ready else {
            throw BlindBoxFeatureStoreError.accountUnavailable
        }
        guard await refreshRemoteCatalogIfAvailable() else {
            throw BlindBoxFeatureStoreError.remoteCatalogUnavailable
        }
        guard economyConfiguration.isBlindBoxOpeningEnabled else {
            throw BlindBoxFeatureStoreError.openingPaused
        }

        let result = try await drawRepository.open(request)
        // A completed theme changes its candidate eligibility immediately. Run
        // that reconciliation behind the authoritative draw, rather than
        // relying on a later lobby refresh that a user might never reach.
        // Reconciliation is intentionally best-effort here: the immutable draw
        // result must still be shown if a follow-up maintenance request has a
        // transient CloudKit failure.
        do {
            lastMaintenanceResult = try await accountRepository.maintain(
                BlindBoxCloudMaintenanceRequest(
                    themes: candidateThemes,
                    hasPremiumAccess: hasPremiumAccess,
                    candidateZoneWasPresented: false,
                    isAutomaticOpeningEnabled: economyConfiguration.isBlindBoxOpeningEnabled,
                    now: now,
                    calendar: calendar,
                    reason: .themeCompleted
                )
            )
        } catch {
            // The next online refresh retries this safe, idempotent pass.
        }
        if let refreshedAccount = try? await accountRepository.loadAccount() {
            accountState = refreshedAccount.accountState
        }
        return result
    }

    /// A reveal is acknowledged only after the user leaves its result screen.
    /// This is intentionally separate from `open`: the paid result remains
    /// recoverable across an interruption until the user has had a chance to
    /// see it.
    func acknowledgePendingReveal(_ pendingReveal: BlindBoxPendingReveal) async throws {
        guard availability == .ready else {
            throw BlindBoxFeatureStoreError.accountUnavailable
        }
        let didAcknowledge = try await accountRepository.acknowledgePendingReveal(
            idempotencyKey: pendingReveal.drawIdempotencyKey
        )
        accountState = try await accountRepository.loadAccount().accountState
        guard didAcknowledge else {
            throw BlindBoxFeatureStoreError.pendingRevealChanged
        }
    }

    /// Reserves the configured one-per-grant-day exchange in the private
    /// account first, snapshots its point cost, writes that amount to the
    /// app's existing point ledger, then releases the reserved ticket. If the
    /// app is interrupted after the reservation, `refresh` completes the same
    /// request rather than allowing a second charge or a duplicate ticket.
    func exchangePointsForOneTicket(
        availablePoints: Int,
        expectedEconomyConfigurationVersion: Int? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> BlindBoxPointExchangeResult {
        guard availability == .ready else {
            throw BlindBoxFeatureStoreError.accountUnavailable
        }

        guard await refreshRemoteCatalogIfAvailable() else {
            throw BlindBoxFeatureStoreError.remoteCatalogUnavailable
        }
        if let expectedEconomyConfigurationVersion,
           economyConfiguration.version != expectedEconomyConfigurationVersion {
            throw BlindBoxFeatureStoreError.pointExchangeConfigurationChanged
        }
        guard economyConfiguration.isPointExchangeEnabled else {
            throw BlindBoxFeatureStoreError.pointExchangeDisabled
        }

        let request = BlindBoxPointExchangeRequest(
            requestedAt: now,
            economyConfigurationVersion: economyConfiguration.version
        )
        let exchange = try await pointExchangeRepository.begin(
            request,
            availablePoints: availablePoints,
            calendar: calendar,
            economyConfiguration: economyConfiguration
        )
        try persistPointExchangeLedger(
            for: request,
            deductedPoints: exchange.reservation.deductedPoints
        )
        let result = try await pointExchangeRepository.complete(request, completedAt: now)
        accountState = try await accountRepository.loadAccount().accountState
        return result
    }

    private func recoverPendingPointExchangeIfNeeded() async throws {
        guard let pendingExchange = try await pointExchangeRepository.pendingExchange() else {
            return
        }
        try persistPointExchangeLedger(
            for: pendingExchange.request,
            deductedPoints: pendingExchange.reservation.deductedPoints
        )
        _ = try await pointExchangeRepository.complete(
            pendingExchange.request,
            completedAt: .now
        )
    }

    private func persistPointExchangeLedger(
        for request: BlindBoxPointExchangeRequest,
        deductedPoints: Int
    ) throws {
        let referenceID = PointRedemptionRecord.blindBoxTicketReferenceID(request.idempotencyKey)
        if PointRedemptionHistoryStore.load().contains(where: {
            $0.isActive && $0.itemReferenceID == referenceID
        }) {
            return
        }

        guard PointRedemptionHistoryStore.append(
            PointRedemptionRecord(
                itemKind: .blindBoxTicket,
                title: "Blind Box Ticket",
                points: deductedPoints,
                redeemedAt: request.requestedAt,
                emoji: "🎟️",
                itemReferenceID: referenceID
            )
        ) != nil else {
            throw BlindBoxFeatureStoreError.pointLedgerWriteFailed
        }
    }

    private var candidateThemes: [BlindBoxThemeDefinition] {
        themes.filter { activeThemeIDs.contains($0.id) }
    }

    /// Refreshes the remote release when one is configured. Ordinary screen
    /// refreshes can continue from a good cache when this fails, while the
    /// two value-changing actions require a `true` result before proceeding.
    /// That fail-closed transaction boundary prevents an old cached price or
    /// switch from being used after a publisher changes the catalog.
    @discardableResult
    private func refreshRemoteCatalogIfAvailable() async -> Bool {
        guard let catalogRepository else {
            return true
        }
        guard let bundle = try? await catalogRepository.fetchLatestBundle() else {
            return false
        }

        let installResult: BlindBoxCatalogBundleCacheInstallResult
        if let catalogCacheRootDirectory {
            installResult = BlindBoxCatalogBundleCache.install(
                bundle,
                currentBuild: catalogCurrentBuild,
                rootDirectory: catalogCacheRootDirectory
            )
        } else {
            installResult = BlindBoxCatalogBundleCache.install(
                bundle,
                currentBuild: catalogCurrentBuild
            )
        }

        guard installResult == .installed else { return false }
        let cachedEntry: BlindBoxCatalogBundleCache.Entry?
        if let catalogCacheRootDirectory {
            cachedEntry = BlindBoxCatalogBundleCache.load(
                currentBuild: catalogCurrentBuild,
                rootDirectory: catalogCacheRootDirectory
            )
        } else {
            cachedEntry = BlindBoxCatalogBundleCache.load(currentBuild: catalogCurrentBuild)
        }
        guard let cachedEntry else { return false }

        themes = cachedEntry.release.themes
        activeThemeIDs = Set(cachedEntry.release.activeThemeIDs)
        // Older remote releases predate the bundled Zodiac launch. A release
        // that explicitly includes Zodiac retains control of its active state.
        if !themes.contains(where: { $0.id == BlindBoxCatalog.zodiac.id }) {
            themes.append(BlindBoxCatalog.zodiac)
            activeThemeIDs.insert(BlindBoxCatalog.zodiac.id)
        }
        economyConfiguration = cachedEntry.release.economyConfiguration
        if catalogCacheRootDirectory == nil {
            BlindBoxCatalogArtworkStore.shared.reload()
        }
        return true
    }

    private static func message(for error: any Error) -> String {
        switch error as? BlindBoxCloudKitRepositoryError {
        case .accountNotInitialized:
            return "Your Blind Box account is not ready yet."
        case .contentionRetryLimitReached:
            return "Your Blind Box account changed on another device. Please try again."
        case .incompleteCloudKitResponse:
            return "Your Blind Box account could not be verified. Please try again."
        case nil:
            return "Unable to sync Blind Box right now. Please try again."
        }
    }
}

enum BlindBoxFeatureStoreError: Error, Equatable {
    case accountUnavailable
    case remoteCatalogUnavailable
    case pendingRevealChanged
    case openingPaused
    case pointExchangeDisabled
    case pointExchangeConfigurationChanged
    case pointLedgerWriteFailed
}
