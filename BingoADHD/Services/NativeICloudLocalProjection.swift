import Foundation

extension Notification.Name {
    static let nativeICloudPrimaryProjectionDidChange = Notification.Name(
        "NativeICloudPrimaryProjectionDidChange"
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
        referenceDate: Date = .now
    ) -> Bool {
        guard snapshot.schemaVersion == NativeICloudPrimaryStateSnapshot.schemaVersion else {
            return false
        }
        let preferredSelection = BingoBoardStore.loadNamedBoardsSnapshot().selectedBoardID
        let selectedID = preferredSelection.flatMap { candidate in
            snapshot.boards.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? snapshot.boards.first?.id
        guard let selectedID,
              let selectedBoard = snapshot.boards.first(where: { $0.id == selectedID }) else {
            return false
        }
        return PointsStore.loadPersistenceSnapshot() != localPointsSnapshot(
            from: snapshot.points,
            selectedBoard: selectedBoard,
            referenceDate: referenceDate
        )
    }

    static func apply(
        _ snapshot: NativeICloudPrimaryStateSnapshot,
        reloadWidgets: Bool = true
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
              RewardStore.saveRewards(snapshot.customRewards),
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
            deletedBoardIDs: snapshot.effectiveDeletedBoardIDs
        )
        let didSaveNamedBoards = BingoBoardStore.saveNamedBoardsSnapshot(
            namedSnapshot,
            reloadWidgets: false
        )
        guard didSaveNamedBoards || BingoBoardStore.loadNamedBoardsSnapshot() == namedSnapshot else {
            return false
        }

        guard BingoBoardStore.saveBoard(
                selectedBoard.board,
                savedAt: selectedBoard.updatedAt,
                associatedBoardID: selectedID,
                reloadWidgets: false
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
            // Never import this ledger from another device: board selection is
            // intentionally local and therefore it may describe a different board.
            savedDailyRewardState: nil
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
