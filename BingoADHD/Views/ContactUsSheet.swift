import SwiftUI

struct ContactUsSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var isPresented: Bool
    let isPadLayout: Bool
    let isCopyToastVisible: Bool
    let onCopyEmail: () -> Void
    let onOpenBugReportEmail: () -> Void
    let onOpenFeatureSuggestionEmail: () -> Void

    private var usesReflowedLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: 0) {
            heroSection

            Group {
                if usesReflowedLayout {
                    ScrollView(showsIndicators: false) {
                        contactDetails
                            .frame(maxWidth: 560)
                            .padding(.bottom, 28)
                    }
                } else {
                    contactDetails
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(hex: "F7F2EE"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "F7F2EE"))
        .clipShape(RoundedRectangle(cornerRadius: scaled(16, pad: 20), style: .continuous))
        .presentationDetents(
            usesReflowedLayout ? [.large] : [.height(isPadLayout ? 600 : 554)]
        )
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(hex: "F7F2EE"))
    }

    private var contactDetails: some View {
        VStack(spacing: scaled(22, pad: 26)) {
            VStack(spacing: scaled(14, pad: 16)) {
                Text(L10n.tr("Support", zhHans: "支持", zhHant: "支援", ja: "サポート"))
                    .appDynamicFont(size: scaled(22, pad: 25), weight: .heavy, design: .rounded)
                    .foregroundStyle(NeumorphicColors.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.contactUsMessage)
                    .appDynamicFont(size: scaled(15, pad: 17), weight: .medium, design: .rounded)
                    .foregroundStyle(Color(hex: "7E7E7E"))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .offset(y: usesReflowedLayout ? 0 : scaled(-10, pad: -12))

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
        .padding(.horizontal, usesReflowedLayout ? 28 : scaled(42, pad: 56))
        .padding(.top, usesReflowedLayout ? 28 : scaled(46, pad: 54))
        .padding(.bottom, usesReflowedLayout ? 28 : scaled(56, pad: 68))
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(hex: "F7F2EE"))
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
                        .foregroundStyle(Color(hex: "201915"))
                        .frame(width: max(scaled(36, pad: 42), 44), height: max(scaled(36, pad: 42), 44))
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
                .appDynamicFont(size: scaled(17, pad: 19), weight: .bold, design: .rounded)
                .foregroundStyle(isPrimary ? .white : NeumorphicColors.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: scaled(58, pad: 66))
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
