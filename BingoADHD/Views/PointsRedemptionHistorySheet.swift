import SwiftUI

struct PointsRedemptionHistorySheet: View {
    private struct HistoryItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let points: Int
        let redeemedAt: Date
        let imageName: String?
        let emoji: String?
    }

    let inventoryCounts: [StickerKind: Int]
    let rewards: [CustomReward]
    let records: [PointRedemptionRecord]
    let isPadLayout: Bool
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var displayedMonth = Calendar.current.startOfMonth(for: .now)
    private let calendar = Calendar.redemptionHistoryCalendar

    private var historyItems: [HistoryItem] {
        let recordedItems = records.map { record in
            HistoryItem(
                id: record.id.uuidString,
                title: historyTitle(for: record),
                detail: historyDetail(for: record),
                points: record.points,
                redeemedAt: record.redeemedAt,
                imageName: record.imageName,
                emoji: record.emoji
            )
        }

        let legacyRewards = rewards.compactMap { reward -> HistoryItem? in
            let linkedRecords = records.filter {
                $0.isActive && $0.referencedCustomRewardID == reward.id
            }
            let missingCount = max(reward.redemptionCount - linkedRecords.count, 0)
            guard missingCount > 0 else { return nil }
            let linkedPoints = linkedRecords.reduce(0) { $0 + max($1.points, 0) }
            return HistoryItem(
                id: "legacy-reward-\(reward.id.uuidString)",
                title: reward.title,
                detail: L10n.tr("Redeemed before history tracking", zhHans: "开启记录前已兑换", zhHant: "開啟記錄前已兌換", ja: "履歴記録の開始前に交換済み"),
                points: max(reward.totalSpentPoints - linkedPoints, 0),
                redeemedAt: .distantPast,
                imageName: reward.themeImageName,
                emoji: reward.themeImageName == nil ? reward.displayEmoji : nil
            )
        }

        let legacyStickers = StickerKind.allCases.compactMap { kind -> HistoryItem? in
            let count = inventoryCounts[kind] ?? 0
            let hasLinkedRecord = records.contains {
                $0.isActive && $0.referencedStickerKind == kind
            }
            guard count > 0, !hasLinkedRecord else { return nil }
            return HistoryItem(
                id: "legacy-sticker-\(kind.rawValue)",
                title: kind.redemptionHistoryTitle,
                detail: L10n.tr("Redeemed before history tracking", zhHans: "开启记录前已兑换", zhHant: "開啟記錄前已兌換", ja: "履歴記録の開始前に交換済み"),
                points: kind.requiredPoints * count,
                redeemedAt: .distantPast,
                imageName: kind.unlockedImageName,
                emoji: nil
            )
        }

        return (recordedItems + legacyRewards + legacyStickers)
            .sorted { $0.redeemedAt > $1.redeemedAt }
    }

    private var itemsByDay: [Date: [HistoryItem]] {
        return Dictionary(grouping: historyItems.filter { $0.redeemedAt != .distantPast }) { item in
            calendar.startOfDay(for: item.redeemedAt)
        }
        .mapValues { $0.sorted { $0.redeemedAt > $1.redeemedAt } }
    }

    private var legacyItems: [HistoryItem] {
        historyItems.filter { $0.redeemedAt == .distantPast }
    }

    private var selectedItems: [HistoryItem] {
        return itemsByDay[calendar.startOfDay(for: selectedDate)] ?? []
    }

    private func stickerHistoryTitle(_ title: String) -> String {
        var normalized = title
        ["（星星）", "(Star)", "（スター）"].forEach { suffix in
            normalized = normalized.replacingOccurrences(of: suffix, with: "")
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func historyTitle(for record: PointRedemptionRecord) -> String {
        switch record.itemKind {
        case .sticker:
            stickerHistoryTitle(record.title)
        case .customReward, .blindBoxTicket:
            record.title
        }
    }

    private func historyDetail(for record: PointRedemptionRecord) -> String {
        switch record.itemKind {
        case .sticker:
            L10n.stickers
        case .customReward:
            L10n.myRewards
        case .blindBoxTicket:
            L10n.tr(
                "Blind Box",
                zhHans: "盲盒",
                zhHant: "盲盒",
                ja: "ブラインドボックス"
            )
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var historyPrimaryTextColor: Color {
        Color(red: 0.24, green: 0.20, blue: 0.17)
    }

    private var historySecondaryTextColor: Color {
        Color(red: 0.42, green: 0.36, blue: 0.31)
    }

    private func historyAccessibilitySummary(for item: HistoryItem) -> String {
        var components = [item.detail]
        if item.redeemedAt != .distantPast {
            components.append(
                DateFormatter.localizedString(
                    from: item.redeemedAt,
                    dateStyle: .full,
                    timeStyle: .short
                )
            )
        }
        components.append("\(item.points) \(L10n.pointsUnit)")
        return components.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PointsRewardBackground()
                    .ignoresSafeArea()

                if historyItems.isEmpty {
                    Text(L10n.tr("No redemption history yet", zhHans: "暂无兑换记录", zhHant: "暫無兌換記錄", ja: "交換履歴はまだありません"))
                        .appDynamicFont(size: scaled(17, pad: 20), weight: .semibold, design: .rounded)
                        .foregroundStyle(historySecondaryTextColor.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: scaled(16, pad: 20)) {
                            calendarView

                            VStack(alignment: .leading, spacing: scaled(10, pad: 12)) {
                                Text(selectedSectionTitle)
                                    .appDynamicFont(size: scaled(14, pad: 17), weight: .heavy, design: .rounded)
                                    .foregroundStyle(historySecondaryTextColor.opacity(0.95))
                                    .padding(.horizontal, scaled(4, pad: 6))
                                    .accessibilityAddTraits(.isHeader)

                                if selectedItems.isEmpty {
                                    emptySelectedDateState
                                } else {
                                    ForEach(selectedItems) { item in
                                        historyRow(item)
                                    }
                                }

                                if !legacyItems.isEmpty {
                                    Text(L10n.tr("Earlier", zhHans: "较早记录", zhHant: "較早記錄", ja: "過去の記録"))
                                        .appDynamicFont(size: scaled(14, pad: 17), weight: .heavy, design: .rounded)
                                        .foregroundStyle(historySecondaryTextColor.opacity(0.95))
                                        .padding(.horizontal, scaled(4, pad: 6))
                                        .padding(.top, scaled(8, pad: 10))
                                        .accessibilityAddTraits(.isHeader)

                                    ForEach(legacyItems) { item in
                                        historyRow(item)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, scaled(20, pad: 32))
                        .padding(.top, scaled(18, pad: 24))
                        .padding(.bottom, scaled(28, pad: 36))
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.tr("Redemption History", zhHans: "兑换记录", zhHant: "兌換記錄", ja: "交換履歴"))
                        .appDynamicFont(size: scaled(17, pad: 20), weight: .heavy, design: .rounded)
                        .foregroundStyle(historyPrimaryTextColor)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(historyPrimaryTextColor)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(L10n.done)
                }
            }
        }
        .presentationDetents([dynamicTypeSize.isAccessibilitySize ? .large : .fraction(0.9)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    private var calendarView: some View {
        RedemptionCalendarView(
            displayedMonth: $displayedMonth,
            selectedDate: $selectedDate,
            recordedDates: Set(itemsByDay.keys),
            isPadLayout: isPadLayout
        )
        .padding(.horizontal, scaled(10, pad: 14))
        .padding(.vertical, scaled(14, pad: 18))
        .background(
            RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                        .stroke(historySecondaryTextColor.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private var selectedSectionTitle: String {
        return sectionTitle(for: selectedDate)
    }

    private var emptySelectedDateState: some View {
        Text(L10n.tr("No redemptions on this date", zhHans: "这一天没有兑换记录", zhHant: "這一天沒有兌換記錄", ja: "この日に交換履歴はありません"))
            .appDynamicFont(size: scaled(14, pad: 17), weight: .semibold, design: .rounded)
            .foregroundStyle(historySecondaryTextColor.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, scaled(18, pad: 22))
            .background(
                RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                    .fill(Color.white.opacity(0.86))
            )
    }

    private func historyRow(_ item: HistoryItem) -> some View {
        historyRowContent(item)
            .padding(.horizontal, scaled(14, pad: 18))
            .padding(.vertical, scaled(12, pad: 15))
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                            .stroke(historySecondaryTextColor.opacity(0.14), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title)
            .accessibilityValue(historyAccessibilitySummary(for: item))
    }

    @ViewBuilder
    private func historyRowContent(_ item: HistoryItem) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    historyThumbnail(item)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .appDynamicFont(size: scaled(16, pad: 19), weight: .bold, design: .rounded)
                            .foregroundStyle(historyPrimaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(item.detail)
                            .appDynamicFont(size: scaled(12, pad: 14), weight: .semibold, design: .rounded)
                            .foregroundStyle(historySecondaryTextColor.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .firstTextBaseline) {
                    if item.redeemedAt != .distantPast {
                        Text(timeText(for: item.redeemedAt))
                            .appDynamicFont(size: scaled(13, pad: 15), weight: .heavy, design: .rounded)
                            .foregroundStyle(historySecondaryTextColor.opacity(0.92))
                    }

                    Spacer(minLength: 8)

                    Text("\(item.points) \(L10n.pointsUnit)")
                        .appDynamicFont(size: scaled(12, pad: 14), weight: .semibold, design: .rounded)
                        .foregroundStyle(historyPrimaryTextColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: scaled(12, pad: 16)) {
                historyThumbnail(item)

                VStack(alignment: .leading, spacing: scaled(4, pad: 5)) {
                    Text(item.title)
                        .appDynamicFont(size: scaled(16, pad: 19), weight: .bold, design: .rounded)
                        .foregroundStyle(historyPrimaryTextColor)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.detail)
                        .appDynamicFont(size: scaled(12, pad: 14), weight: .semibold, design: .rounded)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(historySecondaryTextColor.opacity(0.86))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: scaled(4, pad: 5)) {
                    if item.redeemedAt != .distantPast {
                        Text(timeText(for: item.redeemedAt))
                            .appDynamicFont(size: scaled(13, pad: 15), weight: .heavy, design: .rounded)
                            .foregroundStyle(historySecondaryTextColor.opacity(0.92))
                    }

                    Text("\(item.points) pts")
                        .appDynamicFont(size: scaled(12, pad: 14), weight: .semibold, design: .rounded)
                        .foregroundStyle(historyPrimaryTextColor)
                }
            }
        }
    }

    private func historyThumbnail(_ item: HistoryItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: scaled(14, pad: 16), style: .continuous)
                .fill(Color.white.opacity(0.72))

            if let imageName = item.imageName {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(scaled(8, pad: 10))
                    .accessibilityHidden(true)
            } else if let emoji = item.emoji {
                Text(emoji)
                    .font(.system(size: scaled(28, pad: 34)))
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: dynamicTypeSize.isAccessibilitySize ? scaled(68, pad: 80) : scaled(56, pad: 68),
            height: dynamicTypeSize.isAccessibilitySize ? scaled(68, pad: 80) : scaled(56, pad: 68)
        )
    }

    private func sectionTitle(for date: Date) -> String {
        guard date != .distantPast else {
            return L10n.tr("Earlier", zhHans: "较早记录", zhHant: "較早記錄", ja: "過去の記録")
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L10n.tr("Today", zhHans: "今天", zhHant: "今天", ja: "今日")
        }
        if calendar.isDateInYesterday(date) {
            return L10n.tr("Yesterday", zhHans: "昨天", zhHant: "昨天", ja: "昨日")
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter.string(from: date)
    }

    private func timeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

private struct RedemptionCalendarView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    let recordedDates: Set<Date>
    let isPadLayout: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let calendar = Calendar.redemptionHistoryCalendar
    private let nonSelectedDayColor = Color(hex: "828282")
    private var historyAccentColor: Color { NeumorphicColors.modalAccent }
    private var selectedDayBackground: Color { historyAccentColor.opacity(0.18) }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    var body: some View {
        VStack(spacing: scaled(18, pad: 22)) {
            header
            weekdayHeader
            dayGrid
        }
        .padding(.horizontal, scaled(8, pad: 12))
        .padding(.vertical, scaled(10, pad: 12))
    }

    private var header: some View {
        HStack {
            Text(monthTitle)
                .appDynamicFont(size: scaled(17, pad: 20), weight: .bold, design: .rounded)
                .foregroundStyle(Color.black.opacity(0.92))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            HStack(spacing: scaled(28, pad: 34)) {
                monthButton(systemName: "chevron.left") {
                    moveMonth(by: -1)
                }
                monthButton(systemName: "chevron.right") {
                    moveMonth(by: 1)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .appDynamicFont(size: scaled(13, pad: 15), weight: .bold, design: .rounded)
                    .foregroundStyle(nonSelectedDayColor)
                    .lineLimit(1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.55 : 1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: scaled(16, pad: 20)) {
            ForEach(calendarCells) { cell in
                if let date = cell.date {
                    dayButton(for: date)
                } else {
                    Color.clear
                        .frame(height: scaled(34, pad: 40))
                }
            }
        }
    }

    private func dayButton(for date: Date) -> some View {
        let startOfDay = calendar.startOfDay(for: date)
        let isSelected = calendar.isDate(startOfDay, inSameDayAs: selectedDate)
        let hasRecord = recordedDates.contains(startOfDay)

        return Button {
            selectedDate = startOfDay
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? selectedDayBackground : Color.clear)
                    .frame(
                        width: dynamicTypeSize.isAccessibilitySize ? scaled(40, pad: 46) : scaled(36, pad: 42),
                        height: dynamicTypeSize.isAccessibilitySize ? scaled(40, pad: 46) : scaled(36, pad: 42)
                    )

                VStack(spacing: scaled(1, pad: 2)) {
                    Text("\(calendar.component(.day, from: date))")
                        .appDynamicFont(size: scaled(18, pad: 21), weight: isSelected ? .heavy : .medium, design: .rounded)
                        .foregroundStyle(dayTextColor(isSelected: isSelected, hasRecord: hasRecord))
                        .lineLimit(1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.55 : 1)
                        .monospacedDigit()

                    Circle()
                        .fill(hasRecord && !isSelected ? historyAccentColor : Color.clear)
                        .frame(width: scaled(4, pad: 5), height: scaled(4, pad: 5))
                }
                .offset(y: hasRecord && !isSelected ? scaled(2, pad: 2) : 0)
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 48 : scaled(38, pad: 44))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none))
        .accessibilityValue(
            hasRecord
                ? L10n.tr("Has redemptions", zhHans: "有兑换记录", zhHant: "有兌換記錄", ja: "交換履歴あり")
                : L10n.tr("No redemptions", zhHans: "没有兑换记录", zhHant: "沒有兌換記錄", ja: "交換履歴なし")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(L10n.tr("Shows redemptions for this date.", zhHans: "显示这一天的兑换记录。", zhHant: "顯示這一天的兌換記錄。", ja: "この日の交換履歴を表示します。"))
    }

    private func dayTextColor(isSelected: Bool, hasRecord: Bool) -> Color {
        if isSelected {
            return historyAccentColor
        }
        if hasRecord {
            return historyAccentColor.opacity(0.92)
        }
        return nonSelectedDayColor
    }

    private func monthButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .appDynamicFont(size: scaled(20, pad: 23), weight: .heavy)
                .foregroundStyle(Color.black.opacity(0.9))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            systemName == "chevron.left"
                ? L10n.tr("Previous month", zhHans: "上个月", zhHant: "上個月", ja: "前の月")
                : L10n.tr("Next month", zhHans: "下个月", zhHant: "下個月", ja: "次の月")
        )
        .accessibilityValue(monthTitle)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = .current
        return formatter.shortStandaloneWeekdaySymbols.map { $0.uppercased() }
    }

    private var calendarCells: [CalendarCell] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leadingEmptyCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells = (0..<leadingEmptyCount).map { CalendarCell(id: "empty-\($0)", date: nil) }

        for day in range {
            var components = calendar.dateComponents([.year, .month], from: displayedMonth)
            components.day = day
            if let date = calendar.date(from: components) {
                cells.append(CalendarCell(id: date.ISO8601Format(), date: date))
            }
        }

        return cells
    }

    private func moveMonth(by value: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = calendar.startOfMonth(for: nextMonth)
    }

    private struct CalendarCell: Identifiable {
        let id: String
        let date: Date?
    }
}

private extension Calendar {
    static var redemptionHistoryCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        return calendar
    }

    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }
}
