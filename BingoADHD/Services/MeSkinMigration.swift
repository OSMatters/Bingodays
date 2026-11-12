import Foundation

enum MeSkinMigration {
    static let completionKey = "me_autumn_default_applied_v1"

    /// A seasonal introduction runs once, independent of subsequent app versions.
    static func applyIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: completionKey) else { return }
        defaults.set(MeSkin.autumn.rawValue, forKey: AppSettings.meSkinKey)
        defaults.set(true, forKey: completionKey)
    }
}
