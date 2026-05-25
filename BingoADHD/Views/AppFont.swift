import SwiftUI

extension Font {
    static func appSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        switch AppLanguage.current {
        case .english:
            return .custom("Outfit", size: size).weight(weight)
        case .simplifiedChinese, .traditionalChinese, .japanese:
            return .system(size: size, weight: weight, design: design)
        }
    }
}
