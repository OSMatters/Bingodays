import SwiftUI
import Lottie
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
                .foregroundStyle(themeColor)
                .frame(width: isPadLayout ? 24 : 22, height: isPadLayout ? 24 : 22)

            Text(title)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                .foregroundStyle(NeumorphicColors.text)

            Spacer()

            Image(systemName: trailingIcon)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                .foregroundStyle(NeumorphicColors.text.opacity(0.42))
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
                .foregroundStyle(NeumorphicColors.text.opacity(0.78))

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
                    .foregroundStyle(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundStyle(themeColor)
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
                    .foregroundStyle(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundStyle(themeColor)
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
            .foregroundStyle(NeumorphicColors.text.opacity(0.6))
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
                    .foregroundStyle(NeumorphicColors.text)
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
                .foregroundStyle(NeumorphicColors.text)

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
                .foregroundStyle(isAchieved ? activeTone : NeumorphicColors.text.opacity(isCurrent ? 0.62 : 0.5))
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
                .foregroundStyle(NeumorphicColors.text.opacity(0.78))

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
                        .foregroundStyle(.white)
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

struct HomeThemePickerSheet: View {
    @Binding var themeRawValue: String
    @Binding var backgroundRawValue: String
    let isPadLayout: Bool
    let stickerItems: [BlindBoxStickerShelfItem]
    let blindBoxStickerHomeCount: (BlindBoxStickerID) -> Int
    let onAddStickerToHome: (BlindBoxStickerShelfItem) -> Bool
    let onApply: () -> Void

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .concise
    }

    private var selectedBackground: HomeBackgroundOption {
        HomeBackgroundOption(rawValue: backgroundRawValue) ?? .none
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onApply) {
                    Text(L10n.apply)
                        .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule(style: .continuous).fill(selectedTheme.color))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, scaled(20, pad: 28))
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: scaled(22, pad: 24)) {
                pickerSection(title: L10n.themeColor) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(minimum: 32), spacing: 4),
                            count: AppTheme.selectableCases.count
                        ),
                        spacing: 0
                    ) {
                        ForEach(AppTheme.selectableCases) { theme in
                            Button {
                                apply(theme)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(theme.color)
                                        .frame(width: scaled(26, pad: 31), height: scaled(26, pad: 31))

                                    Circle()
                                        .stroke(
                                            themeRawValue == theme.rawValue
                                                ? NeumorphicColors.text
                                                : Color.white.opacity(0.72),
                                            lineWidth: themeRawValue == theme.rawValue ? 2.4 : 1.4
                                        )
                                        .frame(width: scaled(35, pad: 40), height: scaled(35, pad: 40))
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(theme.rawValue)
                            .accessibilityAddTraits(themeRawValue == theme.rawValue ? .isSelected : [])
                        }
                    }
                }

                pickerSection(title: L10n.backgroundPattern) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(HomeBackgroundOption.allCases) { option in
                                Button {
                                    apply(option)
                                } label: {
                                    backgroundThumbnail(for: option)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    option == .none
                                        ? L10n.noBackground
                                        : [option.badgeTitle, option.rawValue]
                                            .compactMap { $0 }
                                            .joined(separator: " ")
                                )
                                .accessibilityAddTraits(selectedBackground == option ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                pickerSection(title: L10n.mySticker) {
                    if stickerItems.isEmpty {
                        Text(L10n.noBlindBoxStickers)
                            .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                            .foregroundStyle(NeumorphicColors.text.opacity(0.56))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .bottom, spacing: 12) {
                                ForEach(stickerItems) { item in
                                    let placedCount = blindBoxStickerHomeCount(item.sticker.id)
                                    let isFullyPlaced = placedCount >= item.ownedCount
                                    Button {
                                        guard !isFullyPlaced else { return }
                                        _ = onAddStickerToHome(item)
                                    } label: {
                                        stickerThumbnail(item, placedCount: placedCount)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isFullyPlaced)
                                    .accessibilityLabel(item.sticker.id.rawValue)
                                    .accessibilityValue(String(placedCount) + "/" + String(item.ownedCount))
                                    .accessibilityHint(isFullyPlaced ? L10n.addedToHome : L10n.addToHome)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.bottom, 4)
                        }
                    }
                }
                }
                .padding(.horizontal, scaled(20, pad: 28))
                .padding(.top, scaled(37, pad: 40))
                .padding(.bottom, scaled(12, pad: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(NeumorphicColors.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func pickerSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                .foregroundStyle(NeumorphicColors.text)
            content()
        }
    }

    private func backgroundThumbnail(for option: HomeBackgroundOption) -> some View {
        let isSelected = selectedBackground == option
        let thumbnailShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let thumbnailWidth: CGFloat = 74
        let thumbnailHeight: CGFloat = 160
        let optionWidth: CGFloat = 82
        let optionHeight: CGFloat = 168

        return Group {
            ZStack {
                Group {
                    if let imageName = option.imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                    } else {
                        HomeBackgroundStyle.defaultColor
                    }
                }
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .background(HomeBackgroundStyle.defaultColor)
                .clipped()
                .clipShape(thumbnailShape)
                .overlay {
                    if !isSelected {
                        thumbnailShape
                        .strokeBorder(NeumorphicColors.text.opacity(0.12), lineWidth: 1)
                    }
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(NeumorphicColors.text, lineWidth: 1.5)
                        .frame(width: optionWidth, height: optionHeight)
                }
            }
            .frame(width: optionWidth, height: optionHeight)
            .overlay(alignment: .topTrailing) {
                if let badgeTitle = option.badgeTitle {
                    Text(badgeTitle)
                        .font(
                            option.isHalloweenLimited
                                ? .system(size: 15)
                                : .appSystem(size: 9, weight: .bold, design: .rounded)
                        )
                        .foregroundStyle(.white)
                        .padding(.horizontal, option.isHalloweenLimited ? 0 : 5)
                        .padding(.vertical, option.isHalloweenLimited ? 0 : 3)
                        .background {
                            if !option.isHalloweenLimited {
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.62))
                            }
                        }
                        .padding(6)
                }
            }
        }
        .contentShape(
            RoundedRectangle(
                cornerRadius: isSelected ? 16 : 12,
                style: .continuous
            )
        )
    }

    private func stickerThumbnail(
        _ item: BlindBoxStickerShelfItem,
        placedCount: Int
    ) -> some View {
        let isFullyPlaced = placedCount >= item.ownedCount

        return ZStack(alignment: .topTrailing) {
            BlindBoxImage(item.sticker.assetName)
                .frame(width: 76, height: 88)
                .opacity(isFullyPlaced ? 0.42 : 1)

            if isFullyPlaced {
                Image(systemName: "checkmark.circle.fill")
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundStyle(NeumorphicColors.accent)
                    .background(Circle().fill(NeumorphicColors.background))
            } else if item.ownedCount > 1 {
                Text(placedCount == 0 ? "×\(item.ownedCount)" : "\(placedCount)/\(item.ownedCount)")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(NeumorphicColors.accent))
            }
        }
        .frame(width: 80, height: 92)
        .contentShape(Rectangle())
    }

    private func apply(_ theme: AppTheme) {
        guard themeRawValue != theme.rawValue else { return }
        themeRawValue = theme.rawValue
        UserDefaults(suiteName: BingoBoardStore.appGroupID)?.set(theme.rawValue, forKey: AppSettings.themeKey)
    }

    private func apply(_ option: HomeBackgroundOption) {
        guard backgroundRawValue != option.rawValue else { return }
        backgroundRawValue = option.rawValue
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct HomeBackgroundLayer: View {
    let option: HomeBackgroundOption

    var body: some View {
        GeometryReader { geo in
            Group {
                if let imageName = option.imageName {
                    Image(imageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    HomeBackgroundStyle.defaultColor
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private enum HomeBackgroundStyle {
    static let defaultColor = Color(hex: "FAF9F3")
}

private enum MeScreenPalette {
    static let background = Color(hex: "F9F7F0")
    static let text = Color(hex: "463C2E")
    static let mutedText = Color(hex: "8B7B68")
    static let accent = Color(hex: "D6A77C")
    static let darkBadge = Color(hex: "23190F")
    static let cardBackground = Color.white.opacity(0.84)
    static let border = Color(hex: "2F281F").opacity(0.82)
}

enum MeSkin: String, Equatable {
    case normal
    case halloween

    var isHalloween: Bool { self == .halloween }

    var backgroundImageName: String {
        isHalloween ? "MeHalloweenBackground" : "MeBackground"
    }

    var titleColor: Color {
        isHalloween ? Color(hex: "FFF7E8") : MeScreenPalette.text
    }

    var actionColor: Color {
        isHalloween ? Color(hex: "FFC477") : MeScreenPalette.accent
    }

    var crownArrowImageName: String {
        isHalloween ? "MeHalloweenCrownArrow" : "MeCrownArrow"
    }

    func characterImageName(isPremiumMember: Bool, hasReviewedApp: Bool) -> String {
        switch (isHalloween, isPremiumMember, hasReviewedApp) {
        case (false, false, false):
            return "MeNoproUnreviewed"
        case (false, false, true):
            return "MeNoproReviewed"
        case (false, true, false):
            return "MeProUnreviewed"
        case (false, true, true):
            return "MeProReviewed"
        case (true, false, false):
            return "MeHalloweenNoproUnreviewed"
        case (true, false, true):
            return "MeHalloweenNoproReviewed"
        case (true, true, false):
            return "MeHalloweenProUnreviewed"
        case (true, true, true):
            return "MeHalloweenProReviewed"
        }
    }
}

enum MeGreeting: Int, CaseIterable {
    case hardWork
    case welcomeBack
    case deservesCredit
    case takeItSlow
    case beKind
    case doingEnough
    case noRush
    case takeCare
    case ownPace
    case worthCelebrating
    case thanksForBeingHere
    case betterThanThink
    case believeALittle
    case noNeedPerfect
    case everyStep
    case thankYourself
    case kindDay
    case rememberSmile
    case alwaysWorthy
    case happyToSeeYou

    static func randomIndex(excluding excludedIndex: Int? = nil) -> Int {
        let allIndexes = allCases.map(\.rawValue)
        let candidates = allIndexes.filter { $0 != excludedIndex }
        return candidates.randomElement() ?? allIndexes.randomElement() ?? 0
    }

    static func localizedText(at index: Int) -> String {
        let greeting = MeGreeting(rawValue: index) ?? .welcomeBack
        return greeting.localizedText
    }

    private var localizedText: String {
        switch self {
        case .hardWork:
            return L10n.tr("You’re doing great today.", zhHans: "今天也辛苦啦。", zhHant: "今天也辛苦啦。", ja: "今日もおつかれさま。")
        case .welcomeBack:
            return L10n.tr("Welcome back.", zhHans: "欢迎回来。", zhHant: "歡迎回來。", ja: "おかえりなさい。")
        case .deservesCredit:
            return L10n.tr("You deserve some credit today.", zhHans: "今天也值得被夸夸。", zhHant: "今天也值得被誇誇。", ja: "今日のあなたもちゃんとすごい。")
        case .takeItSlow:
            return L10n.tr("It’s okay to take it slow.", zhHans: "慢一点，也没关系。", zhHant: "慢一點，也沒關係。", ja: "ゆっくりでも大丈夫。")
        case .beKind:
            return L10n.tr("Be kind to yourself today.", zhHans: "今天也要对自己温柔一点。", zhHant: "今天也要對自己溫柔一點。", ja: "今日も自分にやさしく。")
        case .doingEnough:
            return L10n.tr("You’re doing enough.", zhHans: "你已经做得很好了。", zhHant: "你已經做得很好了。", ja: "もう十分頑張ってるよ。")
        case .noRush:
            return L10n.tr("No rush. Things will come together.", zhHans: "不用着急，一切都会慢慢变好。", zhHant: "不用著急，一切都會慢慢變好。", ja: "焦らなくて大丈夫。")
        case .takeCare:
            return L10n.tr("Take care of yourself today.", zhHans: "今天也请照顾好自己。", zhHant: "今天也請照顧好自己。", ja: "今日も自分を大切にね。")
        case .ownPace:
            return L10n.tr("Every day has its own pace.", zhHans: "每一天都有自己的节奏。", zhHant: "每一天都有自己的節奏。", ja: "毎日には毎日のペースがある。")
        case .worthCelebrating:
            return L10n.tr("Today is worth celebrating.", zhHans: "今天也是值得庆祝的一天。", zhHant: "今天也是值得慶祝的一天。", ja: "今日も大切な一日。")
        case .thanksForBeingHere:
            return L10n.tr("Thanks for being here today.", zhHans: "谢谢你今天也来了。", zhHant: "謝謝你今天也來了。", ja: "今日も来てくれてありがとう。")
        case .betterThanThink:
            return L10n.tr("You’re doing better than you think.", zhHans: "你比想象中更棒。", zhHant: "你比想像中更棒。", ja: "思っているより、ちゃんとできてるよ。")
        case .believeALittle:
            return L10n.tr("Believe in yourself a little today.", zhHans: "今天，也请相信自己一点点。", zhHant: "今天，也請相信自己一點點。", ja: "今日も少しだけ自分を信じて。")
        case .noNeedPerfect:
            return L10n.tr("You don’t have to be perfect.", zhHans: "不用完美，你已经很好了。", zhHant: "不用完美，你已經很好了。", ja: "完璧じゃなくていい。")
        case .everyStep:
            return L10n.tr("Every step is worth celebrating.", zhHans: "每一步都值得骄傲。", zhHant: "每一步都值得驕傲。", ja: "一歩一歩がちゃんと前進。")
        case .thankYourself:
            return L10n.tr("Thank yourself for showing up today.", zhHans: "今天也谢谢努力的自己。", zhHant: "今天也謝謝努力的自己。", ja: "今日も頑張った自分にありがとう。")
        case .kindDay:
            return L10n.tr("Hope today is kind to you.", zhHans: "愿今天对你温柔一点。", zhHant: "願今天對你溫柔一點。", ja: "今日がやさしい一日になりますように。")
        case .rememberSmile:
            return L10n.tr("Don’t forget to smile today.", zhHans: "今天，也要记得微笑。", zhHant: "今天，也要記得微笑。", ja: "今日も笑顔を忘れずに。")
        case .alwaysWorthy:
            return L10n.tr("You’re worthy, no matter how today goes.", zhHans: "无论今天怎样，你都值得被喜欢。", zhHant: "無論今天怎樣，你都值得被喜歡。", ja: "どんな一日でも、あなたは大切。")
        case .happyToSeeYou:
            return L10n.tr("I’m happy to see you again.", zhHans: "很高兴今天又见到你。", zhHant: "很高興今天又見到你。", ja: "今日も会えてうれしい。")
        }
    }
}

struct BingodaysMeScreen: View {
    let isPremiumMember: Bool
    let premiumPlanKind: PremiumPlanKind?
    let hasReviewedApp: Bool
    let streakDays: Int
    let greetingText: String
    let skin: MeSkin
    let isPadLayout: Bool
    let bottomInset: CGFloat
    let onOpenContact: () -> Void
    let onOpenSettings: () -> Void
    let onLeaveReview: () -> Void
    let onOpenDiary: () -> Void
    let onOpenPremium: () -> Void
    let onToggleSkin: () -> Void

    @State private var halloweenCatDotLottieFile: DotLottieFile?
    @State private var halloweenCatAnimationToken = 0
    @State private var isHalloweenCatAnimating = false

    var body: some View {
        GeometryReader { geo in
            let contentWidth = min(geo.size.width, isPadLayout ? 430 : 393)
            let layoutScale = min(
                max(
                    min(contentWidth / 393, (geo.size.height - bottomInset) / 849),
                    isPadLayout ? 0.9 : 0.82
                ),
                isPadLayout ? 1.08 : 1.0
            )
            let contentX = geo.size.width / 2
            let yLift = isPadLayout ? max(0, (geo.size.height - 849 * layoutScale) * 0.18) : 0
            // Keep the Me screen adaptive when the same iPhone changes between Duo displays.
            let isPadDevice = isPadLayout
            let isPadPortraitLayout = isPadDevice && geo.size.height > geo.size.width
            let isPadLandscapeLayout = isPadDevice && geo.size.width > geo.size.height
            let reviewBubbleHorizontalOffset: CGFloat = isPadPortraitLayout ? -60 : 0
            let meContentVerticalOffset: CGFloat = 16
            let characterAndDiaryVerticalOffset: CGFloat = meContentVerticalOffset
                + (isPadDevice ? 20 : 0)
                + (isPadPortraitLayout ? 40 : 0)
            let backgroundVerticalOffset: CGFloat = isPadLandscapeLayout ? -60 : 0
            let skinToggleVerticalOffset: CGFloat = 42

            ZStack(alignment: .top) {
                Image(skin.backgroundImageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .offset(y: backgroundVerticalOffset)
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                    )
                    .clipped()
                    .ignoresSafeArea()

                MeSkinToggleButton(
                    skin: skin,
                    isPadLayout: isPadLayout,
                    onTap: onToggleSkin
                )
                .scaleEffect(layoutScale, anchor: .center)
                .position(
                    x: contentX - contentWidth / 2 + 20 + scaled(39, pad: 44) * layoutScale,
                    y: y(skinToggleVerticalOffset, scale: layoutScale, lift: yLift)
                )
                .zIndex(12)

                VStack(spacing: scaled(20, pad: 24)) {
                    titleBlock
                    topActions
                }
                .frame(width: contentWidth)
                .position(x: contentX, y: y(118, scale: layoutScale, lift: yLift))

                if isPremiumMember {
                    if isPadDevice {
                        membershipBadgeButton
                            .padding(.trailing, 28)
                            .frame(width: geo.size.width, alignment: .trailing)
                            .position(x: geo.size.width / 2, y: 39)
                            .zIndex(10)
                    } else {
                        membershipBadgeButton
                            .position(
                                x: contentX + contentWidth / 2 - scaled(66, pad: 76),
                                y: y(39, scale: layoutScale, lift: yLift)
                            )
                            .zIndex(10)
                    }
                }

                MeStreakCard(
                    streakDays: streakDays,
                    isPadLayout: isPadLayout
                )
                .scaleEffect(layoutScale, anchor: .center)
                .position(
                    x: contentX - contentWidth / 2 + 96 * layoutScale,
                    y: y(266, scale: layoutScale, lift: yLift) + meContentVerticalOffset
                )

                if !isPremiumMember {
                    MeCrownUpgradeButton(
                        isPadLayout: isPadLayout,
                        textColor: skin.titleColor,
                        arrowImageName: skin.crownArrowImageName,
                        onTap: onOpenPremium
                    )
                    .scaleEffect(layoutScale, anchor: .center)
                    .position(
                        x: contentX + contentWidth / 2 - 126 * layoutScale,
                        y: y(270, scale: layoutScale, lift: yLift) + meContentVerticalOffset
                    )
                }

                Image(mainImageName)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: scaled(392, pad: 424) * layoutScale)
                    .position(
                        x: contentX,
                        y: y(476, scale: layoutScale, lift: yLift) + characterAndDiaryVerticalOffset
                    )
                    .accessibilityHidden(true)

                if skin.isHalloween {
                    Button {
                        AppHaptics.control()
                        halloweenCatAnimationToken &+= 1
                        isHalloweenCatAnimating = true
                    } label: {
                        Group {
                            if let halloweenCatDotLottieFile {
                                MeHalloweenCatLottieView(
                                    dotLottieFile: halloweenCatDotLottieFile,
                                    playToken: halloweenCatAnimationToken,
                                    isPlaying: isHalloweenCatAnimating,
                                    onFinished: { isHalloweenCatAnimating = false }
                                )
                            } else {
                                Color.clear
                            }
                        }
                        .frame(
                            width: scaled(112, pad: 128) * layoutScale,
                            height: scaled(178, pad: 202) * layoutScale
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: contentX - contentWidth / 2 + 70 * layoutScale,
                        y: y(674, scale: layoutScale, lift: yLift) + characterAndDiaryVerticalOffset
                    )
                    .accessibilityLabel(
                        L10n.tr("Play cat animation", zhHans: "播放猫咪动画", zhHant: "播放貓咪動畫", ja: "猫のアニメーションを再生")
                    )
                    .task {
                        guard halloweenCatDotLottieFile == nil else { return }
                        halloweenCatDotLottieFile = try? await DotLottieFile.asset(named: "MeHalloweenCatLottie")
                    }
                    .zIndex(0.5)
                }

                MeDiaryDeskButton(
                    isPadLayout: isPadLayout,
                    onTap: onOpenDiary
                )
                .scaleEffect(layoutScale, anchor: .center)
                .position(
                    x: contentX + contentWidth / 2 - 173 * layoutScale,
                    y: y(557, scale: layoutScale, lift: yLift) + characterAndDiaryVerticalOffset
                )
                .zIndex(2)

                if !hasReviewedApp {
                    MeReviewButton(
                        isPadLayout: isPadLayout,
                        onTap: onLeaveReview
                    )
                    .scaleEffect(layoutScale, anchor: .center)
                    .position(
                        x: contentX - contentWidth / 2 + 125 * layoutScale + reviewBubbleHorizontalOffset,
                        y: y(383, scale: layoutScale, lift: yLift) + characterAndDiaryVerticalOffset
                    )
                }

                MeDiaryButton(
                    isPadLayout: isPadLayout,
                    onTap: onOpenDiary
                )
                .scaleEffect(layoutScale, anchor: .center)
                .position(
                    x: contentX + contentWidth / 2 - (147 + 52) * layoutScale,
                    y: y(623, scale: layoutScale, lift: yLift) + characterAndDiaryVerticalOffset
                )
                .zIndex(1)
            }
        }
        .background(
            (skin.isHalloween ? Color(hex: "131936") : MeScreenPalette.background)
                .ignoresSafeArea()
        )
    }

    private var membershipBadgeButton: some View {
        Button(action: onOpenPremium) {
            MeMembershipBadge(
                planKind: premiumPlanKind,
                isPadLayout: isPadLayout
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
        .accessibilityLabel(L10n.tr("Membership details", zhHans: "会员详情", zhHant: "會員詳情", ja: "メンバーシップ詳細"))
    }

    private var titleBlock: some View {
        VStack(spacing: 0) {
            Text(greetingText)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .font(.custom("Outfit", size: scaled(23, pad: 27)).weight(.semibold))
        .foregroundStyle(skin.titleColor)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .offset(y: scaled(-4, pad: -5))
    }

    private var topActions: some View {
        HStack(spacing: scaled(42, pad: 52)) {
            Button(action: onOpenContact) {
                Text("\(L10n.contactUs) 📫")
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.actionColor)
            }
            .buttonStyle(.plain)

            Button(action: onOpenSettings) {
                Text("\(L10n.tr("Preferences", zhHans: "个性设置", zhHant: "個性設定", ja: "個人設定")) ⚙️")
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.actionColor)
            }
            .buttonStyle(.plain)
        }
        .offset(y: scaled(-4, pad: -5))
    }

    private var mainImageName: String {
        skin.characterImageName(
            isPremiumMember: isPremiumMember,
            hasReviewedApp: hasReviewedApp
        )
    }

    private func y(_ value: CGFloat, scale: CGFloat, lift: CGFloat) -> CGFloat {
        value * scale + lift
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeHalloweenCatLottieView: UIViewRepresentable {
    let dotLottieFile: DotLottieFile
    let playToken: Int
    let isPlaying: Bool
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(dotLottie: dotLottieFile)
        view.loopMode = .playOnce
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        context.coordinator.lastPlayToken = playToken
        context.coordinator.isPlaying = isPlaying
        view.currentProgress = Self.staticProgress
        if isPlaying {
            play(view)
        }
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        if isPlaying {
            guard context.coordinator.lastPlayToken != playToken else { return }
            context.coordinator.lastPlayToken = playToken
            context.coordinator.isPlaying = true
            play(view)
        } else if context.coordinator.isPlaying || context.coordinator.lastPlayToken != playToken {
            view.stop()
            view.currentProgress = Self.staticProgress
            context.coordinator.lastPlayToken = playToken
            context.coordinator.isPlaying = false
        }
    }

    private static let staticProgress: AnimationProgressTime = 0

    private func play(_ view: LottieAnimationView) {
        view.stop()
        view.currentProgress = 0
        view.play { finished in
            guard finished else { return }
            DispatchQueue.main.async {
                onFinished()
            }
        }
    }

    final class Coordinator {
        var lastPlayToken: Int?
        var isPlaying = false
    }
}

private struct MeSkinToggleButton: View {
    let skin: MeSkin
    let isPadLayout: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            AppHaptics.control()
            onTap()
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(skin.isHalloween ? Color(hex: "20294D") : Color(hex: "D9AA7C"))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(skin.isHalloween ? 0.28 : 0.42), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.16), radius: 2, y: 1)

                if skin.isHalloween {
                    Image("MeHalloweenCasper")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: casperWidth, height: casperHeight)
                        .offset(x: -switchWidth / 2 + casperLeading, y: -3)
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, y: 1)
                    .offset(x: knobOffset)
                    .animation(.spring(response: 0.24, dampingFraction: 0.82), value: skin)
            }
            .frame(width: switchWidth, height: switchHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(
            skin.isHalloween
                ? L10n.tr("Switch to normal theme", zhHans: "切换到普通皮肤", zhHant: "切換到普通皮膚", ja: "通常スキンに切り替える")
                : L10n.tr("Switch to Halloween theme", zhHans: "切换到万圣节皮肤", zhHant: "切換到萬聖節皮膚", ja: "ハロウィンスキンに切り替える")
        )
    }

    private var switchWidth: CGFloat { scaled(78, pad: 88) }

    private var switchHeight: CGFloat { scaled(40, pad: 46) }

    private var knobSize: CGFloat { scaled(27, pad: 31) }

    private var casperWidth: CGFloat { scaled(56, pad: 63) }

    private var casperHeight: CGFloat { scaled(38, pad: 43) }

    private var casperLeading: CGFloat { scaled(27, pad: 31) }

    private var knobOffset: CGFloat {
        let inset = scaled(4, pad: 5)
        return skin.isHalloween
            ? switchWidth / 2 - knobSize / 2 - inset
            : -switchWidth / 2 + knobSize / 2 + inset
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeMembershipBadge: View {
    let planKind: PremiumPlanKind?
    let isPadLayout: Bool

    var body: some View {
        HStack(spacing: scaled(4, pad: 5)) {
            Image("MeProIcon")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: scaled(12, pad: 14), height: scaled(12, pad: 14))

            Text(memberTitle)
                .font(.appSystem(size: scaled(10.5, pad: 12), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.leading, scaled(6, pad: 7))
        .padding(.trailing, scaled(8, pad: 9))
        .frame(minWidth: scaled(72, pad: 84))
        .frame(height: scaled(22, pad: 26))
        .background(
            Capsule(style: .continuous)
                .fill(Color(hex: "2B2116"))
                .shadow(color: Color.black.opacity(0.18), radius: scaled(4, pad: 6), x: 0, y: scaled(2, pad: 3))
        )
        .accessibilityElement(children: .combine)
    }

    private var memberTitle: String {
        switch planKind {
        case .monthly:
            return L10n.tr("Monthly", zhHans: "月度会员", zhHant: "月度會員", ja: "月間プラン")
        case .yearly:
            return L10n.tr("Annual", zhHans: "年度会员", zhHant: "年度會員", ja: "年間プラン")
        case .lifetime:
            return L10n.tr("Lifetime", zhHans: "终身会员", zhHant: "終身會員", ja: "永久プラン")
        case nil:
            return L10n.tr("Premium", zhHans: "会员", zhHant: "會員", ja: "Premiumメンバー")
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeStreakCard: View {
    let streakDays: Int
    let isPadLayout: Bool
    @StateObject private var streakStore = AppOpenStreakStore.shared
    @State private var isIconProgressPresented = false

    var body: some View {
        Button {
            AppHaptics.control()
            isIconProgressPresented = true
        } label: {
            ZStack {
                Image("MeStreakBackground")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()

                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Image("MeStreakIcon")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: scaled(19, pad: 22), height: scaled(19, pad: 22))

                        Text("\(streakDays)")
                            .font(.appSystem(size: scaled(28, pad: 32), weight: .bold, design: .rounded))
                            .foregroundStyle(MeScreenPalette.accent)
                    }

                    Text(L10n.consecutiveOpenDays)
                        .font(.appSystem(size: scaled(9.5, pad: 11), weight: .bold, design: .rounded))
                        .foregroundStyle(MeScreenPalette.accent.opacity(0.8))
                }
                .offset(y: scaled(10, pad: 12))
            }
            .frame(width: scaled(96, pad: 108), height: scaled(110, pad: 124))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("View app icon unlock progress", zhHans: "查看桌面图标解锁进度", zhHant: "查看桌面圖標解鎖進度", ja: "アプリアイコンの解放進捗を見る"))
        .accessibilityValue("\(streakDays)")
        .sheet(isPresented: $isIconProgressPresented) {
            AppIconMilestoneSheet(milestones: [], streakStore: streakStore)
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeCrownUpgradeButton: View {
    let isPadLayout: Bool
    let textColor: Color
    let arrowImageName: String
    let onTap: () -> Void

    var body: some View {
        Button {
            AppHaptics.control()
            onTap()
        } label: {
            VStack(spacing: -5) {
                DecorativeAnimationTimeline { time in
                    let floatProgress = time.map { (1 - cos(.pi * $0 / 1.15)) / 2 }
                    ZStack {
                        Image("MeLightBackground")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: scaled(156, pad: 176), height: scaled(156, pad: 176))
                            .rotationEffect(.degrees(time.map { $0.truncatingRemainder(dividingBy: 18) * 20 } ?? 0))

                        Image("MeCrown")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: scaled(78, pad: 88), height: scaled(70, pad: 80))
                            .rotationEffect(.degrees(-10))
                            .offset(y: scaled(floatProgress.map { 6 - 6 * $0 } ?? 4, pad: floatProgress.map { 7 - 6 * $0 } ?? 5))
                    }
                }
                .frame(width: scaled(150, pad: 170), height: scaled(88, pad: 98))

                Text(L10n.tr("Go Crowned", zhHans: "戴上皇冠", zhHant: "戴上皇冠", ja: "王冠をかぶる"))
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Image(arrowImageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: scaled(42, pad: 48), height: scaled(42, pad: 48))
                    .offset(x: scaled(-12, pad: -11), y: scaled(8, pad: 9))
            }
            .frame(width: scaled(150, pad: 168), height: scaled(150, pad: 168))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.paywallHeroAllFeaturesTitle)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeReviewButton: View {
    let isPadLayout: Bool
    let onTap: () -> Void

    var body: some View {
        MeOutlinedPillButton(
            title: L10n.tr("Like Bingodays?", zhHans: "喜欢 Bingodays？", zhHant: "喜歡 Bingodays？", ja: "Bingodaysが好き？"),
            imageName: "MePopReview",
            width: scaled(142, pad: 163),
            height: scaled(70, pad: 80),
            isPadLayout: isPadLayout,
            onTap: onTap
        )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeDiaryButton: View {
    let isPadLayout: Bool
    let onTap: () -> Void

    var body: some View {
        MeOutlinedPillButton(
            title: L10n.tr("Check My\nBingo Dairy", zhHans: "查看我的\nBingo 日记", zhHant: "查看我的\nBingo 日記", ja: "Bingo日記を\n見る"),
            imageName: "MePopDairy",
            width: scaled(178, pad: 205),
            height: scaled(73, pad: 84),
            isPadLayout: isPadLayout,
            contentTopOffset: 4,
            onTap: onTap
        )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeDiaryDeskButton: View {
    let isPadLayout: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            AppHaptics.control()
            onTap()
        } label: {
            Image("MeDiary")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: scaled(94, pad: 108), height: scaled(70, pad: 80))
                .contentShape(Rectangle())
        }
        .buttonStyle(MeDiaryDeskButtonStyle())
        .accessibilityLabel(L10n.tr("Check My Bingo Dairy", zhHans: "查看我的 Bingo 日记", zhHant: "查看我的 Bingo 日記", ja: "Bingo日記を見る"))
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeDiaryDeskButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

private struct MeOutlinedPillButton: View {
    let title: String
    let imageName: String
    let width: CGFloat
    let height: CGFloat
    let isPadLayout: Bool
    let contentTopOffset: CGFloat
    let onTap: () -> Void

    init(
        title: String,
        imageName: String,
        width: CGFloat,
        height: CGFloat,
        isPadLayout: Bool,
        contentTopOffset: CGFloat = 0,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.imageName = imageName
        self.width = width
        self.height = height
        self.isPadLayout = isPadLayout
        self.contentTopOffset = contentTopOffset
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: width, height: height)

                HStack(spacing: scaled(6, pad: 7)) {
                    Text(title)
                        .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                        .foregroundStyle(MeScreenPalette.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .layoutPriority(1)

                    Image("MeEnter")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: scaled(20, pad: 23), height: scaled(20, pad: 23))
                        .padding(.trailing, scaled(1, pad: 2))
                }
                .padding(.leading, scaled(17, pad: 20))
                .padding(.trailing, scaled(12, pad: 14))
                .padding(.top, scaled(3 + contentTopOffset, pad: 4 + contentTopOffset))
                .frame(width: width, height: height)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct MeSettingsScreen: View {
    let hasPremiumAccess: Bool
    let onOpenPremiumIcon: () -> Void
    let isPadLayout: Bool
    let appShortVersion: String
    let iCloudState: NativeICloudSyncCoordinator.State
    let themeColor: Color
    let isICloudSyncEnabled: Bool
    @Binding var isHapticsEnabled: Bool
    @Binding var isSoundEffectsEnabled: Bool
    @Binding var isWidgetGuideExpanded: Bool
    let onBack: () -> Void
    let onOpenLanguage: () -> Void
    let onOpenICloud: () -> Void
    let onSetICloudEnabled: (Bool) -> Void
    let onOpenTerms: () -> Void
    let onOpenPrivacy: () -> Void
    let onEncourageUs: () -> Void
    var body: some View {
        GeometryReader { geo in
            let contentWidth = min(geo.size.width - 32, isPadLayout ? 430 : 361)
            let topContentPadding = max(0, max(geo.safeAreaInsets.top, 12) + 10 - 40)

            VStack(spacing: 0) {
                settingsHeader
                    .padding(.top, topContentPadding)
                    .padding(.horizontal, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: scaled(14, pad: 18)) {
                        VStack(spacing: 0) {
                            MeICloudSettingsEntry(
                                state: iCloudState,
                                isPadLayout: isPadLayout,
                                themeColor: themeColor,
                                isEnabled: isICloudSyncEnabled,
                                onSetEnabled: onSetICloudEnabled,
                                action: onOpenICloud
                            )

                            MeSettingsToggleRow(
                                title: L10n.haptics,
                                isOn: $isHapticsEnabled,
                                isPadLayout: isPadLayout
                            )

                            MeSettingsToggleRow(
                                title: L10n.soundEffects,
                                isOn: $isSoundEffectsEnabled,
                                isPadLayout: isPadLayout
                            )

                            MeSettingsActionRow(
                                title: L10n.homeWidget,
                                isPadLayout: isPadLayout
                            ) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    isWidgetGuideExpanded.toggle()
                                }
                            }

                            if isWidgetGuideExpanded {
                                Text(L10n.homeWidgetInstructions)
                                    .font(.appSystem(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                                    .foregroundStyle(MeScreenPalette.mutedText)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, scaled(18, pad: 22))
                                    .padding(.bottom, scaled(12, pad: 14))
                            }

                            MeSettingsActionRow(
                                title: L10n.language,
                                isPadLayout: isPadLayout,
                                action: onOpenLanguage
                            )

                            MeSettingsActionRow(
                                title: L10n.encourageUs,
                                isPadLayout: isPadLayout,
                                action: onEncourageUs
                            )
                        }
                        .frame(width: contentWidth)
                        .background(
                            RoundedRectangle(cornerRadius: scaled(15, pad: 18), style: .continuous)
                                .fill(Color.white.opacity(0.88))
                        )

                        AppIconSettingsSection(
                            isPadLayout: isPadLayout,
                            themeColor: themeColor,
                            hasPremiumAccess: hasPremiumAccess,
                            onOpenPremium: onOpenPremiumIcon
                        )
                        .frame(width: contentWidth)

                        settingsLegalLinks
                            .padding(.top, scaled(16, pad: 22))
                            .padding(.bottom, scaled(16, pad: 20))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, scaled(24, pad: 32))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(MeScreenPalette.background.ignoresSafeArea())
        }
    }

    private var settingsToggleInactiveColor: Color {
        Color(hex: "8F8F8F").opacity(0.62)
    }

    private var settingsHeader: some View {
        ZStack {
            Text(L10n.setting)
                .font(.appSystem(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                .foregroundStyle(MeScreenPalette.text)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: scaled(17, pad: 19), weight: .bold))
                        .foregroundStyle(MeScreenPalette.text)
                        .frame(width: scaled(40, pad: 46), height: scaled(40, pad: 46))
                        .appLiquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.cancel)

                Spacer()
            }
        }
        .frame(height: scaled(44, pad: 52))
    }

    private var settingsLegalLinks: some View {
        HStack(spacing: scaled(12, pad: 14)) {
            Button(action: onOpenTerms) {
                Text(L10n.paywallTermsOfUse)
            }
            .buttonStyle(.plain)

            Text("|")

            Button(action: onOpenPrivacy) {
                Text(L10n.paywallPrivacyPolicy)
            }
            .buttonStyle(.plain)

            Text("|")

            Text("Version \(appShortVersion)")
        }
        .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
        .foregroundStyle(MeScreenPalette.mutedText.opacity(0.72))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeICloudSettingsEntry: View {
    let state: NativeICloudSyncCoordinator.State
    let isPadLayout: Bool
    let themeColor: Color
    let isEnabled: Bool
    let onSetEnabled: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 5) {
                    Text(L10n.tr("iCloud Sync", zhHans: "iCloud 同步", zhHant: "iCloud 同步", ja: "iCloud同期"))
                        .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                        .foregroundStyle(MeScreenPalette.text)

                    if let statusText {
                        Text("(\(statusText))")
                            .font(.appSystem(size: scaled(11, pad: 12.5), weight: .medium, design: .rounded))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(get: { isEnabled }, set: { onSetEnabled($0) }))
                .labelsHidden()
                .toggleStyle(
                    SidebarGlassToggleStyle(
                        accentColor: themeColor,
                        inactiveColor: Color(hex: "8F8F8F").opacity(0.62)
                    )
                )
        }
        .frame(height: scaled(50, pad: 58))
        .padding(.horizontal, scaled(18, pad: 22))
    }

    private var statusText: String? {
        switch state {
        case .disabled:
            return nil
        case .preparing:
            return L10n.tr("Preparing", zhHans: "正在准备", zhHant: "正在準備", ja: "準備中")
        case .syncing:
            return L10n.tr("Syncing", zhHans: "正在同步", zhHant: "正在同步", ja: "同期中")
        case .waitingForCloud:
            return L10n.tr("Waiting", zhHans: "正在等待", zhHant: "正在等待", ja: "待機中")
        case .ready:
            return L10n.tr("Connected", zhHans: "已连接", zhHant: "已連接", ja: "接続済み")
        case .accountChangeRequiresDecision:
            return L10n.tr("Choose data", zhHans: "请选择数据", zhHant: "請選擇資料", ja: "データを選択")
        case .unavailable:
            return L10n.tr("Unavailable", zhHans: "暂不可用", zhHant: "暫不可用", ja: "利用不可")
        case .failed:
            return L10n.tr("Needs attention", zhHans: "需要检查", zhHant: "需要檢查", ja: "確認が必要")
        }
    }

    private var statusColor: Color {
        switch state {
        case .ready:
            return themeColor
        case .waitingForCloud:
            return themeColor
        case .accountChangeRequiresDecision:
            return themeColor
        case .failed, .unavailable:
            return Color(hex: "D26A5C")
        default:
            return MeScreenPalette.mutedText
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeSettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let isPadLayout: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                .foregroundStyle(MeScreenPalette.text)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(
                    SidebarGlassToggleStyle(
                        accentColor: MeScreenPalette.accent,
                        inactiveColor: Color(hex: "8F8F8F").opacity(0.62)
                    )
                )
        }
        .frame(height: scaled(50, pad: 58))
        .padding(.horizontal, scaled(18, pad: 22))
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct MeSettingsActionRow: View {
    let title: String
    let isPadLayout: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                    .foregroundStyle(MeScreenPalette.text)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .bold))
                    .foregroundStyle(MeScreenPalette.mutedText.opacity(0.48))
            }
            .frame(height: scaled(50, pad: 58))
            .padding(.horizontal, scaled(18, pad: 22))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
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
                .foregroundStyle(NeumorphicColors.text.opacity(0.6))
            Text("Locale Region: \(AppLanguage.currentRegionCode)")
                .font(debugFont)
                .foregroundStyle(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Storefront: \(storefrontCountryCode) | \(storefrontID)")
                .font(debugFont)
                .foregroundStyle(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Language: \(languageCode)")
                .font(debugFont)
                .foregroundStyle(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Loaded Products: \(loaded)")
                .font(debugFont)
                .foregroundStyle(debugTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text("Missing Products: \(missing)")
                .font(debugFont)
                .foregroundStyle(debugTextColor)
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
                    .foregroundStyle(.white)
                    .position(x: proStarCenterX, y: 21.5)

                Text(titleText)
                    .font(OnboardingFonts.supporting(size: 20, weight: 600))
                    .foregroundStyle(.white)
                    .frame(width: titleFrameWidth, height: 25, alignment: textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .position(x: titlePositionX, y: 28.5)

                Text(subtitleText)
                    .font(OnboardingFonts.supporting(size: 14, weight: 500))
                    .foregroundStyle(subtitleColor)
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

struct HomeSidebarView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

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
                .foregroundStyle(NeumorphicColors.text.opacity(0.35))
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
