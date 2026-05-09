import SwiftUI

struct BoardSwitcherControlsView: View {
    let boards: [BingoBoardStore.NamedBoard]
    let selectedBoardID: UUID?
    let contentWidth: CGFloat
    let isPadLayout: Bool
    let onSelectBoard: (UUID) -> Void
    let onBoardLongPress: (UUID) -> Void
    let onCreateBoard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(boards) { board in
                        let isSelected = board.id == selectedBoardID

                        Button {
                            onSelectBoard(board.id)
                        } label: {
                            Text(board.name)
                                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundColor(isSelected ? .white : NeumorphicColors.text)
                                .padding(.horizontal, 14)
                                .frame(height: isPadLayout ? 38 : 36)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isSelected ? NeumorphicColors.accent : NeumorphicColors.background)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(
                                            isSelected ? NeumorphicColors.accent : NeumorphicColors.accent.opacity(0.22),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    onBoardLongPress(board.id)
                                }
                        )
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCreateBoard) {
                Text(L10n.tr("+ add board", zhHans: "+ 添加棋盘", zhHant: "+ 新增棋盤"))
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: isPadLayout ? 38 : 36)
                    .background(
                        RoundedRectangle(cornerRadius: isPadLayout ? 19 : 18, style: .continuous)
                            .fill(NeumorphicColors.background)
                            .shadow(color: Color.white.opacity(0.7), radius: isPadLayout ? 8 : 6, x: -4, y: -4)
                            .shadow(color: NeumorphicColors.darkShadow.opacity(0.22), radius: isPadLayout ? 8 : 6, x: 4, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}

struct BoardActionsOverlayView: View {
    let canDelete: Bool
    let contentWidth: CGFloat
    let bottomInset: CGFloat
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onBoardRules: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 12) {
                actionButton(
                    title: L10n.tr("Board Rules", zhHans: "面板规则", zhHant: "面板規則"),
                    color: NeumorphicColors.text,
                    action: onBoardRules
                )

                actionButton(
                    title: L10n.tr("Edit", zhHans: "编辑", zhHant: "編輯"),
                    color: NeumorphicColors.text,
                    action: onEdit
                )

                if canDelete {
                    actionButton(
                        title: L10n.deleteConfirmationTitle,
                        color: Color.red.opacity(0.84),
                        action: onDelete
                    )
                }
            }
            .frame(width: min(contentWidth, isPadLayout ? 460 : 353))
            .padding(.bottom, max(bottomInset, 14) + 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func actionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NeumorphicColors.background)
                )
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}
