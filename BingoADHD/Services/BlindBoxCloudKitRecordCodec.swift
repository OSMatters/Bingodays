import CloudKit
import Foundation

/// The private account payload stored in the BlindBoxZone. Migration versions
/// live beside the account state so the eventual CloudKit transaction can make
/// both changes together instead of relying on a device-local marker.
struct BlindBoxCloudAccountEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var accountState: BlindBoxAccountState
    var completedLegacyMigrationVersions: Set<Int>

    init(
        schemaVersion: Int = BlindBoxCloudAccountEnvelope.currentSchemaVersion,
        accountState: BlindBoxAccountState = BlindBoxAccountState(),
        completedLegacyMigrationVersions: Set<Int> = []
    ) {
        self.schemaVersion = schemaVersion
        self.accountState = accountState
        self.completedLegacyMigrationVersions = completedLegacyMigrationVersions
    }
}

/// Immutable evidence for one accepted draw. A retry reads this record by the
/// request idempotency key and returns the original result without mutating the
/// account record again.
struct BlindBoxCloudDrawEnvelope: Codable, Equatable, Sendable {
    let request: BlindBoxDrawRequest
    let result: BlindBoxOpenResult
    let committedAt: Date
}

enum BlindBoxCloudKitRecordCodecError: Error, Equatable {
    case unexpectedRecordType(expected: String, actual: String)
    case missingPayload
    case invalidPayload
}

/// Field names and JSON encoding are centralized before any production records
/// are created. Both records belong to one private custom zone, which later
/// allows account mutation and draw evidence to be saved atomically.
enum BlindBoxCloudKitRecordCodec {
    static let zoneName = "BlindBoxZone"
    static let accountRecordType = "BlindBoxAccount"
    static let drawRecordType = "BlindBoxDraw"

    private static let payloadField = "payload"
    private static let schemaVersionField = "schemaVersion"
    private static let accountRecordName = "account"

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    static var accountRecordID: CKRecord.ID {
        CKRecord.ID(recordName: accountRecordName, zoneID: zoneID)
    }

    static func drawRecordID(for idempotencyKey: UUID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "draw-\(idempotencyKey.uuidString.lowercased())",
            zoneID: zoneID
        )
    }

    static func makeAccountRecord(
        _ envelope: BlindBoxCloudAccountEnvelope,
        recordID: CKRecord.ID = accountRecordID
    ) throws -> CKRecord {
        let record = CKRecord(recordType: accountRecordType, recordID: recordID)
        try setPayload(envelope, on: record)
        record[schemaVersionField] = NSNumber(value: envelope.schemaVersion)
        return record
    }

    static func makeDrawRecord(
        _ envelope: BlindBoxCloudDrawEnvelope,
        recordID: CKRecord.ID? = nil
    ) throws -> CKRecord {
        let record = CKRecord(
            recordType: drawRecordType,
            recordID: recordID ?? drawRecordID(for: envelope.request.idempotencyKey)
        )
        try setPayload(envelope, on: record)
        return record
    }

    static func decodeAccountRecord(_ record: CKRecord) throws -> BlindBoxCloudAccountEnvelope {
        try validate(record, recordType: accountRecordType)
        return try decodedPayload(from: record, as: BlindBoxCloudAccountEnvelope.self)
    }

    static func decodeDrawRecord(_ record: CKRecord) throws -> BlindBoxCloudDrawEnvelope {
        try validate(record, recordType: drawRecordType)
        return try decodedPayload(from: record, as: BlindBoxCloudDrawEnvelope.self)
    }

    private static func validate(_ record: CKRecord, recordType: String) throws {
        guard record.recordType == recordType else {
            throw BlindBoxCloudKitRecordCodecError.unexpectedRecordType(
                expected: recordType,
                actual: record.recordType
            )
        }
    }

    private static func setPayload<Payload: Encodable>(
        _ payload: Payload,
        on record: CKRecord
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        record[payloadField] = try encoder.encode(payload) as NSData
    }

    private static func decodedPayload<Payload: Decodable>(
        from record: CKRecord,
        as type: Payload.Type
    ) throws -> Payload {
        let data: Data
        if let directData = record[payloadField] as? Data {
            data = directData
        } else if let bridgedData = record[payloadField] as? NSData {
            data = bridgedData as Data
        } else {
            throw BlindBoxCloudKitRecordCodecError.missingPayload
        }
        guard let payload = try? JSONDecoder().decode(type, from: data) else {
            throw BlindBoxCloudKitRecordCodecError.invalidPayload
        }
        return payload
    }
}
