import SwiftUI
import Foundation
import UIKit
import CoreMotion
import AudioToolbox

struct BingoDiaryScreen: View {
    private struct DiarySnapshot {
        var completedTaskStats: [BingoDiaryTaskCount]
        var timeoutTaskStats: [BingoDiaryTaskCount]
        var totalCompletedTasks: Int
        var totalExpiredTasks: Int

        static let empty = DiarySnapshot(
            completedTaskStats: [],
            timeoutTaskStats: [],
            totalCompletedTasks: 0,
            totalExpiredTasks: 0
        )
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var gravityMonitor = BingoDiaryGravityMonitor()
    @State private var isStatsListPresented = false
    @State private var selectedTaskDetail: BingoDiaryTaskCount?
    @State private var snapshot: DiarySnapshot = .empty
    @State private var isLoadingSnapshot = true
    @State private var statsSectionHeight: CGFloat = 0
    @State private var isBubbleCloudInteracting = false

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var diaryTitle: String {
        L10n.tr("Bingo Dairy", zhHans: "Bingo 日记", zhHant: "Bingo 日記")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let contentWidth = geometry.size.width
                let statsToBubbleSpacing = scaled(10, pad: 10)
                let resolvedStatsHeight = max(
                    statsSectionHeight,
                    scaled(132, pad: 150)
                )
                let bubbleViewportHeight = max(
                    scaled(300, pad: 360),
                    geometry.size.height
                    - resolvedStatsHeight
                    - statsToBubbleSpacing  // space between stats and bubble area
                    - scaled(16, pad: 24)   // top content padding
                    - scaled(36, pad: 44)   // bottom content padding
                    - geometry.safeAreaInsets.top
                    - scaled(56, pad: 68)   // header + safe margin
                )
                let bubbleLayout = BingoDiaryBubbleLayout.layout(
                    taskCounts: snapshot.completedTaskStats,
                    width: contentWidth,
                    viewportHeight: bubbleViewportHeight,
                    maximumBubbleCount: 80
                )

                ZStack(alignment: .top) {
                    NeumorphicColors.background
                        .ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: statsToBubbleSpacing) {
                            statsSummarySection
                                .padding(.horizontal, scaled(20, pad: 28))
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(
                                                key: BingoDiaryStatsHeightPreferenceKey.self,
                                                value: proxy.size.height
                                            )
                                    }
                                )

                            if isLoadingSnapshot {
                                ProgressView()
                                    .tint(NeumorphicColors.accent)
                                    .frame(maxWidth: .infinity, minHeight: bubbleViewportHeight)
                                    .padding(.horizontal, scaled(20, pad: 28))
                            } else if bubbleLayout.bubbles.isEmpty {
                                emptyDiaryState
                                    .padding(.horizontal, scaled(20, pad: 28))
                            } else {
                                let horizontalPanInset = scaled(22, pad: 28)
                                let alwaysScrollableCanvasWidth = max(
                                    bubbleLayout.width,
                                    contentWidth + horizontalPanInset * 2
                                )

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 0) {
                                        BingoDiaryBubbleCloud(
                                            bubbles: bubbleLayout.bubbles,
                                            canvasWidth: bubbleLayout.width,
                                            canvasHeight: bubbleLayout.height,
                                            globalMotionOffset: gravityMonitor.offset,
                                            isInteractionPaused: isBubbleCloudInteracting,
                                            onBubbleTap: { bubble in
                                                selectedTaskDetail = snapshot.completedTaskStats.first(where: { $0.id == bubble.id })
                                                    ?? BingoDiaryTaskCount(task: bubble.task, count: bubble.count, firstCompletedAt: nil)
                                            }
                                        )
                                        .padding(.horizontal, max((alwaysScrollableCanvasWidth - bubbleLayout.width) / 2, 0))
                                    }
                                    .frame(width: alwaysScrollableCanvasWidth, alignment: .leading)
                                }
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { _ in
                                            if !isBubbleCloudInteracting {
                                                isBubbleCloudInteracting = true
                                            }
                                        }
                                        .onEnded { _ in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                isBubbleCloudInteracting = false
                                            }
                                        }
                                )
                                .frame(height: bubbleLayout.height)
                                .clipped()
                            }
                        }
                        .padding(.top, scaled(16, pad: 24))
                        .padding(.bottom, scaled(36, pad: 44))
                    }
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                headerBar
                    .background(NeumorphicColors.background.opacity(0.96))
            }
            .sheet(isPresented: $isStatsListPresented) {
                BingoDiaryStatsListSheet(
                    title: diaryTitle,
                    completedStats: snapshot.completedTaskStats,
                    timeoutStats: snapshot.timeoutTaskStats
                )
            }
            .onPreferenceChange(BingoDiaryStatsHeightPreferenceKey.self) { newHeight in
                guard newHeight > 0, abs(newHeight - statsSectionHeight) > 0.5 else { return }
                statsSectionHeight = newHeight
            }
            .onAppear {
                gravityMonitor.start()
                // Defer heavier diary data aggregation until transition finishes,
                // so entering this screen feels immediate.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    loadSnapshot()
                }
            }
            .onDisappear {
                gravityMonitor.stop()
            }
            .navigationDestination(item: $selectedTaskDetail) { item in
                BingoDiaryTaskDetailView(task: item.task)
            }
        }
    }

    private var headerBar: some View {
        ZStack {
            Text(diaryTitle)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                        .foregroundColor(Color(hex: "2B1A0D"))
                        .frame(width: scaled(40, pad: 44), height: scaled(40, pad: 44))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    isStatsListPresented = true
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.appSystem(size: scaled(19, pad: 22), weight: .semibold))
                        .foregroundColor(Color(hex: "2B1A0D"))
                        .frame(width: scaled(40, pad: 44), height: scaled(40, pad: 44))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, scaled(12, pad: 20))
        .padding(.top, scaled(6, pad: 10))
        .padding(.bottom, scaled(4, pad: 8))
    }

    private var statsSummarySection: some View {
        HStack(spacing: scaled(14, pad: 18)) {
            diarySummaryCard(
                value: snapshot.totalCompletedTasks,
                title: L10n.tr("Tasks completed", zhHans: "已完成任务", zhHant: "已完成任務")
            )

            diarySummaryCard(
                value: snapshot.totalExpiredTasks,
                title: L10n.tr("Expired tasks", zhHans: "超时任务", zhHant: "超時任務")
            )
        }
    }

    private func loadSnapshot() {
        isLoadingSnapshot = true
        DispatchQueue.global(qos: .userInitiated).async {
            let completed = BingoDiaryStore.allTimeCompletedTaskStats().map {
                BingoDiaryTaskCount(task: $0.task, count: $0.count, firstCompletedAt: $0.firstCompletedAt)
            }
            let timeout = BingoTimeoutStore.allTimeTimeoutTaskCounts().map {
                BingoDiaryTaskCount(task: $0.task, count: $0.count, firstCompletedAt: nil)
            }
            let snapshot = DiarySnapshot(
                completedTaskStats: completed,
                timeoutTaskStats: timeout,
                totalCompletedTasks: BingoDiaryStore.totalCompletedTasks(),
                totalExpiredTasks: BingoTimeoutStore.totalTimedOutTasks()
            )
            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.isLoadingSnapshot = false
            }
        }
    }

    private func diarySummaryCard(value: Int, title: String) -> some View {
        VStack(spacing: scaled(6, pad: 8)) {
            Text("\(value)")
                .font(.appSystem(size: scaled(54, pad: 68), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(title)
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "8A8179"))
        }
        .frame(maxWidth: .infinity)
        .frame(height: scaled(132, pad: 150))
        .background(
            RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                        .stroke(Color.white.opacity(0.95), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 6)
        )
    }

    private var emptyDiaryState: some View {
        VStack(alignment: .center, spacing: scaled(10, pad: 14)) {
            Text(L10n.noTaskCompletions)
                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))

            Text(L10n.tr("Complete a few tasks and they will appear here.", zhHans: "完成一些任务后，它们会出现在这里。", zhHant: "完成一些任務後，它們會出現在這裡。"))
                .font(.appSystem(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "8A8179"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, scaled(48, pad: 64))
        .background(
            RoundedRectangle(cornerRadius: scaled(24, pad: 28), style: .continuous)
                .fill(Color.white.opacity(0.75))
        )
    }
}

private struct BingoDiaryStatsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DiaryCalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool
    let isWithinVisibleRange: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}

private enum BingoDiaryStatsRange: CaseIterable {
    case week
    case month
    case year

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }

    var title: String {
        switch self {
        case .week: return L10n.statsWeekShort
        case .month: return L10n.statsMonthShort
        case .year: return L10n.statsYearShort
        }
    }
}

private enum BingoDiaryStatsMode: CaseIterable {
    case completed
    case timeoutUnfinished

    var title: String {
        switch self {
        case .completed:
            return L10n.completedTasksShort
        case .timeoutUnfinished:
            return L10n.timeoutTasksShort
        }
    }
}

private struct BingoDiaryTaskCount: Identifiable, Equatable, Hashable {
    let task: String
    let count: Int
    let firstCompletedAt: Date?

    var id: String { task }
}

private struct BingoDiaryBubbleCloud: View {
    let bubbles: [BingoDiaryBubble]
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    let globalMotionOffset: CGSize
    let isInteractionPaused: Bool
    var onBubbleTap: ((BingoDiaryBubble) -> Void)? = nil
    @StateObject private var simulator = BingoDiaryBubbleDynamicsSimulator()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bubbles) { bubble in
                let dynamicOffset = simulator.offset(for: bubble.id)
                BingoDiaryBubbleView(bubble: bubble)
                    .contentShape(Circle())
                    .onTapGesture {
                        onBubbleTap?(bubble)
                    }
                    .offset(
                        x: bubble.position.x - (bubble.diameter / 2) + dynamicOffset.width,
                        y: bubble.position.y - (bubble.diameter / 2) + dynamicOffset.height
                    )
            }
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
        .onAppear {
            simulator.start()
            simulator.setPaused(isInteractionPaused)
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
            simulator.updateGravity(globalMotionOffset)
        }
        .onDisappear {
            simulator.stop()
        }
        .onChange(of: bubblesSignature) {
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
        }
        .onChange(of: canvasSignature) {
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
        }
        .onChange(of: globalMotionOffset) { _, newValue in
            simulator.updateGravity(newValue)
        }
        .onChange(of: isInteractionPaused) { _, newValue in
            simulator.setPaused(newValue)
        }
    }

    private var bubblesSignature: String {
        bubbles
            .map { "\($0.id)|\($0.diameter)|\($0.motionFactor)" }
            .joined(separator: "||")
    }

    private var canvasSignature: String {
        "\(Int(canvasWidth.rounded()))x\(Int(canvasHeight.rounded()))"
    }
}

private final class BingoDiaryBubbleDynamicsSimulator: ObservableObject {
    @Published private var offsets: [String: CGSize] = [:]

    private var velocities: [String: CGVector] = [:]
    private var impulses: [String: CGVector] = [:]
    private var motionFactors: [String: CGFloat] = [:]
    private var diameters: [String: CGFloat] = [:]
    private var baseCenters: [String: CGPoint] = [:]
    private var radii: [String: CGFloat] = [:]
    private var canvasSize: CGSize = .zero
    private var gravity: CGSize = .zero
    private var timer: Timer?
    private var isPaused = false

    func start() {
        guard timer == nil else { return }
        let interval: CGFloat = 1.0 / 45.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.step(deltaTime: interval)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        offsets.removeAll()
        velocities.removeAll()
        impulses.removeAll()
        motionFactors.removeAll()
        diameters.removeAll()
        baseCenters.removeAll()
        radii.removeAll()
        canvasSize = .zero
        gravity = .zero
        isPaused = false
    }

    func updateBubbles(_ bubbles: [BingoDiaryBubble], canvasSize: CGSize) {
        self.canvasSize = canvasSize
        let activeIDs = Set(bubbles.map(\.id))
        offsets = offsets.filter { activeIDs.contains($0.key) }
        velocities = velocities.filter { activeIDs.contains($0.key) }
        impulses = impulses.filter { activeIDs.contains($0.key) }
        motionFactors = motionFactors.filter { activeIDs.contains($0.key) }
        diameters = diameters.filter { activeIDs.contains($0.key) }
        baseCenters = baseCenters.filter { activeIDs.contains($0.key) }
        radii = radii.filter { activeIDs.contains($0.key) }

        for bubble in bubbles {
            motionFactors[bubble.id] = bubble.motionFactor
            diameters[bubble.id] = bubble.diameter
            let radius = bubble.diameter / 2
            radii[bubble.id] = radius
            baseCenters[bubble.id] = bubble.position
            if offsets[bubble.id] == nil {
                offsets[bubble.id] = .zero
            }
            if velocities[bubble.id] == nil {
                velocities[bubble.id] = .zero
            }
            if impulses[bubble.id] == nil {
                impulses[bubble.id] = .zero
            }
        }
    }

    func updateGravity(_ value: CGSize) {
        gravity = value
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    func offset(for id: String) -> CGSize {
        offsets[id] ?? .zero
    }

    private func step(deltaTime: CGFloat) {
        guard !isPaused, !offsets.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }

        var updatedOffsets = offsets
        let gravityX = activeGravityComponent(gravity.width)
        let gravityY = activeGravityComponent(gravity.height)
        let smoothing = min(max(deltaTime * 14, 0.10), 0.36)
        let maxOffsetDistance: CGFloat = 15
        var maxDelta: CGFloat = 0
        let unifiedTargetOffset = clampedOffset(
            CGSize(
                width: gravityX * maxOffsetDistance,
                height: gravityY * maxOffsetDistance
            ),
            maxDistance: maxOffsetDistance
        )

        for (id, currentOffset) in offsets {
            let nextOffset = clampedOffset(
                CGSize(
                    width: currentOffset.width + (unifiedTargetOffset.width - currentOffset.width) * smoothing,
                    height: currentOffset.height + (unifiedTargetOffset.height - currentOffset.height) * smoothing
                ),
                maxDistance: maxOffsetDistance
            )
            maxDelta = max(maxDelta, hypot(nextOffset.width - currentOffset.width, nextOffset.height - currentOffset.height))
            updatedOffsets[id] = nextOffset
        }
        // Avoid needless full cloud redraws when offset changes are visually negligible.
        if maxDelta > 0.03 {
            offsets = updatedOffsets
        }
    }

    private func clampedOffset(_ offset: CGSize, maxDistance: CGFloat) -> CGSize {
        let distance = hypot(offset.width, offset.height)
        guard distance > maxDistance, distance > 0 else { return offset }
        let scale = maxDistance / distance
        return CGSize(width: offset.width * scale, height: offset.height * scale)
    }

    private func resolveCircleCollisions(
        offsets: inout [String: CGSize],
        velocities: inout [String: CGVector]
    ) {
        let ids = offsets.keys.sorted()
        guard ids.count > 1 else { return }

        let separationGap: CGFloat = 8.0
        let iterations = 7

        for _ in 0..<iterations {
            for i in 0..<(ids.count - 1) {
                for j in (i + 1)..<ids.count {
                    let idA = ids[i]
                    let idB = ids[j]

                    guard let baseA = baseCenters[idA],
                          let baseB = baseCenters[idB],
                          let radiusA = radii[idA],
                          let radiusB = radii[idB],
                          let offsetA = offsets[idA],
                          let offsetB = offsets[idB] else {
                        continue
                    }

                    var positionA = CGPoint(x: baseA.x + offsetA.width, y: baseA.y + offsetA.height)
                    var positionB = CGPoint(x: baseB.x + offsetB.width, y: baseB.y + offsetB.height)

                    var dx = positionB.x - positionA.x
                    var dy = positionB.y - positionA.y
                    var distance = hypot(dx, dy)
                    let minimumDistance = radiusA + radiusB + separationGap

                    if distance == 0 {
                        let direction = (stableHash(idA) ^ stableHash(idB)) % 2 == 0 ? 1.0 : -1.0
                        dx = CGFloat(direction)
                        dy = 0
                        distance = 1
                    }

                    guard distance < minimumDistance else { continue }

                    let normalX = dx / distance
                    let normalY = dy / distance
                    let overlap = minimumDistance - distance

                    // 质量与半径成正比：大圆更“重”，位移更小
                    let invMassA = 1.0 / max(radiusA, 1)
                    let invMassB = 1.0 / max(radiusB, 1)
                    let invMassSum = invMassA + invMassB

                    let moveA = overlap * CGFloat(invMassA / invMassSum)
                    let moveB = overlap * CGFloat(invMassB / invMassSum)

                    positionA.x -= normalX * moveA
                    positionA.y -= normalY * moveA
                    positionB.x += normalX * moveB
                    positionB.y += normalY * moveB

                    positionA = clampPosition(positionA, radius: radiusA)
                    positionB = clampPosition(positionB, radius: radiusB)

                    offsets[idA] = CGSize(width: positionA.x - baseA.x, height: positionA.y - baseA.y)
                    offsets[idB] = CGSize(width: positionB.x - baseB.x, height: positionB.y - baseB.y)

                    var velocityA = velocities[idA] ?? .zero
                    var velocityB = velocities[idB] ?? .zero

                    let relativeNormalVelocity =
                        (velocityB.dx - velocityA.dx) * normalX +
                        (velocityB.dy - velocityA.dy) * normalY

                    if relativeNormalVelocity < 0 {
                        let restitution: CGFloat = 0.22
                        let impulse = -(1 + restitution) * relativeNormalVelocity / CGFloat(invMassSum)
                        velocityA.dx -= impulse * normalX * CGFloat(invMassA)
                        velocityA.dy -= impulse * normalY * CGFloat(invMassA)
                        velocityB.dx += impulse * normalX * CGFloat(invMassB)
                        velocityB.dy += impulse * normalY * CGFloat(invMassB)
                        velocities[idA] = velocityA
                        velocities[idB] = velocityB
                    }
                }
            }
        }
    }

    private func clampPosition(_ position: CGPoint, radius: CGFloat) -> CGPoint {
        let edgePadding: CGFloat = 10
        let minX = radius + edgePadding
        let maxX = canvasSize.width - radius - edgePadding
        let minY = radius + edgePadding
        let maxY = canvasSize.height - radius - edgePadding
        return CGPoint(
            x: min(max(position.x, minX), maxX),
            y: min(max(position.y, minY), maxY)
        )
    }

    private func stableHash(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(1469598103934665603) { partialResult, scalar in
            let mixed = partialResult ^ UInt64(scalar.value)
            return mixed &* 1099511628211
        }
    }

    private func recenterCluster(
        offsets: inout [String: CGSize],
        velocities: inout [String: CGVector]
    ) {
        guard !offsets.isEmpty else { return }
        let avgX = offsets.values.reduce(CGFloat.zero) { $0 + $1.width } / CGFloat(offsets.count)
        let avgY = offsets.values.reduce(CGFloat.zero) { $0 + $1.height } / CGFloat(offsets.count)
        let horizontalStrength: CGFloat = 0.018
        let verticalStrength: CGFloat = 0.01

        for id in offsets.keys {
            guard var offset = offsets[id] else { continue }
            offset.width -= avgX * horizontalStrength
            offset.height -= avgY * verticalStrength

            if let baseCenter = baseCenters[id], let radius = radii[id] {
                let clamped = clampPosition(
                    CGPoint(x: baseCenter.x + offset.width, y: baseCenter.y + offset.height),
                    radius: radius
                )
                offsets[id] = CGSize(width: clamped.x - baseCenter.x, height: clamped.y - baseCenter.y)
            } else {
                offsets[id] = offset
            }

            if var velocity = velocities[id] {
                velocity.dx *= 0.97
                velocity.dy *= 0.97
                velocities[id] = velocity
            }
        }
    }

    private func activeGravityComponent(_ rawValue: CGFloat) -> CGFloat {
        let deadZone: CGFloat = 0.03
        let magnitude = abs(rawValue)
        guard magnitude > deadZone else { return 0 }
        let normalized = min(1.0, (magnitude - deadZone) / max(0.0001, 1.0 - deadZone))
        let curved = pow(normalized, 0.92)
        return rawValue.sign == .minus ? -curved : curved
    }
}

private final class BingoDiaryImpactFeedbackEngine {
    static let shared = BingoDiaryImpactFeedbackEngine()

    private let generator = UIImpactFeedbackGenerator(style: .medium)
    private var lastTriggerTime: TimeInterval = 0
    private let minimumInterval: TimeInterval = 0.12

    private init() {
        generator.prepare()
    }

    func trigger(intensity: CGFloat) {
        let now = CACurrentMediaTime()
        guard now - lastTriggerTime >= minimumInterval else { return }
        lastTriggerTime = now

        let normalizedIntensity = max(0.35, min(1.0, intensity))
        generator.impactOccurred(intensity: normalizedIntensity)
        generator.prepare()

        if AppSettings.isSoundEffectsEnabled {
            AudioServicesPlaySystemSound(1104)
        }
    }
}

private struct BingoDiaryBubbleView: View {
    let bubble: BingoDiaryBubble

    private var labelWidth: CGFloat {
        bubble.diameter * (bubble.diameter <= 70 ? 0.72 : 0.78)
    }

    private var labelHeight: CGFloat {
        bubble.diameter * 0.56
    }

    private var backgroundNumberFontSize: CGFloat {
        // radius 40~140 -> font 40~150
        let radius = bubble.diameter / 2
        let normalized = max(0, min(1, (radius - 40) / 100))
        return 40 + normalized * 110
    }

    private var taskFontSize: CGFloat {
        let baseSize: CGFloat
        switch bubble.diameter {
        case ..<90:
            baseSize = 13
        case ..<150:
            baseSize = 16
        case ..<210:
            baseSize = 19
        default:
            baseSize = 22
        }
        let lengthPenalty = CGFloat(max(0, bubble.task.count - 8)) * 0.22
        return max(10, baseSize - lengthPenalty)
    }

    private var bubbleTextColor: Color {
        let mixed = mix(colorA: bubble.gradientStart, colorB: bubble.gradientEnd, ratio: 0.56)
        return deepenedColor(from: mixed)
    }

    private func mix(colorA: Color, colorB: Color, ratio: CGFloat) -> UIColor {
        let left = UIColor(colorA)
        let right = UIColor(colorB)
        var lr: CGFloat = 0
        var lg: CGFloat = 0
        var lb: CGFloat = 0
        var la: CGFloat = 0
        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        let leftOK = left.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        let rightOK = right.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        guard leftOK, rightOK else { return left }
        let clamped = min(max(ratio, 0), 1)
        let inv = 1 - clamped
        return UIColor(
            red: lr * clamped + rr * inv,
            green: lg * clamped + rg * inv,
            blue: lb * clamped + rb * inv,
            alpha: la * clamped + ra * inv
        )
    }

    private func deepenedColor(from color: UIColor) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let deeper = UIColor(
                hue: hue,
                saturation: min(1.0, saturation * 1.12 + 0.04),
                brightness: max(0.08, brightness * 0.38),
                alpha: 1
            )
            return Color(uiColor: deeper)
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var rgbaAlpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &rgbaAlpha) {
            return Color(
                red: max(0, red * 0.42),
                green: max(0, green * 0.42),
                blue: max(0, blue * 0.42)
            )
        }
        return Color(hex: "2B1A0D")
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [bubble.gradientStart, bubble.gradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("\(bubble.count)")
                .font(.appSystem(size: backgroundNumberFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.2))
                .minimumScaleFactor(0.4)

            Text(bubble.task)
                .font(.appSystem(size: taskFontSize, weight: .bold, design: .rounded))
                .foregroundColor(bubbleTextColor)
                .frame(width: labelWidth, height: labelHeight, alignment: .center)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
        }
        .frame(width: bubble.diameter, height: bubble.diameter)
        .clipShape(Circle())
    }
}

private struct BingoDiaryBubble: Identifiable, Equatable {
    let id: String
    let task: String
    let count: Int
    let diameter: CGFloat
    let position: CGPoint
    let gradientStart: Color
    let gradientEnd: Color
    let motionFactor: CGFloat
}

private enum BingoDiaryBubbleTier {
    case round1
    case round2
    case round3
    case round4

    var diameter: CGFloat {
        switch self {
        case .round1: return 237
        case .round2: return 200
        case .round3: return 130
        case .round4: return 70
        }
    }

    var backgroundFontSize: CGFloat {
        switch self {
        case .round1: return 150
        case .round2: return 110
        case .round3: return 90
        case .round4: return 40
        }
    }
}

private enum BingoDiaryBubbleLayout {
    private struct Descriptor {
        let taskCount: BingoDiaryTaskCount
        let radius: CGFloat
        let gradientStart: Color
        let gradientEnd: Color
        let motionFactor: CGFloat

        var diameter: CGFloat { radius * 2 }
    }

    private struct Placement {
        let descriptor: Descriptor
        let center: CGPoint
        let radius: CGFloat
    }

    private static let minimumGap: CGFloat = 8
    private static let sideInset: CGFloat = 16
    private static let topInset: CGFloat = 0
    private static let initialTopGap: CGFloat = 0
    private static let bottomVisibilityReserve: CGFloat = 28
    private static let palette: [(Color, Color)] = [
        (Color(hex: "F1C397"), Color(hex: "F7E3CF")),
        (Color(hex: "F1A0A0"), Color(hex: "FFDBDB")),
        (Color(hex: "99DAC0"), Color(hex: "CCF4D0")),
        (Color(hex: "7DC5E2"), Color(hex: "D6F3FF")),
        (Color(hex: "BF9CD6"), Color(hex: "FDE4FC")),
        (Color(hex: "EBA1CA"), Color(hex: "FDD7EC"))
    ]

    static func layout(
        taskCounts: [BingoDiaryTaskCount],
        width: CGFloat,
        viewportHeight: CGFloat,
        maximumBubbleCount: Int
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        let visibleItems = Array(taskCounts.prefix(maximumBubbleCount))
        let usableWidth = width.isFinite ? max(width, 0) : 0
        guard !visibleItems.isEmpty else { return ([], usableWidth, 0, false) }
        // Wait for a real measured width instead of using a synthetic fallback.
        // This avoids first-entry transient vertical stacks caused by early narrow passes.
        guard usableWidth > 1 else { return ([], 0, 0, false) }

        let sortedItems = visibleItems.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                switch (lhs.firstCompletedAt, rhs.firstCompletedAt) {
                case let (l?, r?) where l != r:
                    return l < r
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                default:
                    return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
                }
            }
            return lhs.count > rhs.count
        }

        let minimumCount = sortedItems.map(\.count).min() ?? 0
        let maximumCount = sortedItems.map(\.count).max() ?? 0
        let countSpread = maximumCount - minimumCount
        let uniqueCountsAscending = Array(Set(sortedItems.map(\.count))).sorted()
        let shouldUseAdjacentTierSizing = sortedItems.count < 4 || countSpread < 2

        let adjacentTierByCount: [Int: BingoDiaryBubbleTier] = {
            guard shouldUseAdjacentTierSizing, !uniqueCountsAscending.isEmpty else { return [:] }
            let tiersAscending: [BingoDiaryBubbleTier] = [.round4, .round3, .round2, .round1] // small -> large
            let requiredTierCount = min(max(uniqueCountsAscending.count, 1), tiersAscending.count)
            let preferredStart = adjacentTierStartIndex(maxCount: maximumCount, requiredTierCount: requiredTierCount)
            let maxStart = tiersAscending.count - requiredTierCount
            let startIndex = min(max(preferredStart, 0), maxStart)
            var mapping: [Int: BingoDiaryBubbleTier] = [:]
            for (index, count) in uniqueCountsAscending.enumerated() {
                let tierOffset = min(index, requiredTierCount - 1)
                mapping[count] = tiersAscending[startIndex + tierOffset]
            }
            return mapping
        }()

        func radius(for value: Int) -> CGFloat {
            if shouldUseAdjacentTierSizing, let tier = adjacentTierByCount[value] {
                return tier.diameter / 2
            }
            guard maximumCount > minimumCount else { return 90 }
            let normalized = CGFloat(value - minimumCount) / CGFloat(maximumCount - minimumCount)
            return 40 + normalized * 100
        }

        let descriptors: [Descriptor] = sortedItems.enumerated().map { index, item in
            let resolvedRadius = radius(for: item.count)
            let paletteItem = palette[colorIndex(for: item.task)]
            let normalizedRadius = max(0, min(1, (resolvedRadius - 40) / 100))
            let tierMotionBase: CGFloat = 1.12 - normalizedRadius * 0.16
            let colorJitter = CGFloat(colorIndex(for: item.task) % 4) * 0.04
            let motionFactor = min(1.25, tierMotionBase + colorJitter)
            return Descriptor(
                taskCount: item,
                radius: resolvedRadius,
                gradientStart: paletteItem.0,
                gradientEnd: paletteItem.1,
                motionFactor: motionFactor
            )
        }

        if descriptors.count == 1 {
            let descriptor = descriptors[0]
            let canvasHeight = max(360, descriptor.radius * 2 + 160) + bottomVisibilityReserve
            let center = CGPoint(
                x: usableWidth / 2,
                y: canvasHeight / 2
            )
            let bubbles = [makeBubble(from: descriptor, at: center)]
            return (
                bubbles,
                usableWidth,
                canvasHeight,
                false
            )
        }

        return horizontalOverflowLayout(
            descriptors: descriptors,
            canvasWidth: usableWidth,
            viewportHeight: viewportHeight
        )
    }

    private static func adjacentTierStartIndex(maxCount: Int, requiredTierCount: Int) -> Int {
        let preferredStart: Int
        switch maxCount {
        case ...2:
            preferredStart = 0
        case ...5:
            preferredStart = 1
        case ...24:
            preferredStart = 2
        default:
            preferredStart = 2
        }
        return min(max(preferredStart, 0), max(0, 4 - requiredTierCount))
    }

    private static func shouldUseHorizontalOverflowByWidth(
        descriptors: [Descriptor],
        availableWidth: CGFloat
    ) -> Bool {
        let totalDiameters = descriptors.reduce(CGFloat.zero) { $0 + $1.diameter }
        let totalGaps = CGFloat(max(descriptors.count - 1, 0)) * minimumGap
        let requiredWidth = sideInset + totalDiameters + totalGaps + sideInset
        return requiredWidth > availableWidth
    }

    private static func centeredVerticalColumnsLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard !descriptors.isEmpty else { return ([], canvasWidth, 0, false) }

        let centerX = canvasWidth / 2
        let centerIndex: Int = descriptors.enumerated().min { lhs, rhs in
            let leftDate = lhs.element.taskCount.firstCompletedAt
            let rightDate = rhs.element.taskCount.firstCompletedAt
            switch (leftDate, rightDate) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.offset < rhs.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }?.offset ?? 0

        let centerDescriptor = descriptors[centerIndex]
        var remainingDescriptors = descriptors.enumerated().compactMap { index, descriptor in
            index == centerIndex ? nil : descriptor
        }

        let centerAnchor = CGPoint(
            x: centerX,
            y: topInset + centerDescriptor.radius + initialTopGap
        )
        var bubbles: [BingoDiaryBubble] = []
        bubbles.reserveCapacity(descriptors.count)
        bubbles.append(
            makeBubble(
                from: centerDescriptor,
                at: centerAnchor
            )
        )

        var nextTopY = centerAnchor.y + centerDescriptor.radius + minimumGap
        var rowIndex = 0

        while !remainingDescriptors.isEmpty {
            let leftDescriptor = remainingDescriptors.isEmpty ? nil : remainingDescriptors.removeFirst()
            let rightDescriptor = remainingDescriptors.isEmpty ? nil : remainingDescriptors.removeFirst()
            let rowHeight = max(leftDescriptor?.diameter ?? 0, rightDescriptor?.diameter ?? 0)
            guard rowHeight > 0 else { break }

            let rowCenterY = nextTopY + (rowHeight / 2)
            let horizontalExtra = CGFloat(rowIndex) * 4

            if let leftDescriptor {
                let leftCenterX = clamp(
                    centerX - (centerDescriptor.radius + leftDescriptor.radius + minimumGap + 12 + horizontalExtra),
                    sideInset + leftDescriptor.radius,
                    canvasWidth - sideInset - leftDescriptor.radius
                )
                bubbles.append(
                    makeBubble(
                        from: leftDescriptor,
                        at: CGPoint(x: leftCenterX, y: rowCenterY)
                    )
                )
            }

            if let rightDescriptor {
                let rightCenterX = clamp(
                    centerX + (centerDescriptor.radius + rightDescriptor.radius + minimumGap + 12 + horizontalExtra),
                    sideInset + rightDescriptor.radius,
                    canvasWidth - sideInset - rightDescriptor.radius
                )
                bubbles.append(
                    makeBubble(
                        from: rightDescriptor,
                        at: CGPoint(x: rightCenterX, y: rowCenterY)
                    )
                )
            }

            nextTopY += rowHeight + minimumGap
            rowIndex += 1
        }

        let contentBottom = max(
            bubbles.map { $0.position.y + ($0.diameter / 2) }.max() ?? 0,
            nextTopY - minimumGap
        )
        let canvasHeight = max(420, contentBottom + topInset + bottomVisibilityReserve)
        let relaxed = relaxInitialOverlaps(
            bubbles: bubbles,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
        return (relaxed, canvasWidth, canvasHeight, false)
    }

    private static func verticalStackLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard !descriptors.isEmpty else { return ([], canvasWidth, 0, false) }

        let centerX = canvasWidth / 2
        var nextTopY = topInset + initialTopGap
        var bubbles: [BingoDiaryBubble] = []
        bubbles.reserveCapacity(descriptors.count)

        for descriptor in descriptors {
            let centerY = nextTopY + descriptor.radius
            bubbles.append(
                makeBubble(
                    from: descriptor,
                    at: CGPoint(x: centerX, y: centerY)
                )
            )
            nextTopY = centerY + descriptor.radius + minimumGap
        }

        let contentBottom = nextTopY - minimumGap
        let canvasHeight = max(420, contentBottom + topInset + bottomVisibilityReserve)
        return (bubbles, canvasWidth, canvasHeight, false)
    }

    private static func tier(for count: Int, rank: Int, total: Int, topCount: Int) -> BingoDiaryBubbleTier {
        if total == 1 { return .round1 }
        if rank == 0 { return .round1 }
        if total == 2 { return rank == 1 ? .round2 : .round1 }
        if total == 3 {
            return rank == 1 ? .round2 : (rank == 2 ? .round3 : .round1)
        }

        let normalizedTop = max(topCount, 1)
        let ratio = Double(count) / Double(normalizedTop)

        // 在窄屏上避免前几颗圆过大导致只能纵向堆叠：当头部完成数不高时，压缩到 round3/round4。
        if normalizedTop <= 2 {
            return rank <= 4 ? .round3 : .round4
        }

        if normalizedTop <= 4 {
            if rank <= 1 && ratio >= 0.8 {
                return .round2
            }
            if rank <= 6 || ratio >= 0.22 {
                return .round3
            }
            return .round4
        }

        if rank <= 2 && ratio >= 0.58 {
            return .round2
        }
        if rank <= 7 || ratio >= 0.14 {
            return .round3
        }
        return .round4
    }

    private static func uniformTier(forItemCount itemCount: Int) -> BingoDiaryBubbleTier {
        switch itemCount {
        case ...4:
            return .round2
        case ...12:
            return .round3
        default:
            return .round4
        }
    }

    private static func shouldPreferHorizontalOverflow(
        descriptors: [Descriptor],
        availableWidth: CGFloat,
        clusteredHeight: CGFloat
    ) -> Bool {
        // 优先使用“最大圆居中 + 周围随机分布”，只有数量很多且高度明显过高时才切换到右延展。
        if descriptors.count < 14 {
            return false
        }
        if availableWidth >= 430 && descriptors.count < 18 {
            return false
        }
        return clusteredHeight > 2200
    }

    private static func horizontalOverflowLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard !descriptors.isEmpty else { return ([], canvasWidth, 0, false) }

        let effectiveViewportHeight = viewportHeight.isFinite ? max(viewportHeight, 0) : 0
        let baseHeight = effectiveViewportHeight > 1 ? effectiveViewportHeight : 560
        let pageHeight = max(560, baseHeight + 140)
        let availableTop = topInset + initialTopGap
        let availableBottom = pageHeight - topInset
        let edgeOverflowX: CGFloat = 26
        let edgeOverflowY: CGFloat = 0

        let sortedDescriptors = descriptors.sorted { lhs, rhs in
            if lhs.radius != rhs.radius { return lhs.radius > rhs.radius }
            return lhs.taskCount.count > rhs.taskCount.count
        }

        var placed: [Placement] = []
        var requiredPageCount = 1
        let maxAttemptsPerPage = 800

        for (index, descriptor) in sortedDescriptors.enumerated() {
            var placement: Placement?
            var pageIndex = 0

            while placement == nil && pageIndex < 120 {
                let pageStartX = CGFloat(pageIndex) * canvasWidth
                let minX = pageStartX + descriptor.radius - edgeOverflowX
                let maxX = pageStartX + canvasWidth - descriptor.radius + edgeOverflowX
                let minY = availableTop + descriptor.radius - edgeOverflowY
                let maxY = availableBottom - descriptor.radius + edgeOverflowY

                var generator = SeededGenerator(
                    state: seed(for: descriptor.taskCount.task)
                    &+ UInt64(index * 131)
                    &+ UInt64(pageIndex * 9_973)
                    &+ 1
                )
                let pagePlaced = placed.filter { placement in
                    placement.center.x >= pageStartX - edgeOverflowX &&
                    placement.center.x <= pageStartX + canvasWidth + edgeOverflowX
                }
                var bestPlacementForPage: (placement: Placement, score: CGFloat)?

                let tangentAttempts = Int(CGFloat(maxAttemptsPerPage) * 0.9)
                for attempt in 0..<maxAttemptsPerPage {
                    let candidate: CGPoint
                    if !pagePlaced.isEmpty,
                       attempt < tangentAttempts,
                       let base = pagePlaced.randomElement(using: &generator) {
                        let angle = CGFloat.random(in: 0...(2 * .pi), using: &generator)
                        // Keep edge spacing uniform regardless of bubble sizes.
                        let targetDistance = base.radius + descriptor.radius + minimumGap
                        candidate = CGPoint(
                            x: base.center.x + cos(angle) * targetDistance,
                            y: base.center.y + sin(angle) * targetDistance
                        )
                    } else {
                        candidate = CGPoint(
                            x: CGFloat.random(in: minX...maxX, using: &generator),
                            y: CGFloat.random(in: minY...maxY, using: &generator)
                        )
                    }

                    guard candidate.x >= minX, candidate.x <= maxX,
                          candidate.y >= minY, candidate.y <= maxY else {
                        continue
                    }
                    if fits(candidate, radius: descriptor.radius, among: placed) {
                        let resolvedPlacement = Placement(
                            descriptor: descriptor,
                            center: candidate,
                            radius: descriptor.radius
                        )
                        let nearestEdgeDistance: CGFloat = placed.isEmpty
                            ? 0
                            : placed.reduce(CGFloat.greatestFiniteMagnitude) { current, other in
                                let centerDistance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
                                let edgeDistance = max(0, centerDistance - (descriptor.radius + other.radius))
                                return min(current, edgeDistance)
                            }
                        let pageCenter = CGPoint(
                            x: pageStartX + (canvasWidth / 2),
                            y: (availableTop + availableBottom) / 2
                        )
                        let centerDistance = hypot(candidate.x - pageCenter.x, candidate.y - pageCenter.y)
                        // Prefer candidates that keep the nearest edge gap close to minimumGap.
                        let score = nearestEdgeDistance * 8 + centerDistance * 0.02

                        if let best = bestPlacementForPage {
                            if score < best.score {
                                bestPlacementForPage = (resolvedPlacement, score)
                            }
                        } else {
                            bestPlacementForPage = (resolvedPlacement, score)
                        }
                    }
                }

                if let bestPlacementForPage {
                    placement = bestPlacementForPage.placement
                    requiredPageCount = max(requiredPageCount, pageIndex + 1)
                }

                if placement == nil {
                    pageIndex += 1
                }
            }

            if let placement {
                placed.append(placement)
            } else {
                let fallbackPage = requiredPageCount
                let fallbackCenter = CGPoint(
                    x: CGFloat(fallbackPage) * canvasWidth + canvasWidth * 0.5,
                    y: (availableTop + availableBottom) * 0.5
                )
                placed.append(
                    Placement(
                        descriptor: descriptor,
                        center: fallbackCenter,
                        radius: descriptor.radius
                    )
                )
                requiredPageCount = fallbackPage + 1
            }
        }

        let bubbles = placed.map { placement in
            makeBubble(from: placement.descriptor, at: placement.center)
        }
        let totalCanvasWidth = max(canvasWidth, CGFloat(requiredPageCount) * canvasWidth)
        return (bubbles, totalCanvasWidth, pageHeight, requiredPageCount > 1)
    }

    private static func uniformSideWrappedLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard let centerDescriptor = descriptors.first else {
            return ([], canvasWidth, 0, false)
        }

        var canvasHeight = max(420, centerDescriptor.diameter + 220)
        let anchor = CGPoint(
            x: canvasWidth / 2,
            y: topInset + centerDescriptor.radius + initialTopGap
        )
        let sidePreferredAngles = sideWrappingAngleIndices(count: 24).map {
            (CGFloat($0) / 24.0) * .pi * 2
        }

        var placed: [Placement] = [
            Placement(descriptor: centerDescriptor, center: anchor, radius: centerDescriptor.radius)
        ]

        for descriptor in descriptors.dropFirst() {
            var placedPoint: CGPoint?
            let minX = sideInset + descriptor.radius
            let maxX = canvasWidth - sideInset - descriptor.radius

            var expansion = 0
            while placedPoint == nil && expansion < 7 {
                let minY = topInset + descriptor.radius
                let maxY = canvasHeight - topInset - descriptor.radius
                let maxReachX = max(18, min(anchor.x - minX, maxX - anchor.x))
                let maxReachY = max(18, min(anchor.y - minY, maxY - anchor.y))

                var bestRelaxedCandidate: (point: CGPoint, overlapPenalty: CGFloat, distancePenalty: CGFloat)?

                for ring in 1...18 {
                    let baseX = max(descriptor.radius + minimumGap + 6, CGFloat(ring) * (descriptor.radius * 1.18 + minimumGap))
                    let baseY = max(descriptor.radius + minimumGap + 6, CGFloat(ring) * (descriptor.radius * 1.05 + minimumGap))
                    let ellipseX = min(maxReachX * 0.96, baseX)
                    let ellipseY = min(maxReachY * 0.96, baseY)

                    for angle in sidePreferredAngles {
                        let candidate = CGPoint(
                            x: anchor.x + cos(angle) * ellipseX,
                            y: anchor.y + sin(angle) * ellipseY
                        )

                        guard candidate.x >= minX, candidate.x <= maxX,
                              candidate.y >= minY, candidate.y <= maxY else {
                            continue
                        }

                        if fits(candidate, radius: descriptor.radius, among: placed) {
                            placedPoint = candidate
                            break
                        }

                        let overlapPenalty = placed.reduce(CGFloat.zero) { partial, other in
                            let distance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
                            let minDistance = descriptor.radius + other.radius + minimumGap
                            return partial + max(0, minDistance - distance)
                        }
                        let horizontalPreference = abs(candidate.y - anchor.y) * 0.7 + abs(candidate.x - anchor.x) * 0.25
                        if let current = bestRelaxedCandidate {
                            if overlapPenalty < current.overlapPenalty ||
                                (overlapPenalty == current.overlapPenalty && horizontalPreference < current.distancePenalty) {
                                bestRelaxedCandidate = (candidate, overlapPenalty, horizontalPreference)
                            }
                        } else {
                            bestRelaxedCandidate = (candidate, overlapPenalty, horizontalPreference)
                        }
                    }

                    if placedPoint != nil { break }
                }

                if placedPoint == nil {
                    if let relaxed = bestRelaxedCandidate {
                        placedPoint = relaxed.point
                    } else {
                        canvasHeight += 90
                        expansion += 1
                    }
                }
            }

            if placedPoint == nil {
                let fallbackAngle = sidePreferredAngles[(placed.count - 1) % sidePreferredAngles.count]
                let minY = topInset + descriptor.radius
                let maxY = canvasHeight - topInset - descriptor.radius
                let fallback = CGPoint(
                    x: clamp(anchor.x + cos(fallbackAngle) * max(22, descriptor.radius + 8), minX, maxX),
                    y: clamp(anchor.y + sin(fallbackAngle) * max(22, descriptor.radius + 8), minY, maxY)
                )
                placedPoint = fallback
            }

            placed.append(
                Placement(
                    descriptor: descriptor,
                    center: placedPoint ?? anchor,
                    radius: descriptor.radius
                )
            )
        }

        let maxY = placed.map { $0.center.y + $0.radius }.max() ?? anchor.y
        let bubbles = placed.map { makeBubble(from: $0.descriptor, at: $0.center) }
        let finalHeight = max(canvasHeight, maxY + 24 + bottomVisibilityReserve)
        let relaxed = relaxInitialOverlaps(
            bubbles: bubbles,
            canvasWidth: canvasWidth,
            canvasHeight: finalHeight
        )
        return (relaxed, canvasWidth, finalHeight, false)
    }

    private static func clusteredLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat,
        preferSideWrapping: Bool = false
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard let firstDescriptor = descriptors.first else {
            return ([], canvasWidth, 0, false)
        }

        var canvasHeight = max(430, firstDescriptor.diameter + 240)
        let centerAnchor = CGPoint(
            x: canvasWidth / 2,
            y: topInset + firstDescriptor.radius + initialTopGap
        )
        var placed: [Placement] = [
            Placement(descriptor: firstDescriptor, center: centerAnchor, radius: firstDescriptor.radius)
        ]

        for descriptor in descriptors.dropFirst() {
            var placedPoint: CGPoint?
            var relaxedCandidate: (point: CGPoint, score: CGFloat)?
            var laneIndex = 0

            while placedPoint == nil && laneIndex < 22 {
                let minX = sideInset + descriptor.radius
                let maxX = canvasWidth - sideInset - descriptor.radius
                let minY = topInset + descriptor.radius
                let maxY = canvasHeight - topInset - descriptor.radius

                let lane = CGFloat(laneIndex)
                let xOffset =
                    firstDescriptor.radius +
                    descriptor.radius +
                    minimumGap +
                    16 +
                    lane * max(descriptor.radius * 0.85, 24)

                let yStep = max(descriptor.radius * 0.95, 22)
                let yOffsets: [CGFloat] = [0, -yStep, yStep, -2 * yStep, 2 * yStep]
                let sidePriority: [CGFloat] = placed.count.isMultiple(of: 2) ? [1, -1] : [-1, 1]

                for side in sidePriority {
                    for yOffset in yOffsets {
                        let candidate = CGPoint(
                            x: clamp(centerAnchor.x + side * xOffset, minX, maxX),
                            y: clamp(centerAnchor.y + yOffset, minY, maxY)
                        )

                        if fits(candidate, radius: descriptor.radius, among: placed) {
                            placedPoint = candidate
                            break
                        }

                        let overlapPenalty = placed.reduce(CGFloat.zero) { partial, other in
                            let distance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
                            let minDistance = descriptor.radius + other.radius + minimumGap
                            return partial + max(0, minDistance - distance)
                        }
                        let verticalPenalty = abs(candidate.y - centerAnchor.y)
                        let sidePenalty = abs((candidate.x - centerAnchor.x) / max(1, xOffset))
                        let score = overlapPenalty * 2.0 + verticalPenalty * 0.65 + sidePenalty * 20

                        if let current = relaxedCandidate {
                            if score < current.score {
                                relaxedCandidate = (candidate, score)
                            }
                        } else {
                            relaxedCandidate = (candidate, score)
                        }
                    }
                    if placedPoint != nil { break }
                }

                if placedPoint == nil {
                    laneIndex += 1
                    if laneIndex % 5 == 0 {
                        canvasHeight += 56
                    }
                }
            }

            if placedPoint == nil, preferSideWrapping {
                let stepSeed = seed(for: descriptor.taskCount.task) &+ UInt64(placed.count * 97)
                placedPoint = findClusterCenter(
                    radius: descriptor.radius,
                    clusterAnchor: centerAnchor,
                    canvasWidth: canvasWidth,
                    canvasHeight: canvasHeight,
                    placed: placed,
                    seed: stepSeed,
                    preferSideWrapping: true
                )
            }

            let sideSign: CGFloat = placed.count.isMultiple(of: 2) ? 1 : -1
            let lane = CGFloat(max(0, placed.count - 1) / 2)
            let fallback = CGPoint(
                x: clamp(
                    centerAnchor.x + sideSign * (firstDescriptor.radius + descriptor.radius + minimumGap + 14 + lane * 20),
                    sideInset + descriptor.radius,
                    canvasWidth - sideInset - descriptor.radius
                ),
                y: clamp(
                    centerAnchor.y + ((lane.truncatingRemainder(dividingBy: 2) == 0) ? -1 : 1) * (descriptor.radius * 0.2 + lane * 4),
                    topInset + descriptor.radius,
                    canvasHeight - topInset - descriptor.radius
                )
            )
            placed.append(
                Placement(
                    descriptor: descriptor,
                    center: placedPoint ?? relaxedCandidate?.point ?? fallback,
                    radius: descriptor.radius
                )
            )
        }

        if !placed.isEmpty {
            let minBoundX = placed.map { $0.center.x - $0.radius }.min() ?? sideInset
            let maxBoundX = placed.map { $0.center.x + $0.radius }.max() ?? (canvasWidth - sideInset)
            let clusterMidX = (minBoundX + maxBoundX) / 2
            let allowablePositive = (canvasWidth - sideInset) - maxBoundX
            let allowableNegative = sideInset - minBoundX
            let shiftX = clamp(centerAnchor.x - clusterMidX, allowableNegative, allowablePositive)
            if abs(shiftX) > 0.5 {
                placed = placed.map { current in
                    Placement(
                        descriptor: current.descriptor,
                        center: CGPoint(x: current.center.x + shiftX, y: current.center.y),
                        radius: current.radius
                    )
                }
            }
        }

        let maxY = placed.map { $0.center.y + $0.radius }.max() ?? 0
        let bubbles = placed.map { makeBubble(from: $0.descriptor, at: $0.center) }
        let finalHeight = max(canvasHeight, maxY + 28 + bottomVisibilityReserve)
        let relaxed = relaxInitialOverlaps(
            bubbles: bubbles,
            canvasWidth: canvasWidth,
            canvasHeight: finalHeight
        )
        return (relaxed, canvasWidth, finalHeight, false)
    }

    private static func findClusterCenter(
        radius: CGFloat,
        clusterAnchor: CGPoint,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat,
        placed: [Placement],
        seed: UInt64,
        preferSideWrapping: Bool
    ) -> CGPoint? {
        let minX = sideInset + radius
        let maxX = canvasWidth - sideInset - radius
        let minY = topInset + radius
        let maxY = canvasHeight - topInset - radius

        let largestRadius = placed.first?.radius ?? 0
        let ringStart = largestRadius + radius + minimumGap
        let angleCount = 24
        var bestCandidate: (point: CGPoint, score: CGFloat)?

        for ringIndex in 0..<30 {
            let ringDistance = ringStart + CGFloat(ringIndex) * 18
            let angleOrder: [Int]
            if preferSideWrapping {
                angleOrder = sideWrappingAngleIndices(count: angleCount)
            } else {
                angleOrder = shuffledIndices(
                    count: angleCount,
                    seed: seed &+ UInt64(ringIndex * 31)
                )
            }

            for angleIndex in angleOrder {
                let angle = (CGFloat(angleIndex) / CGFloat(angleCount)) * .pi * 2
                let rawPoint = CGPoint(
                    x: clusterAnchor.x + cos(angle) * ringDistance,
                    y: clusterAnchor.y + sin(angle) * ringDistance
                )
                let candidate = CGPoint(
                    x: clamp(rawPoint.x, minX, maxX),
                    y: clamp(rawPoint.y, minY, maxY)
                )

                guard fits(candidate, radius: radius, among: placed) else { continue }

                let centerDistance = hypot(
                    candidate.x - clusterAnchor.x,
                    candidate.y - clusterAnchor.y
                )
                let nearbyCount = placed.reduce(0) { partialResult, placement in
                    let distance = hypot(
                        candidate.x - placement.center.x,
                        candidate.y - placement.center.y
                    )
                    let edgeDistance = distance - radius - placement.radius
                    return partialResult + (edgeDistance <= minimumGap + 20 ? 1 : 0)
                }
                let randomBias = CGFloat((seed &+ UInt64(angleIndex * 13)) % 100) / 500.0
                let verticalPenalty = abs(candidate.y - clusterAnchor.y)
                let sideBias = abs(cos(angle))
                let sidePenalty = max(0, 0.55 - sideBias) * 180
                let score: CGFloat
                if preferSideWrapping {
                    score = centerDistance * 0.28 + verticalPenalty * 1.45 + sidePenalty - CGFloat(nearbyCount) * 20 + randomBias
                } else {
                    score = centerDistance - CGFloat(nearbyCount) * 26 + randomBias
                }

                if let currentBest = bestCandidate {
                    if score < currentBest.score {
                        bestCandidate = (candidate, score)
                    }
                } else {
                    bestCandidate = (candidate, score)
                }
            }
        }

        return bestCandidate?.point
    }

    private static func fits(_ candidate: CGPoint, radius: CGFloat, among placed: [Placement]) -> Bool {
        for other in placed {
            let distance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
            if distance < radius + other.radius + minimumGap {
                return false
            }
        }
        return true
    }

    private static func makeBubble(from descriptor: Descriptor, at center: CGPoint) -> BingoDiaryBubble {
        BingoDiaryBubble(
            id: descriptor.taskCount.id,
            task: descriptor.taskCount.task,
            count: descriptor.taskCount.count,
            diameter: descriptor.diameter,
            position: center,
            gradientStart: descriptor.gradientStart,
            gradientEnd: descriptor.gradientEnd,
            motionFactor: descriptor.motionFactor
        )
    }

    private static func shuffledIndices(count: Int, seed: UInt64) -> [Int] {
        var values = Array(0..<count)
        var generator = SeededGenerator(state: max(seed, 1))
        values.shuffle(using: &generator)
        return values
    }

    private static func sideWrappingAngleIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let all = Array(0..<count)
        let angles = all.map { idx in
            (idx: idx, angle: (CGFloat(idx) / CGFloat(count)) * .pi * 2)
        }

        let left = angles
            .filter { cos($0.angle) < 0 }
            .sorted {
                let lhs = abs(sin($0.angle))
                let rhs = abs(sin($1.angle))
                if lhs == rhs {
                    return abs(cos($0.angle)) > abs(cos($1.angle))
                }
                return lhs < rhs
            }
            .map(\.idx)

        let right = angles
            .filter { cos($0.angle) >= 0 }
            .sorted {
                let lhs = abs(sin($0.angle))
                let rhs = abs(sin($1.angle))
                if lhs == rhs {
                    return abs(cos($0.angle)) > abs(cos($1.angle))
                }
                return lhs < rhs
            }
            .map(\.idx)

        var result: [Int] = []
        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < left.count || rightIndex < right.count {
            if leftIndex < left.count {
                result.append(left[leftIndex])
                leftIndex += 1
            }
            if rightIndex < right.count {
                result.append(right[rightIndex])
                rightIndex += 1
            }
        }
        return result
    }

    private static func deterministicJitter(task: String, amplitude: CGFloat) -> CGFloat {
        guard amplitude > 0 else { return 0 }
        let value = CGFloat(seed(for: task) % 10_000) / 10_000.0
        return (value * 2 - 1) * amplitude
    }

    private static func seed(for text: String) -> UInt64 {
        text.unicodeScalars.reduce(1469598103934665603) { partialResult, scalar in
            let mixed = partialResult ^ UInt64(scalar.value)
            return mixed &* 1099511628211
        }
    }

    private static func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    private static func colorIndex(for task: String) -> Int {
        abs(task.unicodeScalars.reduce(0) { partialResult, scalar in
            ((partialResult * 31) + Int(scalar.value)) % 100_000
        }) % palette.count
    }

    private static func relaxInitialOverlaps(
        bubbles: [BingoDiaryBubble],
        canvasWidth: CGFloat,
        canvasHeight: CGFloat
    ) -> [BingoDiaryBubble] {
        guard bubbles.count > 1 else { return bubbles }

        var centers = bubbles.map(\.position)
        let radii = bubbles.map { $0.diameter / 2 }
        let gap = minimumGap
        let iterations = 18
        let minXPadding = sideInset
        let minYPadding = topInset + 4

        for _ in 0..<iterations {
            for i in 0..<(centers.count - 1) {
                for j in (i + 1)..<centers.count {
                    var dx = centers[j].x - centers[i].x
                    var dy = centers[j].y - centers[i].y
                    var distance = hypot(dx, dy)
                    let minDistance = radii[i] + radii[j] + gap
                    if distance == 0 {
                        dx = 1
                        dy = 0
                        distance = 1
                    }
                    guard distance < minDistance else { continue }
                    let overlap = minDistance - distance
                    let nx = dx / distance
                    let ny = dy / distance
                    let push = overlap * 0.5
                    centers[i].x -= nx * push
                    centers[i].y -= ny * push
                    centers[j].x += nx * push
                    centers[j].y += ny * push
                }
            }

            for index in centers.indices {
                let radius = radii[index]
                centers[index].x = clamp(
                    centers[index].x,
                    minXPadding + radius,
                    canvasWidth - minXPadding - radius
                )
                centers[index].y = clamp(
                    centers[index].y,
                    minYPadding + radius,
                    canvasHeight - minYPadding - radius
                )
            }
        }

        return zip(bubbles, centers).map { bubble, center in
            BingoDiaryBubble(
                id: bubble.id,
                task: bubble.task,
                count: bubble.count,
                diameter: bubble.diameter,
                position: center,
                gradientStart: bubble.gradientStart,
                gradientEnd: bubble.gradientEnd,
                motionFactor: bubble.motionFactor
            )
        }
    }

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
}

private final class BingoDiaryGravityMonitor: ObservableObject {
    @Published var offset: CGSize = .zero

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private var referenceTilt: CGSize?

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        referenceTilt = nil
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let userAcceleration = motion?.userAcceleration
            let accelX = CGFloat(userAcceleration?.x ?? 0)
            let accelY = CGFloat(userAcceleration?.y ?? 0)

            // 以当前拿起手机的姿态作为“零重力位”，避免默认持续下坠。
            let currentTilt = CGSize(width: CGFloat(gravity.x), height: CGFloat(-gravity.y))
            if self.referenceTilt == nil {
                self.referenceTilt = currentTilt
            } else if abs(accelX) < 0.035 && abs(accelY) < 0.035 {
                // 慢速重基线：消除静置状态下的长期偏航，防止圆群持续单向漂移。
                let old = self.referenceTilt ?? .zero
                self.referenceTilt = CGSize(
                    width: old.width * 0.985 + currentTilt.width * 0.015,
                    height: old.height * 0.985 + currentTilt.height * 0.015
                )
            }
            let reference = self.referenceTilt ?? .zero

            // 归一化输入：相对倾斜 + 抖动冲量，范围控制在可模拟区间。
            var tiltX = (currentTilt.width - reference.width) * 3.4
            var tiltY = (currentTilt.height - reference.height) * 3.4
            if abs(tiltX) < 0.04 { tiltX = 0 }
            if abs(tiltY) < 0.04 { tiltY = 0 }
            let jerkX = accelX * 2.8
            let jerkY = CGFloat(-accelY) * 2.8
            let rawX = max(min(tiltX + jerkX, 2.35), -2.35)
            let rawY = max(min(tiltY + jerkY, 2.35), -2.35)
            DispatchQueue.main.async {
                // 保留足够响应性，避免重力信号被过度抹平。
                self.offset = CGSize(
                    width: self.offset.width * 0.10 + rawX * 0.90,
                    height: self.offset.height * 0.10 + rawY * 0.90
                )
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        referenceTilt = nil
        offset = .zero
    }
}

private struct BingoDiaryStatsListSheet: View {
    let title: String
    let completedStats: [BingoDiaryTaskCount]
    let timeoutStats: [BingoDiaryTaskCount]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: scaled(20, pad: 24)) {
                    diaryListSection(
                        title: L10n.tr("Completed tasks", zhHans: "完成任务", zhHant: "完成任務"),
                        items: completedStats
                    )

                    diaryListSection(
                        title: L10n.tr("Expired tasks", zhHans: "超时任务", zhHant: "超時任務"),
                        items: timeoutStats
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, scaled(20, pad: 26))
                .padding(.vertical, scaled(20, pad: 26))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NeumorphicColors.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }

    private func diaryListSection(title: String, items: [BingoDiaryTaskCount]) -> some View {
        VStack(alignment: .leading, spacing: scaled(12, pad: 14)) {
            Text(title)
                .font(.appSystem(size: scaled(17, pad: 19), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))

            if items.isEmpty {
                Text(L10n.tr("None", zhHans: "暂无", zhHant: "暫無"))
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "8A8179"))
            } else {
                VStack(spacing: scaled(10, pad: 12)) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Text(item.task)
                                .font(.appSystem(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "2B1A0D"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Text("\(item.count)")
                                .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "8A8179"))
                        }
                        .padding(.horizontal, scaled(16, pad: 18))
                        .padding(.vertical, scaled(14, pad: 16))
                        .background(
                            RoundedRectangle(cornerRadius: scaled(18, pad: 20), style: .continuous)
                                .fill(Color.white.opacity(0.92))
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BingoDiaryTaskDetailView: View {
    let task: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var pageTitle: String {
        L10n.tr("Task Details", zhHans: "任务详情", zhHant: "任務詳情")
    }

    private var totalCompletionsTitle: String {
        L10n.tr("Total Completions", zhHans: "总完成次数", zhHant: "總完成次數")
    }

    private var thisWeekTitle: String {
        L10n.tr("This Week", zhHans: "本周完成", zhHant: "本週完成")
    }

    private var recentActivityTitle: String {
        L10n.tr("Recent Activity", zhHans: "近期记录", zhHant: "近期記錄")
    }

    private var noActivityTitle: String {
        L10n.tr("No activity yet", zhHans: "暂无记录", zhHant: "暫無記錄")
    }

    private var normalizedTask: String {
        task.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activityRows: [(date: Date, count: Int)] {
        BingoDiaryStore.taskDailyCompletions(task: normalizedTask, limit: 30)
    }

    private var totalCompletions: Int {
        activityRows.reduce(0) { $0 + $1.count }
    }

    private var thisWeekCompletions: Int {
        BingoDiaryStore.taskCompletionsThisWeek(task: normalizedTask)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NeumorphicColors.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: scaled(18, pad: 22)) {
                    VStack(alignment: .leading, spacing: scaled(2, pad: 4)) {
                        Text(normalizedTask.isEmpty ? pageTitle : normalizedTask)
                            .font(.appSystem(size: scaled(24, pad: 30), weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "121A2B"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }

                    HStack(spacing: 0) {
                        metricColumn(
                            title: totalCompletionsTitle,
                            value: totalCompletions,
                            valueColor: Color(hex: "C5915E")
                        )

                        metricColumn(
                            title: thisWeekTitle,
                            value: thisWeekCompletions,
                            valueColor: Color(hex: "121A2B")
                        )
                    }
                    .padding(.vertical, scaled(20, pad: 24))
                    .background(
                        RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )

                    Text(recentActivityTitle)
                        .font(.appSystem(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "121A2B"))

                    if activityRows.isEmpty {
                        RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                            .fill(Color.white.opacity(0.9))
                            .frame(height: scaled(108, pad: 126))
                            .overlay(
                                Text(noActivityTitle)
                                    .font(.appSystem(size: scaled(15, pad: 18), weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(hex: "6C7889"))
                            )
                    } else {
                        VStack(spacing: scaled(12, pad: 14)) {
                            ForEach(activityRows, id: \.date) { row in
                                activityRow(date: row.date, count: row.count)
                            }
                        }
                    }
                }
                .padding(.horizontal, scaled(20, pad: 26))
                .padding(.top, scaled(12, pad: 18))
                .padding(.bottom, scaled(34, pad: 44))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            topBar
                .background(NeumorphicColors.background.opacity(0.96))
        }
    }

    private var topBar: some View {
        ZStack {
            Text(pageTitle)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                        .foregroundColor(Color(hex: "2B1A0D"))
                        .frame(width: scaled(40, pad: 44), height: scaled(40, pad: 44))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, scaled(12, pad: 20))
        .padding(.top, scaled(6, pad: 10))
        .padding(.bottom, scaled(4, pad: 8))
    }

    private func metricColumn(title: String, value: Int, valueColor: Color) -> some View {
        VStack(spacing: scaled(6, pad: 8)) {
            Text(title)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "4B5A6C"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("\(value)")
                .font(.appSystem(size: scaled(28, pad: 34), weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private func activityRow(date: Date, count: Int) -> some View {
        HStack(spacing: scaled(12, pad: 16)) {
            VStack(alignment: .leading, spacing: scaled(4, pad: 6)) {
                Text(activityDateText(from: date))
                    .font(.appSystem(size: scaled(16, pad: 20), weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "121A2B"))

                Text(activityCountText(count))
                    .font(.appSystem(size: scaled(14, pad: 17), weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "4B5A6C"))
            }

            Spacer(minLength: scaled(8, pad: 10))

            ZStack {
                Circle()
                    .fill(Color(hex: "C9DAE8"))
                Text("\(count)")
                    .font(.appSystem(size: scaled(14, pad: 18), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: scaled(60, pad: 68), height: scaled(60, pad: 68))
        }
        .padding(.horizontal, scaled(16, pad: 20))
        .padding(.vertical, scaled(14, pad: 16))
        .background(
            RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }

    private func activityDateText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter.string(from: date)
    }

    private func activityCountText(_ count: Int) -> String {
        let lang = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if lang.hasPrefix("zh-hans") || lang.hasPrefix("zh-cn") || lang == "zh" {
            return "完成 \(count) 次"
        }
        if lang.hasPrefix("zh-hant") || lang.hasPrefix("zh-tw") || lang.hasPrefix("zh-hk") {
            return "完成 \(count) 次"
        }
        return count == 1 ? "Completed 1 time" : "Completed \(count) times"
    }
}

private struct BingoDiaryDetailView: View {
    let entry: BingoDiaryEntry
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    BingoDiaryBoardView(board: entry.board)
                        .frame(maxWidth: isPadLayout ? 720 : .infinity)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text(detailTitle)
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }
            }
        }
    }

    private var detailTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.dateStyle = .long
        return formatter.string(from: entry.date)
    }
}

private struct BingoDiaryBoardView: View {
    let board: SavedBoard

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let totalSpacing = spacing * CGFloat(max(board.gridSize - 1, 0))
            let cellSize = (geo.size.width - 24 - totalSpacing) / CGFloat(max(board.gridSize, 1))

            VStack(spacing: spacing) {
                ForEach(0..<board.gridSize, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<board.gridSize, id: \.self) { col in
                            if row < board.cells.count && col < board.cells[row].count {
                                BingoDiaryCellView(
                                    cell: board.cells[row][col],
                                    isInBingoLine: isInCompletedLine(row: row, col: col),
                                    isLocked: isLocked(row: row, col: col),
                                    cellSize: cellSize
                                )
                            }
                        }
                    }
                }
            }
            .padding(8)
            .padding(12)
            .neumorphicConvex(radius: 20)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func isInCompletedLine(row: Int, col: Int) -> Bool {
        for line in board.completedLines {
            switch line {
            case .row(let r): if r == row { return true }
            case .column(let c): if c == col { return true }
            case .diagonalMain: if row == col { return true }
            case .diagonalAnti: if row + col == board.gridSize - 1 { return true }
            }
        }
        return false
    }

    private func isLocked(row: Int, col: Int) -> Bool {
        let activeForced = activeForcedPositions
        guard !activeForced.isEmpty else { return false }
        return !activeForced.contains(DiaryPosition(row: row, col: col))
    }

    private var activeForcedPositions: Set<DiaryPosition> {
        var positions: Set<DiaryPosition> = []

        for row in board.cells.indices {
            for col in board.cells[row].indices {
                let cell = board.cells[row][col]
                if cell.isForced && !cell.isCompleted && !cell.isEmpty {
                    positions.insert(DiaryPosition(row: row, col: col))
                }
            }
        }

        return positions
    }

    private struct DiaryPosition: Hashable {
        let row: Int
        let col: Int
    }
}

private struct BingoDiaryCellView: View {
    let cell: BingoCell
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat

    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var bingoSurfaceColor: Color { activeTheme.bingoSurfaceColor }
    private var bingoSurfaceShadowColor: Color { activeTheme.bingoSurfaceShadowColor }
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            backgroundSurface

            if isInBingoLine {
                bingoLineContent
            } else if !cell.isEmpty {
                VStack(spacing: 2) {
                    Text(cell.text)
                        .font(.appSystem(size: dynamicFontSize, weight: .medium))
                        .foregroundColor(isLocked ? NeumorphicColors.text.opacity(0.35) : NeumorphicColors.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(8)

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
    }

    private var dynamicFontSize: CGFloat {
        let maxBaseSize: CGFloat = isPadLayout ? 22.0 : 16.0
        let minimumSize: CGFloat = isPadLayout ? 11.0 : 9.0
        let baseSize = min(cellSize * (isPadLayout ? 0.24 : 0.22), maxBaseSize)
        return cell.text.count > 6 ? max(baseSize * (isPadLayout ? 0.84 : 0.8), minimumSize) : baseSize
    }

    private var bingoLineContent: some View {
        VStack(spacing: 4) {
            Text(cell.text)
                .font(.appSystem(size: dynamicFontSize, weight: .medium))
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

    private var backgroundSurface: some View {
        Group {
            if isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(bingoSurfaceColor)
                    .shadow(color: bingoSurfaceShadowColor.opacity(0.28), radius: 7, x: 4, y: 4)
                    .shadow(color: Color.white.opacity(0.42), radius: 7, x: -4, y: -4)
            } else if cell.isCompleted {
                Color.clear
                    .neumorphicConcave(radius: 12)
            } else {
                Color.clear
                    .neumorphicConvex(radius: 12)
            }
        }
        .overlay {
            if isLocked && !isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(NeumorphicColors.background.opacity(0.62))
            }
        }
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
                .font(.appSystem(size: size * 0.42, weight: .bold))
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
                .font(.appSystem(size: size * 0.42, weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
        }
        .frame(width: size, height: size)
    }
}

