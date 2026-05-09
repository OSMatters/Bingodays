import SwiftUI

struct DailyResetToastView: View {
    let isPadLayout: Bool

    var body: some View {
        Text(L10n.newDayResetMessage)
            .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.96))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(NeumorphicColors.accent.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.28), lineWidth: 1)
                    )
            )
            .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}

struct CommonTasksToastView: View {
    let message: String
    let isPadLayout: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.appSystem(size: scaled(18, pad: 21), weight: .bold))
                .foregroundColor(.white.opacity(0.96))

            Text(message)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.96))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NeumorphicColors.accent.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                )
        )
        .shadow(color: NeumorphicColors.darkShadow.opacity(0.22), radius: 16, x: 0, y: 8)
        .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}
