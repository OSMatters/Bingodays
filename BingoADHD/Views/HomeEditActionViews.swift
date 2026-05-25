import SwiftUI

struct GridSizeAdjustmentSheet: View {
    let gridSize: Int
    let isPadLayout: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        let controlSize: CGFloat = isPadLayout ? 56 : 50
        let iconSize: CGFloat = isPadLayout ? 24 : 22

        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: isPadLayout ? 20 : 16) {
                    Button(action: onDecrease) {
                        Image(systemName: "minus")
                            .font(.appSystem(size: iconSize, weight: .bold))
                            .foregroundColor(NeumorphicColors.accent)
                            .frame(width: controlSize, height: controlSize)
                            .background(functionSurface(cornerRadius: controlSize / 2, shadowRadius: isPadLayout ? 10 : 8, offset: isPadLayout ? 5 : 4))
                    }
                    .disabled(gridSize <= 2)
                    .buttonStyle(.plain)
                    .opacity(gridSize <= 2 ? 0.45 : 1)

                    Text("\(gridSize) × \(gridSize)")
                        .font(.appSystem(size: scaled(30, pad: 36), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .frame(minWidth: isPadLayout ? 140 : 120)
                        .multilineTextAlignment(.center)

                    Button(action: onIncrease) {
                        Image(systemName: "plus")
                            .font(.appSystem(size: iconSize, weight: .bold))
                            .foregroundColor(NeumorphicColors.accent)
                            .frame(width: controlSize, height: controlSize)
                            .background(functionSurface(cornerRadius: controlSize / 2, shadowRadius: isPadLayout ? 10 : 8, offset: isPadLayout ? 5 : 4))
                    }
                    .disabled(gridSize >= 5)
                    .buttonStyle(.plain)
                    .opacity(gridSize >= 5 ? 0.45 : 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height * 0.42)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, isPadLayout ? 28 : 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NeumorphicColors.background)
    }

    private func functionSurface(cornerRadius: CGFloat, shadowRadius: CGFloat, offset: CGFloat) -> some View {
        let theme = AppTheme.current
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.color.opacity(theme == .concise ? 0.12 : 0.14))
            .shadow(color: Color.white.opacity(theme == .concise ? 0.72 : 0.62), radius: shadowRadius, x: -offset, y: -offset)
            .shadow(color: theme.bingoSurfaceShadowColor.opacity(0.2), radius: shadowRadius, x: offset, y: offset)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}

struct EditActionsFullscreenOverlay: View {
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onShuffle: () -> Void
    let onClearBoard: () -> Void
    let onGridSize: () -> Void
    let onQuickEdit: () -> Void

    var body: some View {
        ZStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 10)

                Color.black.opacity(0.6)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)

            VStack(spacing: isPadLayout ? 48 : 40) {
                editActionsTextButton(L10n.tr("Shuffle", zhHans: "随机排序"), action: onShuffle)
                editActionsTextButton(L10n.clearBoard, action: onClearBoard)
                editActionsTextButton(L10n.tr("Grid Size", zhHans: "格子大小"), action: onGridSize)
                editActionsTextButton(L10n.quickEdit, action: onQuickEdit)

                editActionsTextButton(
                    L10n.cancel,
                    fontWeight: .semibold,
                    color: Color.white.opacity(0.55),
                    extraTopPadding: isPadLayout ? 14 : 8,
                    action: nil
                )
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editActionsTextButton(
        _ title: String,
        fontWeight: Font.Weight = .bold,
        color: Color = .white,
        extraTopPadding: CGFloat = 0,
        action: (() -> Void)?
    ) -> some View {
        Button {
            onDismiss()
            if let action {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    action()
                }
            }
        } label: {
            Text(title)
                .font(.appSystem(size: scaled(28, pad: 38), weight: fontWeight, design: .rounded))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.top, extraTopPadding)
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}
