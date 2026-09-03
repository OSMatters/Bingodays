import CloudKit
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

    func testRemoteCatalogReleaseRequiresValidatedPresentationAndKeepsActiveOrder() throws {
        let normalOne = BlindBoxStickerDefinition(
            id: BlindBoxStickerID(rawValue: "remote_normal_one"),
            assetName: "remote_normal_one",
            isHidden: false
        )
        let normalTwo = BlindBoxStickerDefinition(
            id: BlindBoxStickerID(rawValue: "remote_normal_two"),
            assetName: "remote_normal_two",
            isHidden: false
        )
        let hidden = BlindBoxStickerDefinition(
            id: BlindBoxStickerID(rawValue: "remote_hidden"),
            assetName: "remote_hidden",
            isHidden: true
        )
        let remoteTheme = BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "remote_theme"),
            catalogVersion: 4,
            stickers: [normalOne, normalTwo, hidden],
            presentation: BlindBoxThemePresentation(collectionPlacements: [
                BlindBoxCollectionPlacement(
                    stickerID: hidden.id,
                    centerX: 196.5,
                    centerY: 365,
                    displaySize: 128,
                    isSpecialSlot: true
                ),
                BlindBoxCollectionPlacement(
                    stickerID: normalOne.id,
                    centerX: 104,
                    centerY: 490,
                    displaySize: 72
                ),
                BlindBoxCollectionPlacement(
                    stickerID: normalTwo.id,
                    centerX: 290,
                    centerY: 490,
                    displaySize: 72
                )
            ])
        )
        let retiredTheme = BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "retired_theme"),
            catalogVersion: 2,
            stickers: [
                BlindBoxStickerDefinition(
                    id: BlindBoxStickerID(rawValue: "retired_normal"),
                    assetName: "retired_normal",
                    isHidden: false
                ),
                BlindBoxStickerDefinition(
                    id: BlindBoxStickerID(rawValue: "retired_hidden"),
                    assetName: "retired_hidden",
                    isHidden: true
                )
            ],
            presentation: BlindBoxThemePresentation(collectionPlacements: [
                BlindBoxCollectionPlacement(
                    stickerID: BlindBoxStickerID(rawValue: "retired_hidden"),
                    centerX: 196.5,
                    centerY: 365,
                    displaySize: 128,
                    isSpecialSlot: true
                ),
                BlindBoxCollectionPlacement(
                    stickerID: BlindBoxStickerID(rawValue: "retired_normal"),
                    centerX: 196.5,
                    centerY: 500,
                    displaySize: 72
                )
            ])
        )
        let release = BlindBoxCatalogRelease(
            releaseID: "release-2026-09-03",
            catalogSchemaVersion: 1,
            minimumAppBuild: 0,
            publishedAt: Date(timeIntervalSince1970: 1_000),
            activeThemeIDs: [remoteTheme.id],
            themes: [retiredTheme, remoteTheme]
        )

        XCTAssertNil(release.validationError())
        XCTAssertEqual(release.activeThemes.map(\.id), [remoteTheme.id])

        let decodedRelease = try JSONDecoder().decode(
            BlindBoxCatalogRelease.self,
            from: JSONEncoder().encode(release)
        )
        XCTAssertEqual(decodedRelease, release)

        let presentationlessRelease = BlindBoxCatalogRelease(
            releaseID: "invalid-release",
            catalogSchemaVersion: 1,
            minimumAppBuild: 0,
            publishedAt: .now,
            activeThemeIDs: [petsTheme.id],
            themes: [petsTheme]
        )
        XCTAssertEqual(
            presentationlessRelease.validationError(),
            .missingPresentation(petsTheme.id)
        )
    }

    func testCatalogCacheKeepsLastKnownGoodReleaseWhenNewInputIsRejected() throws {
        let suiteName = "BlindBoxCatalogCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let validRelease = makeCacheableCatalogRelease(releaseID: "release-one")
        XCTAssertEqual(
            BlindBoxCatalogCache.save(validRelease, defaults: defaults, currentBuild: 1),
            .saved
        )
        XCTAssertEqual(
            BlindBoxCatalogCache.load(defaults: defaults, currentBuild: 1),
            validRelease
        )

        let invalidRelease = BlindBoxCatalogRelease(
            releaseID: " ",
            catalogSchemaVersion: validRelease.catalogSchemaVersion,
            minimumAppBuild: validRelease.minimumAppBuild,
            publishedAt: validRelease.publishedAt,
            activeThemeIDs: validRelease.activeThemeIDs,
            themes: validRelease.themes
        )
        XCTAssertEqual(
            BlindBoxCatalogCache.save(invalidRelease, defaults: defaults, currentBuild: 1),
            .rejectedInvalidRelease(.invalidReleaseID)
        )

        let incompatibleRelease = BlindBoxCatalogRelease(
            releaseID: "release-future",
            catalogSchemaVersion: validRelease.catalogSchemaVersion,
            minimumAppBuild: 2,
            publishedAt: validRelease.publishedAt,
            activeThemeIDs: validRelease.activeThemeIDs,
            themes: validRelease.themes
        )
        XCTAssertEqual(
            BlindBoxCatalogCache.save(incompatibleRelease, defaults: defaults, currentBuild: 1),
            .rejectedIncompatibleBuild(required: 2, current: 1)
        )
        XCTAssertEqual(
            BlindBoxCatalogCache.load(defaults: defaults, currentBuild: 1),
            validRelease
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

    func testLegacyMigrationAddsConfirmedHiddenRagdollsExactlyOnce() {
        var state = BlindBoxAccountState(ownedStickerCounts: ["pets_12": 3])
        var completedVersions: Set<Int> = []
        let legacyInventory = [
            StickerKind.ragdollCat.rawValue: 1,
            StickerKind.ragdollCatStar.rawValue: 1,
            StickerKind.cowCat.rawValue: 1
        ]

        let firstResult = BlindBoxLegacyStickerMigration.apply(
            legacyInventoryCounts: legacyInventory,
            to: &state,
            completedMigrationVersions: &completedVersions
        )

        guard case let .applied(preview) = firstResult else {
            return XCTFail("Expected confirmed legacy stickers to migrate")
        }
        XCTAssertEqual(preview.migratedOwnedStickerCounts["pets_12"], 2)
        XCTAssertEqual(state.ownedStickerCounts["pets_12"], 5)
        XCTAssertEqual(state.ownedStickerCounts["pets_11"], 1)
        XCTAssertEqual(
            completedVersions,
            [BlindBoxLegacyStickerMigration.initialCatalogMigrationVersion]
        )

        let migratedState = state
        XCTAssertEqual(
            BlindBoxLegacyStickerMigration.apply(
                legacyInventoryCounts: legacyInventory,
                to: &state,
                completedMigrationVersions: &completedVersions
            ),
            .alreadyApplied
        )
        XCTAssertEqual(state, migratedState)
    }

    func testLegacyMigrationDoesNotMutateStateWhenAnIDNeedsReview() {
        var state = BlindBoxAccountState(ownedStickerCounts: ["pets_01": 2])
        var completedVersions: Set<Int> = []
        let originalState = state

        XCTAssertEqual(
            BlindBoxLegacyStickerMigration.apply(
                legacyInventoryCounts: [
                    StickerKind.akita.rawValue: 1,
                    "unmapped_legacy_sticker": 1
                ],
                to: &state,
                completedMigrationVersions: &completedVersions
            ),
            .requiresManualReview(unmappedLegacyStickerIDs: ["unmapped_legacy_sticker"])
        )
        XCTAssertEqual(state, originalState)
        XCTAssertTrue(completedVersions.isEmpty)
    }

    func testLocalMigrationPreservesLegacyInventoryAndPersistsItsVersionAtomically() throws {
        let suiteName = "BlindBoxLegacyMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyInventory = [
            StickerKind.ragdollCat.rawValue: 1,
            StickerKind.ragdollCatStar.rawValue: 1,
            StickerKind.cowCatStar.rawValue: 1
        ]
        let legacyData = try JSONEncoder().encode(legacyInventory)
        defaults.set(legacyData, forKey: AppSettings.stickerInventoryCountsKey)

        let firstResult = BlindBoxLocalStateStore.migrateLegacyInventoryIfNeeded(defaults: defaults)
        guard case let .applied(preview) = firstResult else {
            return XCTFail("Expected the persisted migration to apply")
        }
        XCTAssertEqual(preview.migratedOwnedStickerCounts["pets_12"], 2)
        XCTAssertEqual(BlindBoxLocalStateStore.load(defaults: defaults).ownedStickerCounts["pets_12"], 2)
        XCTAssertEqual(BlindBoxLocalStateStore.load(defaults: defaults).ownedStickerCounts["pets_11"], 1)
        XCTAssertEqual(
            defaults.data(forKey: AppSettings.stickerInventoryCountsKey),
            legacyData,
            "Migrating Blind Box ownership must not rewrite old StickerStore data."
        )

        XCTAssertEqual(
            BlindBoxLocalStateStore.migrateLegacyInventoryIfNeeded(defaults: defaults),
            .alreadyApplied
        )
        XCTAssertEqual(BlindBoxLocalStateStore.load(defaults: defaults).ownedStickerCounts["pets_12"], 2)
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

    private func makeCacheableCatalogRelease(releaseID: String) -> BlindBoxCatalogRelease {
        let normal = BlindBoxStickerDefinition(
            id: BlindBoxStickerID(rawValue: "cache_normal"),
            assetName: "cache_normal",
            isHidden: false
        )
        let hidden = BlindBoxStickerDefinition(
            id: BlindBoxStickerID(rawValue: "cache_hidden"),
            assetName: "cache_hidden",
            isHidden: true
        )
        let theme = BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "cache_theme"),
            catalogVersion: 1,
            stickers: [normal, hidden],
            presentation: BlindBoxThemePresentation(collectionPlacements: [
                BlindBoxCollectionPlacement(
                    stickerID: hidden.id,
                    centerX: 196.5,
                    centerY: 365,
                    displaySize: 128,
                    isSpecialSlot: true
                ),
                BlindBoxCollectionPlacement(
                    stickerID: normal.id,
                    centerX: 196.5,
                    centerY: 500,
                    displaySize: 72
                )
            ])
        )
        return BlindBoxCatalogRelease(
            releaseID: releaseID,
            catalogSchemaVersion: 1,
            minimumAppBuild: 1,
            publishedAt: Date(timeIntervalSince1970: 1_000),
            activeThemeIDs: [theme.id],
            themes: [theme]
        )
    }
}

final class BlindBoxStateMachineTests: XCTestCase {
    func testCloudKitRecordCodecRoundTripsAccountAndImmutableDraw() throws {
        let batchID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let request = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000002")!,
            batchID: batchID,
            positionIndex: 3
        )
        let accountEnvelope = BlindBoxCloudAccountEnvelope(
            accountState: BlindBoxAccountState(
                ticketBalance: 7,
                ownedStickerCounts: ["pets_12": 2]
            ),
            completedLegacyMigrationVersions: [1]
        )
        let result = BlindBoxOpenResult(
            batchID: batchID,
            openedStickers: [
                BlindBoxOpenedSticker(
                    positionIndex: 3,
                    stickerID: BlindBoxStickerID(rawValue: "pets_12"),
                    resultingOwnedCount: 2
                )
            ],
            ticketCost: 1,
            resultingTicketBalance: 7,
            restockAt: nil
        )
        let drawEnvelope = BlindBoxCloudDrawEnvelope(
            request: request,
            result: result,
            committedAt: Date(timeIntervalSince1970: 1_000)
        )

        let accountRecord = try BlindBoxCloudKitRecordCodec.makeAccountRecord(accountEnvelope)
        let drawRecord = try BlindBoxCloudKitRecordCodec.makeDrawRecord(drawEnvelope)

        XCTAssertEqual(accountRecord.recordType, BlindBoxCloudKitRecordCodec.accountRecordType)
        XCTAssertEqual(try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord), accountEnvelope)
        XCTAssertEqual(drawRecord.recordID, BlindBoxCloudKitRecordCodec.drawRecordID(for: request.idempotencyKey))
        XCTAssertEqual(try BlindBoxCloudKitRecordCodec.decodeDrawRecord(drawRecord), drawEnvelope)

        let updatedAccount = BlindBoxCloudAccountEnvelope(
            accountState: BlindBoxAccountState(ticketBalance: 6),
            completedLegacyMigrationVersions: [1]
        )
        try BlindBoxCloudKitRecordCodec.updateAccountRecord(accountRecord, with: updatedAccount)
        XCTAssertEqual(try BlindBoxCloudKitRecordCodec.decodeAccountRecord(accountRecord), updatedAccount)
    }

    func testCloudKitRecordCodecRoundTripsPointExchangeIntent() throws {
        let request = BlindBoxPointExchangeRequest(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000007")!,
            requestedAt: Date(timeIntervalSince1970: 1_000)
        )
        let reservation = BlindBoxPointExchangeReservationResult(
            idempotencyKey: request.idempotencyKey,
            deductedPoints: 100,
            grantDayIdentifier: "2026-09-01"
        )
        let exchange = BlindBoxCloudPointExchangeEnvelope(
            request: request,
            reservation: reservation,
            completion: nil,
            reservedAt: request.requestedAt,
            completedAt: nil
        )

        let record = try BlindBoxCloudKitRecordCodec.makePointExchangeRecord(exchange)
        XCTAssertEqual(record.recordType, BlindBoxCloudKitRecordCodec.pointExchangeRecordType)
        XCTAssertEqual(
            record.recordID,
            BlindBoxCloudKitRecordCodec.pointExchangeRecordID(for: request.idempotencyKey)
        )
        XCTAssertEqual(try BlindBoxCloudKitRecordCodec.decodePointExchangeRecord(record), exchange)
    }

    func testCloudDrawTransactionCommitsOnceAndReturnsPriorResultForARetry() throws {
        let plan = makePlan()
        let request = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000003")!,
            batchID: plan.id,
            positionIndex: 0
        )
        let originalAccount = BlindBoxCloudAccountEnvelope(
            accountState: BlindBoxAccountState(
                ticketBalance: 2,
                candidateBatches: [BlindBoxCandidateBatch(plan: plan)]
            )
        )
        let committedAt = Date(timeIntervalSince1970: 1_000)

        let firstDecision = try BlindBoxCloudDrawTransaction.plan(
            request: request,
            account: originalAccount,
            existingDraw: nil,
            committedAt: committedAt
        )
        guard case let .commit(updatedAccount, draw) = firstDecision else {
            return XCTFail("A new command must produce an atomic account-and-draw commit.")
        }
        XCTAssertEqual(updatedAccount.accountState.ticketBalance, 1)
        XCTAssertEqual(updatedAccount.accountState.ownedStickerCounts["pets_01"], 1)
        XCTAssertEqual(draw.result.ticketCost, 1)
        XCTAssertEqual(originalAccount.accountState.ticketBalance, 2)

        let retryDecision = try BlindBoxCloudDrawTransaction.plan(
            request: request,
            account: updatedAccount,
            existingDraw: draw,
            committedAt: committedAt.addingTimeInterval(60)
        )
        XCTAssertEqual(retryDecision, .priorResult(draw.result))
    }

    func testCloudDrawTransactionRejectsAConflictingReuseOfAnIdempotencyKey() throws {
        let plan = makePlan()
        let originalRequest = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000004")!,
            batchID: plan.id,
            positionIndex: 0
        )
        let conflictingRequest = BlindBoxDrawRequest.single(
            idempotencyKey: originalRequest.idempotencyKey,
            batchID: plan.id,
            positionIndex: 1
        )
        let account = BlindBoxCloudAccountEnvelope(
            accountState: BlindBoxAccountState(
                ticketBalance: 2,
                candidateBatches: [BlindBoxCandidateBatch(plan: plan)]
            )
        )
        let committed = try BlindBoxCloudDrawTransaction.plan(
            request: originalRequest,
            account: account,
            existingDraw: nil,
            committedAt: Date(timeIntervalSince1970: 1_000)
        )
        guard case let .commit(_, draw) = committed else {
            return XCTFail("Expected a new draw commit.")
        }

        XCTAssertThrowsError(
            try BlindBoxCloudDrawTransaction.plan(
                request: conflictingRequest,
                account: account,
                existingDraw: draw,
                committedAt: Date(timeIntervalSince1970: 1_100)
            )
        ) { error in
            XCTAssertEqual(error as? BlindBoxDrawRepositoryError, .idempotencyKeyConflict)
        }
    }

    @MainActor
    func testCloudAccountBootstrapMigratesLegacyInventoryInItsCreatedAccount() async throws {
        let database = InMemoryBlindBoxCloudRecordDatabase()
        let bootstrapper = BlindBoxCloudKitAccountBootstrapper(database: database)

        let result = try await bootstrapper.bootstrap(
            legacyInventoryCounts: [
                StickerKind.cowCat.rawValue: 1,
                StickerKind.cowCatStar.rawValue: 1,
                StickerKind.ragdollCat.rawValue: 1
            ]
        )

        guard case let .created(account) = result else {
            return XCTFail("The first completed migration must create the account.")
        }
        XCTAssertEqual(account.accountState.ownedStickerCounts["pets_11"], 2)
        XCTAssertEqual(account.accountState.ownedStickerCounts["pets_12"], 1)
        XCTAssertTrue(
            account.completedLegacyMigrationVersions.contains(
                BlindBoxLegacyStickerMigration.initialCatalogMigrationVersion
            )
        )
        XCTAssertEqual(database.saveAttemptCount, 1)
    }

    @MainActor
    func testCloudAccountBootstrapLeavesUnknownLegacyInventoryUnwritten() async throws {
        let database = InMemoryBlindBoxCloudRecordDatabase()
        let bootstrapper = BlindBoxCloudKitAccountBootstrapper(database: database)

        let result = try await bootstrapper.bootstrap(
            legacyInventoryCounts: ["future_legacy_sticker": 1]
        )

        XCTAssertEqual(
            result,
            .requiresManualReview(unmappedLegacyStickerIDs: ["future_legacy_sticker"])
        )
        XCTAssertNil(database.record(for: BlindBoxCloudKitRecordCodec.accountRecordID))
        XCTAssertEqual(database.saveAttemptCount, 0)
    }

    @MainActor
    func testCloudAccountBootstrapDoesNotApplyTheMigrationTwice() async throws {
        let database = InMemoryBlindBoxCloudRecordDatabase()
        let existing = BlindBoxCloudAccountEnvelope(
            accountState: BlindBoxAccountState(ownedStickerCounts: ["pets_11": 2]),
            completedLegacyMigrationVersions: [
                BlindBoxLegacyStickerMigration.initialCatalogMigrationVersion
            ]
        )
        try database.seed(BlindBoxCloudKitRecordCodec.makeAccountRecord(existing))
        let bootstrapper = BlindBoxCloudKitAccountBootstrapper(database: database)

        let result = try await bootstrapper.bootstrap(
            legacyInventoryCounts: [StickerKind.cowCat.rawValue: 1]
        )

        XCTAssertEqual(result, .alreadyReady(account: existing))
        XCTAssertEqual(database.saveAttemptCount, 0)
    }

    @MainActor
    func testCloudAccountMaintenancePersistsTheDailyGrantAndVisibleCandidates() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let database = InMemoryBlindBoxCloudRecordDatabase()
        try database.seed(
            BlindBoxCloudKitRecordCodec.makeAccountRecord(BlindBoxCloudAccountEnvelope())
        )
        try await database.createZone(BlindBoxCloudKitRecordCodec.zoneID)
        let repository = BlindBoxCloudKitAccountStateRepository(database: database)

        let result = try await repository.maintain(
            BlindBoxCloudMaintenanceRequest(
                themes: BlindBoxCatalog.builtInThemes,
                hasPremiumAccess: false,
                candidateZoneWasPresented: true,
                now: Date(timeIntervalSince1970: 2_000),
                calendar: calendar
            )
        )

        XCTAssertEqual(result.dailyTicketRefresh.grantedTicketCount, 1)
        XCTAssertEqual(database.saveAttemptCount, 1)
        let account = try await repository.loadAccount()
        XCTAssertEqual(account.accountState.ticketBalance, 1)
        XCTAssertEqual(account.accountState.candidateBatches.count, 4)
        XCTAssertTrue(account.accountState.candidateBatches.allSatisfy { $0.firstPresentedAt != nil })
    }

    @MainActor
    func testFeatureStoreWaitsForInitialICloudImportWithoutCreatingAnAccount() async throws {
        let database = InMemoryBlindBoxCloudRecordDatabase()
        let store = BlindBoxFeatureStore(
            themes: BlindBoxCatalog.builtInThemes,
            database: database,
            legacyInventoryProvider: { [StickerKind.cowCat.rawValue: 1] }
        )

        await store.refresh(
            hasPremiumAccess: false,
            candidateZoneWasPresented: true,
            nativeICloudInitialImportComplete: false
        )

        XCTAssertEqual(store.availability, .waitingForICloudInitialImport)
        XCTAssertEqual(database.saveAttemptCount, 0)
        XCTAssertNil(database.record(for: BlindBoxCloudKitRecordCodec.accountRecordID))
    }

    @MainActor
    func testFeatureStoreBootstrapsMaintainsAndUsesTheCloudDrawRepository() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 2_000)
        let database = InMemoryBlindBoxCloudRecordDatabase()
        let store = BlindBoxFeatureStore(
            themes: BlindBoxCatalog.builtInThemes,
            database: database,
            legacyInventoryProvider: { [:] }
        )

        await store.refresh(
            hasPremiumAccess: false,
            candidateZoneWasPresented: true,
            nativeICloudInitialImportComplete: true,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(store.availability, .ready)
        XCTAssertEqual(store.accountState.ticketBalance, 1)
        let batch = try XCTUnwrap(store.accountState.candidateBatches.first)
        let result = try await store.open(
            .single(batchID: batch.id, positionIndex: batch.unopenedPositionPlans[0].index)
        )

        XCTAssertEqual(result.ticketCost, 1)
        XCTAssertEqual(store.accountState.ticketBalance, 0)
        XCTAssertEqual(store.accountState.ownedStickerCounts.count, 1)
    }

    @MainActor
    func testCloudDrawRepositoryAtomicallyCommitsAndReturnsThePriorResultForARetry() async throws {
        let plan = makePlan()
        let request = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000005")!,
            batchID: plan.id,
            positionIndex: 0
        )
        let database = InMemoryBlindBoxCloudRecordDatabase()
        let account = BlindBoxCloudAccountEnvelope(
            accountState: BlindBoxAccountState(
                ticketBalance: 2,
                candidateBatches: [BlindBoxCandidateBatch(plan: plan)]
            )
        )
        try database.seed(BlindBoxCloudKitRecordCodec.makeAccountRecord(account))
        let repository = BlindBoxCloudKitDrawRepository(
            database: database,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let firstResult = try await repository.open(request)
        let retryResult = try await repository.open(request)

        XCTAssertEqual(retryResult, firstResult)
        XCTAssertTrue(database.zoneWasCreated)
        XCTAssertEqual(database.saveAttemptCount, 1)
        let storedAccount = try XCTUnwrap(database.record(for: BlindBoxCloudKitRecordCodec.accountRecordID))
        XCTAssertEqual(
            try BlindBoxCloudKitRecordCodec.decodeAccountRecord(storedAccount).accountState.ticketBalance,
            1
        )
        XCTAssertNotNil(database.record(for: BlindBoxCloudKitRecordCodec.drawRecordID(for: request.idempotencyKey)))
    }

    @MainActor
    func testCloudDrawRepositoryRetriesAConcurrentAccountConflict() async throws {
        let plan = makePlan()
        let request = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000006")!,
            batchID: plan.id,
            positionIndex: 0
        )
        let database = InMemoryBlindBoxCloudRecordDatabase(conflictingSaveAttempts: 1)
        try database.seed(
            BlindBoxCloudKitRecordCodec.makeAccountRecord(
                BlindBoxCloudAccountEnvelope(
                    accountState: BlindBoxAccountState(
                        ticketBalance: 2,
                        candidateBatches: [BlindBoxCandidateBatch(plan: plan)]
                    )
                )
            )
        )
        let repository = BlindBoxCloudKitDrawRepository(
            database: database,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let result = try await repository.open(request)

        XCTAssertEqual(result.ticketCost, 1)
        XCTAssertEqual(database.saveAttemptCount, 2)
        let storedAccount = try XCTUnwrap(database.record(for: BlindBoxCloudKitRecordCodec.accountRecordID))
        XCTAssertEqual(
            try BlindBoxCloudKitRecordCodec.decodeAccountRecord(storedAccount).accountState.ticketBalance,
            1
        )
    }

    @MainActor
    func testCloudDrawRepositoryNeverCreatesAnEmptyAccountDuringAnOpen() async throws {
        let plan = makePlan()
        let repository = BlindBoxCloudKitDrawRepository(
            database: InMemoryBlindBoxCloudRecordDatabase(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        do {
            _ = try await repository.open(
                BlindBoxDrawRequest.single(batchID: plan.id, positionIndex: 0)
            )
            XCTFail("Opening before account bootstrap must be rejected.")
        } catch {
            XCTAssertEqual(error as? BlindBoxCloudKitRepositoryError, .accountNotInitialized)
        }
    }

    @MainActor
    func testPointExchangeRepositoryReservesCapacityThenCompletesIdempotently() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let requestedAt = ISO8601DateFormatter().date(from: "2026-09-02T03:59:00Z")!
        let request = BlindBoxPointExchangeRequest(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000008")!,
            requestedAt: requestedAt
        )
        let database = InMemoryBlindBoxCloudRecordDatabase()
        let bootstrapper = BlindBoxCloudKitAccountBootstrapper(database: database)
        _ = try await bootstrapper.bootstrap(legacyInventoryCounts: [:])
        let repository = BlindBoxCloudKitPointExchangeRepository(database: database)

        let reserved = try await repository.begin(
            request,
            availablePoints: 100,
            calendar: calendar
        )
        XCTAssertFalse(reserved.isCompleted)
        XCTAssertEqual(reserved.reservation.deductedPoints, 100)
        XCTAssertEqual(reserved.reservation.grantDayIdentifier, "2026-09-01")

        let accountRepository = BlindBoxCloudKitAccountStateRepository(database: database)
        var account = try await accountRepository.loadAccount()
        XCTAssertEqual(account.accountState.ticketBalance, 0)
        XCTAssertEqual(account.accountState.pendingPointExchange?.idempotencyKey, request.idempotencyKey)
        XCTAssertEqual(account.accountState.pointExchangesUsedOnLastGrantDay, 1)

        // The pending exchange holds one capacity position through the next
        // daily allowance, so it cannot be accepted and then stranded at cap.
        account.accountState.ticketBalance = 19
        let accountRecord = try XCTUnwrap(database.record(for: BlindBoxCloudKitRecordCodec.accountRecordID))
        try BlindBoxCloudKitRecordCodec.updateAccountRecord(accountRecord, with: account)
        try await database.saveRecordsAtomically([accountRecord])
        let maintenance = try await accountRepository.maintain(
            BlindBoxCloudMaintenanceRequest(
                themes: BlindBoxCatalog.builtInThemes,
                hasPremiumAccess: false,
                candidateZoneWasPresented: false,
                now: ISO8601DateFormatter().date(from: "2026-09-02T04:00:00Z")!,
                calendar: calendar
            )
        )
        XCTAssertEqual(maintenance.dailyTicketRefresh.grantedTicketCount, 0)

        let completed = try await repository.complete(request, completedAt: requestedAt)
        XCTAssertEqual(completed.deductedPoints, 100)
        XCTAssertEqual(completed.grantedTickets, 1)
        XCTAssertEqual(completed.resultingTicketBalance, 20)
        let completedRetry = try await repository.complete(request, completedAt: requestedAt)
        XCTAssertEqual(completedRetry, completed)

        account = try await accountRepository.loadAccount()
        XCTAssertNil(account.accountState.pendingPointExchange)
        XCTAssertEqual(account.accountState.ticketBalance, 20)
        let replay = try await repository.begin(request, availablePoints: 0, calendar: calendar)
        XCTAssertEqual(replay.completion, completed)
    }

    @MainActor
    func testPointExchangeRepositoryRejectsConcurrentReservationBeforeAnotherLedgerCharge() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let requestedAt = Date(timeIntervalSince1970: 1_000)
        let database = InMemoryBlindBoxCloudRecordDatabase()
        let bootstrapper = BlindBoxCloudKitAccountBootstrapper(database: database)
        _ = try await bootstrapper.bootstrap(legacyInventoryCounts: [:])
        let repository = BlindBoxCloudKitPointExchangeRepository(database: database)
        _ = try await repository.begin(
            BlindBoxPointExchangeRequest(requestedAt: requestedAt),
            availablePoints: 100,
            calendar: calendar
        )

        do {
            _ = try await repository.begin(
                BlindBoxPointExchangeRequest(requestedAt: requestedAt),
                availablePoints: 100,
                calendar: calendar
            )
            XCTFail("A second device must be stopped before it records another point charge.")
        } catch {
            XCTAssertEqual(
                error as? BlindBoxPointExchangeRepositoryError,
                .anotherExchangeIsPending
            )
        }
    }

    @MainActor
    func testForcedOfflineConnectivityGateBlocksNetworkOperations() {
        let monitor = BlindBoxConnectivityMonitor(forceOffline: true)

        XCTAssertEqual(monitor.status, .offline)
        XCTAssertFalse(monitor.status.canMakeNetworkRequests)
        XCTAssertEqual(
            monitor.status.unavailableMessage,
            "You're offline. Connect to the internet and try again."
        )
    }

    @MainActor
    func testPreviewDrawRepositoryReturnsTheOriginalResultForAnIdempotencyRetry() async throws {
        let store = BlindBoxPreviewStore(referenceDate: Date(timeIntervalSince1970: 1_000))
        let batchID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let idempotencyKey = UUID(uuidString: "FACEFEED-0000-4000-8000-000000000001")!
        let request = BlindBoxDrawRequest.single(
            idempotencyKey: idempotencyKey,
            batchID: batchID,
            positionIndex: 0
        )

        let firstResult = try await store.open(request)
        let stateAfterFirstOpen = store.state
        let retryResult = try await store.open(request)

        XCTAssertEqual(retryResult, firstResult)
        XCTAssertEqual(store.state, stateAfterFirstOpen)

        let conflictingRequest = BlindBoxDrawRequest.single(
            idempotencyKey: idempotencyKey,
            batchID: batchID,
            positionIndex: 1
        )
        do {
            _ = try await store.open(conflictingRequest)
            XCTFail("A reused idempotency key must not be accepted for another draw.")
        } catch {
            XCTAssertEqual(error as? BlindBoxDrawRepositoryError, .idempotencyKeyConflict)
        }
    }

    @MainActor
    func testPreviewTicketExchangeOnlyChangesItsOwnDevelopmentPoints() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = BlindBoxPreviewStore(
            previewAvailablePoints: 100,
            referenceDate: Date(timeIntervalSince1970: 1_000)
        )

        let result = try store.exchangePointsForOneTicket(
            now: Date(timeIntervalSince1970: 1_000),
            calendar: calendar
        )

        XCTAssertEqual(result.deductedPoints, 100)
        XCTAssertEqual(result.grantedTickets, 1)
        XCTAssertEqual(store.previewAvailablePoints, 0)
        XCTAssertEqual(store.state.ticketBalance, BlindBoxRuleConfiguration.maximumTicketBalance)
        XCTAssertEqual(
            store.pointExchangeEligibility(
                now: Date(timeIntervalSince1970: 1_000),
                calendar: calendar
            ),
            .ticketBalanceAtCapacity
        )
    }

    func testDrawRequestRejectsInvalidModeAndPositionCombinations() {
        let batchID = UUID(uuidString: "BEEFF00D-0000-4000-8000-000000000001")!
        let malformedSingle = BlindBoxDrawRequest(
            idempotencyKey: UUID(),
            batchID: batchID,
            mode: .single,
            positionIndex: nil
        )
        let malformedWholeBox = BlindBoxDrawRequest(
            idempotencyKey: UUID(),
            batchID: batchID,
            mode: .wholeBox,
            positionIndex: 0
        )

        XCTAssertEqual(malformedSingle.validationError(), .missingPositionIndex)
        XCTAssertEqual(malformedWholeBox.validationError(), .unexpectedPositionIndex)
    }

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

@MainActor
private final class InMemoryBlindBoxCloudRecordDatabase: BlindBoxCloudRecordDatabase {
    private var storedRecords: [CKRecord.ID: CKRecord] = [:]
    private var hasZone = false
    private var conflictingSaveAttempts: Int

    private(set) var saveAttemptCount = 0

    var zoneWasCreated: Bool {
        hasZone
    }

    init(conflictingSaveAttempts: Int = 0) {
        self.conflictingSaveAttempts = conflictingSaveAttempts
    }

    func seed(_ record: CKRecord) throws {
        storedRecords[record.recordID] = try clone(record)
    }

    func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let record = storedRecords[recordID] else { return nil }
        return try? clone(record)
    }

    func fetchZone(_ zoneID: CKRecordZone.ID) async throws -> CKRecordZone? {
        hasZone ? CKRecordZone(zoneID: zoneID) : nil
    }

    func createZone(_ zoneID: CKRecordZone.ID) async throws {
        hasZone = true
    }

    func fetchRecords(_ recordIDs: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        var fetched: [CKRecord.ID: CKRecord] = [:]
        for recordID in recordIDs {
            if let record = storedRecords[recordID] {
                fetched[recordID] = try clone(record)
            }
        }
        return fetched
    }

    func saveRecordsAtomically(_ records: [CKRecord]) async throws {
        saveAttemptCount += 1
        if conflictingSaveAttempts > 0 {
            conflictingSaveAttempts -= 1
            throw NSError(
                domain: CKErrorDomain,
                code: CKError.Code.serverRecordChanged.rawValue
            )
        }

        var nextRecords = storedRecords
        for record in records {
            nextRecords[record.recordID] = try clone(record)
        }
        storedRecords = nextRecords
    }

    private func clone(_ record: CKRecord) throws -> CKRecord {
        switch record.recordType {
        case BlindBoxCloudKitRecordCodec.accountRecordType:
            return try BlindBoxCloudKitRecordCodec.makeAccountRecord(
                BlindBoxCloudKitRecordCodec.decodeAccountRecord(record),
                recordID: record.recordID
            )
        case BlindBoxCloudKitRecordCodec.drawRecordType:
            return try BlindBoxCloudKitRecordCodec.makeDrawRecord(
                BlindBoxCloudKitRecordCodec.decodeDrawRecord(record),
                recordID: record.recordID
            )
        case BlindBoxCloudKitRecordCodec.pointExchangeRecordType:
            return try BlindBoxCloudKitRecordCodec.makePointExchangeRecord(
                BlindBoxCloudKitRecordCodec.decodePointExchangeRecord(record),
                recordID: record.recordID
            )
        default:
            throw BlindBoxCloudKitRepositoryError.incompleteCloudKitResponse
        }
    }
}

final class BlindBoxCandidateCoordinatorTests: XCTestCase {
    func testAccountMaintenanceGrantsTicketsFillsCandidatesAndStartsSchedulesOnlyAfterPresentation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 2_000)
        var state = BlindBoxAccountState()
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0])

        let firstPass = try BlindBoxAccountMaintenance.apply(
            state: &state,
            themes: BlindBoxCatalog.builtInThemes,
            hasPremiumAccess: false,
            candidateZoneWasPresented: false,
            now: now,
            calendar: calendar,
            generator: &generator
        )

        XCTAssertEqual(firstPass.dailyTicketRefresh.grantedTicketCount, 1)
        XCTAssertEqual(state.ticketBalance, 1)
        XCTAssertEqual(state.candidateBatches.count, 4)
        XCTAssertTrue(state.candidateBatches.allSatisfy { $0.firstPresentedAt == nil })

        let secondPass = try BlindBoxAccountMaintenance.apply(
            state: &state,
            themes: BlindBoxCatalog.builtInThemes,
            hasPremiumAccess: false,
            candidateZoneWasPresented: true,
            now: now,
            calendar: calendar,
            generator: &generator
        )

        XCTAssertEqual(secondPass.dailyTicketRefresh.grantedTicketCount, 0)
        XCTAssertTrue(state.candidateBatches.allSatisfy { $0.firstPresentedAt == now })
        XCTAssertTrue(state.candidateBatches.allSatisfy {
            $0.nextSystemOpenAt == now.addingTimeInterval(45 * 60)
        })
    }

    func testAccountMaintenanceProcessesOnlyOneDueAutomaticOpen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let pets = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }!
        let plan = makePlan(theme: pets, identifier: "C0FFEE00-0000-4000-8000-000000000006")
        let now = Date(timeIntervalSince1970: 2_000)
        var state = BlindBoxAccountState(
            candidateBatches: [
                BlindBoxCandidateBatch(
                    plan: plan,
                    firstPresentedAt: now.addingTimeInterval(-60 * 60),
                    nextSystemOpenAt: now.addingTimeInterval(-1)
                )
            ]
        )
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0])

        let result = try BlindBoxAccountMaintenance.apply(
            state: &state,
            themes: [pets],
            hasPremiumAccess: false,
            candidateZoneWasPresented: false,
            now: now,
            calendar: calendar,
            generator: &generator
        )

        XCTAssertNotNil(result.automaticOpen)
        XCTAssertEqual(state.candidateBatches.reduce(0) { $0 + $1.openedPositionIndices.count }, 1)
        XCTAssertEqual(state.ownedStickerCounts, [:])
    }

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
