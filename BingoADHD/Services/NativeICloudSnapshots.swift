import Foundation

struct NativeICloudPrimaryStateSnapshot: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let boards: [BingoBoardStore.NamedBoard]
    let deletedBoardIDs: Set<UUID>?
    let protectedBoardID: UUID?
    let boardOrderModifiedAt: Date?
    let points: PointsPersistenceSnapshot
    let diaryEntries: [String: BingoDiaryEntry]
    let timeoutPayload: [String: [String: Int]]
    let customRewards: [CustomReward]
    let redemptionHistory: [PointRedemptionRecord]
    let stickerInventory: [String: Int]
    let stickerPlacements: [HomeStickerPlacement]

    init(
        schemaVersion: Int = Self.schemaVersion,
        boards: [BingoBoardStore.NamedBoard],
        deletedBoardIDs: Set<UUID> = [],
        protectedBoardID: UUID? = nil,
        boardOrderModifiedAt: Date? = nil,
        points: PointsPersistenceSnapshot,
        diaryEntries: [String: BingoDiaryEntry],
        timeoutPayload: [String: [String: Int]],
        customRewards: [CustomReward],
        redemptionHistory: [PointRedemptionRecord],
        stickerInventory: [String: Int],
        stickerPlacements: [HomeStickerPlacement]
    ) {
        self.schemaVersion = schemaVersion
        self.boards = boards
        self.deletedBoardIDs = deletedBoardIDs
        self.protectedBoardID = protectedBoardID
        self.boardOrderModifiedAt = boardOrderModifiedAt
        self.points = points
        self.diaryEntries = diaryEntries
        self.timeoutPayload = timeoutPayload
        self.customRewards = customRewards
        self.redemptionHistory = redemptionHistory
        self.stickerInventory = stickerInventory
        self.stickerPlacements = stickerPlacements
    }

    static func captureLocal() -> NativeICloudPrimaryStateSnapshot {
        var namedSnapshot = BingoBoardStore.loadNamedBoardsSnapshot()
        if let activeBoardID = BingoBoardStore.loadActiveNamedBoardID(),
           let activeBoard = BingoBoardStore.loadBoard(),
           let index = namedSnapshot.boards.firstIndex(where: { $0.id == activeBoardID }) {
            namedSnapshot.boards[index].board = activeBoard
            namedSnapshot.boards[index].countdownEndsAt = BingoBoardStore.loadBoardCountdownEndsAt()
            namedSnapshot.boards[index].updatedAt = max(
                namedSnapshot.boards[index].updatedAt,
                BingoBoardStore.loadBoardLastSavedAt() ?? namedSnapshot.boards[index].updatedAt
            )
        }

        return NativeICloudPrimaryStateSnapshot(
            boards: namedSnapshot.boards,
            deletedBoardIDs: namedSnapshot.effectiveDeletedBoardIDs,
            protectedBoardID: namedSnapshot.effectiveProtectedBoardID,
            boardOrderModifiedAt: namedSnapshot.boardOrderModifiedAt,
            points: PointsStore.loadPersistenceSnapshot(),
            diaryEntries: BingoDiaryStore.loadAllEntriesDictionary(),
            timeoutPayload: BingoTimeoutStore.loadAllPayload(),
            customRewards: RewardStore.loadRewards(),
            redemptionHistory: PointRedemptionHistoryStore.load(),
            stickerInventory: StickerStore.loadInventoryCounts().reduce(into: [:]) { result, entry in
                result[entry.key.rawValue] = entry.value
            },
            stickerPlacements: StickerStore.loadPlacements()
        )
    }

    var hasMeaningfulUserData: Bool {
        if !effectiveDeletedBoardIDs.isEmpty ||
            boards.count > 1 ||
            diaryEntries.isEmpty == false ||
            timeoutPayload.isEmpty == false ||
            customRewards.isEmpty == false ||
            redemptionHistory.isEmpty == false ||
            stickerInventory.isEmpty == false ||
            stickerPlacements.isEmpty == false {
            return true
        }
        if (points.totalPoints ?? 0) != 0 || (points.lifetimePoints ?? 0) != 0 {
            return true
        }
        return boards.contains { namedBoard in
            let defaultBoardNames = Set([
                "Board 1",
                "棋盘 1",
                "棋盤 1",
                "ボード 1",
                L10n.boardDefaultName(1)
            ])
            let cells = namedBoard.board.fullBoardCells ?? namedBoard.board.cells
            return cells.joined().contains { !$0.isEmpty } ||
                namedBoard.board.gridSize != 3 ||
                namedBoard.countdownEndsAt != nil ||
                namedBoard.taskResetMode != .resetStatusNextDay ||
                namedBoard.customResetMinutes != nil ||
                !defaultBoardNames.contains(namedBoard.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The three untouched tasks created by onboarding are presentation data,
    /// not an account backup. A reinstall creates them before CloudKit finishes
    /// its first download, so treating them as normal user content can let a
    /// zero-point local snapshot overwrite an established account.
    var isSystemStarterGuideSeedData: Bool {
        guard boards.count == 1,
              effectiveDeletedBoardIDs.isEmpty,
              (points.totalPoints ?? 0) == 0,
              (points.lifetimePoints ?? 0) == 0,
              timeoutPayload.isEmpty,
              customRewards.isEmpty,
              redemptionHistory.isEmpty,
              stickerInventory.isEmpty,
              stickerPlacements.isEmpty else {
            return false
        }

        return BingoBoardStore.isPristineStarterGuideBoard(boards[0])
    }

    var lastUserModifiedAt: Date? {
        // Board persistence updates bookkeeping dates during ordinary reloads.
        // Only the iCloud change reporter records a genuine local user change.
        NativeICloudPreferences.primaryLocalModifiedAt
    }

    func hasSameUserState(as other: NativeICloudPrimaryStateSnapshot) -> Bool {
        schemaVersion == other.schemaVersion &&
            boards.map(PrimaryBoardUserState.init) == other.boards.map(PrimaryBoardUserState.init) &&
            effectiveDeletedBoardIDs == other.effectiveDeletedBoardIDs &&
            effectiveProtectedBoardID == other.effectiveProtectedBoardID &&
            boardOrderModifiedAt == other.boardOrderModifiedAt &&
            // The daily reward ledger belongs to the board currently displayed on
            // this device. Board selection intentionally remains device-local, so
            // treating another device's ledger as cloud-authoritative lets a
            // completed board on one device be reconciled against an empty board
            // on another. Only the durable point counters participate in cloud
            // equality; the local projection rebuilds the ledger for its board.
            points.totalPoints == other.points.totalPoints &&
            points.lifetimePoints == other.points.lifetimePoints &&
            diaryEntries == other.diaryEntries &&
            timeoutPayload == other.timeoutPayload &&
            customRewards == other.customRewards &&
            redemptionHistory == other.redemptionHistory &&
            stickerInventory == other.stickerInventory &&
            stickerPlacements == other.stickerPlacements
    }

    var effectiveDeletedBoardIDs: Set<UUID> {
        deletedBoardIDs ?? []
    }

    var effectiveProtectedBoardID: UUID? {
        if let protectedBoardID,
           boards.contains(where: { $0.id == protectedBoardID }) {
            return protectedBoardID
        }
        return boards.first?.id
    }

    private struct PrimaryBoardUserState: Equatable {
        let id: UUID
        let name: String
        let board: SavedBoard
        let countdownEndsAt: Date?
        let taskResetMode: BoardTaskResetMode
        let customResetMinutes: Int?
        let lastTaskResetAppliedAt: Date?
        let origin: BingoNamedBoardOrigin

        init(_ board: BingoBoardStore.NamedBoard) {
            id = board.id
            name = board.name
            self.board = board.board
            countdownEndsAt = board.countdownEndsAt
            taskResetMode = board.taskResetMode
            customResetMinutes = board.customResetMinutes
            lastTaskResetAppliedAt = board.lastTaskResetAppliedAt
            origin = board.origin
        }
    }
}

/// Merges an imported primary snapshot with the durable state already on this
/// device. This is deliberately conservative for task progress: a delayed device
/// must not turn a same-day automatic reset into a newer destructive cloud write.
/// Explicit user toggles still use a board's `updatedAt` as their ordering signal.
enum NativeICloudPrimaryStateMerger {
    static func merged(
        local: NativeICloudPrimaryStateSnapshot,
        incoming: NativeICloudPrimaryStateSnapshot,
        localHasNewerUserChange: Bool,
        preferIncomingCommit: Bool = false,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> NativeICloudPrimaryStateSnapshot {
        // Until an explicit, confirmed cloud-delete flow exists, an empty
        // snapshot is never allowed to erase a meaningful account snapshot.
        // This specifically protects history written by a fresh reinstall that
        // had not finished downloading yet. Normal task unchecks remain valid:
        // a board with tasks is still meaningful even when its score is zero.
        if local.hasMeaningfulUserData && incoming.isSystemStarterGuideSeedData {
            return removingRedundantStarterGuideBoards(from: NativeICloudPrimaryStateSnapshot(
                schemaVersion: max(local.schemaVersion, incoming.schemaVersion),
                boards: local.boards + incoming.boards,
                deletedBoardIDs: local.effectiveDeletedBoardIDs.union(incoming.effectiveDeletedBoardIDs),
                protectedBoardID: local.effectiveProtectedBoardID,
                boardOrderModifiedAt: local.boardOrderModifiedAt,
                points: local.points,
                diaryEntries: local.diaryEntries,
                timeoutPayload: local.timeoutPayload,
                customRewards: local.customRewards,
                redemptionHistory: local.redemptionHistory,
                stickerInventory: local.stickerInventory,
                stickerPlacements: local.stickerPlacements
            ))
        }
        if local.hasMeaningfulUserData && !incoming.hasMeaningfulUserData {
            return removingRedundantStarterGuideBoards(from: local)
        }

        let boardMerge = mergeBoards(
            local: local.boards,
            incoming: incoming.boards,
            deletedBoardIDs: local.effectiveDeletedBoardIDs.union(incoming.effectiveDeletedBoardIDs),
            referenceDate: referenceDate,
            calendar: calendar,
            preferIncomingCommit: preferIncomingCommit
        )
        let points = mergedPoints(
            local: local.points,
            incoming: incoming.points,
            preserveLocalProgressAgainstReset: boardMerge.preservedLocalProgressAgainstReset,
            localHasNewerUserChange: localHasNewerUserChange
        )
        let boardOrder = mergedBoardOrder(
            mergedBoards: boardMerge.boards,
            local: local,
            incoming: incoming,
            preferIncomingCommit: preferIncomingCommit
        )

        return removingRedundantStarterGuideBoards(from: NativeICloudPrimaryStateSnapshot(
            schemaVersion: max(local.schemaVersion, incoming.schemaVersion),
            boards: boardOrder.boards,
            deletedBoardIDs: local.effectiveDeletedBoardIDs.union(incoming.effectiveDeletedBoardIDs),
            protectedBoardID: boardOrder.protectedBoardID,
            boardOrderModifiedAt: boardOrder.modifiedAt,
            points: points,
            diaryEntries: localHasNewerUserChange ? local.diaryEntries : incoming.diaryEntries,
            timeoutPayload: localHasNewerUserChange ? local.timeoutPayload : incoming.timeoutPayload,
            customRewards: localHasNewerUserChange ? local.customRewards : incoming.customRewards,
            // Redemption records are append-only purchase evidence (with an
            // optional irreversible revocation marker), not a mutable view
            // model. Taking only one device's whole array can erase a blind-box
            // ticket charge that has already reserved a private CloudKit ticket
            // slot. Merge by stable record ID instead.
            redemptionHistory: mergedRedemptionHistory(
                local: local.redemptionHistory,
                incoming: incoming.redemptionHistory
            ),
            stickerInventory: localHasNewerUserChange ? local.stickerInventory : incoming.stickerInventory,
            stickerPlacements: localHasNewerUserChange ? local.stickerPlacements : incoming.stickerPlacements
        ))
    }

    private static func mergedRedemptionHistory(
        local: [PointRedemptionRecord],
        incoming: [PointRedemptionRecord]
    ) -> [PointRedemptionRecord] {
        var recordsByID: [UUID: PointRedemptionRecord] = [:]
        for record in local + incoming {
            guard let existing = recordsByID[record.id] else {
                recordsByID[record.id] = record
                continue
            }
            recordsByID[record.id] = mergedRedemptionRecord(existing, record)
        }

        return recordsByID.values.sorted { lhs, rhs in
            if lhs.redeemedAt != rhs.redeemedAt {
                return lhs.redeemedAt > rhs.redeemedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func mergedRedemptionRecord(
        _ lhs: PointRedemptionRecord,
        _ rhs: PointRedemptionRecord
    ) -> PointRedemptionRecord {
        // A revocation is a safety action. Once any synced copy has recorded
        // it, an older active snapshot must never resurrect that purchase.
        if lhs.isActive != rhs.isActive {
            return lhs.isActive ? rhs : lhs
        }
        if lhs.revokedAt != rhs.revokedAt {
            switch (lhs.revokedAt, rhs.revokedAt) {
            case let (leftDate?, rightDate?):
                return leftDate >= rightDate ? lhs : rhs
            case (.some, nil):
                return lhs
            case (nil, .some):
                return rhs
            case (nil, nil):
                break
            }
        }
        // Record fields are immutable after creation. For the unexpected case
        // of two active payloads sharing an ID, retain the later evidence.
        return lhs.redeemedAt >= rhs.redeemedAt ? lhs : rhs
    }

    static func removingRedundantStarterGuideBoards(
        from snapshot: NativeICloudPrimaryStateSnapshot
    ) -> NativeICloudPrimaryStateSnapshot {
        let normalizedBoards = BingoBoardStore.snapshotByRemovingRedundantStarterGuideBoards(
            BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: nil,
                boards: snapshot.boards,
                deletedBoardIDs: snapshot.effectiveDeletedBoardIDs,
                protectedBoardID: snapshot.effectiveProtectedBoardID,
                boardOrderModifiedAt: snapshot.boardOrderModifiedAt
            )
        )
        guard normalizedBoards.boards != snapshot.boards ||
                normalizedBoards.effectiveDeletedBoardIDs != snapshot.effectiveDeletedBoardIDs else {
            return snapshot
        }
        return NativeICloudPrimaryStateSnapshot(
            schemaVersion: snapshot.schemaVersion,
            boards: normalizedBoards.boards,
            deletedBoardIDs: normalizedBoards.effectiveDeletedBoardIDs,
            protectedBoardID: normalizedBoards.effectiveProtectedBoardID,
            boardOrderModifiedAt: snapshot.boardOrderModifiedAt,
            points: snapshot.points,
            diaryEntries: snapshot.diaryEntries,
            timeoutPayload: snapshot.timeoutPayload,
            customRewards: snapshot.customRewards,
            redemptionHistory: snapshot.redemptionHistory,
            stickerInventory: snapshot.stickerInventory,
            stickerPlacements: snapshot.stickerPlacements
        )
    }

    private static func mergedBoardOrder(
        mergedBoards: [BingoBoardStore.NamedBoard],
        local: NativeICloudPrimaryStateSnapshot,
        incoming: NativeICloudPrimaryStateSnapshot,
        preferIncomingCommit: Bool
    ) -> (boards: [BingoBoardStore.NamedBoard], protectedBoardID: UUID?, modifiedAt: Date?) {
        let shouldUseIncomingOrder: Bool
        switch (local.boardOrderModifiedAt, incoming.boardOrderModifiedAt) {
        case let (localDate?, incomingDate?):
            shouldUseIncomingOrder = incomingDate > localDate ||
                (incomingDate == localDate && preferIncomingCommit)
        case (nil, .some):
            shouldUseIncomingOrder = true
        case (.some, nil):
            shouldUseIncomingOrder = false
        case (nil, nil):
            // Preserve the historical merger's incoming-first order for snapshots
            // created before board ordering became an explicit user preference.
            shouldUseIncomingOrder = true
        }

        let orderSource = shouldUseIncomingOrder ? incoming : local
        let boardsByID = Dictionary(uniqueKeysWithValues: mergedBoards.map { ($0.id, $0) })
        var orderedIDs = orderSource.boards.map(\.id)
        let existingIDs = Set(orderedIDs)
        orderedIDs.append(contentsOf: mergedBoards.map(\.id).filter { !existingIDs.contains($0) })
        let boards = orderedIDs.compactMap { boardsByID[$0] }
        let protectedBoardID = orderSource.effectiveProtectedBoardID.flatMap { protectedID in
            boards.contains(where: { $0.id == protectedID }) ? protectedID : boards.first?.id
        } ?? boards.first?.id
        let modifiedAt: Date?
        if local.boardOrderModifiedAt == nil && incoming.boardOrderModifiedAt == nil {
            modifiedAt = nil
        } else {
            modifiedAt = shouldUseIncomingOrder
                ? incoming.boardOrderModifiedAt
                : local.boardOrderModifiedAt
        }
        return (boards, protectedBoardID, modifiedAt)
    }

    private static func mergedPoints(
        local: PointsPersistenceSnapshot,
        incoming: PointsPersistenceSnapshot,
        preserveLocalProgressAgainstReset: Bool,
        localHasNewerUserChange: Bool
    ) -> PointsPersistenceSnapshot {
        if localHasNewerUserChange {
            return local
        }

        let totalPoints: Int?
        if preserveLocalProgressAgainstReset {
            totalPoints = maximum(local.totalPoints, incoming.totalPoints)
        } else {
            totalPoints = incoming.totalPoints ?? local.totalPoints
        }

        // Lifetime points never decrease, including when a task is unchecked.
        // Taking the maximum is both correct and prevents an old device from
        // erasing earned history while it catches up.
        let lifetimePoints = maximum(local.lifetimePoints, incoming.lifetimePoints)

        return PointsPersistenceSnapshot(
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            // This value is rebuilt for the device-local active board while the
            // projection is applied. Keep a value here only for a complete Codable
            // snapshot before that projection occurs.
            dailyRewardState: incoming.dailyRewardState ?? local.dailyRewardState
        )
    }

    private static func maximum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private static func mergeBoards(
        local: [BingoBoardStore.NamedBoard],
        incoming: [BingoBoardStore.NamedBoard],
        deletedBoardIDs: Set<UUID>,
        referenceDate: Date,
        calendar: Calendar,
        preferIncomingCommit: Bool
    ) -> (boards: [BingoBoardStore.NamedBoard], preservedLocalProgressAgainstReset: Bool) {
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        var orderedIDs = incoming.map(\.id)
        orderedIDs.append(contentsOf: local.map(\.id).filter { incomingByID[$0] == nil })

        var preservedLocalProgressAgainstReset = false
        let boards = orderedIDs.compactMap { id -> BingoBoardStore.NamedBoard? in
            guard !deletedBoardIDs.contains(id) else { return nil }
            guard let localBoard = localByID[id] else { return incomingByID[id] }
            guard let incomingBoard = incomingByID[id] else { return localBoard }

            if shouldPreserveLocalProgress(
                local: localBoard,
                incoming: incomingBoard,
                referenceDate: referenceDate,
                calendar: calendar
            ) {
                preservedLocalProgressAgainstReset = true
                return localBoard
            }
            if preferIncomingCommit {
                return incomingBoard
            }
            return incomingBoard.updatedAt >= localBoard.updatedAt ? incomingBoard : localBoard
        }
        return (boards, preservedLocalProgressAgainstReset)
    }

    private static func shouldPreserveLocalProgress(
        local: BingoBoardStore.NamedBoard,
        incoming: BingoBoardStore.NamedBoard,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        // A scheduled midnight reset has a distinct reset anchor. If a device
        // that was offline performs that reset after another device completed
        // tasks today, its newer `updatedAt` must not erase today's work.
        guard incoming.taskResetMode == .resetStatusNextDay,
              BoardResetRuleEngine.normalizedCustomResetMinutes(
                incoming.customResetMinutes,
                mode: incoming.taskResetMode
              ) == nil,
              let incomingResetAt = incoming.lastTaskResetAppliedAt,
              let localResetAt = local.lastTaskResetAppliedAt,
              incomingResetAt > localResetAt,
              calendar.isDate(incomingResetAt, inSameDayAs: referenceDate),
              calendar.isDate(localResetAt, inSameDayAs: referenceDate),
              completedTaskCount(in: incoming.board) < completedTaskCount(in: local.board) else {
            return false
        }
        return true
    }

    private static func completedTaskCount(in board: SavedBoard) -> Int {
        BoardEngine.expandedBoardCache(from: board)
            .flatMap(\.self)
            .filter { $0.isCompleted && $0.hasStoredTask }
            .count
    }
}

/// Replays the bounded immutable primary history in commit order. A single
/// latest-record lookup is insufficient because device maintenance (for
/// example, a delayed midnight reset) can be saved after a genuine task tap
/// from another device. Replaying through the primary merger retains that tap
/// while still allowing a later explicit undo to win normally.
enum NativeICloudPrimaryHistoryResolver {
    static func resolve(
        _ history: [(NativeICloudEnvelopeValue, NativeICloudPrimaryStateSnapshot)],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> NativeICloudPrimaryStateSnapshot? {
        guard let first = history.first else { return nil }
        var resolved = NativeICloudPrimaryStateMerger.removingRedundantStarterGuideBoards(
            from: first.1
        )
        for (envelope, incoming) in history.dropFirst() {
            resolved = NativeICloudPrimaryStateMerger.merged(
                local: resolved,
                incoming: incoming,
                localHasNewerUserChange: false,
                preferIncomingCommit: envelope.schemaVersion >= NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        return resolved
    }
}

enum NativeICloudPrimaryHandledStateResolver {
    static func contains(
        latestStamp: NativeICloudCommitStamp,
        latestSchemaVersion: Int64,
        resolvedState: NativeICloudPrimaryStateSnapshot,
        handledStamp: NativeICloudCommitStamp?,
        handledSchemaVersion: Int64?,
        handledState: NativeICloudPrimaryStateSnapshot?
    ) -> Bool {
        guard let handledStamp,
              let handledSchemaVersion,
              (latestSchemaVersion < handledSchemaVersion ||
                (latestSchemaVersion == handledSchemaVersion && latestStamp <= handledStamp)),
              let handledState else {
            return false
        }
        return handledState.hasSameUserState(as: resolvedState)
    }
}

enum NativeICloudPrimaryConflictResolver {
    /// Primary snapshots are atomic user commits. A task undo legitimately lowers
    /// total points, and a device that has not imported yet can also have a lower
    /// lifetime total. Treating either point counter as a version makes an older
    /// snapshot permanently override later taps. Resolve the immutable history by
    /// the genuine user-change stamp instead.
    static func prefers(
        _ lhs: NativeICloudEnvelopeValue,
        over rhs: NativeICloudEnvelopeValue
    ) -> Bool {
        if lhs.schemaVersion != rhs.schemaVersion {
            return lhs.schemaVersion > rhs.schemaVersion
        }
        return lhs.stamp > rhs.stamp
    }

    static func localChangeIsNewer(
        modifiedAt: Date?,
        than incomingStamp: NativeICloudCommitStamp
    ) -> Bool {
        guard let modifiedAt else { return false }
        return modifiedAt > incomingStamp.modifiedAt
    }
}

enum NativeICloudInitialMigrationDecision: Equatable {
    case uploadLocal
    case applyRemote
    /// Do not manufacture a cloud record from an untouched first-run state.
    case deferUpload
}

enum NativeICloudInitialMigrationPlanner {
    static func decide(
        localHasMeaningfulData: Bool,
        localIsSystemStarterGuideSeedData: Bool = false,
        localModifiedAt: Date?,
        remoteStamp: NativeICloudCommitStamp?,
        remoteHasMeaningfulData: Bool = true,
        isAccountBindingConfirmed: Bool = true
    ) -> NativeICloudInitialMigrationDecision {
        guard let remoteStamp else {
            return localHasMeaningfulData && !localIsSystemStarterGuideSeedData
                ? .uploadLocal
                : .deferUpload
        }
        // During a first association, an existing account record wins. A local
        // timestamp from onboarding/reload is not evidence that this device owns
        // the iCloud account's state.
        guard isAccountBindingConfirmed else { return .applyRemote }
        guard !localIsSystemStarterGuideSeedData else { return .applyRemote }
        guard localHasMeaningfulData else { return .applyRemote }
        // A default/empty seed is not an authoritative account state. This
        // covers the order where a brand-new device enables iCloud first and an
        // older device with pre-iCloud user data joins later.
        guard remoteHasMeaningfulData else { return .uploadLocal }
        guard let localModifiedAt else { return .applyRemote }
        return localModifiedAt > remoteStamp.modifiedAt ? .uploadLocal : .applyRemote
    }
}

/// A normal task undo can legitimately reduce the score, but a freshly installed
/// app has no user state at all. Never let that empty seed replace an existing
/// account snapshot outside the explicit delete flow.
enum NativeICloudPrimaryExportGuard {
    static func blocksAutomaticUpload(
        local: NativeICloudPrimaryStateSnapshot,
        remote: NativeICloudPrimaryStateSnapshot
    ) -> Bool {
        local.isSystemStarterGuideSeedData ||
            (remote.hasMeaningfulUserData && !local.hasMeaningfulUserData)
    }
}
