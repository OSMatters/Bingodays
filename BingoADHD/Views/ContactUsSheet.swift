import SwiftUI

struct ContactUsSheet: View {
    @Binding var isPresented: Bool
    let isPadLayout: Bool
    let isCopyToastVisible: Bool
    let onCopyEmail: () -> Void
    let onOpenBugReportEmail: () -> Void
    let onOpenFeatureSuggestionEmail: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            heroSection

            VStack(spacing: scaled(22, pad: 26)) {
                VStack(spacing: scaled(14, pad: 16)) {
                    Text(L10n.tr("Support", zhHans: "支持", zhHant: "支援", ja: "サポート"))
                        .font(.appSystem(size: scaled(22, pad: 25), weight: .heavy, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(L10n.contactUsMessage)
                        .font(.appSystem(size: scaled(15, pad: 17), weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "7E7E7E"))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .offset(y: scaled(-10, pad: -12))

                VStack(spacing: scaled(14, pad: 16)) {
                    contactActionButton(
                        title: L10n.contactUsBugReportAction,
                        isPrimary: true,
                        action: onOpenBugReportEmail
                    )

                    contactActionButton(
                        title: L10n.contactUsFeatureSuggestionAction,
                        isPrimary: false,
                        action: onOpenFeatureSuggestionEmail
                    )
                }
            }
            .padding(.horizontal, scaled(42, pad: 56))
            .padding(.top, scaled(46, pad: 54))
            .padding(.bottom, scaled(56, pad: 68))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(hex: "F7F2EE"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "F7F2EE"))
        .clipShape(RoundedRectangle(cornerRadius: scaled(16, pad: 20), style: .continuous))
        .presentationDetents([.height(isPadLayout ? 600 : 554)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(hex: "F7F2EE"))
    }

    private var heroSection: some View {
        GeometryReader { proxy in
            let imageWidth = min(proxy.size.width, scaled(420, pad: 480))
            let imageHeight = imageWidth * (366.0 / 786.0)

            ZStack(alignment: .topTrailing) {
                Color(hex: "FFF0DE")

                Image("ContactSupport")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: imageWidth, height: imageHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .accessibilityHidden(true)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: scaled(18, pad: 21), weight: .semibold))
                        .foregroundColor(Color(hex: "201915"))
                        .frame(width: scaled(36, pad: 42), height: scaled(36, pad: 42))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.done)
                .padding(.top, scaled(22, pad: 26))
                .padding(.trailing, scaled(10, pad: 16))
            }
        }
        .frame(height: scaled(244, pad: 282))
    }

    private func contactActionButton(
        title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(17, pad: 19), weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundColor(isPrimary ? .white : NeumorphicColors.text)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(58, pad: 66))
                .background(
                    Capsule(style: .continuous)
                        .fill(isPrimary ? Color(hex: "D9A574") : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(hex: "D9A574"), lineWidth: isPrimary ? 0 : 1.2)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}
