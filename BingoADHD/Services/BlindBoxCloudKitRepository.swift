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
