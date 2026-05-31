import SwiftUI

struct UpdatePromptOverlayView: View {
    let latestVersion: String
    let items: [String]
    let isPadLayout: Bool
    let onSkip: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture(perform: onSkip)

            VStack(spacing: 0) {
                hero

                VStack(spacing: scaled(14, pad: 18)) {
                    Text(L10n.updateWhatsNewTitle)
                        .font(.appSystem(size: scaled(19, pad: 23), weight: .semibold, design: .rounded))
                        .foregroundColor(updateTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.top, scaled(32, pad: 40))

                    changeList

                    Button(action: onUpdate) {
                        Text(L10n.updatePrimaryAction)
                            .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: scaled(58, pad: 66))
                            .background(
                                Capsule()
                                    .fill(updateButtonColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, scaled(18, pad: 24))
                }
                .padding(.horizontal, scaled(34, pad: 44))
                .padding(.bottom, scaled(34, pad: 44))
                .background(updateBodyColor)
            }
            .frame(maxWidth: isPadLayout ? 500 : 360)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            Image("UpdatePromptImage")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            Button(action: onSkip) {
                Image(systemName: "xmark")
                    .font(.appSystem(size: scaled(21, pad: 25), weight: .medium))
                    .foregroundColor(updateTextColor)
                    .frame(width: scaled(40, pad: 46), height: scaled(40, pad: 46))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, scaled(12, pad: 14))
            .padding(.trailing, scaled(12, pad: 14))
        }
        .frame(height: scaled(133, pad: 184))
    }

    private var changeList: some View {
        VStack(alignment: .leading, spacing: scaled(12, pad: 15)) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(updateTextColor)
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
