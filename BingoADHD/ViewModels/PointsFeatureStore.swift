import Foundation
import Combine

enum CustomRewardCreationResult: Equatable {
    case created
    case premiumRequired
    case persistenceFailed
    case invalidInput
    case rewardUnavailable
    case dataChanged
}

@MainActor
final class PointsFeatureStore: ObservableObject {
    @Published private(set) var stickerInventoryCounts: [StickerKind: Int] = [:]
    @Published private(set) var homeStickerPlacements: [HomeStickerPlacement] = []
    @Published private(set) var customRewards: [CustomReward] = []
    @Published private(set) var redemptionHistory: [PointRedemptionRecord] = []
    @Published private(set) var committedSpendPoints = 0

    private var hasLoadedStores = false
    private var redemptionHistoryObservation: AnyCancellable?

    init() {
        loadPersistedStores()
        redemptionHistoryObservation = NotificationCenter.default
            .publisher(for: PointRedemptionHistoryStore.didChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadPersistedStores()
            }
    }

    var activeRewards: [CustomReward] {
        customRewards.filter { !$0.isArchived }
    }

    var currentStickerUsageCounts: [StickerKind: Int] {
        homeStickerPlacements.reduce(into: [:]) { partial, placement in
            guard let kind = placement.legacyKind else { return }
            partial[kind, default: 0] += 1
        }
    }

    func availablePoints(totalPoints: Int) -> Int {
        max(totalPoints - committedSpendPoints, 0)
    }

    func loadAfterFirstFrameIfNeeded() {
        guard !hasLoadedStores else { return }
        loadPersistedStores()
    }

    func reloadAfterExternalDataChange() {
        loadPersistedStores()
    }

    func redeemSticker(_ kind: StickerKind, totalPoints: Int) {
        guard availablePoints(totalPoints: totalPoints) >= kind.requiredPoints else { return }
        guard stickerInventoryCounts[kind] != 1 else { return }

        guard let records = PointRedemptionHistoryStore.append(
            PointRedemptionRecord(
                itemKind: .sticker,
                title: kind.redemptionHistoryTitle,
                points: kind.requiredPoints,
                imageName: kind.unlockedImageName,
                itemReferenceID: PointRedemptionRecord.stickerReferenceID(kind)
            )
        ) else { return }
        redemptionHistory = records.filter(\.isActive)
        stickerInventoryCounts[kind] = 1
        StickerStore.saveInventoryCounts(stickerInventoryCounts)
        committedSpendPoints = PointRedemptionLedger.committedSpend(in: records)
        AppHaptics.completion()
        AnalyticsService.logStickerRedeemed(kind)
    }

    func containsPlacement(id: UUID) -> Bool {
        homeStickerPlacements.contains { $0.id == id }
    }

    @discardableResult
    func addStickerToHome(_ kind: StickerKind) -> Bool {
        guard availableStickerCount(for: kind) > 0 else { return false }

        let placement = HomeStickerPlacement(
            kind: kind,
            xRatio: kind.defaultPlacement.xRatio,
            yRatio: kind.defaultPlacement.yRatio
        )
        homeStickerPlacements.append(placement)
        StickerStore.savePlacements(homeStickerPlacements)
        return true
    }

    func isBlindBoxStickerOnHome(_ stickerID: BlindBoxStickerID) -> Bool {
        blindBoxStickerHomeCount(stickerID) > 0
    }

    func blindBoxStickerHomeCount(_ stickerID: BlindBoxStickerID) -> Int {
        homeStickerPlacements.reduce(into: 0) { count, placement in
            if placement.blindBoxStickerID == stickerID.rawValue {
                count += 1
            }
        }
    }

    @discardableResult
    func addBlindBoxStickerToHome(
        _ sticker: BlindBoxStickerDefinition,
        maximumCount: Int = 1,
        preferredYRatio: Double? = nil
    ) -> Bool {
        let existingCount = blindBoxStickerHomeCount(sticker.id)
        guard existingCount < max(maximumCount, 1) else { return false }

        let defaultPlacement = defaultBlindBoxStickerPlacement(for: sticker.id)
        let duplicateOffsets: [(x: Double, y: Double)] = [
            (0, 0),
            (0.12, 0.08),
            (-0.12, 0.16),
            (0.12, 0.24)
        ]
        let offset = duplicateOffsets[min(existingCount, duplicateOffsets.count - 1)]
        let placement = HomeStickerPlacement(
            blindBoxStickerID: sticker.id.rawValue,
            assetName: sticker.assetName,
            xRatio: min(max(defaultPlacement.xRatio + offset.x, 0.08), 0.92),
            yRatio: min(max((preferredYRatio ?? defaultPlacement.yRatio) + offset.y, 0.08), 1.02)
        )
        homeStickerPlacements.append(placement)
        StickerStore.savePlacements(homeStickerPlacements)
        return true
    }

    func updateStickerPlacement(_ placement: HomeStickerPlacement) {
        guard let index = homeStickerPlacements.firstIndex(where: { $0.id == placement.id }) else { return }
        homeStickerPlacements[index] = placement
        StickerStore.savePlacements(homeStickerPlacements)
    }

    func deleteStickerPlacement(id: UUID) {
        homeStickerPlacements.removeAll { $0.id == id }
        StickerStore.savePlacements(homeStickerPlacements)
    }

    func canCreateReward(hasPremiumAccess: Bool) -> Bool {
        hasPremiumAccess || activeRewards.count < AppSettings.maxFreeCustomRewards
    }

    @discardableResult
    func createReward(
        title: String,
        requiredPoints: Int,
        emoji: String,
        themeImageName: String? = nil,
        hasPremiumAccess: Bool
    ) -> Bool {
        createRewardResult(
            title: title,
            requiredPoints: requiredPoints,
            emoji: emoji,
            themeImageName: themeImageName,
            hasPremiumAccess: hasPremiumAccess
        ) == .created
    }

    @discardableResult
    func createRewardResult(
        title: String,
        requiredPoints: Int,
        emoji: String,
        themeImageName: String? = nil,
        hasPremiumAccess: Bool
    ) -> CustomRewardCreationResult {
        guard refreshRewardsIfChanged() == false else { return .dataChanged }
        let trimmedTitle = String(title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPoints = min(max(requiredPoints, 1), 9_999)
        guard !trimmedTitle.isEmpty, (1...9_999).contains(requiredPoints) else { return .invalidInput }
        guard canCreateReward(hasPremiumAccess: hasPremiumAccess) else { return .premiumRequired }

        var updatedRewards = customRewards
        updatedRewards.append(
            CustomReward(
                title: trimmedTitle,
                requiredPoints: normalizedPoints,
                emoji: emoji,
                themeImageName: themeImageName
            )
        )
        guard RewardStore.saveRewards(updatedRewards) else { return .persistenceFailed }
        customRewards = updatedRewards
        AnalyticsService.logCustomRewardVisualUsed(
            action: .create,
            emoji: emoji,
            themeImageName: themeImageName
        )
        return .created
    }

    @discardableResult
    func updateReward(_ reward: CustomReward) -> CustomRewardCreationResult {
        guard refreshRewardsIfChanged() == false else { return .dataChanged }
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }),
              !customRewards[index].isArchived else { return .rewardUnavailable }
        let trimmedTitle = String(reward.title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, (1...9_999).contains(reward.requiredPoints) else { return .invalidInput }

        let previousVisual = AnalyticsEventContract.customRewardVisual(
            emoji: customRewards[index].emoji,
            themeImageName: customRewards[index].themeImageName
        )
        var updatedRewards = customRewards
        updatedRewards[index].title = trimmedTitle
        updatedRewards[index].requiredPoints = min(max(reward.requiredPoints, 1), 9_999)
        updatedRewards[index].emoji = reward.emoji
        updatedRewards[index].themeImageName = reward.themeImageName
        updatedRewards[index].cardStyleVersion = CustomReward.currentCardStyleVersion
        guard RewardStore.saveRewards(updatedRewards) else { return .persistenceFailed }
        customRewards = updatedRewards

        let updatedVisual = AnalyticsEventContract.customRewardVisual(
            emoji: reward.emoji,
            themeImageName: reward.themeImageName
        )
        if updatedVisual != previousVisual {
            AnalyticsService.logCustomRewardVisualUsed(
                action: .update,
                emoji: reward.emoji,
                themeImageName: reward.themeImageName
            )
        }
        return .created
    }

    /// Reject a stale editor write rather than replacing rewards imported since
    /// this store last loaded. The user's draft stays in the editor for retry.
    private func refreshRewardsIfChanged() -> Bool {
        let persistedRewards = RewardStore.loadRewards(reading: .readOnly)
        guard persistedRewards != customRewards else { return false }
        DiagnosticLogStore.recordWarning("custom_reward.stale_write_rejected", details: [
            "local_count": "\(customRewards.count)", "persisted_count": "\(persistedRewards.count)"
        ])
        customRewards = persistedRewards
        return true
    }

    @discardableResult
    func reorderRewards(_ orderedActiveRewards: [CustomReward]) -> Bool {
        let currentActiveRewards = activeRewards
        guard orderedActiveRewards.count == currentActiveRewards.count,
              Set(orderedActiveRewards.map(\.id)).count == orderedActiveRewards.count,
              Set(orderedActiveRewards.map(\.id)) == Set(currentActiveRewards.map(\.id)) else {
            return false
        }

        guard orderedActiveRewards.map(\.id) != currentActiveRewards.map(\.id) else {
            return true
        }

        var activeIndex = 0
        let updatedRewards = customRewards.map { reward in
            guard !reward.isArchived else { return reward }
            defer { activeIndex += 1 }
            return orderedActiveRewards[activeIndex]
        }

        guard RewardStore.saveRewards(updatedRewards) else { return false }
        customRewards = updatedRewards
        return true
    }

    func archiveReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        customRewards[index].isArchived = true
        RewardStore.saveRewards(customRewards)
    }

    func redeemReward(_ reward: CustomReward, totalPoints: Int) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        let requiredPoints = customRewards[index].requiredPoints
        guard availablePoints(totalPoints: totalPoints) >= requiredPoints else { return }

        guard let records = PointRedemptionHistoryStore.append(
            PointRedemptionRecord(
                itemKind: .customReward,
                title: customRewards[index].title,
                points: requiredPoints,
                imageName: customRewards[index].themeImageName,
                emoji: customRewards[index].themeImageName == nil ? customRewards[index].displayEmoji : nil,
                itemReferenceID: PointRedemptionRecord.customRewardReferenceID(customRewards[index].id)
            )
        ) else { return }
        redemptionHistory = records.filter(\.isActive)
        customRewards[index].redemptionCount += 1
        customRewards[index].totalSpentPoints += requiredPoints
        RewardStore.saveRewards(customRewards)
        committedSpendPoints = PointRedemptionLedger.committedSpend(in: records)
        AppHaptics.completion()
    }

    private func loadPersistedStores() {
        hasLoadedStores = true
        stickerInventoryCounts = StickerStore.loadInventoryCounts()
        homeStickerPlacements = StickerStore.loadPlacements()
        customRewards = RewardStore.loadRewards()
        guard let ledgerRecords = PointRedemptionLedger.loadOrMigrate(
            stickerInventoryCounts: stickerInventoryCounts,
            customRewards: customRewards
        ) else {
            redemptionHistory = PointRedemptionHistoryStore.load().filter(\.isActive)
            committedSpendPoints = PointRedemptionLedger.committedSpend(in: redemptionHistory)
            return
        }
        let projection = PointRedemptionLedger.projection(
            from: ledgerRecords,
            homeStickerPlacements: homeStickerPlacements,
            customRewards: customRewards
        )
        if projection.stickerInventoryCounts != stickerInventoryCounts {
            stickerInventoryCounts = projection.stickerInventoryCounts
            StickerStore.saveInventoryCounts(stickerInventoryCounts)
        }
        if projection.homeStickerPlacements != homeStickerPlacements {
            homeStickerPlacements = projection.homeStickerPlacements
            StickerStore.savePlacements(homeStickerPlacements)
        }
        if projection.customRewards != customRewards {
            customRewards = projection.customRewards
            RewardStore.saveRewards(customRewards)
        }
        redemptionHistory = ledgerRecords.filter(\.isActive)
        committedSpendPoints = PointRedemptionLedger.committedSpend(in: ledgerRecords)
    }

    private func defaultBlindBoxStickerPlacement(
        for stickerID: BlindBoxStickerID
    ) -> (xRatio: Double, yRatio: Double) {
        // Use a stable ID-derived spot so adding several Blind Box stickers
        // starts them apart instead of stacking them in the centre. Users can
        // still drag and resize every placement on the Home screen.
        let placements: [(Double, Double)] = [
            (0.18, 0.24), (0.50, 0.18), (0.80, 0.25),
            (0.24, 0.48), (0.56, 0.44), (0.80, 0.54),
            (0.18, 0.72), (0.48, 0.78), (0.78, 0.76)
        ]
        let index = stickerID.rawValue.unicodeScalars.reduce(0) {
            ($0 &* 31 &+ Int($1.value)) % placements.count
        }
        return placements[index]
    }

    private func availableStickerCount(for kind: StickerKind) -> Int {
        max((stickerInventoryCounts[kind] ?? 0) - (currentStickerUsageCounts[kind] ?? 0), 0)
    }
}
