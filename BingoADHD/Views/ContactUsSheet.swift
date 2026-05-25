import SwiftUI
import UIKit

struct ContactUsSheet: View {
    @Binding var isPresented: Bool
    let isPadLayout: Bool
    let isCopyToastVisible: Bool
    let onCopyEmail: () -> Void
    let onOpenFeedbackEmail: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.contactUsMessage)
                    .font(.appSystem(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                emailCard

                feedbackButton

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
                Text(L10n.contactUsEmailCopied)
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.82))
                    )
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isCopyToastVisible)
        .presentationDetents([.height(isPadLayout ? 410 : 360)])
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

    private var feedbackButton: some View {
        Button(action: onOpenFeedbackEmail) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.open")
                    .font(.appSystem(size: 17, weight: .semibold, design: .rounded))

                Text(L10n.contactUsFeedbackAction)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(NeumorphicColors.accent)
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.24), radius: 8, x: 4, y: 4)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.contactUsFeedbackAction)
    }
}
