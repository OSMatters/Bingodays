import SwiftUI

struct MacTaskCell: View {
    let cell: BingoCell
    let theme: AppTheme
    let isInLine: Bool
    let isSelected: Bool
    let isOrganizing: Bool
    let isAvailable: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(cell.isCompleted ? theme.bingoSurfaceColor : Color.white.opacity(0.82))
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(isSelected ? theme.color : (isInLine ? theme.bingoAccentColor : theme.bingoCellOutlineColor), style: StrokeStyle(lineWidth: isInLine || isSelected ? 3 : 2, dash: cell.hasStoredTask ? [] : [5, 4]))
                VStack(spacing: 7) {
                    if cell.isCompleted { Image(systemName: "checkmark").font(.title3.bold()).foregroundStyle(theme.color) }
                    if cell.hasStoredTask {
                        Text(cell.text.isEmpty ? cell.storedTaskText : cell.text)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.75)
                            .foregroundStyle(theme.textColor.opacity(isAvailable || cell.isCompleted ? 1 : 0.45))
                        if let deadline = cell.countdownEndsAt, !cell.isCompleted {
                            Text(deadline, style: .timer).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        } else if cell.countdownPausedRemainingSeconds != nil {
                            Text("计时已暂停").font(.caption2).foregroundStyle(.secondary)
                        }
                        if !isAvailable && !cell.isCompleted { Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary) }
                    } else {
                        Image(systemName: "plus").font(.title3).foregroundStyle(theme.color.opacity(isHovered ? 1 : 0.45))
                    }
                }.padding(14)
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(isHovered ? 1.025 : 1)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if cell.hasStoredTask && (isHovered || isOrganizing) {
                Button(action: onEdit) { Image(systemName: "pencil").font(.caption).padding(7).background(.regularMaterial, in: Circle()) }
                    .buttonStyle(.plain).padding(5).help("编辑任务").accessibilityLabel("编辑任务")
            }
        }
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: cell.isCompleted)
        .contextMenu { Button("编辑任务", systemImage: "pencil", action: onEdit) }
        .help(cell.hasStoredTask ? (isAvailable ? "点击完成或取消完成；右键编辑" : "任务尚未开放或已锁定，右键可编辑") : "添加任务")
        .accessibilityLabel(cell.hasStoredTask ? cell.storedTaskText : "空白格，添加任务")
        .accessibilityValue(cell.isCompleted ? "已完成" : "未完成")
        .accessibilityAction(named: "编辑任务", onEdit)
    }
}
