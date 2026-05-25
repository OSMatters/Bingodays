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
            saveInventoryCounts(normalized)
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
            saveInventoryCounts(migratedCounts)
        }
        return migratedCounts
    }

    static func saveInventoryCounts(_ counts: [StickerKind: Int]) {
        let payload = counts.reduce(into: [String: Int]()) { partial, entry in
            guard entry.value > 0 else { return }
            partial[entry.key.rawValue] = 1
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.stickerInventoryCountsKey)
    }

    static func loadPlacements() -> [HomeStickerPlacement] {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.homeStickerPlacementsKey),
              let placements = try? JSONDecoder().decode([HomeStickerPlacement].self, from: data) else {
            return []
        }
        let normalized = normalizedPlacements(placements)
        savePlacements(normalized)
        return normalized
    }

    static func savePlacements(_ placements: [HomeStickerPlacement]) {
        let normalized = normalizedPlacements(placements)
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.homeStickerPlacementsKey)
    }

    static func clearPlacements() {
        UserDefaults.standard.removeObject(forKey: AppSettings.homeStickerPlacementsKey)
    }

    static func clearInventoryCounts() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppSettings.stickerInventoryCountsKey)
        defaults.removeObject(forKey: AppSettings.redeemedStickersKey)
        defaults.removeObject(forKey: AppSettings.redeemedStickerOrderKey)
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

enum PointsStore {
    static func loadTotalPoints() -> Int? {
        if sharedDefaults.object(forKey: AppSettings.totalPointsKey) != nil {
            return sharedDefaults.integer(forKey: AppSettings.totalPointsKey)
        }
        guard UserDefaults.standard.object(forKey: AppSettings.totalPointsKey) != nil else { return nil }
        let points = UserDefaults.standard.integer(forKey: AppSettings.totalPointsKey)
        sharedDefaults.set(points, forKey: AppSettings.totalPointsKey)
        return points
    }

    static func saveTotalPoints(_ points: Int) {
        sharedDefaults.set(points, forKey: AppSettings.totalPointsKey)
        UserDefaults.standard.set(points, forKey: AppSettings.totalPointsKey)
    }

    static func loadLifetimePoints() -> Int? {
        if sharedDefaults.object(forKey: AppSettings.lifetimePointsKey) != nil {
            return sharedDefaults.integer(forKey: AppSettings.lifetimePointsKey)
        }
        guard UserDefaults.standard.object(forKey: AppSettings.lifetimePointsKey) != nil else { return nil }
        let points = UserDefaults.standard.integer(forKey: AppSettings.lifetimePointsKey)
        sharedDefaults.set(points, forKey: AppSettings.lifetimePointsKey)
        return points
    }

    static func saveLifetimePoints(_ points: Int) {
        sharedDefaults.set(points, forKey: AppSettings.lifetimePointsKey)
        UserDefaults.standard.set(points, forKey: AppSettings.lifetimePointsKey)
    }

    static func loadDailyRewardState() -> DailyRewardState? {
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
        guard let data = try? JSONEncoder().encode(state) else { return }
        sharedDefaults.set(data, forKey: AppSettings.dailyRewardStateKey)
        UserDefaults.standard.set(data, forKey: AppSettings.dailyRewardStateKey)
    }

    static func clearDailyRewardState() {
        sharedDefaults.removeObject(forKey: AppSettings.dailyRewardStateKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.dailyRewardStateKey)
    }

    static func clearTotalPoints() {
        sharedDefaults.removeObject(forKey: AppSettings.totalPointsKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.totalPointsKey)
    }

    static func clearLifetimePoints() {
        sharedDefaults.removeObject(forKey: AppSettings.lifetimePointsKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.lifetimePointsKey)
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }
}

enum RewardStore {
    static func loadRewards() -> [CustomReward] {
        if let data = sharedDefaults.data(forKey: AppSettings.customRewardsKey),
           let rewards = try? JSONDecoder().decode([CustomReward].self, from: data) {
            return rewards
        }
        guard let data = UserDefaults.standard.data(forKey: AppSettings.customRewardsKey),
              let rewards = try? JSONDecoder().decode([CustomReward].self, from: data) else {
            return []
        }

        sharedDefaults.set(data, forKey: AppSettings.customRewardsKey)
        return rewards
    }

    static func saveRewards(_ rewards: [CustomReward]) {
        guard let data = try? JSONEncoder().encode(rewards) else { return }
        sharedDefaults.set(data, forKey: AppSettings.customRewardsKey)
        UserDefaults.standard.set(data, forKey: AppSettings.customRewardsKey)
    }

    static func clearRewards() {
        sharedDefaults.removeObject(forKey: AppSettings.customRewardsKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.customRewardsKey)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
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

    static func append(_ record: PointRedemptionRecord) -> [PointRedemptionRecord] {
        let records = Array(([record] + load()).prefix(maxRecordCount))
        save(records)
        return records
    }

    static func save(_ records: [PointRedemptionRecord]) {
        let normalized = Array(records.sorted { $0.redeemedAt > $1.redeemedAt }.prefix(maxRecordCount))
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.pointRedemptionHistoryKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: AppSettings.pointRedemptionHistoryKey)
    }
}
