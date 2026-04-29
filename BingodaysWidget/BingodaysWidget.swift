import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

private struct BingodaysWidgetEntry: TimelineEntry {
    let date: Date
    let board: SavedBoard
    let usageDays: Int
    let boardCountdownEndsAt: Date?
}

private struct BingodaysWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BingodaysWidgetEntry {
        BingodaysWidgetEntry(
            date: .now,
            board: .sample,
            usageDays: 7,
            boardCountdownEndsAt: Calendar.current.date(byAdding: .hour, value: 3, to: .now)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BingodaysWidgetEntry) -> Void) {
        completion(
            BingodaysWidgetEntry(
                date: .now,
                board: BingoBoardStore.loadBoard() ?? .sample,
                usageDays: BingoDiaryStore.consecutiveBingoDays(),
                boardCountdownEndsAt: BingoBoardStore.loadBoardCountdownEndsAt()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BingodaysWidgetEntry>) -> Void) {
        let entry = BingodaysWidgetEntry(
            date: .now,
            board: BingoBoardStore.loadBoard() ?? .sample,
            usageDays: BingoDiaryStore.consecutiveBingoDays(),
            boardCountdownEndsAt: BingoBoardStore.loadBoardCountdownEndsAt()
        )
        let nextRefresh: Date
        if let countdownEndsAt = entry.boardCountdownEndsAt, countdownEndsAt > .now {
            nextRefresh = .now.addingTimeInterval(1)
        } else {
            nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        }
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

@main
struct BingodaysWidgets: WidgetBundle {
    var body: some Widget {
        BingodaysCountdownWidget()
        BingodaysLargeWidget()
        if #available(iOSApplicationExtension 17.0, *) {
            BingodaysFinalHourLiveActivityWidget()
        }
    }
}

struct BingodaysCountdownWidget: Widget {
    private let kind = "BingodaysCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BingodaysWidgetProvider()) { entry in
            BingodaysCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.widgetCountdownName)
        .description(L10n.widgetCountdownDescription)
        .supportedFamilies([.systemSmall])
    }
}

struct BingodaysLargeWidget: Widget {
    private let kind = "BingodaysLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BingodaysWidgetProvider()) { entry in
            BingodaysLargeWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.widgetBoardName)
        .description(L10n.widgetBoardDescription)
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct BingodaysCountdownWidgetView: View {
    let entry: BingodaysWidgetEntry

    var body: some View {
        ZStack {
            NeumorphicColors.background

            VStack(spacing: 14) {
                if let countdownText = countdownText {
                    Text(L10n.dontForget)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.44))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(countdownText)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(NeumorphicColors.accent)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)

                    Text(L10n.doTask)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(NeumorphicColors.background)
                                .shadow(color: NeumorphicColors.darkShadow.opacity(0.2), radius: 8, x: 4, y: 4)
                                .shadow(color: Color.white.opacity(0.8), radius: 8, x: -4, y: -4)
                        )
                } else {
                    Text(L10n.dontForget)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.44))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(L10n.noTimer)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Text(L10n.doTask)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(NeumorphicColors.background)
                                .shadow(color: NeumorphicColors.darkShadow.opacity(0.2), radius: 8, x: 4, y: 4)
                                .shadow(color: Color.white.opacity(0.8), radius: 8, x: -4, y: -4)
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
        .containerBackground(for: .widget) {
            NeumorphicColors.background
        }
    }

    private var countdownText: String? {
        guard let endsAt = entry.boardCountdownEndsAt, endsAt > entry.date else {
            return nil
        }

        let remainingSeconds = max(Int(endsAt.timeIntervalSince(entry.date)), 0)
        let hours = min(remainingSeconds / 3600, 99)
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

private struct BingodaysLargeWidgetView: View {
    let entry: BingodaysWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var board: SavedBoard { entry.board }
    private var totalTasks: Int { board.cells.flatMap(\.self).filter { !$0.isEmpty }.count }
    private var completedTasks: Int { board.cells.flatMap(\.self).filter(\.isCompleted).count }
    private var mediumItems: [MediumDisplayItem] {
        let candidates = board.cells.enumerated().flatMap { boardRow in
            let (row, rowCells) = boardRow

            return Array(rowCells.enumerated()).compactMap { (item: (offset: Int, element: BingoCell)) -> MediumDisplayItem? in
                let col = item.offset
                let cell = item.element
                guard !cell.isEmpty else { return nil }
                return MediumDisplayItem(row: row, col: col, cell: cell)
            }
        }

        let sorted = candidates.sorted {
            stableMediumOrder(for: $0) < stableMediumOrder(for: $1)
        }

        let selected = Array(sorted.prefix(4))
        if selected.count == 4 {
            return selected
        }

        return selected + Array(repeating: MediumDisplayItem.empty, count: 4 - selected.count)
    }

    var body: some View {
        ZStack {
            NeumorphicColors.background

            if family == .systemMedium {
                mediumView
            } else {
                VStack(spacing: 0) {
                    boardView
                }
                .padding(18)
            }
        }
        .containerBackground(for: .widget) {
            NeumorphicColors.background
        }
    }

    private var mediumView: some View {
        GeometryReader { proxy in
            let verticalPadding: CGFloat = 18
            let horizontalPadding: CGFloat = 20
            let spacing: CGFloat = 12
            let contentHeight = max(proxy.size.height - verticalPadding * 2, 0)
            let topHeight = max((contentHeight - spacing) * 0.34, 58)
            let bottomHeight = max(contentHeight - topHeight - spacing, 104)

            VStack(spacing: spacing) {
                HStack(spacing: 12) {
                    mediumMetricCard(
                        value: "\(entry.usageDays)",
                        title: L10n.streakDays
                    )

                    mediumMetricCard(
                        value: "\(completedTasks)",
                        title: L10n.bingoCount
                    )
                }
                .frame(height: topHeight)

                mediumGrid
                    .frame(height: bottomHeight)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func mediumMetricCard(value: String, title: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.72))

            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .multilineTextAlignment(.center)
        .padding(.top, 43)
    }

    private var mediumGrid: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let availableWidth = proxy.size.width
            let availableHeight = proxy.size.height
            let cellSize = min((availableWidth - spacing * 3) / 4, availableHeight)
            let gridWidth = cellSize * 4 + spacing * 3

            HStack(spacing: spacing) {
                ForEach(0..<4, id: \.self) { index in
                    let item = mediumItems[index]

                    WidgetBingoCellView(
                        cell: item.cell,
                        isInBingoLine: item.isActive ? isInCompletedLine(row: item.row, col: item.col) : false,
                        isLocked: item.isActive ? isLocked(row: item.row, col: item.col) : false,
                        cellSize: cellSize,
                        isFirstCell: false
                    )
                }
            }
            .frame(width: gridWidth, height: cellSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var boardView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let boardSide = min(geo.size.width, geo.size.height)
            let totalSpacing = spacing * CGFloat(max(board.gridSize - 1, 0))
            let cellSize = (boardSide - totalSpacing) / CGFloat(board.gridSize)

            VStack(spacing: spacing) {
                ForEach(0..<board.gridSize, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<board.gridSize, id: \.self) { col in
                            let cell = cellAt(row: row, col: col)

                            WidgetBingoCellView(
                                cell: cell,
                                isInBingoLine: isInCompletedLine(row: row, col: col),
                                isLocked: isLocked(row: row, col: col),
                                cellSize: cellSize,
                                isFirstCell: row == 0 && col == 0
                            )
                        }
                    }
                }
            }
            .frame(width: boardSide, height: boardSide)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cellAt(row: Int, col: Int) -> BingoCell {
        guard row < board.cells.count, col < board.cells[row].count else {
            return BingoCell()
        }
        return board.cells[row][col]
    }

    private func isInCompletedLine(row: Int, col: Int) -> Bool {
        let size = board.gridSize

        for line in board.completedLines {
            switch line {
            case .row(let r):
                if r == row { return true }
            case .column(let c):
                if c == col { return true }
            case .diagonalMain:
                if row == col { return true }
            case .diagonalAnti:
                if row + col == size - 1 { return true }
            }
        }

        return false
    }

    private func isLocked(row: Int, col: Int) -> Bool {
        let activeForced = board.cells.flatMap(\.self).filter { $0.isForced && !$0.isCompleted && !$0.isEmpty }
        guard !activeForced.isEmpty else {
            return false
        }

        let cell = cellAt(row: row, col: col)
        return !(cell.isForced && !cell.isCompleted && !cell.isEmpty)
    }

    private func stableMediumOrder(for item: MediumDisplayItem) -> Int {
        var hasher = Hasher()
        hasher.combine(Int(entry.date.timeIntervalSince1970 / 1800))
        hasher.combine(item.cell.id)
        return hasher.finalize()
    }
}

private struct MediumDisplayItem {
    let row: Int
    let col: Int
    let cell: BingoCell
    let isActive: Bool

    init(row: Int, col: Int, cell: BingoCell, isActive: Bool = true) {
        self.row = row
        self.col = col
        self.cell = cell
        self.isActive = isActive
    }

    static let empty = MediumDisplayItem(row: 0, col: 0, cell: BingoCell(), isActive: false)
}

private struct WidgetBingoCellView: View {
    let cell: BingoCell
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat
    let isFirstCell: Bool

    private var activeTheme: AppTheme { AppTheme.current }
    private var bingoSurfaceColor: Color { activeTheme.bingoSurfaceColor }
    private var bingoSurfaceShadowColor: Color { activeTheme.bingoSurfaceShadowColor }

    var body: some View {
        ZStack {
            backgroundSurface

            if isInBingoLine {
                bingoLineContent
            } else if !cell.isEmpty {
                VStack(spacing: 2) {
                    Text(cell.text)
                        .font(.system(size: dynamicFontSize, weight: .medium))
                        .foregroundColor(cellTextColor)
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
        let baseSize = min(cellSize * 0.22, 16.0)
        let textLength = cell.text.count
        if textLength > 6 {
            return max(baseSize * 0.8, 9)
        }
        return baseSize
    }

    private var cellTextColor: Color {
        isLocked ? NeumorphicColors.text.opacity(0.35) : NeumorphicColors.text
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
                    .neumorphicConvex(radius: 12, isPressed: false)
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
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor((isLarge || usesGoldSurface) ? .white : NeumorphicColors.accent)
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

#if canImport(ActivityKit)
@available(iOSApplicationExtension 17.0, *)
struct BingodaysFinalHourLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BingodaysFinalHourActivityAttributes.self) { context in
            liveActivityBody(for: context.state)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    liveActivityBody(for: context.state)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            } compactLeading: {
                compactReminderIcon
            } compactTrailing: {
                Text(context.state.compactText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            } minimal: {
                compactReminderIcon
            }
        }
    }

    private func liveActivityBody(for state: BingodaysFinalHourActivityAttributes.ContentState) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                reminderIcon
                    .frame(width: 22, height: 22)
                Text(L10n.finalHourLiveTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(state.progressText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)
            }

            Text(state.message)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var reminderIcon: some View {
        Image("DynamicIslandLogo")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 24, height: 24)
            .offset(x: 10)
    }

    private var compactReminderIcon: some View {
        Image("DynamicIslandLogo")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 20, height: 20)
            .offset(x: 10)
    }
}
#endif

private extension SavedBoard {
    static let sample = SavedBoard(
        gridSize: 3,
        cells: [
            [
                BingoCell(text: "Drink Water", isCompleted: true),
                BingoCell(text: "Brush Teeth"),
                BingoCell(text: "Shower")
            ],
            [
                BingoCell(text: "Eat"),
                BingoCell(text: "Sweep", isForced: true),
                BingoCell(text: "Laundry")
            ],
            [
                BingoCell(text: "Walk"),
                BingoCell(text: "Stretch"),
                BingoCell(text: "Read")
            ]
        ],
        completedLines: []
    )
}
