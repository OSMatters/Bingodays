import SwiftUI

struct IOSNativeToastView: View {
    let message: String
    let systemImage: String?
    let actionTitle: String?
    let isPadLayout: Bool
    let maxLines: Int
    let action: (() -> Void)?

    init(
        _ message: String,
        systemImage: String? = nil,
        actionTitle: String? = nil,
        isPadLayout: Bool,
        maxLines: Int = 2,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.isPadLayout = isPadLayout
        self.maxLines = maxLines
        self.action = action
    }

    var body: some View {
        HStack(spacing: scaled(10, pad: 12)) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: scaled(17, pad: 20), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.94))
            }

            Text(message)
                .font(.system(size: scaled(14, pad: 16), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(maxLines)
                .multilineTextAlignment(messageAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: actionTitle == nil ? nil : .infinity, alignment: .leading)

            if let actionTitle, let action {
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: scaled(20, pad: 22))

                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: scaled(14, pad: 16), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, actionTitle == nil ? scaled(16, pad: 18) : scaled(18, pad: 20))
        .padding(.vertical, scaled(11, pad: 13))
        .background(toastBackground)
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 1)
        .accessibilityElement(children: .combine)
    }

    private var messageAlignment: TextAlignment {
        systemImage == nil && actionTitle == nil ? .center : .leading
    }

    private var toastBackground: some View {
        RoundedRectangle(cornerRadius: scaled(17, pad: 20), style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: scaled(17, pad: 20), style: .continuous)
                    .fill(Color.black.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: scaled(17, pad: 20), style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

struct DailyResetToastView: View {
    let isPadLayout: Bool

    var body: some View {
        IOSNativeToastView(
            L10n.newDayResetMessage,
            isPadLayout: isPadLayout
        )
    }
}

struct CompletedSingleTaskRemovalToastView: View {
    let isPadLayout: Bool

    var body: some View {
        IOSNativeToastView(
            L10n.completedSingleTaskRemovedMessage,
            systemImage: "checkmark.circle.fill",
            isPadLayout: isPadLayout
        )
    }
}

struct CommonTasksToastView: View {
    let message: String
    let isPadLayout: Bool

    var body: some View {
        IOSNativeToastView(
            message,
            systemImage: "checkmark.circle.fill",
            isPadLayout: isPadLayout
        )
        .frame(maxWidth: .infinity)
    }
}
