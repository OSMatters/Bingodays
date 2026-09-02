import SwiftUI

/// Gate A presentation data only. It lets the Figma flow be exercised without
/// touching the user's existing points, legacy stickers, or CloudKit records.
/// The later CloudKit repository will replace this object at the same view-model
/// boundary rather than changing the view hierarchy.
@MainActor
final class BlindBoxPreviewStore: ObservableObject {
    @Published private(set) var state: BlindBoxAccountState
    @Published private(set) var lastOpenResult: BlindBoxOpenResult?

    let themes: [BlindBoxThemeDefinition]

    init(
        themes: [BlindBoxThemeDefinition] = BlindBoxCatalog.builtInThemes,
        referenceDate: Date = .now
    ) {
        self.themes = themes
        self.state = Self.makeFixture(themes: themes, referenceDate: referenceDate)
    }

    func theme(for id: BlindBoxThemeID) -> BlindBoxThemeDefinition? {
        themes.first(where: { $0.id == id })
    }

    func candidates(hasPremiumAccess: Bool) -> [BlindBoxCandidateBatch] {
        Array(state.candidateBatches.prefix(BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: hasPremiumAccess)))
    }

    func openSingle(batchID: UUID, positionIndex: Int, openedAt: Date = .now) throws -> BlindBoxOpenResult {
        let result = try BlindBoxStateMachine.openSingle(
            state: &state,
            batchID: batchID,
            positionIndex: positionIndex,
            openedAt: openedAt
        )
        lastOpenResult = result
        return result
    }

    func openWholeBox(batchID: UUID, openedAt: Date = .now) throws -> BlindBoxOpenResult {
        let result = try BlindBoxStateMachine.openWholeBox(
            state: &state,
            batchID: batchID,
            openedAt: openedAt
        )
        lastOpenResult = result
        return result
    }

    func count(for stickerID: BlindBoxStickerID) -> Int {
        state.ownedCount(for: stickerID)
    }

    private static func makeFixture(
        themes: [BlindBoxThemeDefinition],
        referenceDate: Date
    ) -> BlindBoxAccountState {
        guard let pets = themes.first(where: { $0.id.rawValue == "pets" }),
              let cozy = themes.first(where: { $0.id.rawValue == "cozy_daily" }) else {
            return BlindBoxAccountState(ticketBalance: BlindBoxRuleConfiguration.maximumTicketBalance)
        }

        let petsBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000001",
            theme: pets,
            stickerIDs: ["pets_01", "pets_02", "pets_03", "pets_04", "pets_05", "pets_11", "pets_07", "pets_08", "pets_09"],
            createdAt: referenceDate
        )
        let cozyBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000002",
            theme: cozy,
            stickerIDs: ["cozy_01", "cozy_02", "cozy_03", "cozy_04", "cozy_05", "cozy_06", "cozy_07", "cozy_08", "cozy_01"],
            createdAt: referenceDate
        )
        let petsSecondBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000003",
            theme: pets,
            stickerIDs: ["pets_10", "pets_04", "pets_08", "pets_06", "pets_11", "pets_03", "pets_05", "pets_02", "pets_01"],
            createdAt: referenceDate
        )
        let cozySecondBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000004",
            theme: cozy,
            stickerIDs: ["cozy_08", "cozy_07", "cozy_06", "cozy_05", "cozy_04", "cozy_03", "cozy_02", "cozy_01", "cozy_07"],
            createdAt: referenceDate
        )
        let petsThirdBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000005",
            theme: pets,
            stickerIDs: ["pets_09", "pets_10", "pets_08", "pets_07", "pets_06", "pets_05", "pets_04", "pets_03", "pets_02"],
            createdAt: referenceDate
        )
        let cozyThirdBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000006",
            theme: cozy,
            stickerIDs: ["cozy_02", "cozy_03", "cozy_04", "cozy_05", "cozy_06", "cozy_07", "cozy_08", "cozy_01", "cozy_04"],
            createdAt: referenceDate
        )

        let allIndices = Set(0..<BlindBoxRuleConfiguration.batchPositionCount)
        return BlindBoxAccountState(
            ticketBalance: BlindBoxRuleConfiguration.maximumTicketBalance,
            ownedStickerCounts: [
                "pets_02": 1,
                "pets_03": 1,
                "pets_08": 1,
                "pets_09": 1,
                "pets_11": 1,
                "cozy_01": 1,
                "cozy_04": 1
            ],
            candidateBatches: [
                BlindBoxCandidateBatch(
                    plan: petsBatch,
                    openedPositionIndices: [5],
                    systemOpenedPositionIndices: [5],
                    firstPresentedAt: referenceDate,
                    nextSystemOpenAt: referenceDate.addingTimeInterval(90 * 60)
                ),
                BlindBoxCandidateBatch(
                    plan: cozyBatch,
                    openedPositionIndices: allIndices,
                    systemOpenedPositionIndices: allIndices,
                    firstPresentedAt: referenceDate.addingTimeInterval(-3 * 60 * 60),
                    soldOutAt: referenceDate.addingTimeInterval(-3 * 60 * 60)
                ),
                BlindBoxCandidateBatch(plan: cozySecondBatch),
                BlindBoxCandidateBatch(plan: petsSecondBatch),
                BlindBoxCandidateBatch(plan: cozyThirdBatch),
                BlindBoxCandidateBatch(plan: petsThirdBatch)
            ]
        )
    }

    private static func fixturePlan(
        id: String,
        theme: BlindBoxThemeDefinition,
        stickerIDs: [String],
        createdAt: Date
    ) -> BlindBoxBatchPlan {
        BlindBoxBatchPlan(
            id: UUID(uuidString: id)!,
            themeID: theme.id,
            catalogVersion: theme.catalogVersion,
            probabilityMode: .standard,
            createdAt: createdAt,
            positions: stickerIDs.enumerated().map { index, stickerID in
                BlindBoxPositionPlan(
                    index: index,
                    stickerID: BlindBoxStickerID(rawValue: stickerID)
                )
            }
        )
    }
}
