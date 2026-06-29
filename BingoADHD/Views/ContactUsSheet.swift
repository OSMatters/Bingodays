import SwiftUI
import UIKit

struct ContactUsSheet: View {
    @Binding var isPresented: Bool
    let isPadLayout: Bool
    let isCopyToastVisible: Bool
    let onCopyEmail: () -> Void
    let onOpenBugReportEmail: () -> Void
    let onOpenFeatureSuggestionEmail: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.contactUsMessage)
                    .font(.appSystem(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                emailCard

                actionButtons

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(NeumorphicColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.done)
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isCopyToastVisible {
                IOSNativeToastView(
                    L10n.contactUsEmailCopied,
                    isPadLayout: isPadLayout
                )
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isCopyToastVisible)
        .presentationDetents([.height(isPadLayout ? 470 : 420)])
        .presentationDragIndicator(.visible)
        .presentationBackground(NeumorphicColors.background)
    }

    private var emailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.contactUsEmailLabel)
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.56))

            HStack(spacing: 10) {
                Text(L10n.contactUsEmail)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.accent)
                    .textSelection(.enabled)

                Spacer(minLength: 0)

                Button {
                    UIPasteboard.general.string = L10n.contactUsEmail
                    onCopyEmail()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(NeumorphicColors.background)
                                .shadow(color: NeumorphicColors.lightShadow.opacity(0.8), radius: 4, x: -2, y: -2)
                                .shadow(color: NeumorphicColors.darkShadow.opacity(0.25), radius: 4, x: 2, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.contactUsCopyEmailAction)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.8), radius: 8, x: -4, y: -4)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.42), radius: 8, x: 4, y: 4)
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            contactActionButton(
                title: L10n.contactUsBugReportAction,
                systemImage: "exclamationmark.bubble",
                isPrimary: true,
                action: onOpenBugReportEmail
            )

            contactActionButton(
                title: L10n.contactUsFeatureSuggestionAction,
                systemImage: "lightbulb",
                isPrimary: false,
                action: onOpenFeatureSuggestionEmail
            )
        }
    }

    private func contactActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.appSystem(size: 17, weight: .semibold, design: .rounded))

                Text(title)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundColor(isPrimary ? .white : NeumorphicColors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(isPrimary ? NeumorphicColors.accent : NeumorphicColors.background)
                    .shadow(color: NeumorphicColors.lightShadow.opacity(isPrimary ? 0 : 0.8), radius: 6, x: -3, y: -3)
                    .shadow(color: NeumorphicColors.darkShadow.opacity(isPrimary ? 0.24 : 0.34), radius: 8, x: 4, y: 4)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
