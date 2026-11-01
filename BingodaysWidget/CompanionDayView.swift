import SwiftUI

struct CompanionDayView: View {
    let date: Date
    let state: AppOpenWidgetSnapshot.DayState
    let ink: Color
    let accent: Color
    var milestone: Int? = nil

    var body: some View {
        VStack(spacing: 7) {
            Text(date, format: .dateTime.weekday(.narrow))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ink.opacity(0.75))
            ZStack {
                switch state {
                case .opened:
                    if let milestone {
                        Image("AppIconPreview\(milestone)Days")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white, lineWidth: 1) }
                    } else {
                        Circle().fill(accent)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                case .missed:
                    Circle().fill(ink.opacity(0.09))
                    Image(systemName: "minus").font(.system(size: 8, weight: .semibold)).foregroundStyle(ink.opacity(0.45))
                case .today:
                    Circle().strokeBorder(accent, lineWidth: 1.8)
                case .future:
                    Circle().fill(ink.opacity(0.12)).frame(width: 6, height: 6)
                case .unknown:
                    Circle().strokeBorder(ink.opacity(0.15), lineWidth: 1)
                }
            }
            .frame(width: 19, height: 19)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(stateLabel)
    }

    private var stateLabel: String {
        switch state {
        case .opened:
            if let milestone {
                L10n.tr("\(milestone) day app icon unlocked", zhHans: "已打开，解锁 \(milestone) 天图标", ja: "起動済み、\(milestone)日のアイコンを解放")
            } else {
                L10n.tr("Opened", zhHans: "已打开", ja: "起動済み")
            }
        case .missed: L10n.tr("Missed", zhHans: "漏打开", ja: "起動なし")
        case .today: L10n.tr("Not opened today", zhHans: "今天尚未打开", ja: "今日は未起動")
        case .future: L10n.tr("Upcoming", zhHans: "未来日期", ja: "これから")
        case .unknown: L10n.tr("No record", zhHans: "暂无记录", ja: "記録なし")
        }
    }
}
