import SwiftUI
import Foundation

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

    private struct DiaryBubbleLayoutCache {
        var signature: String
        var bubbles: [BingoDiaryBubble]
        var width: CGFloat
        var height: CGFloat
        var isHorizontallyOverflowing: Bool

        static let empty = DiaryBubbleLayoutCache(
            signature: "",
            bubbles: [],
            width: 0,
            height: 0,
            isHorizontallyOverflowing: false
        )
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var gravityMonitor = BingoDiaryGravityMonitor()
    @State private var isStatsListPresented = false
    @State private var selectedTaskDetail: BingoDiaryTaskCount?
    @State private var snapshot: DiarySnapshot = .empty
    @State private var bubbleLayoutCache: DiaryBubbleLayoutCache = .empty
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
                let bottomSafeArea = max(geometry.safeAreaInsets.bottom, 0)
                let statsToBubbleSpacing = scaled(10, pad: 10)
                let bottomContentPadding = scaled(36, pad: 44) + bottomSafeArea
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
                    - bottomContentPadding
                    - geometry.safeAreaInsets.top
                    - scaled(56, pad: 68)   // header + safe margin
                )
                let bubbleLayoutSignature = makeBubbleLayoutSignature(
                    contentWidth: contentWidth,
                    viewportHeight: bubbleViewportHeight
                )
                let bubbleLayout = bubbleLayoutCache.signature == bubbleLayoutSignature
                    ? bubbleLayoutCache
                    : .empty

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
                                bubbleCloudSection(bubbleLayout)
                            }
                        }
                        .padding(.top, scaled(16, pad: 24))
                        .padding(.bottom, bottomContentPadding)
                    }
                }
                .onAppear {
                    refreshBubbleLayoutIfNeeded(
                        signature: bubbleLayoutSignature,
                        contentWidth: contentWidth,
                        viewportHeight: bubbleViewportHeight
                    )
                }
                .onChange(of: bubbleLayoutSignature) { _, newSignature in
                    refreshBubbleLayoutIfNeeded(
                        signature: newSignature,
                        contentWidth: contentWidth,
                        viewportHeight: bubbleViewportHeight
                    )
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
                    LiquidGlassIconBadge(
                        systemName: "chevron.left",
                        size: scaled(40, pad: 44),
                        iconSize: scaled(18, pad: 20),
                        foregroundColor: Color(hex: "2B1A0D")
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    isStatsListPresented = true
                } label: {
                    LiquidGlassIconBadge(
                        imageName: "HistoryIcon",
                        size: scaled(40, pad: 44),
                        iconSize: scaled(24, pad: 27)
                    )
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
                totalCompletedTasks: completed.reduce(0) { $0 + $1.count },
                totalExpiredTasks: timeout.reduce(0) { $0 + $1.count }
            )
            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.isLoadingSnapshot = false
            }
        }
    }

    private func makeBubbleLayoutSignature(contentWidth: CGFloat, viewportHeight: CGFloat) -> String {
        let roundedWidth = Int(contentWidth.rounded())
        let roundedHeight = Int(viewportHeight.rounded())
        let statsSignature = snapshot.completedTaskStats
            .prefix(80)
            .map { item in
                let firstCompletedAt = Int((item.firstCompletedAt?.timeIntervalSince1970 ?? -1).rounded())
                return "\(item.id)|\(item.count)|\(firstCompletedAt)"
            }
            .joined(separator: "||")
        return "\(roundedWidth)x\(roundedHeight)#\(statsSignature)"
    }

    private func refreshBubbleLayoutIfNeeded(
        signature: String,
        contentWidth: CGFloat,
        viewportHeight: CGFloat
    ) {
        guard bubbleLayoutCache.signature != signature else { return }
        let layout = BingoDiaryBubbleLayout.layout(
            taskCounts: snapshot.completedTaskStats,
            width: contentWidth,
            viewportHeight: viewportHeight,
            maximumBubbleCount: 80
        )
        bubbleLayoutCache = DiaryBubbleLayoutCache(
            signature: signature,
            bubbles: layout.bubbles,
            width: layout.width,
            height: layout.height,
            isHorizontallyOverflowing: layout.isHorizontallyOverflowing
        )
    }

    @ViewBuilder
    private func bubbleCloudSection(_ bubbleLayout: DiaryBubbleLayoutCache) -> some View {
        let cloud = BingoDiaryBubbleCloud(
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

        if bubbleLayout.isHorizontallyOverflowing {
            ScrollView(.horizontal, showsIndicators: false) {
                cloud
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
        } else {
            cloud
                .frame(maxWidth: .infinity)
                .frame(height: bubbleLayout.height)
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

struct BingoDiaryTaskCount: Identifiable, Equatable, Hashable {
    let task: String
    let count: Int
    let firstCompletedAt: Date?

    var id: String { task }
}
