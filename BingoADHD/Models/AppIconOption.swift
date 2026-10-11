import Foundation

enum AppIconOption: String, CaseIterable, Identifiable {
    case `default`
    case halloween
    case days10
    case days20
    case days30
    case premium

    var id: String { rawValue }

    var previewAssetName: String {
        switch self {
        case .default:
            return "AppIconPreviewDefault"
        case .halloween:
            return "AppIconPreviewHalloween"
        case .days10:
            return "AppIconPreview10Days"
        case .days20:
            return "AppIconPreview20Days"
        case .days30:
            return "AppIconPreview30Days"
        case .premium:
            return "AppIconPreviewPremium"
        }
    }

    /// A stable asset identity, independent of which seasonal icon is primary.
    var iconAssetName: String {
        switch self {
        case .default:
            return "AppIcon"
        case .halloween:
            return "AppIconHalloween"
        case .days10:
            return "AppIcon10Days"
        case .days20:
            return "AppIcon20Days"
        case .days30:
            return "AppIcon30Days"
        case .premium:
            return "AppIconPremium"
        }
    }

    func alternateIconName(primaryIconName: String?) -> String? {
        iconAssetName == primaryIconName ? nil : iconAssetName
    }

    var requiredDays: Int? {
        switch self {
        case .default, .halloween, .premium:
            return nil
        case .days10:
            return 10
        case .days20:
            return 20
        case .days30:
            return 30
        }
    }

    var displayName: String {
        switch self {
        case .default:
            return L10n.tr("Default", zhHans: "默认", zhHant: "預設", ja: "デフォルト")
        case .halloween:
            return "Halloween"
        case .days10:
            return "10 days"
        case .days20:
            return "20 days"
        case .days30:
            return "30 days"
        case .premium:
            return "Premium"
        }
    }

    func isUnlocked(bestStreak: Int) -> Bool {
        guard let requiredDays else { return true }
        return bestStreak >= requiredDays
    }
}
