import SwiftUI

// Prompt overlays share one layer so their z-order stays explicit around board interactions.
struct HomePromptLayer: View {
    let firstStepGuideOverlay: FirstStepGuideOverlay?
    let pendingUpdateInfo: AppUpdateInfo?
    let isUpdatePromptPresented: Bool
    let isAppReviewPromptPresented: Bool
    let isCustomResetDowngradeAlertPresented: Bool
    let isPremiumBackgroundDowngradeAlertPresented: Bool
    let customResetDowngradeBoardNames: [String]
    let isPadLayout: Bool
    let onFirstStepGuideStart: () -> Void
    let onFirstStepGuideDismiss: () -> Void
    let onUpdateSkip: () -> Void
    let onUpdate: () -> Void
    let onRateApp: () -> Void
    let onOpenFeedbackEmail: () -> Void
    let onRejectAppReviewPrompt: () -> Void
    let onCloseAppReviewPrompt: () -> Void
    let onCustomResetDowngradeClose: () -> Void
    let onCustomResetDowngradeRestore: () -> Void
    let onPremiumBackgroundDowngradeContinue: () -> Void
    let onPremiumBackgroundDowngradeNoThanks: () -> Void

    private var isShowingPrompt: Bool {
        firstStepGuideOverlay != nil ||
            isUpdatePromptPresented ||
            isAppReviewPromptPresented ||
            isCustomResetDowngradeAlertPresented ||
            isPremiumBackgroundDowngradeAlertPresented
    }

    var body: some View {
        Group {
            if let firstStepGuideOverlay {
                FirstStepGuideOverlayView(
                    overlay: firstStepGuideOverlay,
                    isPadLayout: isPadLayout,
                    presentation: FirstStepGuideStore.overlayPresentation,
                    onStart: onFirstStepGuideStart,
                    onDismiss: onFirstStepGuideDismiss
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(40)
            }

            if isUpdatePromptPresented, let pendingUpdateInfo {
                UpdatePromptOverlayView(
                    latestVersion: pendingUpdateInfo.latestVersion,
                    items: AppUpdatePromptStore.releaseNotesItems(for: pendingUpdateInfo),
                    isPadLayout: isPadLayout,
                    onSkip: onUpdateSkip,
                    onUpdate: onUpdate
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if isAppReviewPromptPresented {
                AppReviewPromptOverlayView(
                    isPadLayout: isPadLayout,
                    onRateApp: onRateApp,
                    onOpenFeedbackEmail: onOpenFeedbackEmail,
                    onReject: onRejectAppReviewPrompt,
                    onClose: onCloseAppReviewPrompt
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(80)
            }

            if isCustomResetDowngradeAlertPresented {
                CustomResetDowngradeOverlay(
                    boardNames: customResetDowngradeBoardNames,
                    isPadLayout: isPadLayout,
                    onClose: onCustomResetDowngradeClose,
                    onRestore: onCustomResetDowngradeRestore
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(90)
            }

            if isPremiumBackgroundDowngradeAlertPresented && !isCustomResetDowngradeAlertPresented {
                PremiumBackgroundDowngradeOverlay(
                    isPadLayout: isPadLayout,
                    onContinue: onPremiumBackgroundDowngradeContinue,
                    onNoThanks: onPremiumBackgroundDowngradeNoThanks
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(95)
            }
        }
        .allowsHitTesting(isShowingPrompt)
    }
}

private struct AppReviewPromptOverlayView: View {
    let isPadLayout: Bool
    let onRateApp: () -> Void
    let onOpenFeedbackEmail: () -> Void
    let onReject: () -> Void
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let horizontalMargin = scaled(10, pad: 24)
            let panelWidth = min(scaled(393, pad: 430), max(280, proxy.size.width - horizontalMargin * 2))
            let panelHeight = min(scaled(516, pad: 540), max(proxy.size.height - proxy.safeAreaInsets.top - 56, scaled(430, pad: 500)))
            let horizontalInset = max((proxy.size.width - panelWidth) / 2, 0)
            let contentWidth = max(236, min(scaled(300, pad: 340), panelWidth - scaled(48, pad: 56)))

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()

                if isPadLayout {
                    panel(contentWidth: contentWidth)
                        .frame(width: panelWidth, height: panelHeight, alignment: .top)
                        .background(
                            RoundedRectangle(cornerRadius: scaled(16, pad: 20), style: .continuous)
                                .fill(Color(hex: "FBF6F2"))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: scaled(16, pad: 20), style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            closeButton
                                .padding(.top, 14)
                                .padding(.trailing, 14)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    closeButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, proxy.safeAreaInsets.top + scaled(128, pad: 96))
                        .padding(.trailing, horizontalInset + scaled(32, pad: 34))

                    panel(contentWidth: contentWidth)
                        .frame(width: panelWidth, height: panelHeight, alignment: .top)
                        .background(
                            AppReviewPromptTopRoundedShape(radius: scaled(16, pad: 20))
                                .fill(Color(hex: "FBF6F2"))
                        )
                        .clipShape(AppReviewPromptTopRoundedShape(radius: scaled(16, pad: 20)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .ignoresSafeArea()
        .dynamicTypeSize(.xSmall...DynamicTypeSize.xxxLarge)
    }

    private func panel(contentWidth: CGFloat) -> some View {
        let imageWidth = min(scaled(211, pad: 238), contentWidth * 0.72)
        let imageHeight = imageWidth * (145.0 / 211.0)

        return VStack(spacing: scaled(32, pad: 34)) {
            Image("RatingPromptFiveStars")
                .resizable()
                .scaledToFill()
                .frame(width: imageWidth, height: imageHeight)
                .clipped()
                .padding(.top, scaled(31, pad: 36))

            VStack(spacing: scaled(8, pad: 10)) {
                Text(L10n.appReviewPromptTitle)
                    .font(.appSystem(size: scaled(20, pad: 23), weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "291E0A"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(L10n.appReviewPromptSubtitle)
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "828282"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
            }
            .frame(width: contentWidth)

            VStack(spacing: scaled(16, pad: 18)) {
                AppReviewPromptButton(
                    title: L10n.appReviewPromptRateAction,
                    style: .primary,
                    isPadLayout: isPadLayout,
                    width: contentWidth,
                    action: onRateApp
                )

                AppReviewPromptButton(
                    title: L10n.appReviewPromptFeedbackAction,
                    style: .secondary,
                    isPadLayout: isPadLayout,
                    width: contentWidth,
                    action: onOpenFeedbackEmail
                )

                AppReviewPromptButton(
                    title: L10n.appReviewPromptDismissAction,
                    style: .plain,
                    isPadLayout: isPadLayout,
                    width: contentWidth,
                    action: onReject
                )
            }
            .padding(.bottom, scaled(32, pad: 36))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.appSystem(size: scaled(21, pad: 24), weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "1F1A16"))
                .frame(width: scaled(40, pad: 44), height: scaled(40, pad: 44))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.appReviewPromptDismissAction)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.12) : base
    }
}

private struct AppReviewPromptButton: View {
    enum Style {
        case primary
        case secondary
        case plain
    }

    let title: String
    let style: Style
    let isPadLayout: Bool
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .medium, design: .rounded))
                .foregroundColor(foregroundColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(52, pad: 58))
                .background(background)
                .overlay(border)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(width: width, height: scaled(52, pad: 58))
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "D2A57E"), Color(hex: "D3A375")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .secondary, .plain:
            Capsule()
                .fill(Color.clear)
        }
    }

    @ViewBuilder
    private var border: some View {
        if style == .secondary {
            Capsule()
                .stroke(Color(hex: "D2A67F"), lineWidth: 1)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return Color(hex: "291E0A")
        case .plain:
            return Color(hex: "828282")
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.12) : base
    }
}

private struct AppReviewPromptTopRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let resolvedRadius = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + resolvedRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + resolvedRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - resolvedRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + resolvedRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct CustomResetDowngradeOverlay: View {
    let boardNames: [String]
    let isPadLayout: Bool
    let onClose: () -> Void
    let onRestore: () -> Void

    private var cardWidth: CGFloat { isPadLayout ? 520 : 322 }
    private var imageSize: CGSize {
        isPadLayout
            ? CGSize(width: 380, height: 236)
            : CGSize(width: 300, height: 186)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        Image("ResetPush")
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .padding(.top, isPadLayout ? 16 : 10)

                        VStack(alignment: .leading, spacing: isPadLayout ? 28 : 22) {
                            Text(primaryMessage)
                                .font(.appSystem(size: isPadLayout ? 18 : 15, weight: .medium, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(restoreMessage)
                                .font(.appSystem(size: isPadLayout ? 18 : 15, weight: .medium, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, isPadLayout ? 40 : 24)
                        .padding(.top, isPadLayout ? 22 : 18)

                        Button(action: onRestore) {
                            Text(
                                L10n.tr(
                                    "Restore custom time",
                                    zhHans: "恢复自定义时间",
                                    zhHant: "恢復自訂時間",
                                    ja: "カスタム時刻を復元"
                                )
                            )
                            .font(.appSystem(size: isPadLayout ? 20 : 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: isPadLayout ? 58 : 48)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "DBAB7B"))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, isPadLayout ? 40 : 24)
                        .padding(.top, isPadLayout ? 34 : 30)
                        .padding(.bottom, isPadLayout ? 40 : 28)
                    }

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: isPadLayout ? 24 : 21, weight: .medium))
                            .foregroundColor(Color(hex: "1F1A16"))
                            .frame(width: isPadLayout ? 48 : 42, height: isPadLayout ? 48 : 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, isPadLayout ? 20 : 16)
                    .padding(.trailing, isPadLayout ? 20 : 16)
                }
                .background(
                    RoundedRectangle(cornerRadius: isPadLayout ? 26 : 20, style: .continuous)
                        .fill(Color(hex: "FBF6F3"))
                )
                .frame(width: cardWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 28)
        }
    }

    private var primaryMessage: String {
        L10n.tr(
            "Pro has expired. \(boardNamesDisplay) now resets task status automatically at 24:00 every day.",
            zhHans: "Pro 已到期，\(boardNamesDisplay) 现在会在每天 24:00 自动重置任务状态。",
            zhHant: "Pro 已到期，\(boardNamesDisplay) 現在會在每天 24:00 自動重置任務狀態。",
            ja: "Proの期限が切れたため、\(boardNamesDisplay) は毎日24:00にタスク状態を自動リセットします。"
        )
    }

    private var restoreMessage: String {
        L10n.tr(
            "Renew Pro to continue using custom reset time.",
            zhHans: "重新开通 Pro 后，即可继续使用自定义重置时间",
            zhHant: "重新開通 Pro 後，即可繼續使用自訂重置時間",
            ja: "Proを再開すると、カスタムリセット時刻を引き続き利用できます"
        )
    }

    private var boardNamesDisplay: String {
        let normalized = boardNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return L10n.tr("this board", zhHans: "当前面板", zhHant: "目前面板", ja: "このボード")
        }

        let limited = Array(normalized.prefix(3))
        let names = limited.map { "「\($0)」" }.joined()
        if normalized.count > limited.count {
            return L10n.tr(
                "\(names) and other boards",
                zhHans: "\(names) 等面板",
                zhHant: "\(names) 等面板",
                ja: "\(names) などのボード"
            )
        }
        return L10n.tr(
            "\(names) board",
            zhHans: "\(names) 面板",
            zhHant: "\(names) 面板",
            ja: "\(names) ボード"
        )
    }
}

private struct PremiumBackgroundDowngradeOverlay: View {
    let isPadLayout: Bool
    let onContinue: () -> Void
    let onNoThanks: () -> Void

    private var cardWidth: CGFloat { isPadLayout ? 520 : 322 }
    private var imageSize: CGSize {
        isPadLayout
            ? CGSize(width: 380, height: 236)
            : CGSize(width: 300, height: 186)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image("ResetPush")
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .padding(.top, isPadLayout ? 16 : 10)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: isPadLayout ? 18 : 14) {
                    Text(L10n.premiumBackgroundExpiredTitle)
                        .font(.appSystem(size: isPadLayout ? 19 : 16, weight: .bold, design: .rounded))
                        .foregroundStyle(NeumorphicColors.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.premiumBackgroundExpiredMessage)
                        .font(.appSystem(size: isPadLayout ? 18 : 15, weight: .medium, design: .rounded))
                        .foregroundStyle(NeumorphicColors.text)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, isPadLayout ? 40 : 24)
                .padding(.top, isPadLayout ? 22 : 18)

                Button(action: onContinue) {
                    Text(L10n.premiumBackgroundExpiredContinue)
                        .font(.appSystem(size: isPadLayout ? 20 : 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: isPadLayout ? 58 : 48)
                        .background(Capsule().fill(Color(hex: "DBAB7B")))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, isPadLayout ? 40 : 24)
                .padding(.top, isPadLayout ? 30 : 26)

                Button(action: onNoThanks) {
                    Text(L10n.premiumBackgroundExpiredNoThanks)
                        .font(.appSystem(size: isPadLayout ? 15 : 13, weight: .medium, design: .rounded))
                        .foregroundStyle(NeumorphicColors.text.opacity(0.58))
                        .frame(minHeight: 30)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.bottom, isPadLayout ? 28 : 22)
                .accessibilityHint(L10n.tr("Closes this message", zhHans: "关闭此提示", zhHant: "關閉此提示", ja: "このメッセージを閉じます"))
            }
            .background(
                RoundedRectangle(cornerRadius: isPadLayout ? 26 : 20, style: .continuous)
                    .fill(Color(hex: "FBF6F3"))
            )
            .frame(width: cardWidth)
            .padding(.horizontal, 28)
        }
    }
}
