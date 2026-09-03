import Foundation

enum StickerStore {
    static func loadInventoryCounts() -> [StickerKind: Int] {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: AppSettings.stickerInventoryCountsKey),
           let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            let normalized = saved.reduce(into: [StickerKind: Int]()) { partial, entry in
                guard let kind = StickerKind(rawValue: entry.key), entry.value > 0 else { return }
                partial[kind] = 1
            }
            saveInventoryCounts(normalized, reportChange: false)
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
        if !migratedCounts.isEmpty {
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

    static func loadPlacements() -> [HomeStickerPlacement] {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.homeStickerPlacementsKey),
              let placements = try? JSONDecoder().decode([HomeStickerPlacement].self, from: data) else {
            return []
        }
        let normalized = normalizedPlacements(placements)
        savePlacements(normalized, reportChange: false)
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
        var seenKinds = Set<StickerKind>()
        var result: [HomeStickerPlacement] = []
        result.reserveCapacity(placements.count)

        for placement in placements {
            let normalized = placement.normalized()
            guard !seenKinds.contains(normalized.kind) else { continue }
            seenKinds.insert(normalized.kind)
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

    static func loadTotalPoints() -> Int? {
        if let state = loadState() {
            return state.totalPoints
        }
        if sharedDefaults.object(forKey: AppSettings.totalPointsKey) != nil {
            return sharedDefaults.integer(forKey: AppSettings.totalPointsKey)
        }
        guard UserDefaults.standard.object(forKey: AppSettings.totalPointsKey) != nil else { return nil }
        let points = UserDefaults.standard.integer(forKey: AppSettings.totalPointsKey)
        sharedDefaults.set(points, forKey: AppSettings.totalPointsKey)
        return points
    }

    static func loadPersistenceSnapshot() -> PointsPersistenceSnapshot {
        if let state = loadState() {
            return PointsPersistenceSnapshot(
                totalPoints: state.totalPoints,
                lifetimePoints: state.lifetimePoints,
                dailyRewardState: state.dailyRewardState
            )
        }

        return PointsPersistenceSnapshot(
            totalPoints: loadTotalPoints(),
            lifetimePoints: loadLifetimePoints(),
            dailyRewardState: loadDailyRewardState()
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

    static func loadLifetimePoints() -> Int? {
        if let state = loadState() {
            return state.lifetimePoints
        }
        if sharedDefaults.object(forKey: AppSettings.lifetimePointsKey) != nil {
            return sharedDefaults.integer(forKey: AppSettings.lifetimePointsKey)
        }
        guard UserDefaults.standard.object(forKey: AppSettings.lifetimePointsKey) != nil else { return nil }
        let points = UserDefaults.standard.integer(forKey: AppSettings.lifetimePointsKey)
        sharedDefaults.set(points, forKey: AppSettings.lifetimePointsKey)
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

    static func loadDailyRewardState() -> DailyRewardState? {
        if let state = loadState() {
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
        sharedDefaults.set(data, forKey: AppSettings.dailyRewardStateKey)
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

    private static func loadState() -> PersistedState? {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return nil
        }
        repairDefaultsIfNeeded(for: state)
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
    static func loadRewards() -> [CustomReward] {
        if let data = sharedDefaults.data(forKey: AppSettings.customRewardsKey),
           let rewards = try? JSONDecoder().decode([CustomReward].self, from: data) {
            if UserDefaults.standard.data(forKey: AppSettings.customRewardsKey) != data {
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

        _ = PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: AppSettings.customRewardsKey,
                newValue: data
            )
        ])
        return rewards
    }

    @discardableResult
    static func saveRewards(_ rewards: [CustomReward]) -> Bool {
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
    static func loadOrMigrate(
        stickerInventoryCounts: [StickerKind: Int],
        customRewards: [CustomReward]
    ) -> [PointRedemptionRecord]? {
        let records = PointRedemptionHistoryStore.load()
        guard !UserDefaults.standard.bool(forKey: AppSettings.pointRedemptionLedgerInitializedKey) else {
            return records
        }

        let migrated = recordsByAddingLegacyCoverage(
            to: records,
            stickerInventoryCounts: stickerInventoryCounts,
            customRewards: customRewards
        )
        guard PointRedemptionHistoryStore.save(migrated) else { return nil }
        UserDefaults.standard.set(true, forKey: AppSettings.pointRedemptionLedgerInitializedKey)
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
        let placements = homeStickerPlacements.filter { ownedStickerKinds.contains($0.kind) }
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

        var updatedInventory = stickerInventoryCounts
        var updatedPlacements = homeStickerPlacements
        var updatedRewards = customRewards
        var didRevokeStickers = false
        var didRevokeCustomRewards = false

        let pointBudget = max(totalPoints, 0)
        var currentSpent = spentStickerPoints(in: updatedInventory) + spentRewardPoints(in: updatedRewards)
        guard currentSpent > pointBudget else {
            return PointRedemptionReconciliationResult(
                stickerInventoryCounts: updatedInventory,
                homeStickerPlacements: updatedPlacements,
                customRewards: updatedRewards,
                didRevokeStickers: false,
                didRevokeCustomRewards: false
            )
        }

        while currentSpent > pointBudget {
            let stickerCandidate = nextStickerCandidate(in: updatedInventory)
            let rewardCandidate = nextRewardCandidate(in: updatedRewards)

            if shouldRevokeReward(rewardCandidate: rewardCandidate, stickerCandidate: stickerCandidate),
               let rewardCandidate {
                let refundPoints = rewardCandidate.points
                updatedRewards[rewardCandidate.index].redemptionCount = max(
                    updatedRewards[rewardCandidate.index].redemptionCount - 1,
                    0
                )
                updatedRewards[rewardCandidate.index].totalSpentPoints = max(
                    updatedRewards[rewardCandidate.index].totalSpentPoints - refundPoints,
                    0
                )
                if updatedRewards[rewardCandidate.index].totalSpentPoints == 0 {
                    updatedRewards[rewardCandidate.index].redemptionCount = 0
                }
                currentSpent -= refundPoints
                didRevokeCustomRewards = true
                continue
            }

            if let stickerCandidate {
                updatedInventory[stickerCandidate.kind] = 0
                updatedPlacements.removeAll { $0.kind == stickerCandidate.kind }
                currentSpent -= stickerCandidate.points
                didRevokeStickers = true
                continue
            }

            break
        }

        return PointRedemptionReconciliationResult(
            stickerInventoryCounts: updatedInventory,
            homeStickerPlacements: updatedPlacements,
            customRewards: updatedRewards,
            didRevokeStickers: didRevokeStickers,
            didRevokeCustomRewards: didRevokeCustomRewards
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
        var updatedRecords = redemptionRecords
        let pointBudget = max(totalPoints, 0)
        var currentSpent = activeLinkedSpend(in: updatedRecords)

        while currentSpent > pointBudget,
              let candidateIndex = nextLedgerRevocationIndex(in: updatedRecords) {
            let points = max(updatedRecords[candidateIndex].points, 0)
            updatedRecords[candidateIndex].revokedAt = now
            currentSpent -= points
        }

        let projection = PointRedemptionLedger.projection(
            from: updatedRecords,
            homeStickerPlacements: homeStickerPlacements,
            customRewards: customRewards
        )
        let didUpdateLedger = updatedRecords != redemptionRecords
        let didRevokeStickers = projection.homeStickerPlacements != homeStickerPlacements ||
            projection.stickerInventoryCounts != stickerInventoryCounts
        let didRevokeCustomRewards = projection.customRewards != customRewards

        return PointRedemptionReconciliationResult(
            stickerInventoryCounts: projection.stickerInventoryCounts,
            homeStickerPlacements: projection.homeStickerPlacements,
            customRewards: projection.customRewards,
            didRevokeStickers: didRevokeStickers,
            didRevokeCustomRewards: didRevokeCustomRewards,
            redemptionRecords: updatedRecords,
            didUpdateLedger: didUpdateLedger
        )
    }

    private static func activeLinkedSpend(in records: [PointRedemptionRecord]) -> Int {
        records.reduce(0) { partial, record in
            guard record.isActive, record.itemReferenceID != nil else { return partial }
            return partial + max(record.points, 0)
        }
    }

    private static func nextLedgerRevocationIndex(in records: [PointRedemptionRecord]) -> Int? {
        records.indices
            // A Blind Box ticket may already have been used to open a box. Its
            // ledger entry is therefore an irreversible purchase record, not a
            // revocable reward entitlement. If a legacy cross-device point
            // conflict leaves the overall ledger temporarily over budget, the
            // reconciling code may revoke an unfulfilled sticker/reward but
            // must never make a completed draw lose its paid ticket history.
            .filter {
                records[$0].isActive &&
                    records[$0].itemReferenceID != nil &&
                    records[$0].itemKind != .blindBoxTicket
            }
            .sorted { lhs, rhs in
                let left = records[lhs]
                let right = records[rhs]
                if left.points != right.points {
                    return left.points > right.points
                }
                if left.itemKind != right.itemKind {
                    return left.itemKind == .sticker
                }
                return left.redeemedAt > right.redeemedAt
            }
            .first
    }

    private struct StickerCandidate {
        let kind: StickerKind
        let points: Int
    }

    private struct RewardCandidate {
        let index: Int
        let points: Int
    }

    private static func nextStickerCandidate(in inventory: [StickerKind: Int]) -> StickerCandidate? {
        inventory
            .filter { $0.value > 0 }
            .map { StickerCandidate(kind: $0.key, points: $0.key.requiredPoints) }
            .sorted { lhs, rhs in
                if lhs.points == rhs.points {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                return lhs.points > rhs.points
            }
            .first
    }

    private static func nextRewardCandidate(in rewards: [CustomReward]) -> RewardCandidate? {
        rewards.indices
            .compactMap { index -> RewardCandidate? in
                let refundPoints = nextRewardRefundPoints(for: rewards[index])
                guard refundPoints > 0 else { return nil }
                return RewardCandidate(index: index, points: refundPoints)
            }
            .sorted { lhs, rhs in
                if lhs.points == rhs.points {
                    let lhsReward = rewards[lhs.index]
                    let rhsReward = rewards[rhs.index]
                    if lhsReward.title == rhsReward.title {
                        return lhsReward.id.uuidString < rhsReward.id.uuidString
                    }
                    return lhsReward.title < rhsReward.title
                }
                return lhs.points > rhs.points
            }
            .first
    }

    private static func shouldRevokeReward(
        rewardCandidate: RewardCandidate?,
        stickerCandidate: StickerCandidate?
    ) -> Bool {
        guard let rewardCandidate else { return false }
        guard let stickerCandidate else { return true }
        guard rewardCandidate.points != stickerCandidate.points else { return false }
        return rewardCandidate.points > stickerCandidate.points
    }

    private static func nextRewardRefundPoints(for reward: CustomReward) -> Int {
        guard reward.redemptionCount > 0, reward.totalSpentPoints > 0 else { return 0 }
        let averageSpent = Int(ceil(Double(reward.totalSpentPoints) / Double(reward.redemptionCount)))
        return min(max(averageSpent, 1), reward.totalSpentPoints)
    }

    private static func spentStickerPoints(in inventory: [StickerKind: Int]) -> Int {
        inventory.reduce(0) { partial, entry in
            partial + (entry.key.requiredPoints * entry.value)
        }
    }

    private static func spentRewardPoints(in rewards: [CustomReward]) -> Int {
        rewards.reduce(0) { partial, reward in
            partial + reward.totalSpentPoints
        }
    }
}

enum PointRedemptionHistoryStore {
    private static let maxRecordCount = 500

    static func load() -> [PointRedemptionRecord] {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.pointRedemptionHistoryKey),
              let records = try? JSONDecoder().decode([PointRedemptionRecord].self, from: data) else {
            return []
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
        guard UserDefaults.standard.data(forKey: AppSettings.pointRedemptionHistoryKey) != data else {
            return true
        }
        UserDefaults.standard.set(data, forKey: AppSettings.pointRedemptionHistoryKey)
        let didSave = UserDefaults.standard.data(forKey: AppSettings.pointRedemptionHistoryKey) == data
        if didSave, didUserStateChange {
            NativeICloudLocalChangeReporter.primaryStateDidChange()
        }
        return didSave
    }

    static func clear() {
        let didChange = UserDefaults.standard.object(forKey: AppSettings.pointRedemptionHistoryKey) != nil ||
            UserDefaults.standard.object(forKey: AppSettings.pointRedemptionLedgerInitializedKey) != nil
        UserDefaults.standard.removeObject(forKey: AppSettings.pointRedemptionHistoryKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.pointRedemptionLedgerInitializedKey)
        if didChange {
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
