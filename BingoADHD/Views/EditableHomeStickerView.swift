import SwiftUI

struct EditableHomeStickerView: View {
    let placement: HomeStickerPlacement
    let canvasSize: CGSize
    let isEditing: Bool
    let onSelect: () -> Void
    let onUpdate: (HomeStickerPlacement) -> Void
    let onDelete: () -> Void

    @State private var dragStartPlacement: HomeStickerPlacement?
    @State private var magnifyStartScale: Double?
    @State private var previewScale: Double?
    @State private var isMagnifying = false

    private var baseStickerWidth: CGFloat {
        placement.kind.homeDisplayWidth
    }

    private var stickerWidth: CGFloat {
        baseStickerWidth * CGFloat(normalizedScale)
    }

    private var normalizedXRatio: Double {
        normalized(placement.xRatio, min: 0.02, max: 0.98, fallback: 0.5)
    }

    private var normalizedYRatio: Double {
        normalized(placement.yRatio, min: 0.02, max: bottomOverflowYRatio, fallback: 0.5)
    }

    private var normalizedScale: Double {
        normalized(previewScale ?? placement.scale, min: 0.5, max: 1.6, fallback: 1.0)
    }

    private var horizontalInsetRatio: Double {
        let inset = stickerWidth / 2
        return clampRatio(inset / max(canvasSize.width, 1))
    }

    private var verticalInsetRatio: Double {
        let inset = stickerWidth / 2
        return clampRatio(inset / max(canvasSize.height, 1))
    }

    private var bottomOverflowYRatio: Double {
        1.08
    }

    var body: some View {
        let position = CGPoint(
            x: canvasSize.width * normalizedXRatio,
            y: canvasSize.height * normalizedYRatio
        )

        ZStack(alignment: .topTrailing) {
            Image(placement.kind.unlockedImageName)
                .resizable()
                .scaledToFit()
                .frame(width: stickerWidth)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.16), radius: 6, x: 3, y: 4)
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(NeumorphicColors.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .padding(2)
                    }
                }

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(NeumorphicColors.accent))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .contentShape(Rectangle())
        .position(position)
        .onTapGesture {
            onSelect()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard isEditing, !isMagnifying else { return }

                    let baseline = dragStartPlacement ?? placement
                    if dragStartPlacement == nil {
                        dragStartPlacement = placement
                    }

                    let newX = clamp(
                        baseline.xRatio + value.translation.width / max(canvasSize.width, 1),
                        min: horizontalInsetRatio,
                        max: 1 - horizontalInsetRatio
                    )
                    let newY = clamp(
                        baseline.yRatio + value.translation.height / max(canvasSize.height, 1),
                        min: verticalInsetRatio,
                        max: bottomOverflowYRatio
                    )

                    onUpdate(
                        HomeStickerPlacement(
                            id: placement.id,
                            kind: placement.kind,
                            xRatio: newX,
                            yRatio: newY,
                            scale: placement.scale
                        )
                    )
                }
                .onEnded { _ in
                    dragStartPlacement = nil
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if !isEditing {
                        onSelect()
                    }
                    isMagnifying = true

                    let baseline = magnifyStartScale ?? placement.scale
                    if magnifyStartScale == nil {
                        magnifyStartScale = placement.scale
                    }

                    let newScale = clamp(baseline * value.magnification, min: 0.5, max: 1.6)
                    previewScale = newScale
                }
                .onEnded { _ in
                    if let previewScale {
                        onUpdate(
                            HomeStickerPlacement(
                                id: placement.id,
                                kind: placement.kind,
                                xRatio: placement.xRatio,
                                yRatio: placement.yRatio,
                                scale: previewScale
                            )
                        )
                    }
                    previewScale = nil
                    magnifyStartScale = nil
                    isMagnifying = false
                }
        )
    }

    private func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }

    private func clampRatio(_ value: CGFloat) -> Double {
        let normalized = Double(value)
        return Swift.max(0.02, Swift.min(normalized, 0.48))
    }

    private func normalized(_ value: Double, min lowerBound: Double, max upperBound: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}
