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
    @Published private(set) var accountState = BlindBoxAccountState()
    @Published private(set) var lastMaintenanceResult: BlindBoxAccountMaintenanceResult?

    let themes: [BlindBoxThemeDefinition]

    private let bootstrapper: BlindBoxCloudKitAccountBootstrapper
    private let accountRepository: BlindBoxCloudKitAccountStateRepository
    private let drawRepository: BlindBoxCloudKitDrawRepository
    private let pointExchangeRepository: BlindBoxCloudKitPointExchangeRepository
    private let legacyInventoryProvider: () -> [String: Int]

    convenience init(
        themes: [BlindBoxThemeDefinition] = BlindBoxCatalog.builtInThemes,
        legacyInventoryProvider: @escaping () -> [String: Int] = {
            BlindBoxLegacyInventoryReader.loadInventoryCounts()
        }
    ) {
        let database = BlindBoxCloudKitDatabase(
            database: CKContainer(
                identifier: NativeICloudConfiguration.containerIdentifier
            ).privateCloudDatabase
        )
        self.init(
            themes: themes,
            database: database,
            legacyInventoryProvider: legacyInventoryProvider
        )
    }

    init(
        themes: [BlindBoxThemeDefinition],
        database: any BlindBoxCloudRecordDatabase,
        legacyInventoryProvider: @escaping () -> [String: Int]
    ) {
        self.themes = themes
        self.bootstrapper = BlindBoxCloudKitAccountBootstrapper(database: database)
        self.accountRepository = BlindBoxCloudKitAccountStateRepository(database: database)
        self.drawRepository = BlindBoxCloudKitDrawRepository(database: database)
        self.pointExchangeRepository = BlindBoxCloudKitPointExchangeRepository(database: database)
        self.legacyInventoryProvider = legacyInventoryProvider
    }

    func theme(for id: BlindBoxThemeID) -> BlindBoxThemeDefinition? {
        themes.first(where: { $0.id == id })
    }

    func candidates(hasPremiumAccess: Bool) -> [BlindBoxCandidateBatch] {
        Array(accountState.candidateBatches.prefix(
            BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: hasPremiumAccess)
        ))
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

        availability = .loading
        do {
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
                    themes: themes,
                    hasPremiumAccess: hasPremiumAccess,
                    candidateZoneWasPresented: candidateZoneWasPresented,
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

    func open(
        _ request: BlindBoxDrawRequest,
        hasPremiumAccess: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> BlindBoxOpenResult {
        guard availability == .ready else {
            throw BlindBoxFeatureStoreError.accountUnavailable
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
                    themes: themes,
                    hasPremiumAccess: hasPremiumAccess,
                    candidateZoneWasPresented: false,
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

    /// Reserves the one-per-grant-day exchange in the private account first,
    /// writes the matching 100-point entry to the app's existing point ledger,
    /// then atomically releases the reserved ticket. If the app is interrupted
    /// after the reservation, `refresh` completes the same request rather than
    /// allowing a second charge or a duplicate ticket.
    func exchangePointsForOneTicket(
        availablePoints: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> BlindBoxPointExchangeResult {
        guard availability == .ready else {
            throw BlindBoxFeatureStoreError.accountUnavailable
        }

        let request = BlindBoxPointExchangeRequest(requestedAt: now)
        _ = try await pointExchangeRepository.begin(
            request,
            availablePoints: availablePoints,
            calendar: calendar
        )
        try persistPointExchangeLedger(for: request)
        let result = try await pointExchangeRepository.complete(request, completedAt: now)
        accountState = try await accountRepository.loadAccount().accountState
        return result
    }

    private func recoverPendingPointExchangeIfNeeded() async throws {
        guard let pendingExchange = try await pointExchangeRepository.pendingExchange() else {
            return
        }
        try persistPointExchangeLedger(for: pendingExchange.request)
        _ = try await pointExchangeRepository.complete(
            pendingExchange.request,
            completedAt: .now
        )
    }

    private func persistPointExchangeLedger(
        for request: BlindBoxPointExchangeRequest
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
                points: BlindBoxRuleConfiguration.pointExchangePrice,
                redeemedAt: request.requestedAt,
                imageName: "BlindBoxTicketIcon",
                itemReferenceID: referenceID
            )
        ) != nil else {
            throw BlindBoxFeatureStoreError.pointLedgerWriteFailed
        }
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
    case pointLedgerWriteFailed
}
