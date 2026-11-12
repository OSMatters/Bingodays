import SwiftUI

struct QuickEditPreviewGridView: View {
    @Binding var targetGridSize: Int
    @Binding var previewSlots: [QuickEditPreviewSlot]
    @Binding var previewDragSourceID: UUID?
    @Binding var previewDropTargetID: UUID?

    let selectedCountSummary: String
    let isPadLayout: Bool
    let sectionBackground: Color
    let selectedBadgeBackground: Color
    let previewEmptySlotFill: Color
    let previewFilledSlotFill: Color
    let previewEmptySlotStroke: Color
    let previewFilledSlotStroke: Color
    let onDecreaseGrid: () -> Void
    let onIncreaseGrid: () -> Void
    let onEditSlot: (UUID) -> Void
    let onDeleteSlot: (UUID) -> Void
    let onClearPreviewDrag: () -> Void

    var body: some View {
        let gridSpacing: CGFloat = isPadLayout ? 16 : 12

        VStack(alignment: .leading, spacing: 14) {
            controlsRow

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: targetGridSize),
                spacing: gridSpacing
            ) {
                ForEach(previewSlots) { slot in
                    QuickEditPreviewSlotCard(
                        slot: slot,
                        isPadLayout: isPadLayout,
                        emptySlotFill: previewEmptySlotFill,
                        filledSlotFill: previewFilledSlotFill,
                        emptySlotStroke: previewEmptySlotStroke,
                        filledSlotStroke: previewFilledSlotStroke
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        RoundedRectangle(cornerRadius: isPadLayout ? 18 : 16)
                            .stroke(Color(hex: "D79863"), lineWidth: previewDropTargetID == slot.id ? 2 : 0)
                            .allowsHitTesting(false)
                    }
                    .onDrag {
                        guard slot.task != nil else { return NSItemProvider() }
                        previewDragSourceID = slot.id
                        previewDropTargetID = nil
                        return NSItemProvider(object: NSString(string: slot.id.uuidString))
                    }
                    .onDrop(
                        of: ["public.text", "public.plain-text"],
                        delegate: QuickEditPreviewDropDelegate(
                            targetSlotID: slot.id,
                            previewSlots: $previewSlots,
                            dragSourceID: $previewDragSourceID,
                            dropTargetID: $previewDropTargetID
                        )
                    )
                    .contextMenu {
                        if slot.task != nil {
                            Button {
                                onEditSlot(slot.id)
                            } label: {
                                Label(L10n.editTask, systemImage: "square.and.pencil")
                            }

                            Button(role: .destructive) {
                                onDeleteSlot(slot.id)
                            } label: {
                                Label(L10n.deleteTask, systemImage: "trash")
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if slot.task != nil {
                            Button {
                                onDeleteSlot(slot.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.appSystem(size: 20, weight: .medium))
                                    .foregroundStyle(NeumorphicColors.text.opacity(0.65), Color.white.opacity(0.95))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .offset(x: -8, y: -8)
                            .accessibilityLabel(L10n.tr("Remove from board", zhHans: "从棋盘移除", zhHant: "從棋盤移除"))
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .onDrop(of: ["public.text", "public.plain-text"], isTargeted: nil) { _ in
                onClearPreviewDrag()
                return false
            }
        }
        .padding(isPadLayout ? 22 : 18)
        .background(
            RoundedRectangle(cornerRadius: isPadLayout ? 30 : 26, style: .continuous)
                .fill(sectionBackground)
        )
    }

    private var controlsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                gridSizeControls
                Spacer(minLength: 0)
                selectedCountBadge
            }
            VStack(alignment: .leading, spacing: 12) {
                gridSizeControls
                selectedCountBadge
            }
        }
    }

    private var gridSizeControls: some View {
        let controlSize: CGFloat = 44
        let iconSize: CGFloat = isPadLayout ? 18 : 16
        let theme = AppTheme.concise
        return HStack(spacing: isPadLayout ? 10 : 2) {
                Button {
                    onDecreaseGrid()
                } label: {
                    Image(systemName: "minus")
                        .font(.appSystem(size: iconSize, weight: .bold))
                        .foregroundStyle(theme.color)
                        .frame(width: controlSize, height: controlSize)

                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Reduce board size", zhHans: "缩小棋盘", zhHant: "縮小棋盤"))
                .disabled(targetGridSize <= 2)
                .opacity(targetGridSize <= 2 ? 0.45 : 1)

                Text("\(targetGridSize) × \(targetGridSize)")
                    .font(.appSystem(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                    .foregroundStyle(NeumorphicColors.text)

                Button {
                    onIncreaseGrid()
                } label: {
                    Image(systemName: "plus")
                        .font(.appSystem(size: iconSize, weight: .bold))
                        .foregroundStyle(theme.color)
                        .frame(width: controlSize, height: controlSize)

                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Increase board size", zhHans: "扩大棋盘", zhHant: "擴大棋盤"))
                .disabled(targetGridSize >= 5)
                .opacity(targetGridSize >= 5 ? 0.45 : 1)
            }.fixedSize(horizontal: true, vertical: false)
    }

    private var selectedCountBadge: some View {
        Text(selectedCountSummary)
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundStyle(NeumorphicColors.text.opacity(0.92))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(selectedBadgeBackground)
                ).fixedSize(horizontal: true, vertical: false)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }


}

private struct QuickEditPreviewSlotCard: View {
    let slot: QuickEditPreviewSlot
    let isPadLayout: Bool
    let emptySlotFill: Color
    let filledSlotFill: Color
    let emptySlotStroke: Color
    let filledSlotStroke: Color

    var body: some View {
        let cornerRadius: CGFloat = isPadLayout ? 18 : 16
        let hasTask = slot.task != nil

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(hasTask ? filledSlotFill : emptySlotFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(hasTask ? filledSlotStroke : emptySlotStroke, lineWidth: 1)
                )

            if let task = slot.task?.trimmedText, !task.isEmpty {
                Text(task)
                    .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                    .foregroundStyle(NeumorphicColors.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .padding(10)
            }
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}
