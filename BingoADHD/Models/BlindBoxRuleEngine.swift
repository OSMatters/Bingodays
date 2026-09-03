import Foundation

/// Identifies a remotely configurable sticker theme without tying the blind-box
/// domain to the legacy direct-redemption `StickerKind` enum.
struct BlindBoxThemeID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }
}

/// Identifies one sticker inside a blind-box theme. IDs remain stable even when
/// display text or artwork is changed by remote configuration.
struct BlindBoxStickerID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }
}

struct BlindBoxStickerDefinition: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: BlindBoxStickerID
    let assetName: String
    let isHidden: Bool

    init(id: BlindBoxStickerID, assetName: String, isHidden: Bool) {
        self.id = id
        self.assetName = assetName
        self.isHidden = isHidden
    }
}

/// A catalog-owned coordinate for one sticker in My Box. Keeping the display
/// order in content configuration lets newly published themes choose a layout
/// without requiring an app release or a new hard-coded switch statement.
struct BlindBoxCollectionPlacement: Codable, Equatable, Hashable, Identifiable, Sendable {
    let stickerID: BlindBoxStickerID
    let centerX: Double
    let centerY: Double
    let displaySize: Double
    let isSpecialSlot: Bool

    var id: BlindBoxStickerID { stickerID }

    init(
        stickerID: BlindBoxStickerID,
        centerX: Double,
        centerY: Double,
        displaySize: Double,
        isSpecialSlot: Bool = false
    ) {
        self.stickerID = stickerID
        self.centerX = centerX
        self.centerY = centerY
        self.displaySize = displaySize
        self.isSpecialSlot = isSpecialSlot
    }
}

struct BlindBoxThemePresentation: Codable, Equatable, Hashable, Sendable {
    let collectionPlacements: [BlindBoxCollectionPlacement]

    init(collectionPlacements: [BlindBoxCollectionPlacement]) {
        self.collectionPlacements = collectionPlacements
    }

    func validationError(
        stickerIDs: [BlindBoxStickerID],
        hiddenStickerID: BlindBoxStickerID
    ) -> BlindBoxThemePresentationValidationError? {
        guard collectionPlacements.count == stickerIDs.count else {
            return .incorrectStickerCount(expected: stickerIDs.count, actual: collectionPlacements.count)
        }
        guard Set(collectionPlacements.map(\.stickerID)).count == collectionPlacements.count else {
            return .duplicateStickerPlacement
        }
        guard Set(collectionPlacements.map(\.stickerID)) == Set(stickerIDs) else {
            return .placementsDoNotMatchTheme
        }

        let specialPlacements = collectionPlacements.filter(\.isSpecialSlot)
        guard specialPlacements.count == 1 else {
            return .incorrectSpecialSlotCount(actual: specialPlacements.count)
        }
        guard specialPlacements[0].stickerID == hiddenStickerID else {
            return .specialSlotMustContainHiddenSticker
        }
        guard collectionPlacements.allSatisfy({
            $0.centerX >= 0 && $0.centerX <= 393 &&
            $0.centerY >= 0 && $0.centerY <= 852 &&
            $0.displaySize > 0
        }) else {
            return .invalidCoordinate
        }
        return nil
    }
}

enum BlindBoxThemePresentationValidationError: Equatable, Sendable {
    case incorrectStickerCount(expected: Int, actual: Int)
    case duplicateStickerPlacement
    case placementsDoNotMatchTheme
    case incorrectSpecialSlotCount(actual: Int)
    case specialSlotMustContainHiddenSticker
    case invalidCoordinate
}

/// The non-sticker artwork a theme needs to render in the shared Figma layout.
/// Remote releases supply these as cache keys for image files that travel with
/// the catalog bundle; built-in development themes continue to use the fixed
/// asset-catalog artwork until the remote catalog is enabled for release.
struct BlindBoxThemeArtwork: Codable, Equatable, Hashable, Sendable {
    let lobbyCardAssetName: String
    let detailHeaderAssetName: String
    let detailBoardAssetName: String
    let collectionPickerAssetName: String

    init(
        lobbyCardAssetName: String,
        detailHeaderAssetName: String,
        detailBoardAssetName: String,
        collectionPickerAssetName: String
    ) {
        self.lobbyCardAssetName = lobbyCardAssetName
        self.detailHeaderAssetName = detailHeaderAssetName
        self.detailBoardAssetName = detailBoardAssetName
        self.collectionPickerAssetName = collectionPickerAssetName
    }

    var assetNames: [String] {
        [
            lobbyCardAssetName,
            detailHeaderAssetName,
            detailBoardAssetName,
            collectionPickerAssetName
        ]
    }

    func validationError() -> BlindBoxThemeArtworkValidationError? {
        guard assetNames.allSatisfy(BlindBoxAssetName.isValid) else {
            return .invalidAssetName
        }
        guard Set(assetNames).count == assetNames.count else {
            return .duplicateAssetName
        }
        return nil
    }
}

enum BlindBoxThemeArtworkValidationError: Equatable, Sendable {
    case invalidAssetName
    case duplicateAssetName
}

/// Keeps remotely supplied filenames safe to use as keys in the app's catalog
/// cache. Artwork is always addressed by an opaque key rather than a path.
enum BlindBoxAssetName {
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 120 else { return false }
        return value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) ||
            ($0.value >= 65 && $0.value <= 90) ||
            ($0.value >= 97 && $0.value <= 122) ||
            $0 == "_" || $0 == "-"
        }
    }
}

struct BlindBoxThemeDefinition: Codable, Equatable, Identifiable, Sendable {
    let id: BlindBoxThemeID
    let catalogVersion: Int
    let stickers: [BlindBoxStickerDefinition]
    /// Optional only for the built-in development fallback. A remotely
    /// published theme must provide and pass this presentation validation.
    let presentation: BlindBoxThemePresentation?
    /// Required by remotely published themes. Built-in development themes may
    /// omit it while they use the fixed Figma-exported artwork in Assets.xcassets.
    let artwork: BlindBoxThemeArtwork?

    init(
        id: BlindBoxThemeID,
        catalogVersion: Int,
        stickers: [BlindBoxStickerDefinition],
        presentation: BlindBoxThemePresentation? = nil,
        artwork: BlindBoxThemeArtwork? = nil
    ) {
        self.id = id
        self.catalogVersion = catalogVersion
        self.stickers = stickers
        self.presentation = presentation
        self.artwork = artwork
    }

    var normalStickers: [BlindBoxStickerDefinition] {
        stickers.filter { !$0.isHidden }
    }

    var hiddenSticker: BlindBoxStickerDefinition? {
        stickers.first(where: \.isHidden)
    }

    var collectionSize: Int {
        stickers.count
    }

    func validationError() -> BlindBoxThemeValidationError? {
        guard !id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalidThemeID
        }
        guard catalogVersion > 0 else { return .invalidCatalogVersion }
        guard stickers.allSatisfy({
            !$0.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return .invalidStickerID
        }
        guard stickers.allSatisfy({
            !$0.assetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return .invalidAssetName
        }
        guard !normalStickers.isEmpty else { return .missingNormalSticker }
        guard hiddenSticker != nil else { return .missingHiddenSticker }
        guard stickers.filter(\.isHidden).count == 1 else { return .multipleHiddenStickers }
        guard Set(stickers.map(\.id)).count == stickers.count else { return .duplicateStickerID }
        guard Set(stickers.map(\.assetName)).count == stickers.count else { return .duplicateAssetName }
        guard normalStickers.count <= BlindBoxRuleConfiguration.maximumNormalStickerCount else {
            return .tooManyNormalStickers(maximum: BlindBoxRuleConfiguration.maximumNormalStickerCount)
        }
        if let presentation,
           let hiddenSticker,
           let error = presentation.validationError(
               stickerIDs: stickers.map(\.id),
               hiddenStickerID: hiddenSticker.id
           ) {
            return .invalidPresentation(error)
        }
        if let artwork,
           let error = artwork.validationError() {
            return .invalidArtwork(error)
        }
        return nil
    }
}

enum BlindBoxThemeValidationError: Error, Equatable {
    case invalidThemeID
    case invalidCatalogVersion
    case invalidStickerID
    case invalidAssetName
    case missingNormalSticker
    case missingHiddenSticker
    case multipleHiddenStickers
    case duplicateStickerID
    case duplicateAssetName
    case tooManyNormalStickers(maximum: Int)
    case invalidPresentation(BlindBoxThemePresentationValidationError)
    case invalidArtwork(BlindBoxThemeArtworkValidationError)
}

/// Versioned economy controls delivered together with a catalog release. The
/// values are deliberately small in scope: a published catalog can pause new
/// openings or ticket exchange and adjust the next exchange price without
/// changing any result that was already committed.
struct BlindBoxEconomyConfiguration: Codable, Equatable, Sendable {
    static let defaultValue = BlindBoxEconomyConfiguration(
        version: 1,
        isBlindBoxOpeningEnabled: true,
        isPointExchangeEnabled: true,
        pointExchangePrice: 100,
        maximumPointExchangesPerGrantDay: 1
    )

    let version: Int
    let isBlindBoxOpeningEnabled: Bool
    let isPointExchangeEnabled: Bool
    let pointExchangePrice: Int
    let maximumPointExchangesPerGrantDay: Int

    init(
        version: Int,
        isBlindBoxOpeningEnabled: Bool,
        isPointExchangeEnabled: Bool,
        pointExchangePrice: Int,
        maximumPointExchangesPerGrantDay: Int
    ) {
        self.version = version
        self.isBlindBoxOpeningEnabled = isBlindBoxOpeningEnabled
        self.isPointExchangeEnabled = isPointExchangeEnabled
        self.pointExchangePrice = pointExchangePrice
        self.maximumPointExchangesPerGrantDay = maximumPointExchangesPerGrantDay
    }

    func validationError() -> BlindBoxEconomyConfigurationValidationError? {
        guard version > 0 else { return .invalidVersion }
        guard (50...9_999).contains(pointExchangePrice) else {
            return .invalidPointExchangePrice
        }
        guard maximumPointExchangesPerGrantDay == 1 else {
            return .invalidMaximumPointExchangesPerGrantDay
        }
        return nil
    }
}

enum BlindBoxEconomyConfigurationValidationError: Error, Equatable, Sendable {
    case invalidVersion
    case invalidPointExchangePrice
    case invalidMaximumPointExchangesPerGrantDay
}

/// Immutable, remotely publishable catalog payload. The current app keeps its
/// built-in catalog as a fallback, while future CloudKit releases use this type
/// to validate a complete candidate before it becomes active on-device.
struct BlindBoxCatalogRelease: Codable, Equatable, Sendable {
    let releaseID: String
    let catalogSchemaVersion: Int
    let minimumAppBuild: Int
    let publishedAt: Date
    let activeThemeIDs: [BlindBoxThemeID]
    let themes: [BlindBoxThemeDefinition]
    let economyConfiguration: BlindBoxEconomyConfiguration

    init(
        releaseID: String,
        catalogSchemaVersion: Int,
        minimumAppBuild: Int,
        publishedAt: Date,
        activeThemeIDs: [BlindBoxThemeID],
        themes: [BlindBoxThemeDefinition],
        economyConfiguration: BlindBoxEconomyConfiguration = .defaultValue
    ) {
        self.releaseID = releaseID
        self.catalogSchemaVersion = catalogSchemaVersion
        self.minimumAppBuild = minimumAppBuild
        self.publishedAt = publishedAt
        self.activeThemeIDs = activeThemeIDs
        self.themes = themes
        self.economyConfiguration = economyConfiguration
    }

    private enum CodingKeys: String, CodingKey {
        case releaseID
        case catalogSchemaVersion
        case minimumAppBuild
        case publishedAt
        case activeThemeIDs
        case themes
        case economyConfiguration
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            releaseID: try container.decode(String.self, forKey: .releaseID),
            catalogSchemaVersion: try container.decode(Int.self, forKey: .catalogSchemaVersion),
            minimumAppBuild: try container.decode(Int.self, forKey: .minimumAppBuild),
            publishedAt: try container.decode(Date.self, forKey: .publishedAt),
            activeThemeIDs: try container.decode([BlindBoxThemeID].self, forKey: .activeThemeIDs),
            themes: try container.decode([BlindBoxThemeDefinition].self, forKey: .themes),
            economyConfiguration: try container.decodeIfPresent(
                BlindBoxEconomyConfiguration.self,
                forKey: .economyConfiguration
            ) ?? .defaultValue
        )
    }

    /// Active themes retain the publisher's explicit order. Retired themes may
    /// remain in `themes` so historical batches and My Box can still resolve
    /// their IDs without making them candidates again.
    var activeThemes: [BlindBoxThemeDefinition] {
        let themesByID = Dictionary(
            themes.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return activeThemeIDs.compactMap { themesByID[$0] }
    }

    func validationError() -> BlindBoxCatalogReleaseValidationError? {
        guard !releaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalidReleaseID
        }
        guard catalogSchemaVersion > 0 else { return .invalidCatalogSchemaVersion }
        guard minimumAppBuild >= 0 else { return .invalidMinimumAppBuild }
        if let economyError = economyConfiguration.validationError() {
            return .invalidEconomyConfiguration(economyError)
        }
        guard Set(themes.map(\.id)).count == themes.count else { return .duplicateThemeID }
        guard Set(activeThemeIDs).count == activeThemeIDs.count else {
            return .duplicateActiveThemeID
        }

        let allStickerIDs = themes.flatMap { $0.stickers.map(\.id) }
        guard Set(allStickerIDs).count == allStickerIDs.count else {
            return .duplicateStickerID
        }

        let knownThemeIDs = Set(themes.map(\.id))
        for activeThemeID in activeThemeIDs where !knownThemeIDs.contains(activeThemeID) {
            return .activeThemeMissingDefinition(activeThemeID)
        }

        for theme in themes {
            guard let themeError = theme.validationError() else {
                if theme.presentation == nil {
                    return .missingPresentation(theme.id)
                }
                if theme.artwork == nil {
                    return .missingArtwork(theme.id)
                }
                continue
            }
            return .invalidTheme(themeID: theme.id, error: themeError)
        }
        return nil
    }
}

enum BlindBoxCatalogReleaseValidationError: Error, Equatable {
    case invalidReleaseID
    case invalidCatalogSchemaVersion
    case invalidMinimumAppBuild
    case invalidEconomyConfiguration(BlindBoxEconomyConfigurationValidationError)
    case duplicateThemeID
    case duplicateStickerID
    case duplicateActiveThemeID
    case activeThemeMissingDefinition(BlindBoxThemeID)
    case missingPresentation(BlindBoxThemeID)
    case missingArtwork(BlindBoxThemeID)
    case invalidTheme(themeID: BlindBoxThemeID, error: BlindBoxThemeValidationError)
}

enum BlindBoxProbabilityMode: String, Codable, CaseIterable, Sendable {
    case standard
    case hiddenHunt

    var hiddenStickerProbability: Double {
        switch self {
        case .standard: return BlindBoxRuleConfiguration.standardHiddenStickerProbability
        case .hiddenHunt: return BlindBoxRuleConfiguration.hiddenHuntStickerProbability
        }
    }

    /// Each batch has nine positions and holds at most one hidden sticker. This
    /// preserves the displayed per-position hidden chance exactly.
    var hiddenInclusionProbability: Double {
        hiddenStickerProbability * Double(BlindBoxRuleConfiguration.batchPositionCount)
    }
}

enum BlindBoxRuleConfiguration {
    static let batchPositionCount = 9
    static let freeCandidateCount = 4
    static let premiumCandidateCount = 6
    static let freeDailyTicketAllowance = 1
    static let premiumDailyTicketAllowance = 3
    static let maximumTicketBalance = 20
    static let standardHiddenStickerProbability = 0.01
    static let hiddenHuntStickerProbability = 0.05
    static let minimumAutomaticOpenInterval: TimeInterval = 45 * 60
    static let maximumAutomaticOpenInterval: TimeInterval = 180 * 60
    static let restockDelay: TimeInterval = 24 * 60 * 60
    static let maximumNormalStickerCount = 18
}

struct BlindBoxProbabilityDisclosure: Equatable, Sendable {
    let mode: BlindBoxProbabilityMode
    let hiddenStickerProbability: Double
    let normalStickerProbability: Double
    let hiddenInclusionProbabilityPerBatch: Double
}

enum BlindBoxProbabilityEngine {
    static func mode(
        for theme: BlindBoxThemeDefinition,
        ownedCounts: [BlindBoxStickerID: Int]
    ) -> BlindBoxProbabilityMode {
        guard let hiddenSticker = theme.hiddenSticker,
              (ownedCounts[hiddenSticker.id] ?? 0) == 0,
              theme.normalStickers.allSatisfy({ (ownedCounts[$0.id] ?? 0) > 0 }) else {
            return .standard
        }
        return .hiddenHunt
    }

    static func disclosure(
        for theme: BlindBoxThemeDefinition,
        mode: BlindBoxProbabilityMode
    ) throws -> BlindBoxProbabilityDisclosure {
        if let validationError = theme.validationError() {
            throw validationError
        }

        let normalProbability = (1 - mode.hiddenStickerProbability) /
            Double(theme.normalStickers.count)
        return BlindBoxProbabilityDisclosure(
            mode: mode,
            hiddenStickerProbability: mode.hiddenStickerProbability,
            normalStickerProbability: normalProbability,
            hiddenInclusionProbabilityPerBatch: mode.hiddenInclusionProbability
        )
    }
}

protocol BlindBoxRandomNumberGenerating {
    mutating func nextUnitInterval() -> Double
}

struct SystemBlindBoxRandomNumberGenerator: BlindBoxRandomNumberGenerating {
    private var generator = SystemRandomNumberGenerator()

    mutating func nextUnitInterval() -> Double {
        Double.random(in: 0..<1, using: &generator)
    }
}

struct BlindBoxPositionPlan: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let index: Int
    let stickerID: BlindBoxStickerID

    init(id: UUID = UUID(), index: Int, stickerID: BlindBoxStickerID) {
        self.id = id
        self.index = index
        self.stickerID = stickerID
    }
}

/// A generated plan is immutable. Future CloudKit work stores this exact plan
/// before exposing a batch, so opening animations never decide the reward.
struct BlindBoxBatchPlan: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let themeID: BlindBoxThemeID
    let catalogVersion: Int
    let probabilityMode: BlindBoxProbabilityMode
    let createdAt: Date
    let positions: [BlindBoxPositionPlan]

    init(
        id: UUID = UUID(),
        themeID: BlindBoxThemeID,
        catalogVersion: Int,
        probabilityMode: BlindBoxProbabilityMode,
        createdAt: Date,
        positions: [BlindBoxPositionPlan]
    ) {
        self.id = id
        self.themeID = themeID
        self.catalogVersion = catalogVersion
        self.probabilityMode = probabilityMode
        self.createdAt = createdAt
        self.positions = positions
    }
}

enum BlindBoxBatchGenerationError: Error, Equatable {
    case invalidTheme(BlindBoxThemeValidationError)
    case invalidRandomValue
}

enum BlindBoxBatchGenerator {
    static func generate<Generator: BlindBoxRandomNumberGenerating>(
        theme: BlindBoxThemeDefinition,
        ownedCounts: [BlindBoxStickerID: Int],
        batchID: UUID = UUID(),
        createdAt: Date = .now,
        generator: inout Generator
    ) throws -> BlindBoxBatchPlan {
        if let validationError = theme.validationError() {
            throw BlindBoxBatchGenerationError.invalidTheme(validationError)
        }

        let probabilityMode = BlindBoxProbabilityEngine.mode(for: theme, ownedCounts: ownedCounts)
        let containsHidden = try draw(
            probability: probabilityMode.hiddenInclusionProbability,
            generator: &generator
        )
        var stickerIDs = try normalStickerIDs(
            from: theme.normalStickers.map(\.id),
            count: BlindBoxRuleConfiguration.batchPositionCount - (containsHidden ? 1 : 0),
            generator: &generator
        )

        if containsHidden, let hiddenID = theme.hiddenSticker?.id {
            let insertionIndex = try randomIndex(upperBound: stickerIDs.count + 1, generator: &generator)
            stickerIDs.insert(hiddenID, at: insertionIndex)
        }

        let positions = stickerIDs.enumerated().map { index, stickerID in
            BlindBoxPositionPlan(index: index, stickerID: stickerID)
        }
        return BlindBoxBatchPlan(
            id: batchID,
            themeID: theme.id,
            catalogVersion: theme.catalogVersion,
            probabilityMode: probabilityMode,
            createdAt: createdAt,
            positions: positions
        )
    }

    private static func normalStickerIDs<Generator: BlindBoxRandomNumberGenerating>(
        from normalStickerIDs: [BlindBoxStickerID],
        count: Int,
        generator: inout Generator
    ) throws -> [BlindBoxStickerID] {
        var result: [BlindBoxStickerID] = []
        while result.count < count {
            var shuffledCycle = normalStickerIDs
            try shuffle(&shuffledCycle, generator: &generator)
            let remainingCount = count - result.count
            result.append(contentsOf: shuffledCycle.prefix(remainingCount))
        }
        try shuffle(&result, generator: &generator)
        return result
    }

    private static func shuffle<Generator: BlindBoxRandomNumberGenerating>(
        _ values: inout [BlindBoxStickerID],
        generator: inout Generator
    ) throws {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let swapIndex = try randomIndex(upperBound: index + 1, generator: &generator)
            values.swapAt(index, swapIndex)
        }
    }

    private static func draw<Generator: BlindBoxRandomNumberGenerating>(
        probability: Double,
        generator: inout Generator
    ) throws -> Bool {
        try nextUnitInterval(using: &generator) < probability
    }

    private static func randomIndex<Generator: BlindBoxRandomNumberGenerating>(
        upperBound: Int,
        generator: inout Generator
    ) throws -> Int {
        precondition(upperBound > 0)
        let value = try nextUnitInterval(using: &generator)
        return min(Int(value * Double(upperBound)), upperBound - 1)
    }

    private static func nextUnitInterval<Generator: BlindBoxRandomNumberGenerating>(
        using generator: inout Generator
    ) throws -> Double {
        let value = generator.nextUnitInterval()
        guard value >= 0, value < 1 else {
            throw BlindBoxBatchGenerationError.invalidRandomValue
        }
        return value
    }
}

enum BlindBoxTicketGrantResult: Equatable {
    case granted(amount: Int, resultingBalance: Int)
    case atCapacity
}

enum BlindBoxTicketPolicy {
    static func candidateCount(hasPremiumAccess: Bool) -> Int {
        hasPremiumAccess
            ? BlindBoxRuleConfiguration.premiumCandidateCount
            : BlindBoxRuleConfiguration.freeCandidateCount
    }

    static func dailyAllowance(hasPremiumAccess: Bool) -> Int {
        hasPremiumAccess
            ? BlindBoxRuleConfiguration.premiumDailyTicketAllowance
            : BlindBoxRuleConfiguration.freeDailyTicketAllowance
    }

    static func dailyGrant(
        currentBalance: Int,
        hasPremiumAccess: Bool
    ) -> BlindBoxTicketGrantResult {
        let normalizedBalance = min(
            max(currentBalance, 0),
            BlindBoxRuleConfiguration.maximumTicketBalance
        )
        let amount = min(
            dailyAllowance(hasPremiumAccess: hasPremiumAccess),
            BlindBoxRuleConfiguration.maximumTicketBalance - normalizedBalance
        )
        guard amount > 0 else { return .atCapacity }
        return .granted(amount: amount, resultingBalance: normalizedBalance + amount)
    }

    static func restockDate(soldOutAt: Date) -> Date {
        soldOutAt.addingTimeInterval(BlindBoxRuleConfiguration.restockDelay)
    }

    static func automaticOpenDelay<Generator: BlindBoxRandomNumberGenerating>(
        generator: inout Generator
    ) -> TimeInterval? {
        let unitInterval = generator.nextUnitInterval()
        guard unitInterval >= 0, unitInterval < 1 else { return nil }
        let range = BlindBoxRuleConfiguration.maximumAutomaticOpenInterval -
            BlindBoxRuleConfiguration.minimumAutomaticOpenInterval
        return BlindBoxRuleConfiguration.minimumAutomaticOpenInterval + (range * unitInterval)
    }
}

/// Formats the fixed 24-hour sold-out window without consulting the device's
/// locale calendar. The restock instant is still persisted as a Date; this is
/// only the small, user-facing countdown representation.
enum BlindBoxRestockCountdown {
    static func text(restockAt: Date?, now: Date = .now) -> String {
        let defaultInterval = BlindBoxRuleConfiguration.restockDelay
        let interval = restockAt?.timeIntervalSince(now) ?? defaultInterval
        let remainingSeconds = max(0, Int(interval))
        return String(
            format: "%02d:%02d:%02d",
            remainingSeconds / 3_600,
            (remainingSeconds % 3_600) / 60,
            remainingSeconds % 60
        )
    }
}

enum BlindBoxPointExchangeEligibility: Equatable {
    case eligible
    case disabled
    case insufficientPoints(required: Int, current: Int)
    case ticketBalanceAtCapacity
    case grantDayLimitReached
}

enum BlindBoxPointExchangePolicy {
    static func eligibility(
        availablePoints: Int,
        ticketBalance: Int,
        exchangesUsedThisGrantDay: Int,
        economyConfiguration: BlindBoxEconomyConfiguration = .defaultValue
    ) -> BlindBoxPointExchangeEligibility {
        guard economyConfiguration.isPointExchangeEnabled else {
            return .disabled
        }
        guard ticketBalance < BlindBoxRuleConfiguration.maximumTicketBalance else {
            return .ticketBalanceAtCapacity
        }
        guard exchangesUsedThisGrantDay < economyConfiguration.maximumPointExchangesPerGrantDay else {
            return .grantDayLimitReached
        }
        guard availablePoints >= economyConfiguration.pointExchangePrice else {
            return .insufficientPoints(
                required: economyConfiguration.pointExchangePrice,
                current: availablePoints
            )
        }
        return .eligible
    }
}

enum BlindBoxCatalog {
    /// The local fallback mirrors the assets exported from the user-supplied Figma
    /// page. Remote catalog work later replaces this list without changing IDs.
    static let builtInThemes: [BlindBoxThemeDefinition] = [
        BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "pets"),
            catalogVersion: 1,
            stickers: (1...12).map { index in
                BlindBoxStickerDefinition(
                    id: BlindBoxStickerID(rawValue: "pets_\(String(format: "%02d", index))"),
                    assetName: index == 12
                        ? "sticker_pets_12_hidden"
                        : "sticker_pets_\(String(format: "%02d", index))",
                    isHidden: index == 12
                )
            }
        ),
        BlindBoxThemeDefinition(
            id: BlindBoxThemeID(rawValue: "cozy_daily"),
            catalogVersion: 1,
            stickers: (1...9).map { index in
                BlindBoxStickerDefinition(
                    id: BlindBoxStickerID(rawValue: "cozy_\(String(format: "%02d", index))"),
                    assetName: index == 9
                        ? "sticker_cozy_09_hidden"
                        : "sticker_cozy_\(String(format: "%02d", index))",
                    isHidden: index == 9
                )
            }
        )
    ]
}
