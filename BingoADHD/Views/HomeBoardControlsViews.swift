import SwiftUI

struct BoardSwitcherControlsView: View {
    let boards: [BingoBoardStore.NamedBoard]
    let selectedBoardID: UUID?
    let contentWidth: CGFloat
    let isPadLayout: Bool
    let shouldShowBoardEditHint: Bool
    let onSelectBoard: (UUID) -> Void
    let onBoardLongPress: (UUID) -> Void
    let onCreateBoard: () -> Void
    let onDismissBoardEditHint: () -> Void
    @State private var hasReservedBoardEditHintSpace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowBoardEditHint || hasReservedBoardEditHintSpace {
                ZStack(alignment: .topLeading) {
                    if shouldShowBoardEditHint {
                        BoardEditHintBubbleView(
                            isPadLayout: isPadLayout,
                            onDismiss: onDismissBoardEditHint
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomLeading)))
                    }
                }
                .frame(height: isPadLayout ? 56 : 51, alignment: .topLeading)
            }

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
                                    .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text)
                                    .padding(.horizontal, 14)
                                    .frame(height: isPadLayout ? 38 : 36)
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
                                .fill(Color.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: shouldShowBoardEditHint)
        .onAppear {
            if shouldShowBoardEditHint {
                hasReservedBoardEditHintSpace = true
            }
        }
        .onChange(of: shouldShowBoardEditHint) { _, newValue in
            if newValue {
                hasReservedBoardEditHintSpace = true
            }
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}

private struct BoardEditHintBubbleView: View {
    let isPadLayout: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: isPadLayout ? 8 : 7) {
                Image(systemName: "hand.tap")
                    .font(.appSystem(size: isPadLayout ? 16 : 14, weight: .medium))
                    .foregroundColor(Color(hex: "9D9D9D"))
                    .frame(width: isPadLayout ? 20 : 18)

                Text(L10n.boardEditHintMessage)
                    .font(.appSystem(size: isPadLayout ? 13 : 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "2B2B2B"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Button(action: onDismiss) {
                    Text(L10n.boardEditHintAcknowledge)
                        .font(.appSystem(size: isPadLayout ? 12 : 11, weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                        .padding(.horizontal, 4)
                        .frame(height: isPadLayout ? 26 : 24)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, isPadLayout ? 18 : 16)
            .padding(.trailing, isPadLayout ? 10 : 8)
            .frame(height: isPadLayout ? 44 : 40)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .shadow(color: Color.black.opacity(0.13), radius: 12, x: 0, y: 5)
                    .shadow(color: Color.white.opacity(0.76), radius: 2, x: 0, y: -1)
            )

            Triangle()
                .fill(Color.white.opacity(0.96))
                .frame(width: isPadLayout ? 20 : 18, height: isPadLayout ? 13 : 12)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 3)
                .offset(x: isPadLayout ? 22 : 20, y: isPadLayout ? 11 : 10)
        }
        .padding(.bottom, isPadLayout ? 12 : 11)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
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

struct BoardBottomControlsView: View {
    let countdownText: String?
    let isPadLayout: Bool
    let isTemplateShareDisabled: Bool
    let isEditActionsExpanded: Bool
    let surfaceShadowColor: Color
    let onTemplateShare: () -> Void
    let onCountdown: () -> Void
    let onEditActionsToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BoardTemplateShareTriggerView(
                isPadLayout: isPadLayout,
                isDisabled: isTemplateShareDisabled,
                onTap: onTemplateShare
            )

            Spacer(minLength: 0)

            if let countdownText {
                BoardCountdownTriggerView(
                    text: countdownText,
                    isPadLayout: isPadLayout,
                    surfaceShadowColor: surfaceShadowColor,
                    onTap: onCountdown
                )
                .offset(y: isPadLayout ? 4 : 3)
            } else {
                Color.clear
                    .frame(width: isPadLayout ? 170 : 140, height: isPadLayout ? 38 : 32)
            }

            Spacer(minLength: 0)

            BoardEditActionsTriggerView(
                isExpanded: isEditActionsExpanded,
                isPadLayout: isPadLayout,
                onTap: onEditActionsToggle
            )
        }
    }
}

struct BoardTemplateShareTriggerView: View {
    let isPadLayout: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        let buttonSize: CGFloat = isPadLayout ? 51 : 45

        if AppFeatureFlags.isTemplateSharingEnabled {
            Button(action: onTap) {
                Image(systemName: "paperplane.fill")
                    .font(.appSystem(size: isPadLayout ? 22 : 20, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: buttonSize, height: buttonSize)
                    .appLiquidGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel(L10n.shareBoardTemplate)
        } else {
            Color.clear
                .frame(width: buttonSize, height: buttonSize)
        }
    }
}

struct BoardEditActionsTriggerView: View {
    let isExpanded: Bool
    let isPadLayout: Bool
    let onTap: () -> Void

    var body: some View {
        let buttonSize: CGFloat = isPadLayout ? 51 : 45

        Button(action: onTap) {
            Image(systemName: isExpanded ? "xmark" : "square.and.pencil")
                .font(.appSystem(size: isPadLayout ? 28 : 26, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: buttonSize, height: buttonSize)
                .appLiquidGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize, height: buttonSize, alignment: .bottomTrailing)
    }
}

struct BoardCountdownTriggerView: View {
    let text: String
    let isPadLayout: Bool
    let surfaceShadowColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(text)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: scaled(11, pad: 12), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)
            }
            .padding(.horizontal, isPadLayout ? 20 : 16)
            .frame(height: isPadLayout ? 38 : 32)
            .frame(minWidth: isPadLayout ? 152 : 124)
            .background(
                themedFunctionSurface(
                    cornerRadius: isPadLayout ? 19 : 16,
                    shadowRadius: isPadLayout ? 12 : 10,
                    offset: isPadLayout ? 6 : 5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func themedFunctionSurface(cornerRadius: CGFloat, shadowRadius: CGFloat, offset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.5))
            .shadow(color: Color.white, radius: shadowRadius + 3, x: -offset - 1, y: -offset - 1)
            .shadow(color: surfaceShadowColor.opacity(0.2), radius: shadowRadius + 3, x: offset + 1, y: offset + 1)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}
