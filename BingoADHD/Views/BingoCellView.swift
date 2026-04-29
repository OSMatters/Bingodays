import SwiftUI

struct BingoCellView: View {
    private static let longPressDuration = 0.28
    private static let dragThreshold: CGFloat = 20

    let cell: BingoCell
    let currentTime: Date
    let debugIdentifier: String
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat
    let isFirstCell: Bool
    let isInteractive: Bool
    let isDragSource: Bool
    let isDropTarget: Bool
    let emptyHintText: String?
    let onTap: () -> Void
    let onLongPressRelease: () -> Void
    let onDragStart: () -> Void
    let onDragMove: (CGSize) -> Void
    let onDragEnd: (CGSize) -> Void

    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isTouching = false
    @State private var isLongPressRecognized = false
    @State private var didStartDrag = false
    @State private var touchStartDate: Date?
    @State private var cancelledLongPressByMovement = false
    @State private var longPressRecognitionWorkItem: DispatchWorkItem?

    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var boardSurfaceColor: Color { NeumorphicColors.innerSurface }
    private var bingoLineColor: Color { activeTheme.color }
    private var selectedColor: Color { activeTheme.bingoSurfaceShadowColor }
    private var primaryTextColor: Color { NeumorphicColors.text }
    private var cellShadowDark: Color { NeumorphicColors.darkShadow.opacity(0.70) }
    private var cellShadowLight: Color { NeumorphicColors.lightShadow.opacity(0.70) }
    private var isPadLayout: Bool { horizontalSizeClass == .regular }
    private var isTaskHiddenFaceVisible: Bool { cell.isCompleted && cell.isTaskHidden && !cell.isEmpty }

    var body: some View {
        let baseView = ZStack {
            frontFace
                .opacity(isTaskHiddenFaceVisible ? 0 : 1)

            hiddenBackFace
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isTaskHiddenFaceVisible ? 1 : 0)
        }
        .rotation3DEffect(.degrees(isTaskHiddenFaceVisible ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .overlay(alignment: .topTrailing) {
            if comboBadgeVisible {
                comboBadge
                    .padding(8)
                    .offset(x: 2, y: -2)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .scaleEffect(interactionScale)
        .opacity(isDragSource ? 0.18 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cell.isCompleted)
        .animation(.easeInOut(duration: 0.45), value: isTaskHiddenFaceVisible)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.8), value: interactionScale)
        .animation(.easeInOut(duration: 0.18), value: isDragSource)
        .animation(.easeInOut(duration: 0.18), value: isDropTarget)
        .contentShape(RoundedRectangle(cornerRadius: 12))

        if isInteractive {
            baseView
                .highPriorityGesture(primaryTouchGesture)
                .onDisappear {
                    cancelLongPressRecognition()
                    isTouching = false
                    touchStartDate = nil
                    cancelledLongPressByMovement = false
                }
        } else {
            baseView
                .onDisappear {
                    cancelLongPressRecognition()
                    isTouching = false
                    touchStartDate = nil
                    cancelledLongPressByMovement = false
                }
        }
    }

    private var primaryTouchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if touchStartDate == nil {
                    touchStartDate = Date()
                    cancelledLongPressByMovement = false
                    debugGesture("touch began")
                    scheduleLongPressRecognition()
                }

                isTouching = true

                let translation = value.translation
                let movement = hypot(translation.width, translation.height)

                if !isLongPressRecognized {
                    if movement > Self.dragThreshold {
                        cancelledLongPressByMovement = true
                        cancelLongPressRecognition()
                    }
                }

                if isLongPressRecognized && !didStartDrag && !cell.isEmpty && movement > Self.dragThreshold {
                    didStartDrag = true
                    cancelLongPressRecognition()
                    debugGesture("drag started after long press")
                    onDragStart()
                }

                if didStartDrag {
                    onDragMove(translation)
                }
            }
            .onEnded { value in
                defer {
                    cancelLongPressRecognition()
                    isLongPressRecognized = false
                    didStartDrag = false
                    isTouching = false
                    touchStartDate = nil
                    cancelledLongPressByMovement = false
                }

                let translation = value.translation
                let movement = hypot(translation.width, translation.height)
                let elapsed = Date().timeIntervalSince(touchStartDate ?? Date())

                if didStartDrag {
                    debugGesture("drag end")
                    onDragEnd(translation)
                    return
                }

                guard !isLocked else {
                    debugGesture("touch end blocked by lock")
                    return
                }

                if !isLongPressRecognized && !cancelledLongPressByMovement && elapsed >= Self.longPressDuration {
                    recognizeLongPress(source: "touch end fallback")
                }

                if isLongPressRecognized {
                    debugGesture("long press -> release action")
                    onLongPressRelease()
                    return
                }

                guard movement <= 10 else {
                    debugGesture("touch ended without action due to movement")
                    return
                }

                guard !cell.isEmpty else {
                    debugGesture("tap ignored for empty cell")
                    return
                }

                let willComplete = !cell.isCompleted
                if willComplete && isHapticsEnabled {
                    AppHaptics.completion()
                }
                debugGesture("tap -> toggle complete")
                onTap()
            }
    }

    private var interactionScale: CGFloat {
        if didStartDrag {
            return 1.05
        }
        if isLongPressRecognized {
            return 1.03
        }
        return (isTouching && !isLocked) ? 0.98 : 1.0
    }

    private var dynamicFontSize: CGFloat {
        let maxBaseSize: CGFloat = isPadLayout ? 20.0 : 18.0
        let minimumSize: CGFloat = isPadLayout ? 12.0 : 11.0
        let gridScale: CGFloat
        if cellSize < 72 {
            gridScale = 0.78   // 5x5
        } else if cellSize < 90 {
            gridScale = 0.86   // 4x4
        } else {
            gridScale = 1.0    // 3x3
        }
        let baseSize = min(cellSize * 0.19, maxBaseSize) * gridScale
        let textLength = cell.text.trimmingCharacters(in: .whitespacesAndNewlines).count

        let scale: CGFloat
        switch textLength {
        case 0...4:
            scale = 1.0
        case 5...8:
            scale = 0.93
        case 9...12:
            scale = 0.86
        case 13...16:
            scale = 0.79
        case 17...20:
            scale = 0.73
        default:
            scale = 0.67
        }

        return max(baseSize * scale, minimumSize)
    }

    private var comboBadgeVisible: Bool {
        !cell.isEmpty &&
        cell.completionStreakCount > 1 &&
        !isDragSource &&
        !isLocked &&
        !isTaskHiddenFaceVisible
    }

    private var footerSlotHeight: CGFloat {
        min(max(cellSize * 0.2, 20), 28)
    }

    private var frontFace: some View {
        ZStack {
            backgroundSurface

            if !isDragSource {
                if isLocked {
                    lockOverlay
                } else if isInBingoLine {
                    bingoLineContent
                } else if !cell.isEmpty {
                    ZStack(alignment: .bottom) {
                        Text(cell.text)
                            .font(.appSystem(size: dynamicFontSize, weight: .medium))
                            .foregroundColor(cellTextColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                        if let countdownText = taskCountdownText, !cell.isCompleted {
                            Text(countdownText)
                                .font(.appSystem(size: max(dynamicFontSize * 0.42, 9), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.accent.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.88))
                                )
                                .frame(height: footerSlotHeight)
                                .padding(.bottom, 8)
                        }

                        if cell.isCompleted {
                            completionIcon(isLarge: false)
                                .frame(height: footerSlotHeight)
                                .padding(.bottom, 8)
                        }

                        if taskCountdownText == nil && !cell.isCompleted {
                            Color.clear
                                .frame(height: footerSlotHeight)
                                .padding(.bottom, 8)
                        }
                    }
                } else if let emptyHintText, !emptyHintText.isEmpty {
                    Text(emptyHintText)
                        .font(.appSystem(size: max(dynamicFontSize * 0.68, 10), weight: .semibold, design: .rounded))
                        .foregroundColor(primaryTextColor.opacity(0.46))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                }
            }
        }
    }

    private var hiddenBackFace: some View {
        ZStack {
            hiddenBackgroundSurface

            if !isDragSource {
                if isLocked {
                    lockOverlay
                } else {
                    completionIcon(isLarge: true)
                }
            }
        }
    }

    private var comboBadge: some View {
        Text("x\(cell.completionStreakCount)")
            .font(.appSystem(size: max(dynamicFontSize * 0.5, 11), weight: .bold, design: .rounded))
            .foregroundColor(cellTextColor.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .shadow(color: Color.black.opacity(cell.isCompleted ? 0.28 : 0.14), radius: 1.5, x: 0, y: 1)
            .zIndex(10)
            .animation(.easeInOut(duration: 0.22), value: cell.isCompleted)
            .animation(.easeInOut(duration: 0.22), value: isLocked)
    }

    private var bingoLineContent: some View {
        VStack(spacing: 10) {
            Text(cell.text)
                .font(.appSystem(size: dynamicFontSize, weight: .medium))
                .foregroundColor(.white)
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
        if cell.isCompleted {
            return .white
        }
        return isLocked ? primaryTextColor.opacity(0.35) : primaryTextColor
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
            } else if isTouching && !isLocked {
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

    private var hiddenBackgroundSurface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selectedColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
    }

    private func completionIcon(isLarge: Bool) -> some View {
        let size = isLarge
            ? min(max(cellSize * 0.42, 36), 52)
            : (cellSize >= 90 ? 20 : min(max(cellSize * 0.13, 14), 18))

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.96))

            Image(systemName: "checkmark")
                .font(.appSystem(size: size * 0.5, weight: .bold))
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
                .font(.appSystem(size: size * 0.42, weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
        }
        .frame(width: size, height: size)
    }

    private var isGestureDebugEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugTileGestures")
#else
        false
#endif
    }

    private func debugGesture(_ message: String) {
#if DEBUG
        guard isGestureDebugEnabled else { return }
        print("[TileGestureDebug][\(debugIdentifier)] \(message)")
#else
        _ = message
#endif
    }

    private func scheduleLongPressRecognition() {
        cancelLongPressRecognition()

        let workItem = DispatchWorkItem { [isHapticsEnabled] in
            guard isTouching else { return }
            guard !cancelledLongPressByMovement else { return }
            guard !isLongPressRecognized else { return }

            recognizeLongPress(source: "scheduled")
            if isHapticsEnabled {
                AppHaptics.control()
            }
        }

        longPressRecognitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longPressDuration, execute: workItem)
    }

    private func cancelLongPressRecognition() {
        longPressRecognitionWorkItem?.cancel()
        longPressRecognitionWorkItem = nil
    }

    private func recognizeLongPress(source: String) {
        guard !isLongPressRecognized else { return }
        isLongPressRecognized = true
        isTouching = true
        debugGesture("long press recognized (\(source))")
    }
}
