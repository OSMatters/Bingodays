import Foundation

/// A conversion plan from the existing direct-redemption inventory to the
/// data-driven Blind Box catalog. Applying the plan never changes the legacy
/// inventory; it only copies its ownership into the Blind Box account state.
struct BlindBoxLegacyInventoryMigrationPreview: Equatable, Sendable {
    let migratedOwnedStickerCounts: [String: Int]
    let unmappedLegacyStickerIDs: [String]

    var migratedStickerTotal: Int {
        migratedOwnedStickerCounts.values.reduce(0, +)
    }
}

enum BlindBoxLegacyMigrationResult: Equatable, Sendable {
    case applied(BlindBoxLegacyInventoryMigrationPreview)
    case alreadyApplied
    case requiresManualReview(unmappedLegacyStickerIDs: [String])
}

enum BlindBoxLegacyStickerMigration {
    static let initialCatalogMigrationVersion = 1

    /// Every legacy asset has a visually matching item in the first Pets
    /// catalog. Two earlier enum aliases intentionally merge into a duplicate
    /// count, preserving every owned inventory item without erasing history.
    private static let destinations: [String: BlindBoxStickerID] = [
        StickerKind.akita.rawValue: BlindBoxStickerID(rawValue: "pets_01"),
        StickerKind.orangeCat.rawValue: BlindBoxStickerID(rawValue: "pets_02"),
        StickerKind.chineseVillageDog.rawValue: BlindBoxStickerID(rawValue: "pets_03"),
        StickerKind.pomeranian.rawValue: BlindBoxStickerID(rawValue: "pets_04"),
        StickerKind.yorkshire.rawValue: BlindBoxStickerID(rawValue: "pets_05"),
        StickerKind.dachshund.rawValue: BlindBoxStickerID(rawValue: "pets_06"),
        StickerKind.alaskanMalamute.rawValue: BlindBoxStickerID(rawValue: "pets_07"),
        StickerKind.goldenRetriever.rawValue: BlindBoxStickerID(rawValue: "pets_08"),
        StickerKind.maineCoon.rawValue: BlindBoxStickerID(rawValue: "pets_09"),
        StickerKind.toyPoodle.rawValue: BlindBoxStickerID(rawValue: "pets_10"),
        StickerKind.cowCat.rawValue: BlindBoxStickerID(rawValue: "pets_11"),
        StickerKind.cowCatStar.rawValue: BlindBoxStickerID(rawValue: "pets_11"),
        StickerKind.ragdollCat.rawValue: BlindBoxStickerID(rawValue: "pets_12"),
        StickerKind.ragdollCatStar.rawValue: BlindBoxStickerID(rawValue: "pets_12")
    ]

    static func preview(
        inventoryCounts: [String: Int]
    ) -> BlindBoxLegacyInventoryMigrationPreview {
        var migratedCounts: [String: Int] = [:]
        var unmappedIDs: [String] = []

        for (legacyID, count) in inventoryCounts where count > 0 {
            guard let destination = destinations[legacyID] else {
                unmappedIDs.append(legacyID)
                continue
            }
            migratedCounts[destination.rawValue, default: 0] += count
        }

        return BlindBoxLegacyInventoryMigrationPreview(
            migratedOwnedStickerCounts: migratedCounts,
            unmappedLegacyStickerIDs: unmappedIDs.sorted()
        )
    }

    /// Applies the initial catalog migration exactly once. Unknown legacy IDs
    /// leave both the Blind Box state and the version marker untouched, so a
    /// future catalog update can resolve them without losing ownership.
    static func apply(
        legacyInventoryCounts: [String: Int],
        to state: inout BlindBoxAccountState,
        completedMigrationVersions: inout Set<Int>,
        migrationVersion: Int = initialCatalogMigrationVersion
    ) -> BlindBoxLegacyMigrationResult {
        guard !completedMigrationVersions.contains(migrationVersion) else {
            return .alreadyApplied
        }

        let preview = preview(inventoryCounts: legacyInventoryCounts)
        guard preview.unmappedLegacyStickerIDs.isEmpty else {
            return .requiresManualReview(
                unmappedLegacyStickerIDs: preview.unmappedLegacyStickerIDs
            )
        }

        for (stickerID, legacyCount) in preview.migratedOwnedStickerCounts {
            state.ownedStickerCounts[stickerID, default: 0] += legacyCount
        }
        completedMigrationVersions.insert(migrationVersion)
        return .applied(preview)
    }
}

/// Reads the legacy sticker inventory without calling `StickerStore`, because
/// that store intentionally normalizes and rewrites its historical data during
/// loading. The Blind Box migration must be a non-mutating reader of the old
/// feature's state.
enum BlindBoxLegacyInventoryReader {
    static func loadInventoryCounts(defaults: UserDefaults = .standard) -> [String: Int] {
        if let data = defaults.data(forKey: AppSettings.stickerInventoryCountsKey),
           let savedCounts = try? JSONDecoder().decode([String: Int].self, from: data) {
            return normalizedCounts(savedCounts)
        }

        if let data = defaults.data(forKey: AppSettings.redeemedStickerOrderKey),
           let orderedKinds = try? JSONDecoder().decode([StickerKind].self, from: data) {
            return ownershipCounts(for: orderedKinds)
        }

        if let data = defaults.data(forKey: AppSettings.redeemedStickersKey),
           let redeemedKinds = try? JSONDecoder().decode([StickerKind].self, from: data) {
            return ownershipCounts(for: redeemedKinds)
        }

        return [:]
    }

    private static func normalizedCounts(_ counts: [String: Int]) -> [String: Int] {
        counts.reduce(into: [:]) { result, entry in
            guard entry.value > 0 else { return }
            // Legacy direct-redemption stickers were binary ownership. Keep a
            // defensively malformed positive value from minting extra copies.
            result[entry.key] = 1
        }
    }

    private static func ownershipCounts(for kinds: [StickerKind]) -> [String: Int] {
        Dictionary(kinds.map { ($0.rawValue, 1) }, uniquingKeysWith: { _, latest in latest })
    }
}
