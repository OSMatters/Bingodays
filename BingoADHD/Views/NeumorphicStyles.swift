import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case sky
    case mint
    case coral
    case violet
    case amber
    case indigo
    case rose
    case lime
    case ocean
    case peach

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .sky:
            return Color(hex: "67B7FF")
        case .mint:
            return Color(hex: "4ECDC4")
        case .coral:
            return Color(hex: "FF8A80")
        case .violet:
            return Color(hex: "8D7CFF")
        case .amber:
            return Color(hex: "FFBE55")
        case .indigo:
            return Color(hex: "5E72E4")
        case .rose:
            return Color(hex: "FF6FAE")
        case .lime:
            return Color(hex: "9CCC65")
        case .ocean:
            return Color(hex: "2BB3C0")
        case .peach:
            return Color(hex: "FF9E80")
        }
    }

    var bingoSurfaceColor: Color {
        switch self {
        case .sky:
            return Color(hex: "8CCBFF")
        case .mint:
            return Color(hex: "75DCD4")
        case .coral:
            return Color(hex: "FFB0A6")
        case .violet:
            return Color(hex: "B4A8FF")
        case .amber:
            return Color(hex: "E7C76A")
        case .indigo:
            return Color(hex: "8795F0")
        case .rose:
            return Color(hex: "FF9BC5")
        case .lime:
            return Color(hex: "B8D98A")
        case .ocean:
            return Color(hex: "6FCFD7")
        case .peach:
            return Color(hex: "FFB59F")
        }
    }

    var bingoSurfaceShadowColor: Color {
        switch self {
        case .sky:
            return Color(hex: "4D99D6")
        case .mint:
            return Color(hex: "2EA89F")
        case .coral:
            return Color(hex: "E27166")
        case .violet:
            return Color(hex: "6C5CE7")
        case .amber:
            return Color(hex: "C9A642")
        case .indigo:
            return Color(hex: "4356C8")
        case .rose:
            return Color(hex: "D95A94")
        case .lime:
            return Color(hex: "7EAB47")
        case .ocean:
            return Color(hex: "1A8E99")
        case .peach:
            return Color(hex: "E57E62")
        }
    }

    static var current: AppTheme {
        let sharedDefaults = UserDefaults(suiteName: "group.com.bingoday.app")
        let stored = sharedDefaults?.string(forKey: AppSettings.themeKey)
            ?? UserDefaults.standard.string(forKey: AppSettings.themeKey)
        return AppTheme(rawValue: stored ?? "") ?? .sky
    }
}

struct NeumorphicColors {
    static let background = Color(hex: "E0E5EC")
    static let lightShadow = Color.white.opacity(0.8)
    static let darkShadow = Color(hex: "A3B1C6").opacity(0.7)
    static let text = Color(hex: "5A6789")
    static var accent: Color { AppTheme.current.color }
    static let bingoAccent = Color(hex: "FF6B6B")
    static let lineText = Color(hex: "AAB3C2")
    static let pencilStroke = Color(hex: "B8C0CC")
    static let bingoGold = Color(hex: "E7C76A")
    static let bingoGoldDark = Color(hex: "C9A642")
}

struct NeumorphicConvexModifier: ViewModifier {
    var radius: CGFloat
    var isPressed: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(NeumorphicColors.background)
                    .shadow(color: isPressed ? .clear : NeumorphicColors.darkShadow, radius: isPressed ? 0 : 8, x: isPressed ? 0 : 6, y: isPressed ? 0 : 6)
                    .shadow(color: isPressed ? .clear : NeumorphicColors.lightShadow, radius: isPressed ? 0 : 8, x: isPressed ? 0 : -6, y: isPressed ? 0 : -6)
            )
            // Add a subtle inner shadow if pressed, otherwise keep it clean
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(NeumorphicColors.background, lineWidth: 2)
                    .shadow(color: isPressed ? NeumorphicColors.darkShadow : .clear, radius: 4, x: 2, y: 2)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .shadow(color: isPressed ? NeumorphicColors.lightShadow : .clear, radius: 4, x: -2, y: -2)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
            )
    }
}

struct NeumorphicConcaveModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(NeumorphicColors.background)
                    
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(Color.clear, lineWidth: 4)
                        .shadow(color: NeumorphicColors.darkShadow, radius: 4, x: 4, y: 4)
                        .clipShape(RoundedRectangle(cornerRadius: radius))
                    
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(Color.clear, lineWidth: 4)
                        .shadow(color: NeumorphicColors.lightShadow, radius: 4, x: -4, y: -4)
                        .clipShape(RoundedRectangle(cornerRadius: radius))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func neumorphicConvex(radius: CGFloat = 16, isPressed: Bool = false) -> some View {
        self.modifier(NeumorphicConvexModifier(radius: radius, isPressed: isPressed))
    }
    
    func neumorphicConcave(radius: CGFloat = 16) -> some View {
        self.modifier(NeumorphicConcaveModifier(radius: radius))
    }
}
