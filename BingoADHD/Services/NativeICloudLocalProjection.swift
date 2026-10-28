import Foundation

extension Notification.Name {
    static let nativeICloudPrimaryProjectionDidChange = Notification.Name(
        "NativeICloudPrimaryProjectionDidChange"
    )
    static let nativeICloudSecondaryProjectionDidChange = Notification.Name(
        "NativeICloudSecondaryProjectionDidChange"
    )
}

/// Serializes primary-state projection with foreground task mutations inside a
/// process. CloudKit callbacks run on background tasks, while task taps mutate the
/// same App Group files synchronously; allowing both at once can make a successful
/// board write fail its verification and expose an older points snapshot.
enum NativeICloudPrimaryMutationGate {
    private static let lock = NSRecursiveLock()

    static func acquire() {
        lock.lock()
    }

    static func release() {
        lock.unlock()
    }
}

struct NativeICloudPrimaryProjectionCommitResult {
    let localSnapshot: NativeICloudPrimaryStateSnapshot
    let hasPendingLocalMutation: Bool
    let localHasNewerUserChange: Bool
    let needsProjection: Bool
    let didSkipHandledCommit: Bool
    let didApply: Bool
}

enum NativeICloudLocalProjectionError: LocalizedError {
    case unsupportedPrimarySchema(Int)
    case invalidPrimarySnapshot
    case primaryProjectionFailed
    case unsupportedSecondarySchema(Int)
    case secondaryProjectionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedPrimarySchema(let version):
            return "Unsupported primary iCloud data schema: \(version)."
        case .invalidPrimarySnapshot:
            return "The primary iCloud data is incomplete."
        case .primaryProjectionFailed:
            return "The primary iCloud data could not be applied locally."
        case .unsupportedSecondarySchema(let version):
            return "Unsupported secondary iCloud data schema: \(version)."
        case .secondaryProjectionFailed:
            return "The secondary iCloud data could not be applied locally."
        }
    }
}

enum NativeICloudPrimaryLocalProjection {
    static func needsDailyRewardStateRepair(
        for snapshot: NativeICloudPrimaryStateSnapshot,
        referenceDate: Date = .now,
        reading mode: PersistenceReadMode = .readOnly
    ) -> Bool {
        guard snapshot.schemaVersion == NativeICloudPrimaryStateSnapshot.schemaVersion else {
            return false
        }
        let preferredSelection = BingoBoardStore.loadNamedBoardsSnapshot(
            repairingPersistence: false
        ).selectedBoardID
        let selectedID = preferredSelection.flatMap { candidate in
            snapshot.boards.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? snapshot.boards.first?.id
        guard let selectedID,
              let selectedBoard = snapshot.boards.first(where: { $0.id == selectedID }) else {
            return false
        }
        return PointsStore.loadPersistenceSnapshot(reading: mode) != localPointsSnapshot(
            from: snapshot.points,
            selectedBoard: selectedBoard,
            referenceDate: referenceDate
        )
    }

    @MainActor
    static func apply(
        _ snapshot: NativeICloudPrimaryStateSnapshot,
        reloadWidgets: Bool = true
    ) throws {
        guard let outcome = BingoBoardStore.withBoardPersistenceLock({
            Result { try applyUnderPersistenceLock(snapshot, reloadWidgets: reloadWidgets) }
        }) else {
            throw NativeICloudLocalProjectionError.primaryProjectionFailed
        }
        try outcome.get()
    }

    /// A CloudKit callback can arrive on a background executor while SwiftUI is
    /// processing UserDefaults notifications. Keep the whole local decision and
    /// commit on the main actor so neither side waits on the other's lock.
    @MainActor
    static func applyIfCurrent(
        _ snapshot: NativeICloudPrimaryStateSnapshot,
        latestStamp: NativeICloudCommitStamp,
        latestSchemaVersion: Int64,
        hasHandledLatestCommit: Bool,
        resolvedStateWasAlreadyHandled: Bool,
        reloadWidgets: Bool = true,
        accountScope: String? = nil,
        session: NativeICloudPrimarySession? = nil,
        sessionID: UUID? = nil,
        allowsDisabledSync: Bool = false,
        isExplicitAccountReplacement: Bool = false
    ) throws -> NativeICloudPrimaryProjectionCommitResult {
        guard let outcome = BingoBoardStore.withBoardPersistenceLock({
            Result {
                if let session, let sessionID {
                    guard session.matches(sessionID),
                          allowsDisabledSync || NativeICloudPreferences.isEnabled,
                          NativeICloudPreferences.accountScopeIdentifier == accountScope ||
                            (allowsDisabledSync && NativeICloudPreferences.accountScopeIdentifier == nil) ||
                            isExplicitAccountReplacement else {
                        throw CancellationError()
                    }
                }
                let localSnapshot = NativeICloudPrimaryStateSnapshot.captureLocal()
                let checkpoint = accountScope.map { NativeICloudPreferences.primaryCheckpoint(for: $0) }
                let version = NativeICloudPrimaryCommitVersion(stamp: latestStamp, schemaVersion: latestSchemaVersion)
                if !isExplicitAccountReplacement, checkpoint?.shouldReject(version) == true {
                    return NativeICloudPrimaryProjectionCommitResult(
                        localSnapshot: localSnapshot,
                        hasPendingLocalMutation: checkpoint?.hasPendingMutation ?? false,
                        localHasNewerUserChange: false, needsProjection: false,
                        didSkipHandledCommit: true, didApply: false
                    )
                }
                let hasPendingLocalMutation = checkpoint?.hasPendingMutation ??
                    (NativeICloudPreferences.primaryPendingMutationGeneration != 0)
                let localHasNewerUserChange = !isExplicitAccountReplacement && (hasPendingLocalMutation || (
                    latestSchemaVersion < NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion &&
                    NativeICloudPrimaryConflictResolver.localChangeIsNewer(
                        modifiedAt: NativeICloudPreferences.primaryLocalModifiedAt,
                        than: latestStamp
                    )
                ))
                let needsProjection = !localSnapshot.hasSameUserState(as: snapshot) ||
                    needsDailyRewardStateRepair(for: snapshot)

                guard !localHasNewerUserChange else {
                    return NativeICloudPrimaryProjectionCommitResult(
                        localSnapshot: localSnapshot,
                        hasPendingLocalMutation: hasPendingLocalMutation,
                        localHasNewerUserChange: true,
                        needsProjection: needsProjection,
                        didSkipHandledCommit: false,
                        didApply: false
                    )
                }

                // Preserve the previous import behavior for a commit already
                // acknowledged by this runtime. In particular, do not turn a
                // duplicate import into a repair write just because its local
                // mirrors have drifted.
                if hasHandledLatestCommit &&
                    (resolvedStateWasAlreadyHandled || !needsProjection) {
                    return NativeICloudPrimaryProjectionCommitResult(
                        localSnapshot: localSnapshot,
                        hasPendingLocalMutation: hasPendingLocalMutation,
                        localHasNewerUserChange: false,
                        needsProjection: needsProjection,
                        didSkipHandledCommit: true,
                        didApply: false
                    )
                }

                if needsProjection {
                    try applyUnderPersistenceLock(snapshot, reloadWidgets: reloadWidgets)
                }
                if let accountScope {
                    var accepted = NativeICloudPreferences.primaryCheckpoint(for: accountScope)
                    if isExplicitAccountReplacement { accepted.acknowledge(accepted.localRevision) }
                    accepted.accept(version)
                    guard NativeICloudPreferences.savePrimaryCheckpoint(accepted, for: accountScope) else {
                        throw NativeICloudLocalProjectionError.primaryProjectionFailed
                    }
                }

                return NativeICloudPrimaryProjectionCommitResult(
                    localSnapshot: localSnapshot,
                    hasPendingLocalMutation: hasPendingLocalMutation,
                    localHasNewerUserChange: false,
                    needsProjection: needsProjection,
                    didSkipHandledCommit: false,
                    didApply: needsProjection
                )
            }
        }) else {
            throw NativeICloudLocalProjectionError.primaryProjectionFailed
        }
        return try outcome.get()
    }

    @MainActor
    static func applyOnMainActor(
        _ snapshot: NativeICloudPrimaryStateSnapshot,
        reloadWidgets: Bool = true
    ) throws {
        try apply(snapshot, reloadWidgets: reloadWidgets)
    }

    private static func applyUnderPersistenceLock(
        _ snapshot: NativeICloudPrimaryStateSnapshot,
        reloadWidgets: Bool
    ) throws {
        NativeICloudPrimaryMutationGate.acquire()
        defer { NativeICloudPrimaryMutationGate.release() }

        guard snapshot.schemaVersion == NativeICloudPrimaryStateSnapshot.schemaVersion else {
            throw NativeICloudLocalProjectionError.unsupportedPrimarySchema(snapshot.schemaVersion)
        }
        guard !snapshot.boards.isEmpty else {
            throw NativeICloudLocalProjectionError.invalidPrimarySnapshot
        }

        let backup = NativeICloudPrimaryStateSnapshot.captureLocal()
        let previousSelection = BingoBoardStore.loadNamedBoardsSnapshot().selectedBoardID
        let didApply = NativeICloudLocalChangeReporter.withReportingSuppressed {
            applyWithoutRollback(snapshot, preferredSelection: previousSelection)
        }
        guard didApply else {
            _ = NativeICloudLocalChangeReporter.withReportingSuppressed {
                applyWithoutRollback(backup, preferredSelection: previousSelection)
            }
            throw NativeICloudLocalProjectionError.primaryProjectionFailed
        }

        let beforeBoards = Dictionary(backup.boards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var completed = 0
        var undone = 0
        var changedIDs: [String] = []
        for board in snapshot.boards {
            guard let previous = beforeBoards[board.id] else { continue }
            let beforeCells = Dictionary(
                BoardEngine.expandedBoardCache(from: previous.board).flatMap { $0 }.map { ($0.id, $0.isCompleted) },
                uniquingKeysWith: { first, _ in first }
            )
            for cell in BoardEngine.expandedBoardCache(from: board.board).flatMap({ $0 }) {
                guard let wasCompleted = beforeCells[cell.id], wasCompleted != cell.isCompleted else { continue }
                if cell.isCompleted { completed += 1 } else { undone += 1 }
                if changedIDs.count < 10 { changedIDs.append(String(cell.id.uuidString.prefix(8))) }
            }
        }
        if completed + undone > 0 {
            DiagnosticLogStore.recordStateChange("points.icloud_projection_task_changes", details: [
                "completed": String(completed), "undone": String(undone),
                "cell_ids": changedIDs.joined(separator: ",")
            ])
        }

        if reloadWidgets {
            BingoBoardStore.reloadICloudWidgetTimelines()
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .nativeICloudPrimaryProjectionDidChange, object: nil)
        }
    }

    private static func applyWithoutRollback(
        _ snapshot: NativeICloudPrimaryStateSnapshot,
        preferredSelection: UUID?
    ) -> Bool {
        guard !snapshot.boards.isEmpty else { return false }

        let selectedID = preferredSelection.flatMap { candidate in
            snapshot.boards.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? snapshot.boards.first?.id
        guard let selectedID,
              let selectedBoard = snapshot.boards.first(where: { $0.id == selectedID }) else {
            return false
        }

        // `DailyRewardState` is an anti-duplication ledger for the board shown on
        // this device, not an account-wide score. It must be rebuilt from the
        // selected board after every cloud projection. Applying the other device's
        // ledger is what allowed an empty iPad board to subtract a completed iPhone
        // board's tasks on the next save.
        let projectedPoints = localPointsSnapshot(
            from: snapshot.points,
            selectedBoard: selectedBoard,
            referenceDate: .now
        )
        let pointsBeforeProjection = PointsStore.loadPersistenceSnapshot()
        DiagnosticLogStore.recordWarning(
            "points.icloud_projection_begin",
            details: [
                "before_total": pointsBeforeProjection.totalPoints.map { "\($0)" } ?? "nil",
                "incoming_total": projectedPoints.totalPoints.map { "\($0)" } ?? "nil",
                "before_lifetime": pointsBeforeProjection.lifetimePoints.map { "\($0)" } ?? "nil",
                "incoming_lifetime": projectedPoints.lifetimePoints.map { "\($0)" } ?? "nil"
            ]
        )

        guard PointsStore.replacePersistenceSnapshot(projectedPoints),
              BingoDiaryStore.replaceAllEntriesDictionary(snapshot.diaryEntries),
              BingoTimeoutStore.replacePayload(snapshot.timeoutPayload),
              RewardStore.saveRewards(snapshot.customRewards, source: "icloud_projection"),
              PointRedemptionHistoryStore.save(snapshot.redemptionHistory),
              StickerStore.saveInventoryCounts(stickerInventory(from: snapshot.stickerInventory)),
              StickerStore.savePlacements(snapshot.stickerPlacements) else {
            DiagnosticLogStore.recordWarning(
                "points.icloud_projection_failed",
                details: [
                    "target_total": projectedPoints.totalPoints.map { "\($0)" } ?? "nil"
                ]
            )
            return false
        }
        let pointsAfterProjection = PointsStore.loadPersistenceSnapshot()
        DiagnosticLogStore.recordStateChange(
            "points.icloud_projection_saved",
            details: [
                "after_total": pointsAfterProjection.totalPoints.map { "\($0)" } ?? "nil",
                "after_lifetime": pointsAfterProjection.lifetimePoints.map { "\($0)" } ?? "nil"
            ]
        )

        let namedSnapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedID,
            boards: snapshot.boards,
            deletedBoardIDs: snapshot.effectiveDeletedBoardIDs,
            protectedBoardID: snapshot.effectiveProtectedBoardID,
            boardOrderModifiedAt: snapshot.boardOrderModifiedAt
        )
        // Applying an already-resolved cloud snapshot (including rollback) is a
        // definition replacement, not an ordinary completion/status write.
        let localBoards = BingoBoardStore.loadNamedBoardsSnapshot().boards
        var authorizedRuleChanges = Dictionary(snapshot.boards.map { incoming in
            (incoming.id, TaskRulePersistenceGuard.downgradedCellIDs(
                from: localBoards.first { $0.id == incoming.id }?.board, to: incoming.board
            ))
        }, uniquingKeysWith: { $0.union($1) })
        let activeRuleChanges = TaskRulePersistenceGuard.downgradedCellIDs(
            from: BingoBoardStore.loadActiveNamedBoardID() == selectedID ? BingoBoardStore.loadBoard() : nil,
            to: selectedBoard.board
        )
        authorizedRuleChanges[selectedID, default: []].formUnion(activeRuleChanges)
        let didSaveNamedBoards = BingoBoardStore.saveNamedBoardsSnapshot(
            namedSnapshot,
            reloadWidgets: false,
            source: "resolved_cloud_projection",
            authorizedRuleChangeCellIDs: authorizedRuleChanges
        )
        guard didSaveNamedBoards || BingoBoardStore.loadNamedBoardsSnapshot() == namedSnapshot else {
            return false
        }

        guard BingoBoardStore.saveBoard(
                selectedBoard.board,
                savedAt: selectedBoard.updatedAt,
                associatedBoardID: selectedID,
                reloadWidgets: false,
                explicitlyEditedCellIDs: activeRuleChanges.union(authorizedRuleChanges[selectedID] ?? [])
              ) else {
            return false
        }
        BingoBoardStore.saveBoardCountdownEndsAt(selectedBoard.countdownEndsAt)
        BingoBoardStore.saveActiveNamedBoardID(selectedID)

        return BingoBoardStore.loadBoard() == selectedBoard.board &&
            BingoBoardStore.loadBoardCountdownEndsAt() == selectedBoard.countdownEndsAt &&
            BingoBoardStore.loadActiveNamedBoardID() == selectedID
    }

    private static func localPointsSnapshot(
        from cloudPoints: PointsPersistenceSnapshot,
        selectedBoard: BingoBoardStore.NamedBoard,
        referenceDate: Date
    ) -> PointsPersistenceSnapshot {
        guard let totalPoints = cloudPoints.totalPoints,
              let lifetimePoints = cloudPoints.lifetimePoints else {
            return cloudPoints
        }

        let dailyRewardState = BingoRewardSettlement.initialDailyRewardState(
            referenceDate: referenceDate,
            boardLastSavedAt: selectedBoard.updatedAt,
            currentCells: selectedBoard.board.cells,
            currentCompletedLines: selectedBoard.board.completedLines,
            isBoardFullyCompleted: BoardEngine.isBoardFullyCompleted(selectedBoard.board.cells),
            // Rebuild the visible board snapshot while retaining this device's
            // source-keyed reversal credits across cloud refreshes.
            savedDailyRewardState: PointsStore.loadDailyRewardState(reading: .readOnly)
        )
        return PointsPersistenceSnapshot(
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState
        )
    }

    private static func stickerInventory(from rawValues: [String: Int]) -> [StickerKind: Int] {
        rawValues.reduce(into: [:]) { result, entry in
            guard let kind = StickerKind(rawValue: entry.key), entry.value > 0 else { return }
            result[kind] = entry.value
        }
    }
}
