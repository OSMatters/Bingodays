import SwiftUI

struct UpdatePromptOverlayView: View {
    let latestVersion: String
    let items: [String]
    let isPadLayout: Bool
    let onSkip: () -> Void
    let onUpdate: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesAccessibilityType: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalMargin = scaled(16, pad: 24)
            let panelWidth = min(scaled(360, pad: 500), max(0, proxy.size.width - horizontalMargin * 2))
            let contentPadding = min(scaled(34, pad: 44), max(22, panelWidth * 0.09))
            let availablePanelHeight = max(
                0,
                proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom - 32
            )

            ZStack {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onSkip)
                    .accessibilityHidden(true)

                ViewThatFits(in: .vertical) {
                    promptPanel(panelWidth: panelWidth, contentPadding: contentPadding)
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        promptPanel(panelWidth: panelWidth, contentPadding: contentPadding)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(width: panelWidth)
                .frame(maxHeight: availablePanelHeight)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, onSkip)
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            }
        }
    }

    private func promptPanel(panelWidth: CGFloat, contentPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            hero(panelWidth: panelWidth)
            promptBody(contentPadding: contentPadding)
        }
    }

    private func promptBody(contentPadding: CGFloat) -> some View {
        VStack(spacing: scaled(14, pad: 18)) {
            Text(L10n.updateWhatsNewTitle)
                .appDynamicFont(size: scaled(19, pad: 23), weight: .semibold, design: .rounded)
                .foregroundStyle(updateTextColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, scaled(32, pad: 40))

            changeList

            Button(action: onUpdate) {
                Text(L10n.updatePrimaryAction)
                    .appDynamicFont(size: scaled(16, pad: 18), weight: .semibold, design: .rounded)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .frame(minHeight: scaled(58, pad: 66))
                    .background(
                        Capsule()
                            .fill(updateButtonColor)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, scaled(18, pad: 24))
        }
        .padding(.horizontal, contentPadding)
        .padding(.bottom, scaled(34, pad: 44))
        .background(updateBodyColor)
    }

    private func hero(panelWidth: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Image("UpdatePromptImage")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)

            Button(action: onSkip) {
                Image(systemName: "xmark")
                    .appDynamicFont(size: scaled(21, pad: 25), weight: .medium)
                    .foregroundStyle(updateTextColor)
                    .frame(
                        width: usesAccessibilityType ? scaled(52, pad: 56) : scaled(44, pad: 46),
                        height: usesAccessibilityType ? scaled(52, pad: 56) : scaled(44, pad: 46)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Close", zhHans: "关闭", zhHant: "關閉"))
            .padding(.top, scaled(12, pad: 14))
            .padding(.trailing, scaled(12, pad: 14))
        }
        .frame(height: min(scaled(133, pad: 184), panelWidth * (133.0 / 360.0)))
    }

    private var changeList: some View {
        VStack(alignment: .leading, spacing: scaled(12, pad: 15)) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .appDynamicFont(size: scaled(15, pad: 18), weight: .medium, design: .rounded)
                    .foregroundStyle(updateTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }

    private var updateBodyColor: Color { Color(hex: "F9F5F2") }
    private var updateTextColor: Color { Color(hex: "2F261B") }
    private var updateButtonColor: Color { Color(hex: "D7A879") }
}
