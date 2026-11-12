import SwiftUI

enum MeSkin: String, CaseIterable, Identifiable {
    case autumn
    case halloween
    case normal

    var id: String { rawValue }
    var isHalloween: Bool { self == .halloween }
    var isDarkBackground: Bool { self != .normal }

    var title: String {
        switch self {
        case .autumn:
            L10n.tr("Autumn", zhHans: "秋日", zhHant: "秋日", ja: "秋", ko: "가을")
        case .halloween:
            L10n.tr("Halloween", zhHans: "万圣节", zhHant: "萬聖節", ja: "ハロウィン")
        case .normal:
            L10n.tr("Classic", zhHans: "经典", zhHant: "經典", ja: "クラシック", ko: "클래식")
        }
    }

    private var assetPrefix: String {
        switch self {
        case .autumn: "MeAutumn"
        case .halloween: "MeHalloween"
        case .normal: "Me"
        }
    }

    var backgroundImageName: String { "\(assetPrefix)Background" }

    var pickerImageName: String {
        switch self {
        case .autumn: "MeSkinAutumnIcon"
        case .halloween: "MeSkinHalloweenIcon"
        case .normal: "MeSkinNormalIcon"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .autumn: Color(hex: "54251B")
        case .halloween: Color(hex: "131936")
        case .normal: Color(hex: "F9F7F0")
        }
    }

    var titleColor: Color {
        switch self {
        case .autumn: Color(hex: "FFF9F4")
        case .halloween: Color(hex: "FFF7E8")
        case .normal: Color(hex: "463C2E")
        }
    }

    var actionColor: Color {
        switch self {
        case .autumn: Color(hex: "DDB080")
        case .halloween: Color(hex: "FFC477")
        case .normal: Color(hex: "D6A77C")
        }
    }

    var pickerColor: Color {
        switch self {
        case .autumn: Color(hex: "401B0B")
        case .halloween: Color(hex: "20294D")
        case .normal: Color.white.opacity(0.18)
        }
    }

    var controlTextColor: Color {
        isDarkBackground ? .white : .black
    }

    var controlBorderColor: Color {
        isDarkBackground ? .white.opacity(0.55) : .black
    }

    var crownArrowImageName: String {
        isDarkBackground ? "MeHalloweenCrownArrow" : "MeCrownArrow"
    }

    func characterImageName(isPremiumMember: Bool, hasReviewedApp: Bool) -> String {
        let membership = isPremiumMember ? "Pro" : "Nopro"
        let review = hasReviewedApp ? "Reviewed" : "Unreviewed"
        return "\(assetPrefix)\(membership)\(review)"
    }
}
