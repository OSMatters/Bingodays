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
        case .simplifiedChinese, .traditionalChinese, .japanese, .korean, .german:
            return .system(size: size, weight: weight, design: design)
        }
    }
}

struct AppDynamicFontModifier: ViewModifier {
    let weight: Font.Weight
    let design: Font.Design
    @ScaledMetric private var scaledSize: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        self.weight = weight
        self.design = design
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.font(.appSystem(size: scaledSize, weight: weight, design: design))
    }
}

extension View {
    func appDynamicFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(AppDynamicFontModifier(size: size, weight: weight, design: design))
    }
}
