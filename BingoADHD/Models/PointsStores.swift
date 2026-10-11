import Foundation

enum StickerStore {
    static func loadInventoryCounts(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> [StickerKind: Int] {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: AppSettings.stickerInventoryCountsKey),
           let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            let normalized = saved.reduce(into: [StickerKind: Int]()) { partial, entry in
                guard let kind = StickerKind(rawValue: entry.key), entry.value > 0 else { return }
                partial[kind] = 1
            }
            if mode == .repairingMirrors {
                saveInventoryCounts(normalized, reportChange: false)
            }
            return normalized
        }

        // Migrate legacy "redeemed once" state into a single owned sticker inventory.
        var migratedKinds: [StickerKind] = []
        if let data = defaults.data(forKey: AppSettings.redeemedStickerOrderKey),
           let orderedKinds = try? JSONDecoder().decode([StickerKind].self, from: data) {
            migratedKinds = orderedKinds
        } else if let data = defaults.data(forKey: AppSettings.redeemedStickersKey),
                  let kinds = try? JSONDecoder().decode([StickerKind].self, from: data) {
            migratedKinds = kinds
        }

        let migratedCounts = migratedKinds.reduce(into: [StickerKind: Int]()) { partial, kind in
            partial[kind] = 1
        }
        if mode == .repairingMirrors, !migratedCounts.isEmpty {
            saveInventoryCounts(migratedCounts, reportChange: false)
        }
        return migratedCounts
    }

    @discardableResult
    static func saveInventoryCounts(
        _ counts: [StickerKind: Int],
        reportChange: Bool = true
    ) -> Bool {
        let payload = counts.reduce(into: [String: Int]()) { partial, entry in
            guard entry.value > 0 else { return }
            partial[entry.key.rawValue] = 1
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return false }
        guard UserDefaults.standard.data(forKey: AppSettings.stickerInventoryCountsKey) != data else {
            return true
        }
        UserDefaults.standard.set(data, forKey: AppSettings.stickerInventoryCountsKey)
        let didSave = UserDefaults.standard.data(forKey: AppSettings.stickerInventoryCountsKey) == data
        if didSave, reportChange {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        return didSave
    }

    static func loadPlacements(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> [HomeStickerPlacement] {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.homeStickerPlacementsKey),
              let placements = try? JSONDecoder().decode([HomeStickerPlacement].self, from: data) else {
            return []
        }
        let normalized = normalizedPlacements(placements)
        if mode == .repairingMirrors {
            savePlacements(normalized, reportChange: false)
        }
        return normalized
    }

    @discardableResult
    static func savePlacements(
        _ placements: [HomeStickerPlacement],
        reportChange: Bool = true
    ) -> Bool {
        let normalized = normalizedPlacements(placements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(normalized) else { return false }
        guard UserDefaults.standard.data(forKey: AppSettings.homeStickerPlacementsKey) != data else {
            return true
        }
        UserDefaults.standard.set(data, forKey: AppSettings.homeStickerPlacementsKey)
        let didSave = UserDefaults.standard.data(forKey: AppSettings.homeStickerPlacementsKey) == data
        if didSave, reportChange {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        return didSave
    }

    static func clearPlacements() {
        let didChange = UserDefaults.standard.object(forKey: AppSettings.homeStickerPlacementsKey) != nil
        UserDefaults.standard.removeObject(forKey: AppSettings.homeStickerPlacementsKey)
        if didChange {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
    }

    static func clearInventoryCounts() {
        let defaults = UserDefaults.standard
        let didChange = defaults.object(forKey: AppSettings.stickerInventoryCountsKey) != nil ||
            defaults.object(forKey: AppSettings.redeemedStickersKey) != nil ||
            defaults.object(forKey: AppSettings.redeemedStickerOrderKey) != nil
        defaults.removeObject(forKey: AppSettings.stickerInventoryCountsKey)
        defaults.removeObject(forKey: AppSettings.redeemedStickersKey)
        defaults.removeObject(forKey: AppSettings.redeemedStickerOrderKey)
        if didChange {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
    }

    private static func normalizedPlacements(_ placements: [HomeStickerPlacement]) -> [HomeStickerPlacement] {
        var seenContentIdentifiers = Set<String>()
        var result: [HomeStickerPlacement] = []
        result.reserveCapacity(placements.count)

        for placement in placements {
            let normalized = placement.normalized()
            guard !seenContentIdentifiers.contains(normalized.stableContentIdentifier) else { continue }
            seenContentIdentifiers.insert(normalized.stableContentIdentifier)
            result.append(normalized)
        }

        return result
    }
}

struct PointsPersistenceSnapshot: Codable, Equatable {
    let totalPoints: Int?
    let lifetimePoints: Int?
    let dailyRewardState: DailyRewardState?
}

enum PointsStore {
    private struct PersistedState: Codable {
        let totalPoints: Int
        let lifetimePoints: Int
        let dailyRewardState: DailyRewardState
    }

    private static let stateFileName = "bingo_points_state_v1.json"

    static func loadTotalPoints(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> Int? {
        if let state = loadState(reading: mode) {
            return state.totalPoints
        }
        if sharedDefaults.object(forKey: AppSettings.totalPointsKey) != nil {
            return sharedDefaults.integer(forKey: AppSettings.totalPointsKey)
        }
        guard UserDefaults.standard.object(forKey: AppSettings.totalPointsKey) != nil else { return nil }
        let points = UserDefaults.standard.integer(forKey: AppSettings.totalPointsKey)
        if mode == .repairingMirrors {
            sharedDefaults.set(points, forKey: AppSettings.totalPointsKey)
        }
        return points
    }

    static func loadPersistenceSnapshot(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> PointsPersistenceSnapshot {
        if let state = loadState(reading: mode) {
            return PointsPersistenceSnapshot(
                totalPoints: state.totalPoints,
                lifetimePoints: state.lifetimePoints,
                dailyRewardState: state.dailyRewardState
            )
        }

        return PointsPersistenceSnapshot(
            totalPoints: loadTotalPoints(reading: mode),
            lifetimePoints: loadLifetimePoints(reading: mode),
            dailyRewardState: loadDailyRewardState(reading: mode)
        )
    }

    static func saveTotalPoints(_ points: Int) {
        let current = loadPersistenceSnapshot()
        _ = replacePersistenceSnapshot(PointsPersistenceSnapshot(
            totalPoints: points,
            lifetimePoints: current.lifetimePoints,
            dailyRewardState: current.dailyRewardState
        ))
    }

    static func loadLifetimePoints(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> Int? {
        if let state = loadState(reading: mode) {
            return state.lifetimePoints
        }
        if sharedDefaults.object(forKey: AppSettings.lifetimePointsKey) != nil {
            return sharedDefaults.integer(forKey: AppSettings.lifetimePointsKey)
        }
        guard UserDefaults.standard.object(forKey: AppSettings.lifetimePointsKey) != nil else { return nil }
        let points = UserDefaults.standard.integer(forKey: AppSettings.lifetimePointsKey)
        if mode == .repairingMirrors {
            sharedDefaults.set(points, forKey: AppSettings.lifetimePointsKey)
        }
        return points
    }

    static func saveLifetimePoints(_ points: Int) {
        let current = loadPersistenceSnapshot()
        _ = replacePersistenceSnapshot(PointsPersistenceSnapshot(
            totalPoints: current.totalPoints,
            lifetimePoints: points,
            dailyRewardState: current.dailyRewardState
        ))
    }

    static func loadDailyRewardState(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> DailyRewardState? {
        if let state = loadState(reading: mode) {
            return state.dailyRewardState
        }
        if let data = sharedDefaults.data(forKey: AppSettings.dailyRewardStateKey),
           let state = try? JSONDecoder().decode(DailyRewardState.self, from: data) {
            return state
        }
        guard let data = UserDefaults.standard.data(forKey: AppSettings.dailyRewardStateKey),
              let state = try? JSONDecoder().decode(DailyRewardState.self, from: data) else {
                return nil
        }
        if mode == .repairingMirrors {
            sharedDefaults.set(data, forKey: AppSettings.dailyRewardStateKey)
        }
        return state
    }

    static func saveDailyRewardState(_ state: DailyRewardState) {
        let current = loadPersistenceSnapshot()
        _ = replacePersistenceSnapshot(PointsPersistenceSnapshot(
            totalPoints: current.totalPoints,
            lifetimePoints: current.lifetimePoints,
            dailyRewardState: state
        ))
    }

    static func clearDailyRewardState() {
        let current = loadPersistenceSnapshot()
        _ = replacePersistenceSnapshot(PointsPersistenceSnapshot(
            totalPoints: current.totalPoints,
            lifetimePoints: current.lifetimePoints,
            dailyRewardState: nil
        ))
    }

    static func clearTotalPoints() {
        let current = loadPersistenceSnapshot()
        _ = replacePersistenceSnapshot(PointsPersistenceSnapshot(
            totalPoints: nil,
            lifetimePoints: current.lifetimePoints,
            dailyRewardState: current.dailyRewardState
        ))
    }

    static func clearLifetimePoints() {
        let current = loadPersistenceSnapshot()
        _ = replacePersistenceSnapshot(PointsPersistenceSnapshot(
            totalPoints: current.totalPoints,
            lifetimePoints: nil,
            dailyRewardState: current.dailyRewardState
        ))
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    @discardableResult
    static func saveState(
        totalPoints: Int,
        lifetimePoints: Int,
        dailyRewardState: DailyRewardState
    ) -> Bool {
        replacePersistenceSnapshot(PointsPersistenceSnapshot(
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints,
            dailyRewardState: dailyRewardState
        ))
    }

    @discardableResult
    static func replacePersistenceSnapshot(_ snapshot: PointsPersistenceSnapshot) -> Bool {
        let previousSnapshot = loadPersistenceSnapshot()
        let fileData: Data?
        if let totalPoints = snapshot.totalPoints,
           let lifetimePoints = snapshot.lifetimePoints,
           let dailyRewardState = snapshot.dailyRewardState {
            let state = PersistedState(
                totalPoints: totalPoints,
                lifetimePoints: lifetimePoints,
                dailyRewardState: dailyRewardState
            )
            guard let data = try? JSONEncoder().encode(state) else { return false }
            fileData = data
        } else {
            fileData = nil
        }

        let rewardData: Data?
        if let dailyRewardState = snapshot.dailyRewardState {
            guard let data = try? JSONEncoder().encode(dailyRewardState) else { return false }
            rewardData = data
        } else {
            rewardData = nil
        }

        guard let fileStep = PersistenceWriteTransaction.fileDataStep(
            at: stateFileURL,
            newData: fileData
        ) else { return false }
        let didSave = PersistenceWriteTransaction.commit([
            fileStep,
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.totalPointsKey,
                newValue: snapshot.totalPoints
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.totalPointsKey,
                newValue: snapshot.totalPoints
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.lifetimePointsKey,
                newValue: snapshot.lifetimePoints
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.lifetimePointsKey,
                newValue: snapshot.lifetimePoints
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.dailyRewardStateKey,
                newValue: rewardData
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.dailyRewardStateKey,
                newValue: rewardData
            )
        ])
        if didSave, previousSnapshot != snapshot {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        return didSave
    }

    private static func loadState(reading mode: PersistenceReadMode) -> PersistedState? {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return nil
        }
        if mode == .repairingMirrors {
            repairDefaultsIfNeeded(for: state)
        }
        return state
    }

    private static func repairDefaultsIfNeeded(for state: PersistedState) {
        guard let rewardData = try? JSONEncoder().encode(state.dailyRewardState) else { return }
        let values: [(UserDefaults, String, Any)] = [
            (sharedDefaults, AppSettings.totalPointsKey, state.totalPoints),
            (.standard, AppSettings.totalPointsKey, state.totalPoints),
            (sharedDefaults, AppSettings.lifetimePointsKey, state.lifetimePoints),
            (.standard, AppSettings.lifetimePointsKey, state.lifetimePoints),
            (sharedDefaults, AppSettings.dailyRewardStateKey, rewardData),
            (.standard, AppSettings.dailyRewardStateKey, rewardData)
        ]
        let steps = values.compactMap { defaults, key, value -> PersistenceWriteStep? in
            guard let current = defaults.object(forKey: key) as? NSObject,
                  !current.isEqual(value as AnyObject) else {
                return defaults.object(forKey: key) == nil
                    ? PersistenceWriteTransaction.userDefaultsStep(
                        defaults: defaults,
                        key: key,
                        newValue: value
                    )
                    : nil
            }
            return PersistenceWriteTransaction.userDefaultsStep(
                defaults: defaults,
                key: key,
                newValue: value
            )
        }
        _ = PersistenceWriteTransaction.commit(steps)
    }

    private static var stateFileURL: URL {
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BingoBoardStore.appGroupID
        ) {
            let directory = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(stateFileName)
        }

        #if targetEnvironment(simulator)
        let directory = URL(fileURLWithPath: "/tmp/\(BingoBoardStore.appGroupID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(stateFileName)
        #else
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(stateFileName)
        #endif
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }
}

enum RewardStore {
    static func loadRewards(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> [CustomReward] {
        if let data = sharedDefaults.data(forKey: AppSettings.customRewardsKey),
           let rewards = try? JSONDecoder().decode([CustomReward].self, from: data) {
            if mode == .repairingMirrors,
               UserDefaults.standard.data(forKey: AppSettings.customRewardsKey) != data {
                _ = PersistenceWriteTransaction.commit([
                    PersistenceWriteTransaction.userDefaultsStep(
                        defaults: .standard,
                        key: AppSettings.customRewardsKey,
                        newValue: data
                    )
                ])
            }
            return rewards
        }
        guard let data = UserDefaults.standard.data(forKey: AppSettings.customRewardsKey),
              let rewards = try? JSONDecoder().decode([CustomReward].self, from: data) else {
            return []
        }

        if mode == .repairingMirrors {
            _ = PersistenceWriteTransaction.commit([
                PersistenceWriteTransaction.userDefaultsStep(
                    defaults: sharedDefaults,
                    key: AppSettings.customRewardsKey,
                    newValue: data
                )
            ])
        }
        return rewards
    }

    @discardableResult
    static func saveRewards(_ rewards: [CustomReward], source: String = "local") -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(rewards) else { return false }
        guard sharedDefaults.data(forKey: AppSettings.customRewardsKey) != data ||
                UserDefaults.standard.data(forKey: AppSettings.customRewardsKey) != data else {
            return true
        }
        let didSave = PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.customRewardsKey,
                newValue: data
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.customRewardsKey,
                newValue: data
            )
        ])
        if didSave {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        DiagnosticLogStore.recordStateChange("custom_reward.persistence_result", details: [
            "source": source, "count": "\(rewards.count)",
            "active_count": "\(rewards.filter { !$0.isArchived }.count)", "saved": "\(didSave)"
        ])
        return didSave
    }

    @discardableResult
    static func clearRewards() -> Bool {
        let didChange = sharedDefaults.object(forKey: AppSettings.customRewardsKey) != nil ||
            UserDefaults.standard.object(forKey: AppSettings.customRewardsKey) != nil
        let didClear = PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.customRewardsKey,
                newValue: nil
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.customRewardsKey,
                newValue: nil
            )
        ])
        if didClear, didChange {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        return didClear
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }
}

struct PointRedemptionReconciliationResult {
    var stickerInventoryCounts: [StickerKind: Int]
    var homeStickerPlacements: [HomeStickerPlacement]
    var customRewards: [CustomReward]
    var didRevokeStickers: Bool
    var didRevokeCustomRewards: Bool
    var redemptionRecords: [PointRedemptionRecord]? = nil
    var didUpdateLedger: Bool = false

    var didChange: Bool {
        didRevokeStickers || didRevokeCustomRewards || didUpdateLedger
    }
}

struct PointRedemptionLedgerProjection {
    var stickerInventoryCounts: [StickerKind: Int]
    var homeStickerPlacements: [HomeStickerPlacement]
    var customRewards: [CustomReward]
}

enum PointRedemptionLedger {
    /// The point floor needed to preserve successful redemptions. Task undos may
    /// consume only the unspent portion above this amount; purchases are never
    /// revoked to make a derived balance fit an older task total.
    static func currentCommittedSpend() -> Int {
        let records = loadOrMigrate(
            stickerInventoryCounts: StickerStore.loadInventoryCounts(),
            customRewards: RewardStore.loadRewards()
        ) ?? PointRedemptionHistoryStore.load()
        return committedSpend(in: records)
    }

    static func committedSpend(in records: [PointRedemptionRecord]) -> Int {
        records.reduce(0) { partial, record in
            // Legacy display-only history can remain unlinked after aggregate
            // migration (for example, when a reward was renamed). Its cost is
            // already covered by the linked migration records.
            guard record.isActive,
                  record.itemReferenceID != nil || record.itemKind == .blindBoxTicket else { return partial }
            return partial + max(record.points, 0)
        }
    }

    static func loadOrMigrate(
        stickerInventoryCounts: [StickerKind: Int],
        customRewards: [CustomReward]
    ) -> [PointRedemptionRecord]? {
        let records = PointRedemptionHistoryStore.load()
        // Only the app can migrate its legacy sticker inventory. An extension
        // has a different private defaults domain and must not initialize an
        // empty shared ledger before the updated app has launched.
        guard Bundle.main.bundleURL.pathExtension != "appex" else { return records }
        guard !PointRedemptionHistoryStore.isLedgerInitialized else {
            return records
        }

        let migrated = recordsByAddingLegacyCoverage(
            to: records,
            stickerInventoryCounts: stickerInventoryCounts,
            customRewards: customRewards
        )
        guard PointRedemptionHistoryStore.save(migrated) else { return nil }
        PointRedemptionHistoryStore.markLedgerInitialized()
        return migrated
    }

    static func projection(
        from records: [PointRedemptionRecord],
        homeStickerPlacements: [HomeStickerPlacement],
        customRewards: [CustomReward]
    ) -> PointRedemptionLedgerProjection {
        let activeRecords = records.filter(\.isActive)
        let ownedStickerKinds = Set(activeRecords.compactMap(\.referencedStickerKind))
        let inventory = ownedStickerKinds.reduce(into: [StickerKind: Int]()) { partial, kind in
            partial[kind] = 1
        }
        let placements = homeStickerPlacements.filter { placement in
            // Blind Box ownership is held in its independent immutable draw
            // journal, not in the points redemption ledger. Keep those
            // placements while this legacy projection validates its own items.
            guard let kind = placement.legacyKind else { return true }
            return ownedStickerKinds.contains(kind)
        }
        let rewardRecords = Dictionary(grouping: activeRecords.compactMap { record -> (UUID, Int)? in
            guard let rewardID = record.referencedCustomRewardID else { return nil }
            return (rewardID, max(record.points, 0))
        }, by: { $0.0 })
        let rewards = customRewards.map { reward -> CustomReward in
            var updatedReward = reward
            let entries = rewardRecords[reward.id] ?? []
            updatedReward.redemptionCount = entries.count
            updatedReward.totalSpentPoints = entries.reduce(0) { $0 + $1.1 }
            return updatedReward
        }
        return PointRedemptionLedgerProjection(
            stickerInventoryCounts: inventory,
            homeStickerPlacements: placements,
            customRewards: rewards
        )
    }

    private static func recordsByAddingLegacyCoverage(
        to records: [PointRedemptionRecord],
        stickerInventoryCounts: [StickerKind: Int],
        customRewards: [CustomReward]
    ) -> [PointRedemptionRecord] {
        var result = records
        var claimedUnlinkedRecordIDs = Set<UUID>()

        for kind in StickerKind.allCases where stickerInventoryCounts[kind, default: 0] > 0 {
            let referenceID = PointRedemptionRecord.stickerReferenceID(kind)
            guard !result.contains(where: { $0.isActive && $0.itemReferenceID == referenceID }) else {
                continue
            }
            if let index = result.indices.first(where: { index in
                let record = result[index]
                return record.isActive &&
                    record.itemKind == .sticker &&
                    record.itemReferenceID == nil &&
                    !claimedUnlinkedRecordIDs.contains(record.id) &&
                    (record.imageName == kind.unlockedImageName || record.title == kind.redemptionHistoryTitle)
            }) {
                claimedUnlinkedRecordIDs.insert(result[index].id)
                result[index] = result[index].linked(to: referenceID)
            } else {
                result.append(
                    PointRedemptionRecord(
                        itemKind: .sticker,
                        title: kind.redemptionHistoryTitle,
                        points: kind.requiredPoints,
                        redeemedAt: .distantPast,
                        imageName: kind.unlockedImageName,
                        itemReferenceID: referenceID
                    )
                )
            }
        }

        for reward in customRewards where reward.redemptionCount > 0 {
            let referenceID = PointRedemptionRecord.customRewardReferenceID(reward.id)
            let linkedRecords = result.filter { $0.isActive && $0.itemReferenceID == referenceID }
            var remainingCount = max(reward.redemptionCount - linkedRecords.count, 0)
            var remainingPoints = max(
                reward.totalSpentPoints - linkedRecords.reduce(0) { $0 + max($1.points, 0) },
                0
            )

            while remainingCount > 0,
                  let index = result.indices.first(where: { index in
                      let record = result[index]
                      return record.isActive &&
                          record.itemKind == .customReward &&
                          record.itemReferenceID == nil &&
                          !claimedUnlinkedRecordIDs.contains(record.id) &&
                          record.title == reward.title &&
                          max(record.points, 0) <= remainingPoints
                  }) {
                claimedUnlinkedRecordIDs.insert(result[index].id)
                remainingPoints -= max(result[index].points, 0)
                remainingCount -= 1
                result[index] = result[index].linked(to: referenceID)
            }

            for points in legacyPointSplit(totalPoints: remainingPoints, count: remainingCount) {
                result.append(
                    PointRedemptionRecord(
                        itemKind: .customReward,
                        title: reward.title,
                        points: points,
                        redeemedAt: .distantPast,
                        imageName: reward.themeImageName,
                        emoji: reward.themeImageName == nil ? reward.displayEmoji : nil,
                        itemReferenceID: referenceID
                    )
                )
            }
        }
        return result
    }

    private static func legacyPointSplit(totalPoints: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let normalizedTotal = max(totalPoints, 0)
        let base = normalizedTotal / count
        let remainder = normalizedTotal % count
        return (0..<count).map { index in
            base + (index < remainder ? 1 : 0)
        }
    }
}

enum PointRedemptionReconciler {
    @discardableResult
    static func reconcilePersistedRedemptionsIfNeeded(totalPoints: Int) -> PointRedemptionReconciliationResult {
        let stickerInventoryCounts = StickerStore.loadInventoryCounts()
        let homeStickerPlacements = StickerStore.loadPlacements()
        let customRewards = RewardStore.loadRewards()
        let ledgerRecords = PointRedemptionLedger.loadOrMigrate(
            stickerInventoryCounts: stickerInventoryCounts,
            customRewards: customRewards
        )
        let result = reconcileRedemptionsIfNeeded(
            totalPoints: totalPoints,
            stickerInventoryCounts: stickerInventoryCounts,
            homeStickerPlacements: homeStickerPlacements,
            customRewards: customRewards,
            redemptionRecords: ledgerRecords
        )
        persist(result)
        return result
    }

    static func reconcileRedemptionsIfNeeded(
        totalPoints: Int,
        stickerInventoryCounts: [StickerKind: Int],
        homeStickerPlacements: [HomeStickerPlacement],
        customRewards: [CustomReward],
        redemptionRecords: [PointRedemptionRecord]? = nil,
        now: Date = .now
    ) -> PointRedemptionReconciliationResult {
        if let redemptionRecords {
            return reconcileUsingLedger(
                totalPoints: totalPoints,
                stickerInventoryCounts: stickerInventoryCounts,
                homeStickerPlacements: homeStickerPlacements,
                customRewards: customRewards,
                redemptionRecords: redemptionRecords,
                now: now
            )
        }
        _ = totalPoints
        return PointRedemptionReconciliationResult(
            stickerInventoryCounts: stickerInventoryCounts,
            homeStickerPlacements: homeStickerPlacements,
            customRewards: customRewards,
            didRevokeStickers: false,
            didRevokeCustomRewards: false
        )
    }

    static func persist(_ result: PointRedemptionReconciliationResult) {
        if result.didUpdateLedger, let records = result.redemptionRecords {
            guard PointRedemptionHistoryStore.save(records) else { return }
        }
        if result.didRevokeStickers {
            StickerStore.saveInventoryCounts(result.stickerInventoryCounts)
            StickerStore.savePlacements(result.homeStickerPlacements)
        }

        if result.didRevokeCustomRewards {
            RewardStore.saveRewards(result.customRewards)
        }
    }

    private static func reconcileUsingLedger(
        totalPoints: Int,
        stickerInventoryCounts: [StickerKind: Int],
        homeStickerPlacements: [HomeStickerPlacement],
        customRewards: [CustomReward],
        redemptionRecords: [PointRedemptionRecord],
        now: Date
    ) -> PointRedemptionReconciliationResult {
        _ = totalPoints
        _ = now
        let projection = PointRedemptionLedger.projection(
            from: redemptionRecords,
            homeStickerPlacements: homeStickerPlacements,
            customRewards: customRewards
        )
        let didRevokeStickers = projection.homeStickerPlacements != homeStickerPlacements ||
            projection.stickerInventoryCounts != stickerInventoryCounts
        let didRevokeCustomRewards = projection.customRewards != customRewards

        return PointRedemptionReconciliationResult(
            stickerInventoryCounts: projection.stickerInventoryCounts,
            homeStickerPlacements: projection.homeStickerPlacements,
            customRewards: projection.customRewards,
            didRevokeStickers: didRevokeStickers,
            didRevokeCustomRewards: didRevokeCustomRewards,
            redemptionRecords: redemptionRecords,
            didUpdateLedger: false
        )
    }

}

enum PointRedemptionHistoryStore {
    static let didChange = Notification.Name("PointRedemptionHistoryDidChange")
    private static let maxRecordCount = 500

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    static var isLedgerInitialized: Bool {
        sharedDefaults.bool(forKey: AppSettings.pointRedemptionLedgerInitializedKey) ||
            UserDefaults.standard.bool(forKey: AppSettings.pointRedemptionLedgerInitializedKey)
    }

    static func markLedgerInitialized() {
        sharedDefaults.set(true, forKey: AppSettings.pointRedemptionLedgerInitializedKey)
        UserDefaults.standard.set(true, forKey: AppSettings.pointRedemptionLedgerInitializedKey)
    }

    static func load(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> [PointRedemptionRecord] {
        // Task undos in WidgetKit must see the same committed spend as the app.
        if let data = sharedDefaults.data(forKey: AppSettings.pointRedemptionHistoryKey),
           let records = try? JSONDecoder().decode([PointRedemptionRecord].self, from: data) {
            return records.sorted { $0.redeemedAt > $1.redeemedAt }
        }
        guard let data = UserDefaults.standard.data(forKey: AppSettings.pointRedemptionHistoryKey),
              let records = try? JSONDecoder().decode([PointRedemptionRecord].self, from: data) else {
            return []
        }

        if mode == .repairingMirrors {
            sharedDefaults.set(data, forKey: AppSettings.pointRedemptionHistoryKey)
            if isLedgerInitialized {
                markLedgerInitialized()
            }
        }
        return records.sorted { $0.redeemedAt > $1.redeemedAt }
    }

    static func append(_ record: PointRedemptionRecord) -> [PointRedemptionRecord]? {
        let records = normalizedRecords([record] + load())
        guard save(records) else { return nil }
        return records
    }

    @discardableResult
    static func save(_ records: [PointRedemptionRecord]) -> Bool {
        let normalized = normalizedRecords(records)
        let didUserStateChange = load() != normalized
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(normalized) else { return false }
        guard UserDefaults.standard.data(forKey: AppSettings.pointRedemptionHistoryKey) != data ||
                sharedDefaults.data(forKey: AppSettings.pointRedemptionHistoryKey) != data else {
            return true
        }
        let didSave = PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.pointRedemptionHistoryKey,
                newValue: data
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: AppSettings.pointRedemptionHistoryKey,
                newValue: data
            )
        ])
        if didSave, didUserStateChange {
            NotificationCenter.default.post(name: didChange, object: nil)
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        return didSave
    }

    static func clear() {
        let keys = [AppSettings.pointRedemptionHistoryKey, AppSettings.pointRedemptionLedgerInitializedKey]
        let defaults = [sharedDefaults, UserDefaults.standard]
        let hadRecords = defaults.contains { store in
            keys.contains { store.object(forKey: $0) != nil }
        }
        let didClear = PersistenceWriteTransaction.commit(defaults.flatMap { store in
            keys.map { key in
                PersistenceWriteTransaction.userDefaultsStep(defaults: store, key: key, newValue: nil)
            }
        })
        if didClear, hadRecords {
            NotificationCenter.default.post(name: didChange, object: nil)
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
    }

    private static func normalizedRecords(_ records: [PointRedemptionRecord]) -> [PointRedemptionRecord] {
        var seenIDs = Set<UUID>()
        let unique = records.filter { seenIDs.insert($0.id).inserted }
        let active = unique.filter(\.isActive).sorted { $0.redeemedAt > $1.redeemedAt }
        let revoked = unique.filter { !$0.isActive }.sorted { $0.redeemedAt > $1.redeemedAt }
        let retainedRevokedCount = max(maxRecordCount - active.count, 0)
        return (active + revoked.prefix(retainedRevokedCount)).sorted { $0.redeemedAt > $1.redeemedAt }
    }
}
