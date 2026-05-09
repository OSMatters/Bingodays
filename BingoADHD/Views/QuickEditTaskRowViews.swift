import SwiftUI

struct QuickEditReadOnlyTaskRow: View {
    let text: String
    let isSelected: Bool
    let isPadLayout: Bool
    let taskBackground: Color
    let fieldStroke: Color
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            selectionButton(action: onToggle)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .medium))
                    .foregroundColor(NeumorphicColors.text.opacity(0.52))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .quickEditTaskRowSurface(background: taskBackground, stroke: fieldStroke)
    }

    private func selectionButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.38))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

struct QuickEditLockedTaskRow: View {
    let text: String
    let isPadLayout: Bool
    let taskBackground: Color
    let fieldStroke: Color
    let onUnlock: () -> Void

    var body: some View {
        Button(action: onUnlock) {
            ZStack {
                lockedRowContent(text: text)
                    .quickEditTaskRowSurface(background: taskBackground, stroke: fieldStroke)
                    .blur(radius: 2.8)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.18))

                lockBadge
            }
        }
        .buttonStyle(.plain)
    }

    private func lockedRowContent(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.28))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var lockBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.appSystem(size: scaled(11, pad: 13), weight: .bold))
            Text(L10n.quickEditHistoryPaywallHint)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.96))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.32))
        )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

struct QuickEditLockedHistoryPreviewBlock: View {
    let taskTexts: [String]
    let isPadLayout: Bool
    let taskBackground: Color
    let fieldStroke: Color
    let onUnlock: () -> Void

    var body: some View {
        Button(action: onUnlock) {
            ZStack {
                VStack(spacing: 10) {
                    ForEach(Array(taskTexts.enumerated()), id: \.offset) { _, text in
                        lockedPreviewRow(text: text)
                            .quickEditTaskRowSurface(background: taskBackground, stroke: fieldStroke)
                    }
                }
                .blur(radius: 2.8)
                .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.2))
                    .overlay(previewLockBadge)
            }
        }
        .buttonStyle(.plain)
    }

    private func lockedPreviewRow(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.28))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var previewLockBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.appSystem(size: scaled(11, pad: 13), weight: .bold))
            Text(L10n.quickEditHistoryPaywallHint)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.96))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.36))
        )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

struct QuickEditAddTaskButton: View {
    let isPadLayout: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(L10n.addTask)
                .font(.appSystem(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(NeumorphicColors.accent)
                        .shadow(color: NeumorphicColors.accent.opacity(0.24), radius: 10, x: 0, y: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

private extension View {
    func quickEditTaskRowSurface(background: Color, stroke: Color) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(background)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
