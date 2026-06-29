import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SidebarMenuRow: View {
    let icon: String
    let title: String
    let isPadLayout: Bool
    let themeColor: Color
    var trailingIcon: String = "chevron.right"
    var trailingRotation: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                .foregroundColor(themeColor)
                .frame(width: isPadLayout ? 24 : 22, height: isPadLayout ? 24 : 22)

            Text(title)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Spacer()

            Image(systemName: trailingIcon)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                .rotationEffect(.degrees(trailingRotation))
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarToggleRowView: View {
    let title: String
    @Binding var isOn: Bool
    let isPadLayout: Bool
    let themeColor: Color

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SidebarGlassToggleStyle(accentColor: themeColor))
        }
        .sidebarListRow()
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarDisclosureRow: View {
    let title: String
    let isExpanded: Bool
    let isPadLayout: Bool
    let themeColor: Color
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 14) {
                Text(title)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(themeColor)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
        .sidebarListRow()
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarSettingsLinkRow: View {
    let title: String
    let isPadLayout: Bool
    let themeColor: Color
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 14) {
                Text(title)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(themeColor)
            }
        }
        .buttonStyle(.plain)
        .sidebarListRow()
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarWidgetGuideTextRow: View {
    let isPadLayout: Bool

    var body: some View {
        Text(L10n.homeWidgetInstructions)
            .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.6))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 12, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarStreakHeroView: View {
    let streakDays: Int
    let themeColor: Color
    let isPadLayout: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(streakDays)")
                    .font(.appSystem(size: scaled(40, pad: 52), weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                themeColor.opacity(0.72),
                                themeColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 10)

                Text(L10n.dayStreak)
                    .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(themeColor.opacity(0.24))
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)

                Image(systemName: "flame.fill")
                    .font(.appSystem(size: scaled(44, pad: 54), weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                themeColor.opacity(0.42),
                                themeColor.opacity(0.76),
                                themeColor
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: themeColor.opacity(0.34), radius: 10, x: 0, y: 6)
            }
            .frame(width: isPadLayout ? 90 : 78, height: isPadLayout ? 90 : 78)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 18, leading: 22, bottom: 10, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarStreakGoalsView: View {
    let streakDays: Int
    let goals: [Int]
    let themeColor: Color
    let isPadLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.streakGoals)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(goals.enumerated()), id: \.offset) { index, goal in
                    streakGoalNode(goal: goal, previousGoal: index == 0 ? 0 : goals[index - 1])

                    if index < goals.count - 1 {
                        streakConnector(from: goal, to: goals[index + 1])
                            .frame(maxWidth: .infinity)
                            .frame(height: 10)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(NeumorphicColors.text.opacity(0.28), lineWidth: 1)
                )
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 22, bottom: 14, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func streakConnector(from startGoal: Int, to endGoal: Int) -> some View {
        let fillProgress = streakConnectorProgress(from: startGoal, to: endGoal)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(NeumorphicColors.text.opacity(0.16))
                .frame(height: 8)

            GeometryReader { geo in
                Capsule()
                    .fill(themeColor)
                    .frame(height: 8)
                    .frame(width: geo.size.width * fillProgress)
            }
        }
    }

    private func streakGoalNode(goal: Int, previousGoal: Int) -> some View {
        let isAchieved = streakDays >= goal
        let isCurrent = !isAchieved && streakDays >= previousGoal
        let inactiveTone = NeumorphicColors.text.opacity(0.36)
        let activeTone = themeColor

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isAchieved
                    ? activeTone.opacity(0.16)
                    : NeumorphicColors.background.opacity(isCurrent ? 0.96 : 0.92)
                )
                .frame(width: 44, height: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isAchieved
                                ? activeTone
                                : inactiveTone.opacity(isCurrent ? 1 : 0.8),
                            lineWidth: 1.2
                        )
                }

            Text("\(goal)")
                .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(isAchieved ? activeTone : NeumorphicColors.text.opacity(isCurrent ? 0.62 : 0.5))
        }
        .frame(width: 44, height: 48)
    }

    private func streakConnectorProgress(from startGoal: Int, to endGoal: Int) -> CGFloat {
        if streakDays >= endGoal {
            return 1
        }
        if streakDays <= startGoal {
            return 0
        }

        let progress = CGFloat(streakDays - startGoal) / CGFloat(max(endGoal - startGoal, 1))
        return min(max(progress, 0), 1)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarThemePickerTriggerRow: View {
    let isPadLayout: Bool
    let themeColor: Color
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(L10n.themeColor)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Button {
                onTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(themeColor)
                    Circle()
                        .stroke(Color.white.opacity(0.72), lineWidth: 2)
                        .padding(2)
                    Image(systemName: "paintpalette.fill")
                        .font(.appSystem(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 26, height: 26)
                .shadow(color: themeColor.opacity(0.24), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .sidebarListRow()
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarThemePickerRow: View {
    @Binding var themeRawValue: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 12), count: 5), spacing: 12) {
            ForEach(AppTheme.selectableCases) { theme in
                Button {
                    guard themeRawValue != theme.rawValue else { return }
                    themeRawValue = theme.rawValue
                    UserDefaults(suiteName: BingoBoardStore.appGroupID)?.set(theme.rawValue, forKey: AppSettings.themeKey)
                    AnalyticsService.logThemeColorSelected(theme)
                    BingoBoardStore.reloadWidgetTimelines()
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .stroke(themeRawValue == theme.rawValue ? NeumorphicColors.text : .clear, lineWidth: 2)
                        }
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 4, leading: 76, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#if DEBUG
struct SidebarPricingDebugInfoRow: View {
    let loadedProductIDs: [String]
    let missingProductIDs: [String]
    let storefrontCountryCode: String
    let storefrontID: String
    let isPadLayout: Bool

    var body: some View {
        let loaded = loadedProductIDs.isEmpty ? "none" : loadedProductIDs.joined(separator: ", ")
        let missing = missingProductIDs.isEmpty ? "none" : missingProductIDs.joined(separator: ", ")

        VStack(alignment: .leading, spacing: 4) {
            Text("Debug")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.6))
            Text("Locale Region: \(AppLanguage.currentRegionCode)")
                .font(debugFont)
                .foregroundColor(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Storefront: \(storefrontCountryCode) | \(storefrontID)")
                .font(debugFont)
                .foregroundColor(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Language: \(languageCode)")
                .font(debugFont)
                .foregroundColor(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Loaded Products: \(loaded)")
                .font(debugFont)
                .foregroundColor(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text("Missing Products: \(missing)")
                .font(debugFont)
                .foregroundColor(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 10, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var debugFont: Font {
        .appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded)
    }

    private var debugTextColor: Color {
        NeumorphicColors.text.opacity(0.66)
    }

    private var languageCode: String {
        switch AppLanguage.current {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .japanese:
            return "ja"
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}
#endif

struct SidebarProEntryRow: View {
    let isPremiumMember: Bool
    let themeColor: Color
    let onTap: () -> Void

    var body: some View {
        let cardWidth: CGFloat = 254
        let cardHeight: CGFloat = 75
        let cornerRadius: CGFloat = 16
        let isEnglish = AppLanguage.current == .english
        let titleText = isPremiumMember ? L10n.proEntryMemberTitle : L10n.proEntryTitle
        let subtitleText = isPremiumMember ? L10n.proEntryMemberSubtitle : L10n.proEntrySubtitle
        let proTitleWidth: CGFloat = {
            if isPremiumMember {
                return isEnglish ? 172 : 132
            }
            return isEnglish ? 70 : 88
        }()
        let subtitleWidth: CGFloat = {
            if isPremiumMember {
                return isEnglish ? 214 : 188
            }
            return 168
        }()
        let proTitleCenterX: CGFloat = 27 + (proTitleWidth / 2)
        let proStarCenterX: CGFloat = {
            if isPremiumMember {
                return proTitleCenterX + (isEnglish ? 71 : 52)
            }
            return isEnglish ? 101.5 : 116.5
        }()
        let titleFrameWidth: CGFloat = isPremiumMember ? 220 : proTitleWidth
        let subtitleFrameWidth: CGFloat = isPremiumMember ? 224 : subtitleWidth
        let titlePositionX: CGFloat = isPremiumMember ? cardWidth / 2 : proTitleCenterX
        let subtitlePositionX: CGFloat = isPremiumMember ? cardWidth / 2 : 111
        let textAlignment: SwiftUI.Alignment = isPremiumMember ? .center : .leading
        let subtitleColor: Color = isPremiumMember ? .white : .white.opacity(0.82)
        let backgroundGradient = LinearGradient(
            colors: [themeColor.opacity(0.92), themeColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return Button {
            onTap()
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundGradient)

                Image("ProEntryCrown")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .frame(width: 140.42, height: 140.42)
                    .rotationEffect(.degrees(-24.92))
                    .blendMode(.screen)
                    .opacity(0.6)
                    .position(x: 103.258, y: 37.5)

                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .position(x: proStarCenterX, y: 21.5)

                Text(titleText)
                    .font(OnboardingFonts.supporting(size: 20, weight: 600))
                    .foregroundColor(.white)
                    .frame(width: titleFrameWidth, height: 25, alignment: textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .position(x: titlePositionX, y: 28.5)

                Text(subtitleText)
                    .font(OnboardingFonts.supporting(size: 14, weight: 500))
                    .foregroundColor(subtitleColor)
                    .frame(width: subtitleFrameWidth, height: 18, alignment: textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .position(x: subtitlePositionX, y: 51)

                if !isPremiumMember {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))

                        Path { path in
                            path.move(to: CGPoint(x: 7.39049, y: 5.25716))
                            path.addLine(to: CGPoint(x: 10.1334, y: 8.00002))
                            path.addLine(to: CGPoint(x: 7.39049, y: 10.7429))
                        }
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 1.06667, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .frame(width: 16, height: 16)
                    .position(x: 227.5, y: 38)
                }
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 10, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

struct SidebarAccountSection: View {
    let profile: AccountProfile
    let errorMessage: String?
    let themeColor: Color
    let isPadLayout: Bool
    let onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Account", zhHans: "账户", zhHant: "帳戶", ja: "アカウント"))
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Text(displayName)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            if let email = profile.email, !email.isEmpty {
                Text(email)
                    .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
            }

            Text(profile.providerIDs.map(providerDisplayName).joined(separator: " · "))
                .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.52))

            Button {
                onSignOut()
            } label: {
                Text(L10n.tr("Sign Out", zhHans: "退出登录", zhHant: "登出", ja: "サインアウト"))
                    .font(.appSystem(size: scaled(13.5, pad: 15.5), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(themeColor.opacity(0.92))
                    )
            }
            .buttonStyle(.plain)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.appSystem(size: scaled(11.5, pad: 13), weight: .medium, design: .rounded))
                    .foregroundColor(Color.red.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(themeColor.opacity(0.24), lineWidth: 1)
                )
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 14, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var displayName: String {
        profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? profile.displayName!
            : (profile.email ?? profile.uid)
    }

    private func providerDisplayName(_ providerID: String) -> String {
        switch providerID {
        case "apple.com":
            return "Apple"
        case "google.com":
            return "Google"
        case "password":
            return "Email"
        default:
            return providerID
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct HomeSidebarView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var accountSession: AccountSession

    let width: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let streakDays: Int
    let streakGoals: [Int]
    let themeColor: Color
    let isPadLayout: Bool
    let appShortVersion: String
    @Binding var isPresented: Bool
    @Binding var isSettingsExpanded: Bool
    @Binding var isWidgetGuideExpanded: Bool
    @Binding var isThemePickerExpanded: Bool
    @Binding var isHapticsEnabled: Bool
    @Binding var isSoundEffectsEnabled: Bool
    @Binding var themeRawValue: String
    let onOpenDiary: () -> Void
    let onOpenBlackBoxMode: () -> Void
    let onOpenContact: () -> Void
    let onEncourageUs: () -> Void
    let onPresentPremiumPaywall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section {
                    SidebarStreakHeroView(
                        streakDays: streakDays,
                        themeColor: themeColor,
                        isPadLayout: isPadLayout
                    )
                    SidebarStreakGoalsView(
                        streakDays: streakDays,
                        goals: streakGoals,
                        themeColor: themeColor,
                        isPadLayout: isPadLayout
                    )

                    sidebarMenuButton(icon: "calendar", title: L10n.bingoDiary) {
                        closeAndRun(after: 0.16, action: onOpenDiary)
                    }

                    sidebarMenuButton(icon: "gamecontroller.fill", title: L10n.tr("2048", zhHans: "2048", zhHant: "2048")) {
                        closeAndRun(after: 0.1, action: onOpenBlackBoxMode)
                    }

                    sidebarMenuButton(icon: "envelope", title: L10n.contactUs) {
                        closeAndRun(after: 0.12, action: onOpenContact)
                    }

                    sidebarMenuButton(icon: "star.fill", title: L10n.encourageUs) {
                        closeAndRun(after: 0.12, action: onEncourageUs)
                    }

                    settingsDisclosureButton

                    if isSettingsExpanded {
                        settingsRows
                    }

                    SidebarProEntryRow(isPremiumMember: subscriptionManager.hasPremiumAccess, themeColor: themeColor) {
                        closeAndRun(after: 0.1, action: onPresentPremiumPaywall)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 72)
            .padding(.top, max(topInset, 22))
            .padding(.bottom, max(bottomInset, 12))
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            sidebarShape
                .fill(Color(hex: "F4F4F4"))
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.75), radius: 14, x: 10, y: 0)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.8), radius: 8, x: -2, y: 0)
        }
        .overlay {
            sidebarShape
                .stroke(Color(hex: "F4F4F4").opacity(0.95), lineWidth: 1.5)
        }
        .clipShape(sidebarShape)
        .overlay(alignment: .bottomLeading) {
            Text("v\(appShortVersion)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.35))
                .padding(.leading, 22)
                .padding(.bottom, max(bottomInset, 12) + 8)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onEnded { value in
                    guard isPresented else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) else { return }
                    let dismissThreshold: CGFloat = isPadLayout ? 72 : 54
                    guard horizontal <= -dismissThreshold else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isPresented = false
                    }
                }
        )
        .ignoresSafeArea(edges: .vertical)
    }

    private var sidebarShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 28,
            topTrailingRadius: 28,
            style: .continuous
        )
    }

    private var settingsDisclosureButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isSettingsExpanded.toggle()
            }
        } label: {
            SidebarMenuRow(
                icon: "gearshape",
                title: L10n.setting,
                isPadLayout: isPadLayout,
                themeColor: themeColor,
                trailingIcon: "chevron.down",
                trailingRotation: isSettingsExpanded ? 0 : -90
            )
        }
        .buttonStyle(.plain)
        .sidebarListRow()
    }

    @ViewBuilder
    private var settingsRows: some View {
        SidebarToggleRowView(title: L10n.haptics, isOn: $isHapticsEnabled, isPadLayout: isPadLayout, themeColor: themeColor)
            .padding(.top, 6)

        SidebarToggleRowView(title: L10n.soundEffects, isOn: $isSoundEffectsEnabled, isPadLayout: isPadLayout, themeColor: themeColor)

        SidebarSettingsLinkRow(title: L10n.language, isPadLayout: isPadLayout, themeColor: themeColor) {
            closeAndRun(after: 0.12, action: openAppSettings)
        }

        SidebarDisclosureRow(title: L10n.homeWidget, isExpanded: isWidgetGuideExpanded, isPadLayout: isPadLayout, themeColor: themeColor) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isWidgetGuideExpanded.toggle()
            }
        }

        if isWidgetGuideExpanded {
            SidebarWidgetGuideTextRow(isPadLayout: isPadLayout)
        }

        SidebarThemePickerTriggerRow(isPadLayout: isPadLayout, themeColor: themeColor) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isThemePickerExpanded.toggle()
            }
        }

        if isThemePickerExpanded {
            SidebarThemePickerRow(themeRawValue: $themeRawValue)
        }

        #if DEBUG
        SidebarPricingDebugInfoRow(
            loadedProductIDs: subscriptionManager.loadedProductIDs,
            missingProductIDs: subscriptionManager.missingProductIDs,
            storefrontCountryCode: subscriptionManager.storefrontCountryCode,
            storefrontID: subscriptionManager.storefrontID,
            isPadLayout: isPadLayout
        )
        #endif

        if AppFeatureFlags.isAccountEnabled, let profile = accountSession.profile {
            SidebarAccountSection(
                profile: profile,
                errorMessage: accountSession.errorMessage,
                themeColor: themeColor,
                isPadLayout: isPadLayout
            ) {
                accountSession.signOut()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isPresented = false
                }
            }
        }
    }

    private func sidebarMenuButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            SidebarMenuRow(icon: icon, title: title, isPadLayout: isPadLayout, themeColor: themeColor)
        }
        .buttonStyle(.plain)
        .sidebarListRow()
    }

    private func closeAndRun(after delay: TimeInterval, action: @escaping () -> Void) {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private extension View {
    func sidebarListRow() -> some View {
        listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
