import SwiftUI

struct BingoCellView: View {
    private static let longPressDuration = 0.28
    private static let dragThreshold: CGFloat = 12
    private static let tapThreshold: CGFloat = 10

    let cell: BingoCell
    let currentTime: Date
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat
    let isFirstCell: Bool
    let isInteractive: Bool
    let isDragSource: Bool
    let isDropTarget: Bool
    let onTap: () -> Void
    let onLongPressRelease: () -> Void
    let onDragStart: () -> Void
    let onDragMove: (CGSize) -> Void
    let onDragEnd: (CGSize) -> Void

    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.sky.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isPressed = false
    @State private var isLongPressRecognized = false
    @State private var didStartDrag = false
    @State private var hasActiveTouch = false
    @State private var pendingLongPressWorkItem: DispatchWorkItem?

    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .sky }
    private let boardSurfaceColor = Color(hex: "EBF0F7")
    private var bingoLineColor: Color { activeTheme.bingoSurfaceColor }
    private var selectedColor: Color { activeTheme.bingoSurfaceColor.opacity(0.34) }
    private let primaryTextColor = Color(hex: "373F4B")
    private let cellShadowDark = Color(hex: "CFD4DA").opacity(0.70)
    private let cellShadowLight = Color.white.opacity(0.70)
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        let baseView = ZStack {
            backgroundSurface

            if !isDragSource {
                if isInBingoLine {
                    bingoLineContent
                } else if !cell.isEmpty {
                    VStack(spacing: cell.isCompleted ? 10 : 4) {
                        Text(cell.text)
                            .font(.system(size: dynamicFontSize, weight: .medium))
                            .foregroundColor(cellTextColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)
                            .padding(8)

                        if let countdownText = taskCountdownText, !cell.isCompleted {
                            Text(countdownText)
                                .font(.system(size: max(dynamicFontSize * 0.42, 9), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.accent.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.88))
                                )
                        }

                        if cell.isCompleted && !isLocked {
                            completionIcon(isLarge: false)
                        }
                    }
                }

                if isLocked {
                    lockOverlay
                }
            }
        }
        .frame(width: cellSize, height: cellSize)
        .scaleEffect(interactionScale)
        .opacity(isDragSource ? 0.18 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cell.isCompleted)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.8), value: interactionScale)
        .animation(.easeInOut(duration: 0.18), value: isDragSource)
        .animation(.easeInOut(duration: 0.18), value: isDropTarget)
        .contentShape(RoundedRectangle(cornerRadius: 12))

        if isInteractive {
            baseView.highPriorityGesture(interactionGesture)
        } else {
            baseView
        }
    }

    private var interactionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isLocked else { return }

                if !hasActiveTouch {
                    hasActiveTouch = true
                    isPressed = true
                    scheduleLongPressRecognition()
                }

                let distance = dragDistance(for: value.translation)
                if isLongPressRecognized && !didStartDrag && !cell.isEmpty && distance > Self.dragThreshold {
                    didStartDrag = true
                    isPressed = false
                    onDragStart()
                }

                if didStartDrag {
                    onDragMove(value.translation)
                }
            }
            .onEnded { value in
                let distance = dragDistance(for: value.translation)
                finishInteraction(distance: distance, translation: value.translation)
            }
    }

    private var interactionScale: CGFloat {
        if didStartDrag {
            return 1.05
        }
        if isLongPressRecognized {
            return 1.03
        }
        return isPressed ? 0.98 : 1.0
    }

    private var dynamicFontSize: CGFloat {
        let maxBaseSize: CGFloat = isPadLayout ? 20.0 : 18.0
        let minimumSize: CGFloat = isPadLayout ? 12.0 : 11.0
        let baseSize = min(cellSize * 0.19, maxBaseSize)
        let textLength = cell.text.count
        if textLength > 6 {
            return max(baseSize * 0.88, minimumSize)
        }
        return baseSize
    }

    private var bingoLineContent: some View {
        VStack(spacing: 10) {
            Text(cell.text)
                .font(.system(size: dynamicFontSize, weight: .medium))
                .foregroundColor(.white.opacity(0.96))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)

            if !isLocked {
                completionIcon(isLarge: false)
            }
        }
    }

    private var cellTextColor: Color {
        isLocked ? primaryTextColor.opacity(0.35) : primaryTextColor
    }

    private var taskCountdownText: String? {
        guard let deadline = cell.countdownEndsAt else { return nil }
        let remainingSeconds = max(Int(deadline.timeIntervalSince(currentTime)), 0)
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var backgroundSurface: some View {
        let baseShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return Group {
            if isDragSource || isDropTarget {
                Color.clear.neumorphicConcave(radius: 12)
            } else if isInBingoLine {
                baseShape
                    .fill(bingoLineColor)
                    .shadow(color: cellShadowDark, radius: 12, x: 6, y: 6)
                    .shadow(color: cellShadowLight, radius: 12, x: -6, y: -6)
            } else if cell.isCompleted {
                baseShape
                    .fill(selectedColor)
            } else if isPressed {
                baseShape
                    .fill(boardSurfaceColor)
                    .shadow(color: cellShadowDark.opacity(0.95), radius: 8, x: 4, y: 4)
                    .shadow(color: cellShadowLight.opacity(0.95), radius: 8, x: -4, y: -4)
            } else {
                baseShape
                    .fill(boardSurfaceColor)
                    .shadow(color: cellShadowDark, radius: 12, x: 6, y: 6)
                    .shadow(color: cellShadowLight, radius: 12, x: -6, y: -6)
            }
        }
        .overlay {
            if isLocked && !isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(boardSurfaceColor.opacity(0.62))
            }

            if isDropTarget {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        bingoLineColor.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 6])
                    )
                    .padding(4)
            }

            if isDragSource {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        primaryTextColor.opacity(0.2),
                        style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                    )
                    .padding(4)
            }
        }
    }

    private func completionIcon(isLarge: Bool) -> some View {
        let size = isLarge
            ? min(max(cellSize * 0.42, 36), 52)
            : 20.0

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.96))

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(activeTheme.bingoSurfaceColor)
        }
        .frame(width: size, height: size)
    }

    private var lockOverlay: some View {
        let size = min(max(cellSize * 0.22, 20), 28)

        return ZStack {
            Circle()
                .fill(boardSurfaceColor)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.25), radius: 4, x: 2, y: 2)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.85), radius: 4, x: -2, y: -2)

            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
        }
        .frame(width: size, height: size)
    }

    private func dragDistance(for translation: CGSize) -> CGFloat {
        hypot(translation.width, translation.height)
    }

    private func scheduleLongPressRecognition() {
        cancelPendingLongPress()

        let workItem = DispatchWorkItem {
            guard hasActiveTouch else { return }
            isLongPressRecognized = true
            isPressed = false

            if isHapticsEnabled {
                AppHaptics.control()
            }
        }

        pendingLongPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.longPressDuration,
            execute: workItem
        )
    }

    private func finishInteraction(distance: CGFloat, translation: CGSize) {
        cancelPendingLongPress()

        defer {
            hasActiveTouch = false
            isPressed = false
            isLongPressRecognized = false
            didStartDrag = false
        }

        guard !isLocked else { return }

        if didStartDrag {
            onDragEnd(translation)
            return
        }

        if isLongPressRecognized {
            onLongPressRelease()
            return
        }

        guard distance <= Self.tapThreshold else { return }
        guard !cell.isEmpty else { return }

        let willComplete = !cell.isCompleted
        if willComplete && isHapticsEnabled {
            AppHaptics.completion()
        }
        onTap()
    }

    private func cancelPendingLongPress() {
        pendingLongPressWorkItem?.cancel()
        pendingLongPressWorkItem = nil
    }
}
