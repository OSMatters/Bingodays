import SwiftUI

enum TaskCountdownDisplayRules {
    static let refreshInterval: TimeInterval = 1

    static func text(remainingSeconds: Int) -> String {
        let safeSeconds = max(remainingSeconds, 0)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let seconds = safeSeconds % 60
        return "\(padded(hours)):\(padded(minutes)):\(padded(seconds))"
    }

    static func remainingSeconds(until deadline: Date, at referenceDate: Date) -> Int {
        max(Int(ceil(deadline.timeIntervalSince(referenceDate))), 0)
    }

    private static func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

struct BingoCellView: View {
    private static let longPressDuration = 0.28
    private static let dragThreshold: CGFloat = 20
    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = Calendar.current
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    let cell: BingoCell
    let currentTime: Date
    let isScheduledInactive: Bool
    let scheduleStatusText: String?
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTouching = false
    @State private var isLongPressRecognized = false
    @State private var didStartDrag = false
    @State private var touchStartDate: Date?
    @State private var cancelledLongPressByMovement = false
    @State private var longPressRecognitionWorkItem: DispatchWorkItem?
    @State private var completionPulseScale: CGFloat = 1
    @State private var completionPulseGeneration = 0
    @State private var completionPulseWorkItem: DispatchWorkItem?

    private let boardSurfaceColor = Color(hex: "F4F4F4")
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var bingoLineColor: Color { activeTheme.color }
    private var selectedColor: Color { reducedSaturationColor(from: activeTheme.color, by: 0.30) }
    private let primaryTextColor = Color(hex: "291E0A")
    private let cellCornerRadius: CGFloat = 12
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
        .overlay(alignment: .top) {
            if comboBadgeVisible {
                comboBadge
                    .padding(.top, 4)
            }
        }
        .frame(width: cellSize, height: cellSize)
        // Keep the press response and the completion pulse independent.  The completion
        // pulse is driven directly from the successful tap below, so it is always applied
        // to this exact cell before the model publishes its new completion state.
        .scaleEffect(touchScale)
        .scaleEffect(completionPulseScale)
        .opacity(isDragSource ? 0.18 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cell.isCompleted)
        .animation(.easeInOut(duration: 0.45), value: isTaskHiddenFaceVisible)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.8), value: touchScale)
        .animation(.easeInOut(duration: 0.18), value: isDragSource)
        .animation(.easeInOut(duration: 0.18), value: isDropTarget)
        .contentShape(RoundedRectangle(cornerRadius: cellCornerRadius))
        .onChange(of: cell.isCompleted) { _, isCompleted in
            // Undoing a completion must not leave a transient scale on the cell.
            if !isCompleted {
                cancelCompletionPulse()
            }
        }

        if isInteractive {
            baseView
                .highPriorityGesture(primaryTouchGesture)
                .onDisappear {
                    cancelLongPressRecognition()
                    cancelCompletionPulse()
                    isTouching = false
                    touchStartDate = nil
                    cancelledLongPressByMovement = false
                }
        } else {
            baseView
                .onDisappear {
                    cancelLongPressRecognition()
                    cancelCompletionPulse()
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
                    if isHapticsEnabled {
                        AppHaptics.prepareForInteraction()
                    }
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

                guard !isScheduledInactive else {
                    debugGesture("tap ignored for inactive visibility window")
                    return
                }

                let willComplete = !cell.isCompleted
                if willComplete {
                    // Start before mutating the board model: waiting for an `onChange` here
                    // is visibly late once the grid has been re-rendered.
                    runCompletionPulse()
                }
                debugGesture("tap -> toggle complete")
                onTap()
            }
    }

    private var touchScale: CGFloat {
        let scale: CGFloat
        if didStartDrag {
            scale = 1.05
        } else if isLongPressRecognized {
            scale = 1.03
        } else {
            scale = (isTouching && !isLocked) ? 0.98 : 1.0
        }
        return scale
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
        !isScheduledInactive &&
        !isTaskHiddenFaceVisible
    }

    private var footerSlotHeight: CGFloat {
        min(max(cellSize * 0.2, 20), 28)
    }

    private var auxiliaryStatusText: String? {
        scheduleStatusText ?? scheduleWindowText
    }

    private var hasFrontFooter: Bool {
        !cell.isCompleted && (
            displayCountdownText(at: currentTime) != nil ||
            auxiliaryStatusText != nil
        )
    }

    private var taskTitleFontSize: CGFloat {
        guard cellSize < 72, hasFrontFooter else { return dynamicFontSize }
        return max(dynamicFontSize * 0.86, 9.5)
    }

    private var taskTitleLineLimit: Int {
        cellSize < 72 && hasFrontFooter ? 2 : 3
    }

    private var frontFace: some View {
        ZStack {
            backgroundSurface

            if !isDragSource {
                if isLocked {
                    lockOverlay
                } else {
                    if cell.isCompleted {
                        completionArtwork
                    }

                    if !cell.isEmpty {
                        VStack(spacing: 0) {
                            Text(cell.text)
                                .font(.appSystem(size: taskTitleFontSize, weight: .medium))
                                .foregroundColor(cellTextColor)
                                .multilineTextAlignment(.center)
                                .lineLimit(taskTitleLineLimit)
                                .minimumScaleFactor(0.5)
                                .padding(.horizontal, cellSize < 72 ? 5 : 10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                            if hasFrontFooter {
                                frontFooter
                                    .frame(height: footerSlotHeight)
                            }
                        }
                        .padding(.top, cellSize < 72 ? 5 : 8)
                        .padding(.bottom, cellSize < 72 ? 4 : 8)
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
    }

    @ViewBuilder
    private var frontFooter: some View {
        if displayCountdownText(at: currentTime) != nil {
            TimelineView(
                .periodic(
                    from: .now,
                    by: TaskCountdownDisplayRules.refreshInterval
                )
            ) { context in
                Text(displayCountdownText(at: context.date) ?? "00:00:00")
                    .font(.appSystem(size: max(dynamicFontSize * 0.42, 9), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(NeumorphicColors.accent.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 4)
            }
        } else if let auxiliaryStatusText {
            Text(auxiliaryStatusText)
                .font(.appSystem(size: max(dynamicFontSize * 0.34, 8), weight: .semibold, design: .rounded))
                .foregroundColor(primaryTextColor.opacity(isScheduledInactive ? 0.45 : 0.58))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
    }

    private var hiddenBackFace: some View {
        ZStack {
            hiddenBackgroundSurface

            if !isDragSource {
                if isLocked {
                    lockOverlay
                } else {
                    completionArtwork
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

    private var cellTextColor: Color {
        if isInBingoLine {
            return .white
        }
        if cell.isCompleted {
            return primaryTextColor
        }
        if isScheduledInactive {
            return primaryTextColor.opacity(0.38)
        }
        return isLocked ? primaryTextColor.opacity(0.35) : primaryTextColor
    }

    private var scheduleWindowText: String? {
        guard cell.startVisibleAt != nil || cell.endVisibleAt != nil else { return nil }

        if let start = cell.occurrenceStartVisibleAt(on: currentTime) {
            return Self.scheduleDateFormatter.string(from: start)
        }
        if let end = cell.occurrenceEndVisibleAt(on: currentTime) {
            return Self.scheduleDateFormatter.string(from: end)
        }
        return nil
    }

    private func taskCountdownText(at referenceDate: Date) -> String? {
        guard cell.canUseTaskCountdown else { return nil }
        if (cell.countdownPausedRemainingSeconds ?? 0) > 0 {
            return L10n.tr("Paused", zhHans: "已暂停", zhHant: "已暫停", ja: "一時停止中")
        }
        guard let deadline = cell.countdownEndsAt else { return nil }
        let remainingSeconds = TaskCountdownDisplayRules.remainingSeconds(
            until: deadline,
            at: referenceDate
        )
        return countdownUnitText(from: remainingSeconds)
    }

    private func windowCountdownText(at referenceDate: Date) -> String? {
        guard !isScheduledInactive,
              let start = cell.occurrenceStartVisibleAt(on: referenceDate),
              let end = cell.occurrenceEndVisibleAt(on: referenceDate),
              referenceDate >= start,
              referenceDate < end else {
            return nil
        }
        let remainingSeconds = TaskCountdownDisplayRules.remainingSeconds(
            until: end,
            at: referenceDate
        )
        return countdownUnitText(from: remainingSeconds)
    }

    private func displayCountdownText(at referenceDate: Date) -> String? {
        windowCountdownText(at: referenceDate) ?? taskCountdownText(at: referenceDate)
    }

    private func countdownUnitText(from remainingSeconds: Int) -> String {
        TaskCountdownDisplayRules.text(remainingSeconds: remainingSeconds)
    }

    private var backgroundSurface: some View {
        let baseShape = RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)

        return Group {
            if isDragSource || isDropTarget {
                baseShape
                    .fill(boardSurfaceColor)
                    .opacity(0.78)
            } else if isInBingoLine {
                baseShape
                    .fill(bingoLineColor)
            } else if cell.isCompleted {
                baseShape
                    .fill(selectedColor)
            } else if isTouching && !isLocked {
                baseShape
                    .fill(boardSurfaceColor)
                    .opacity(0.92)
            } else {
                baseShape
                    .fill(boardSurfaceColor)
            }
        }
        .overlay {
            if isLocked && !isInBingoLine {
                RoundedRectangle(cornerRadius: cellCornerRadius)
                    .fill(boardSurfaceColor.opacity(0.62))
            }

            if isScheduledInactive && !isInBingoLine {
                RoundedRectangle(cornerRadius: cellCornerRadius)
                    .fill(Color.white.opacity(0.2))
            }

            if isDropTarget {
                RoundedRectangle(cornerRadius: cellCornerRadius)
                    .stroke(
                        bingoLineColor.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 6])
                    )
                    .padding(4)
            }

            if isDragSource {
                RoundedRectangle(cornerRadius: cellCornerRadius)
                    .stroke(
                        primaryTextColor.opacity(0.2),
                        style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                    )
                    .padding(4)
            }
        }
    }

    private var hiddenBackgroundSurface: some View {
        RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
            .fill(isInBingoLine ? bingoLineColor : selectedColor)
    }

    private var completionArtwork: some View {
        Image(isInBingoLine ? "CellBingo" : "CellComplete")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: cellSize * 0.76, height: cellSize * 0.76)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
            .allowsHitTesting(false)
    }

    private var lockOverlay: some View {
        let size = min(max(cellSize * 0.22, 20), 28)

        return ZStack {
            Circle()
                .fill(boardSurfaceColor)

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

    private func reducedSaturationColor(from color: Color, by amount: CGFloat) -> Color {
        let ui = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard ui.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }

        return Color(
            hue: Double(hue),
            saturation: Double(max(0, saturation - amount)),
            brightness: Double(brightness),
            opacity: Double(alpha)
        )
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

    private func runCompletionPulse() {
        cancelCompletionPulse()
        guard !reduceMotion else {
            completionPulseScale = 1
            return
        }

        completionPulseGeneration &+= 1
        let generation = completionPulseGeneration
        // The 70% shrink is intentionally immediate. This makes the following spring read as
        // a quick rebound instead of a nearly imperceptible change during the grid refresh.
        var shrinkTransaction = Transaction(animation: nil)
        shrinkTransaction.disablesAnimations = true
        withTransaction(shrinkTransaction) {
            completionPulseScale = 0.70
        }

        let workItem = DispatchWorkItem {
            guard completionPulseGeneration == generation else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
                completionPulseScale = 1
            }
        }
        completionPulseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
    }

    private func cancelCompletionPulse() {
        completionPulseWorkItem?.cancel()
        completionPulseWorkItem = nil
        completionPulseGeneration &+= 1
        completionPulseScale = 1
    }

    private func recognizeLongPress(source: String) {
        guard !isLongPressRecognized else { return }
        isLongPressRecognized = true
        isTouching = true
        debugGesture("long press recognized (\(source))")
    }
}
