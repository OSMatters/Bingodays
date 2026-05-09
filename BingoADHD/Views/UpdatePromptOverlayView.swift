import SwiftUI

struct UpdatePromptOverlayView: View {
    let latestVersion: String
    let items: [String]
    let isPadLayout: Bool
    let onSkip: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture(perform: onSkip)

            VStack(alignment: .leading, spacing: 18) {
                header
                changeList
                actions
                    .padding(.top, 22)
            }
            .padding(22)
            .frame(maxWidth: isPadLayout ? 560 : 350)
            .background(cardBackground)
            .padding(.horizontal, 24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.updateWhatsNewTitle)
                .font(.appSystem(size: scaled(20, pad: 26), weight: .heavy, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Text(L10n.updateVersionTitle(latestVersion))
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.58))
        }
    }

    private var changeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.appSystem(size: scaled(11, pad: 13), weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: scaled(20, pad: 24), height: scaled(20, pad: 24))
                        .background(
                            Circle()
                                .fill(NeumorphicColors.accent)
                                .shadow(color: NeumorphicColors.accent.opacity(0.28), radius: 6, x: 0, y: 3)
                        )
                        .padding(.top, 1)

                    Text(item)
                        .font(.appSystem(size: scaled(13, pad: 16), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: onSkip) {
                Text(L10n.updateSecondaryAction)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.clear.neumorphicConvex(radius: 18))
            }
            .buttonStyle(.plain)

            Button(action: onUpdate) {
                Text(L10n.updatePrimaryAction)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(NeumorphicColors.bingoAccent)
                            .shadow(color: NeumorphicColors.bingoAccent.opacity(0.24), radius: 10, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(NeumorphicColors.background)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
            .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}
