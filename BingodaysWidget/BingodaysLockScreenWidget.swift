import SwiftUI
import WidgetKit

struct BingodaysLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BingodaysWidgetKind.lockScreen, provider: BingodaysWidgetProvider()) { entry in
            BingodaysLockScreenWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(L10n.tr("Lock Screen Bingo", zhHans: "锁屏棋盘", zhHant: "鎖屏棋盤", ja: "ロック画面のビンゴ"))
        .description(L10n.tr("View your board and completion progress below the clock.", zhHans: "在时钟下方查看棋盘和完成进度。", zhHant: "在時鐘下方查看棋盤和完成進度。", ja: "時計の下でボードと完了の進捗を確認できます。"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
