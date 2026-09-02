import XCTest
@testable import Bingodays

final class BlindBoxRuleEngineTests: XCTestCase {
    func testBuiltInThemesMatchConfiguredContentCounts() {
        XCTAssertEqual(BlindBoxCatalog.builtInThemes.count, 2)

        let pets = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }
        XCTAssertEqual(pets?.normalStickers.count, 11)
        XCTAssertEqual(pets?.hiddenSticker?.id.rawValue, "pets_12")
        XCTAssertEqual(pets?.hiddenSticker?.assetName, "sticker_pets_12_hidden")
        XCTAssertNil(pets?.validationError())

        let cozyDaily = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "cozy_daily" }
        XCTAssertEqual(cozyDaily?.normalStickers.count, 8)
        XCTAssertEqual(cozyDaily?.hiddenSticker?.id.rawValue, "cozy_09")
        XCTAssertEqual(cozyDaily?.hiddenSticker?.assetName, "sticker_cozy_09_hidden")
        XCTAssertNil(cozyDaily?.validationError())
    }

    func testHiddenHuntRequiresEveryNormalStickerAndNoHiddenSticker() {
        let theme = petsTheme
        let allNormalsOwned = Dictionary(
            uniqueKeysWithValues: theme.normalStickers.map { ($0.id, 1) }
        )

        XCTAssertEqual(
            BlindBoxProbabilityEngine.mode(for: theme, ownedCounts: allNormalsOwned),
            .hiddenHunt
        )

        var missingOneNormal = allNormalsOwned
        missingOneNormal[theme.normalStickers[0].id] = 0
        XCTAssertEqual(
            BlindBoxProbabilityEngine.mode(for: theme, ownedCounts: missingOneNormal),
            .standard
        )

        var hiddenAlreadyOwned = allNormalsOwned
        hiddenAlreadyOwned[theme.hiddenSticker!.id] = 1
        XCTAssertEqual(
            BlindBoxProbabilityEngine.mode(for: theme, ownedCounts: hiddenAlreadyOwned),
            .standard
        )
    }

    func testProbabilityDisclosureUsesApprovedOneAndFivePercentRules() throws {
        let standard = try BlindBoxProbabilityEngine.disclosure(for: petsTheme, mode: .standard)
        XCTAssertEqual(standard.hiddenStickerProbability, 0.01, accuracy: 0.000_001)
        XCTAssertEqual(standard.normalStickerProbability, 0.09, accuracy: 0.000_001)
        XCTAssertEqual(standard.hiddenInclusionProbabilityPerBatch, 0.09, accuracy: 0.000_001)

        let hiddenHunt = try BlindBoxProbabilityEngine.disclosure(for: petsTheme, mode: .hiddenHunt)
        XCTAssertEqual(hiddenHunt.hiddenStickerProbability, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(hiddenHunt.normalStickerProbability, 0.95 / 11, accuracy: 0.000_001)
        XCTAssertEqual(hiddenHunt.hiddenInclusionProbabilityPerBatch, 0.45, accuracy: 0.000_001)
    }

    func testGeneratedBatchContainsOneHiddenStickerWhenHiddenBatchIsDrawn() throws {
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0])

        let plan = try BlindBoxBatchGenerator.generate(
            theme: petsTheme,
            ownedCounts: [:],
            generator: &generator
        )

        XCTAssertEqual(plan.positions.count, BlindBoxRuleConfiguration.batchPositionCount)
        XCTAssertEqual(
            plan.positions.filter { $0.stickerID == petsTheme.hiddenSticker!.id }.count,
            1
        )
        XCTAssertEqual(Set(plan.positions.map(\.index)), Set(0..<BlindBoxRuleConfiguration.batchPositionCount))
    }

    func testGeneratedFullPetsBatchHasNoRepeatedNormalSticker() throws {
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])

        let plan = try BlindBoxBatchGenerator.generate(
            theme: petsTheme,
            ownedCounts: [:],
            generator: &generator
        )

        let stickers = plan.positions.map(\.stickerID)
        XCTAssertFalse(stickers.contains(petsTheme.hiddenSticker!.id))
        XCTAssertEqual(Set(stickers).count, BlindBoxRuleConfiguration.batchPositionCount)
    }

    func testGeneratedCozyBatchFillsNinePositionsWithOneAllowedRepeat() throws {
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])

        let plan = try BlindBoxBatchGenerator.generate(
            theme: cozyDailyTheme,
            ownedCounts: [:],
            generator: &generator
        )

        let stickers = plan.positions.map(\.stickerID)
        let counts = Dictionary(grouping: stickers, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(stickers.count, 9)
        XCTAssertEqual(counts.count, 8)
        XCTAssertEqual(counts.values.sorted(), [1, 1, 1, 1, 1, 1, 1, 2])
        XCTAssertFalse(stickers.contains(cozyDailyTheme.hiddenSticker!.id))
    }

    func testInvalidRemoteThemeCannotGenerateBatch() {
        let invalidTheme = BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "too_many_normals"),
            catalogVersion: 1,
            stickers: (0...BlindBoxRuleConfiguration.maximumNormalStickerCount).map { index in
                BlindBoxStickerDefinition(
                    id: BlindBoxStickerID(rawValue: "normal_\(index)"),
                    assetName: "normal_\(index)",
                    isHidden: false
                )
            } + [
                BlindBoxStickerDefinition(
                    id: BlindBoxStickerID(rawValue: "hidden"),
                    assetName: "hidden",
                    isHidden: true
                )
            ]
        )
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0])

        XCTAssertEqual(
            invalidTheme.validationError(),
            .tooManyNormalStickers(maximum: BlindBoxRuleConfiguration.maximumNormalStickerCount)
        )
        XCTAssertThrowsError(
            try BlindBoxBatchGenerator.generate(
                theme: invalidTheme,
                ownedCounts: [:],
                generator: &generator
            )
        ) { error in
            XCTAssertEqual(
                error as? BlindBoxBatchGenerationError,
                .invalidTheme(.tooManyNormalStickers(
                    maximum: BlindBoxRuleConfiguration.maximumNormalStickerCount
                ))
            )
        }
    }

    func testTicketDailyGrantHonorsTheTwentyTicketCap() {
        XCTAssertEqual(
            BlindBoxTicketPolicy.dailyGrant(currentBalance: 19, hasPremiumAccess: false),
            .granted(amount: 1, resultingBalance: 20)
        )
        XCTAssertEqual(
            BlindBoxTicketPolicy.dailyGrant(currentBalance: 18, hasPremiumAccess: true),
            .granted(amount: 2, resultingBalance: 20)
        )
        XCTAssertEqual(
            BlindBoxTicketPolicy.dailyGrant(currentBalance: 20, hasPremiumAccess: true),
            .atCapacity
        )
        XCTAssertEqual(BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: false), 4)
        XCTAssertEqual(BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: true), 6)
    }

    func testPointExchangeIsLimitedToOnePerGrantDayAtOneHundredPoints() {
        XCTAssertEqual(
            BlindBoxPointExchangePolicy.eligibility(
                availablePoints: 100,
                ticketBalance: 19,
                exchangesUsedThisGrantDay: 0
            ),
            .eligible
        )
        XCTAssertEqual(
            BlindBoxPointExchangePolicy.eligibility(
                availablePoints: 99,
                ticketBalance: 0,
                exchangesUsedThisGrantDay: 0
            ),
            .insufficientPoints(required: 100, current: 99)
        )
        XCTAssertEqual(
            BlindBoxPointExchangePolicy.eligibility(
                availablePoints: 1_000,
                ticketBalance: 20,
                exchangesUsedThisGrantDay: 0
            ),
            .ticketBalanceAtCapacity
        )
        XCTAssertEqual(
            BlindBoxPointExchangePolicy.eligibility(
                availablePoints: 1_000,
                ticketBalance: 0,
                exchangesUsedThisGrantDay: 1
            ),
            .grantDayLimitReached
        )
    }

    func testRestockAndAutomaticOpenIntervalsUseApprovedTiming() {
        let soldOutAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            BlindBoxTicketPolicy.restockDate(soldOutAt: soldOutAt),
            soldOutAt.addingTimeInterval(24 * 60 * 60)
        )

        var firstGenerator = ScriptedBlindBoxRandomNumberGenerator(values: [0])
        XCTAssertEqual(
            BlindBoxTicketPolicy.automaticOpenDelay(generator: &firstGenerator),
            45 * 60
        )

        var lastGenerator = ScriptedBlindBoxRandomNumberGenerator(values: [0.999_999])
        let lastDelay = BlindBoxTicketPolicy.automaticOpenDelay(generator: &lastGenerator)
        XCTAssertNotNil(lastDelay)
        XCTAssertLessThan(lastDelay!, 180 * 60)
        XCTAssertGreaterThanOrEqual(lastDelay!, 45 * 60)
    }

    private var petsTheme: BlindBoxThemeDefinition {
        BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }!
    }

    private var cozyDailyTheme: BlindBoxThemeDefinition {
        BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "cozy_daily" }!
    }
}

private struct ScriptedBlindBoxRandomNumberGenerator: BlindBoxRandomNumberGenerating {
    private var values: [Double]
    private var nextIndex = 0

    init(values: [Double]) {
        self.values = values
    }

    mutating func nextUnitInterval() -> Double {
        guard !values.isEmpty else { return 0 }
        defer { nextIndex += 1 }
        return values[min(nextIndex, values.count - 1)]
    }
}
