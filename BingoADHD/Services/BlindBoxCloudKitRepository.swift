import CloudKit
import Foundation

/// The minimum CloudKit surface the draw repository needs. Keeping this seam
/// lets the transaction behavior be exercised without issuing requests to a
/// user's private database.
@MainActor
protocol BlindBoxCloudRecordDatabase: AnyObject {
    func fetchZone(_ zoneID: CKRecordZone.ID) async throws -> CKRecordZone?
    func createZone(_ zoneID: CKRecordZone.ID) async throws
    func fetchRecords(_ recordIDs: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord]
    func saveRecordsAtomically(_ records: [CKRecord]) async throws
}

/// Thin adapter over CloudKit's private database. The adapter turns CloudKit's
/// per-record result dictionaries into all-or-nothing calls so the repository
/// never mistakes a partial fetch or save for a successful blind-box command.
@MainActor
final class BlindBoxCloudKitDatabase: BlindBoxCloudRecordDatabase {
    private let database: CKDatabase

    init(database: CKDatabase) {
        self.database = database
    }

    func fetchZone(_ zoneID: CKRecordZone.ID) async throws -> CKRecordZone? {
        let results = try await database.recordZones(for: [zoneID])
        guard let result = results[zoneID] else {
            throw BlindBoxCloudKitRepositoryError.incompleteCloudKitResponse
        }

        switch result {
        case let .success(zone):
            return zone
        case let .failure(error):
            if Self.isUnknownItem(error) {
                return nil
            }
            throw error
        }
    }

    func createZone(_ zoneID: CKRecordZone.ID) async throws {
        let results = try await database.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)],
            deleting: []
        )
        guard let result = results.saveResults[zoneID] else {
            throw BlindBoxCloudKitRepositoryError.incompleteCloudKitResponse
        }
        _ = try result.get()
    }

    func fetchRecords(_ recordIDs: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        let results = try await database.records(for: recordIDs)
        var fetchedRecords: [CKRecord.ID: CKRecord] = [:]
        fetchedRecords.reserveCapacity(recordIDs.count)

        for recordID in recordIDs {
            guard let result = results[recordID] else {
                throw BlindBoxCloudKitRepositoryError.incompleteCloudKitResponse
            }

            switch result {
            case let .success(record):
                fetchedRecords[recordID] = record
            case let .failure(error):
                if !Self.isUnknownItem(error) {
                    throw error
                }
            }
        }
        return fetchedRecords
    }

    func saveRecordsAtomically(_ records: [CKRecord]) async throws {
        let results = try await database.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        for record in records {
            guard let result = results.saveResults[record.recordID] else {
                throw BlindBoxCloudKitRepositoryError.incompleteCloudKitResponse
            }
            _ = try result.get()
        }
    }

    private static func isUnknownItem(_ error: any Error) -> Bool {
        Self.cloudKitErrorCode(from: error) == .unknownItem
    }

    private static func cloudKitErrorCode(from error: any Error) -> CKError.Code? {
        if let cloudKitError = error as? CKError {
            return cloudKitError.code
        }
        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain else { return nil }
        return CKError.Code(rawValue: nsError.code)
    }
}

enum BlindBoxCloudKitRepositoryError: Error, Equatable {
    /// Account creation is intentionally separate from drawing. A future
    /// bootstrap transaction will only create this after the existing iCloud
    /// data has completed its initial import and legacy inventory is available.
    case accountNotInitialized
    case incompleteCloudKitResponse
    case contentionRetryLimitReached
}

/// Result of the one-time account bootstrap. Callers must obtain
/// `legacyInventoryCounts` only after Native iCloud has completed its initial
/// primary-state import; before then a local device may still be looking at an
/// empty cache rather than the account's actual direct-redemption inventory.
enum BlindBoxCloudAccountBootstrapResult: Equatable {
    case created(account: BlindBoxCloudAccountEnvelope)
    case migratedExisting(account: BlindBoxCloudAccountEnvelope)
    case alreadyReady(account: BlindBoxCloudAccountEnvelope)
    case requiresManualReview(unmappedLegacyStickerIDs: [String])
}

/// Initializes or migrates the private Blind Box account record. This is
/// intentionally separate from `open(_:)`: opening can never create a blank
/// account and accidentally mark a not-yet-imported legacy inventory as done.
@MainActor
final class BlindBoxCloudKitAccountBootstrapper {
    private static let maximumContentionAttempts = 3

    private let database: any BlindBoxCloudRecordDatabase

    init(database: any BlindBoxCloudRecordDatabase) {
        self.database = database
    }

    func bootstrap(
        legacyInventoryCounts: [String: Int]
    ) async throws -> BlindBoxCloudAccountBootstrapResult {
        try await ensureZoneExists()

        for attempt in 0..<Self.maximumContentionAttempts {
            do {
                let records = try await database.fetchRecords([
                    BlindBoxCloudKitRecordCodec.accountRecordID
                ])
                let existingRecord = records[BlindBoxCloudKitRecordCodec.accountRecordID]
                var account = try existingRecord.map(BlindBoxCloudKitRecordCodec.decodeAccountRecord)
                    ?? BlindBoxCloudAccountEnvelope()

                let migration = BlindBoxLegacyStickerMigration.apply(
                    legacyInventoryCounts: legacyInventoryCounts,
                    to: &account.accountState,
                    completedMigrationVersions: &account.completedLegacyMigrationVersions
                )

                switch migration {
                case let .requiresManualReview(unmappedLegacyStickerIDs):
                    return .requiresManualReview(
                        unmappedLegacyStickerIDs: unmappedLegacyStickerIDs
                    )

                case .alreadyApplied:
                    guard existingRecord != nil else {
                        throw BlindBoxCloudKitRepositoryError.incompleteCloudKitResponse
                    }
                    return .alreadyReady(account: account)

                case .applied:
                    let accountRecord: CKRecord
                    if let existingRecord {
                        try BlindBoxCloudKitRecordCodec.updateAccountRecord(
                            existingRecord,
                            with: account
                        )
                        accountRecord = existingRecord
                    } else {
                        accountRecord = try BlindBoxCloudKitRecordCodec.makeAccountRecord(account)
                    }
                    try await database.saveRecordsAtomically([accountRecord])
                    return existingRecord == nil
                        ? .created(account: account)
                        : .migratedExisting(account: account)
                }
            } catch {
                guard Self.isServerRecordChanged(error) else {
                    throw error
                }
                if attempt == Self.maximumContentionAttempts - 1 {
                    throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
                }
            }
        }

        throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
    }

    private func ensureZoneExists() async throws {
        if try await database.fetchZone(BlindBoxCloudKitRecordCodec.zoneID) != nil {
            return
        }

        do {
            try await database.createZone(BlindBoxCloudKitRecordCodec.zoneID)
        } catch {
            if (try? await database.fetchZone(BlindBoxCloudKitRecordCodec.zoneID)) != nil {
                return
            }
            throw error
        }
    }

    private static func isServerRecordChanged(_ error: any Error) -> Bool {
        if let cloudKitError = error as? CKError {
            return cloudKitError.code == .serverRecordChanged
        }
        let nsError = error as NSError
        return nsError.domain == CKErrorDomain
            && nsError.code == CKError.Code.serverRecordChanged.rawValue
    }
}

/// Inputs that are current at the moment the candidate zone is refreshed. They
/// are not persisted because membership, the active catalog, and device time
/// are supplied fresh for each CloudKit maintenance transaction.
struct BlindBoxCloudMaintenanceRequest {
    let themes: [BlindBoxThemeDefinition]
    let hasPremiumAccess: Bool
    let candidateZoneWasPresented: Bool
    let isAutomaticOpeningEnabled: Bool
    let now: Date
    let calendar: Calendar
    let reason: BlindBoxCandidateRefreshReason

    init(
        themes: [BlindBoxThemeDefinition],
        hasPremiumAccess: Bool,
        candidateZoneWasPresented: Bool,
        isAutomaticOpeningEnabled: Bool = true,
        now: Date = .now,
        calendar: Calendar = .current,
        reason: BlindBoxCandidateRefreshReason = .initialLoad
    ) {
        self.themes = themes
        self.hasPremiumAccess = hasPremiumAccess
        self.candidateZoneWasPresented = candidateZoneWasPresented
        self.isAutomaticOpeningEnabled = isAutomaticOpeningEnabled
        self.now = now
        self.calendar = calendar
        self.reason = reason
    }
}

/// CloudKit-backed account reads and time-based maintenance. A pass saves the
/// whole account only when it actually changes, preserving the fetched record's
/// change tag and retrying a concurrent update from fresh state.
@MainActor
final class BlindBoxCloudKitAccountStateRepository {
    private static let maximumContentionAttempts = 3

    private let database: any BlindBoxCloudRecordDatabase

    init(database: any BlindBoxCloudRecordDatabase) {
        self.database = database
    }

    func loadAccount() async throws -> BlindBoxCloudAccountEnvelope {
        guard try await database.fetchZone(BlindBoxCloudKitRecordCodec.zoneID) != nil else {
            throw BlindBoxCloudKitRepositoryError.accountNotInitialized
        }
        let records = try await database.fetchRecords([
            BlindBoxCloudKitRecordCodec.accountRecordID
        ])
        guard let accountRecord = records[BlindBoxCloudKitRecordCodec.accountRecordID] else {
            throw BlindBoxCloudKitRepositoryError.accountNotInitialized
        }
        return try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord)
    }

    func maintain(
        _ request: BlindBoxCloudMaintenanceRequest
    ) async throws -> BlindBoxAccountMaintenanceResult {
        for attempt in 0..<Self.maximumContentionAttempts {
            do {
                guard try await database.fetchZone(BlindBoxCloudKitRecordCodec.zoneID) != nil else {
                    throw BlindBoxCloudKitRepositoryError.accountNotInitialized
                }
                let records = try await database.fetchRecords([
                    BlindBoxCloudKitRecordCodec.accountRecordID
                ])
                guard let accountRecord = records[BlindBoxCloudKitRecordCodec.accountRecordID] else {
                    throw BlindBoxCloudKitRepositoryError.accountNotInitialized
                }
                var account = try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord)
                let originalAccount = account
                var generator = SystemBlindBoxRandomNumberGenerator()
                let result = try BlindBoxAccountMaintenance.apply(
                    state: &account.accountState,
                    themes: request.themes,
                    hasPremiumAccess: request.hasPremiumAccess,
                    candidateZoneWasPresented: request.candidateZoneWasPresented,
                    isAutomaticOpeningEnabled: request.isAutomaticOpeningEnabled,
                    now: request.now,
                    calendar: request.calendar,
                    reason: request.reason,
                    generator: &generator
                )

                guard account != originalAccount else {
                    return result
                }

                try BlindBoxCloudKitRecordCodec.updateAccountRecord(
                    accountRecord,
                    with: account
                )
                try await database.saveRecordsAtomically([accountRecord])
                return result
            } catch {
                guard Self.isServerRecordChanged(error) else {
                    throw error
                }
                if attempt == Self.maximumContentionAttempts - 1 {
                    throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
                }
            }
        }

        throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
    }

    func acknowledgeTicketReceipt(_ id: UUID) async throws -> Bool {
        for attempt in 0..<Self.maximumContentionAttempts {
            do {
                let records = try await database.fetchRecords([BlindBoxCloudKitRecordCodec.accountRecordID])
                guard let record = records[BlindBoxCloudKitRecordCodec.accountRecordID] else {
                    throw BlindBoxCloudKitRepositoryError.accountNotInitialized
                }
                var account = try BlindBoxCloudKitRecordCodec.decodeAccountRecord(record)
                guard account.accountState.pendingTicketReceipt?.id == id else { return false }
                account.accountState.pendingTicketReceipt = nil
                try BlindBoxCloudKitRecordCodec.updateAccountRecord(record, with: account)
                try await database.saveRecordsAtomically([record])
                return true
            } catch {
                guard Self.isServerRecordChanged(error) else { throw error }
                if attempt == Self.maximumContentionAttempts - 1 {
                    throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
                }
            }
        }
        throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
    }

    /// Clears only the reveal that the user has finished viewing. If another
    /// device has already committed a newer reveal, this deliberately leaves
    /// it in place so the older device cannot hide a result it never showed.
    /// A missing pending reveal is an idempotent success: another device may
    /// have already acknowledged the same draw.
    @discardableResult
    func acknowledgePendingReveal(idempotencyKey: UUID) async throws -> Bool {
        for attempt in 0..<Self.maximumContentionAttempts {
            do {
                guard try await database.fetchZone(BlindBoxCloudKitRecordCodec.zoneID) != nil else {
                    throw BlindBoxCloudKitRepositoryError.accountNotInitialized
                }
                let records = try await database.fetchRecords([
                    BlindBoxCloudKitRecordCodec.accountRecordID
                ])
                guard let accountRecord = records[BlindBoxCloudKitRecordCodec.accountRecordID] else {
                    throw BlindBoxCloudKitRepositoryError.accountNotInitialized
                }
                var account = try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord)

                guard let pendingReveal = account.accountState.pendingReveal else {
                    return true
                }
                guard pendingReveal.drawIdempotencyKey == idempotencyKey else {
                    return false
                }

                account.accountState.pendingReveal = nil
                try BlindBoxCloudKitRecordCodec.updateAccountRecord(
                    accountRecord,
                    with: account
                )
                try await database.saveRecordsAtomically([accountRecord])
                return true
            } catch {
                guard Self.isServerRecordChanged(error) else {
                    throw error
                }
                if attempt == Self.maximumContentionAttempts - 1 {
                    throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
                }
            }
        }

        throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
    }

    private static func isServerRecordChanged(_ error: any Error) -> Bool {
        if let cloudKitError = error as? CKError {
            return cloudKitError.code == .serverRecordChanged
        }
        let nsError = error as NSError
        return nsError.domain == CKErrorDomain
            && nsError.code == CKError.Code.serverRecordChanged.rawValue
    }
}

enum BlindBoxCloudPointExchangeRepositoryError: Error, Equatable {
    case idempotencyKeyConflict
    case pendingExchangeRecordMissing
    case unexpectedCompletedExchange
}

/// Owns the private-zone half of the point-to-ticket exchange saga. A begin
/// command reserves the daily allowance and one ticket-capacity slot together
/// with immutable intent evidence. The primary iCloud point ledger is written
/// between `begin` and `complete`; either app termination or a request timeout
/// can safely resume from the same intent on a later online refresh.
@MainActor
final class BlindBoxCloudKitPointExchangeRepository {
    private static let maximumContentionAttempts = 3

    private let database: any BlindBoxCloudRecordDatabase

    init(database: any BlindBoxCloudRecordDatabase) {
        self.database = database
    }

    func begin(
        _ request: BlindBoxPointExchangeRequest,
        availablePoints: Int,
        calendar: Calendar,
        economyConfiguration: BlindBoxEconomyConfiguration = .defaultValue
    ) async throws -> BlindBoxCloudPointExchangeEnvelope {
        let exchangeRecordID = BlindBoxCloudKitRecordCodec.pointExchangeRecordID(
            for: request.idempotencyKey
        )
        let accountRecordID = BlindBoxCloudKitRecordCodec.accountRecordID

        for attempt in 0..<Self.maximumContentionAttempts {
            do {
                let records = try await database.fetchRecords([exchangeRecordID, accountRecordID])
                if let exchangeRecord = records[exchangeRecordID] {
                    let existing = try BlindBoxCloudKitRecordCodec.decodePointExchangeRecord(exchangeRecord)
                    guard existing.request == request else {
                        throw BlindBoxCloudPointExchangeRepositoryError.idempotencyKeyConflict
                    }
                    return existing
                }

                guard let accountRecord = records[accountRecordID] else {
                    throw BlindBoxCloudKitRepositoryError.accountNotInitialized
                }
                var account = try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord)
                let reservation = try BlindBoxWalletStateMachine.reservePointsForOneTicketExchange(
                    state: &account.accountState,
                    idempotencyKey: request.idempotencyKey,
                    availablePoints: availablePoints,
                    now: request.requestedAt,
                    calendar: calendar,
                    economyConfiguration: economyConfiguration
                )
                let exchange = BlindBoxCloudPointExchangeEnvelope(
                    request: request,
                    reservation: reservation,
                    completion: nil,
                    reservedAt: request.requestedAt,
                    completedAt: nil
                )

                try BlindBoxCloudKitRecordCodec.updateAccountRecord(accountRecord, with: account)
                let exchangeRecord = try BlindBoxCloudKitRecordCodec.makePointExchangeRecord(exchange)
                try await database.saveRecordsAtomically([accountRecord, exchangeRecord])
                return exchange
            } catch {
                guard Self.isServerRecordChanged(error) else {
                    throw error
                }
                if attempt == Self.maximumContentionAttempts - 1 {
                    throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
                }
            }
        }

        throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
    }

    func complete(
        _ request: BlindBoxPointExchangeRequest,
        completedAt: Date = .now
    ) async throws -> BlindBoxPointExchangeResult {
        let exchangeRecordID = BlindBoxCloudKitRecordCodec.pointExchangeRecordID(
            for: request.idempotencyKey
        )
        let accountRecordID = BlindBoxCloudKitRecordCodec.accountRecordID

        for attempt in 0..<Self.maximumContentionAttempts {
            do {
                let records = try await database.fetchRecords([exchangeRecordID, accountRecordID])
                guard let exchangeRecord = records[exchangeRecordID] else {
                    throw BlindBoxCloudPointExchangeRepositoryError.pendingExchangeRecordMissing
                }
                var exchange = try BlindBoxCloudKitRecordCodec.decodePointExchangeRecord(exchangeRecord)
                guard exchange.request == request else {
                    throw BlindBoxCloudPointExchangeRepositoryError.idempotencyKeyConflict
                }
                if let completion = exchange.completion {
                    return completion
                }

                guard let accountRecord = records[accountRecordID] else {
                    throw BlindBoxCloudKitRepositoryError.accountNotInitialized
                }
                var account = try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord)
                let completion = try BlindBoxWalletStateMachine.completeReservedPointExchange(
                    state: &account.accountState,
                    idempotencyKey: request.idempotencyKey
                )
                exchange.completion = completion
                exchange.completedAt = completedAt

                try BlindBoxCloudKitRecordCodec.updateAccountRecord(accountRecord, with: account)
                try BlindBoxCloudKitRecordCodec.updatePointExchangeRecord(
                    exchangeRecord,
                    with: exchange
                )
                try await database.saveRecordsAtomically([accountRecord, exchangeRecord])
                return completion
            } catch {
                guard Self.isServerRecordChanged(error) else {
                    throw error
                }
                if attempt == Self.maximumContentionAttempts - 1 {
                    throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
                }
            }
        }

        throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
    }

    func pendingExchange() async throws -> BlindBoxCloudPointExchangeEnvelope? {
        let accountRecordID = BlindBoxCloudKitRecordCodec.accountRecordID
        let accountRecords = try await database.fetchRecords([accountRecordID])
        guard let accountRecord = accountRecords[accountRecordID] else {
            throw BlindBoxCloudKitRepositoryError.accountNotInitialized
        }
        let account = try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord)
        guard let pending = account.accountState.pendingPointExchange else {
            return nil
        }

        let exchangeRecordID = BlindBoxCloudKitRecordCodec.pointExchangeRecordID(
            for: pending.idempotencyKey
        )
        let exchangeRecords = try await database.fetchRecords([exchangeRecordID])
        guard let exchangeRecord = exchangeRecords[exchangeRecordID] else {
            throw BlindBoxCloudPointExchangeRepositoryError.pendingExchangeRecordMissing
        }
        let exchange = try BlindBoxCloudKitRecordCodec.decodePointExchangeRecord(exchangeRecord)
        guard exchange.request.idempotencyKey == pending.idempotencyKey else {
            throw BlindBoxCloudPointExchangeRepositoryError.idempotencyKeyConflict
        }
        return exchange
    }

    private static func isServerRecordChanged(_ error: any Error) -> Bool {
        if let cloudKitError = error as? CKError {
            return cloudKitError.code == .serverRecordChanged
        }
        let nsError = error as NSError
        return nsError.domain == CKErrorDomain &&
            nsError.code == CKError.Code.serverRecordChanged.rawValue
    }
}

/// Pure command planner used by the CloudKit repository. This keeps
/// idempotency behavior deterministic: the existing immutable draw is always
/// returned before attempting another ticket deduction.
enum BlindBoxCloudDrawTransaction {
    enum Decision: Equatable {
        case priorResult(BlindBoxOpenResult)
        case commit(
            account: BlindBoxCloudAccountEnvelope,
            draw: BlindBoxCloudDrawEnvelope
        )
    }

    static func plan(
        request: BlindBoxDrawRequest,
        account: BlindBoxCloudAccountEnvelope,
        existingDraw: BlindBoxCloudDrawEnvelope?,
        committedAt: Date
    ) throws -> Decision {
        if let existingDraw {
            guard existingDraw.request == request else {
                throw BlindBoxDrawRepositoryError.idempotencyKeyConflict
            }
            return .priorResult(existingDraw.result)
        }

        var updatedAccount = account
        if updatedAccount.accountState.pendingReveal != nil {
            throw BlindBoxOpenError.pendingRevealMustBeAcknowledged
        }
        let result: BlindBoxOpenResult
        switch request.mode {
        case .single:
            guard let positionIndex = request.positionIndex else {
                throw BlindBoxDrawRequestValidationError.missingPositionIndex
            }
            result = try BlindBoxStateMachine.openSingle(
                state: &updatedAccount.accountState,
                batchID: request.batchID,
                positionIndex: positionIndex,
                openedAt: committedAt
            )
        case .wholeBox:
            guard request.positionIndex == nil else {
                throw BlindBoxDrawRequestValidationError.unexpectedPositionIndex
            }
            result = try BlindBoxStateMachine.openWholeBox(
                state: &updatedAccount.accountState,
                batchID: request.batchID,
                openedAt: committedAt
            )
        }

        updatedAccount.accountState.pendingReveal = BlindBoxPendingReveal(
            drawIdempotencyKey: request.idempotencyKey,
            result: result
        )

        return .commit(
            account: updatedAccount,
            draw: BlindBoxCloudDrawEnvelope(
                request: request,
                result: result,
                committedAt: committedAt
            )
        )
    }
}

/// Authoritative private-zone draw repository. It is deliberately not wired to
/// the UI yet: release integration must first provide an account bootstrap
/// transaction that waits for Native iCloud's initial import and performs the
/// legacy inventory migration atomically.
@MainActor
final class BlindBoxCloudKitDrawRepository: BlindBoxDrawRepository {
    private static let maximumContentionAttempts = 3

    private let database: any BlindBoxCloudRecordDatabase
    private let now: () -> Date

    convenience init(
        container: CKContainer = CKContainer(
            identifier: NativeICloudConfiguration.containerIdentifier
        ),
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            database: BlindBoxCloudKitDatabase(database: container.privateCloudDatabase),
            now: now
        )
    }

    init(
        database: any BlindBoxCloudRecordDatabase,
        now: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.now = now
    }

    func open(_ request: BlindBoxDrawRequest) async throws -> BlindBoxOpenResult {
        if let validationError = request.validationError() {
            throw validationError
        }

        try await ensureZoneExists()
        let drawRecordID = BlindBoxCloudKitRecordCodec.drawRecordID(for: request.idempotencyKey)
        let accountRecordID = BlindBoxCloudKitRecordCodec.accountRecordID

        for attempt in 0..<Self.maximumContentionAttempts {
            do {
                let records = try await database.fetchRecords([drawRecordID, accountRecordID])
                let existingDraw = try records[drawRecordID].map(
                    BlindBoxCloudKitRecordCodec.decodeDrawRecord
                )
                guard let accountRecord = records[accountRecordID] else {
                    throw BlindBoxCloudKitRepositoryError.accountNotInitialized
                }
                let account = try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord)

                switch try BlindBoxCloudDrawTransaction.plan(
                    request: request,
                    account: account,
                    existingDraw: existingDraw,
                    committedAt: now()
                ) {
                case let .priorResult(result):
                    return result

                case let .commit(updatedAccount, draw):
                    try BlindBoxCloudKitRecordCodec.updateAccountRecord(
                        accountRecord,
                        with: updatedAccount
                    )
                    let drawRecord = try BlindBoxCloudKitRecordCodec.makeDrawRecord(draw)
                    try await database.saveRecordsAtomically([accountRecord, drawRecord])
                    return draw.result
                }
            } catch {
                guard Self.isServerRecordChanged(error) else {
                    throw error
                }
                if attempt == Self.maximumContentionAttempts - 1 {
                    throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
                }
            }
        }

        throw BlindBoxCloudKitRepositoryError.contentionRetryLimitReached
    }

    private func ensureZoneExists() async throws {
        if try await database.fetchZone(BlindBoxCloudKitRecordCodec.zoneID) != nil {
            return
        }

        do {
            try await database.createZone(BlindBoxCloudKitRecordCodec.zoneID)
        } catch {
            // Another device may have created the zone between our read and
            // write. Re-read once before treating the creation failure as real.
            if (try? await database.fetchZone(BlindBoxCloudKitRecordCodec.zoneID)) != nil {
                return
            }
            throw error
        }
    }

    private static func isServerRecordChanged(_ error: any Error) -> Bool {
        if let cloudKitError = error as? CKError {
            return cloudKitError.code == .serverRecordChanged
        }
        let nsError = error as NSError
        return nsError.domain == CKErrorDomain
            && nsError.code == CKError.Code.serverRecordChanged.rawValue
    }
}
