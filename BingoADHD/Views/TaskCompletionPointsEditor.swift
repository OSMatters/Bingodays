import SwiftUI

/// Draft-only control; the task editor owns validation and saving.
struct TaskCompletionPointsEditor: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var pointsText: String
    let hasPremiumAccess: Bool
    let onRequestPremium: () -> Void
    @FocusState private var isPointsFocused: Bool

    private var isPadLayout: Bool { horizontalSizeClass == .regular }
    private var numberSize: CGFloat { isPadLayout ? 44 : 36 }
    private var title: String {
        L10n.tr("Completion points", zhHans: "完成积分", zhHant: "完成積分", ja: "完了ポイント")
    }
    private var points: Int {
        min(max(Int(pointsText) ?? 1, 1), TaskCompletionRewardRules.allowedPoints.upperBound)
    }

    var body: some View {
        if hasPremiumAccess {
            row
        } else {
            Button(action: onRequestPremium) { row }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(pointsText)
                .accessibilityHint(L10n.tr("Unlock with Premium", zhHans: "开通会员即可设置", zhHant: "開通會員即可設定", ja: "プレミアムで設定できます"))
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.circle")
                .font(.appSystem(size: isPadLayout ? 20 : 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(title)
                .font(.custom("Outfit", size: isPadLayout ? 16 : 14).weight(.medium))
                .kerning(-0.15)
                .foregroundStyle(Color.white.opacity(0.96))

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                adjustmentButton(incrementing: false)
                Group {
                    if hasPremiumAccess {
                        TextField("1", text: $pointsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .focused($isPointsFocused)
                            .accessibilityLabel(title)
                            .accessibilityIdentifier("taskCompletionPointsInput")
                    } else {
                        Text(pointsText)
                    }
                }
                .font(.appSystem(size: isPadLayout ? 18 : 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: numberSize, height: numberSize)
                .background(Color(hex: "3F3F3F"), in: RoundedRectangle(cornerRadius: 8))
                adjustmentButton(incrementing: true)
            }
        }
        .frame(height: numberSize)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func adjustmentButton(incrementing: Bool) -> some View {
        if hasPremiumAccess {
            Button {
                isPointsFocused = false
                pointsText = String(min(max(points + (incrementing ? 1 : -1), 1), TaskCompletionRewardRules.allowedPoints.upperBound))
            } label: {
                adjustmentSymbol(incrementing: incrementing)
            }
            .buttonStyle(.plain)
            .disabled(incrementing ? points >= TaskCompletionRewardRules.allowedPoints.upperBound : points <= 1)
            .accessibilityLabel(incrementing
                ? L10n.tr("Increase points", zhHans: "增加积分", zhHant: "增加積分", ja: "ポイントを増やす")
                : L10n.tr("Decrease points", zhHans: "减少积分", zhHant: "減少積分", ja: "ポイントを減らす"))
        } else {
            adjustmentSymbol(incrementing: incrementing)
        }
    }

    private func adjustmentSymbol(incrementing: Bool) -> some View {
        Image(systemName: incrementing ? "plus" : "minus")
            .font(.appSystem(size: isPadLayout ? 18 : 16, weight: .medium))
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
