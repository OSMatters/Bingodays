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

    func testNormalFillBalancesRepeatsForSmallerRemoteTheme() throws {
        let theme = BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "five_normals"),
            catalogVersion: 1,
            stickers: (1...5).map { index in
                BlindBoxStickerDefinition(
                    id: BlindBoxStickerID(rawValue: "normal_\(index)"),
                    assetName: "normal_\(index)",
                    isHidden: false
                )
            } + [
                BlindBoxStickerDefinition(
                    id: BlindBoxStickerID(rawValue: "hidden"), assetName: "hidden", isHidden: true)
            ]
        )
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])

        let plan = try BlindBoxBatchGenerator.generate(
            theme: theme,
            ownedCounts: [:],
            generator: &generator
        )

        let counts = Dictionary(grouping: plan.positions.map(\.stickerID), by: { $0 }).mapValues(\.count)
        XCTAssertEqual(counts.values.sorted(), [1, 2, 2, 2, 2])
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

    func testRemoteCollectionPresentationRequiresEveryStickerAndHiddenSpecialSlot() {
        let normalOne = BlindBoxStickerDefinition(
            id: BlindBoxStickerID(rawValue: "normal_one"),
            assetName: "normal_one",
            isHidden: false
        )
        let normalTwo = BlindBoxStickerDefinition(
            id: BlindBoxStickerID(rawValue: "normal_two"),
            assetName: "normal_two",
            isHidden: false
        )
        let hidden = BlindBoxStickerDefinition(
            id: BlindBoxStickerID(rawValue: "hidden"),
            assetName: "hidden",
            isHidden: true
        )

        let validPresentation = BlindBoxThemePresentation(collectionPlacements: [
            BlindBoxCollectionPlacement(
                stickerID: normalOne.id,
                centerX: 90,
                centerY: 450,
                displaySize: 72
            ),
            BlindBoxCollectionPlacement(
                stickerID: normalTwo.id,
                centerX: 180,
                centerY: 450,
                displaySize: 72
            ),
            BlindBoxCollectionPlacement(
                stickerID: hidden.id,
                centerX: 164,
                centerY: 360,
                displaySize: 138,
                isSpecialSlot: true
            )
        ])
        let validTheme = BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "configured_theme"),
            catalogVersion: 1,
            stickers: [normalOne, normalTwo, hidden],
            presentation: validPresentation
        )
        XCTAssertNil(validTheme.validationError())

        let missingStickerPresentation = BlindBoxThemePresentation(collectionPlacements: [
            BlindBoxCollectionPlacement(
                stickerID: normalOne.id,
                centerX: 90,
                centerY: 450,
                displaySize: 72
            ),
            BlindBoxCollectionPlacement(
                stickerID: hidden.id,
                centerX: 164,
                centerY: 360,
                displaySize: 138,
                isSpecialSlot: true
            )
        ])
        let invalidTheme = BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "missing_placement"),
            catalogVersion: 1,
            stickers: [normalOne, normalTwo, hidden],
            presentation: missingStickerPresentation
        )
        XCTAssertEqual(
            invalidTheme.validationError(),
            .invalidPresentation(.incorrectStickerCount(expected: 3, actual: 2))
        )

        let wrongSpecialPresentation = BlindBoxThemePresentation(collectionPlacements: [
            BlindBoxCollectionPlacement(
                stickerID: normalOne.id,
                centerX: 90,
                centerY: 450,
                displaySize: 72,
                isSpecialSlot: true
            ),
            BlindBoxCollectionPlacement(
                stickerID: normalTwo.id,
                centerX: 180,
                centerY: 450,
                displaySize: 72
            ),
            BlindBoxCollectionPlacement(
                stickerID: hidden.id,
                centerX: 164,
                centerY: 360,
                displaySize: 138
            )
        ])
        let wrongSpecialTheme = BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "wrong_special"),
            catalogVersion: 1,
            stickers: [normalOne, normalTwo, hidden],
            presentation: wrongSpecialPresentation
        )
        XCTAssertEqual(
            wrongSpecialTheme.validationError(),
            .invalidPresentation(.specialSlotMustContainHiddenSticker)
        )
    }

    func testLegacyStickerPreviewMapsEveryKnownAssetWithoutDroppingCounts() {
        let legacyInventory = Dictionary(
            uniqueKeysWithValues: StickerKind.allCases.map { ($0.rawValue, 1) }
        )

        let preview = BlindBoxLegacyStickerMigration.preview(inventoryCounts: legacyInventory)

        XCTAssertEqual(preview.unmappedLegacyStickerIDs, [])
        XCTAssertEqual(preview.migratedStickerTotal, legacyInventory.count)
        XCTAssertEqual(preview.migratedOwnedStickerCounts["pets_11"], 2)
        XCTAssertEqual(preview.migratedOwnedStickerCounts["pets_12"], 2)
        XCTAssertEqual(preview.migratedOwnedStickerCounts["pets_01"], 1)
        XCTAssertEqual(preview.migratedOwnedStickerCounts["pets_10"], 1)
    }

    func testLegacyStickerPreviewReportsUnknownIDsInsteadOfDiscardingThem() {
        let preview = BlindBoxLegacyStickerMigration.preview(inventoryCounts: [
            StickerKind.akita.rawValue: 1,
            "future_legacy_sticker": 2,
            StickerKind.orangeCat.rawValue: 0
        ])

        XCTAssertEqual(preview.migratedOwnedStickerCounts, ["pets_01": 1])
        XCTAssertEqual(preview.unmappedLegacyStickerIDs, ["future_legacy_sticker"])
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

final class BlindBoxStateMachineTests: XCTestCase {
    func testSingleOpenDeductsOneTicketAndRecordsDuplicateOwnership() throws {
        let plan = makePlan()
        var state = BlindBoxAccountState(
            ticketBalance: 2,
            ownedStickerCounts: ["pets_01": 1],
            candidateBatches: [BlindBoxCandidateBatch(plan: plan)]
        )

        let result = try BlindBoxStateMachine.openSingle(
            state: &state,
            batchID: plan.id,
            positionIndex: 0,
            openedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(result.ticketCost, 1)
        XCTAssertEqual(result.resultingTicketBalance, 1)
        XCTAssertEqual(result.openedStickers.count, 1)
        XCTAssertTrue(result.openedStickers[0].isDuplicate)
        XCTAssertEqual(result.openedStickers[0].resultingOwnedCount, 2)
        XCTAssertEqual(state.ticketBalance, 1)
        XCTAssertEqual(state.ownedStickerCounts["pets_01"], 2)
        XCTAssertEqual(state.candidateBatches[0].openedPositionIndices, Set([0]))
    }

    func testWholeBoxChargesOnlyRemainingPositionsAndStartsTwentyFourHourRestock() throws {
        let plan = makePlan()
        let openedIndices: Set<Int> = [0, 1, 2, 3]
        var state = BlindBoxAccountState(
            ticketBalance: 5,
            candidateBatches: [
                BlindBoxCandidateBatch(
                    plan: plan,
                    openedPositionIndices: openedIndices,
                    systemOpenedPositionIndices: openedIndices
                )
            ]
        )
        let openedAt = Date(timeIntervalSince1970: 1_000)

        let result = try BlindBoxStateMachine.openWholeBox(
            state: &state,
            batchID: plan.id,
            openedAt: openedAt
        )

        XCTAssertEqual(result.ticketCost, 5)
        XCTAssertEqual(result.openedStickers.count, 5)
        XCTAssertEqual(result.resultingTicketBalance, 0)
        XCTAssertEqual(result.restockAt, openedAt.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(state.candidateBatches[0].remainingPositionCount, 0)
        XCTAssertEqual(state.candidateBatches[0].soldOutAt, openedAt)
    }

    func testOpenDoesNotMutateStateWhenTheTicketBalanceIsInsufficient() {
        let plan = makePlan()
        var state = BlindBoxAccountState(
            ticketBalance: 0,
            candidateBatches: [BlindBoxCandidateBatch(plan: plan)]
        )
        let originalState = state

        XCTAssertThrowsError(
            try BlindBoxStateMachine.openSingle(
                state: &state,
                batchID: plan.id,
                positionIndex: 0,
                openedAt: .now
            )
        ) { error in
            XCTAssertEqual(error as? BlindBoxOpenError, .insufficientTickets(required: 1, current: 0))
        }
        XCTAssertEqual(state, originalState)
    }

    func testGrantDayRollsOverAtFourAM() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dateFormatter = ISO8601DateFormatter()

        XCTAssertEqual(
            BlindBoxGrantDay.identifier(
                for: dateFormatter.date(from: "2026-09-02T03:59:00Z")!,
                calendar: calendar
            ),
            "2026-09-01"
        )
        XCTAssertEqual(
            BlindBoxGrantDay.identifier(
                for: dateFormatter.date(from: "2026-09-02T04:00:00Z")!,
                calendar: calendar
            ),
            "2026-09-02"
        )
    }

    private func makePlan() -> BlindBoxBatchPlan {
        BlindBoxBatchPlan(
            id: UUID(uuidString: "BEEFF00D-0000-4000-8000-000000000001")!,
            themeID: BlindBoxThemeID(rawValue: "pets"),
            catalogVersion: 1,
            probabilityMode: .standard,
            createdAt: Date(timeIntervalSince1970: 500),
            positions: (0..<BlindBoxRuleConfiguration.batchPositionCount).map { index in
                BlindBoxPositionPlan(
                    id: UUID(uuidString: String(format: "BEEFF00D-0000-4000-8000-%012d", index + 10))!,
                    index: index,
                    stickerID: BlindBoxStickerID(rawValue: "pets_\(String(format: "%02d", index + 1))")
                )
            }
        )
    }
}

final class BlindBoxCandidateCoordinatorTests: XCTestCase {
    func testReconciliationFillsExactlyFourOrSixThemeBatchesAndAllowsRepeatedThemes() throws {
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])
        var state = BlindBoxAccountState()
        let now = Date(timeIntervalSince1970: 2_000)

        let freeResult = try BlindBoxCandidateCoordinator.reconcile(
            state: &state,
            themes: BlindBoxCatalog.builtInThemes,
            hasPremiumAccess: false,
            reason: .initialLoad,
            now: now,
            generator: &generator
        )

        XCTAssertEqual(freeResult.candidateCount, 4)
        XCTAssertEqual(state.candidateBatches.count, 4)
        XCTAssertTrue(state.candidateBatches.allSatisfy {
            ["pets", "cozy_daily"].contains($0.plan.themeID.rawValue)
        })

        let premiumResult = try BlindBoxCandidateCoordinator.reconcile(
            state: &state,
            themes: BlindBoxCatalog.builtInThemes,
            hasPremiumAccess: true,
            reason: .membershipChanged,
            now: now,
            generator: &generator
        )

        XCTAssertEqual(premiumResult.candidateCount, 6)
        XCTAssertEqual(state.candidateBatches.count, 6)
    }

    func testCompletedThemeIsRemovedAndDoesNotReturnToCandidates() throws {
        let pets = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }!
        let cozy = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "cozy_daily" }!
        let petsPlan = makePlan(theme: pets, identifier: "C0FFEE00-0000-4000-8000-000000000001")
        let cozyPlan = makePlan(theme: cozy, identifier: "C0FFEE00-0000-4000-8000-000000000002")
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])
        var state = BlindBoxAccountState(
            ownedStickerCounts: Dictionary(uniqueKeysWithValues: pets.stickers.map { ($0.id.rawValue, 1) }),
            candidateBatches: [
                BlindBoxCandidateBatch(plan: petsPlan),
                BlindBoxCandidateBatch(plan: cozyPlan)
            ]
        )

        let result = try BlindBoxCandidateCoordinator.reconcile(
            state: &state,
            themes: [pets, cozy],
            hasPremiumAccess: false,
            reason: .themeCompleted,
            now: Date(timeIntervalSince1970: 2_000),
            generator: &generator
        )

        XCTAssertTrue(result.removedBatchIDs.contains(petsPlan.id))
        XCTAssertEqual(state.candidateBatches.count, 4)
        XCTAssertTrue(state.candidateBatches.allSatisfy { $0.plan.themeID == cozy.id })
    }

    func testSoldOutCandidateRestocksAsANewImmutableBatchAfterTwentyFourHours() throws {
        let pets = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }!
        let plan = makePlan(theme: pets, identifier: "C0FFEE00-0000-4000-8000-000000000003")
        let soldOutAt = Date(timeIntervalSince1970: 2_000)
        let allPositions = Set(0..<BlindBoxRuleConfiguration.batchPositionCount)
        var state = BlindBoxAccountState(
            candidateBatches: [
                BlindBoxCandidateBatch(
                    plan: plan,
                    openedPositionIndices: allPositions,
                    systemOpenedPositionIndices: allPositions,
                    soldOutAt: soldOutAt
                )
            ]
        )
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])

        let result = try BlindBoxCandidateCoordinator.reconcile(
            state: &state,
            themes: [pets],
            hasPremiumAccess: false,
            reason: .restockCompleted,
            now: BlindBoxTicketPolicy.restockDate(soldOutAt: soldOutAt),
            generator: &generator
        )

        XCTAssertEqual(result.restockedBatchIDs, [plan.id])
        XCTAssertNotEqual(state.candidateBatches[0].id, plan.id)
        XCTAssertEqual(state.candidateBatches[0].remainingPositionCount, 9)
        XCTAssertNil(state.candidateBatches[0].firstPresentedAt)
        XCTAssertNil(state.candidateBatches[0].nextSystemOpenAt)
    }

    func testAutomaticOpenStartsAfterFirstPresentationAndNeverGrantsUserSticker() {
        let pets = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }!
        let plan = makePlan(theme: pets, identifier: "C0FFEE00-0000-4000-8000-000000000004")
        let shownAt = Date(timeIntervalSince1970: 2_000)
        var state = BlindBoxAccountState(candidateBatches: [BlindBoxCandidateBatch(plan: plan)])
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0])

        BlindBoxCandidateCoordinator.recordFirstPresentation(
            state: &state,
            visibleBatchIDs: [plan.id],
            presentedAt: shownAt,
            generator: &generator
        )

        XCTAssertEqual(state.candidateBatches[0].firstPresentedAt, shownAt)
        XCTAssertEqual(
            state.candidateBatches[0].nextSystemOpenAt,
            shownAt.addingTimeInterval(BlindBoxRuleConfiguration.minimumAutomaticOpenInterval)
        )

        let result = BlindBoxCandidateCoordinator.processOneAutomaticOpen(
            state: &state,
            now: shownAt.addingTimeInterval(BlindBoxRuleConfiguration.minimumAutomaticOpenInterval),
            generator: &generator
        )

        XCTAssertEqual(result?.batchID, plan.id)
        XCTAssertEqual(state.ownedStickerCounts, [:])
        XCTAssertEqual(state.candidateBatches[0].systemOpenedPositionIndices.count, 1)
        XCTAssertEqual(state.candidateBatches[0].openedPositionIndices.count, 1)
        XCTAssertNotNil(state.candidateBatches[0].nextSystemOpenAt)
    }

    func testAutomaticOpenPreservesTheFinalOpenPositionInCandidateZone() {
        let pets = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }!
        let plan = makePlan(theme: pets, identifier: "C0FFEE00-0000-4000-8000-000000000005")
        let finalPosition = BlindBoxRuleConfiguration.batchPositionCount - 1
        let shownAt = Date(timeIntervalSince1970: 2_000)
        var state = BlindBoxAccountState(
            candidateBatches: [
                BlindBoxCandidateBatch(
                    plan: plan,
                    openedPositionIndices: Set(0..<finalPosition),
                    systemOpenedPositionIndices: Set(0..<finalPosition),
                    firstPresentedAt: shownAt,
                    nextSystemOpenAt: shownAt
                )
            ]
        )
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0])

        XCTAssertNil(
            BlindBoxCandidateCoordinator.processOneAutomaticOpen(
                state: &state,
                now: shownAt,
                generator: &generator
            )
        )
        XCTAssertEqual(state.candidateBatches[0].remainingPositionCount, 1)
        XCTAssertFalse(state.candidateBatches[0].openedPositionIndices.contains(finalPosition))
    }

    private func makePlan(
        theme: BlindBoxThemeDefinition,
        identifier: String
    ) -> BlindBoxBatchPlan {
        BlindBoxBatchPlan(
            id: UUID(uuidString: identifier)!,
            themeID: theme.id,
            catalogVersion: theme.catalogVersion,
            probabilityMode: .standard,
            createdAt: Date(timeIntervalSince1970: 1_000),
            positions: (0..<BlindBoxRuleConfiguration.batchPositionCount).map { index in
                BlindBoxPositionPlan(
                    index: index,
                    stickerID: theme.normalStickers[index % theme.normalStickers.count].id
                )
            }
        )
    }
}

final class BlindBoxWalletStateMachineTests: XCTestCase {
    func testDailyTicketRefreshBackfillsMissedDaysButNeverExceedsTwentyTickets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        var state = BlindBoxAccountState(
            ticketBalance: 17,
            lastTicketGrantDayIdentifier: "2026-08-28"
        )

        let result = BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: true,
            now: formatter.date(from: "2026-09-02T04:01:00Z")!,
            calendar: calendar
        )

        XCTAssertEqual(result.processedGrantDays, 5)
        XCTAssertEqual(result.grantedTicketCount, 3)
        XCTAssertEqual(result.resultingTicketBalance, 20)
        XCTAssertEqual(state.lastTicketGrantDayIdentifier, "2026-09-02")

        let noRetroactiveGrant = BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: true,
            now: formatter.date(from: "2026-09-02T04:02:00Z")!,
            calendar: calendar
        )
        XCTAssertEqual(noRetroactiveGrant.processedGrantDays, 0)
        XCTAssertEqual(noRetroactiveGrant.grantedTicketCount, 0)
    }

    func testFirstDailyTicketRefreshStartsWithOnlyTodayAllowance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var state = BlindBoxAccountState()

        let result = BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: false,
            now: Date(timeIntervalSince1970: 1_000),
            calendar: calendar
        )

        XCTAssertEqual(result.processedGrantDays, 1)
        XCTAssertEqual(result.grantedTicketCount, 1)
        XCTAssertEqual(result.resultingTicketBalance, 1)
    }

    func testPointExchangeChargesOneHundredAndResetsAtFourAM() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        var state = BlindBoxAccountState(ticketBalance: 2)

        let first = try BlindBoxWalletStateMachine.exchangePointsForOneTicket(
            state: &state,
            availablePoints: 100,
            now: formatter.date(from: "2026-09-02T03:59:00Z")!,
            calendar: calendar
        )
        XCTAssertEqual(first.deductedPoints, 100)
        XCTAssertEqual(first.grantedTickets, 1)
        XCTAssertEqual(state.ticketBalance, 3)

        XCTAssertThrowsError(
            try BlindBoxWalletStateMachine.exchangePointsForOneTicket(
                state: &state,
                availablePoints: 100,
                now: formatter.date(from: "2026-09-02T03:59:30Z")!,
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(
                error as? BlindBoxWalletError,
                .pointExchange(.grantDayLimitReached)
            )
        }

        let afterReset = try BlindBoxWalletStateMachine.exchangePointsForOneTicket(
            state: &state,
            availablePoints: 100,
            now: formatter.date(from: "2026-09-02T04:00:00Z")!,
            calendar: calendar
        )
        XCTAssertEqual(afterReset.resultingTicketBalance, 4)
        XCTAssertEqual(state.pointExchangesUsedOnLastGrantDay, 1)
        XCTAssertEqual(state.lastPointExchangeDayIdentifier, "2026-09-02")
    }

    func testPointExchangeDoesNotMutateWalletOnFailure() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let original = BlindBoxAccountState(ticketBalance: 20)
        var state = original

        XCTAssertThrowsError(
            try BlindBoxWalletStateMachine.exchangePointsForOneTicket(
                state: &state,
                availablePoints: 1_000,
                now: Date(timeIntervalSince1970: 1_000),
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(
                error as? BlindBoxWalletError,
                .pointExchange(.ticketBalanceAtCapacity)
            )
        }
        XCTAssertEqual(state, original)
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
