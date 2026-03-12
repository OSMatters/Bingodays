import SwiftUI

struct BingoCellView: View {
    let cell: BingoCell
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat
    let isFirstCell: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.sky.rawValue
    @State private var isPressed = false
    @State private var didTriggerLongPress = false
    @State private var showCompletionGlow = false
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .sky }
    private var bingoSurfaceColor: Color { activeTheme.bingoSurfaceColor }
    private var bingoSurfaceShadowColor: Color { activeTheme.bingoSurfaceShadowColor }

    var body: some View {
        ZStack {
            backgroundSurface

            if isInBingoLine {
                bingoLineContent
            } else if !cell.isEmpty {
                VStack(spacing: 2) {
                    // Task text
                    Text(cell.text)
                        .font(.system(size: dynamicFontSize, weight: .medium))
                        .foregroundColor(cellTextColor)
                        .scaleEffect(cell.isCompleted ? 1.14 : 1.0)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(8)
                        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: cell.isCompleted)

                    // Completion indicator
                    if cell.isCompleted && !isLocked {
                        completionIcon(isLarge: false)
                    }
                }
            }

            if isLocked {
                lockOverlay
            }
        }
        .frame(width: cellSize, height: cellSize)
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cell.isCompleted)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .onChange(of: cell.isCompleted) { _, isCompleted in
            guard isCompleted else {
                showCompletionGlow = false
                return
            }

            withAnimation(.easeOut(duration: 0.1)) {
                showCompletionGlow = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.42)) {
                    showCompletionGlow = false
                }
            }
        }
        .onTapGesture {
            if isLocked {
                return
            }
            if didTriggerLongPress {
                didTriggerLongPress = false
                return
            }
            let willComplete = !cell.isCompleted
            isPressed = true
            if willComplete && isHapticsEnabled {
                AppHaptics.completion()
            }
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isPressed = false
            }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            if isLocked {
                return
            }
            didTriggerLongPress = true
            if isHapticsEnabled {
                AppHaptics.control()
            }
            onLongPress()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                didTriggerLongPress = false
            }
        }
    }

    private var dynamicFontSize: CGFloat {
        let baseSize = min(cellSize * 0.22, 16.0)
        let textLength = cell.text.count
        if textLength > 6 {
            return max(baseSize * 0.8, 9)
        }
        return baseSize
    }

    private var bingoLineContent: some View {
        VStack(spacing: 4) {
            Text(cell.text)
                .font(.system(size: dynamicFontSize, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            if !isLocked {
                completionIcon(isLarge: false, usesGoldSurface: true)
            }
        }
    }

    private var cellTextColor: Color {
        isLocked ? NeumorphicColors.text.opacity(0.35) : NeumorphicColors.text
    }

    private var backgroundSurface: some View {
        Group {
            if isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(bingoSurfaceColor)
                    .shadow(color: bingoSurfaceShadowColor.opacity(0.28), radius: 7, x: 4, y: 4)
                    .shadow(color: Color.white.opacity(0.42), radius: 7, x: -4, y: -4)
            } else if cell.isCompleted || isPressed {
                Color.clear
                    .neumorphicConcave(radius: 12)
            } else {
                Color.clear
                    .neumorphicConvex(radius: 12, isPressed: isPressed)
            }
        }
        .overlay {
            if isLocked && !isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(NeumorphicColors.background.opacity(0.62))
            }
        }
        .shadow(
            color: showCompletionGlow ? bingoSurfaceColor.opacity(0.62) : .clear,
            radius: showCompletionGlow ? 16 : 0,
            x: 0,
            y: 0
        )
        .shadow(
            color: showCompletionGlow ? bingoSurfaceShadowColor.opacity(0.28) : .clear,
            radius: showCompletionGlow ? 26 : 0,
            x: 0,
            y: 0
        )
    }

    private func completionIcon(isLarge: Bool, usesGoldSurface: Bool = false) -> some View {
        let size = isLarge
            ? min(max(cellSize * 0.42, 34), 52)
            : min(max(cellSize * 0.16, 16), 22)

        return ZStack {
            Circle()
                .fill(isLarge || usesGoldSurface ? bingoSurfaceColor : NeumorphicColors.background)
                .shadow(
                    color: ((isLarge || usesGoldSurface) ? bingoSurfaceShadowColor : NeumorphicColors.darkShadow).opacity(0.3),
                    radius: isLarge ? 6 : 4,
                    x: isLarge ? 4 : 3,
                    y: isLarge ? 4 : 3
                )
                .shadow(
                    color: ((isLarge || usesGoldSurface) ? Color.white : NeumorphicColors.lightShadow).opacity(0.85),
                    radius: isLarge ? 6 : 4,
                    x: isLarge ? -4 : -3,
                    y: isLarge ? -4 : -3
                )

            Image(systemName: "checkmark")
                .font(.system(size: size * (isLarge ? 0.42 : 0.42), weight: .bold))
                .foregroundColor((isLarge || usesGoldSurface) ? .white : activeTheme.color)
        }
        .frame(width: size, height: size)
        .padding(.top, isLarge ? 0 : 6)
    }

    private var lockOverlay: some View {
        let size = min(max(cellSize * 0.22, 20), 28)

        return ZStack {
            Circle()
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.25), radius: 4, x: 2, y: 2)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.85), radius: 4, x: -2, y: -2)

            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
        }
        .frame(width: size, height: size)
    }
}
