import SwiftUI
import WidgetKit

struct BingodaysLockScreenWidgetView: View {
    let entry: BingodaysWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var tasks: [BingoCell] { entry.board.cells.flatMap { $0 }.filter { !$0.isEmpty } }
    private var completed: Int { tasks.filter(\.isCompleted).count }
    private var progress: Double { tasks.isEmpty ? 0 : Double(completed) / Double(tasks.count) }
    private var boardName: String {
        entry.panels.indices.contains(entry.selectedPanelIndex)
            ? entry.panels[entry.selectedPanelIndex].name : L10n.boardDefaultName(1)
    }
    private var countLabel: String {
        L10n.tr("Completed", zhHans: "已完成", zhHant: "已完成", ja: "完了") + " \(completed)／\(tasks.count)"
    }

    var body: some View {
        Group {
            if family == .accessoryCircular {
                Gauge(value: progress) {
                    Image(systemName: "square.grid.3x3.fill")
                } currentValueLabel: {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .minimumScaleFactor(0.7)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                HStack(spacing: 8) {
                    BingodaysLockScreenMiniBoard(board: entry.board)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(boardName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(countLabel)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(boardName)
        .accessibilityValue(countLabel)
    }
}
