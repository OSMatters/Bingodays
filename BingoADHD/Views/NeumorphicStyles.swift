import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case concise
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

    static var selectableCases: [AppTheme] {
        // Keep the picker in the same order as the product color spec.
        [.concise, .violet, .sky, .indigo, .lime, .coral, .amber, .mint]
    }

    var color: Color {
        switch self {
        case .concise:
            return Color(hex: "DFAE81")
        case .sky:
            return Color(hex: "82C0F0")
        case .mint:
            return Color(hex: "65CFB0")
        case .coral:
            return Color(hex: "ED9D9E")
        case .violet:
            return Color(hex: "9993CF")
        case .amber:
            return Color(hex: "FFA52F")
        case .indigo:
            return Color(hex: "6D96E8")
        case .rose:
            // Legacy persisted value. New users see the coral palette instead.
            return Color(hex: "ED9D9E")
        case .lime:
            return Color(hex: "4F8F4F")
        case .ocean:
            // Legacy persisted value kept visually close to mint.
            return Color(hex: "65CFB0")
        case .peach:
            // Legacy persisted value kept visually close to coral.
            return Color(hex: "ED9D9E")
        }
    }

    var bingoSurfaceColor: Color {
        switch self {
        case .concise:
            return Color(hex: "EFE0D1")
        case .sky:
            return Color(hex: "CFECFF")
        case .mint:
            return Color(hex: "D1F7EC")
        case .coral:
            return Color(hex: "FEE4E4")
        case .violet:
            return Color(hex: "E5E3F7")
        case .amber:
            return Color(hex: "FFDCB6")
        case .indigo:
            return Color(hex: "CADCFF")
        case .rose:
            return Color(hex: "FEE4E4")
        case .lime:
            return Color(hex: "DFF1DF")
        case .ocean:
            return Color(hex: "D1F7EC")
        case .peach:
            return Color(hex: "FEE4E4")
        }
    }

    /// The quiet outline used by an unfinished cell. Keeping this separate from
    /// the completed surface lets each theme follow the color spec exactly.
    var bingoCellOutlineColor: Color {
        switch self {
        case .concise:
            return Color(hex: "EFE0D1")
        case .sky:
            return Color(hex: "CFECFF")
        case .mint:
            return Color(hex: "D1F7EC")
        case .coral:
            return Color(hex: "FEE4E4")
        case .violet:
            return Color(hex: "E5E3F7")
        case .amber:
            return Color(hex: "FFDCB6")
        case .indigo:
            return Color(hex: "CADCFF")
        case .rose:
            return Color(hex: "FEE4E4")
        case .lime:
            return Color(hex: "DFF1DF")
        case .ocean:
            return Color(hex: "D1F7EC")
        case .peach:
            return Color(hex: "FEE4E4")
        }
    }

    var bingoSurfaceShadowColor: Color {
        switch self {
        case .concise:
            return Color(hex: "C1A184")
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
        return AppTheme(rawValue: stored ?? "") ?? .concise
    }

    var backgroundColor: Color {
        switch self {
        case .concise:
            return Color(hex: "F4EFE9")
        default:
            return Color(hex: "E0E5EC")
        }
    }

    var innerSurfaceColor: Color {
        switch self {
        case .concise:
            return Color(hex: "F2E9DF")
        default:
            return Color(hex: "E0E5EC")
        }
    }

    var lightShadowColor: Color {
        switch self {
        case .concise:
            return Color(hex: "FDF7F1")
        default:
            return Color.white.opacity(0.8)
        }
    }

    var darkShadowColor: Color {
        switch self {
        case .concise:
            return Color(hex: "C1A184").opacity(0.55)
        default:
            return Color(hex: "A3B1C6").opacity(0.7)
        }
    }

    var textColor: Color {
        // Keep copy in the default palette, including reward editor text fields.
        // Theme selection changes decorative colors without recoloring shared text.
        Color(hex: "4B463F")
    }

    var bingoAccentColor: Color {
        switch self {
        case .concise:
            return Color(hex: "C39060")
        default:
            return Color(hex: "FF6B6B")
        }
    }

    var lineTextColor: Color {
        switch self {
        case .concise:
            return Color(hex: "C1A184")
        default:
            return Color(hex: "AAB3C2")
        }
    }

    var pencilStrokeColor: Color {
        switch self {
        case .concise:
            return Color(hex: "C1A184")
        default:
            return Color(hex: "B8C0CC")
        }
    }
}

struct NeumorphicColors {
    static var background: Color { AppTheme.current.backgroundColor }
    static var innerSurface: Color { AppTheme.current.innerSurfaceColor }
    static var lightShadow: Color { AppTheme.current.lightShadowColor }
    static var darkShadow: Color { AppTheme.current.darkShadowColor }
    static var text: Color { AppTheme.current.textColor }
    static var accent: Color { AppTheme.current.color }
    // Modal actions keep the default palette when the board skin changes.
    static var modalAccent: Color { AppTheme.concise.color }
    static var bingoAccent: Color { AppTheme.current.bingoAccentColor }
    static var lineText: Color { AppTheme.current.lineTextColor }
    static var pencilStroke: Color { AppTheme.current.pencilStrokeColor }
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
                        .fill(NeumorphicColors.innerSurface)
                    
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
    @ViewBuilder
    func homeActionGlass(isDarkBackground: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(), in: Capsule())
                .environment(\.colorScheme, isDarkBackground ? .dark : .light)
        } else {
            self.background {
                Capsule()
                    .fill(isDarkBackground ? Color.black.opacity(0.58) : Color.white.opacity(0.72))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(isDarkBackground ? 0.30 : 0.75))
                    }
            }
        }
    }

    func neumorphicConvex(radius: CGFloat = 16, isPressed: Bool = false) -> some View {
        self.modifier(NeumorphicConvexModifier(radius: radius, isPressed: isPressed))
    }
    
    func neumorphicConcave(radius: CGFloat = 16) -> some View {
        self.modifier(NeumorphicConcaveModifier(radius: radius))
    }

    @ViewBuilder
    func appLiquidGlass<S: Shape>(
        in shape: S,
        interactive: Bool = true,
        tint: Color? = nil,
        fallbackWhiteOpacity: Double = 0.74
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(
                    .regular
                        .tint(tint)
                        .interactive(interactive),
                    in: shape
                )
        } else {
            self.background {
                ZStack {
                    shape
                        .fill(.ultraThinMaterial)

                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(fallbackWhiteOpacity),
                                    Color.white.opacity(fallbackWhiteOpacity * 0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let tint {
                        shape
                            .fill(tint.opacity(0.26))
                    }

                    shape
                        .stroke(Color.white.opacity(0.94), lineWidth: 1)

                    shape
                        .stroke(Color.white.opacity(0.24), lineWidth: 3)
                        .blur(radius: 2.4)
                        .offset(y: -1)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func appGlassEffectContainer(spacing: CGFloat = 20) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

struct LiquidGlassIconBadge: View {
    var systemName: String? = nil
    var imageName: String? = nil
    var size: CGFloat
    var iconSize: CGFloat
    var foregroundColor: Color = NeumorphicColors.text
    var baseFill: Color? = nil
    var glassTint: Color? = nil
    var usesLiquidGlass: Bool = true
    var glassInteractive: Bool = true

    private var badgeContent: some View {
        ZStack {
            if let imageName {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(foregroundColor)
            }
        }
        .frame(width: size, height: size)
    }

    var body: some View {
        Group {
            if usesLiquidGlass {
                badgeContent
                    .background {
                        if let baseFill {
                            Circle()
                                .fill(baseFill)
                        }
                    }
                    .appLiquidGlass(in: Circle(), interactive: glassInteractive, tint: glassTint)
            } else {
                badgeContent
                    .background {
                        Circle()
                            .fill(baseFill ?? Color.white.opacity(0.74))
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    }
            }
        }
        .contentShape(Circle())
    }
}
