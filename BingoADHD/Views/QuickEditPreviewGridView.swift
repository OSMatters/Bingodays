import SwiftUI

struct QuickEditPreviewGridView: View {
    @Binding var targetGridSize: Int
    @Binding var previewSlots: [QuickEditView.PreviewSlot]
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
                }
            }
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
        let controlSize: CGFloat = isPadLayout ? 38 : 32
        let iconSize: CGFloat = isPadLayout ? 18 : 16
        let theme = AppTheme.concise

        return HStack(alignment: .center, spacing: 12) {
            HStack(spacing: isPadLayout ? 14 : 11) {
                Button {
                    onDecreaseGrid()
                } label: {
                    Image(systemName: "minus")
                        .font(.appSystem(size: iconSize, weight: .bold))
                        .foregroundColor(theme.color)
                        .frame(width: controlSize, height: controlSize)
                        .background(controlButtonSurface(size: controlSize))
                }
                .buttonStyle(.plain)
                .disabled(targetGridSize <= 2)
                .opacity(targetGridSize <= 2 ? 0.45 : 1)

                Text("\(targetGridSize)")
                    .font(.appSystem(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Image(systemName: "xmark")
                    .font(.appSystem(size: scaled(10, pad: 12), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.6))

                Text("\(targetGridSize)")
                    .font(.appSystem(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Button {
                    onIncreaseGrid()
                } label: {
                    Image(systemName: "plus")
                        .font(.appSystem(size: iconSize, weight: .bold))
                        .foregroundColor(theme.color)
                        .frame(width: controlSize, height: controlSize)
                        .background(controlButtonSurface(size: controlSize))
                }
                .buttonStyle(.plain)
                .disabled(targetGridSize >= 5)
                .opacity(targetGridSize >= 5 ? 0.45 : 1)
            }

            Spacer(minLength: 0)

            Text(selectedCountSummary)
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.92))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(selectedBadgeBackground)
                )
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private func controlButtonSurface(size: CGFloat) -> some View {
        let theme = AppTheme.concise
        return Circle()
            .fill(theme.color.opacity(theme == .concise ? 0.12 : 0.14))
            .shadow(color: Color.white.opacity(theme == .concise ? 0.72 : 0.62), radius: 6, x: -3, y: -3)
            .shadow(color: theme.bingoSurfaceShadowColor.opacity(0.2), radius: 6, x: 3, y: 3)
            .frame(width: size, height: size)
    }
}

private struct QuickEditPreviewSlotCard: View {
    let slot: QuickEditView.PreviewSlot
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
                    .font(.appSystem(size: scaled(14, pad: 18), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
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
