import CloudKit
import Foundation

/// Read-only surface for the single public CloudKit pointer record. The app
/// never publishes content: GitHub Actions owns that privileged operation.
@MainActor
protocol BlindBoxCatalogPublicRecordDatabase: AnyObject {
    func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord?
}

@MainActor
final class BlindBoxCloudKitPublicDatabase: BlindBoxCatalogPublicRecordDatabase {
    private let database: CKDatabase

    init(database: CKDatabase) {
        self.database = database
    }

    func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        let results = try await database.records(for: [recordID])
        guard let result = results[recordID] else {
            throw BlindBoxCloudKitCatalogRepositoryError.incompleteCloudKitResponse
        }
        switch result {
        case let .success(record):
            return record
        case let .failure(error):
            if Self.cloudKitErrorCode(from: error) == .unknownItem {
                return nil
            }
            throw error
        }
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

/// Fetches the atomically published catalog bundle from the public database.
/// A missing pointer is normal before the first content release; malformed
/// data is rejected before the cache can observe it.
@MainActor
final class BlindBoxCloudKitCatalogRepository {
    static let pointerRecordType = "BlindBoxCatalogPointer"
    static let pointerRecordName = "current"
    static let bundleField = "bundle"

    private let database: any BlindBoxCatalogPublicRecordDatabase

    convenience init() {
        let publicDatabase = CKContainer(
            identifier: NativeICloudConfiguration.containerIdentifier
        ).publicCloudDatabase
        self.init(database: BlindBoxCloudKitPublicDatabase(database: publicDatabase))
    }

    init(database: any BlindBoxCatalogPublicRecordDatabase) {
        self.database = database
    }

    func fetchLatestBundle() async throws -> BlindBoxCatalogBundle? {
        guard let record = try await database.fetchRecord(Self.pointerRecordID) else {
            return nil
        }
        guard record.recordType == Self.pointerRecordType else {
            throw BlindBoxCloudKitCatalogRepositoryError.unexpectedRecordType(
                expected: Self.pointerRecordType,
                actual: record.recordType
            )
        }
        guard let asset = record[Self.bundleField] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw BlindBoxCloudKitCatalogRepositoryError.missingBundleAsset
        }
        let data = try Data(contentsOf: assetURL)
        guard let bundle = try? JSONDecoder().decode(BlindBoxCatalogBundle.self, from: data) else {
            throw BlindBoxCloudKitCatalogRepositoryError.invalidBundleEncoding
        }
        if let validationError = bundle.validationError() {
            throw BlindBoxCloudKitCatalogRepositoryError.invalidBundle(validationError)
        }
        return bundle
    }

    static var pointerRecordID: CKRecord.ID {
        CKRecord.ID(recordName: pointerRecordName)
    }
}

enum BlindBoxCloudKitCatalogRepositoryError: Error, Equatable {
    case incompleteCloudKitResponse
    case unexpectedRecordType(expected: String, actual: String)
    case missingBundleAsset
    case invalidBundleEncoding
    case invalidBundle(BlindBoxCatalogBundleValidationError)
}
