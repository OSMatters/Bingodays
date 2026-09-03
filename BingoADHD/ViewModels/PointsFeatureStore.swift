import Foundation

@MainActor
final class PointsFeatureStore: ObservableObject {
    @Published private(set) var stickerInventoryCounts: [StickerKind: Int] = [:]
    @Published private(set) var homeStickerPlacements: [HomeStickerPlacement] = []
    @Published private(set) var customRewards: [CustomReward] = []
    @Published private(set) var redemptionHistory: [PointRedemptionRecord] = []

    private var hasLoadedStores = false

    init() {
        loadPersistedStores()
    }

    var activeRewards: [CustomReward] {
        customRewards.filter { !$0.isArchived }
    }

    var currentStickerUsageCounts: [StickerKind: Int] {
        homeStickerPlacements.reduce(into: [:]) { partial, placement in
            partial[placement.kind, default: 0] += 1
        }
    }

    func availablePoints(totalPoints: Int) -> Int {
        max(totalPoints - spentStickerPoints - spentRewardPoints - spentBlindBoxTicketPoints, 0)
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
        AppHaptics.completion()
        AnalyticsService.logStickerRedeemed(kind)
    }

    @discardableResult
    func reconcileRedemptionsIfPointsInsufficient(totalPoints: Int) -> PointRedemptionReconciliationResult {
        let ledgerRecords = PointRedemptionLedger.loadOrMigrate(
            stickerInventoryCounts: stickerInventoryCounts,
            customRewards: customRewards
        )
        let result = PointRedemptionReconciler.reconcileRedemptionsIfNeeded(
            totalPoints: totalPoints,
            stickerInventoryCounts: stickerInventoryCounts,
            homeStickerPlacements: homeStickerPlacements,
            customRewards: customRewards,
            redemptionRecords: ledgerRecords
        )
        guard result.didChange else { return result }

        stickerInventoryCounts = result.stickerInventoryCounts
        homeStickerPlacements = result.homeStickerPlacements
        customRewards = result.customRewards
        PointRedemptionReconciler.persist(result)
        redemptionHistory = (result.redemptionRecords ?? PointRedemptionHistoryStore.load()).filter(\.isActive)
        return result
    }

    @discardableResult
    func reconcileStickerOwnershipIfPointsInsufficient(totalPoints: Int) -> Bool {
        reconcileRedemptionsIfPointsInsufficient(totalPoints: totalPoints).didChange
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
        let trimmedTitle = String(title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPoints = min(max(requiredPoints, 1), 9_999)
        guard !trimmedTitle.isEmpty else { return false }
        guard canCreateReward(hasPremiumAccess: hasPremiumAccess) else { return false }

        var updatedRewards = customRewards
        updatedRewards.append(
            CustomReward(
                title: trimmedTitle,
                requiredPoints: normalizedPoints,
                emoji: emoji,
                themeImageName: themeImageName
            )
        )
        guard RewardStore.saveRewards(updatedRewards) else { return false }
        customRewards = updatedRewards
        AnalyticsService.logCustomRewardVisualUsed(
            action: .create,
            emoji: emoji,
            themeImageName: themeImageName
        )
        return true
    }

    func updateReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        let trimmedTitle = String(reward.title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

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
        guard RewardStore.saveRewards(updatedRewards) else { return }
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
        AppHaptics.completion()
    }

    private var spentStickerPoints: Int {
        stickerInventoryCounts.reduce(0) { partial, entry in
            partial + (entry.key.requiredPoints * entry.value)
        }
    }

    private var spentRewardPoints: Int {
        customRewards.reduce(0) { partial, reward in
            partial + reward.totalSpentPoints
        }
    }

    /// Blind Box tickets live in the same point-spend ledger as stickers and
    /// custom rewards, while their ownership is authoritatively stored in the
    /// private Blind Box CloudKit zone. Counting only active ticket records
    /// keeps the familiar points balance correct without turning the lifetime
    /// `totalPoints` counter into a mutable wallet.
    private var spentBlindBoxTicketPoints: Int {
        redemptionHistory.reduce(0) { partial, record in
            guard record.isActive, record.itemKind == .blindBoxTicket else {
                return partial
            }
            return partial + max(record.points, 0)
        }
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
    }

    private func availableStickerCount(for kind: StickerKind) -> Int {
        max((stickerInventoryCounts[kind] ?? 0) - (currentStickerUsageCounts[kind] ?? 0), 0)
    }
}
