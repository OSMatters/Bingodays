import CloudKit
import CoreData
import Foundation

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
        set {
            sharedDefaults.set(newValue, forKey: enabledKey)
            if !newValue {
                sharedDefaults.removeObject(forKey: primaryPendingMutationGenerationKey)
            }
        }
    }

    static var accountScopeIdentifier: String? {
        get { sharedDefaults.string(forKey: accountScopeKey) }
        set { sharedDefaults.set(newValue, forKey: accountScopeKey) }
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
        sharedDefaults.integer(forKey: primaryPendingMutationGenerationKey)
    }

    @discardableResult
    static func markPrimaryMutationPending() -> Int {
        let next = primaryPendingMutationGeneration &+ 1
        sharedDefaults.set(next, forKey: primaryPendingMutationGenerationKey)
        return next
    }

    static func clearPrimaryMutationPending(ifCurrent generation: Int) {
        guard primaryPendingMutationGeneration == generation else { return }
        sharedDefaults.removeObject(forKey: primaryPendingMutationGenerationKey)
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
        UserDefaults(suiteName: NativeICloudConfiguration.appGroupIdentifier) ?? .standard
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
            try? store?.unload()
            store = nil
            remoteChangeObserver = nil
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
            beginObservingCloudKitEventsIfNeeded()
            try await newStore.load()
            guard generation == lifecycleGeneration else {
                throw CancellationError()
            }
            store = newStore
            loadedAccountScopeIdentifier = resolvedScope
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
                store = nil
                loadedAccountScopeIdentifier = nil
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
        stamp: NativeICloudCommitStamp? = nil
    ) async throws -> NativeICloudEnvelopeValue {
        let syncStore = try await readyStore()
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
        let saved = try await syncStore.saveLatest(
            domain: domain,
            payload: payload,
            stamp: resolvedStamp,
            schemaVersion: schemaVersion
        )
        if domain == .primaryState {
            // A primary record is an immutable, explicit local user commit. Never
            // merge an older cloud record into it and never manufacture a follow-up
            // "recovery" record here. That feedback loop made two devices publish
            // alternating whole-board snapshots, which changed points without a
            // corresponding user tap and could revert completed tasks.
            rememberPrimaryHandled(stamp: saved.stamp, schemaVersion: saved.schemaVersion)
            if let submittedState = try? JSONDecoder().decode(
                NativeICloudPrimaryStateSnapshot.self,
                from: payload
            ) {
                lastHandledPrimaryState = submittedState
            }
        }
        return saved
    }

    func markPrimaryHandled(
        _ stamp: NativeICloudCommitStamp,
        schemaVersion: Int64 = NativeICloudPrimaryEnvelopeSchema.legacyVersion,
        state: NativeICloudPrimaryStateSnapshot? = nil
    ) {
        rememberPrimaryHandled(stamp: stamp, schemaVersion: schemaVersion)
        if let state {
            lastHandledPrimaryState = state
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
        guard NativeICloudPreferences.isEnabled else { return nil }
        try await prepare()
        // On a fresh device Core Data may still contain an old local mirror while
        // CloudKit has not completed its first download. Do not let that cache
        // publish a newer-looking whole snapshot over the real account data.
        guard hasCompletedInitialCloudImport else { return nil }
        let snapshot = NativeICloudPrimaryStateSnapshot.captureLocal()
        let pendingMutationGeneration = NativeICloudPreferences.primaryPendingMutationGeneration
        guard !snapshot.isSystemStarterGuideSeedData else {
            DiagnosticLogStore.recordStateChange("icloud_export_skipped_starter_guide_seed")
            return nil
        }
        if let current = try await latestValue(for: .primaryState),
           let currentSnapshot = try? JSONDecoder().decode(
               NativeICloudPrimaryStateSnapshot.self,
               from: current.payload
           ) {
            if current.schemaVersion >= NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion,
               currentSnapshot.hasSameUserState(as: snapshot) {
                DiagnosticLogStore.recordStateChange(
                    "points.icloud_export_skipped_same_state",
                    details: [
                        "local_total": snapshot.points.totalPoints.map { "\($0)" } ?? "nil",
                        "cloud_total": currentSnapshot.points.totalPoints.map { "\($0)" } ?? "nil",
                        "cloud_stamp": "\(current.stamp.modifiedAt.timeIntervalSince1970)"
                    ]
                )
                rememberPrimaryHandled(stamp: current.stamp, schemaVersion: current.schemaVersion)
                lastHandledPrimaryState = snapshot
                NativeICloudPreferences.clearPrimaryMutationPending(
                    ifCurrent: pendingMutationGeneration
                )
                return current
            }

            if NativeICloudPrimaryExportGuard.blocksAutomaticUpload(
                local: snapshot,
                remote: currentSnapshot
            ) {
                DiagnosticLogStore.recordWarning(
                    "points.icloud_export_blocked_empty_local_state",
                    details: [
                        "local_total": snapshot.points.totalPoints.map { "\($0)" } ?? "nil",
                        "remote_total": currentSnapshot.points.totalPoints.map { "\($0)" } ?? "nil",
                        "remote_stamp": "\(current.stamp.modifiedAt.timeIntervalSince1970)"
                    ]
                )
                return nil
            }
        }

        let payload = try JSONEncoder().encode(snapshot)
        let stamp = try await nextPrimaryLogicalStamp(after: try await latestValue(for: .primaryState))
        DiagnosticLogStore.recordStateChange(
            "points.icloud_export_begin",
            details: [
                "local_total": snapshot.points.totalPoints.map { "\($0)" } ?? "nil",
                "local_lifetime": snapshot.points.lifetimePoints.map { "\($0)" } ?? "nil",
                "logical_stamp": "\(stamp.modifiedAt.timeIntervalSinceReferenceDate)",
                "commit_id": String(stamp.commitID.uuidString.prefix(8))
            ]
        )
        let saved = try await saveLatest(domain: .primaryState, payload: payload, stamp: stamp)
        NativeICloudPreferences.clearPrimaryMutationPending(ifCurrent: pendingMutationGeneration)
        DiagnosticLogStore.recordStateChange(
            "points.icloud_export_saved",
            details: [
                "local_total": snapshot.points.totalPoints.map { "\($0)" } ?? "nil",
                "saved_logical_stamp": "\(saved.stamp.modifiedAt.timeIntervalSinceReferenceDate)",
                "commit_id": String(saved.stamp.commitID.uuidString.prefix(8))
            ]
        )
        return saved
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
        try await prepare()
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
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }
        let localSnapshot = NativeICloudPrimaryStateSnapshot.captureLocal()
        let hasPendingLocalMutation = NativeICloudPreferences.primaryPendingMutationGeneration != 0
        let localHasNewerUserChange = hasPendingLocalMutation || (
            latest.schemaVersion < NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion &&
            NativeICloudPrimaryConflictResolver.localChangeIsNewer(
                modifiedAt: NativeICloudPreferences.primaryLocalModifiedAt,
                than: latest.stamp
            )
        )
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
            "local_newer": String(localHasNewerUserChange),
            "pending_local_mutation": String(hasPendingLocalMutation),
            "cloud_schema": String(latest.schemaVersion),
            "history_count": String(decodedHistory.count),
            "history_repaired_latest": String(!snapshot.hasSameUserState(as: newestSnapshot))
        ]
        let needsProjection = !localSnapshot.hasSameUserState(as: snapshot) ||
            NativeICloudPrimaryLocalProjection.needsDailyRewardStateRepair(for: snapshot)
        let resolvedStateWasAlreadyHandled = NativeICloudPrimaryHandledStateResolver.contains(
            latestStamp: latest.stamp,
            latestSchemaVersion: latest.schemaVersion,
            resolvedState: snapshot,
            handledStamp: lastHandledPrimaryStamp,
            handledSchemaVersion: lastHandledPrimarySchemaVersion,
            handledState: lastHandledPrimaryState
        )
        if hasHandledPrimaryCommit(latest),
           !localHasNewerUserChange,
           (resolvedStateWasAlreadyHandled || !needsProjection) {
            DiagnosticLogStore.recordStateChange(
                "points.icloud_import_skipped_handled",
                details: importDetails
            )
            lastHandledPrimaryState = snapshot
            return false
        }

        // A local tap that has not reached CloudKit yet must not be replaced by a
        // delayed import. The scheduled exporter retains the dirty timestamp and
        // will publish that exact local commit.
        guard !localHasNewerUserChange else {
            DiagnosticLogStore.recordStateChange(
                "points.icloud_import_skipped_local_newer",
                details: importDetails
            )
            // An interactive widget can run while this process is still waiting
            // for its first CloudKit import. Keep the durable mutation marker and
            // retry the export after the import notification instead of allowing
            // the newly tapped task to remain local forever.
            if hasPendingLocalMutation {
                schedulePrimaryExport()
            }
            return false
        }

        // Import is deliberately one-way: it projects the resolved immutable
        // cloud history, then stops. In particular, an import must never create
        // another primary record. The former import/export feedback loop was the
        // source of repeated point jumps and task-state reversions.
        let didApplyProjection: Bool
        if needsProjection {
            DiagnosticLogStore.recordWarning(
                "points.icloud_import_applying",
                details: importDetails
            )
            try NativeICloudPrimaryLocalProjection.apply(snapshot, reloadWidgets: reloadWidgets)
            primaryProjectionRevision &+= 1
            didApplyProjection = true
        } else {
            DiagnosticLogStore.recordStateChange(
                "points.icloud_import_same_state",
                details: importDetails
            )
            didApplyProjection = false
        }
        rememberPrimaryHandled(stamp: latest.stamp, schemaVersion: latest.schemaVersion)
        lastHandledPrimaryState = snapshot
        return didApplyProjection
    }

    func beginObservingRemoteChanges() async throws {
        guard remoteChangeObserver == nil else { return }
        try await prepare()
        guard let coordinator = store?.persistentStoreCoordinator else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coordinator,
            queue: nil
        ) { _ in
            Task {
                await NativeICloudRuntime.shared.schedulePersistentStoreChangeImport()
            }
        }
    }

    /// Returns whether CloudKit confirmed an initial import. A device can already
    /// have a durable mirrored snapshot while Core Data keeps an import event open
    /// (or emits no import event when there is nothing new). That is not a sync
    /// failure and must not turn the user's enabled switch into an error state.
    func waitForInitialCloudImport(timeout: TimeInterval = 12) async throws -> Bool {
        let storeAlreadyHadPrimarySnapshot = try await readyStore().latestValue(
            for: .primaryState
        ) != nil
        if NativeICloudInitialImportReadiness.isReady(
            storeHasPrimarySnapshot: storeAlreadyHadPrimarySnapshot,
            observedImportForCurrentStore: hasCompletedInitialCloudImport
        ) {
            hasCompletedInitialCloudImport = true
            return true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !hasCompletedInitialCloudImport {
            if let latestCloudEventFailure {
                throw latestCloudEventFailure
            }
            if !storeAlreadyHadPrimarySnapshot,
               try await readyStore().latestValue(for: .primaryState) != nil {
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
        try? store?.unload()
        store = nil
        loadedAccountScopeIdentifier = nil
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

    private func schedulePersistentStoreChangeImport() {
        scheduledRemoteImportGeneration &+= 1
        let generation = scheduledRemoteImportGeneration
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard generation == scheduledRemoteImportGeneration else { return }
            await handlePersistentStoreChange()
        }
    }

    private func handlePersistentStoreChange() async {
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

    private func beginObservingCloudKitEventsIfNeeded() {
        guard cloudEventObserver == nil else { return }
        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { notification in
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
            Task {
                await NativeICloudRuntime.shared.handleCloudKitEvent(snapshot)
            }
        }
    }

    func handleCloudKitEvent(_ event: NativeICloudMirroringEvent) async {
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
        NotificationCenter.default.post(
            name: .nativeICloudRuntimeDidFail,
            object: nil,
            userInfo: ["error": error]
        )
    }
}

enum NativeICloudLocalChangeReporter {
    private static let lock = NSLock()
    private static var suppressionDepth = 0

    static func withReportingSuppressed<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        suppressionDepth += 1
        lock.unlock()
        defer {
            lock.lock()
            suppressionDepth = max(suppressionDepth - 1, 0)
            lock.unlock()
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
        guard NativeICloudPreferences.isEnabled else {
            return
        }
        _ = NativeICloudPreferences.markPrimaryMutationPending()
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
        lock.lock()
        defer { lock.unlock() }
        return suppressionDepth > 0
    }
}
