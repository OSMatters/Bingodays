import CoreData
import Foundation

enum NativeICloudDomain: String, CaseIterable {
    case primaryState
    case secondaryState
}

struct NativeICloudCommitStamp: Codable, Equatable, Comparable {
    let modifiedAt: Date
    let commitID: UUID

    static func < (lhs: NativeICloudCommitStamp, rhs: NativeICloudCommitStamp) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt < rhs.modifiedAt
        }
        return lhs.commitID.uuidString < rhs.commitID.uuidString
    }
}

struct NativeICloudEnvelopeValue: Equatable {
    let domain: NativeICloudDomain
    let payload: Data
    let stamp: NativeICloudCommitStamp
    let schemaVersion: Int64
}

/// Primary records used to be ordered solely by wall-clock time. A device with
/// its clock moved into the future could therefore keep overriding every later
/// task tap after its clock was corrected. Version 2 is a logical commit stream:
/// it wins over the legacy stream, and its stamps are generated monotonically by
/// the app rather than taken from the device clock.
enum NativeICloudPrimaryEnvelopeSchema {
    static let legacyVersion: Int64 = 1
    static let logicalCommitVersion: Int64 = 2
}

enum NativeICloudSaveConflictResolver {
    static func submittedValueWasPersisted(
        payload: Data,
        stamp: NativeICloudCommitStamp,
        savedValue: NativeICloudEnvelopeValue
    ) -> Bool {
        savedValue.payload == payload && savedValue.stamp == stamp
    }
}

final class NativeICloudSyncStore {
    /// CloudKit is the synchronization source, not a full backup system, but a
    /// bounded runway of meaningful commits lets us diagnose a bad client before
    /// a short burst of writes erases every recovery candidate.
    static let primaryHistoryLimit = 64

    private let controller: NativeICloudPersistenceController

    init(controller: NativeICloudPersistenceController) {
        self.controller = controller
    }

    var persistentStoreCoordinator: NSPersistentStoreCoordinator {
        controller.container.persistentStoreCoordinator
    }

    /// Scope CloudKit event observation to this mirror. A runtime can replace a
    /// mirror after an iCloud account change; events from the retired container
    /// must not drive imports for the replacement.
    var persistentCloudKitContainer: NSPersistentCloudKitContainer {
        controller.container
    }

    func load() async throws {
        try await controller.load()
    }

    func unload() throws {
        try controller.unload()
    }

    #if DEBUG
    func initializeDevelopmentCloudKitSchema() throws {
        try controller.initializeDevelopmentCloudKitSchema()
    }
    #endif

    func latestValue(for domain: NativeICloudDomain) async throws -> NativeICloudEnvelopeValue? {
        let container = controller.container
        return try await container.performBackgroundTask { context in
            try Self.fetchLatestValue(for: domain, in: context)
        }
    }

    func values(for domain: NativeICloudDomain) async throws -> [NativeICloudEnvelopeValue] {
        let container = controller.container
        return try await container.performBackgroundTask { context in
            try Self.fetchValues(for: domain, in: context)
        }
    }

    @discardableResult
    func saveLatest(
        domain: NativeICloudDomain,
        payload: Data,
        stamp: NativeICloudCommitStamp = NativeICloudCommitStamp(modifiedAt: .now, commitID: UUID()),
        schemaVersion: Int64 = 1
    ) async throws -> NativeICloudEnvelopeValue {
        let container = controller.container
        return try await container.performBackgroundTask { context in
            if domain == .primaryState {
                if let current = try Self.fetchLatestValue(for: domain, in: context),
                   current.schemaVersion >= schemaVersion,
                   Self.isSamePrimaryUserState(current.payload, payload) {
                    return current
                }
                let target = NativeCloudStateEnvelope(context: context)
                target.domain = domain.rawValue
                target.payload = payload
                target.modifiedAt = stamp.modifiedAt
                target.commitID = stamp.commitID
                target.schemaVersion = schemaVersion
                try context.save()
                try Self.prunePrimaryHistoryIfNeeded(in: context)
                return NativeICloudEnvelopeValue(
                    domain: domain,
                    payload: payload,
                    stamp: stamp,
                    schemaVersion: schemaVersion
                )
            }

            let currentObject = try Self.fetchLatestObject(for: domain, in: context)
            if let currentObject,
               let currentValue = Self.value(from: currentObject),
               currentValue.stamp > stamp {
                return currentValue
            }

            let target = currentObject ?? NativeCloudStateEnvelope(context: context)
            target.domain = domain.rawValue
            target.payload = payload
            target.modifiedAt = stamp.modifiedAt
            target.commitID = stamp.commitID
            target.schemaVersion = schemaVersion
            try context.save()

            return NativeICloudEnvelopeValue(
                domain: domain,
                payload: payload,
                stamp: stamp,
                schemaVersion: schemaVersion
            )
        }
    }

    private static func fetchLatestValue(
        for domain: NativeICloudDomain,
        in context: NSManagedObjectContext
    ) throws -> NativeICloudEnvelopeValue? {
        try fetchLatestObject(for: domain, in: context).flatMap(value(from:))
    }

    private static func fetchLatestObject(
        for domain: NativeICloudDomain,
        in context: NSManagedObjectContext
    ) throws -> NativeCloudStateEnvelope? {
        let request = NativeCloudStateEnvelope.fetchRequest()
        request.predicate = NSPredicate(format: "domain == %@", domain.rawValue)
        request.sortDescriptors = [
            NSSortDescriptor(key: "modifiedAt", ascending: false),
            NSSortDescriptor(key: "commitID", ascending: false)
        ]
        let candidates = try context.fetch(request).compactMap { object -> (NativeCloudStateEnvelope, NativeICloudEnvelopeValue)? in
            guard let value = value(from: object) else { return nil }
            return (object, value)
        }
        return candidates.sorted { lhs, rhs in
            isPreferred(lhs.1, over: rhs.1, for: domain)
        }.first?.0
    }

    private static func fetchValues(
        for domain: NativeICloudDomain,
        in context: NSManagedObjectContext
    ) throws -> [NativeICloudEnvelopeValue] {
        let request = NativeCloudStateEnvelope.fetchRequest()
        request.predicate = NSPredicate(format: "domain == %@", domain.rawValue)
        return try context.fetch(request)
            .compactMap(value(from:))
            .sorted { lhs, rhs in
                if domain == .primaryState,
                   lhs.schemaVersion != rhs.schemaVersion {
                    return lhs.schemaVersion < rhs.schemaVersion
                }
                return lhs.stamp < rhs.stamp
            }
    }

    private static func prunePrimaryHistoryIfNeeded(in context: NSManagedObjectContext) throws {
        let request = NativeCloudStateEnvelope.fetchRequest()
        request.predicate = NSPredicate(format: "domain == %@", NativeICloudDomain.primaryState.rawValue)
        let candidates = try context.fetch(request).compactMap { object -> (NativeCloudStateEnvelope, NativeICloudEnvelopeValue)? in
            guard let value = value(from: object) else { return nil }
            return (object, value)
        }.sorted { lhs, rhs in
            isPreferred(lhs.1, over: rhs.1, for: .primaryState)
        }
        guard candidates.count > primaryHistoryLimit else { return }

        for candidate in candidates.dropFirst(primaryHistoryLimit) {
            context.delete(candidate.0)
        }
        try context.save()
    }

    /// The device-local daily reward ledger is deliberately excluded from the
    /// primary cloud state. Two encodings can therefore represent the same user
    /// data while their bytes differ. Treating them as distinct commits would
    /// fill the bounded history with no-op records and shorten recovery time.
    private static func isSamePrimaryUserState(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs != rhs else { return true }
        guard let lhsSnapshot = try? JSONDecoder().decode(
            NativeICloudPrimaryStateSnapshot.self,
            from: lhs
        ), let rhsSnapshot = try? JSONDecoder().decode(
            NativeICloudPrimaryStateSnapshot.self,
            from: rhs
        ) else {
            return false
        }
        return lhsSnapshot.hasSameUserState(as: rhsSnapshot)
    }

    private static func isPreferred(
        _ lhs: NativeICloudEnvelopeValue,
        over rhs: NativeICloudEnvelopeValue,
        for domain: NativeICloudDomain
    ) -> Bool {
        if domain == .primaryState {
            return NativeICloudPrimaryConflictResolver.prefers(lhs, over: rhs)
        }
        return lhs.stamp > rhs.stamp
    }

    private static func value(from object: NativeCloudStateEnvelope) -> NativeICloudEnvelopeValue? {
        guard let rawDomain = object.domain,
              let domain = NativeICloudDomain(rawValue: rawDomain),
              let payload = object.payload,
              let modifiedAt = object.modifiedAt,
              let commitID = object.commitID else {
            return nil
        }
        return NativeICloudEnvelopeValue(
            domain: domain,
            payload: payload,
            stamp: NativeICloudCommitStamp(modifiedAt: modifiedAt, commitID: commitID),
            schemaVersion: object.schemaVersion
        )
    }
}
