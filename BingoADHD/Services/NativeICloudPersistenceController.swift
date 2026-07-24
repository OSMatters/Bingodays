import CloudKit
import CoreData
import CryptoKit
import Foundation

enum NativeICloudConfiguration {
    static let appGroupIdentifier = "group.com.bingoday.app"
    static let containerIdentifier = "iCloud.com.bingoday.app.coredata"
    static let modelName = "BingodaysCloudModel"
    // V2 starts with clean Core Data/CloudKit mirroring metadata. The V1 mirror may
    // contain a partially-created record zone from earlier failed setup attempts.
    // Business data remains in the existing local stores and is migrated separately.
    static let storeDirectoryName = "BingodaysNativeCloudSyncV2"
    static let storeFileName = "BingodaysCloud.sqlite"

    static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["BingodaysCloudModelV1"]

        let entity = NSEntityDescription()
        entity.name = NativeCloudStateEnvelope.entityName
        entity.managedObjectClassName = NSStringFromClass(NativeCloudStateEnvelope.self)

        let domain = NSAttributeDescription()
        domain.name = "domain"
        domain.attributeType = .stringAttributeType
        domain.isOptional = true

        let payload = NSAttributeDescription()
        payload.name = "payload"
        payload.attributeType = .binaryDataAttributeType
        payload.isOptional = true

        let modifiedAt = NSAttributeDescription()
        modifiedAt.name = "modifiedAt"
        modifiedAt.attributeType = .dateAttributeType
        modifiedAt.isOptional = true

        let commitID = NSAttributeDescription()
        commitID.name = "commitID"
        commitID.attributeType = .UUIDAttributeType
        commitID.isOptional = true

        let schemaVersion = NSAttributeDescription()
        schemaVersion.name = "schemaVersion"
        schemaVersion.attributeType = .integer64AttributeType
        schemaVersion.isOptional = false
        schemaVersion.defaultValue = 1

        entity.properties = [domain, payload, modifiedAt, commitID, schemaVersion]
        entity.uniquenessConstraints = []
        model.entities = [entity]
        return model
    }

    static func cloudStoreURL(
        accountScopeIdentifier: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw NativeICloudPersistenceError.appGroupContainerUnavailable
        }

        let directoryURL = appGroupURL
            .appendingPathComponent(storeDirectoryName, isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(accountScopeIdentifier, isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } catch {
            throw NativeICloudPersistenceError.cannotCreateStoreDirectory(error)
        }
        return directoryURL.appendingPathComponent(storeFileName)
    }
}

enum NativeICloudPersistenceError: LocalizedError {
    case appGroupContainerUnavailable
    case cannotCreateStoreDirectory(Error)
    case iCloudAccountUnavailable
    case accountChangedRequiresConfirmation
    case initialCloudImportTimedOut

    var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable:
            return "The Bingodays App Group container is unavailable."
        case .cannotCreateStoreDirectory(let error):
            return "The native iCloud store directory could not be created: \(error.localizedDescription)"
        case .iCloudAccountUnavailable:
            return "An available iCloud account is required."
        case .accountChangedRequiresConfirmation:
            return "The iCloud account changed. Turn sync on again to confirm using the new account."
        case .initialCloudImportTimedOut:
            return "iCloud did not finish its initial download. Check the network and iCloud Drive, then try again."
        }
    }
}

enum NativeICloudAccountScope {
    static func currentIdentifier() async throws -> String {
        let container = CKContainer(identifier: NativeICloudConfiguration.containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw NativeICloudPersistenceError.iCloudAccountUnavailable
        }
        let recordID = try await container.userRecordID()
        let digest = SHA256.hash(data: Data(recordID.recordName.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@objc(NativeCloudStateEnvelope)
final class NativeCloudStateEnvelope: NSManagedObject {
    static let entityName = "NativeCloudStateEnvelope"

    @NSManaged var domain: String?
    @NSManaged var payload: Data?
    @NSManaged var modifiedAt: Date?
    @NSManaged var commitID: UUID?
    @NSManaged var schemaVersion: Int64
}

extension NativeCloudStateEnvelope {
    @nonobjc class func fetchRequest() -> NSFetchRequest<NativeCloudStateEnvelope> {
        NSFetchRequest<NativeCloudStateEnvelope>(entityName: entityName)
    }
}

final class NativeICloudPersistenceController {
    enum StoreMode {
        case cloud(URL)
        case inMemory
    }

    let container: NSPersistentCloudKitContainer

    static func makeCloudController(
        accountScopeIdentifier: String,
        fileManager: FileManager = .default
    ) throws -> NativeICloudPersistenceController {
        try NativeICloudPersistenceController(
            mode: .cloud(
                NativeICloudConfiguration.cloudStoreURL(
                    accountScopeIdentifier: accountScopeIdentifier,
                    fileManager: fileManager
                )
            )
        )
    }

    init(mode: StoreMode) throws {
        let model = NativeICloudConfiguration.makeManagedObjectModel()
        container = NSPersistentCloudKitContainer(
            name: NativeICloudConfiguration.modelName,
            managedObjectModel: model
        )

        let description: NSPersistentStoreDescription
        switch mode {
        case .cloud(let storeURL):
            description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            let cloudKitOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: NativeICloudConfiguration.containerIdentifier
            )
            // Bingodays synchronizes each user's data through their private
            // CloudKit database. Keep this explicit so a future configuration
            // change cannot accidentally select a public/shared database.
            cloudKitOptions.databaseScope = .private
            description.cloudKitContainerOptions = cloudKitOptions
            description.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
        case .inMemory:
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.shouldAddStoreAsynchronously = false
        }

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        container.persistentStoreDescriptions = [description]
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { [container] _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                container.viewContext.automaticallyMergesChangesFromParent = true
                container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                container.viewContext.name = "BingodaysNativeCloudViewContext"
                try? container.viewContext.setQueryGenerationFrom(.current)
                continuation.resume(returning: ())
            }
        }
    }

    #if DEBUG
    func initializeDevelopmentCloudKitSchema() throws {
        try container.initializeCloudKitSchema(options: [])
    }
    #endif

    func unload() throws {
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
