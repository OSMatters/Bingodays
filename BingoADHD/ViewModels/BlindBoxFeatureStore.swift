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
    private let localRepository: BlindBoxLocalAccountRepository
    private let legacyInventoryProvider: () -> [String: Int]
    private let catalogRepository: (any BlindBoxCatalogBundleFetching)?
    private let catalogCurrentBuild: Int
    private let catalogCacheRootDirectory: URL?
    private let cloudAccountIdentifierProvider: (@MainActor () async -> String?)?
    private var activeThemeIDs: Set<BlindBoxThemeID>
    private var isCloudSynchronizationInFlight = false

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
        let container = CKContainer(identifier: NativeICloudConfiguration.containerIdentifier)
        let database = BlindBoxCloudKitDatabase(database: container.privateCloudDatabase)
        self.init(
            themes: catalogThemes,
            activeThemeIDs: cachedRelease?.activeThemeIDs,
            economyConfiguration: cachedRelease?.economyConfiguration ?? .defaultValue,
            database: database,
            legacyInventoryProvider: legacyInventoryProvider,
            catalogRepository: BlindBoxCloudKitCatalogRepository(),
            catalogCurrentBuild: currentBuild,
            localDefaults: .standard,
            cloudAccountIdentifierProvider: {
                guard (try? await container.accountStatus()) == .available else { return nil }
                return try? await container.userRecordID().recordName
            }
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
        catalogCacheRootDirectory: URL? = nil,
        localDefaults: UserDefaults = .standard,
        cloudAccountIdentifierProvider: (@MainActor () async -> String?)? = nil
    ) {
        self.themes = themes
        self.activeThemeIDs = Set(activeThemeIDs ?? themes.map(\.id))
        self.economyConfiguration = economyConfiguration
        self.bootstrapper = BlindBoxCloudKitAccountBootstrapper(database: database)
        self.accountRepository = BlindBoxCloudKitAccountStateRepository(database: database)
        self.localRepository = BlindBoxLocalAccountRepository(defaults: localDefaults)
        self.legacyInventoryProvider = legacyInventoryProvider
        self.catalogRepository = catalogRepository
        self.catalogCurrentBuild = catalogCurrentBuild
        self.catalogCacheRootDirectory = catalogCacheRootDirectory
        self.cloudAccountIdentifierProvider = cloudAccountIdentifierProvider
        includeBundledLaunchThemesIfMissing()
    }

    func theme(for id: BlindBoxThemeID) -> BlindBoxThemeDefinition? {
        themes.first(where: { $0.id == id })
    }

    var stickerShelfItems: [BlindBoxStickerShelfItem] {
        BlindBoxStickerShelfBuilder.items(themes: themes, state: accountState)
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

    /// Refreshes immediately from the device-local account. `nativeICloud…`
    /// remains an input for source compatibility with the host screen, but it
    /// must never gate a Blind Box action: Core Data import is unrelated to
    /// the local Blind Box transaction journal.
    func refresh(
        hasPremiumAccess: Bool,
        candidateZoneWasPresented: Bool,
        nativeICloudInitialImportComplete: Bool,
        premiumPurchaseTransactionID: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current,
        reason: BlindBoxCandidateRefreshReason = .initialLoad
    ) async {
        _ = nativeICloudInitialImportComplete
        if availability != .ready { availability = .loading }
        do {
            // A release fetch is useful, but it never belongs on the critical
            // path to a locally usable account. Keep the bundled/cache catalog
            // for this refresh and update a later presentation if the fetch
            // eventually succeeds.
            refreshRemoteCatalogInBackground()

            switch localRepository.migrateLegacyInventoryIfNeeded(
                legacyInventoryCounts: legacyInventoryProvider()
            ) {
            case .requiresManualReview:
                // An obsolete/unknown legacy sticker must not lock users out
                // of the new game. Known local Blind Box data stays intact and
                // this isolated migration can be reviewed separately.
                break
            case .persistenceFailed:
                throw BlindBoxLocalStateStoreError.persistenceFailed
            case .applied, .alreadyApplied:
                break
            }

            try recoverPendingPointExchangeIfNeeded()
            lastMaintenanceResult = try localRepository.maintain(
                themes: candidateThemes,
                hasPremiumAccess: hasPremiumAccess,
                candidateZoneWasPresented: candidateZoneWasPresented,
                isAutomaticOpeningEnabled: economyConfiguration.isBlindBoxOpeningEnabled,
                premiumPurchaseTransactionID: premiumPurchaseTransactionID,
                now: now,
                calendar: calendar,
                reason: reason
            )
            accountState = localRepository.accountState
            availability = .ready
            scheduleCloudSynchronization()
        } catch {
            availability = .failed(message: Self.message(for: error))
        }
    }

    func consumeTicketReceipt() async throws -> BlindBoxTicketReceipt? {
        let receipt = try localRepository.consumeTicketReceipt()
        accountState = localRepository.accountState
        scheduleCloudSynchronization()
        return receipt
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
        guard economyConfiguration.isBlindBoxOpeningEnabled else {
            throw BlindBoxFeatureStoreError.openingPaused
        }

        let result = try localRepository.open(request, now: now)
        // A completed theme changes its candidate eligibility immediately. Run
        // that reconciliation behind the authoritative draw, rather than
        // relying on a later lobby refresh that a user might never reach.
        // Reconciliation is intentionally best-effort here: the immutable draw
        // result must still be shown if a follow-up maintenance request has a
        // transient CloudKit failure.
        do {
            lastMaintenanceResult = try localRepository.maintain(
                themes: candidateThemes,
                hasPremiumAccess: hasPremiumAccess,
                candidateZoneWasPresented: false,
                isAutomaticOpeningEnabled: economyConfiguration.isBlindBoxOpeningEnabled,
                premiumPurchaseTransactionID: nil,
                now: now,
                calendar: calendar,
                reason: .themeCompleted
            )
        } catch {
            // The next online refresh retries this safe, idempotent pass.
        }
        accountState = localRepository.accountState
        scheduleCloudSynchronization()
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
        let didAcknowledge = try localRepository.acknowledgePendingReveal(pendingReveal)
        accountState = localRepository.accountState
        scheduleCloudSynchronization()
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
        let reservation = try localRepository.reservePointExchange(
            request: request,
            availablePoints: availablePoints,
            calendar: calendar,
            economyConfiguration: economyConfiguration
        )
        try persistPointExchangeLedger(
            for: request,
            deductedPoints: reservation.deductedPoints
        )
        let result = try localRepository.completePointExchange(idempotencyKey: request.idempotencyKey)
        accountState = localRepository.accountState
        scheduleCloudSynchronization()
        return result
    }

    private func recoverPendingPointExchangeIfNeeded() throws {
        guard let pendingExchange = localRepository.accountState.pendingPointExchange else {
            return
        }
        try persistPointExchangeLedger(
            for: BlindBoxPointExchangeRequest(
                idempotencyKey: pendingExchange.idempotencyKey,
                requestedAt: pendingExchange.reservedAt,
                economyConfigurationVersion: economyConfiguration.version
            ),
            deductedPoints: pendingExchange.deductedPoints
        )
        _ = try localRepository.completePointExchange(idempotencyKey: pendingExchange.idempotencyKey)
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

    /// Refreshes the remote release when one is configured. A bundled or
    /// verified cached catalog is always sufficient for local transactions;
    /// network refresh merely improves the next presentation.
    @discardableResult
    private func refreshRemoteCatalogIfAvailable() async -> Bool {
        guard let catalogRepository else {
            return true
        }
        guard let bundle = try? await catalogRepository.fetchLatestBundle() else {
            return false
        }

        if let cachedEntry = loadCachedCatalogEntry(),
           BlindBoxCatalogBundleCache.entry(
            cachedEntry,
            matches: bundle,
            currentBuild: catalogCurrentBuild
           ) {
            applyCatalog(cachedEntry, reloadArtwork: false)
            return true
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
        let cachedEntry = loadCachedCatalogEntry()
        guard let cachedEntry else { return false }

        applyCatalog(cachedEntry, reloadArtwork: true)
        return true
    }

    private func refreshRemoteCatalogInBackground() {
        guard catalogRepository != nil else { return }
        Task { [weak self] in
            _ = await self?.refreshRemoteCatalogIfAvailable()
        }
    }

    private func loadCachedCatalogEntry() -> BlindBoxCatalogBundleCache.Entry? {
        if let catalogCacheRootDirectory {
            BlindBoxCatalogBundleCache.load(
                currentBuild: catalogCurrentBuild,
                rootDirectory: catalogCacheRootDirectory
            )
        } else {
            BlindBoxCatalogBundleCache.load(currentBuild: catalogCurrentBuild)
        }
    }

    private func applyCatalog(
        _ cachedEntry: BlindBoxCatalogBundleCache.Entry,
        reloadArtwork: Bool
    ) {
        themes = cachedEntry.release.themes
        activeThemeIDs = Set(cachedEntry.release.activeThemeIDs)
        includeBundledLaunchThemesIfMissing()
        economyConfiguration = cachedEntry.release.economyConfiguration
        if reloadArtwork, catalogCacheRootDirectory == nil {
            BlindBoxCatalogArtworkStore.shared.reload()
        }
    }

    private func includeBundledLaunchThemesIfMissing() {
        // A remote release that includes a launch theme controls its active state.
        for theme in [BlindBoxCatalog.zodiac, BlindBoxCatalog.halloween]
        where !themes.contains(where: { $0.id == theme.id }) {
            themes.append(theme)
            activeThemeIDs.insert(theme.id)
        }
    }

    private static func message(for error: any Error) -> String {
        if error is BlindBoxLocalStateStoreError {
            return "Blind Box data could not be saved on this device. Please free some storage and try again."
        }
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

    /// Mirrors the latest local snapshot without changing the user's current
    /// interaction. A quota/network/iCloud failure is explicitly recoverable:
    /// the local envelope stays marked pending and a later refresh retries it.
    private func scheduleCloudSynchronization() {
        guard localRepository.needsCloudSynchronization,
              !isCloudSynchronizationInFlight else { return }
        Task { [weak self] in
            await self?.synchronizeCloudIfPossible()
        }
    }

    private func synchronizeCloudIfPossible() async {
        guard !isCloudSynchronizationInFlight,
              localRepository.needsCloudSynchronization else { return }
        isCloudSynchronizationInFlight = true
        defer { isCloudSynchronizationInFlight = false }

        do {
            if let cloudAccountIdentifier = await cloudAccountIdentifierProvider?() {
                accountState = try localRepository.activateCloudAccount(
                    identifier: cloudAccountIdentifier
                )
            }
            // The local migration has already happened. Supplying an empty
            // legacy inventory prevents CloudKit bootstrap from becoming a
            // prerequisite for, or a second source of, device-local progress.
            let bootstrap = try await bootstrapper.bootstrap(legacyInventoryCounts: [:])
            if case .requiresManualReview = bootstrap {
                return
            }
            let cloudEnvelope: BlindBoxCloudAccountEnvelope
            let didCreateCloudAccount: Bool
            switch bootstrap {
            case let .created(account):
                cloudEnvelope = account
                didCreateCloudAccount = true
            case let .migratedExisting(account), let .alreadyReady(account):
                cloudEnvelope = account
                didCreateCloudAccount = false
            case .requiresManualReview:
                return
            }

            // Cloud data is a baseline only when binding this device to an
            // existing account. Once a local transaction has completed, the
            // local wallet is authoritative for the next upload; otherwise a
            // stale cloud record could restore spent tickets or an already
            // displayed ticket-receipt popup.
            let stateToMirror: BlindBoxAccountState
            if localRepository.needsCloudBaselineImport,
               (!didCreateCloudAccount || localRepository.accountState.isEmptyCloudAccountShell) {
                stateToMirror = try localRepository.importCloudBaseline(cloudEnvelope.accountState)
            } else {
                stateToMirror = localRepository.accountState
            }
            let mirrored = try await accountRepository.mergeAndSaveLocalAccount(stateToMirror)
            accountState = try localRepository.applyCloudSynchronizedState(mirrored.accountState)
            localRepository.markCloudSynchronizationCompleted(for: accountState)
        } catch {
            // CloudKit is a best-effort mirror. Keep the local state pending so
            // a later refresh can retry without interrupting the user.
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

/// Lightweight shared read model for the Home customization sheet. The full
/// Blind Box flow owns its transaction store; this object only observes the
/// persisted account and avoids creating a second CloudKit transaction owner.
@MainActor
final class HomeBlindBoxStickerShelfStore: ObservableObject {
    @Published private(set) var items: [BlindBoxStickerShelfItem] = []

    private var stateObservation: AnyCancellable?

    init() {
        reload()
        stateObservation = NotificationCenter.default
            .publisher(for: .blindBoxAccountStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // receive(on:) above guarantees synchronous main-actor delivery.
                MainActor.assumeIsolated { self?.reload() }
            }
    }

    func reload() {
        let state: BlindBoxAccountState
        let themes: [BlindBoxThemeDefinition]

        if AppDebugFlags.blindBoxLiveFlowEnabled {
            state = BlindBoxLocalStateStore.load()
            themes = Self.cachedThemes()
        } else {
            let previewStore = BlindBoxPreviewStore(persistence: .standard)
            state = previewStore.state
            themes = previewStore.themes
        }

        items = BlindBoxStickerShelfBuilder.items(themes: themes, state: state)
    }

    private static func cachedThemes() -> [BlindBoxThemeDefinition] {
        let currentBuild = Int(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ) ?? 0
        var themes = BlindBoxCatalogBundleCache.load(currentBuild: currentBuild)?.release.themes
            ?? BlindBoxCatalog.builtInThemes
        for theme in [BlindBoxCatalog.zodiac, BlindBoxCatalog.halloween]
        where !themes.contains(where: { $0.id == theme.id }) {
            themes.append(theme)
        }
        return themes
    }
}
