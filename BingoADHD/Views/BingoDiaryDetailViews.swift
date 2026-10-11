import SwiftUI
import Foundation

struct BingoDiaryStatsListSheet: View {
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.done)
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.modalAccent)
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

struct BingoDiaryTaskDetailView: View {
    let task: String

    private struct TaskDetailSnapshot {
        var activityRows: [(date: Date, count: Int)]
        var totalCompletions: Int
        var thisWeekCompletions: Int

        static let empty = TaskDetailSnapshot(
            activityRows: [],
            totalCompletions: 0,
            thisWeekCompletions: 0
        )
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var snapshot: TaskDetailSnapshot = .empty

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
                            value: snapshot.totalCompletions,
                            valueColor: Color(hex: "C5915E")
                        )

                        metricColumn(
                            title: thisWeekTitle,
                            value: snapshot.thisWeekCompletions,
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

                    if snapshot.activityRows.isEmpty {
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
                            ForEach(snapshot.activityRows, id: \.date) { row in
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
        .onAppear {
            loadSnapshot()
        }
        .onChange(of: normalizedTask) { _, _ in
            loadSnapshot()
        }
    }

    private func loadSnapshot() {
        let task = normalizedTask
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = BingoDiaryStore.taskDailyCompletions(task: task, limit: 30)
            let snapshot = TaskDetailSnapshot(
                activityRows: rows,
                totalCompletions: rows.reduce(0) { $0 + $1.count },
                thisWeekCompletions: BingoDiaryStore.taskCompletionsThisWeek(task: task)
            )
            DispatchQueue.main.async {
                self.snapshot = snapshot
            }
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
                    LiquidGlassIconBadge(
                        systemName: "chevron.left",
                        size: scaled(40, pad: 44),
                        iconSize: scaled(18, pad: 20),
                        foregroundColor: Color(hex: "2B1A0D")
                    )
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.done)
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.modalAccent)
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
