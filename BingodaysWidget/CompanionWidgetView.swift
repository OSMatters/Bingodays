import SwiftUI
import WidgetKit

struct CompanionWidgetView: View {
    let entry: CompanionWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    private let ink = Color(hex: "654B35")
    private let sage = Color(hex: "899578")

    var body: some View {
        GeometryReader { geometry in
            let missed = entry.snapshot?.hasMissedOpening(at: entry.date) ?? false
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(entry.snapshot?.visibleStreak(at: entry.date) ?? 0, format: .number)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(L10n.tr("days", zhHans: "天", ja: "日"))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.tr("Consecutive days", zhHans: "连续打开天数", ja: "連続起動日数"))
                    .accessibilityValue(String(entry.snapshot?.visibleStreak(at: entry.date) ?? 0))
                    Spacer(minLength: 12)
                    HStack(spacing: 0) {
                        ForEach(weekDates, id: \.self) { date in
                            CompanionDayView(date: date, state: entry.snapshot?.dayState(date, at: entry.date) ?? .unknown,
                                             ink: ink, accent: sage,
                                             milestone: entry.snapshot?.unlockedMilestone(on: date, at: entry.date))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .foregroundStyle(renderingMode == .fullColor ? ink : .primary)
                .padding(.vertical, 22)
                .padding(.leading, 20)
                .frame(width: geometry.size.width * 0.56)
                Image(missed ? "CompanionResting" : "CompanionPajamas")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * 0.44 - 8, height: geometry.size.height - 16,
                           alignment: .bottom)
                    // Original resting artwork has extra transparent space below its silhouette.
                    .offset(y: missed ? (geometry.size.width * 0.44 - 8) * 0.21 : 0)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
            }
        }
        .containerBackground(Color(hex: "FAF4E8"), for: .widget)
    }

    private var weekDates: [Date] {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}
