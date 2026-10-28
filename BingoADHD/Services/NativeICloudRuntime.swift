import CloudKit
import CoreData
import CryptoKit
import Foundation
import os

extension Notification.Name {
    static let nativeICloudRuntimeDidImport = Notification.Name("NativeICloudRuntimeDidImport")
    static let nativeICloudRuntimeDidFail = Notification.Name("NativeICloudRuntimeDidFail")
    static let nativeICloudRuntimeEventDidChange = Notification.Name("NativeICloudRuntimeEventDidChange")
    static let nativeICloudSecondaryLocalChange = Notification.Name("NativeICloudSecondaryLocalChange")
}

struct NativeICloudMirroringEvent: Equatable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case setup
        case importData
        case exportData
        case unknown
    }

    let kind: Kind
    let isFinished: Bool
    let succeeded: Bool
    let occurredAt: Date
    let errorDescription: String?
}

struct NativeICloudMirroringFailure: LocalizedError {
    let event: NativeICloudMirroringEvent

    var errorDescription: String? {
        let operation: String
        switch event.kind {
        case .setup:
            operation = "setup"
        case .importData:
            operation = "download"
        case .exportData:
            operation = "upload"
        case .unknown:
            operation = "operation"
        }
        return "iCloud \(operation) failed: \(event.errorDescription ?? "Unknown CloudKit error.")"
    }
}

enum NativeICloudErrorFormatter {
    static func describe(_ error: Error) -> String {
        if let mirroringFailure = error as? NativeICloudMirroringFailure {
            return mirroringFailure.errorDescription ?? "iCloud sync failed."
        }
        return describe(error as NSError, depth: 0)
    }

    private static func describe(_ error: NSError, depth: Int) -> String {
        var components = ["\(error.domain) \(error.code): \(error.localizedDescription)"]
        if let failureReason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
           !failureReason.isEmpty,
           failureReason != error.localizedDescription {
            components.append(failureReason)
        }

        guard depth < 3 else {
            return unique(components).joined(separator: " · ")
        }

        if let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary {
            for value in partialErrors.allValues {
                if let nestedError = value as? NSError {
                    components.append(describe(nestedError, depth: depth + 1))
                } else if let nestedError = value as? Error {
                    components.append(describe(nestedError as NSError, depth: depth + 1))
                }
            }
        }

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            components.append(describe(underlying as NSError, depth: depth + 1))
        }
        for (rawKey, value) in error.userInfo {
            let key = String(describing: rawKey).lowercased()
            guard key.contains("description") || key.contains("reason") || key.contains("message") else {
                continue
            }
            if let text = value as? String, !text.isEmpty {
                components.append(text)
            }
        }
        if error.domain == CKErrorDomain,
           error.code == CKError.partialFailure.rawValue,
           components.count <= 2 {
            components.append(String(reflecting: error))
        }
        return unique(components).joined(separator: " · ")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum NativeICloudPreferences {
    // V2 requires one explicit confirmation after replacing the failed V1 mirror.
    // This prevents two divergent devices from automatically seeding a new mirror
    // at the same time immediately after an app update.
    private static let enabledKey = "native_icloud_sync_enabled_v2"
    private static let accountScopeKey = "native_icloud_account_scope_v1"
    private static let primaryModifiedAtKey = "native_icloud_primary_local_modified_at_v1"
    private static let primaryLogicalClockKey = "native_icloud_primary_logical_clock_v2"
    private static let primaryPendingMutationGenerationKey = "native_icloud_primary_pending_mutation_v2"
    private static let secondaryModifiedAtKey = "native_icloud_secondary_local_modified_at_v1"
    private static let developmentSchemaVersion = 1
    private static let primaryHistoryMigrationVersion = 1

    static var isEnabled: Bool {
        get { sharedDefaults.bool(forKey: enabledKey) }
        set { sharedDefaults.set(newValue, forKey: enabledKey) }
    }

    static var accountScopeIdentifier: String? {
        get { sharedDefaults.string(forKey: accountScopeKey) }
        set {
            if newValue != accountScopeIdentifier {
                // The legacy marker had no account scope. Never carry it into
                // an explicitly selected different account.
                sharedDefaults.removeObject(forKey: primaryPendingMutationGenerationKey)
            }
            sharedDefaults.set(newValue, forKey: accountScopeKey)
        }
    }

    static var primaryLocalModifiedAt: Date? {
        get { date(forKey: primaryModifiedAtKey) }
        set { setDate(newValue, forKey: primaryModifiedAtKey) }
    }

    /// A persistent logical clock is intentionally independent of the device
    /// clock. It is only used for Version 2 primary commit ordering.
    static var primaryLogicalClock: TimeInterval {
        get { sharedDefaults.double(forKey: primaryLogicalClockKey) }
        set { sharedDefaults.set(newValue, forKey: primaryLogicalClockKey) }
    }

    static var primaryPendingMutationGeneration: Int {
        guard let scope = accountScopeIdentifier else { return 0 }
        let checkpoint = primaryCheckpoint(for: scope)
        return checkpoint.hasPendingMutation ? checkpoint.localRevision : 0
    }

    @discardableResult
    static func markPrimaryMutationPending() -> Int {
        guard let scope = accountScopeIdentifier else { return 0 }
        return BingoBoardStore.withBoardPersistenceLock {
            var checkpoint = primaryCheckpoint(for: scope)
            let revision = checkpoint.markChanged()
            savePrimaryCheckpoint(checkpoint, for: scope)
            return revision
        } ?? 0
    }

    static func primaryCheckpoint(for scope: String) -> NativeICloudPrimarySyncCheckpoint {
        let fileData = primaryCheckpointFileURL(for: scope).flatMap { try? Data(contentsOf: $0) }
        let candidates = [fileData, sharedDefaults.data(forKey: primaryCheckpointKey(for: scope))]
            .compactMap { $0 }.compactMap { try? JSONDecoder().decode(NativeICloudPrimarySyncCheckpoint.self, from: $0) }
        if !candidates.isEmpty {
            var merged = NativeICloudPrimarySyncCheckpoint()
            for candidate in candidates {
                merged.localRevision = max(merged.localRevision, candidate.localRevision)
                merged.exportedRevision = max(merged.exportedRevision, candidate.exportedRevision)
                if let version = candidate.acceptedVersion { merged.accept(version) }
            }
            return merged
        }
        var checkpoint = NativeICloudPrimarySyncCheckpoint()
        if accountScopeIdentifier == scope {
            checkpoint.localRevision = max(0, sharedDefaults.integer(forKey: primaryPendingMutationGenerationKey))
        }
        return checkpoint
    }

    /// Call inside the board persistence coordination used for capture/projection.
    @discardableResult
    static func savePrimaryCheckpoint(_ checkpoint: NativeICloudPrimarySyncCheckpoint, for scope: String) -> Bool {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return false }
        sharedDefaults.set(data, forKey: primaryCheckpointKey(for: scope))
        if let file = primaryCheckpointFileURL(for: scope) {
            do {
                try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                DiagnosticLogStore.recordWarning("points.icloud_checkpoint_write_failed")
                return false
            }
        }
        if accountScopeIdentifier == scope {
            sharedDefaults.removeObject(forKey: primaryPendingMutationGenerationKey)
        }
        return true
    }

    static func primaryCheckpointFileURL(for scope: String) -> URL? {
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        let fileName = "native_icloud_primary_checkpoint_v3_\(digest).json"
        if let container = BingoBoardStore.sharedContainerURL {
            return container.appendingPathComponent(fileName)
        }
        // Unsigned development builds have no App Group container. Keep the
        // durable checkpoint in this app's sandbox instead of relying on defaults alone.
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let directory = support
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Bingodays", isDirectory: true)
                .appendingPathComponent("NativeICloudCheckpoints", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(fileName)
        } catch {
            DiagnosticLogStore.recordWarning("points.icloud_checkpoint_directory_failed")
            return nil
        }
    }

    private static func primaryCheckpointKey(for scope: String) -> String {
        "native_icloud_primary_checkpoint_v3_\(scope)"
    }

    static var secondaryLocalModifiedAt: Date? {
        get { date(forKey: secondaryModifiedAtKey) }
        set { setDate(newValue, forKey: secondaryModifiedAtKey) }
    }

    static func hasInitializedDevelopmentSchema(for accountScopeIdentifier: String) -> Bool {
        sharedDefaults.integer(forKey: developmentSchemaKey(for: accountScopeIdentifier)) >= developmentSchemaVersion
    }

    static func markDevelopmentSchemaInitialized(for accountScopeIdentifier: String) {
        sharedDefaults.set(
            developmentSchemaVersion,
            forKey: developmentSchemaKey(for: accountScopeIdentifier)
        )
    }

    static func needsPrimaryHistoryMigration(for accountScopeIdentifier: String) -> Bool {
        sharedDefaults.integer(forKey: primaryHistoryMigrationKey(for: accountScopeIdentifier))
            < primaryHistoryMigrationVersion
    }

    static func markPrimaryHistoryMigrated(for accountScopeIdentifier: String) {
        sharedDefaults.set(
            primaryHistoryMigrationVersion,
            forKey: primaryHistoryMigrationKey(for: accountScopeIdentifier)
        )
    }

    private static var sharedDefaults: UserDefaults {
        BingoBoardStore.sharedDefaults
    }

    private static func date(forKey key: String) -> Date? {
        guard sharedDefaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: sharedDefaults.double(forKey: key))
    }

    private static func setDate(_ date: Date?, forKey key: String) {
        if let date {
            sharedDefaults.set(date.timeIntervalSince1970, forKey: key)
        } else {
            sharedDefaults.removeObject(forKey: key)
        }
    }

    private static func developmentSchemaKey(for accountScopeIdentifier: String) -> String {
        "native_icloud_development_schema_v\(developmentSchemaVersion)_\(accountScopeIdentifier)"
    }

    private static func primaryHistoryMigrationKey(for accountScopeIdentifier: String) -> String {
        "native_icloud_primary_history_migration_v\(primaryHistoryMigrationVersion)_\(accountScopeIdentifier)"
    }

}

/// A successful import belongs to one specific local Core Data mirror. App Group
/// preferences can survive reinstalls, while that mirror is recreated. Never use
/// a persisted "initial import completed" marker as proof that a fresh mirror
/// has downloaded its CloudKit records.
enum NativeICloudInitialImportReadiness {
    static func isReady(
        storeHasPrimarySnapshot: Bool,
        observedImportForCurrentStore: Bool
    ) -> Bool {
        storeHasPrimarySnapshot || observedImportForCurrentStore
    }
}

/// A synchronous token check is also available inside the main-actor commit.
/// Actor state checked before awaiting that actor can already be obsolete there.
final class NativeICloudPrimarySession: Sendable {
    private let identifier = OSAllocatedUnfairLock(initialState: UUID())

    var id: UUID { identifier.withLock { $0 } }
    func matches(_ candidate: UUID) -> Bool { identifier.withLock { $0 == candidate } }
    func invalidate() { identifier.withLock { $0 = UUID() } }
}

actor NativeICloudRuntime {
    static let shared = NativeICloudRuntime()

    private var store: NativeICloudSyncStore?
    private var loadedAccountScopeIdentifier: String?
    private var remoteChangeObserver: NSObjectProtocol?
    private var cloudEventObserver: NSObjectProtocol?
    private var lastHandledPrimaryStamp: NativeICloudCommitStamp?
    private var lastHandledPrimarySchemaVersion: Int64?
    private var lastHandledPrimaryState: NativeICloudPrimaryStateSnapshot?
    private var lastSuccessfulCloudEventAt: Date?
    private var finishedCloudEventRevision: UInt = 0
    private var latestFinishedCloudEvent: (revision: UInt, event: NativeICloudMirroringEvent)?
    private var latestFinishedCloudEventByKind: [
        NativeICloudMirroringEvent.Kind: (revision: UInt, event: NativeICloudMirroringEvent)
    ] = [:]
    private var hasCompletedInitialCloudImport = false
    private var latestCloudEventFailure: NativeICloudMirroringFailure?
    private var primaryProjectionRevision: UInt = 0
    private var scheduledExportGeneration: UInt = 0
    private var scheduledPrimaryExportRequestedAt: Date?
    private var scheduledRemoteImportGeneration: UInt = 0
    private var preparingAccountScopeIdentifier: String?
    private var preparationWaiters: [CheckedContinuation<Void, Error>] = []
    private var lifecycleGeneration: UInt = 0
    private var activeStoreGeneration: UInt = 0
    private let primarySession = NativeICloudPrimarySession()
    private var isPrimaryOperationRunning = false
    private var primaryOperationWaiters: [CheckedContinuation<Void, Never>] = []

    func primarySessionID() -> UUID { primarySession.id }

    private func acquirePrimaryOperation() async {
        if isPrimaryOperationRunning {
            await withCheckedContinuation { primaryOperationWaiters.append($0) }
        } else {
            isPrimaryOperationRunning = true
        }
    }

    private func releasePrimaryOperation() {
        if primaryOperationWaiters.isEmpty {
            isPrimaryOperationRunning = false
        } else {
            primaryOperationWaiters.removeFirst().resume()
        }
    }

    func prepare(
        accountScopeIdentifier: String? = nil,
        allowsUnconfirmedAccountChange: Bool = false,
        initializeDevelopmentSchema: Bool = false
    ) async throws {
        let resolvedScope: String
        if let accountScopeIdentifier {
            resolvedScope = accountScopeIdentifier
        } else {
            resolvedScope = try await NativeICloudAccountScope.currentIdentifier()
        }
        if let store, loadedAccountScopeIdentifier == resolvedScope {
            try initializeDevelopmentSchemaIfNeeded(
                store: store,
                accountScopeIdentifier: resolvedScope,
                requested: initializeDevelopmentSchema
            )
            return
        }
        if let confirmedScope = NativeICloudPreferences.accountScopeIdentifier,
           confirmedScope != resolvedScope,
           !allowsUnconfirmedAccountChange {
            throw NativeICloudPersistenceError.accountChangedRequiresConfirmation
        }
        if preparingAccountScopeIdentifier != nil {
            try await waitForActivePreparation()
            try await prepare(
                accountScopeIdentifier: resolvedScope,
                allowsUnconfirmedAccountChange: allowsUnconfirmedAccountChange,
                initializeDevelopmentSchema: initializeDevelopmentSchema
            )
            return
        }
        if let loadedAccountScopeIdentifier, loadedAccountScopeIdentifier != resolvedScope {
            discardActiveStore()
            lastHandledPrimaryStamp = nil
            lastHandledPrimarySchemaVersion = nil
        }
        guard store == nil else { return }
        preparingAccountScopeIdentifier = resolvedScope
        let generation = lifecycleGeneration
        var candidateStore: NativeICloudSyncStore?
        do {
            let controller = try NativeICloudPersistenceController.makeCloudController(
                accountScopeIdentifier: resolvedScope
            )
            let newStore = NativeICloudSyncStore(controller: controller)
            candidateStore = newStore
            try await newStore.load()
            guard generation == lifecycleGeneration else {
                throw CancellationError()
            }
            store = newStore
            loadedAccountScopeIdentifier = resolvedScope
            candidateStore = nil
            activeStoreGeneration &+= 1
            beginObservingCloudKitEvents(
                for: newStore,
                storeGeneration: activeStoreGeneration
            )
            // This must start false for every newly prepared local mirror. The
            // App Group outlives an app reinstall, but the CloudKit cache does
            // not; restoring a previous boolean here made an empty reinstall
            // publish a 0-point snapshot before its first download arrived.
            hasCompletedInitialCloudImport = false
            try initializeDevelopmentSchemaIfNeeded(
                store: newStore,
                accountScopeIdentifier: resolvedScope,
                requested: initializeDevelopmentSchema
            )
            finishActivePreparation(error: nil)
        } catch {
            try? candidateStore?.unload()
            if loadedAccountScopeIdentifier == resolvedScope {
                discardActiveStore()
            }
            finishActivePreparation(error: error)
            throw error
        }
    }

    func latestValue(for domain: NativeICloudDomain) async throws -> NativeICloudEnvelopeValue? {
        try await readyStore().latestValue(for: domain)
    }

    func values(for domain: NativeICloudDomain) async throws -> [NativeICloudEnvelopeValue] {
        try await readyStore().values(for: domain)
    }

    @discardableResult
    func saveLatest(
        domain: NativeICloudDomain,
        payload: Data,
        stamp: NativeICloudCommitStamp? = nil,
        expectedSessionID: UUID? = nil
    ) async throws -> NativeICloudEnvelopeValue {
        let sessionID = expectedSessionID ?? primarySession.id
        if domain == .primaryState { await acquirePrimaryOperation() }
        defer { if domain == .primaryState { releasePrimaryOperation() } }
        guard primarySession.matches(sessionID) else { throw CancellationError() }
        return try await saveLatestUnderPrimaryOperation(domain: domain, payload: payload, stamp: stamp, expectedSessionID: sessionID)
    }

    private func saveLatestUnderPrimaryOperation(
        domain: NativeICloudDomain,
        payload: Data,
        stamp: NativeICloudCommitStamp? = nil,
        localRevision: Int? = nil,
        expectedSessionID: UUID
    ) async throws -> NativeICloudEnvelopeValue {
        let sessionID = expectedSessionID
        guard primarySession.matches(sessionID) else { throw CancellationError() }
        let syncStore = try await readyStore()
        guard primarySession.matches(sessionID) else { throw CancellationError() }
        let session = primarySession
        let scope = loadedAccountScopeIdentifier
        let schemaVersion: Int64
        let resolvedStamp: NativeICloudCommitStamp
        if domain == .primaryState {
            schemaVersion = NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion
            if let stamp {
                resolvedStamp = stamp
            } else {
                resolvedStamp = try await nextPrimaryLogicalStamp()
            }
        } else {
            schemaVersion = NativeICloudPrimaryEnvelopeSchema.legacyVersion
            resolvedStamp = stamp ?? NativeICloudCommitStamp(modifiedAt: .now, commitID: UUID())
        }
        guard session.matches(sessionID) else { throw CancellationError() }
        let saved = try await syncStore.saveLatest(
            domain: domain,
            payload: payload,
            stamp: resolvedStamp,
            schemaVersion: schemaVersion
        )
        guard session.matches(sessionID) else { throw CancellationError() }
        if domain == .primaryState {
            // A primary record is an immutable, explicit local user commit. Never
            // merge an older cloud record into it and never manufacture a follow-up
            // "recovery" record here. That feedback loop made two devices publish
            // alternating whole-board snapshots, which changed points without a
            // corresponding user tap and could revert completed tasks.
            if let scope {
                try await MainActor.run {
                    guard session.matches(sessionID) else { throw CancellationError() }
                    guard BingoBoardStore.withBoardPersistenceLock({
                        var checkpoint = NativeICloudPreferences.primaryCheckpoint(for: scope)
                        checkpoint.accept(.init(stamp: saved.stamp, schemaVersion: saved.schemaVersion))
                        if let localRevision { checkpoint.acknowledge(localRevision) }
                        return NativeICloudPreferences.savePrimaryCheckpoint(checkpoint, for: scope)
                    }) == true else { throw NativeICloudLocalProjectionError.primaryProjectionFailed }
                }
            }
            guard session.matches(sessionID) else { throw CancellationError() }
            if let submittedState = try? JSONDecoder().decode(
                NativeICloudPrimaryStateSnapshot.self,
                from: saved.payload
            ) {
                rememberPrimaryHandled(stamp: saved.stamp, schemaVersion: saved.schemaVersion, state: submittedState)
            }
        }
        return saved
    }

    func markPrimaryHandled(
        _ stamp: NativeICloudCommitStamp,
        schemaVersion: Int64 = NativeICloudPrimaryEnvelopeSchema.legacyVersion,
        state: NativeICloudPrimaryStateSnapshot? = nil
    ) {
        if let state {
            rememberPrimaryHandled(stamp: stamp, schemaVersion: schemaVersion, state: state)
        } else {
            rememberPrimaryHandled(stamp: stamp, schemaVersion: schemaVersion)
        }
    }

    private func nextPrimaryLogicalStamp(
        after remote: NativeICloudEnvelopeValue? = nil
    ) async throws -> NativeICloudCommitStamp {
        let current = try await readyStore().latestValue(for: .primaryState)
        let latest = remote ?? current
        let remoteTick: TimeInterval
        if let latest,
           latest.schemaVersion >= NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion {
            remoteTick = latest.stamp.modifiedAt.timeIntervalSinceReferenceDate
        } else {
            remoteTick = 0
        }
        let next = max(NativeICloudPreferences.primaryLogicalClock, remoteTick) + 1
        NativeICloudPreferences.primaryLogicalClock = next
        return NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSinceReferenceDate: next),
            commitID: UUID()
        )
    }

    private func hasHandledPrimaryCommit(_ value: NativeICloudEnvelopeValue) -> Bool {
        guard let handledStamp = lastHandledPrimaryStamp,
              let handledSchema = lastHandledPrimarySchemaVersion else {
            return false
        }
        if handledSchema != value.schemaVersion {
            return handledSchema > value.schemaVersion
        }
        return value.stamp <= handledStamp
    }

    private func rememberPrimaryHandled(
        stamp: NativeICloudCommitStamp,
        schemaVersion: Int64
    ) {
        guard let handledStamp = lastHandledPrimaryStamp,
              let handledSchema = lastHandledPrimarySchemaVersion else {
            lastHandledPrimaryStamp = stamp
            lastHandledPrimarySchemaVersion = schemaVersion
            return
        }
        guard schemaVersion > handledSchema ||
                (schemaVersion == handledSchema && stamp > handledStamp) else {
            return
        }
        lastHandledPrimaryStamp = stamp
        lastHandledPrimarySchemaVersion = schemaVersion
    }

    private func rememberPrimaryHandled(
        stamp: NativeICloudCommitStamp,
        schemaVersion: Int64,
        state: NativeICloudPrimaryStateSnapshot
    ) {
        rememberPrimaryHandled(stamp: stamp, schemaVersion: schemaVersion)
        guard lastHandledPrimaryStamp == stamp,
              lastHandledPrimarySchemaVersion == schemaVersion else {
            return
        }
        lastHandledPrimaryState = state
    }

    func schedulePrimaryExport(requestedAt: Date = .now) {
        guard NativeICloudPreferences.isEnabled else { return }
        scheduledExportGeneration &+= 1
        if let scheduledPrimaryExportRequestedAt {
            self.scheduledPrimaryExportRequestedAt = max(scheduledPrimaryExportRequestedAt, requestedAt)
        } else {
            scheduledPrimaryExportRequestedAt = requestedAt
        }
        if preparingAccountScopeIdentifier != nil {
            finishActivePreparation(error: CancellationError())
        }
        let generation = scheduledExportGeneration
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await performScheduledPrimaryExport(generation: generation)
        }
    }

    /// Immediately consumes the pending debounce request before a user-initiated
    /// sync. This asks Core Data to enqueue the CloudKit export; completion is
    /// confirmed separately by a finished container event.
    @discardableResult
    func flushScheduledPrimaryExport() async throws -> Bool {
        guard NativeICloudPreferences.isEnabled,
              let requestedAt = scheduledPrimaryExportRequestedAt else {
            return false
        }
        scheduledExportGeneration &+= 1
        scheduledPrimaryExportRequestedAt = nil
        _ = try await exportPrimaryNow(requestedAt: requestedAt)
        return true
    }

    @discardableResult
    func exportPrimaryNow(
        requestedAt: Date? = nil
    ) async throws -> NativeICloudEnvelopeValue? {
        try await commitCurrentPrimaryState(allowsDisabledSync: false)
    }

    /// Initial enablement has not set isEnabled yet, but must use exactly the
    /// same serial capture-and-save path as subsequent user changes.
    @discardableResult
    func exportPrimaryForInitialMigration(expectedSessionID: UUID? = nil) async throws -> NativeICloudEnvelopeValue? {
        try await commitCurrentPrimaryState(allowsDisabledSync: true, expectedSessionID: expectedSessionID)
    }

    private func commitCurrentPrimaryState(
        allowsDisabledSync: Bool,
        expectedSessionID: UUID? = nil
    ) async throws -> NativeICloudEnvelopeValue? {
        let sessionID = expectedSessionID ?? primarySession.id
        await acquirePrimaryOperation()
        defer { releasePrimaryOperation() }
        let session = primarySession
        guard session.matches(sessionID), allowsDisabledSync || NativeICloudPreferences.isEnabled else {
            throw CancellationError()
        }
        try await prepare()
        guard hasCompletedInitialCloudImport, let scope = loadedAccountScopeIdentifier else { return nil }
        let current = try await latestValue(for: .primaryState)
        let stamp = try await nextPrimaryLogicalStamp(after: current)
        // All asynchronous cloud reads precede capture. Capture and its revision
        // share the same coordination as app/widget business transactions.
        let captured = try await MainActor.run {
            guard session.matches(sessionID),
                  allowsDisabledSync || NativeICloudPreferences.isEnabled,
                  NativeICloudPreferences.accountScopeIdentifier == scope ||
                    (allowsDisabledSync && NativeICloudPreferences.accountScopeIdentifier == nil) else {
                throw CancellationError()
            }
            guard let captured = BingoBoardStore.withBoardPersistenceLock({
                (NativeICloudPrimaryStateSnapshot.captureLocal(),
                 NativeICloudPreferences.primaryCheckpoint(for: scope).localRevision)
            }) else { throw NativeICloudLocalProjectionError.primaryProjectionFailed }
            return captured
        }
        let (snapshot, revision) = captured
        guard !snapshot.isSystemStarterGuideSeedData else {
            DiagnosticLogStore.recordStateChange("icloud_export_skipped_starter_guide_seed")
            return nil
        }
        if let current,
           let remote = try? JSONDecoder().decode(NativeICloudPrimaryStateSnapshot.self, from: current.payload),
           NativeICloudPrimaryExportGuard.blocksAutomaticUpload(local: snapshot, remote: remote) {
            DiagnosticLogStore.recordWarning("points.icloud_export_blocked_empty_local_state")
            return nil
        }
        guard session.matches(sessionID) else { throw CancellationError() }
        DiagnosticLogStore.recordStateChange("points.icloud_export_begin", details: [
            "local_total": snapshot.points.totalPoints.map(String.init) ?? "nil",
            "local_lifetime": snapshot.points.lifetimePoints.map(String.init) ?? "nil",
            "local_revision": String(revision),
            "logical_stamp": String(stamp.modifiedAt.timeIntervalSinceReferenceDate),
            "commit_id": String(stamp.commitID.uuidString.prefix(8))
        ])
        let saved = try await saveLatestUnderPrimaryOperation(
            domain: .primaryState, payload: try JSONEncoder().encode(snapshot),
            stamp: stamp, localRevision: revision, expectedSessionID: sessionID
        )
        guard session.matches(sessionID) else { throw CancellationError() }
        DiagnosticLogStore.recordStateChange("points.icloud_export_saved", details: [
            "local_total": snapshot.points.totalPoints.map(String.init) ?? "nil",
            "local_revision": String(revision),
            "saved_logical_stamp": String(saved.stamp.modifiedAt.timeIntervalSinceReferenceDate),
            "commit_id": String(saved.stamp.commitID.uuidString.prefix(8))
        ])
        if NativeICloudPreferences.isEnabled,
           NativeICloudPreferences.primaryCheckpoint(for: scope).hasPendingMutation {
            schedulePrimaryExport()
        }
        return saved
    }

    /// Returns false when a user edited the local board while migration was
    /// reading the mirror. The caller then exports a fresh local snapshot.
    func applyPrimaryForInitialMigration(
        _ snapshot: NativeICloudPrimaryStateSnapshot,
        stamp: NativeICloudCommitStamp,
        schemaVersion: Int64,
        expectedSessionID: UUID? = nil,
        isExplicitAccountReplacement: Bool = false
    ) async throws -> Bool {
        let sessionID = expectedSessionID ?? primarySession.id
        await acquirePrimaryOperation()
        defer { releasePrimaryOperation() }
        guard primarySession.matches(sessionID), let scope = loadedAccountScopeIdentifier else {
            throw CancellationError()
        }
        let session = primarySession
        let projection = try await MainActor.run {
            try NativeICloudPrimaryLocalProjection.applyIfCurrent(
                snapshot, latestStamp: stamp, latestSchemaVersion: schemaVersion,
                hasHandledLatestCommit: false, resolvedStateWasAlreadyHandled: false,
                accountScope: scope, session: session, sessionID: sessionID,
                allowsDisabledSync: true, isExplicitAccountReplacement: isExplicitAccountReplacement
            )
        }
        guard session.matches(sessionID) else { throw CancellationError() }
        guard !projection.localHasNewerUserChange else { return false }
        rememberPrimaryHandled(stamp: stamp, schemaVersion: schemaVersion, state: snapshot)
        return true
    }

    func rebasePrimaryHistoryIfNeeded(
        accountScopeIdentifier: String
    ) async throws {
        guard NativeICloudPreferences.needsPrimaryHistoryMigration(
            for: accountScopeIdentifier
        ) else {
            return
        }

        try await prepare(accountScopeIdentifier: accountScopeIdentifier)
        let snapshot = NativeICloudPrimaryStateSnapshot.captureLocal()
        guard snapshot.hasMeaningfulUserData else {
            NativeICloudPreferences.markPrimaryHistoryMigrated(
                for: accountScopeIdentifier
            )
            return
        }

        // V3 stores immutable primary commits. Rebase each device's current local
        // snapshot once so a prior mutable-record overwrite cannot erase progress.
        let payload = try JSONEncoder().encode(snapshot)
        _ = try await saveLatest(domain: .primaryState, payload: payload)
        NativeICloudPreferences.markPrimaryHistoryMigrated(
            for: accountScopeIdentifier
        )
    }

    @discardableResult
    func importPrimaryIfNeeded(reloadWidgets: Bool = true) async throws -> Bool {
        guard NativeICloudPreferences.isEnabled else { return false }
        let sessionID = primarySession.id
        await acquirePrimaryOperation()
        defer { releasePrimaryOperation() }
        guard primarySession.matches(sessionID), NativeICloudPreferences.isEnabled else { throw CancellationError() }
        try await prepare()
        guard let scope = loadedAccountScopeIdentifier else { throw CancellationError() }
        let session = primarySession
        let primaryValues = try await readyStore().values(for: .primaryState)
        let decodedHistory = primaryValues.compactMap { value -> (NativeICloudEnvelopeValue, NativeICloudPrimaryStateSnapshot)? in
            guard let snapshot = try? JSONDecoder().decode(
                NativeICloudPrimaryStateSnapshot.self,
                from: value.payload
            ) else {
                return nil
            }
            return (value, snapshot)
        }
        guard let latest = decodedHistory.last?.0,
              let newestSnapshot = decodedHistory.last?.1,
              let snapshot = NativeICloudPrimaryHistoryResolver.resolve(
                  decodedHistory
        ) else {
            return false
        }
        let hasHandledLatestCommit = hasHandledPrimaryCommit(latest)
        let resolvedStateWasAlreadyHandled = NativeICloudPrimaryHandledStateResolver.contains(
            latestStamp: latest.stamp,
            latestSchemaVersion: latest.schemaVersion,
            resolvedState: snapshot,
            handledStamp: lastHandledPrimaryStamp,
            handledSchemaVersion: lastHandledPrimarySchemaVersion,
            handledState: lastHandledPrimaryState
        )
        // Local projection writes UserDefaults and SwiftUI observes those writes.
        // Run the complete local compare-and-commit on the main actor, with no
        // persistence lock held while this actor awaits the handoff.
        let projection = try await MainActor.run {
            try NativeICloudPrimaryLocalProjection.applyIfCurrent(
                snapshot,
                latestStamp: latest.stamp,
                latestSchemaVersion: latest.schemaVersion,
                hasHandledLatestCommit: hasHandledLatestCommit,
                resolvedStateWasAlreadyHandled: resolvedStateWasAlreadyHandled,
                reloadWidgets: reloadWidgets,
                accountScope: scope, session: session, sessionID: sessionID
            )
        }
        guard session.matches(sessionID) else { throw CancellationError() }
        let localSnapshot = projection.localSnapshot
        let localTotal = localSnapshot.points.totalPoints.map(String.init) ?? "nil"
        let cloudTotal = snapshot.points.totalPoints.map(String.init) ?? "nil"
        let localLifetime = localSnapshot.points.lifetimePoints.map(String.init) ?? "nil"
        let cloudLifetime = snapshot.points.lifetimePoints.map(String.init) ?? "nil"
        let localModified = NativeICloudPreferences.primaryLocalModifiedAt
            .map { String($0.timeIntervalSince1970) } ?? "nil"
        let cloudStamp = String(latest.stamp.modifiedAt.timeIntervalSince1970)
        let commitID = String(latest.stamp.commitID.uuidString.prefix(8))
        let importDetails: [String: String] = [
            "local_total": localTotal,
            "cloud_total": cloudTotal,
            "local_lifetime": localLifetime,
            "cloud_lifetime": cloudLifetime,
            "local_modified": localModified,
            "cloud_stamp": cloudStamp,
            "commit_id": commitID,
            "local_newer": String(projection.localHasNewerUserChange),
            "pending_local_mutation": String(projection.hasPendingLocalMutation),
            "cloud_schema": String(latest.schemaVersion),
            "local_revision": String(NativeICloudPreferences.primaryCheckpoint(for: scope).localRevision),
            "history_count": String(decodedHistory.count),
            "history_repaired_latest": String(!snapshot.hasSameUserState(as: newestSnapshot))
        ]
        if projection.didSkipHandledCommit {
            if projection.hasPendingLocalMutation { schedulePrimaryExport() }
            DiagnosticLogStore.recordStateChange(
                "points.icloud_import_skipped_handled",
                details: importDetails
            )
            rememberPrimaryHandled(
                stamp: latest.stamp,
                schemaVersion: latest.schemaVersion,
                state: snapshot
            )
            return false
        }

        // A local tap that has not reached CloudKit yet must not be replaced by a
        // delayed import. The scheduled exporter retains the dirty timestamp and
        // will publish that exact local commit.
        guard !projection.localHasNewerUserChange else {
            DiagnosticLogStore.recordStateChange(
                "points.icloud_import_skipped_local_newer",
                details: importDetails
            )
            // An interactive widget can run while this process is still waiting
            // for its first CloudKit import. Keep the durable mutation marker and
            // retry the export after the import notification instead of allowing
            // the newly tapped task to remain local forever.
            if projection.hasPendingLocalMutation {
                schedulePrimaryExport()
            }
            return false
        }

        // Import is deliberately one-way: it projects the resolved immutable
        // cloud history, then stops. In particular, an import must never create
        // another primary record. The former import/export feedback loop was the
        // source of repeated point jumps and task-state reversions.
        if projection.didApply {
            DiagnosticLogStore.recordWarning(
                "points.icloud_import_applying",
                details: importDetails
            )
            primaryProjectionRevision &+= 1
        } else {
            DiagnosticLogStore.recordStateChange(
                "points.icloud_import_same_state",
                details: importDetails
            )
        }
        rememberPrimaryHandled(
            stamp: latest.stamp,
            schemaVersion: latest.schemaVersion,
            state: snapshot
        )
        return projection.didApply
    }

    func beginObservingRemoteChanges() async throws {
        try await prepare()
        guard remoteChangeObserver == nil,
              let store else { return }
        let storeGeneration = activeStoreGeneration
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: store.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.schedulePersistentStoreChangeImport(
                    forStoreGeneration: storeGeneration
                )
            }
        }
    }

    /// Returns whether CloudKit confirmed an initial import. A device can already
    /// have a durable mirrored snapshot while Core Data keeps an import event open
    /// (or emits no import event when there is nothing new). That is not a sync
    /// failure and must not turn the user's enabled switch into an error state.
    func waitForInitialCloudImport(timeout: TimeInterval = 12) async throws -> Bool {
        let generation = lifecycleGeneration
        let syncStore = try await readyStore()
        let storeAlreadyHadPrimarySnapshot = try await syncStore.latestValue(for: .primaryState) != nil
        guard generation == lifecycleGeneration else { throw CancellationError() }
        if NativeICloudInitialImportReadiness.isReady(
            storeHasPrimarySnapshot: storeAlreadyHadPrimarySnapshot,
            observedImportForCurrentStore: hasCompletedInitialCloudImport
        ) {
            hasCompletedInitialCloudImport = true
            return true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !hasCompletedInitialCloudImport {
            guard generation == lifecycleGeneration else { throw CancellationError() }
            try Task.checkCancellation()
            if let latestCloudEventFailure {
                throw latestCloudEventFailure
            }
            let receivedPrimary = try await syncStore.latestValue(for: .primaryState) != nil
            guard generation == lifecycleGeneration else { throw CancellationError() }
            if receivedPrimary {
                hasCompletedInitialCloudImport = true
                return true
            }
            guard Date() < deadline else {
                return false
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        return true
    }

    func shutdown() {
        lifecycleGeneration &+= 1
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
        remoteChangeObserver = nil
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
        }
        cloudEventObserver = nil
        discardActiveStore()
        lastHandledPrimaryStamp = nil
        lastHandledPrimarySchemaVersion = nil
        lastHandledPrimaryState = nil
        lastSuccessfulCloudEventAt = nil
        finishedCloudEventRevision = 0
        latestFinishedCloudEvent = nil
        latestFinishedCloudEventByKind.removeAll()
        hasCompletedInitialCloudImport = false
        latestCloudEventFailure = nil
        scheduledExportGeneration &+= 1
        scheduledPrimaryExportRequestedAt = nil
        scheduledRemoteImportGeneration &+= 1
    }

    func latestSuccessfulCloudEventDate() -> Date? {
        lastSuccessfulCloudEventAt
    }

    func cloudActivityCheckpoint() -> UInt {
        finishedCloudEventRevision
    }

    /// Core Data with CloudKit has no public force-download API. Wait for a real
    /// finished operation so the UI can distinguish confirmed cloud activity from
    /// merely reading the local mirrored store.
    func waitForFinishedCloudActivity(
        after checkpoint: UInt,
        expectedKinds: Set<NativeICloudMirroringEvent.Kind>,
        timeout: TimeInterval
    ) async throws -> NativeICloudMirroringEvent? {
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        while true {
            if let latestFinishedCloudEvent,
               latestFinishedCloudEvent.revision > checkpoint,
               !latestFinishedCloudEvent.event.succeeded {
                throw NativeICloudMirroringFailure(event: latestFinishedCloudEvent.event)
            }

            let matchingEvent = expectedKinds.compactMap { kind in
                latestFinishedCloudEventByKind[kind]
            }
            .filter { $0.revision > checkpoint }
            .min { $0.revision < $1.revision }
            if let matchingEvent {
                guard matchingEvent.event.succeeded else {
                    throw NativeICloudMirroringFailure(event: matchingEvent.event)
                }
                return matchingEvent.event
            }

            guard Date() < deadline else { return nil }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// Handles a CloudKit silent push while the app is in the background.
    ///
    /// Core Data owns the CloudKit transport and does not expose a force-download
    /// API. Keep the process alive until its real import event arrives, then let
    /// the normal local projection update the App Group and WidgetKit timeline.
    /// Short polling also covers the case where the mirrored store changes before
    /// Core Data publishes its finished event.
    func importPrimaryForBackgroundCloudNotification(
        timeout: TimeInterval = 12
    ) async throws -> Bool {
        guard NativeICloudPreferences.isEnabled else { return false }

        let activityCheckpoint = cloudActivityCheckpoint()
        let projectionCheckpoint = primaryProjectionRevision
        try await prepare()
        try await beginObservingRemoteChanges()

        if primaryProjectionRevision > projectionCheckpoint {
            return true
        }
        if try await importPrimaryIfNeeded() {
            return true
        }

        _ = try await waitForFinishedCloudActivity(
            after: activityCheckpoint,
            expectedKinds: [.importData],
            timeout: max(timeout, 0)
        )
        if primaryProjectionRevision > projectionCheckpoint {
            return true
        }
        return try await importPrimaryIfNeeded()
    }

    private func readyStore() async throws -> NativeICloudSyncStore {
        try await prepare()
        guard let store else {
            throw NativeICloudPersistenceError.appGroupContainerUnavailable
        }
        return store
    }

    private func waitForActivePreparation() async throws {
        try await withCheckedThrowingContinuation { continuation in
            preparationWaiters.append(continuation)
        }
    }

    private func finishActivePreparation(error: Error?) {
        preparingAccountScopeIdentifier = nil
        let waiters = preparationWaiters
        preparationWaiters.removeAll()
        for waiter in waiters {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume(returning: ())
            }
        }
    }

    private func performScheduledPrimaryExport(generation: UInt) async {
        guard generation == scheduledExportGeneration else { return }
        let requestedAt = scheduledPrimaryExportRequestedAt
        scheduledPrimaryExportRequestedAt = nil
        do {
            _ = try await exportPrimaryNow(requestedAt: requestedAt)
        } catch {
            postFailure(error)
        }
    }

    private func schedulePersistentStoreChangeImport(forStoreGeneration storeGeneration: UInt) {
        guard storeGeneration == activeStoreGeneration else { return }
        scheduledRemoteImportGeneration &+= 1
        let generation = scheduledRemoteImportGeneration
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self.handlePersistentStoreChange(
                scheduledGeneration: generation,
                storeGeneration: storeGeneration
            )
        }
    }

    private func handlePersistentStoreChange(
        scheduledGeneration: UInt? = nil,
        storeGeneration: UInt? = nil
    ) async {
        if let scheduledGeneration,
           scheduledGeneration != scheduledRemoteImportGeneration {
            return
        }
        if let storeGeneration,
           storeGeneration != activeStoreGeneration {
            return
        }
        do {
            let imported = try await importPrimaryIfNeeded()
            NotificationCenter.default.post(
                name: .nativeICloudRuntimeDidImport,
                object: nil,
                userInfo: ["primaryChanged": imported]
            )
        } catch {
            postFailure(error)
        }
    }

    private func beginObservingCloudKitEvents(
        for store: NativeICloudSyncStore,
        storeGeneration: UInt
    ) {
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
        }
        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: store.persistentCloudKitContainer,
            queue: nil
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else {
                return
            }
            let snapshot = NativeICloudMirroringEvent(
                kind: Self.eventKind(event.type),
                isFinished: event.endDate != nil,
                succeeded: event.succeeded,
                occurredAt: event.endDate ?? event.startDate,
                errorDescription: event.error.map(NativeICloudErrorFormatter.describe)
            )
            Task { [weak self] in
                await self?.handleCloudKitEvent(
                    snapshot,
                    forStoreGeneration: storeGeneration
                )
            }
        }
    }

    func handleCloudKitEvent(_ event: NativeICloudMirroringEvent) async {
        await recordCloudKitEvent(event)
    }

    private func handleCloudKitEvent(
        _ event: NativeICloudMirroringEvent,
        forStoreGeneration storeGeneration: UInt
    ) async {
        guard storeGeneration == activeStoreGeneration else {
            DiagnosticLogStore.recordStateChange(
                "icloud_event_ignored_retired_store",
                details: ["store_generation": String(storeGeneration)]
            )
            return
        }
        await recordCloudKitEvent(event)
    }

    private func recordCloudKitEvent(_ event: NativeICloudMirroringEvent) async {
        if event.isFinished, event.succeeded {
            lastSuccessfulCloudEventAt = event.occurredAt
            latestCloudEventFailure = nil
            if event.kind == .importData {
                hasCompletedInitialCloudImport = true
                await handlePersistentStoreChange()
            }
        } else if event.isFinished {
            let failure = NativeICloudMirroringFailure(event: event)
            latestCloudEventFailure = failure
            postFailure(failure)
        }

        if event.isFinished {
            finishedCloudEventRevision &+= 1
            let finished = (revision: finishedCloudEventRevision, event: event)
            latestFinishedCloudEvent = finished
            latestFinishedCloudEventByKind[event.kind] = finished
        }

        NotificationCenter.default.post(
            name: .nativeICloudRuntimeEventDidChange,
            object: nil,
            userInfo: ["event": event]
        )
    }

    /// Do not call `remove(_:)` on a Core Data store while one of its background
    /// contexts may still be saving. The store object remains strongly held by an
    /// in-flight operation and Core Data can release it after that operation ends.
    private func discardActiveStore() {
        primarySession.invalidate()
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
        remoteChangeObserver = nil
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
        }
        cloudEventObserver = nil
        store = nil
        loadedAccountScopeIdentifier = nil
        activeStoreGeneration &+= 1
    }

    private nonisolated static func eventKind(
        _ type: NSPersistentCloudKitContainer.EventType
    ) -> NativeICloudMirroringEvent.Kind {
        switch type {
        case .setup:
            return .setup
        case .import:
            return .importData
        case .export:
            return .exportData
        @unknown default:
            return .unknown
        }
    }

    private func initializeDevelopmentSchemaIfNeeded(
        store: NativeICloudSyncStore,
        accountScopeIdentifier: String,
        requested: Bool
    ) throws {
        #if DEBUG
        guard requested,
              !NativeICloudPreferences.hasInitializedDevelopmentSchema(
                for: accountScopeIdentifier
              ) else { return }
        try store.initializeDevelopmentCloudKitSchema()
        NativeICloudPreferences.markDevelopmentSchemaInitialized(
            for: accountScopeIdentifier
        )
        #endif
    }

    private func postFailure(_ error: Error) {
        guard !(error is CancellationError) else { return }
        NotificationCenter.default.post(
            name: .nativeICloudRuntimeDidFail,
            object: nil,
            userInfo: ["error": error]
        )
    }
}

enum NativeICloudLocalChangeReporter {
    private static let suppressionDepth = OSAllocatedUnfairLock(initialState: 0)

    static func withReportingSuppressed<T>(_ body: () throws -> T) rethrows -> T {
        suppressionDepth.withLock { $0 += 1 }
        defer {
            suppressionDepth.withLock { $0 = max($0 - 1, 0) }
        }
        return try body()
    }

    static func primaryStateDidChange(scheduleExport: Bool = true) {
        guard !isReportingSuppressed else { return }
        // A pre-association write (notably starter-guide setup) must not become
        // a conflict timestamp for an account that has not downloaded yet.
        guard NativeICloudPreferences.accountScopeIdentifier != nil else { return }
        let changeDate = Date()
        // Record the local write before the debounce window. A CloudKit import can
        // arrive during those 250 ms; without this dirty marker it can overwrite the
        // task the user has just tapped before its export starts.
        NativeICloudPreferences.primaryLocalModifiedAt = changeDate
        _ = NativeICloudPreferences.markPrimaryMutationPending()
        guard NativeICloudPreferences.isEnabled else {
            return
        }
        guard scheduleExport else { return }
        Task {
            await NativeICloudRuntime.shared.schedulePrimaryExport(requestedAt: changeDate)
        }
    }

    static func secondaryStateDidChange() {
        guard !isReportingSuppressed else { return }
        NativeICloudPreferences.secondaryLocalModifiedAt = .now
        guard NativeICloudPreferences.isEnabled else { return }
        NotificationCenter.default.post(name: .nativeICloudSecondaryLocalChange, object: nil)
    }

    private static var isReportingSuppressed: Bool {
        suppressionDepth.withLock { $0 > 0 }
    }
}
