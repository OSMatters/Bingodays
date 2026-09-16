import CloudKit
import XCTest
import Testing
@testable import Bingodays

@MainActor
struct BlindBoxPullInteractionTests {
    @Test(arguments: [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852), CGSize(width: 430, height: 932)])
    func ropeStaysAttachedToLocalArc(size: CGSize) {
        let diameter = max(size.width * 3, size.height * 2.4)
        let radius = diameter / 2
        let artworkScale: CGFloat = 45.0 / 68.0
        let ropeX: CGFloat = 21.5 + 13.0 * artworkScale
        let inset = radius - sqrt(radius * radius - pow(ropeX - size.width / 2, 2))
        for bottom: CGFloat in [52, 100, 300] {
            let center = BlindBoxPullInteraction.ropeCenterY(circleBottom: bottom, size: size, diameter: diameter)
            let ropeTop = center - 49.5 * artworkScale
            #expect(abs(ropeTop - (bottom - inset) + 2) < 0.001)
        }
        #expect(BlindBoxPullInteraction.ropeCenterY(circleBottom: -30, size: size, diameter: diameter) == 38)
    }

    @Test(arguments: ["blinbox_la", "blinbox_box", "blindbox_shou", "scroll_down"])
    func suppliedAnimationsArePackaged(name: String) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "BlindBoxMotion"))
        let data = try Data(contentsOf: url)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["fr"] as? Double ?? 0) > 0)
        #expect(!(json["layers"] as? [Any] ?? []).isEmpty)
    }

    @Test func onlyDownwardPullAtScrollTopCanBegin() {
        #expect(BlindBoxPullInteraction.canBegin(scrollTop: 0, translation: CGSize(width: 2, height: 18)))
        #expect(!BlindBoxPullInteraction.canBegin(scrollTop: -100, translation: CGSize(width: 0, height: 40)))
        #expect(!BlindBoxPullInteraction.canBegin(scrollTop: 0, translation: CGSize(width: 40, height: 10)))
        #expect(!BlindBoxPullInteraction.canBegin(scrollTop: 0, translation: CGSize(width: 0, height: -40)))
    }

    @Test func reversedAndTinyPullsCancel() {
        #expect(!BlindBoxPullInteraction.shouldEnter(translation: CGSize(width: 0, height: 10)))
        #expect(!BlindBoxPullInteraction.shouldEnter(translation: CGSize(width: 0, height: -5)))
        #expect(BlindBoxPullInteraction.shouldEnter(translation: CGSize(width: 0, height: 28)))
        #expect(BlindBoxPullInteraction.shouldEnter(translation: CGSize(width: 0, height: 400)))
    }

    @Test(arguments: [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852), CGSize(width: 1024, height: 768)])
    func circleCoversAllFourCorners(size: CGSize) {
        let diameter = max(size.width * 3, size.height * 2.4)
        let radius = diameter / 2
        let centerY = BlindBoxPullInteraction.coveredBottom(size: size, diameter: diameter) - radius
        for y in [CGFloat.zero, size.height] {
            let distance = hypot(size.width / 2, y - centerY)
            #expect(distance < radius)
        }
    }
}

final class BlindBoxRuleEngineTests: XCTestCase {
    func testBuiltInThemesMatchConfiguredContentCounts() {
        XCTAssertEqual(BlindBoxCatalog.builtInThemes.count, 3)
        let zodiac = BlindBoxCatalog.zodiac
        XCTAssertEqual(zodiac.normalStickers.count, 12)
        XCTAssertEqual(zodiac.hiddenSticker?.id.rawValue, "zodiac_13")
        XCTAssertEqual(zodiac.presentation?.collectionPlacements.count, 13)
        XCTAssertNil(zodiac.validationError())

        let pets = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }
        XCTAssertEqual(pets?.normalStickers.count, 12)
        XCTAssertEqual(pets?.hiddenSticker?.id.rawValue, "pets_13")
        XCTAssertEqual(pets?.hiddenSticker?.assetName, "sticker_pets_13")
        XCTAssertTrue(pets?.normalStickers.contains(where: { $0.id.rawValue == "pets_12" }) == true)
        XCTAssertNil(pets?.validationError())

        let cozyDaily = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "cozy_daily" }
        XCTAssertEqual(cozyDaily?.normalStickers.count, 11)
        XCTAssertEqual(cozyDaily?.hiddenSticker?.id.rawValue, "cozy_09")
        XCTAssertEqual(cozyDaily?.hiddenSticker?.assetName, "sticker_cozy_09_hidden")
        XCTAssertFalse(cozyDaily?.stickers.contains(where: { $0.id.rawValue == "cozy_01" }) == true)
        XCTAssertTrue((10...13).allSatisfy { index in
            cozyDaily?.normalStickers.contains(where: { $0.id.rawValue == "cozy_\(String(format: "%02d", index))" }) == true
        })
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
        XCTAssertEqual(standard.normalStickerProbability, 0.99 / 12, accuracy: 0.000_001)
        XCTAssertEqual(standard.hiddenInclusionProbabilityPerBatch, 0.09, accuracy: 0.000_001)

        let hiddenHunt = try BlindBoxProbabilityEngine.disclosure(for: petsTheme, mode: .hiddenHunt)
        XCTAssertEqual(hiddenHunt.hiddenStickerProbability, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(hiddenHunt.normalStickerProbability, 0.95 / 12, accuracy: 0.000_001)
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

    func testGeneratedCozyBatchFillsNineUniquePositions() throws {
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])

        let plan = try BlindBoxBatchGenerator.generate(
            theme: cozyDailyTheme,
            ownedCounts: [:],
            generator: &generator
        )

        let stickers = plan.positions.map(\.stickerID)
        let counts = Dictionary(grouping: stickers, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(stickers.count, 9)
        XCTAssertEqual(counts.count, 9)
        XCTAssertEqual(counts.values.sorted(), [1, 1, 1, 1, 1, 1, 1, 1, 1])
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
            ]),
            artwork: remoteArtwork(prefix: "remote")
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
            ]),
            artwork: remoteArtwork(prefix: "retired")
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

        var legacyReleaseJSONObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(release)) as? [String: Any]
        )
        legacyReleaseJSONObject.removeValue(forKey: "economyConfiguration")
        let legacyReleaseData = try JSONSerialization.data(withJSONObject: legacyReleaseJSONObject)
        let decodedLegacyRelease = try JSONDecoder().decode(
            BlindBoxCatalogRelease.self,
            from: legacyReleaseData
        )
        XCTAssertEqual(
            decodedLegacyRelease.economyConfiguration,
            BlindBoxEconomyConfiguration.defaultValue
        )

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

    func testRemoteCatalogBundleRequiresEveryReferencedArtworkFile() throws {
        let release = makeCacheableCatalogRelease(releaseID: "bundle-release")
        let assetNames = Set(release.themes.flatMap { theme in
            theme.stickers.map(\.assetName) + (theme.artwork?.assetNames ?? [])
        })
        let artworkFiles = assetNames.sorted().map { assetName in
            BlindBoxCatalogArtworkFile(assetName: assetName, data: Data(assetName.utf8))
        }
        let validBundle = BlindBoxCatalogBundle(
            release: release,
            artworkFiles: artworkFiles
        )
        XCTAssertNil(validBundle.validationError())

        let missingAssetName = try XCTUnwrap(assetNames.sorted().first)
        let incompleteBundle = BlindBoxCatalogBundle(
            release: release,
            artworkFiles: artworkFiles.filter { $0.assetName != missingAssetName }
        )
        XCTAssertEqual(
            incompleteBundle.validationError(),
            .missingArtworkFile(missingAssetName)
        )
    }

    func testCatalogBundleCachePromotesOnlyCompleteBundlesAndFallsBackToPreviousRelease() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BlindBoxCatalogBundleCacheTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let firstBundle = makeCacheableCatalogBundle(releaseID: "bundle-one")
        XCTAssertEqual(
            BlindBoxCatalogBundleCache.install(
                firstBundle,
                currentBuild: 1,
                rootDirectory: rootDirectory
            ),
            .installed
        )
        XCTAssertEqual(
            BlindBoxCatalogBundleCache.load(currentBuild: 1, rootDirectory: rootDirectory)?.release,
            firstBundle.release
        )

        let secondBundle = makeCacheableCatalogBundle(releaseID: "bundle-two")
        XCTAssertEqual(
            BlindBoxCatalogBundleCache.install(
                secondBundle,
                currentBuild: 1,
                rootDirectory: rootDirectory
            ),
            .installed
        )
        let artworkName = try XCTUnwrap(secondBundle.artworkFiles.first?.assetName)
        let currentArtworkURL = try XCTUnwrap(
            BlindBoxCatalogBundleCache.artworkURL(
                named: artworkName,
                currentBuild: 1,
                rootDirectory: rootDirectory
            )
        )
        try Data("corrupted".utf8).write(to: currentArtworkURL, options: .atomic)

        XCTAssertEqual(
            BlindBoxCatalogBundleCache.load(currentBuild: 1, rootDirectory: rootDirectory)?.release,
            firstBundle.release
        )

        let missingAssetBundle = BlindBoxCatalogBundle(
            release: secondBundle.release,
            artworkFiles: Array(secondBundle.artworkFiles.dropFirst())
        )
        XCTAssertNotEqual(
            BlindBoxCatalogBundleCache.install(
                missingAssetBundle,
                currentBuild: 1,
                rootDirectory: rootDirectory
            ),
            .installed
        )
        XCTAssertEqual(
            BlindBoxCatalogBundleCache.load(currentBuild: 1, rootDirectory: rootDirectory)?.release,
            firstBundle.release
        )
    }

    @MainActor
    func testPublicCloudKitCatalogRepositoryDecodesThePublishedBundle() async throws {
        let bundle = makeCacheableCatalogBundle(releaseID: "public-catalog")
        let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BlindBoxCatalogPointer-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: assetURL) }
        try JSONEncoder().encode(bundle).write(to: assetURL, options: .atomic)

        let record = CKRecord(
            recordType: BlindBoxCloudKitCatalogRepository.pointerRecordType,
            recordID: BlindBoxCloudKitCatalogRepository.pointerRecordID
        )
        record[BlindBoxCloudKitCatalogRepository.bundleField] = CKAsset(fileURL: assetURL)
        let repository = BlindBoxCloudKitCatalogRepository(
            database: InMemoryBlindBoxCatalogPublicRecordDatabase(record: record)
        )

        let fetchedBundle = try await repository.fetchLatestBundle()
        XCTAssertEqual(fetchedBundle, bundle)
    }

    @MainActor
    func testFeatureStoreIncludesBundledZodiacWithActiveRemoteThemes() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BlindBoxFeatureStoreCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let remoteBundle = makeCacheableCatalogBundle(releaseID: "feature-store-catalog")
        let store = BlindBoxFeatureStore(
            themes: BlindBoxCatalog.builtInThemes,
            database: InMemoryBlindBoxCloudRecordDatabase(),
            legacyInventoryProvider: { [:] },
            catalogRepository: StaticBlindBoxCatalogBundleRepository(bundle: remoteBundle),
            catalogCurrentBuild: 1,
            catalogCacheRootDirectory: rootDirectory
        )

        await store.refresh(
            hasPremiumAccess: false,
            candidateZoneWasPresented: true,
            nativeICloudInitialImportComplete: true,
            now: Date(timeIntervalSince1970: 2_000),
            calendar: calendar
        )

        XCTAssertEqual(store.availability, .ready)
        XCTAssertEqual(store.themes, remoteBundle.release.themes + [BlindBoxCatalog.zodiac])
        XCTAssertEqual(
            Set(store.accountState.candidateBatches.map(\.plan.themeID)),
            Set(remoteBundle.release.activeThemeIDs + [BlindBoxCatalog.zodiac.id])
        )
    }

    @MainActor
    func testFeatureStoreAppliesARemoteOpeningPauseBeforeItCreatesADraw() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BlindBoxFeatureStoreEconomyTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let pausedEconomy = BlindBoxEconomyConfiguration(
            version: 2,
            isBlindBoxOpeningEnabled: false,
            isPointExchangeEnabled: false,
            pointExchangePrice: 250,
            maximumPointExchangesPerGrantDay: 1
        )
        let remoteBundle = makeCacheableCatalogBundle(
            releaseID: "feature-store-economy",
            economyConfiguration: pausedEconomy
        )
        let store = BlindBoxFeatureStore(
            themes: BlindBoxCatalog.builtInThemes,
            database: InMemoryBlindBoxCloudRecordDatabase(),
            legacyInventoryProvider: { [:] },
            catalogRepository: StaticBlindBoxCatalogBundleRepository(bundle: remoteBundle),
            catalogCurrentBuild: 1,
            catalogCacheRootDirectory: rootDirectory
        )

        await store.refresh(
            hasPremiumAccess: false,
            candidateZoneWasPresented: true,
            nativeICloudInitialImportComplete: true,
            now: Date(timeIntervalSince1970: 2_000),
            calendar: calendar
        )

        XCTAssertEqual(store.economyConfiguration, pausedEconomy)
        let batch = try XCTUnwrap(store.accountState.candidateBatches.first)
        do {
            _ = try await store.open(
                .single(batchID: batch.id, positionIndex: batch.unopenedPositionPlans[0].index),
                now: Date(timeIntervalSince1970: 2_000),
                calendar: calendar
            )
            XCTFail("A remotely paused catalog must reject a new draw.")
        } catch {
            XCTAssertEqual(error as? BlindBoxFeatureStoreError, .openingPaused)
        }
    }

    @MainActor
    func testFeatureStoreFailsClosedWhenItCannotVerifyRemoteCatalogForADraw() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = BlindBoxFeatureStore(
            themes: BlindBoxCatalog.builtInThemes,
            database: InMemoryBlindBoxCloudRecordDatabase(),
            legacyInventoryProvider: { [:] },
            catalogRepository: StaticBlindBoxCatalogBundleRepository(bundle: nil)
        )

        await store.refresh(
            hasPremiumAccess: false,
            candidateZoneWasPresented: false,
            nativeICloudInitialImportComplete: true,
            now: Date(timeIntervalSince1970: 2_000),
            calendar: calendar
        )

        let batch = try XCTUnwrap(store.accountState.candidateBatches.first)
        do {
            _ = try await store.open(
                .single(batchID: batch.id, positionIndex: batch.unopenedPositionPlans[0].index),
                now: Date(timeIntervalSince1970: 2_000),
                calendar: calendar
            )
            XCTFail("A draw must not use a catalog it could not freshly verify.")
        } catch {
            XCTAssertEqual(error as? BlindBoxFeatureStoreError, .remoteCatalogUnavailable)
        }
    }

    @MainActor
    func testFeatureStoreRequiresANewConfirmationWhenEconomyVersionChanges() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let economy = BlindBoxEconomyConfiguration(
            version: 2,
            isBlindBoxOpeningEnabled: true,
            isPointExchangeEnabled: true,
            pointExchangePrice: 250,
            maximumPointExchangesPerGrantDay: 1
        )
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BlindBoxFeatureStoreEconomyVersionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let store = BlindBoxFeatureStore(
            themes: BlindBoxCatalog.builtInThemes,
            database: InMemoryBlindBoxCloudRecordDatabase(),
            legacyInventoryProvider: { [:] },
            catalogRepository: StaticBlindBoxCatalogBundleRepository(
                bundle: makeCacheableCatalogBundle(
                    releaseID: "feature-store-economy-version",
                    economyConfiguration: economy
                )
            ),
            catalogCurrentBuild: 1,
            catalogCacheRootDirectory: rootDirectory
        )

        await store.refresh(
            hasPremiumAccess: false,
            candidateZoneWasPresented: false,
            nativeICloudInitialImportComplete: true,
            now: Date(timeIntervalSince1970: 2_000),
            calendar: calendar
        )
        let originalTicketBalance = store.accountState.ticketBalance

        do {
            _ = try await store.exchangePointsForOneTicket(
                availablePoints: 1_000,
                expectedEconomyConfigurationVersion: 1,
                now: Date(timeIntervalSince1970: 2_000),
                calendar: calendar
            )
            XCTFail("A stale confirmation must not exchange at an updated price.")
        } catch {
            XCTAssertEqual(error as? BlindBoxFeatureStoreError, .pointExchangeConfigurationChanged)
        }

        XCTAssertEqual(store.accountState.ticketBalance, originalTicketBalance)
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

    func testPointExchangeIsLimitedToThreePerGrantDayAtOneHundredPoints() {
        for used in 0...2 {
            XCTAssertEqual(BlindBoxPointExchangePolicy.eligibility(
                availablePoints: 100, ticketBalance: 19, exchangesUsedThisGrantDay: used
            ), .eligible)
        }
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
                exchangesUsedThisGrantDay: 3
            ),
            .grantDayLimitReached
        )
    }

    func testLegacyCatalogAllowsThreeExchangesAndCapacityStillWins() throws {
        let legacy = BlindBoxEconomyConfiguration(
            version: 1, isBlindBoxOpeningEnabled: true, isPointExchangeEnabled: true,
            pointExchangePrice: 100, maximumPointExchangesPerGrantDay: 1
        )
        XCTAssertNil(legacy.validationError())
        for used in 1...2 {
            XCTAssertEqual(BlindBoxPointExchangePolicy.eligibility(
                availablePoints: 100, ticketBalance: 0, exchangesUsedThisGrantDay: used,
                economyConfiguration: legacy
            ), .eligible)
        }
        XCTAssertEqual(BlindBoxPointExchangePolicy.eligibility(
            availablePoints: 100, ticketBalance: 0, exchangesUsedThisGrantDay: 3,
            economyConfiguration: legacy
        ), .grantDayLimitReached)
        XCTAssertEqual(BlindBoxPointExchangePolicy.eligibility(
            availablePoints: 100, ticketBalance: 20, exchangesUsedThisGrantDay: 1,
            economyConfiguration: legacy
        ), .ticketBalanceAtCapacity)
        XCTAssertEqual(BlindBoxPointExchangePolicy.eligibility(
            availablePoints: 99, ticketBalance: 0, exchangesUsedThisGrantDay: 2,
            economyConfiguration: legacy
        ), .insufficientPoints(required: 100, current: 99))
        let invalid = BlindBoxAccountState(pointExchangesUsedOnLastGrantDay: 4)
        XCTAssertThrowsError(try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONEncoder().encode(invalid)))
    }

    func testVersionedEconomyControlsPointExchangeAndSnapshotsItsPrice() throws {
        let economy = BlindBoxEconomyConfiguration(
            version: 2,
            isBlindBoxOpeningEnabled: true,
            isPointExchangeEnabled: true,
            pointExchangePrice: 250,
            maximumPointExchangesPerGrantDay: 1
        )
        XCTAssertNil(economy.validationError())
        XCTAssertEqual(
            BlindBoxPointExchangePolicy.eligibility(
                availablePoints: 250,
                ticketBalance: 0,
                exchangesUsedThisGrantDay: 0,
                economyConfiguration: economy
            ),
            .eligible
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var state = BlindBoxAccountState()
        let idempotencyKey = UUID(uuidString: "FACEFEED-0000-4000-8000-000000000031")!
        let reservation = try BlindBoxWalletStateMachine.reservePointsForOneTicketExchange(
            state: &state,
            idempotencyKey: idempotencyKey,
            availablePoints: 250,
            now: Date(timeIntervalSince1970: 1_000),
            calendar: calendar,
            economyConfiguration: economy
        )

        XCTAssertEqual(reservation.deductedPoints, 250)
        XCTAssertEqual(state.pendingPointExchange?.deductedPoints, 250)

        let completion = try BlindBoxWalletStateMachine.completeReservedPointExchange(
            state: &state,
            idempotencyKey: idempotencyKey
        )
        XCTAssertEqual(completion.deductedPoints, 250)
        XCTAssertEqual(completion.resultingTicketBalance, 1)

        let pausedExchange = BlindBoxEconomyConfiguration(
            version: 3,
            isBlindBoxOpeningEnabled: false,
            isPointExchangeEnabled: false,
            pointExchangePrice: 300,
            maximumPointExchangesPerGrantDay: 1
        )
        XCTAssertEqual(
            BlindBoxPointExchangePolicy.eligibility(
                availablePoints: 1_000,
                ticketBalance: 0,
                exchangesUsedThisGrantDay: 0,
                economyConfiguration: pausedExchange
            ),
            .disabled
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

    private func makeCacheableCatalogRelease(
        releaseID: String,
        economyConfiguration: BlindBoxEconomyConfiguration = .defaultValue
    ) -> BlindBoxCatalogRelease {
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
            ]),
            artwork: remoteArtwork(prefix: "cache")
        )
        return BlindBoxCatalogRelease(
            releaseID: releaseID,
            catalogSchemaVersion: 1,
            minimumAppBuild: 1,
            publishedAt: Date(timeIntervalSince1970: 1_000),
            activeThemeIDs: [theme.id],
            themes: [theme],
            economyConfiguration: economyConfiguration
        )
    }

    private func makeCacheableCatalogBundle(
        releaseID: String,
        economyConfiguration: BlindBoxEconomyConfiguration = .defaultValue
    ) -> BlindBoxCatalogBundle {
        let release = makeCacheableCatalogRelease(
            releaseID: releaseID,
            economyConfiguration: economyConfiguration
        )
        let assetNames = Set(release.themes.flatMap { theme in
            theme.stickers.map(\.assetName) + (theme.artwork?.assetNames ?? [])
        })
        return BlindBoxCatalogBundle(
            release: release,
            artworkFiles: assetNames.sorted().map { assetName in
                BlindBoxCatalogArtworkFile(assetName: assetName, data: Data(assetName.utf8))
            }
        )
    }

    private func remoteArtwork(prefix: String) -> BlindBoxThemeArtwork {
        BlindBoxThemeArtwork(
            lobbyCardAssetName: "\(prefix)_lobby",
            detailHeaderAssetName: "\(prefix)_header",
            detailBoardAssetName: "\(prefix)_board",
            collectionPickerAssetName: "\(prefix)_picker"
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
        XCTAssertEqual(
            updatedAccount.accountState.pendingReveal,
            BlindBoxPendingReveal(
                drawIdempotencyKey: request.idempotencyKey,
                result: draw.result
            )
        )
        XCTAssertEqual(originalAccount.accountState.ticketBalance, 2)

        let retryDecision = try BlindBoxCloudDrawTransaction.plan(
            request: request,
            account: updatedAccount,
            existingDraw: draw,
            committedAt: committedAt.addingTimeInterval(60)
        )
        XCTAssertEqual(retryDecision, .priorResult(draw.result))
    }

    func testCloudDrawTransactionBlocksANewDrawUntilThePendingRevealIsAcknowledged() throws {
        let plan = makePlan()
        let firstRequest = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000021")!,
            batchID: plan.id,
            positionIndex: 0
        )
        let nextRequest = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000022")!,
            batchID: plan.id,
            positionIndex: 1
        )
        let originalAccount = BlindBoxCloudAccountEnvelope(
            accountState: BlindBoxAccountState(
                ticketBalance: 2,
                candidateBatches: [BlindBoxCandidateBatch(plan: plan)]
            )
        )

        let firstDecision = try BlindBoxCloudDrawTransaction.plan(
            request: firstRequest,
            account: originalAccount,
            existingDraw: nil,
            committedAt: Date(timeIntervalSince1970: 1_000)
        )
        guard case let .commit(updatedAccount, _) = firstDecision else {
            return XCTFail("Expected the first draw to commit.")
        }

        XCTAssertThrowsError(
            try BlindBoxCloudDrawTransaction.plan(
                request: nextRequest,
                account: updatedAccount,
                existingDraw: nil,
                committedAt: Date(timeIntervalSince1970: 1_001)
            )
        ) { error in
            XCTAssertEqual(
                error as? BlindBoxOpenError,
                .pendingRevealMustBeAcknowledged
            )
        }
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
            BlindBoxCloudKitRecordCodec.makeAccountRecord(BlindBoxCloudAccountEnvelope(accountState: BlindBoxAccountState()))
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
    func testCloudAccountRepositoryAcknowledgesOnlyTheMatchingPendingReveal() async throws {
        let pendingKey = UUID(uuidString: "FACEFEED-0000-4000-8000-000000000023")!
        let pendingResult = BlindBoxOpenResult(
            batchID: UUID(uuidString: "A0000000-0000-4000-8000-000000000023")!,
            openedStickers: [],
            ticketCost: 1,
            resultingTicketBalance: 0,
            restockAt: nil
        )
        let database = InMemoryBlindBoxCloudRecordDatabase()
        try database.seed(
            BlindBoxCloudKitRecordCodec.makeAccountRecord(
                BlindBoxCloudAccountEnvelope(
                    accountState: BlindBoxAccountState(
                        pendingReveal: BlindBoxPendingReveal(
                            drawIdempotencyKey: pendingKey,
                            result: pendingResult
                        )
                    )
                )
            )
        )
        try await database.createZone(BlindBoxCloudKitRecordCodec.zoneID)
        let repository = BlindBoxCloudKitAccountStateRepository(database: database)

        let didRejectMismatchedAcknowledgement = try await repository.acknowledgePendingReveal(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000024")!
        )
        XCTAssertFalse(didRejectMismatchedAcknowledgement)
        let accountAfterMismatchedAcknowledgement = try await repository.loadAccount()
        XCTAssertEqual(
            accountAfterMismatchedAcknowledgement.accountState.pendingReveal?.result,
            pendingResult
        )

        let didAcknowledge = try await repository.acknowledgePendingReveal(idempotencyKey: pendingKey)
        XCTAssertTrue(didAcknowledge)
        let accountAfterAcknowledgement = try await repository.loadAccount()
        XCTAssertNil(accountAfterAcknowledgement.accountState.pendingReveal)
        let didIdempotentlyAcknowledge = try await repository.acknowledgePendingReveal(
            idempotencyKey: pendingKey
        )
        XCTAssertTrue(didIdempotentlyAcknowledge)
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
        XCTAssertEqual(store.accountState.ticketBalance, BlindBoxAccountState.initialTicketBalance)
        let batch = try XCTUnwrap(store.accountState.candidateBatches.first)
        let result = try await store.open(
            .single(batchID: batch.id, positionIndex: batch.unopenedPositionPlans[0].index),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.ticketCost, 1)
        XCTAssertEqual(store.accountState.ticketBalance, BlindBoxAccountState.initialTicketBalance - 1)
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
        XCTAssertEqual(account.accountState.ticketBalance, BlindBoxAccountState.initialTicketBalance)
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
            L10n.tr(
                "You're offline. Connect to the internet and try again.",
                zhHans: "当前无网络连接，请联网后重试。",
                zhHant: "目前沒有網路連線，請連線後再試。",
                ja: "オフラインです。インターネットに接続してから再試行してください。"
            )
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
        XCTAssertEqual(store.state.pendingReveal?.result, firstResult)

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
    func testPreviewDrawRepositoryRequiresAcknowledgingARevealBeforeANewDraw() async throws {
        let store = BlindBoxPreviewStore(referenceDate: Date(timeIntervalSince1970: 1_000))
        let batchID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let firstResult = try await store.open(
            .single(
                idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000025")!,
                batchID: batchID,
                positionIndex: 0
            )
        )

        do {
            _ = try await store.open(
                .single(
                    idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000026")!,
                    batchID: batchID,
                    positionIndex: 1
                )
            )
            XCTFail("A second preview draw must wait until the first reveal is acknowledged.")
        } catch {
            XCTAssertEqual(
                error as? BlindBoxOpenError,
                .pendingRevealMustBeAcknowledged
            )
        }

        store.acknowledgePendingReveal(firstResult)
        XCTAssertNil(store.state.pendingReveal)

        let secondResult = try await store.open(
            .single(
                idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000027")!,
                batchID: batchID,
                positionIndex: 1
            )
        )
        XCTAssertEqual(secondResult.ticketCost, 1)
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
private final class InMemoryBlindBoxCatalogPublicRecordDatabase: BlindBoxCatalogPublicRecordDatabase {
    private let record: CKRecord?

    init(record: CKRecord?) {
        self.record = record
    }

    func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        guard record?.recordID == recordID else { return nil }
        return record
    }
}

@MainActor
private final class StaticBlindBoxCatalogBundleRepository: BlindBoxCatalogBundleFetching {
    private let bundle: BlindBoxCatalogBundle?

    init(bundle: BlindBoxCatalogBundle?) {
        self.bundle = bundle
    }

    func fetchLatestBundle() async throws -> BlindBoxCatalogBundle? {
        bundle
    }
}

@MainActor
private final class InMemoryBlindBoxCloudRecordDatabase: BlindBoxCloudRecordDatabase {
    private var storedRecords: [CKRecord.ID: CKRecord] = [:]
    private var hasZone = false
    private var conflictingSaveAttempts: Int
    private var failingBeforeCommittedSaveAttempts: Int
    private var failingAfterCommittedSaveAttempts: Int

    private(set) var saveAttemptCount = 0

    var zoneWasCreated: Bool {
        hasZone
    }

    init(
        conflictingSaveAttempts: Int = 0,
        failingBeforeCommittedSaveAttempts: Int = 0,
        failingAfterCommittedSaveAttempts: Int = 0
    ) {
        self.conflictingSaveAttempts = conflictingSaveAttempts
        self.failingBeforeCommittedSaveAttempts = failingBeforeCommittedSaveAttempts
        self.failingAfterCommittedSaveAttempts = failingAfterCommittedSaveAttempts
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
        if failingBeforeCommittedSaveAttempts > 0 {
            failingBeforeCommittedSaveAttempts -= 1
            throw URLError(.notConnectedToInternet)
        }

        var nextRecords = storedRecords
        for record in records {
            nextRecords[record.recordID] = try clone(record)
        }
        storedRecords = nextRecords

        // Models an ambiguous client result: CloudKit committed atomically but
        // the connection failed before the client received the acknowledgement.
        // A subsequent command must therefore safely replay the same request.
        if failingAfterCommittedSaveAttempts > 0 {
            failingAfterCommittedSaveAttempts -= 1
            throw URLError(.timedOut)
        }
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

    func testAccountMaintenancePausesAutomaticOpeningWhenRemoteEconomyDisablesOpening() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let pets = BlindBoxCatalog.builtInThemes.first { $0.id.rawValue == "pets" }!
        let plan = makePlan(theme: pets, identifier: "C0FFEE00-0000-4000-8000-000000000007")
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
            isAutomaticOpeningEnabled: false,
            now: now,
            calendar: calendar,
            generator: &generator
        )

        XCTAssertNil(result.automaticOpen)
        XCTAssertTrue(state.candidateBatches[0].openedPositionIndices.isEmpty)
        XCTAssertEqual(state.candidateBatches[0].nextSystemOpenAt, now.addingTimeInterval(-1))
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
            ["pets", "cozy_daily", "zodiac"].contains($0.plan.themeID.rawValue)
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

    func testCollectionJourneyPreservesOldOddsBoostsNewBatchesAndStopsAfterCompletion() throws {
        for theme in BlindBoxCatalog.builtInThemes {
            for premium in [false, true] {
                let now = Date(timeIntervalSince1970: 2_000)
                let oldPlan = makePlan(theme: theme, identifier: "C0FFEE00-0000-4000-8000-000000000099")
                var state = BlindBoxAccountState(
                    ticketBalance: 20,
                    ownedStickerCounts: Dictionary(uniqueKeysWithValues: theme.normalStickers.dropFirst().map { ($0.id.rawValue, 1) }),
                    candidateBatches: [BlindBoxCandidateBatch(plan: oldPlan)]
                )
                _ = try BlindBoxStateMachine.openSingle(state: &state, batchID: oldPlan.id, positionIndex: 0, openedAt: now)
                XCTAssertEqual(state.ticketBalance, 19)
                XCTAssertTrue(theme.normalStickers.allSatisfy { state.ownedCount(for: $0.id) > 0 })
                var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0])
                _ = try BlindBoxCandidateCoordinator.reconcile(state: &state, themes: [theme], hasPremiumAccess: premium, reason: .themeCompleted, now: now, generator: &generator)
                XCTAssertEqual(state.candidateBatches.first?.plan, oldPlan, "Existing results and odds must not change")
                let newBatch = try XCTUnwrap(state.candidateBatches.first { $0.id != oldPlan.id })
                XCTAssertEqual(newBatch.plan.probabilityMode, .hiddenHunt)
                let oldOdds = try BlindBoxProbabilityEngine.disclosure(for: theme, mode: oldPlan.probabilityMode)
                let newOdds = try BlindBoxProbabilityEngine.disclosure(for: theme, mode: newBatch.plan.probabilityMode)
                XCTAssertEqual(oldOdds.hiddenStickerProbability, 0.01, accuracy: 0.000001)
                XCTAssertEqual(newOdds.hiddenStickerProbability, 0.05, accuracy: 0.000001)
                XCTAssertEqual(newOdds.hiddenInclusionProbabilityPerBatch, 0.45, accuracy: 0.000001)
                let hidden = try XCTUnwrap(theme.hiddenSticker)
                let position = try XCTUnwrap(newBatch.plan.positions.first { $0.stickerID == hidden.id })
                _ = try BlindBoxStateMachine.openSingle(state: &state, batchID: newBatch.id, positionIndex: position.index, openedAt: now)
                XCTAssertEqual(state.ticketBalance, 18)
                XCTAssertTrue(theme.stickers.allSatisfy { state.ownedCount(for: $0.id) > 0 })
                _ = try BlindBoxCandidateCoordinator.reconcile(state: &state, themes: [theme], hasPremiumAccess: premium, reason: .themeCompleted, now: now, generator: &generator)
                XCTAssertTrue(state.candidateBatches.isEmpty)
                state = try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONEncoder().encode(state))
                _ = try BlindBoxCandidateCoordinator.reconcile(state: &state, themes: [theme], hasPremiumAccess: premium, reason: .initialLoad, now: now.addingTimeInterval(172800), generator: &generator)
                XCTAssertTrue(state.candidateBatches.isEmpty, "Completed theme must not return after reload or restock")
                XCTAssertEqual(state.ticketBalance, 18)
            }
        }
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

final class BlindBoxForegroundMaintenanceScheduleTests: XCTestCase {
    func testNextMaintenanceUsesTheEarliestAutomaticOpenOrRestockDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 9,
            day: 1,
            hour: 3
        ))!
        let plan = BlindBoxBatchPlan(
            themeID: BlindBoxThemeID(rawValue: "pets"),
            catalogVersion: 1,
            probabilityMode: .standard,
            createdAt: now,
            positions: []
        )
        let automaticOpenDate = now.addingTimeInterval(20 * 60)
        let soldOutDate = now.addingTimeInterval(-23 * 60 * 60 - 30 * 60)
        let state = BlindBoxAccountState(candidateBatches: [
            BlindBoxCandidateBatch(plan: plan, nextSystemOpenAt: automaticOpenDate),
            BlindBoxCandidateBatch(
                plan: BlindBoxBatchPlan(
                    themeID: BlindBoxThemeID(rawValue: "cozy_daily"),
                    catalogVersion: 1,
                    probabilityMode: .standard,
                    createdAt: now,
                    positions: []
                ),
                soldOutAt: soldOutDate
            )
        ])

        XCTAssertEqual(
            BlindBoxForegroundMaintenanceSchedule.nextMaintenanceDate(
                for: state,
                now: now,
                calendar: calendar
            ),
            automaticOpenDate
        )
    }

    func testNextMaintenanceFallsBackToTheNextFourAMTicketBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 9,
            day: 1,
            hour: 5,
            minute: 30
        ))!
        let expected = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 9,
            day: 2,
            hour: 4
        ))!

        XCTAssertEqual(
            BlindBoxForegroundMaintenanceSchedule.nextMaintenanceDate(
                for: BlindBoxAccountState(),
                now: now,
                calendar: calendar
            ),
            expected
        )
    }

    func testRestockCountdownUsesTheExactTwentyFourHourWindow() {
        let now = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(
            BlindBoxRestockCountdown.text(
                restockAt: now.addingTimeInterval(90),
                now: now
            ),
            "00:01:30"
        )
        XCTAssertEqual(BlindBoxRestockCountdown.text(restockAt: nil, now: now), "24:00:00")
        XCTAssertEqual(
            BlindBoxRestockCountdown.text(
                restockAt: now.addingTimeInterval(-1),
                now: now
            ),
            "00:00:00"
        )
    }
}

final class BlindBoxWalletStateMachineTests: XCTestCase {
    func testUpgradePaysOnlyDailyDifferenceAndNeverRepeats() throws {
        var state = BlindBoxAccountState()
        let now = Date(timeIntervalSince1970: 1_000)
        let calendar = Calendar(identifier: .gregorian)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: calendar)
        XCTAssertEqual(state.pendingTicketReceipt?.count, 1)
        state.pendingTicketReceipt = nil
        _ = try BlindBoxWalletStateMachine.exchangePointsForOneTicket(state: &state, availablePoints: 100, now: now, calendar: calendar)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: calendar)
        XCTAssertEqual(state.ticketBalance, 4)
        XCTAssertEqual(state.pendingTicketReceipt?.count, 2)
        let receipt = state.pendingTicketReceipt
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: calendar)
        XCTAssertEqual(state.ticketBalance, 4)
        XCTAssertEqual(state.pendingTicketReceipt, receipt)
    }

    func testCappedAllowanceCannotBeReclaimedAfterSpending() {
        var state = BlindBoxAccountState(ticketBalance: 19)
        let now = Date(timeIntervalSince1970: 1_000)
        let calendar = Calendar(identifier: .gregorian)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: calendar)
        XCTAssertEqual(state.pendingTicketReceipt?.count, 1)
        state.ticketBalance = 15
        state.pendingTicketReceipt = nil
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: calendar)
        XCTAssertEqual(state.ticketBalance, 15)
        XCTAssertNil(state.pendingTicketReceipt)
    }

    func testCappedUpgradeDoesNotBankTheUnpaidDifference() {
        var state = BlindBoxAccountState(ticketBalance: 19)
        let now = Date(timeIntervalSince1970: 1_000)
        let calendar = Calendar(identifier: .gregorian)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: calendar)
        state.pendingTicketReceipt = nil
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: calendar)
        XCTAssertNil(state.pendingTicketReceipt)
        state.ticketBalance = 10
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: calendar)
        XCTAssertEqual(state.ticketBalance, 10)
    }

    func testUnseenReceiptIsReplacedOnNextDayAndOnlyTodayIsGranted() {
        var state = BlindBoxAccountState()
        let now = Date(timeIntervalSince1970: 1_000)
        let calendar = Calendar(identifier: .gregorian)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: calendar)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now.addingTimeInterval(86400 * 5), calendar: calendar)
        XCTAssertEqual(state.ticketBalance, 2)
        XCTAssertEqual(state.pendingTicketReceipt?.count, 1)
    }

    func testGrantReceiptSurvivesEncodingAndLegacyStateDecodes() throws {
        var state = BlindBoxAccountState()
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: .now, calendar: .current)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(BlindBoxAccountState.self, from: data), state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "pendingTicketReceipt")
        json.removeValue(forKey: "settledDailyTicketAllowance")
        let legacy = try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.pendingTicketReceipt)
        XCTAssertNil(legacy.settledDailyTicketAllowance)
    }

    func testDailyTicketRefreshAfterMissedDaysNeverExceedsTwentyTickets() {
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

    func testNewAccountStartsWithThreeLaunchTicketsWithoutFirstDayTopUp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var state = BlindBoxAccountState.newAccount()

        let result = BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: false,
            now: Date(timeIntervalSince1970: 1_000),
            calendar: calendar
        )

        XCTAssertEqual(state.ticketBalance, BlindBoxAccountState.initialTicketBalance)
        XCTAssertEqual(result.processedGrantDays, 0)
        XCTAssertEqual(result.grantedTicketCount, 0)
        XCTAssertNil(state.pendingTicketReceipt)
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

        for expectedCount in 2...3 {
            let result = try BlindBoxWalletStateMachine.exchangePointsForOneTicket(
                state: &state, availablePoints: 100,
                now: formatter.date(from: "2026-09-02T03:59:10Z")!, calendar: calendar
            )
            XCTAssertEqual(result.deductedPoints, 100)
            XCTAssertEqual(result.grantedTickets, 1)
            XCTAssertEqual(state.pointExchangesUsedOnLastGrantDay, expectedCount)
            let decoded = try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONEncoder().encode(state))
            XCTAssertEqual(decoded.pointExchangesUsedOnLastGrantDay, expectedCount)
        }

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
        XCTAssertEqual(afterReset.resultingTicketBalance, 6)
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

/// Executable boundary cases from sticker-blind-box-regression-test-cases.md.
/// Assertions describe the regression contract, including currently failing cases.
final class BlindBoxFullRegressionTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var now: Date { date("2026-09-07T12:00:00Z") }

    func testB01B02DailyAllowanceMatrix() {
        for premium in [false, true] {
            for initial in [0, 17, 18, 19, 20] {
                var state = BlindBoxAccountState(ticketBalance: initial)
                let allowance = premium ? 3 : 1
                let result = BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: premium, now: now, calendar: utc)
                XCTAssertEqual(result.grantedTicketCount, min(allowance, 20 - initial))
                XCTAssertEqual(state.ticketBalance, min(20, initial + allowance))
                XCTAssertEqual(state.settledDailyTicketAllowance, allowance)
                XCTAssertEqual(state.pendingTicketReceipt?.count ?? 0, result.grantedTicketCount)
            }
        }
    }

    func testB03B04C04C05C06RepeatedSettlementAndMembershipChanges() throws {
        for initial in [0, 18, 19, 20] {
            var state = BlindBoxAccountState(ticketBalance: initial)
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: utc)
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: utc)
            XCTAssertEqual(state.ticketBalance, min(20, initial + 3))
            state.ticketBalance = 0
            for _ in 0..<20 {
                state = try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONEncoder().encode(state))
                for premium in [false, true] {
                    BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: premium, now: now, calendar: utc)
                    XCTAssertEqual(state.ticketBalance, 0)
                }
            }
        }
    }

    func testB05B06B13CalendarBoundaries() throws {
        for day in ["2026-09-07", "2026-12-31", "2028-02-29"] {
            let boundary = date("\(day)T04:00:00Z")
            var state = BlindBoxAccountState()
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: boundary.addingTimeInterval(-1), calendar: utc)
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: boundary, calendar: utc)
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: boundary.addingTimeInterval(1), calendar: utc)
            XCTAssertEqual(state.ticketBalance, 2, day)
        }
        var state = BlindBoxAccountState()
        for stamp in ["2026-09-07T23:59:59Z", "2026-09-08T00:00:00Z", "2026-09-08T03:59:59Z"] {
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: date(stamp), calendar: utc)
        }
        XCTAssertEqual(state.ticketBalance, 1)
    }

    func testB09B10AbsenceAndReceiptReplacement() {
        for days in [1, 5, 30, 365] {
            for premium in [false, true] {
                var state = BlindBoxAccountState(ticketBalance: 2, lastTicketGrantDayIdentifier: "2026-09-07")
                state.settledDailyTicketAllowance = premium ? 3 : 1
                state.pendingTicketReceipt = BlindBoxTicketReceipt(day: "2026-09-07", count: 1)
                BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: premium, now: now.addingTimeInterval(Double(days) * 86400), calendar: utc)
                XCTAssertEqual(state.ticketBalance, premium ? 5 : 3)
                XCTAssertEqual(state.pendingTicketReceipt?.count, premium ? 3 : 1)
            }
        }
    }

    func testB11ClockRollbackMustNotUnlockAnotherExchange() throws {
        var state = BlindBoxAccountState()
        _ = try BlindBoxWalletStateMachine.exchangePointsForOneTicket(state: &state, availablePoints: 1000, now: now, calendar: utc)
        XCTAssertThrowsError(try BlindBoxWalletStateMachine.exchangePointsForOneTicket(state: &state, availablePoints: 900, now: now.addingTimeInterval(-86400), calendar: utc))
        XCTAssertEqual(state.ticketBalance, 1)
    }

    func testB12ChangingTimezoneMustNotGrantAgainAtSameInstant() {
        var west = utc
        west.timeZone = TimeZone(secondsFromGMT: -12 * 3600)!
        var east = utc
        east.timeZone = TimeZone(secondsFromGMT: 14 * 3600)!
        var state = BlindBoxAccountState()
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: west)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: east)
        XCTAssertEqual(state.ticketBalance, 1)
    }

    func testC12KnownFreeLegacyAccountReceivesUpgradeDifferenceAfterReload() throws {
        let suite = "BlindBoxRegression-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = BlindBoxAccountState(ticketBalance: 1, lastTicketGrantDayIdentifier: "2026-09-07")
        XCTAssertNil(state.settledDailyTicketAllowance)
        // Observe the actual free entitlement before upgrading; balance alone is not evidence.
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: utc)
        XCTAssertTrue(BlindBoxLocalStateStore.save(state, defaults: defaults))
        state = BlindBoxLocalStateStore.load(defaults: defaults)
        XCTAssertEqual(state.settledDailyTicketAllowance, 1)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: utc)
        XCTAssertEqual(state.ticketBalance, 3)
        XCTAssertEqual(state.pendingTicketReceipt?.count, 2)
        XCTAssertTrue(BlindBoxLocalStateStore.save(state, defaults: defaults))
        state = BlindBoxLocalStateStore.load(defaults: defaults)
        XCTAssertEqual(state.pendingTicketReceipt?.count, 2)
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: utc)
        XCTAssertEqual(state.ticketBalance, 3)
    }

    func testC12UnknownLegacyMembershipDoesNotInventASecondGrant() {
        var state = BlindBoxAccountState(ticketBalance: 1, lastTicketGrantDayIdentifier: "2026-09-07")
        // This may be a member who received 3 and spent 2; never infer free status from T=1.
        BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: utc)
        XCTAssertEqual(state.ticketBalance, 1)
        XCTAssertEqual(state.settledDailyTicketAllowance, 3)
    }

    func testH09DecoderRejectsInvalidWalletAndKeepsValidBoundaryValues() throws {
        let data = try JSONEncoder().encode(BlindBoxAccountState())
        let baseline = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for value in [0, 1, 19, 20] {
            var json = baseline
            json["ticketBalance"] = value
            let decoded = try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(decoded.ticketBalance, value)
        }
        for value in [-1, -10, 21, Int.max] {
            var json = baseline
            json["ticketBalance"] = value
            XCTAssertThrowsError(try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONSerialization.data(withJSONObject: json)))
        }
        for value in [-1, 4] {
            var json = baseline
            json["pointExchangesUsedOnLastGrantDay"] = value
            XCTAssertThrowsError(try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONSerialization.data(withJSONObject: json)))
        }
    }

    func testD01ToD05ExchangeMatrix() throws {
        for points in [0, 99, 100, 101, 199, 200, 10000] {
            for tickets in [0, 1, 17, 18, 19, 20] {
                for used in [0, 1, 2, 3] {
                    var state = BlindBoxAccountState(ticketBalance: tickets, lastPointExchangeDayIdentifier: "2026-09-07", pointExchangesUsedOnLastGrantDay: used)
                    let original = state
                    if points >= 100 && tickets < 20 && used < 3 {
                        let result = try BlindBoxWalletStateMachine.exchangePointsForOneTicket(state: &state, availablePoints: points, now: now, calendar: utc)
                        XCTAssertEqual(result.deductedPoints, 100)
                        XCTAssertEqual(state.ticketBalance, tickets + 1)
                        XCTAssertEqual(state.pointExchangesUsedOnLastGrantDay, used + 1)
                    } else {
                        XCTAssertThrowsError(try BlindBoxWalletStateMachine.exchangePointsForOneTicket(state: &state, availablePoints: points, now: now, calendar: utc))
                        XCTAssertEqual(state, original)
                    }
                }
            }
        }
    }

    func testA12ReceiptAggregatesOnlyUnseenTickets() {
        for viewed in [false, true] {
            var state = BlindBoxAccountState()
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: utc)
            if viewed { state.pendingTicketReceipt = nil }
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: now, calendar: utc)
            XCTAssertEqual(state.pendingTicketReceipt?.count, viewed ? 2 : 3)
            XCTAssertEqual(state.ticketBalance, 3)
        }
    }

    func testB14E10PendingReservationAcrossDayAndCapacity() throws {
        for initial in [18, 19] {
            var state = BlindBoxAccountState(ticketBalance: initial)
            let key = UUID()
            _ = try BlindBoxWalletStateMachine.reservePointsForOneTicketExchange(state: &state, idempotencyKey: key, availablePoints: 1000, now: date("2026-09-07T03:59:59Z"), calendar: utc)
            BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: true, now: date("2026-09-07T04:00:00Z"), calendar: utc)
            _ = try BlindBoxWalletStateMachine.completeReservedPointExchange(state: &state, idempotencyKey: key)
            XCTAssertEqual(state.ticketBalance, 20)
            state.ticketBalance = 19
            _ = try BlindBoxWalletStateMachine.exchangePointsForOneTicket(state: &state, availablePoints: 900, now: date("2026-09-07T04:00:01Z"), calendar: utc)
            XCTAssertEqual(state.ticketBalance, 20)
            XCTAssertThrowsError(try BlindBoxWalletStateMachine.exchangePointsForOneTicket(state: &state, availablePoints: 800, now: date("2026-09-07T04:00:02Z"), calendar: utc))
        }
    }

    @MainActor
    func testE13ReceiptAcknowledgementRejectsStaleIDs() async throws {
        let database = InMemoryBlindBoxCloudRecordDatabase()
        _ = try await database.createZone(BlindBoxCloudKitRecordCodec.zoneID)
        var state = BlindBoxAccountState(ticketBalance: 3)
        let receipt = BlindBoxTicketReceipt(day: "2026-09-07", count: 2)
        state.pendingTicketReceipt = receipt
        try database.seed(BlindBoxCloudKitRecordCodec.makeAccountRecord(BlindBoxCloudAccountEnvelope(accountState: state, completedLegacyMigrationVersions: [])))
        let repository = BlindBoxCloudKitAccountStateRepository(database: database)
        let stale = try await repository.acknowledgeTicketReceipt(UUID())
        XCTAssertFalse(stale)
        let first = try await repository.acknowledgeTicketReceipt(receipt.id)
        let second = try await repository.acknowledgeTicketReceipt(receipt.id)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let account = try await repository.loadAccount()
        XCTAssertEqual(account.accountState.ticketBalance, 3)
        XCTAssertNil(account.accountState.pendingTicketReceipt)
    }

    func testF04F05WholeBoxRemainingMatrix() throws {
        let theme = BlindBoxCatalog.builtInThemes[0]
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.5])
        let plan = try BlindBoxBatchGenerator.generate(theme: theme, ownedCounts: [:], generator: &generator)
        for remaining in [1, 2, 8, 9] {
            let batch = BlindBoxCandidateBatch(plan: plan, openedPositionIndices: Set(0..<(9 - remaining)))
            var state = BlindBoxAccountState(ticketBalance: remaining, candidateBatches: [batch])
            let result = try BlindBoxStateMachine.openWholeBox(state: &state, batchID: plan.id, openedAt: now)
            XCTAssertEqual(result.ticketCost, remaining)
            XCTAssertEqual(result.openedStickers.count, remaining)
            XCTAssertEqual(state.ticketBalance, 0)
            state = BlindBoxAccountState(ticketBalance: remaining - 1, candidateBatches: [batch])
            let original = state
            XCTAssertThrowsError(try BlindBoxStateMachine.openWholeBox(state: &state, batchID: plan.id, openedAt: now))
            XCTAssertEqual(state, original)
        }
    }

    func testH09DecodedOutOfRangeBalanceMustNotSurviveSettlement() throws {
        let data = try JSONEncoder().encode(BlindBoxAccountState())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for balance in [-10, 21] {
            json["ticketBalance"] = balance
            do {
                var state = try JSONDecoder().decode(BlindBoxAccountState.self, from: JSONSerialization.data(withJSONObject: json))
                BlindBoxWalletStateMachine.refreshDailyTickets(state: &state, hasPremiumAccess: false, now: now, calendar: utc)
                XCTAssertTrue((0...20).contains(state.ticketBalance), "Decoded balance \(balance) became \(state.ticketBalance)")
            } catch { /* Rejecting corrupt account payloads is acceptable. */ }
        }
    }
}

/// High-risk lifecycle cases that cannot be trusted to the happy-path UI alone.
/// They simulate a fresh app/repository after interruption while preserving the
/// same authoritative private-zone records.
final class BlindBoxInterruptionAndEntitlementRegressionTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func seededPlan() throws -> BlindBoxBatchPlan {
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])
        return try BlindBoxBatchGenerator.generate(
            theme: BlindBoxCatalog.builtInThemes[0],
            ownedCounts: [:],
            generator: &generator
        )
    }

    @MainActor
    func testKilledDuringCommittedDrawRestartsWithTheSameRevealAndNoSecondCharge() async throws {
        let plan = try seededPlan()
        let committedAt = date("2026-09-08T03:59:59Z")
        let request = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000301")!,
            batchID: plan.id,
            positionIndex: 0
        )
        let database = InMemoryBlindBoxCloudRecordDatabase()
        try await database.createZone(BlindBoxCloudKitRecordCodec.zoneID)
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

        let resultBeforeTermination = try await BlindBoxCloudKitDrawRepository(
            database: database,
            now: { committedAt }
        ).open(request)

        // Simulate termination: discard the repository and restore only from
        // persisted records, as a relaunched process would.
        let restoredAccountRepository = BlindBoxCloudKitAccountStateRepository(database: database)
        let restoredAccount = try await restoredAccountRepository.loadAccount()
        XCTAssertEqual(restoredAccount.accountState.ticketBalance, 1)
        XCTAssertEqual(restoredAccount.accountState.pendingReveal?.result, resultBeforeTermination)

        let retryAfterRestart = try await BlindBoxCloudKitDrawRepository(
            database: database,
            now: { committedAt.addingTimeInterval(11) }
        ).open(request)
        XCTAssertEqual(retryAfterRestart, resultBeforeTermination)
        let accountAfterRetry = try await restoredAccountRepository.loadAccount()
        XCTAssertEqual(accountAfterRetry.accountState.ticketBalance, 1)

        let newRequest = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000302")!,
            batchID: plan.id,
            positionIndex: 1
        )
        do {
            _ = try await BlindBoxCloudKitDrawRepository(database: database).open(newRequest)
            XCTFail("A fresh draw must wait until the interrupted reveal is acknowledged.")
        } catch {
            XCTAssertEqual(error as? BlindBoxOpenError, .pendingRevealMustBeAcknowledged)
        }

        let didAcknowledge = try await restoredAccountRepository.acknowledgePendingReveal(
            idempotencyKey: request.idempotencyKey
        )
        XCTAssertTrue(didAcknowledge)
        let nextResult = try await BlindBoxCloudKitDrawRepository(database: database).open(newRequest)
        XCTAssertEqual(nextResult.ticketCost, 1)
        let finalAccount = try await restoredAccountRepository.loadAccount()
        XCTAssertEqual(finalAccount.accountState.ticketBalance, 0)
    }

    @MainActor
    func testKilledAfterPointExchangeReservationCompletesTheOriginalIntentOnRestart() async throws {
        let requestedAt = date("2026-09-08T03:59:59Z")
        let request = BlindBoxPointExchangeRequest(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000303")!,
            requestedAt: requestedAt
        )
        let database = InMemoryBlindBoxCloudRecordDatabase()
        _ = try await BlindBoxCloudKitAccountBootstrapper(database: database).bootstrap(
            legacyInventoryCounts: [:]
        )

        let reservation = try await BlindBoxCloudKitPointExchangeRepository(database: database).begin(
            request,
            availablePoints: 100,
            calendar: utc
        )
        XCTAssertNil(reservation.completion)

        // The request was reserved before termination. A new process must use
        // that same intent, not create another point charge or ticket grant.
        let restartedRepository = BlindBoxCloudKitPointExchangeRepository(database: database)
        let pendingOptional = try await restartedRepository.pendingExchange()
        let pending = try XCTUnwrap(pendingOptional)
        XCTAssertEqual(pending.request, request)
        let completed = try await restartedRepository.complete(request, completedAt: requestedAt)
        XCTAssertEqual(completed.deductedPoints, 100)
        XCTAssertEqual(completed.grantedTickets, 1)

        let replay = try await restartedRepository.complete(request, completedAt: requestedAt)
        XCTAssertEqual(replay, completed)
        let restoredAccount = try await BlindBoxCloudKitAccountStateRepository(database: database).loadAccount()
        XCTAssertEqual(restoredAccount.accountState.ticketBalance, BlindBoxAccountState.initialTicketBalance + 1)
        XCTAssertNil(restoredAccount.accountState.pendingPointExchange)
        XCTAssertEqual(restoredAccount.accountState.pointExchangesUsedOnLastGrantDay, 1)
    }

    @MainActor
    func testForegroundSessionCrossingFourAMRefreshesExactlyOnceAndReschedulesTomorrow() async throws {
        let beforeFour = date("2026-09-08T03:59:59Z")
        let atFour = date("2026-09-08T04:00:00Z")
        let database = InMemoryBlindBoxCloudRecordDatabase()
        try await database.createZone(BlindBoxCloudKitRecordCodec.zoneID)
        var initialState = BlindBoxAccountState(
            ticketBalance: 6,
            lastTicketGrantDayIdentifier: "2026-09-07"
        )
        initialState.settledDailyTicketAllowance = 1
        try database.seed(
            BlindBoxCloudKitRecordCodec.makeAccountRecord(
                BlindBoxCloudAccountEnvelope(
                    accountState: initialState
                )
            )
        )
        let repository = BlindBoxCloudKitAccountStateRepository(database: database)
        func request(now: Date) -> BlindBoxCloudMaintenanceRequest {
            BlindBoxCloudMaintenanceRequest(
                themes: [],
                hasPremiumAccess: false,
                candidateZoneWasPresented: false,
                now: now,
                calendar: utc
            )
        }

        let accountBeforeFour = try await repository.loadAccount()
        let nextMaintenance = BlindBoxForegroundMaintenanceSchedule.nextMaintenanceDate(
            for: accountBeforeFour.accountState,
            now: beforeFour,
            calendar: utc
        )
        XCTAssertEqual(nextMaintenance, atFour)

        let beforeResult = try await repository.maintain(request(now: beforeFour))
        XCTAssertEqual(beforeResult.dailyTicketRefresh.grantedTicketCount, 0)
        let boundaryResult = try await repository.maintain(request(now: atFour))
        XCTAssertEqual(boundaryResult.dailyTicketRefresh.grantedTicketCount, 1)
        let repeatedResult = try await repository.maintain(request(now: atFour.addingTimeInterval(1)))
        XCTAssertEqual(repeatedResult.dailyTicketRefresh.grantedTicketCount, 0)

        let settled = try await repository.loadAccount().accountState
        XCTAssertEqual(settled.ticketBalance, 7)
        XCTAssertEqual(settled.pendingTicketReceipt?.count, 1)
        let tomorrowMaintenance = BlindBoxForegroundMaintenanceSchedule.nextMaintenanceDate(
            for: settled,
            now: atFour,
            calendar: utc
        )
        XCTAssertEqual(tomorrowMaintenance, date("2026-09-09T04:00:00Z"))
    }

    @MainActor
    func testOfflineAndAmbiguousTimeoutRetriesNeverDoubleChargeOrDoubleGrant() async throws {
        let plan = try seededPlan()
        let request = BlindBoxDrawRequest.single(
            idempotencyKey: UUID(uuidString: "FACEFEED-0000-4000-8000-000000000304")!,
            batchID: plan.id,
            positionIndex: 0
        )

        // Offline before commit: no state transition occurred, so retry later
        // is the one and only paid opening.
        let offlineDatabase = InMemoryBlindBoxCloudRecordDatabase(
            failingBeforeCommittedSaveAttempts: 1
        )
        try await offlineDatabase.createZone(BlindBoxCloudKitRecordCodec.zoneID)
        try offlineDatabase.seed(
            BlindBoxCloudKitRecordCodec.makeAccountRecord(
                BlindBoxCloudAccountEnvelope(
                    accountState: BlindBoxAccountState(ticketBalance: 1, candidateBatches: [BlindBoxCandidateBatch(plan: plan)])
                )
            )
        )
        do {
            _ = try await BlindBoxCloudKitDrawRepository(database: offlineDatabase).open(request)
            XCTFail("The pre-commit offline request must surface its transport error.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        let offlineAccountBeforeRetry = try await BlindBoxCloudKitAccountStateRepository(
            database: offlineDatabase
        ).loadAccount()
        XCTAssertEqual(offlineAccountBeforeRetry.accountState.ticketBalance, 1)
        let offlineRetry = try await BlindBoxCloudKitDrawRepository(database: offlineDatabase).open(request)
        XCTAssertEqual(offlineRetry.ticketCost, 1)
        let offlineAccountAfterRetry = try await BlindBoxCloudKitAccountStateRepository(
            database: offlineDatabase
        ).loadAccount()
        XCTAssertEqual(offlineAccountAfterRetry.accountState.ticketBalance, 0)

        // Timeout after an atomic server commit: client retry finds the stored
        // draw by idempotency key instead of opening (and charging) again.
        let timeoutDatabase = InMemoryBlindBoxCloudRecordDatabase(
            failingAfterCommittedSaveAttempts: 1
        )
        try await timeoutDatabase.createZone(BlindBoxCloudKitRecordCodec.zoneID)
        try timeoutDatabase.seed(
            BlindBoxCloudKitRecordCodec.makeAccountRecord(
                BlindBoxCloudAccountEnvelope(
                    accountState: BlindBoxAccountState(ticketBalance: 1, candidateBatches: [BlindBoxCandidateBatch(plan: plan)])
                )
            )
        )
        do {
            _ = try await BlindBoxCloudKitDrawRepository(database: timeoutDatabase).open(request)
            XCTFail("The post-commit timeout must surface its ambiguous transport error.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        let timeoutRetry = try await BlindBoxCloudKitDrawRepository(database: timeoutDatabase).open(request)
        XCTAssertEqual(timeoutRetry.ticketCost, 1)
        let timeoutAccount = try await BlindBoxCloudKitAccountStateRepository(
            database: timeoutDatabase
        ).loadAccount()
        XCTAssertEqual(timeoutAccount.accountState.ticketBalance, 0)
        XCTAssertEqual(timeoutAccount.accountState.pendingReveal?.result, timeoutRetry)
    }

    func testMembershipExpiryAndRestorationPreserveTicketsAndRefreshVisibleCapacity() throws {
        let firstDay = date("2026-09-08T12:00:00Z")
        let secondDay = date("2026-09-09T12:00:00Z")
        var state = BlindBoxAccountState()

        // Active member: receives the full daily allowance and six slots.
        BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: true,
            now: firstDay,
            calendar: utc
        )
        XCTAssertEqual(state.ticketBalance, 3)
        XCTAssertEqual(state.settledDailyTicketAllowance, 3)
        XCTAssertEqual(BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: true), 6)

        // Expiry does not reclaim a ticket or create a negative adjustment;
        // the lobby immediately presents only the free four-slot capacity.
        BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: false,
            now: firstDay,
            calendar: utc
        )
        XCTAssertEqual(state.ticketBalance, 3)
        XCTAssertEqual(state.settledDailyTicketAllowance, 3)
        XCTAssertEqual(BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: false), 4)

        // Restoring on the same grant day is idempotent: no duplicate tickets.
        BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: true,
            now: firstDay,
            calendar: utc
        )
        XCTAssertEqual(state.ticketBalance, 3)

        // On the next day, a lapsed account gets one ticket. Restoring later
        // that same day supplies only the two-ticket entitlement difference.
        BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: false,
            now: secondDay,
            calendar: utc
        )
        XCTAssertEqual(state.ticketBalance, 4)
        XCTAssertEqual(state.settledDailyTicketAllowance, 1)
        BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: true,
            now: secondDay,
            calendar: utc
        )
        XCTAssertEqual(state.ticketBalance, 6)
        XCTAssertEqual(state.pendingTicketReceipt?.count, 3)

        var candidates = BlindBoxAccountState()
        var generator = ScriptedBlindBoxRandomNumberGenerator(values: [0.99])
        _ = try BlindBoxCandidateCoordinator.reconcile(
            state: &candidates,
            themes: BlindBoxCatalog.builtInThemes,
            hasPremiumAccess: true,
            reason: .initialLoad,
            now: firstDay,
            generator: &generator
        )
        XCTAssertEqual(candidates.candidateBatches.count, 6)
        _ = try BlindBoxCandidateCoordinator.reconcile(
            state: &candidates,
            themes: BlindBoxCatalog.builtInThemes,
            hasPremiumAccess: false,
            reason: .initialLoad,
            now: secondDay,
            generator: &generator
        )
        XCTAssertEqual(candidates.candidateBatches.count, 4)
        _ = try BlindBoxCandidateCoordinator.reconcile(
            state: &candidates,
            themes: BlindBoxCatalog.builtInThemes,
            hasPremiumAccess: true,
            reason: .initialLoad,
            now: secondDay,
            generator: &generator
        )
        XCTAssertEqual(candidates.candidateBatches.count, 6)
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
