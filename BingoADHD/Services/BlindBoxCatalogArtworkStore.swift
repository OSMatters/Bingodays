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
    private var images: [String: UIImage] = [:]

    private init(
        currentBuild: Int = Int(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ) ?? 0
    ) {
        self.currentBuild = currentBuild
    }

    func image(named assetName: String) -> UIImage? {
        if let image = images[assetName] {
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
        images[assetName] = image
        return image
    }

    func reload() {
        entry = BlindBoxCatalogBundleCache.load(currentBuild: currentBuild)
        hasLoadedEntry = true
        images.removeAll()
    }
}
