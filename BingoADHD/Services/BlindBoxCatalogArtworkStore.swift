import UIKit

/// Resolves only previously validated catalog artwork. Images stay in memory
/// while the Blind Box flow is visible, avoiding repeated manifest checks and
/// file decoding for SwiftUI body updates. A catalog refresh explicitly calls
/// `reload()` before it presents a newly installed release.
@MainActor
final class BlindBoxCatalogArtworkStore {
    static let shared = BlindBoxCatalogArtworkStore()

    private let currentBuild: Int
    private var entry: BlindBoxCatalogBundleCache.Entry?
    private var hasLoadedEntry = false
    private let images = NSCache<NSString, UIImage>()

    private static let imageCacheCostLimit = 32 * 1024 * 1024
    private static let imageCacheCountLimit = 48

    private init(
        currentBuild: Int = Int(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ) ?? 0
    ) {
        self.currentBuild = currentBuild
        images.totalCostLimit = Self.imageCacheCostLimit
        images.countLimit = Self.imageCacheCountLimit
    }

    func image(named assetName: String) -> UIImage? {
        let cacheKey = assetName as NSString
        if let image = images.object(forKey: cacheKey) {
            return image
        }
        if !hasLoadedEntry {
            entry = BlindBoxCatalogBundleCache.load(currentBuild: currentBuild)
            hasLoadedEntry = true
        }
        guard let entry,
              BlindBoxAssetName.isValid(assetName) else {
            return nil
        }
        let fileURL = entry.directoryURL.appendingPathComponent("\(assetName).png")
        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let cost = max(1, Int(pixelWidth * pixelHeight * 4))
        images.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    func reload() {
        entry = BlindBoxCatalogBundleCache.load(currentBuild: currentBuild)
        hasLoadedEntry = true
        images.removeAllObjects()
    }
}
