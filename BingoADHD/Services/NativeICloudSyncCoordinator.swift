import CloudKit
import Combine
import Foundation

enum NativeICloudAccountChangePlanner {
    enum Resolution: Equatable {
        case keepLocalOnly
        case useCurrentAccountCloud
        case copyLocalDataToEmptyCurrentAccount
    }

    enum RemoteDataAvailability: Equatable {
        case present
        case empty
        case unknown
    }

    static func allows(
        _ resolution: Resolution,
        localHasMeaningfulData: Bool,
        remoteDataAvailability: RemoteDataAvailability
    ) -> Bool {
        switch resolution {
        case .keepLocalOnly:
            return true
        case .useCurrentAccountCloud:
            return remoteDataAvailability == .present
        case .copyLocalDataToEmptyCurrentAccount:
            return localHasMeaningfulData && remoteDataAvailability == .empty
        }
    }
}

@MainActor
final class NativeICloudSyncCoordinator: ObservableObject {
    struct AccountChange: Equatable {
        let previousAccountScope: String
        let currentAccountScope: String
        let localHasMeaningfulData: Bool
        let remoteDataAvailability: NativeICloudAccountChangePlanner.RemoteDataAvailability
    }

    enum AccountChangeResolution: Equatable {
        /// Leaves the existing device data in place and keeps sync off.
        case keepLocalOnly
        /// Replaces this device with the current iCloud account's existing data.
        case useCurrentAccountCloud
        /// Copies local data only when the current account has no Bingodays data.
        case copyLocalDataToEmptyCurrentAccount

        fileprivate var plannerResolution: NativeICloudAccountChangePlanner.Resolution {
            switch self {
            case .keepLocalOnly:
                return .keepLocalOnly
            case .useCurrentAccountCloud:
                return .useCurrentAccountCloud
            case .copyLocalDataToEmptyCurrentAccount:
                return .copyLocalDataToEmptyCurrentAccount
            }
        }
    }

    enum State: Equatable {
        case disabled
        case preparing
        case syncing
        case waitingForCloud(lastCheckedAt: Date)
        case ready(lastSyncAt: Date?)
        case accountChangeRequiresDecision
        case unavailable(message: String)
        case failed(message: String)
    }

    static let shared = NativeICloudSyncCoordinator()

    @Published private(set) var state: State = NativeICloudPreferences.isEnabled ? .preparing : .disabled
    @Published private(set) var pendingAccountChange: AccountChange?

    private let runtime: NativeICloudRuntime
    private final class RuntimeObservation {
        var tokens: [NSObjectProtocol] = []
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
    private let runtimeObservation = RuntimeObservation()
    private var lastHandledSecondaryStamp: NativeICloudCommitStamp?
    private var startTask: Task<Void, Never>?
    private var foregroundRetryTask: Task<Void, Never>?
    private var isInitialMigrationInFlight = false

    init(runtime: NativeICloudRuntime = .shared) {
        self.runtime = runtime
        observeRuntime()
    }

    private static var initializesDevelopmentSchema: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    deinit {
        startTask?.cancel()
        foregroundRetryTask?.cancel()
    }

    func startIfEnabled() {
        guard NativeICloudPreferences.isEnabled else {
            state = .disabled
            return
        }
        guard startTask == nil else { return }
        state = .preparing
        startTask = Task { [weak self] in
            await self?.start()
            self?.startTask = nil
        }
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            do {
                let accountScope = try await NativeICloudAccountScope.currentIdentifier()
                if let previousAccountScope = NativeICloudPreferences.accountScopeIdentifier,
                   previousAccountScope != accountScope {
                    await prepareAccountChange(
                        previousAccountScope: previousAccountScope,
                        currentAccountScope: accountScope
                    )
                    return
                }
            } catch {
                state = .failed(message: NativeICloudErrorFormatter.describe(error))
                AnalyticsService.logICloudSyncResult(
                    operation: .enable,
                    result: .failed,
                    failureStage: "account_scope"
                )
                return
            }
            state = .preparing
            await start(enableAfterSuccess: true)
        } else {
            foregroundRetryTask?.cancel()
            NativeICloudPreferences.isEnabled = false
            await runtime.shutdown()
            lastHandledSecondaryStamp = nil
            state = .disabled
            AnalyticsService.logICloudSyncToggled(isEnabled: false)
        }
    }

    func resolveAccountChange(_ resolution: AccountChangeResolution) async {
        guard let change = pendingAccountChange else { return }

        guard NativeICloudAccountChangePlanner.allows(
            resolution.plannerResolution,
            localHasMeaningfulData: change.localHasMeaningfulData,
            remoteDataAvailability: change.remoteDataAvailability
        ) else {
            state = .unavailable(message: accountChangeResolutionUnavailableMessage(for: resolution))
            return
        }

        switch resolution {
        case .keepLocalOnly:
            NativeICloudPreferences.isEnabled = false
            pendingAccountChange = nil
            state = .disabled

        case .useCurrentAccountCloud:
            await useCurrentAccountCloud(change)

        case .copyLocalDataToEmptyCurrentAccount:
            await copyLocalDataToEmptyCurrentAccount(change)
        }
    }

    func syncNow() async {
        guard NativeICloudPreferences.isEnabled else { return }
        foregroundRetryTask?.cancel()
        state = .syncing
        do {
            try await runtime.prepare(
                initializeDevelopmentSchema: Self.initializesDevelopmentSchema
            )
            try await runtime.beginObservingRemoteChanges()
            let completedInitialImport = try await runtime.waitForInitialCloudImport()
            guard completedInitialImport else {
                state = .waitingForCloud(lastCheckedAt: .now)
                AnalyticsService.logICloudSyncResult(operation: .manualSync, result: .waiting)
                return
            }
            let checkpoint = await runtime.cloudActivityCheckpoint()
            let flushedLocalChange = try await runtime.flushScheduledPrimaryExport()
            let importedImmediately = try await runtime.importPrimaryIfNeeded()
            try await importSecondaryIfNeeded()
            if importedImmediately {
                state = .ready(lastSyncAt: .now)
                AnalyticsService.logICloudSyncResult(operation: .manualSync, result: .success)
                return
            }

            let expectedKinds: Set<NativeICloudMirroringEvent.Kind> = flushedLocalChange
                ? [.exportData, .importData]
                : [.importData]
            let event = try await runtime.waitForFinishedCloudActivity(
                after: checkpoint,
                expectedKinds: expectedKinds,
                timeout: 12
            )
            let importedAfterWait = try await runtime.importPrimaryIfNeeded()
            try await importSecondaryIfNeeded()
            if let event {
                state = .ready(lastSyncAt: event.occurredAt)
                AnalyticsService.logICloudSyncResult(operation: .manualSync, result: .success)
            } else if importedAfterWait {
                state = .ready(lastSyncAt: .now)
                AnalyticsService.logICloudSyncResult(operation: .manualSync, result: .success)
            } else {
                DiagnosticLogStore.recordStateChange(
                    "icloud.manual_sync_waiting_for_system",
                    details: ["flushed_local_change": String(flushedLocalChange)]
                )
                state = .waitingForCloud(lastCheckedAt: .now)
                AnalyticsService.logICloudSyncResult(operation: .manualSync, result: .waiting)
            }
        } catch {
            state = .failed(message: NativeICloudErrorFormatter.describe(error))
            AnalyticsService.logICloudSyncResult(
                operation: .manualSync,
                result: .failed,
                failureStage: "sync"
            )
        }
    }

    func refreshWhenAppBecomesActive() async {
        guard NativeICloudPreferences.isEnabled else { return }
        do {
            try await runtime.prepare(
                initializeDevelopmentSchema: Self.initializesDevelopmentSchema
            )
            try await runtime.beginObservingRemoteChanges()
            let completedInitialImport = try await runtime.waitForInitialCloudImport()
            guard completedInitialImport else {
                state = .syncing
                return
            }
            let imported = try await runtime.importPrimaryIfNeeded()
            try await importSecondaryIfNeeded()
            if imported {
                state = .ready(lastSyncAt: .now)
            } else if case .waitingForCloud = state {
                // Preserve the truthful waiting state until CloudKit reports an
                // operation or a retry actually applies remote data.
            } else {
                state = .ready(lastSyncAt: await runtime.latestSuccessfulCloudEventDate())
            }
            scheduleForegroundImportRetries()
        } catch {
            state = .failed(message: NativeICloudErrorFormatter.describe(error))
        }
    }

    private func scheduleForegroundImportRetries() {
        foregroundRetryTask?.cancel()
        foregroundRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in [2.0, 5.0, 10.0] {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    try Task.checkCancellation()
                    let imported = try await self.runtime.importPrimaryIfNeeded()
                    try await self.importSecondaryIfNeeded()
                    if imported {
                        self.state = .ready(lastSyncAt: .now)
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.state = .failed(message: NativeICloudErrorFormatter.describe(error))
                    return
                }
            }
        }
    }

    private func start(enableAfterSuccess: Bool = false) async {
        do {
            let accountStatus = try await CKContainer(
                identifier: NativeICloudConfiguration.containerIdentifier
            ).accountStatus()
            guard accountStatus == .available else {
                if enableAfterSuccess {
                    NativeICloudPreferences.isEnabled = false
                    AnalyticsService.logICloudSyncResult(
                        operation: .enable,
                        result: .failed,
                        failureStage: "account_unavailable"
                    )
                }
                state = .unavailable(message: accountStatusMessage(accountStatus))
                return
            }

            let accountScope = try await NativeICloudAccountScope.currentIdentifier()
            if !enableAfterSuccess,
               NativeICloudPreferences.accountScopeIdentifier != accountScope {
                if let previousAccountScope = NativeICloudPreferences.accountScopeIdentifier {
                    await prepareAccountChange(
                        previousAccountScope: previousAccountScope,
                        currentAccountScope: accountScope
                    )
                } else {
                    NativeICloudPreferences.isEnabled = false
                    await runtime.shutdown()
                    state = .disabled
                }
                return
            }

            try await runtime.prepare(
                accountScopeIdentifier: accountScope,
                allowsUnconfirmedAccountChange: enableAfterSuccess,
                initializeDevelopmentSchema: Self.initializesDevelopmentSchema
            )
            try await runtime.beginObservingRemoteChanges()
            let completedInitialImport = try await runtime.waitForInitialCloudImport()
            // A Core Data cache can contain an older local mirror before its first
            // CloudKit import completes. Do not migrate or export it yet; doing so
            // is how an offline iPad reset could overwrite today's iPhone tasks.
            guard completedInitialImport else {
                if enableAfterSuccess {
                    NativeICloudPreferences.accountScopeIdentifier = accountScope
                    NativeICloudPreferences.isEnabled = true
                    AnalyticsService.logICloudSyncToggled(isEnabled: true)
                    AnalyticsService.logICloudSyncResult(operation: .enable, result: .waiting)
                }
                state = .syncing
                return
            }
            _ = try await migrateInitialStateIfNeeded()
            if enableAfterSuccess {
                NativeICloudPreferences.accountScopeIdentifier = accountScope
                NativeICloudPreferences.isEnabled = true
                AnalyticsService.logICloudSyncToggled(isEnabled: true)
                AnalyticsService.logICloudSyncResult(operation: .enable, result: .success)
            }
            if completedInitialImport,
               let cloudEventDate = await runtime.latestSuccessfulCloudEventDate() {
                state = .ready(lastSyncAt: cloudEventDate)
            } else {
                state = .syncing
            }
        } catch {
            if enableAfterSuccess {
                NativeICloudPreferences.isEnabled = false
                AnalyticsService.logICloudSyncResult(
                    operation: .enable,
                    result: .failed,
                    failureStage: "setup"
                )
            }
            state = .failed(message: NativeICloudErrorFormatter.describe(error))
        }
    }

    private func prepareAccountChange(
        previousAccountScope: String,
        currentAccountScope: String
    ) async {
        NativeICloudPreferences.isEnabled = false
        await runtime.shutdown()
        state = .preparing

        let localHasMeaningfulData = NativeICloudPrimaryStateSnapshot.captureLocal().hasMeaningfulUserData ||
            NativeICloudSecondaryStateSnapshot.captureLocal().hasMeaningfulUserData
        let remoteDataAvailability: NativeICloudAccountChangePlanner.RemoteDataAvailability

        do {
            try await runtime.prepare(
                accountScopeIdentifier: currentAccountScope,
                allowsUnconfirmedAccountChange: true,
                initializeDevelopmentSchema: Self.initializesDevelopmentSchema
            )
            try await runtime.beginObservingRemoteChanges()
            let completedInitialImport = try await runtime.waitForInitialCloudImport()
            if completedInitialImport {
                let hasPrimary = try await runtime.latestValue(for: .primaryState) != nil
                let hasSecondary = try await runtime.latestValue(for: .secondaryState) != nil
                // A secondary-only record cannot safely replace the complete
                // account state, nor can it be overwritten by a cross-account
                // copy. Treat it as unknown until a complete account migration
                // flow is introduced.
                remoteDataAvailability = hasPrimary ? .present : (hasSecondary ? .unknown : .empty)
            } else {
                remoteDataAvailability = .unknown
            }
        } catch {
            remoteDataAvailability = .unknown
        }

        await runtime.shutdown()
        pendingAccountChange = AccountChange(
            previousAccountScope: previousAccountScope,
            currentAccountScope: currentAccountScope,
            localHasMeaningfulData: localHasMeaningfulData,
            remoteDataAvailability: remoteDataAvailability
        )
        state = .accountChangeRequiresDecision
    }

    private func useCurrentAccountCloud(_ change: AccountChange) async {
        state = .preparing
        do {
            try await runtime.prepare(
                accountScopeIdentifier: change.currentAccountScope,
                allowsUnconfirmedAccountChange: true,
                initializeDevelopmentSchema: Self.initializesDevelopmentSchema
            )
            try await runtime.beginObservingRemoteChanges()
            guard try await runtime.waitForInitialCloudImport() else {
                state = .waitingForCloud(lastCheckedAt: .now)
                return
            }
            try await NativeICloudInitialMigrator(runtime: runtime).applyRemoteStateOnly()
            NativeICloudPreferences.accountScopeIdentifier = change.currentAccountScope
            NativeICloudPreferences.isEnabled = true
            pendingAccountChange = nil
            state = .ready(lastSyncAt: await runtime.latestSuccessfulCloudEventDate())
        } catch {
            NativeICloudPreferences.isEnabled = false
            state = .failed(message: NativeICloudErrorFormatter.describe(error))
        }
    }

    private func copyLocalDataToEmptyCurrentAccount(_ change: AccountChange) async {
        let localPrimary = NativeICloudPrimaryStateSnapshot.captureLocal()
        let localSecondary = NativeICloudSecondaryStateSnapshot.captureLocal()
        guard localPrimary.hasMeaningfulUserData || localSecondary.hasMeaningfulUserData else {
            state = .unavailable(message: "There is no local Bingodays data to copy to this iCloud account.")
            return
        }

        state = .preparing
        do {
            try await runtime.prepare(
                accountScopeIdentifier: change.currentAccountScope,
                allowsUnconfirmedAccountChange: true,
                initializeDevelopmentSchema: Self.initializesDevelopmentSchema
            )
            try await runtime.beginObservingRemoteChanges()
            guard try await runtime.waitForInitialCloudImport() else {
                state = .waitingForCloud(lastCheckedAt: .now)
                return
            }
            guard try await runtime.latestValue(for: .primaryState) == nil,
                  try await runtime.latestValue(for: .secondaryState) == nil else {
                state = .unavailable(
                    message: "This iCloud account received Bingodays data while preparing and was left unchanged."
                )
                return
            }

            _ = try await runtime.saveLatest(
                domain: .primaryState,
                payload: try JSONEncoder().encode(localPrimary)
            )
            _ = try await runtime.saveLatest(
                domain: .secondaryState,
                payload: try JSONEncoder().encode(localSecondary)
            )
            NativeICloudPreferences.accountScopeIdentifier = change.currentAccountScope
            NativeICloudPreferences.isEnabled = true
            pendingAccountChange = nil
            state = .ready(lastSyncAt: .now)
        } catch {
            NativeICloudPreferences.isEnabled = false
            state = .failed(message: NativeICloudErrorFormatter.describe(error))
        }
    }

    private func accountChangeResolutionUnavailableMessage(
        for resolution: AccountChangeResolution
    ) -> String {
        switch resolution {
        case .keepLocalOnly:
            return ""
        case .useCurrentAccountCloud:
            return "No Bingodays iCloud data is available for this account. Keep this device's data or copy it explicitly."
        case .copyLocalDataToEmptyCurrentAccount:
            return "This iCloud account already has Bingodays data, or this device has no data to copy. Nothing was changed."
        }
    }

    private func observeRuntime() {
        let center = NotificationCenter.default
        runtimeObservation.tokens.append(
            center.addObserver(
                forName: .nativeICloudRuntimeEventDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = notification.userInfo?["event"] as? NativeICloudMirroringEvent else {
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !event.isFinished {
                        self.state = event.kind == .setup ? .preparing : .syncing
                    } else if event.succeeded {
                        self.state = .ready(lastSyncAt: event.occurredAt)
                    }
                }
            }
        )
        runtimeObservation.tokens.append(
            center.addObserver(
                forName: .nativeICloudRuntimeDidImport,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let completedInitialImport = try await self.runtime.waitForInitialCloudImport(
                            timeout: 0
                        )
                        if completedInitialImport {
                            _ = try await self.migrateInitialStateIfNeeded()
                        }
                        try await self.importSecondaryIfNeeded()
                        self.state = .ready(lastSyncAt: .now)
                    } catch {
                        self.state = .failed(message: NativeICloudErrorFormatter.describe(error))
                    }
                }
            }
        )
        runtimeObservation.tokens.append(
            center.addObserver(
                forName: .nativeICloudSecondaryLocalChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await self.exportSecondaryNow()
                        self.state = .ready(lastSyncAt: .now)
                    } catch {
                        self.state = .failed(message: NativeICloudErrorFormatter.describe(error))
                    }
                }
            }
        )
        runtimeObservation.tokens.append(
            center.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, NativeICloudPreferences.isEnabled else { return }
                    await self.runtime.shutdown()
                    self.lastHandledSecondaryStamp = nil
                    self.state = .preparing
                    await self.start()
                }
            }
        )
        runtimeObservation.tokens.append(
            center.addObserver(
                forName: .nativeICloudRuntimeDidFail,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let error = notification.userInfo?["error"] as? Error
                Task { @MainActor [weak self] in
                    self?.state = .failed(
                        message: error.map(NativeICloudErrorFormatter.describe) ?? "iCloud sync failed."
                    )
                }
            }
        )
    }

    /// Setup imports can post more than one notification. There must be exactly
    /// one initial migration/export transaction for a given prepared store;
    /// otherwise a first-run snapshot can be committed twice before the account
    /// binding is finalized.
    private func migrateInitialStateIfNeeded() async throws -> Bool {
        guard !isInitialMigrationInFlight else { return false }
        isInitialMigrationInFlight = true
        defer { isInitialMigrationInFlight = false }
        let migration = NativeICloudInitialMigrator(runtime: runtime)
        _ = try await migration.migrate()
        return true
    }

    private func importSecondaryIfNeeded() async throws {
        guard let latest = try await runtime.latestValue(for: .secondaryState) else { return }
        if let lastHandledSecondaryStamp, latest.stamp <= lastHandledSecondaryStamp {
            return
        }
        let snapshot = try JSONDecoder().decode(NativeICloudSecondaryStateSnapshot.self, from: latest.payload)
        try NativeICloudSecondaryLocalProjection.apply(snapshot)
        lastHandledSecondaryStamp = latest.stamp
    }

    private func exportSecondaryNow() async throws {
        let snapshot = NativeICloudSecondaryStateSnapshot.captureLocal()
        let payload = try JSONEncoder().encode(snapshot)
        let saved = try await runtime.saveLatest(domain: .secondaryState, payload: payload)
        lastHandledSecondaryStamp = saved.stamp
    }

    private func accountStatusMessage(_ status: CKAccountStatus) -> String {
        switch status {
        case .noAccount:
            return "No iCloud account is signed in on this device."
        case .restricted:
            return "iCloud access is restricted on this device."
        case .couldNotDetermine:
            return "The iCloud account status could not be determined."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable."
        case .available:
            return ""
        @unknown default:
            return "iCloud is unavailable."
        }
    }
}
