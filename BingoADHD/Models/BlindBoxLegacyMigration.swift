import Foundation

/// A dry-run-only conversion plan from the existing direct-redemption inventory
/// to the data-driven Blind Box catalog. It deliberately has no storage or
/// CloudKit dependency: the real migration will first persist this preview,
/// then apply it once behind a migration-version marker.
struct BlindBoxLegacyInventoryMigrationPreview: Equatable, Sendable {
    let migratedOwnedStickerCounts: [String: Int]
    let unmappedLegacyStickerIDs: [String]

    var migratedStickerTotal: Int {
        migratedOwnedStickerCounts.values.reduce(0, +)
    }
}

enum BlindBoxLegacyStickerMigration {
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
}
