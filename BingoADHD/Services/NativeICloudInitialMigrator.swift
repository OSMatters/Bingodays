import Foundation

struct NativeICloudInitialMigrationResult: Equatable {
    let primaryDecision: NativeICloudInitialMigrationDecision
    let secondaryDecision: NativeICloudInitialMigrationDecision
}

enum NativeICloudInitialMigratorError: LocalizedError {
    case invalidPrimaryPayload
    case invalidSecondaryPayload

    var errorDescription: String? {
        switch self {
        case .invalidPrimaryPayload:
            return "The primary iCloud payload could not be decoded."
        case .invalidSecondaryPayload:
            return "The secondary iCloud payload could not be decoded."
        }
    }
}

protocol NativeICloudMigrationRuntime: Sendable {
    func primarySessionID() async -> UUID
    func values(for domain: NativeICloudDomain) async throws -> [NativeICloudEnvelopeValue]
    func latestValue(for domain: NativeICloudDomain) async throws -> NativeICloudEnvelopeValue?
    func exportPrimaryForInitialMigration(expectedSessionID: UUID?) async throws -> NativeICloudEnvelopeValue?
    func applyPrimaryForInitialMigration(_ snapshot: NativeICloudPrimaryStateSnapshot, stamp: NativeICloudCommitStamp, schemaVersion: Int64, expectedSessionID: UUID?, isExplicitAccountReplacement: Bool) async throws -> Bool
    func markPrimaryHandled(_ stamp: NativeICloudCommitStamp, schemaVersion: Int64, state: NativeICloudPrimaryStateSnapshot?) async
    func saveLatest(domain: NativeICloudDomain, payload: Data, stamp: NativeICloudCommitStamp?, expectedSessionID: UUID?) async throws -> NativeICloudEnvelopeValue
}

extension NativeICloudRuntime: NativeICloudMigrationRuntime {}

final class NativeICloudInitialMigrator {
    private let runtime: any NativeICloudMigrationRuntime
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let capturePrimary: @MainActor @Sendable () throws -> NativeICloudPrimaryStateSnapshot

    init(
        runtime: any NativeICloudMigrationRuntime = NativeICloudRuntime.shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        capturePrimary: @escaping @MainActor @Sendable () throws -> NativeICloudPrimaryStateSnapshot = {
            guard let local = BingoBoardStore.withBoardPersistenceLock({
                NativeICloudPrimaryStateSnapshot.captureLocal()
            }) else { throw NativeICloudLocalProjectionError.primaryProjectionFailed }
            return local
        }
    ) {
        self.runtime = runtime
        self.encoder = encoder
        self.decoder = decoder
        self.capturePrimary = capturePrimary
    }

    func migrate() async throws -> NativeICloudInitialMigrationResult {
        let sessionID = await runtime.primarySessionID()
        let primaryDecision = try await migratePrimaryState()
        guard await runtime.primarySessionID() == sessionID else { throw CancellationError() }
        let secondaryDecision = try await migrateSecondaryState()
        guard await runtime.primarySessionID() == sessionID else { throw CancellationError() }
        return NativeICloudInitialMigrationResult(
            primaryDecision: primaryDecision,
            secondaryDecision: secondaryDecision
        )
    }

    /// Applies only the current iCloud account's existing data. This is used
    /// after the user explicitly chooses that account during an account switch;
    /// it must never fall back to a local upload.
    func applyRemoteStateOnly() async throws {
        let sessionID = await runtime.primarySessionID()
        if let remote = try await resolvedPrimaryRemoteState() {
            _ = try await runtime.applyPrimaryForInitialMigration(
                remote.snapshot, stamp: remote.latestStamp, schemaVersion: remote.latestSchemaVersion,
                expectedSessionID: sessionID, isExplicitAccountReplacement: true
            )
        }

        if let remote = try await runtime.latestValue(for: .secondaryState) {
            guard await runtime.primarySessionID() == sessionID else { throw CancellationError() }
            guard let snapshot = try? decoder.decode(
                NativeICloudSecondaryStateSnapshot.self,
                from: remote.payload
            ) else {
                throw NativeICloudInitialMigratorError.invalidSecondaryPayload
            }
            try NativeICloudSecondaryLocalProjection.apply(snapshot)
        }
    }

    private func migratePrimaryState() async throws -> NativeICloudInitialMigrationDecision {
        let sessionID = await runtime.primarySessionID()
        let remote = try await resolvedPrimaryRemoteState()
        guard await runtime.primarySessionID() == sessionID else { throw CancellationError() }
        let local = try await capturePrimary()
        let remoteSnapshot = remote?.snapshot
        let decision = NativeICloudInitialMigrationPlanner.decide(
            localHasMeaningfulData: local.hasMeaningfulUserData,
            localIsSystemStarterGuideSeedData: local.isSystemStarterGuideSeedData,
            localModifiedAt: local.lastUserModifiedAt,
            remoteStamp: remote?.latestStamp,
            remoteHasMeaningfulData: remoteSnapshot?.hasMeaningfulUserData ?? false,
            isAccountBindingConfirmed: NativeICloudPreferences.accountScopeIdentifier != nil,
            remoteSchemaVersion: remote?.latestSchemaVersion ?? NativeICloudPrimaryEnvelopeSchema.legacyVersion,
            hasPendingLocalMutation: NativeICloudPreferences.primaryPendingMutationGeneration != 0
        )

        guard let remote else {
            guard decision == .uploadLocal else {
                DiagnosticLogStore.recordStateChange(
                    "icloud_migration_deferred_first_run_state",
                    details: ["is_starter_seed": "\(local.isSystemStarterGuideSeedData)"]
                )
                return .deferUpload
            }
            DiagnosticLogStore.recordWarning(
                "points.icloud_migration_upload_no_remote",
                details: [
                    "local_total": local.points.totalPoints.map { "\($0)" } ?? "nil",
                    "local_meaningful": "\(local.hasMeaningfulUserData)",
                    "local_modified": local.lastUserModifiedAt.map { "\($0.timeIntervalSince1970)" } ?? "nil"
                ]
            )
            // Sync is not marked enabled until the initial setup succeeds, so this
            // cannot go through exportPrimaryNow (which correctly refuses to run
            // before enablement). Store one exact initial local commit instead.
            _ = try await runtime.exportPrimaryForInitialMigration(expectedSessionID: sessionID)
            return .uploadLocal
        }
        guard let remoteSnapshot else {
            throw NativeICloudInitialMigratorError.invalidPrimaryPayload
        }

        let localHasNewerUserChange: Bool
        if remote.latestSchemaVersion >= NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion {
            localHasNewerUserChange = NativeICloudPreferences.primaryPendingMutationGeneration != 0
        } else {
            localHasNewerUserChange = NativeICloudPrimaryConflictResolver.localChangeIsNewer(
                modifiedAt: local.lastUserModifiedAt, than: remote.latestStamp
            )
        }
        let localModifiedText = local.lastUserModifiedAt.map { String($0.timeIntervalSince1970) } ?? "nil"
        let migrationDetails: [String: String] = [
            "local_total": local.points.totalPoints.map { "\($0)" } ?? "nil",
            "remote_total": remoteSnapshot.points.totalPoints.map { "\($0)" } ?? "nil",
            "local_meaningful": "\(local.hasMeaningfulUserData)",
            "local_modified": localModifiedText,
            "remote_stamp": "\(remote.latestStamp.modifiedAt.timeIntervalSince1970)",
            "remote_commit_id": String(remote.latestStamp.commitID.uuidString.prefix(8)),
            "remote_schema": String(remote.latestSchemaVersion),
            "local_newer": "\(localHasNewerUserChange)",
            "decision": "\(decision)"
        ]

        switch decision {
        case .uploadLocal:
            DiagnosticLogStore.recordWarning(
                "points.icloud_migration_upload_local",
                details: migrationDetails
            )
            // The local action is newer than the newest cloud commit. Publish that
            // exact state; do not synthesize a hybrid snapshot during setup.
            _ = try await runtime.exportPrimaryForInitialMigration(expectedSessionID: sessionID)
            return .uploadLocal
        case .applyRemote:
            if !local.hasSameUserState(as: remoteSnapshot) ||
                NativeICloudPrimaryLocalProjection.needsDailyRewardStateRepair(for: remoteSnapshot) {
                DiagnosticLogStore.recordWarning(
                    "points.icloud_migration_apply_remote",
                    details: migrationDetails
                )
            } else {
                DiagnosticLogStore.recordStateChange(
                    "points.icloud_migration_same_state",
                    details: migrationDetails
                )
            }

            let accepted = try await runtime.applyPrimaryForInitialMigration(
                remoteSnapshot, stamp: remote.latestStamp, schemaVersion: remote.latestSchemaVersion,
                expectedSessionID: sessionID, isExplicitAccountReplacement: false
            )
            if !accepted {
                _ = try await runtime.exportPrimaryForInitialMigration(expectedSessionID: sessionID)
                return .uploadLocal
            }
            return .applyRemote
        case .deferUpload:
            return .deferUpload
        }
    }

    private func resolvedPrimaryRemoteState() async throws -> ResolvedPrimaryRemoteState? {
        let values = try await runtime.values(for: .primaryState)
        guard let latest = values.last else { return nil }

        let decodedHistory = try values.map { value -> (NativeICloudEnvelopeValue, NativeICloudPrimaryStateSnapshot) in
            guard let snapshot = try? decoder.decode(
                NativeICloudPrimaryStateSnapshot.self,
                from: value.payload
            ) else {
                throw NativeICloudInitialMigratorError.invalidPrimaryPayload
            }
            return (value, snapshot)
        }
        guard let snapshot = NativeICloudPrimaryHistoryResolver.resolve(decodedHistory) else {
            throw NativeICloudInitialMigratorError.invalidPrimaryPayload
        }
        return ResolvedPrimaryRemoteState(
            latestStamp: latest.stamp,
            latestSchemaVersion: latest.schemaVersion,
            snapshot: snapshot
        )
    }

    private func migrateSecondaryState() async throws -> NativeICloudInitialMigrationDecision {
        let sessionID = await runtime.primarySessionID()
        let remote = try await runtime.latestValue(for: .secondaryState)
        guard await runtime.primarySessionID() == sessionID else { throw CancellationError() }
        let local = NativeICloudSecondaryStateSnapshot.captureLocal()
        let remoteSnapshot: NativeICloudSecondaryStateSnapshot?
        if let remote {
            guard let snapshot = try? decoder.decode(
                NativeICloudSecondaryStateSnapshot.self,
                from: remote.payload
            ) else {
                throw NativeICloudInitialMigratorError.invalidSecondaryPayload
            }
            remoteSnapshot = snapshot
        } else {
            remoteSnapshot = nil
        }
        let decision = NativeICloudInitialMigrationPlanner.decide(
            localHasMeaningfulData: local.hasMeaningfulUserData,
            localModifiedAt: local.lastUserModifiedAt,
            remoteStamp: remote?.stamp,
            remoteHasMeaningfulData: remoteSnapshot?.hasMeaningfulUserData ?? false
        )

        switch decision {
        case .uploadLocal:
            let payload = try encoder.encode(local)
            _ = try await runtime.saveLatest(domain: .secondaryState, payload: payload, stamp: nil, expectedSessionID: sessionID)
        case .applyRemote:
            guard remote != nil, let snapshot = remoteSnapshot else {
                throw NativeICloudInitialMigratorError.invalidSecondaryPayload
            }
            try NativeICloudSecondaryLocalProjection.apply(snapshot)
        case .deferUpload:
            break
        }
        return decision
    }

    private struct ResolvedPrimaryRemoteState {
        let latestStamp: NativeICloudCommitStamp
        let latestSchemaVersion: Int64
        let snapshot: NativeICloudPrimaryStateSnapshot
    }
}

enum NativeICloudSecondaryLocalProjection {
    static func apply(_ snapshot: NativeICloudSecondaryStateSnapshot) throws {
        guard snapshot.schemaVersion == NativeICloudSecondaryStateSnapshot.schemaVersion else {
            throw NativeICloudLocalProjectionError.unsupportedSecondarySchema(snapshot.schemaVersion)
        }

        let backup = NativeICloudSecondaryStateSnapshot.captureLocal()
        let didApply = NativeICloudLocalChangeReporter.withReportingSuppressed {
            applyWithoutRollback(snapshot)
        }
        guard didApply else {
            _ = NativeICloudLocalChangeReporter.withReportingSuppressed {
                applyWithoutRollback(backup)
            }
            throw NativeICloudLocalProjectionError.secondaryProjectionFailed
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .nativeICloudSecondaryProjectionDidChange,
                object: nil
            )
        }
    }

    private static func applyWithoutRollback(_ snapshot: NativeICloudSecondaryStateSnapshot) -> Bool {
        CommonTasksStore.saveLibrary(snapshot.taskLibrary) &&
            TaskHistoryStore.save(snapshot.taskHistory) &&
            TaskCompletionHistoryStore.save(
                TaskCompletionHistoryStore.mergedWithLocal(snapshot.taskCompletionHistory)
            )
    }
}
