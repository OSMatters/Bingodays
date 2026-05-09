import SwiftUI

struct QuickEditTaskListHeaderView: View {
    let title: String
    let activeGroupID: UUID?
    let canApplyGroup: Bool
    let isPadLayout: Bool
    let taskBackground: Color
    let onApplyGroup: () -> Void
    let onDeleteGroup: (UUID) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.appSystem(size: scaled(15, pad: 19), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Spacer(minLength: 0)

            if let activeGroupID {
                Button(action: onApplyGroup) {
                    actionLabel(systemName: "square.grid.2x2", title: L10n.quickEditApplyGroup)
                        .foregroundColor(NeumorphicColors.accent)
                        .background(actionBackground(stroke: NeumorphicColors.accent.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .disabled(!canApplyGroup)
                .opacity(canApplyGroup ? 1 : 0.45)

                Button {
                    onDeleteGroup(activeGroupID)
                } label: {
                    actionLabel(
                        systemName: "trash",
                        title: L10n.tr("Delete Group", zhHans: "删除分组", zhHant: "刪除分組")
                    )
                    .foregroundColor(NeumorphicColors.bingoAccent)
                    .background(actionBackground(stroke: NeumorphicColors.bingoAccent.opacity(0.28)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionLabel(systemName: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.appSystem(size: scaled(11, pad: 13), weight: .semibold))
            Text(title)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func actionBackground(stroke: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(taskBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}
