import SwiftUI
import WidgetKit
import AppIntents

private struct WidgetBoardPanel: Identifiable {
    let id: UUID
    let name: String
    let board: SavedBoard
    let countdownEndsAt: Date?
    let nextResetAt: Date?
}

private struct BingodaysWidgetEntry: TimelineEntry {
    let date: Date
    let panels: [WidgetBoardPanel]
    let selectedPanelID: UUID?
    let usageDays: Int

    private var resolvedSelectedIndex: Int {
        guard !panels.isEmpty else { return 0 }
        guard let selectedPanelID,
              let index = panels.firstIndex(where: { $0.id == selectedPanelID }) else {
            return 0
        }
        return index
    }

    var selectedPanelIndex: Int { resolvedSelectedIndex }

    var board: SavedBoard {
        guard !panels.isEmpty else { return .sample }
        return panels[resolvedSelectedIndex].board
    }

    var boardCountdownEndsAt: Date? {
        guard !panels.isEmpty else { return nil }
        return panels[resolvedSelectedIndex].countdownEndsAt
    }
}

private struct BingodaysWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BingodaysWidgetEntry {
        BingodaysWidgetEntry(
            date: .now,
            panels: [
                WidgetBoardPanel(
                    id: UUID(),
                    name: L10n.boardDefaultName(1),
                    board: .sample,
                    countdownEndsAt: Calendar.current.date(byAdding: .hour, value: 3, to: .now),
                    nextResetAt: nil
                )
            ],
            selectedPanelID: nil,
            usageDays: 7
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BingodaysWidgetEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BingodaysWidgetEntry>) -> Void) {
        // The main app owns the CloudKit mirror and projects imported data into the
        // App Group before reloading WidgetKit. Keeping the timeline provider read-only
        // avoids opening a second CloudKit/Core Data stack for the same SQLite store.
        let now = Date()
        let entry = makeEntry(at: now)
        let nextRefresh = nextRefreshDate(for: entry, at: now)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry(at date: Date) -> BingodaysWidgetEntry {
        let snapshot = WidgetTaskEventMerge.applying(
            WidgetTaskSyncStore.load(),
            to: BingoBoardStore.loadNamedBoardsSnapshot()
        )
        let panels = snapshot.boards.map { makePanel(from: $0, at: date) }

        let resolvedPanels: [WidgetBoardPanel]
        let selectedPanelID: UUID?
        if panels.isEmpty {
            resolvedPanels = [
                WidgetBoardPanel(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                    name: L10n.boardDefaultName(1),
                    board: projectedBoard(BingoBoardStore.loadBoard() ?? .sample, at: date),
                    countdownEndsAt: BingoBoardStore.loadBoardCountdownEndsAt(),
                    nextResetAt: Calendar.current.date(
                        byAdding: .day,
                        value: 1,
                        to: Calendar.current.startOfDay(for: date)
                    )
                )
            ]
            selectedPanelID = resolvedPanels.first?.id
        } else {
            resolvedPanels = panels
            let preferredSelectedID = WidgetPanelSelectionStore.loadSelectedPanelID() ?? snapshot.selectedBoardID
            if let preferredSelectedID,
               resolvedPanels.contains(where: { $0.id == preferredSelectedID }) {
                selectedPanelID = preferredSelectedID
            } else {
                selectedPanelID = resolvedPanels.first?.id
                WidgetPanelSelectionStore.saveSelectedPanelID(selectedPanelID)
            }
        }

        return BingodaysWidgetEntry(
            date: date,
            panels: resolvedPanels,
            selectedPanelID: selectedPanelID,
            usageDays: BingoDiaryStore.consecutiveBingoDays()
        )
    }

    private func makePanel(from namedBoard: BingoBoardStore.NamedBoard, at date: Date) -> WidgetBoardPanel {
        let preparedBoard = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(namedBoard, now: date)

        return WidgetBoardPanel(
            id: preparedBoard.id,
            name: preparedBoard.name,
            board: projectedBoard(preparedBoard.board, at: date),
            countdownEndsAt: preparedBoard.countdownEndsAt,
            nextResetAt: BoardResetRuleEngine.nextScheduledResetTime(
                for: preparedBoard,
                after: date
            )
        )
    }

    private func projectedBoard(_ board: SavedBoard, at date: Date) -> SavedBoard {
        let gridSize = min(max(board.gridSize, 2), BoardEngine.maxGridSize)
        let fullBoard = BoardEngine.expandedBoardCache(from: board)
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoard,
            size: gridSize,
            referenceDate: date
        )
        let completedLines = BoardEngine.completedLines(in: visibleCells, size: gridSize)

        return SavedBoard(
            gridSize: gridSize,
            cells: visibleCells,
            completedLines: completedLines,
            fullBoardCells: fullBoard
        )
    }

    private func nextRefreshDate(for entry: BingodaysWidgetEntry, at date: Date) -> Date {
        var candidates: [Date] = [
            Calendar.current.date(byAdding: .minute, value: 15, to: date) ?? date.addingTimeInterval(900)
        ]

        if let countdownEndsAt = entry.boardCountdownEndsAt, countdownEndsAt > date {
            candidates.append(countdownEndsAt)
        }

        candidates.append(contentsOf: entry.panels.compactMap(\.nextResetAt).filter { $0 > date })

        if let contentRefresh = nextBoardContentRefreshDate(in: entry.panels.map(\.board), after: date) {
            candidates.append(contentRefresh)
        }

        return candidates.min() ?? date.addingTimeInterval(900)
    }

    private func nextBoardContentRefreshDate(in boards: [SavedBoard], after date: Date) -> Date? {
        var candidates: [Date] = []

        for board in boards {
            let cells = board.fullBoardCells ?? board.cells
            for row in cells {
                for cell in row where cell.hasStoredTask {
                    if let countdownEndsAt = cell.countdownEndsAt, countdownEndsAt > date {
                        candidates.append(countdownEndsAt)
                    }

                    if let start = cell.occurrenceStartVisibleAt(on: date), start > date {
                        candidates.append(start)
                    }

                    if let end = cell.occurrenceEndVisibleAt(on: date),
                       end > date,
                       cell.isCurrentlyTappable(on: date) {
                        candidates.append(end)
                    }
                }
            }
        }

        return candidates.min()
    }
}

@main
struct BingodaysWidgets: WidgetBundle {
    var body: some Widget {
        BingodaysCountdownWidget()
        BingodaysLargeWidget()
    }
}

struct BingodaysCountdownWidget: Widget {
    private let kind = BingodaysWidgetKind.countdown

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
    private let kind = BingodaysWidgetKind.board

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
                if let countdownRange = countdownRange {
                    Text(L10n.dontForget)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.44))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(timerInterval: countdownRange, countsDown: true, showsHours: true)
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

    private var countdownRange: ClosedRange<Date>? {
        guard let endsAt = entry.boardCountdownEndsAt, endsAt > entry.date else {
            return nil
        }
        return entry.date...endsAt
    }
}

private struct BingodaysLargeWidgetView: View {
    let entry: BingodaysWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var board: SavedBoard { entry.board }
    private var hasMultiplePanels: Bool { entry.panels.count > 1 }
    private var panelIndex: Int { min(max(entry.selectedPanelIndex, 0), max(entry.panels.count - 1, 0)) }
    private var activePanelID: UUID? {
        guard entry.panels.indices.contains(panelIndex) else { return nil }
        return entry.panels[panelIndex].id
    }
    private var activePanelName: String {
        guard entry.panels.indices.contains(panelIndex) else { return L10n.boardDefaultName(1) }
        return entry.panels[panelIndex].name
    }
    private var widgetBackgroundColor: Color {
        family == .systemLarge ? Color(hex: "FAF9F3") : NeumorphicColors.background
    }
    private var largeHorizontalPadding: CGFloat { 18 }
    private var largeSwitchSideRail: CGFloat { 34 }
    private var largeSwitchButtonSize: CGFloat { 30 }
    private var largeSwitchOutwardOffset: CGFloat { 7 }
    private var largeTitleFontSize: CGFloat { 14 }
    private var largeTitleHeight: CGFloat { 18 }
    private var largeTitleYOffset: CGFloat { -15 }
    private var largePageIndicatorHeight: CGFloat { 6 }
    private var largePageIndicatorYOffset: CGFloat { 25 }
    private var largePanelSpacing: CGFloat { 8 }
    private var totalTasks: Int { board.cells.flatMap(\.self).filter { !$0.isEmpty }.count }
    private var completedTasks: Int {
        board.cells.flatMap(\.self).filter {
            $0.isCompleted && !$0.isEmpty && !$0.isDisplayOnlyInactive
        }.count
    }
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
            widgetBackgroundColor

            if family == .systemMedium {
                mediumView
            } else {
                largeView
            }
        }
        .containerBackground(for: .widget) {
            widgetBackgroundColor
        }
    }

    private var largeView: some View {
        GeometryReader { proxy in
            let topPadding: CGFloat = hasMultiplePanels ? 12 : 18
            let bottomPadding: CGFloat = hasMultiplePanels ? 12 : 18
            let maxBoardWidth = max(proxy.size.width - largeHorizontalPadding * 2, 0)
            let maxBoardHeight = max(
                proxy.size.height
                    - topPadding
                    - bottomPadding
                    - (hasMultiplePanels ? largeTitleHeight + largePageIndicatorHeight + largePanelSpacing * 2 : 0),
                0
            )
            let sideRailBoardWidth = hasMultiplePanels ? max(proxy.size.width - largeSwitchSideRail * 2, 0) : maxBoardWidth
            let boardSide = max(min(min(maxBoardWidth, maxBoardHeight), sideRailBoardWidth), 0)
            let boardMargin = max((proxy.size.width - boardSide) / 2, 0)
            let switchCenterX = boardMargin / 2

            ZStack {
                VStack(spacing: hasMultiplePanels ? largePanelSpacing : 0) {
                    if hasMultiplePanels {
                        Text(activePanelName)
                            .font(.system(size: largeTitleFontSize, weight: .bold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: largeTitleHeight)
                            .offset(y: largeTitleYOffset)
                    }

                    boardView(for: board)
                        .frame(width: boardSide, height: boardSide)

                    if hasMultiplePanels {
                        pageIndicator
                            .frame(height: largePageIndicatorHeight)
                            .offset(y: largePageIndicatorYOffset)
                    }
                }
                .frame(
                    width: max(proxy.size.width - largeHorizontalPadding * 2, 0),
                    height: max(proxy.size.height - topPadding - bottomPadding, 0)
                )
                .padding(.horizontal, largeHorizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)

                if hasMultiplePanels {
                    boardSwitchButton(systemImage: "chevron.left", step: -1)
                        .position(x: switchCenterX - largeSwitchOutwardOffset, y: proxy.size.height / 2)

                    boardSwitchButton(systemImage: "chevron.right", step: 1)
                        .position(x: proxy.size.width - switchCenterX + largeSwitchOutwardOffset, y: proxy.size.height / 2)
                }
            }
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

                    widgetCellButton(
                        cell: item.cell,
                        row: item.row,
                        col: item.col,
                        isActive: item.isActive,
                        isInBingoLine: item.isActive ? isInCompletedLine(row: item.row, col: item.col, in: board) : false,
                        isLocked: item.isActive ? isLocked(row: item.row, col: item.col, in: board) : false,
                        cellSize: cellSize,
                        isFirstCell: false
                    )
                }
            }
            .frame(width: gridWidth, height: cellSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func boardView(for board: SavedBoard) -> some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let boardSide = min(geo.size.width, geo.size.height)
            let totalSpacing = spacing * CGFloat(max(board.gridSize - 1, 0))
            let cellSize = (boardSide - totalSpacing) / CGFloat(board.gridSize)

            VStack(spacing: spacing) {
                ForEach(0..<board.gridSize, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<board.gridSize, id: \.self) { col in
                            let cell = cellAt(row: row, col: col, in: board)

                            widgetCellButton(
                                cell: cell,
                                row: row,
                                col: col,
                                isActive: true,
                                isInBingoLine: isInCompletedLine(row: row, col: col, in: board),
                                isLocked: isLocked(row: row, col: col, in: board),
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

    private func widgetCellButton(
        cell: BingoCell,
        row: Int,
        col: Int,
        isActive: Bool,
        isInBingoLine: Bool,
        isLocked: Bool,
        cellSize: CGFloat,
        isFirstCell: Bool
    ) -> some View {
        let isToggleable = isToggleable(cell: cell, isLocked: isLocked)
        let isScheduledInactive = !isToggleable && !cell.isEmpty
        let cellView = WidgetBingoCellView(
            cell: cell,
            currentTime: entry.date,
            isScheduledInactive: isScheduledInactive,
            scheduleStatusText: scheduleStatusText(for: cell, isScheduledInactive: isScheduledInactive),
            isInBingoLine: isInBingoLine,
            isLocked: isLocked,
            cellSize: cellSize,
            isFirstCell: isFirstCell
        )

        guard isActive, let activePanelID, isToggleable else {
            return AnyView(cellView)
        }

        return AnyView(
            Button(intent: ToggleWidgetTaskIntent(boardID: activePanelID.uuidString, row: row, col: col)) {
                cellView
            }
            .buttonStyle(.plain)
        )
    }

    private func boardSwitchButton(systemImage: String, step: Int) -> some View {
        Button(intent: SwitchBoardIntent(step: step)) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.72))
                .frame(width: largeSwitchButtonSize, height: largeSwitchButtonSize)
                .background(
                    Circle()
                        .fill(widgetBackgroundColor.opacity(0.98))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.62), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<entry.panels.count, id: \.self) { index in
                Circle()
                    .fill(index == panelIndex ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.24))
                    .frame(width: index == panelIndex ? 7 : 6, height: index == panelIndex ? 7 : 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cellAt(row: Int, col: Int, in board: SavedBoard) -> BingoCell {
        guard row < board.cells.count, col < board.cells[row].count else {
            return BingoCell()
        }
        return board.cells[row][col]
    }

    private func isInCompletedLine(row: Int, col: Int, in board: SavedBoard) -> Bool {
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

    private func isLocked(row: Int, col: Int, in board: SavedBoard) -> Bool {
        let activeForced = board.cells.flatMap(\.self).filter {
            $0.isForced && !$0.isCompleted && !$0.isEmpty && $0.isCurrentlyTappable(on: entry.date)
        }
        guard !activeForced.isEmpty else {
            return false
        }

        let cell = cellAt(row: row, col: col, in: board)
        return !(cell.isForced && !cell.isCompleted && !cell.isEmpty && cell.isCurrentlyTappable(on: entry.date))
    }

    private func isToggleable(cell: BingoCell, isLocked: Bool) -> Bool {
        !cell.isEmpty && !isLocked && (cell.isCompleted || cell.isCurrentlyTappable(on: entry.date))
    }

    private func scheduleStatusText(for cell: BingoCell, isScheduledInactive: Bool) -> String? {
        guard cell.hasStoredTask else { return nil }

        if isScheduledInactive {
            if cell.isEndVisibilityReached(on: entry.date) {
                return L10n.tr("Ended", zhHans: "已结束", zhHant: "已結束", ja: "終了")
            }

            if cell.isVisibilityWindowInactive(on: entry.date) {
                return startStatusText(for: cell.occurrenceStartVisibleAt(on: entry.date))
            }

            if let nextActiveDate = cell.nextResidentActiveDate(onOrAfter: entry.date),
               !Calendar.current.isDate(nextActiveDate, inSameDayAs: entry.date) {
                return L10n.tr(
                    "Next \(shortDateLabel(nextActiveDate))",
                    zhHans: "下次 \(shortDateLabel(nextActiveDate))",
                    zhHant: "下次 \(shortDateLabel(nextActiveDate))",
                    ja: "次回 \(shortDateLabel(nextActiveDate))"
                )
            }
            return nil
        }

        guard let rule = cell.effectiveRecurrenceRule,
              rule.kind != .none else {
            return nil
        }
        return activeRecurrenceLabel(for: rule)
    }

    private func startStatusText(for startDate: Date?) -> String? {
        guard let startDate else { return nil }
        if Calendar.current.isDate(startDate, inSameDayAs: entry.date) {
            return L10n.tr(
                "\(timeLabel(startDate)) start",
                zhHans: "\(timeLabel(startDate)) 开始",
                zhHant: "\(timeLabel(startDate)) 開始",
                ja: "\(timeLabel(startDate)) 開始"
            )
        }
        return L10n.tr(
            "\(shortDateLabel(startDate)) start",
            zhHans: "\(shortDateLabel(startDate)) 开始",
            zhHant: "\(shortDateLabel(startDate)) 開始",
            ja: "\(shortDateLabel(startDate)) 開始"
        )
    }

    private func activeRecurrenceLabel(for rule: TaskRecurrenceRule) -> String? {
        switch rule.kind {
        case .daily:
            return L10n.tr("Daily", zhHans: "每天", zhHant: "每天", ja: "毎日")
        case .weekly:
            let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
            let labels = orderedWeekdays
                .filter { rule.weekdays.contains($0) }
                .map(weekdayLabel(for:))
            guard !labels.isEmpty else { return nil }
            return L10n.tr(
                "Every \(labels.joined(separator: ", "))",
                zhHans: "每周\(labels.joined(separator: "、"))",
                zhHant: "每週\(labels.joined(separator: "、"))",
                ja: "毎週\(labels.joined(separator: "・"))"
            )
        case .monthlyDay:
            let day = rule.monthDay ?? Calendar.current.component(.day, from: entry.date)
            return L10n.tr(
                "Monthly on day \(day)",
                zhHans: "每月 \(day) 日",
                zhHant: "每月 \(day) 日",
                ja: "毎月\(day)日"
            )
        case .everyNDays:
            return L10n.tr(
                "Every \(rule.interval) days",
                zhHans: "每隔 \(rule.interval) 天",
                zhHant: "每隔 \(rule.interval) 天",
                ja: "\(rule.interval)日ごと"
            )
        case .none:
            return nil
        }
    }

    private func weekdayLabel(for weekday: Int) -> String {
        switch weekday {
        case 1: return L10n.tr("Sun", zhHans: "周日", zhHant: "週日", ja: "日")
        case 2: return L10n.tr("Mon", zhHans: "周一", zhHant: "週一", ja: "月")
        case 3: return L10n.tr("Tue", zhHans: "周二", zhHant: "週二", ja: "火")
        case 4: return L10n.tr("Wed", zhHans: "周三", zhHant: "週三", ja: "水")
        case 5: return L10n.tr("Thu", zhHans: "周四", zhHant: "週四", ja: "木")
        case 6: return L10n.tr("Fri", zhHans: "周五", zhHant: "週五", ja: "金")
        case 7: return L10n.tr("Sat", zhHans: "周六", zhHant: "週六", ja: "土")
        default: return ""
        }
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.calendar = Calendar.current
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.calendar = Calendar.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
    let currentTime: Date
    let isScheduledInactive: Bool
    let scheduleStatusText: String?
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat
    let isFirstCell: Bool

    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = Calendar.current
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private var activeTheme: AppTheme { AppTheme.current }
    private var bingoLineColor: Color { activeTheme.color }
    private var boardSurfaceColor: Color { Color(hex: "F4F4F4") }
    private var primaryTextColor: Color { Color(hex: "291E0A") }
    private var selectedColor: Color { reducedSaturationColor(from: activeTheme.color, by: 0.30) }
    private var cellCornerRadius: CGFloat { min(max(cellSize * 0.25, 12), 22) }
    private var footerSlotHeight: CGFloat { min(max(cellSize * 0.2, 14), 24) }
    private var footerBottomInset: CGFloat { min(max(cellSize * 0.08, 4), 8) }
    private var isTaskHiddenFaceVisible: Bool { cell.isCompleted && cell.isTaskHidden && !cell.isEmpty && !isLocked }

    var body: some View {
        ZStack {
            backgroundSurface

            if !cell.isEmpty {
                if isTaskHiddenFaceVisible {
                    largeCompletionIcon
                } else {
                    ZStack(alignment: .bottom) {
                        Text(cell.text)
                            .font(.system(size: dynamicFontSize, weight: .medium, design: .rounded))
                            .foregroundColor(cellTextColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, max(cellSize * 0.1, 6))
                            .padding(.top, max(cellSize * 0.12, 7))
                            .padding(.bottom, textBottomPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                        if hasFooterContent {
                            footerContent
                                .font(.system(size: max(dynamicFontSize * 0.34, 7), weight: .semibold, design: .rounded))
                                .foregroundColor(primaryTextColor.opacity(isScheduledInactive ? 0.45 : 0.58))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.65)
                                .padding(.horizontal, max(cellSize * 0.06, 4))
                                .frame(height: footerSlotHeight)
                                .padding(.bottom, footerBottomInset)
                        }

                        if cell.isCompleted && !isLocked {
                            completionIcon
                                .frame(height: footerSlotHeight)
                                .padding(.bottom, footerBottomInset)
                        }
                    }
                }
            }

            if isLocked {
                lockOverlay
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var textBottomPadding: CGFloat {
        if hasFooterContent || (cell.isCompleted && !isLocked) {
            return footerSlotHeight + footerBottomInset + 2
        }
        return max(cellSize * 0.1, 7)
    }

    private var dynamicFontSize: CGFloat {
        let maxBaseSize: CGFloat = 16
        let minimumSize: CGFloat = 9
        let gridScale: CGFloat
        if cellSize < 52 {
            gridScale = 0.78
        } else if cellSize < 70 {
            gridScale = 0.86
        } else {
            gridScale = 1.0
        }

        let baseSize = min(cellSize * 0.22, maxBaseSize) * gridScale
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

    private var hasFooterContent: Bool {
        guard !cell.isCompleted, !isLocked else { return false }
        return displayCountdownDeadline != nil || staticFooterText != nil
    }

    @ViewBuilder
    private var footerContent: some View {
        if let deadline = displayCountdownDeadline {
            Text(timerInterval: currentTime...deadline, countsDown: true, showsHours: true)
        } else if let staticFooterText {
            Text(staticFooterText)
        }
    }

    private var staticFooterText: String? {
        if (cell.countdownPausedRemainingSeconds ?? 0) > 0 {
            return L10n.tr("Paused", zhHans: "已暂停", zhHant: "已暫停", ja: "一時停止中")
        }
        return scheduleStatusText ?? scheduleWindowText
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

    private var taskCountdownDeadline: Date? {
        guard (cell.countdownPausedRemainingSeconds ?? 0) <= 0,
              let deadline = cell.countdownEndsAt,
              deadline > currentTime else {
            return nil
        }
        return deadline
    }

    private var windowCountdownDeadline: Date? {
        guard !isScheduledInactive,
              let start = cell.occurrenceStartVisibleAt(on: currentTime),
              let end = cell.occurrenceEndVisibleAt(on: currentTime),
              currentTime >= start,
              currentTime < end else {
            return nil
        }
        return end
    }

    private var displayCountdownDeadline: Date? {
        windowCountdownDeadline ?? taskCountdownDeadline
    }

    private var backgroundSurface: some View {
        let baseShape = RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)

        return baseShape
            .fill(cellFillColor)
            .overlay {
                baseShape
                    .stroke(
                        isInBingoLine ? Color.white.opacity(0.24) : Color.white.opacity(0.58),
                        lineWidth: isInBingoLine ? 1.1 : 0.9
                    )

                if isLocked && !isInBingoLine {
                    baseShape
                        .fill(boardSurfaceColor.opacity(0.62))
                }

                if isScheduledInactive && !isInBingoLine {
                    baseShape
                        .fill(Color.white.opacity(0.2))
                }

                if cell.isCompleted && !isInBingoLine {
                    baseShape
                        .stroke(selectedColor.opacity(0.36), lineWidth: 1.2)
                }
            }
            .shadow(
                color: isInBingoLine ? bingoLineColor.opacity(0.28) : Color.black.opacity(0.08),
                radius: isInBingoLine ? 5 : 3,
                x: 0,
                y: isInBingoLine ? 2 : 1
            )
    }

    private var cellFillColor: Color {
        if isInBingoLine {
            return bingoLineColor
        }
        if cell.isCompleted {
            return selectedColor
        }
        return boardSurfaceColor
    }

    private var completionIcon: some View {
        let size = min(max(cellSize * 0.16, 14), 22)

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.96))

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(isInBingoLine ? bingoLineColor : selectedColor)
        }
        .frame(width: size, height: size)
    }

    private var largeCompletionIcon: some View {
        let size = min(max(cellSize * 0.42, 28), 48)

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.96))

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(isInBingoLine ? bingoLineColor : selectedColor)
        }
        .frame(width: size, height: size)
    }

    private var lockOverlay: some View {
        let size = min(max(cellSize * 0.22, 18), 26)

        return ZStack {
            Circle()
                .fill(boardSurfaceColor.opacity(0.95))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                )

            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundColor(primaryTextColor.opacity(0.5))
        }
        .frame(width: size, height: size)
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
}

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
