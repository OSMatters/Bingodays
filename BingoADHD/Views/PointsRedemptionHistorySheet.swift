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
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var displayedMonth = Calendar.current.startOfMonth(for: .now)
    private let calendar = Calendar.redemptionHistoryCalendar

    private var historyItems: [HistoryItem] {
        let recordedItems = records.map { record in
            HistoryItem(
                id: record.id.uuidString,
                title: record.itemKind == .sticker ? stickerHistoryTitle(record.title) : record.title,
                detail: record.itemKind == .sticker ? L10n.stickers : L10n.myRewards,
                points: record.points,
                redeemedAt: record.redeemedAt,
                imageName: record.imageName,
                emoji: record.emoji
            )
        }

        let legacyRewards = rewards.compactMap { reward -> HistoryItem? in
            guard reward.redemptionCount > 0 else { return nil }
            return HistoryItem(
                id: "legacy-reward-\(reward.id.uuidString)",
                title: reward.title,
                detail: L10n.tr("Redeemed before history tracking", zhHans: "开启记录前已兑换", zhHant: "開啟記錄前已兌換", ja: "履歴記録の開始前に交換済み"),
                points: reward.totalSpentPoints,
                redeemedAt: .distantPast,
                imageName: reward.themeImageName,
                emoji: reward.themeImageName == nil ? reward.displayEmoji : nil
            )
        }

        let legacyStickers = StickerKind.allCases.compactMap { kind -> HistoryItem? in
            let count = inventoryCounts[kind] ?? 0
            guard count > 0 else { return nil }
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

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var historyPrimaryTextColor: Color {
        Color(red: 0.24, green: 0.20, blue: 0.17)
    }

    private var historySecondaryTextColor: Color {
        Color(red: 0.42, green: 0.36, blue: 0.31)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PointsRewardBackground()
                    .ignoresSafeArea()

                if historyItems.isEmpty {
                    Text(L10n.tr("No redemption history yet", zhHans: "暂无兑换记录", zhHant: "暫無兌換記錄", ja: "交換履歴はまだありません"))
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(historySecondaryTextColor.opacity(0.82))
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: scaled(16, pad: 20)) {
                            calendarView

                            VStack(alignment: .leading, spacing: scaled(10, pad: 12)) {
                                Text(selectedSectionTitle)
                                    .font(.appSystem(size: scaled(14, pad: 17), weight: .heavy, design: .rounded))
                                    .foregroundColor(historySecondaryTextColor.opacity(0.95))
                                    .padding(.horizontal, scaled(4, pad: 6))

                                if selectedItems.isEmpty {
                                    emptySelectedDateState
                                } else {
                                    ForEach(selectedItems) { item in
                                        historyRow(item)
                                    }
                                }

                                if !legacyItems.isEmpty {
                                    Text(L10n.tr("Earlier", zhHans: "较早记录", zhHant: "較早記錄", ja: "過去の記録"))
                                        .font(.appSystem(size: scaled(14, pad: 17), weight: .heavy, design: .rounded))
                                        .foregroundColor(historySecondaryTextColor.opacity(0.95))
                                        .padding(.horizontal, scaled(4, pad: 6))
                                        .padding(.top, scaled(8, pad: 10))

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
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .heavy, design: .rounded))
                        .foregroundColor(historyPrimaryTextColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(historyPrimaryTextColor)
                    }
                    .accessibilityLabel(L10n.done)
                }
            }
        }
        .presentationDetents([.fraction(0.9)])
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
            .font(.appSystem(size: scaled(14, pad: 17), weight: .semibold, design: .rounded))
            .foregroundColor(historySecondaryTextColor.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, scaled(18, pad: 22))
            .background(
                RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                    .fill(Color.white.opacity(0.86))
            )
    }

    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: scaled(12, pad: 16)) {
            ZStack {
                RoundedRectangle(cornerRadius: scaled(14, pad: 16), style: .continuous)
                    .fill(Color.white.opacity(0.72))

                if let imageName = item.imageName {
                    Image(imageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(scaled(8, pad: 10))
                } else if let emoji = item.emoji {
                    Text(emoji)
                        .font(.system(size: scaled(28, pad: 34)))
                }
            }
            .frame(width: scaled(56, pad: 68), height: scaled(56, pad: 68))

            VStack(alignment: .leading, spacing: scaled(4, pad: 5)) {
                Text(item.title)
                    .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                    .foregroundColor(historyPrimaryTextColor)
                    .lineLimit(1)

                Text(item.detail)
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                    .foregroundColor(historySecondaryTextColor.opacity(0.86))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: scaled(4, pad: 5)) {
                if item.redeemedAt != .distantPast {
                    Text(timeText(for: item.redeemedAt))
                        .font(.appSystem(size: scaled(13, pad: 15), weight: .heavy, design: .rounded))
                        .foregroundColor(historySecondaryTextColor.opacity(0.92))
                }

                Text("\(item.points) pts")
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                    .foregroundColor(historyPrimaryTextColor)
            }
        }
        .padding(.horizontal, scaled(14, pad: 18))
        .padding(.vertical, scaled(12, pad: 15))
        .background(
            RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                        .stroke(historySecondaryTextColor.opacity(0.14), lineWidth: 1)
                )
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

    private let calendar = Calendar.redemptionHistoryCalendar
    private let nonSelectedDayColor = Color(hex: "828282")
    private var historyAccentColor: Color { AppTheme.current.color }
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
                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.92))

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
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                    .foregroundColor(nonSelectedDayColor)
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
                    .frame(width: scaled(36, pad: 42), height: scaled(36, pad: 42))

                VStack(spacing: scaled(1, pad: 2)) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.appSystem(size: scaled(18, pad: 21), weight: isSelected ? .heavy : .medium, design: .rounded))
                        .foregroundColor(dayTextColor(isSelected: isSelected, hasRecord: hasRecord))

                    Circle()
                        .fill(hasRecord && !isSelected ? historyAccentColor : Color.clear)
                        .frame(width: scaled(4, pad: 5), height: scaled(4, pad: 5))
                }
                .offset(y: hasRecord && !isSelected ? scaled(2, pad: 2) : 0)
            }
            .frame(width: scaled(42, pad: 48), height: scaled(38, pad: 44))
        }
        .buttonStyle(.plain)
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
                .font(.appSystem(size: scaled(20, pad: 23), weight: .heavy))
                .foregroundColor(Color.black.opacity(0.9))
                .frame(width: scaled(34, pad: 40), height: scaled(34, pad: 40))
        }
        .buttonStyle(.plain)
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
