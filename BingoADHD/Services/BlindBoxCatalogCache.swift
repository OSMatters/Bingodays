import Foundation

enum BlindBoxCatalogCacheSaveResult: Equatable, Sendable {
    case saved
    case rejectedInvalidRelease(BlindBoxCatalogReleaseValidationError)
    case rejectedIncompatibleBuild(required: Int, current: Int)
    case persistenceFailed
}

/// Stores only a fully validated remote catalog. A failed download, invalid
/// publish, or too-new catalog never clears the last-known-good release that
/// My Box needs to render existing user ownership.
enum BlindBoxCatalogCache {
    static func load(
        defaults: UserDefaults = .standard,
        currentBuild: Int
    ) -> BlindBoxCatalogRelease? {
        guard let data = defaults.data(forKey: AppSettings.blindBoxCatalogReleaseKey),
              let release = try? JSONDecoder().decode(BlindBoxCatalogRelease.self, from: data),
              release.validationError() == nil,
              release.minimumAppBuild <= currentBuild else {
            return nil
        }
        return release
    }

    /// Invalid or incompatible input leaves the previous cached release
    /// untouched. The future CloudKit client calls this only after it finishes
    /// downloading every referenced asset and verifies its checksum.
    @discardableResult
    static func save(
        _ release: BlindBoxCatalogRelease,
        defaults: UserDefaults = .standard,
        currentBuild: Int
    ) -> BlindBoxCatalogCacheSaveResult {
        if let validationError = release.validationError() {
            return .rejectedInvalidRelease(validationError)
        }
        guard release.minimumAppBuild <= currentBuild else {
            return .rejectedIncompatibleBuild(
                required: release.minimumAppBuild,
                current: currentBuild
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(release) else {
            return .persistenceFailed
        }
        guard defaults.data(forKey: AppSettings.blindBoxCatalogReleaseKey) != data else {
            return .saved
        }
        defaults.set(data, forKey: AppSettings.blindBoxCatalogReleaseKey)
        guard defaults.data(forKey: AppSettings.blindBoxCatalogReleaseKey) == data else {
            return .persistenceFailed
        }
        return .saved
    }
}
