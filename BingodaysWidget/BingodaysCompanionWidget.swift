import SwiftUI
import WidgetKit

struct BingodaysCompanionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BingodaysCompanionWidget", provider: CompanionWidgetProvider()) { entry in
            CompanionWidgetView(entry: entry)
                .environment(\.locale, AppLanguage.displayLocale)
        }
        .configurationDisplayName(L10n.tr("Daily Companion", zhHans: "卷卷 · 每日见面", ja: "毎日の友だち"))
        .description(L10n.tr("Your days together and weekly check-ins.", zhHans: "记录连续打开天数和本周打卡，卷卷陪你每一天。", ja: "連続起動日数と今週の記録。"))
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
