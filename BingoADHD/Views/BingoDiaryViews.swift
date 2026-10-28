import SwiftUI
import Foundation

private enum BingoDiaryGravityPeriod: String, CaseIterable {
    case week
    case month
    case year

    var calendarComponent: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    var title: String {
        switch self {
        case .week: return L10n.tr("Week", zhHans: "周", zhHant: "週", ja: "週")
        case .month: return L10n.tr("Month", zhHans: "月", zhHant: "月", ja: "月")
        case .year: return L10n.tr("Year", zhHans: "年", zhHant: "年", ja: "年")
        }
    }
}

struct BingoDiaryScreen: View {
    private struct DiarySnapshot {
        var completedTaskStats: [BingoDiaryTaskCount]
        var completionDays: [BingoDiaryCompletionDay]
        var timeoutTaskStats: [BingoDiaryTaskCount]
        var totalCompletedTasks: Int
        var totalExpiredTasks: Int

        static let empty = DiarySnapshot(
            completedTaskStats: [],
            completionDays: [],
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
    @State private var isStatsListPresented = false
    @State private var selectedTaskDetail: BingoDiaryTaskCount?
    @State private var snapshot: DiarySnapshot = .empty
    @State private var bubbleLayoutCache: DiaryBubbleLayoutCache = .empty
    @State private var gravityLayoutCache: DiaryBubbleLayoutCache = .empty
    @AppStorage("bingoDiaryGravityModeEnabled") private var isGravityMode = false
    @AppStorage("bingoDiaryGravityPeriod") private var gravityPeriodRawValue = BingoDiaryGravityPeriod.month.rawValue
    @State private var isLoadingSnapshot = true
    @State private var statsSectionHeight: CGFloat = 0

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var diaryTitle: String {
        L10n.tr("Bingo Diary", zhHans: "Bingo 日记", zhHant: "Bingo 日記")
    }

    private var gravityPeriod: BingoDiaryGravityPeriod {
        BingoDiaryGravityPeriod(rawValue: gravityPeriodRawValue) ?? .month
    }

    private var gravityInterval: DateInterval {
        Calendar.current.dateInterval(of: gravityPeriod.calendarComponent, for: .now)
            ?? DateInterval(start: Calendar.current.startOfDay(for: .now), duration: 86_400)
    }

    private var gravityTaskStats: [BingoDiaryTaskCount] {
        BingoDiaryStore.completedTaskStats(from: snapshot.completionDays, in: gravityInterval).map {
            BingoDiaryTaskCount(task: $0.task, count: $0.count, firstCompletedAt: $0.firstCompletedAt)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let contentWidth = geometry.size.width
                let gravityTasks = gravityTaskStats
                let bottomSafeArea = max(geometry.safeAreaInsets.bottom, 0)
                let statsToBubbleSpacing = scaled(10, pad: 10)
                let gravityControlsHeight = scaled(44, pad: 48)
                let bottomContentPadding = isGravityMode ? 0 : scaled(36, pad: 44) + bottomSafeArea
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
                let gravityViewportHeight = max(
                    80,
                    geometry.size.height - resolvedStatsHeight - statsToBubbleSpacing
                    - gravityControlsHeight - statsToBubbleSpacing
                    - scaled(16, pad: 24)
                )
                let gravityLayoutSignature = makeGravityLayoutSignature(
                    contentWidth: contentWidth,
                    viewportHeight: gravityViewportHeight,
                    taskCounts: gravityTasks
                )
                let gravityLayout = gravityLayoutCache.signature == gravityLayoutSignature
                    ? gravityLayoutCache
                    : .empty
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
                            statsSummarySection(gravityTasks: gravityTasks)
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

                            if isGravityMode {
                                gravityPeriodControls
                                    .frame(height: gravityControlsHeight)
                                    .padding(.horizontal, scaled(20, pad: 28))
                            }

                            if isLoadingSnapshot {
                                ProgressView()
                                    .tint(NeumorphicColors.accent)
                                    .frame(maxWidth: .infinity, minHeight: isGravityMode ? gravityViewportHeight : bubbleViewportHeight)
                                    .padding(.horizontal, scaled(20, pad: 28))
                            } else if (isGravityMode ? gravityTasks.isEmpty : snapshot.completedTaskStats.isEmpty) {
                                Group {
                                    if isGravityMode {
                                        gravityEmptyState
                                    } else {
                                        emptyDiaryState
                                    }
                                }
                                .padding(.horizontal, scaled(20, pad: 28))
                            } else {
                                ZStack(alignment: .top) {
                                    if !bubbleLayout.bubbles.isEmpty {
                                        bubbleCloudSection(bubbleLayout)
                                            .opacity(isGravityMode ? 0 : 1)
                                            .allowsHitTesting(!isGravityMode)
                                            .accessibilityHidden(isGravityMode)
                                    }
                                    if isGravityMode {
                                        if gravityLayout.bubbles.isEmpty {
                                            ProgressView()
                                                .frame(maxWidth: .infinity, minHeight: gravityViewportHeight)
                                        } else {
                                            BingoDiaryGravityBubbleCloud(
                                                bubbles: gravityLayout.bubbles,
                                                width: contentWidth,
                                                height: gravityViewportHeight,
                                                isActive: !isStatsListPresented && selectedTaskDetail == nil,
                                                onBubbleTap: openBubbleDetail
                                            )
                                        }
                                    }
                                }
                                .frame(height: isGravityMode ? gravityViewportHeight : bubbleLayout.height, alignment: .top)
                                .clipped()
                            }
                        }
                        .padding(.top, scaled(16, pad: 24))
                        .padding(.bottom, bottomContentPadding)
                    }
                    .scrollDisabled(isGravityMode)
                }
                .onAppear {
                    refreshLayoutsIfNeeded(
                        flatSignature: bubbleLayoutSignature,
                        gravitySignature: gravityLayoutSignature,
                        contentWidth: contentWidth,
                        flatHeight: bubbleViewportHeight,
                        gravityHeight: gravityViewportHeight,
                        gravityTasks: gravityTasks
                    )
                }
                .onChange(of: isGravityMode) { _, _ in
                    refreshLayoutsIfNeeded(
                        flatSignature: bubbleLayoutSignature,
                        gravitySignature: gravityLayoutSignature,
                        contentWidth: contentWidth,
                        flatHeight: bubbleViewportHeight,
                        gravityHeight: gravityViewportHeight,
                        gravityTasks: gravityTasks
                    )
                }
                .onChange(of: gravityLayoutSignature) { _, _ in
                    refreshLayoutsIfNeeded(
                        flatSignature: bubbleLayoutSignature,
                        gravitySignature: gravityLayoutSignature,
                        contentWidth: contentWidth,
                        flatHeight: bubbleViewportHeight,
                        gravityHeight: gravityViewportHeight,
                        gravityTasks: gravityTasks
                    )
                }
                .onChange(of: bubbleLayoutSignature) { _, _ in
                    refreshLayoutsIfNeeded(
                        flatSignature: bubbleLayoutSignature,
                        gravitySignature: gravityLayoutSignature,
                        contentWidth: contentWidth,
                        flatHeight: bubbleViewportHeight,
                        gravityHeight: gravityViewportHeight,
                        gravityTasks: gravityTasks
                    )
                }
            }
            .ignoresSafeArea(.container, edges: isGravityMode ? .bottom : [])
            .toolbar(.hidden, for: .navigationBar)
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
                // Defer heavier diary data aggregation until transition finishes,
                // so entering this screen feels immediate.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    loadSnapshot()
                }
            }
            .navigationDestination(item: $selectedTaskDetail) { item in
                BingoDiaryTaskDetailView(task: item.task) {
                    loadSnapshot()
                }
            }
        }
    }

    private var headerBar: some View {
        ZStack {
            Text(diaryTitle)
                .appDynamicFont(size: scaled(20, pad: 24), weight: .bold, design: .rounded)
                .foregroundStyle(Color(hex: "2B1A0D"))

            HStack {
                nativeGlassIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: L10n.tr("Back", zhHans: "返回", zhHant: "返回", ja: "戻る"),
                    size: max(scaled(40, pad: 44), 44),
                    iconSize: scaled(18, pad: 20),
                    action: { dismiss() }
                )

                Spacer()

                nativeGlassIconButton(
                    systemName: isGravityMode ? "square.grid.2x2" : "gyroscope",
                    accessibilityLabel: isGravityMode
                        ? L10n.tr("Switch to flat view", zhHans: "切换到平铺模式", zhHant: "切換到平鋪模式", ja: "平面表示に切り替え")
                        : L10n.tr("Switch to gravity view", zhHans: "切换到重力模式", zhHant: "切換到重力模式", ja: "重力表示に切り替え"),
                    size: max(scaled(40, pad: 44), 44),
                    iconSize: scaled(20, pad: 23),
                    action: { isGravityMode.toggle() }
                )

                nativeGlassIconButton(
                    systemName: "clock.arrow.circlepath",
                    accessibilityLabel: L10n.tr("Task statistics", zhHans: "任务统计", zhHant: "任務統計", ja: "タスク統計"),
                    size: max(scaled(40, pad: 44), 44),
                    iconSize: scaled(20, pad: 23),
                    action: { isStatsListPresented = true }
                )
            }
        }
        .padding(.horizontal, scaled(12, pad: 20))
        .padding(.top, scaled(6, pad: 10))
        .padding(.bottom, scaled(4, pad: 8))
    }

    @ViewBuilder
    private func nativeGlassIconButton(
        systemName: String,
        accessibilityLabel: String,
        size: CGFloat,
        iconSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        } else {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.82), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private func statsSummarySection(gravityTasks: [BingoDiaryTaskCount]) -> some View {
        HStack(spacing: scaled(14, pad: 18)) {
            diarySummaryCard(
                value: isGravityMode ? gravityTasks.reduce(0) { $0 + $1.count } : snapshot.totalCompletedTasks,
                title: isGravityMode
                    ? L10n.tr("Completions", zhHans: "完成次数", zhHant: "完成次數", ja: "完了回数")
                    : L10n.tr("Tasks completed", zhHans: "已完成任务", zhHant: "已完成任務")
            )

            diarySummaryCard(
                value: isGravityMode ? gravityTasks.count : snapshot.totalExpiredTasks,
                title: isGravityMode
                    ? L10n.tr("Different tasks", zhHans: "不同任务", zhHant: "不同任務", ja: "タスクの種類")
                    : L10n.tr("Expired tasks", zhHans: "超时任务", zhHant: "超時任務")
            )
        }
    }

    private var gravityPeriodControls: some View {
        HStack {
            Spacer(minLength: 0)
            if #available(iOS 26.0, *) {
                gravityPeriodMenu
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else {
                gravityPeriodMenu
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var gravityPeriodMenu: some View {
        Menu {
            ForEach(BingoDiaryGravityPeriod.allCases, id: \.self) { period in
                Button {
                    gravityPeriodRawValue = period.rawValue
                } label: {
                    if gravityPeriod == period {
                        Label(period.title, systemImage: "checkmark")
                    } else {
                        Text(period.title)
                    }
                }
            }
        } label: {
            HStack(spacing: scaled(8, pad: 10)) {
                Text(gravityPeriod.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: scaled(10, pad: 12), weight: .semibold))
            }
            .appDynamicFont(size: scaled(14, pad: 16), weight: .semibold, design: .rounded)
            .foregroundStyle(Color(hex: "2B1A0D"))
            .frame(minWidth: scaled(70, pad: 80), minHeight: 44)
            .padding(.horizontal, scaled(8, pad: 10))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadSnapshot() {
        isLoadingSnapshot = true
        DispatchQueue.global(qos: .userInitiated).async {
            let completionDays = BingoDiaryStore.completionDays()
            let completed = BingoDiaryStore.completedTaskStats(from: completionDays).map {
                BingoDiaryTaskCount(task: $0.task, count: $0.count, firstCompletedAt: $0.firstCompletedAt)
            }
            let timeout = BingoTimeoutStore.allTimeTimeoutTaskCounts().map {
                BingoDiaryTaskCount(task: $0.task, count: $0.count, firstCompletedAt: nil)
            }
            let snapshot = DiarySnapshot(
                completedTaskStats: completed,
                completionDays: completionDays,
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

    private func makeGravityLayoutSignature(
        contentWidth: CGFloat,
        viewportHeight: CGFloat,
        taskCounts: [BingoDiaryTaskCount]
    ) -> String {
        let stats = taskCounts.map { "\($0.id)|\($0.count)" }.joined(separator: "||")
        return "\(Int(contentWidth.rounded()))x\(Int(viewportHeight.rounded()))#\(stats)"
    }

    private func refreshLayoutsIfNeeded(
        flatSignature: String,
        gravitySignature: String,
        contentWidth: CGFloat,
        flatHeight: CGFloat,
        gravityHeight: CGFloat,
        gravityTasks: [BingoDiaryTaskCount]
    ) {
        if isGravityMode {
            guard gravityLayoutCache.signature != gravitySignature else { return }
            let bubbles = BingoDiaryBubbleLayout.gravityLayout(
                taskCounts: gravityTasks,
                width: contentWidth,
                height: gravityHeight
            )
            gravityLayoutCache = DiaryBubbleLayoutCache(
                signature: gravitySignature,
                bubbles: bubbles,
                width: contentWidth,
                height: gravityHeight,
                isHorizontallyOverflowing: false
            )
        } else {
            refreshBubbleLayoutIfNeeded(
                signature: flatSignature,
                contentWidth: contentWidth,
                viewportHeight: flatHeight
            )
        }
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

    private func bubbleCloudSection(_ bubbleLayout: DiaryBubbleLayoutCache) -> some View {
        BingoDiaryBubbleCloudSection(
            bubbles: bubbleLayout.bubbles,
            width: bubbleLayout.width,
            height: bubbleLayout.height,
            isHorizontallyOverflowing: bubbleLayout.isHorizontallyOverflowing,
            isActive: !isGravityMode && !isStatsListPresented && selectedTaskDetail == nil
        ) { bubble in
            openBubbleDetail(bubble)
        }
    }

    private func openBubbleDetail(_ bubble: BingoDiaryBubble) {
        selectedTaskDetail = snapshot.completedTaskStats.first(where: { $0.id == bubble.id })
            ?? BingoDiaryTaskCount(task: bubble.task, count: bubble.count, firstCompletedAt: nil)
    }

    private func diarySummaryCard(value: Int, title: String) -> some View {
        VStack(spacing: scaled(6, pad: 8)) {
            Text("\(value)")
                .appDynamicFont(size: scaled(54, pad: 68), weight: .bold, design: .rounded)
                .foregroundStyle(Color(hex: "2B1A0D"))
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(title)
                .appDynamicFont(size: scaled(13, pad: 15), weight: .semibold, design: .rounded)
                .foregroundStyle(Color(hex: "8A8179"))
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
                .appDynamicFont(size: scaled(17, pad: 20), weight: .bold, design: .rounded)
                .foregroundStyle(Color(hex: "2B1A0D"))

            Text(L10n.tr("Complete a few tasks and they will appear here.", zhHans: "完成一些任务后，它们会出现在这里。", zhHant: "完成一些任務後，它們會出現在這裡。"))
                .appDynamicFont(size: scaled(13, pad: 15), weight: .medium, design: .rounded)
                .foregroundStyle(Color(hex: "8A8179"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, scaled(48, pad: 64))
        .background(
            RoundedRectangle(cornerRadius: scaled(24, pad: 28), style: .continuous)
                .fill(Color.white.opacity(0.75))
        )
    }

    private var gravityEmptyState: some View {
        VStack(spacing: scaled(10, pad: 14)) {
            Text(L10n.tr("No completions in this period", zhHans: "这个周期还没有完成记录", zhHant: "這個週期還沒有完成紀錄", ja: "この期間の完了記録はありません"))
                .appDynamicFont(size: scaled(17, pad: 20), weight: .bold, design: .rounded)
                .foregroundStyle(Color(hex: "2B1A0D"))
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
    static let defaultValue: CGFloat = 0

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
