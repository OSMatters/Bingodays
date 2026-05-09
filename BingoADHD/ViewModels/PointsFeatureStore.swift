import Foundation

@MainActor
final class PointsFeatureStore: ObservableObject {
    @Published private(set) var stickerInventoryCounts: [StickerKind: Int] = [:]
    @Published private(set) var homeStickerPlacements: [HomeStickerPlacement] = []
    @Published private(set) var customRewards: [CustomReward] = []

    private var hasLoadedStores = false

    var activeRewards: [CustomReward] {
        customRewards.filter { !$0.isArchived }
    }

    var currentStickerUsageCounts: [StickerKind: Int] {
        homeStickerPlacements.reduce(into: [:]) { partial, placement in
            partial[placement.kind, default: 0] += 1
        }
    }

    func availablePoints(totalPoints: Int) -> Int {
        max(totalPoints - spentStickerPoints - spentRewardPoints, 0)
    }

    func loadAfterFirstFrameIfNeeded() {
        guard !hasLoadedStores else { return }
        hasLoadedStores = true

        Task.detached(priority: .utility) {
            let inventoryCounts = StickerStore.loadInventoryCounts()
            let placements = StickerStore.loadPlacements()
            let rewards = RewardStore.loadRewards()

            await MainActor.run {
                self.stickerInventoryCounts = inventoryCounts
                self.homeStickerPlacements = placements
                self.customRewards = rewards
            }
        }
    }

    func redeemSticker(_ kind: StickerKind, totalPoints: Int) {
        guard availablePoints(totalPoints: totalPoints) >= kind.requiredPoints else { return }
        guard stickerInventoryCounts[kind] != 1 else { return }

        stickerInventoryCounts[kind] = 1
        StickerStore.saveInventoryCounts(stickerInventoryCounts)
        AnalyticsService.logStickerRedeemed(kind)
    }

    @discardableResult
    func reconcileStickerOwnershipIfPointsInsufficient(totalPoints: Int) -> Bool {
        let stickerBudget = max(totalPoints - spentRewardPoints, 0)
        var updatedInventory = stickerInventoryCounts
        var updatedPlacements = homeStickerPlacements

        var currentStickerCost = updatedInventory.reduce(0) { partial, entry in
            partial + (entry.key.requiredPoints * entry.value)
        }
        guard currentStickerCost > stickerBudget else { return false }

        let ownedKinds = updatedInventory
            .filter { $0.value > 0 }
            .map(\.key)
            .sorted { lhs, rhs in
                if lhs.requiredPoints == rhs.requiredPoints {
                    return lhs.rawValue < rhs.rawValue
                }
                return lhs.requiredPoints > rhs.requiredPoints
            }

        var didChange = false
        for kind in ownedKinds where currentStickerCost > stickerBudget {
            guard updatedInventory[kind, default: 0] > 0 else { continue }
            updatedInventory[kind] = 0
            updatedPlacements.removeAll { $0.kind == kind }
            currentStickerCost -= kind.requiredPoints
            didChange = true
        }

        guard didChange else { return false }
        stickerInventoryCounts = updatedInventory
        homeStickerPlacements = updatedPlacements
        StickerStore.saveInventoryCounts(updatedInventory)
        StickerStore.savePlacements(updatedPlacements)
        return true
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

    func createReward(title: String, requiredPoints: Int, emoji: String) {
        let trimmedTitle = String(title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPoints = min(max(requiredPoints, 1), 9_999)
        guard !trimmedTitle.isEmpty else { return }

        customRewards.append(
            CustomReward(
                title: trimmedTitle,
                requiredPoints: normalizedPoints,
                emoji: emoji
            )
        )
        RewardStore.saveRewards(customRewards)
    }

    func updateReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        let trimmedTitle = String(reward.title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        customRewards[index].title = trimmedTitle
        customRewards[index].requiredPoints = min(max(reward.requiredPoints, 1), 9_999)
        customRewards[index].emoji = reward.emoji
        RewardStore.saveRewards(customRewards)
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

        customRewards[index].redemptionCount += 1
        customRewards[index].totalSpentPoints += requiredPoints
        RewardStore.saveRewards(customRewards)
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

    private func availableStickerCount(for kind: StickerKind) -> Int {
        max((stickerInventoryCounts[kind] ?? 0) - (currentStickerUsageCounts[kind] ?? 0), 0)
    }
}
