import SwiftUI

struct QuickEditTaskTagView: View {
    let item: QuickEditTaskTagItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void
    let onUnlock: () -> Void
    @ScaledMetric(relativeTo: .body) private var tagHeight = 44

    @ScaledMetric(relativeTo: .body) private var fontSize = 16

    var body: some View {
        Button(action: item.isLocked ? onUnlock : onToggle) {
            HStack(spacing: 8) {
                Text(item.title)
                    .lineLimit(1)
                    .blur(radius: item.isLocked ? 3 : 0)
                if item.isLocked {
                    Image(systemName: "lock.fill")
                        .accessibilityHidden(true)
                } else if item.isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                }
            }
            .font(.appSystem(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(item.isSelected ? Color.white : NeumorphicColors.text)
            .padding(.horizontal, 15)
            .frame(minHeight: tagHeight)
            .frame(maxWidth: 250)
            .background(item.isSelected ? Color(hex: "E5AE7F") : .white, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isLocked ? L10n.quickEditHistoryPaywallHint : item.title)
        .accessibilityValue(item.isSelected ? L10n.tr("Selected", zhHans: "已选择", zhHant: "已選擇") : "")
        .contextMenu {
            if !item.isLocked {
                if item.canEdit {
                    Button(L10n.tr("Edit Details", zhHans: "详细编辑", zhHant: "詳細編輯"), systemImage: "square.and.pencil", action: onEdit)
                }
                if item.canMove {
                    Button(L10n.tr("Move to Group", zhHans: "移动分组", zhHant: "移動分組"), systemImage: "folder", action: onMove)
                }
                Button(L10n.tr("Delete Task", zhHans: "删除待办", zhHant: "刪除待辦"), systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
}
