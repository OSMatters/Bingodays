import SwiftUI
import WidgetKit

@main
struct BingodaysMacWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MacDesktopBoardSnapshot.widgetKind, provider: MacDesktopBoardProvider()) { entry in
            MacDesktopBoardView(snapshot: entry.snapshot, referenceDate: entry.date)
        }
        .configurationDisplayName("桌面棋盘")
        .description("只展示棋盘。点击棋盘，打开任务与编辑界面。")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}
