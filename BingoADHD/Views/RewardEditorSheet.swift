import SwiftUI
import UIKit

struct RewardThemeSkin: Identifiable {
    let id: Int

    var imageName: String {
        "CustomRewardTheme\(id)"
    }

    static let all: [RewardThemeSkin] = (1...9).map { RewardThemeSkin(id: $0) }
}

private struct RewardEditorLayout {
    let headerTopPadding: CGFloat
    let headerLeadingPadding: CGFloat
    let headerTrailingPadding: CGFloat
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardScale: CGFloat
    let cardCenterY: CGFloat
    let cardSkinPanelHeight: CGFloat
}

struct RewardEditorSheet: View {
    private enum CardSkinTab: Equatable {
        case emoji
        case theme
    }

    let reward: CustomReward?
    let isSaving: Bool
    let onSave: (String, Int, String, String?) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var titleText: String
    @State private var pointsText: String
    @State private var selectedEmoji: String
    @State private var selectedThemeImageName: String?
    @State private var selectedSkinTab: CardSkinTab
    @State private var emojiInputBuffer = ""
    @State private var isEmojiKeyboardPresented = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var editorGlobalFrame: CGRect = .zero
    @State private var emojiHistory: [String]
    @State private var validationMessage: String?
    @StateObject private var inputSession = RewardEditorInputSession()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.blindBoxWindowSafeAreaInsets) private var windowSafeAreaInsets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesAccessibilityType: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var isPadDevice: Bool {
        // The unfolded Duo is a regular-width window even though it is still an iPhone.
        isPadLayout
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(
        reward: CustomReward?,
        isSaving: Bool = false,
        onSave: @escaping (String, Int, String, String?) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.reward = reward
        self.isSaving = isSaving
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _titleText = State(initialValue: reward?.title ?? "")
        _pointsText = State(initialValue: reward.map { String($0.requiredPoints) } ?? "")
        _selectedEmoji = State(initialValue: reward?.displayEmoji ?? "😊")
        _selectedThemeImageName = State(initialValue: reward?.themeImageName)
        _selectedSkinTab = State(initialValue: reward?.themeImageName == nil ? .emoji : .theme)
        _emojiHistory = State(initialValue: Self.loadEmojiHistory(current: reward?.displayEmoji))
    }

    private static func loadEmojiHistory(current: String?) -> [String] {
        var history = UserDefaults.standard.stringArray(forKey: AppSettings.rewardEmojiHistoryKey) ?? ["😊", "🎁", "⭐️", "🏆", "🎉", "🍰"]
        if let current, !current.isEmpty {
            history.removeAll { $0 == current }
            history.insert(current, at: 0)
        }
        return Array(history.prefix(12))
    }

    private func rememberEmoji(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let emoji = trimmed.first.map(String.init), !emoji.isEmpty else { return }
        var history = emojiHistory
        history.removeAll { $0 == emoji }
        history.insert(emoji, at: 0)
        history = Array(history.prefix(12))
        emojiHistory = history
        UserDefaults.standard.set(history, forKey: AppSettings.rewardEmojiHistoryKey)
    }

    private func saveReward() {
        DiagnosticLogStore.recordUserAction("custom_reward.save_requested", details: [
            "is_saving": "\(isSaving)", "keyboard_visible": "\(isKeyboardVisible)"
        ])
        guard !isSaving else { return }
        let input = inputSession.prepareSave(fallbackTitle: titleText, fallbackPoints: pointsText)
        titleText = input.title
        pointsText = input.pointsText
        isEmojiKeyboardPresented = false
        keyboardHeight = 0
        DiagnosticLogStore.recordUserAction("custom_reward.save_tapped", details: [
            "editing_existing": "\(reward != nil)",
            "title_valid": "\(!input.title.isEmpty)",
            "points_valid": "\(input.requiredPoints != nil)"
        ])
        guard !input.title.isEmpty else {
            validationMessage = L10n.tr("Enter a reward name.", zhHans: "请填写奖励名称。", zhHant: "請填寫獎勵名稱。", ja: "報酬名を入力してください。")
            return
        }
        guard let requiredPoints = input.requiredPoints else {
            validationMessage = L10n.tr("Enter 1–9999 redemption points.", zhHans: "请填写 1–9999 的兑换积分。", zhHant: "請填寫 1–9999 的兌換積分。", ja: "交換ポイントを1〜9999で入力してください。")
            return
        }
        rememberEmoji(selectedEmoji)
        onSave(input.title, requiredPoints, selectedEmoji, selectedThemeImageName)
    }

    private func endInputSession() {
        isEmojiKeyboardPresented = false
        keyboardHeight = 0
        inputSession.endEditing()
    }

    private func cancelEditing() {
        endInputSession()
        onCancel()
    }

    private var skinPickerContentHeight: CGFloat {
        usesAccessibilityType ? scaled(260, pad: 320) : scaled(220, pad: 288)
    }

    private var cardSkinPanelBottomOffset: CGFloat {
        scaled(34, pad: 42)
    }

    private var isKeyboardVisible: Bool {
        keyboardHeight > 0 || isEmojiKeyboardPresented
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = editorLayout(
                for: proxy.size,
                safeAreaInsets: resolvedSafeAreaInsets(from: proxy.safeAreaInsets)
            )

            ZStack(alignment: .bottom) {
                PointsRewardBackground()
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }

                if isEmojiKeyboardPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissKeyboard()
                        }
                }

                VStack(spacing: 0) {
                    editorHeader
                        .padding(.top, layout.headerTopPadding)
                        .padding(.leading, layout.headerLeadingPadding)
                        .padding(.trailing, layout.headerTrailingPadding)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: isPadLayout ? 620 : .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .zIndex(2)

                rewardTicketPreview(cardWidth: layout.cardWidth, scale: layout.cardScale)
                    .frame(width: layout.cardWidth, height: layout.cardHeight)
                    .position(x: proxy.size.width / 2, y: layout.cardCenterY)
                    .zIndex(1)

                if isPadDevice {
                    cardSkinPanel(height: layout.cardSkinPanelHeight)
                        .allowsHitTesting(!isKeyboardVisible)
                        .zIndex(3)
                } else if !isKeyboardVisible {
                    cardSkinPanel(height: layout.cardSkinPanelHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(3)
                }

                if isEmojiKeyboardPresented {
                    EmojiKeyboardHost(
                        text: $emojiInputBuffer,
                        isPresented: $isEmojiKeyboardPresented,
                        inputSession: inputSession
                    )
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
            }
            .onAppear {
                editorGlobalFrame = proxy.frame(in: .global)
            }
            .onChange(of: proxy.size) { _, _ in
                editorGlobalFrame = proxy.frame(in: .global)
            }
            .onChange(of: proxy.safeAreaInsets) { _, _ in
                editorGlobalFrame = proxy.frame(in: .global)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .alert(L10n.tr("Check reward details", zhHans: "请检查奖励信息", zhHant: "請檢查獎勵資料", ja: "報酬の内容を確認してください"), isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button(L10n.ok, role: .cancel) { validationMessage = nil }
        } message: {
            Text(validationMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            updateKeyboardHeight(from: notification)
        }
        .onChange(of: selectedEmoji) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstCluster = trimmed.first.map(String.init) ?? ""
            if selectedEmoji != firstCluster {
                selectedEmoji = firstCluster
            }
        }
        .onChange(of: emojiInputBuffer) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstCluster = trimmed.first.map(String.init) ?? ""
            guard !firstCluster.isEmpty else { return }
            selectedEmoji = firstCluster
            rememberEmoji(firstCluster)
        }
        .onDisappear {
            inputSession.endEditing()
        }
    }

    private func editorLayout(for size: CGSize, safeAreaInsets: EdgeInsets) -> RewardEditorLayout {
        let usesExpandedPadPortraitLayout = isPadLayout
            && size.height > size.width
        let baseCardWidth = scaled(280, pad: 360)
        let baseCardHeight = scaled(347, pad: 446)
        let expandedCardWidth = min(440, size.width * 0.54)
        let defaultCardWidth = usesExpandedPadPortraitLayout
            ? max(baseCardWidth, expandedCardWidth)
            : baseCardWidth
        let defaultCardHeight = baseCardHeight * (defaultCardWidth / baseCardWidth)
        let headerTopPadding = scaled(8, pad: 12)
        let panelHeight = usesAccessibilityType
            ? min(scaled(480, pad: 560), max(scaled(360, pad: 430), size.height * 0.58))
            : scaled(350, pad: 430)
        let headerLeadingPadding = max(
            scaled(24, pad: 34),
            max(0, safeAreaInsets.leading) + scaled(12, pad: 16)
        )
        let headerTrailingPadding = max(
            scaled(24, pad: 34),
            max(0, safeAreaInsets.trailing) + scaled(12, pad: 16)
        )
        let headerHeight = usesAccessibilityType ? scaled(112, pad: 128) : scaled(56, pad: 66)
        let minimumCardTop = max(0, safeAreaInsets.top) + headerTopPadding + headerHeight + scaled(8, pad: 12)
        let panelTop = size.height - panelHeight + cardSkinPanelBottomOffset
        let cardBottom = panelTop - scaled(10, pad: 14)
        let availableCardHeight = max(scaled(148, pad: 190), cardBottom - minimumCardTop)
        let cardFitScale = min(1, max(0.62, availableCardHeight / defaultCardHeight))
        let cardHeight = defaultCardHeight * cardFitScale
        let cardWidth = defaultCardWidth * cardFitScale

        return RewardEditorLayout(
            headerTopPadding: headerTopPadding,
            headerLeadingPadding: headerLeadingPadding,
            headerTrailingPadding: headerTrailingPadding,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            cardScale: cardWidth / baseCardWidth,
            cardCenterY: usesExpandedPadPortraitLayout
                ? (minimumCardTop + cardBottom) / 2
                : cardBottom - cardHeight / 2,
            cardSkinPanelHeight: panelHeight
        )
    }

    /// The pull portal extends its artwork below system bars. Its window inset
    /// remains reliable even when this editor's local GeometryReader is full-screen.
    private func resolvedSafeAreaInsets(from localInsets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: max(localInsets.top, windowSafeAreaInsets.top),
            leading: max(localInsets.leading, windowSafeAreaInsets.leading),
            bottom: max(localInsets.bottom, windowSafeAreaInsets.bottom),
            trailing: max(localInsets.trailing, windowSafeAreaInsets.trailing)
        )
    }

    private var editorHeader: some View {
        Group {
            if usesAccessibilityType {
                VStack(spacing: 4) {
                    HStack {
                        backButton
                        Spacer(minLength: 12)
                        saveButton
                    }

                    Text(L10n.rewardCard)
                        .appDynamicFont(size: scaled(20, pad: 24), weight: .semibold, design: .rounded)
                        .foregroundStyle(NeumorphicColors.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    backButton.offset(y: -10)

                    Spacer()

                    Text(L10n.rewardCard)
                        .appDynamicFont(size: scaled(20, pad: 24), weight: .semibold, design: .rounded)
                        .foregroundStyle(NeumorphicColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer()

                    saveButton.offset(y: -10)
                }
            }
        }
        .appGlassEffectContainer()
    }

    private var backButton: some View {
        Button {
            cancelEditing()
        } label: {
            LiquidGlassIconBadge(
                systemName: "chevron.left",
                size: scaled(48, pad: 56),
                iconSize: scaled(18, pad: 22),
                foregroundColor: NeumorphicColors.text,
                glassInteractive: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.cancel)
    }

    private var saveButton: some View {
        Button(action: saveReward) {
            Group {
                if isSaving {
                    ProgressView()
                        .tint(NeumorphicColors.text)
                        .accessibilityLabel(L10n.tr("Saving reward", zhHans: "正在保存奖励", zhHant: "正在儲存獎勵", ja: "報酬を保存中"))
                } else {
                    Text(L10n.save)
                        .appDynamicFont(size: scaled(15, pad: 18), weight: .semibold, design: .rounded)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(NeumorphicColors.text)
            .frame(
                width: usesAccessibilityType ? nil : scaled(54, pad: 64),
                height: usesAccessibilityType ? nil : scaled(48, pad: 56)
            )
            .frame(
                minWidth: usesAccessibilityType ? scaled(88, pad: 104) : nil,
                maxWidth: usesAccessibilityType ? scaled(148, pad: 168) : nil,
                minHeight: usesAccessibilityType ? 56 : nil
            )
            .appLiquidGlass(in: Capsule(style: .continuous), interactive: false)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(
            isSaving
                ? L10n.tr("Saving reward", zhHans: "正在保存奖励", zhHant: "正在儲存獎勵", ja: "報酬を保存中")
                : L10n.save
        )
        .accessibilityIdentifier("customReward.save")
    }

    private func rewardTicketPreview(cardWidth previewCardWidth: CGFloat, scale: CGFloat) -> some View {
        let contentScale = max(0.62, min(1.25, scale))
        let titleHeight = max(scaled(44, pad: 56) * contentScale, scaled(34, pad: 40))
        let pointsHeight = max(scaled(42, pad: 52) * contentScale, scaled(32, pad: 38))

        return ZStack {
            Image(selectedThemeImageName ?? "CustomRewardDefaultCard")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .shadow(color: Color(red: 0.66, green: 0.48, blue: 0.22).opacity(0.16), radius: 18, x: 0, y: 12)

            VStack(spacing: 0) {
                if selectedThemeImageName != nil {
                    Color.clear
                        .frame(height: previewCardWidth * CustomRewardThemeCardImage.contentTopRatio)
                    Color.clear
                        .frame(height: scaled(16, pad: 22) * contentScale)
                } else {
                    previewEmoji(scale: contentScale)
                }

                titleEditor(scale: contentScale, height: titleHeight)
                    .frame(height: titleHeight)
                    .padding(.horizontal, scaled(28, pad: 36) * contentScale)

                pointsEditor(scale: contentScale, height: pointsHeight)
                    .frame(height: pointsHeight)
                    .padding(.horizontal, scaled(34, pad: 44) * contentScale)
                    .offset(y: scaled(5, pad: 5) * contentScale)

                Spacer(minLength: 0)
            }
            .padding(.top, scaled(12, pad: 16) * contentScale)
        }
    }

    private func titleEditor(scale: CGFloat, height: CGFloat) -> some View {
        RewardInlineTextField(
            text: $titleText,
            placeholder: L10n.rewardNamePlaceholder,
            maxLength: AppSettings.maxRewardTitleLength,
            keyboardType: .default,
            allowsOnlyDigits: false,
            font: .systemFont(ofSize: max(scaled(18, pad: 22) * scale, scaled(13, pad: 15)), weight: .regular),
            textColor: UIColor(NeumorphicColors.text),
            placeholderColor: UIColor(red: 0.51, green: 0.51, blue: 0.51, alpha: 1),
            textAlignment: .center,
            field: .title,
            inputSession: inputSession
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func pointsEditor(scale: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: scaled(4, pad: 6) * scale) {
            Text(L10n.rewardSetRedeem)
                .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))

            RewardInlineTextField(
                text: $pointsText,
                placeholder: "0",
                maxLength: 4,
                keyboardType: .numberPad,
                allowsOnlyDigits: true,
                font: .systemFont(ofSize: max(scaled(16, pad: 19) * scale, scaled(12, pad: 14)), weight: .medium),
                textColor: UIColor(NeumorphicColors.text),
                placeholderColor: UIColor(red: 0.51, green: 0.51, blue: 0.51, alpha: 1),
                textAlignment: .center,
                field: .points,
                inputSession: inputSession
            )
                .frame(width: max(scaled(64, pad: 80) * scale, scaled(44, pad: 54)))

            Text(L10n.pointsUnit)
                .foregroundStyle(NeumorphicColors.text)
        }
        .appDynamicFont(size: max(scaled(15, pad: 18) * scale, scaled(12, pad: 14)), weight: .medium, design: .rounded)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func cardSkinPanel(height: CGFloat) -> some View {
        let panelContents = VStack(spacing: scaled(18, pad: 22)) {
            Text(L10n.cardSkin)
                .appDynamicFont(size: scaled(16, pad: 20), weight: .semibold, design: .rounded)
                .foregroundStyle(NeumorphicColors.text)
                .padding(.top, scaled(23, pad: 28))

            HStack {
                cardSkinTabButton(title: L10n.emoji, tab: .emoji)

                Spacer()

                cardSkinTabButton(title: L10n.rewardTheme, tab: .theme)
            }
            .padding(.horizontal, scaled(34, pad: 120))

            if selectedSkinTab == .emoji {
                emojiSkinPicker
            } else {
                themeSkinPicker
            }
        }

        return Group {
            if usesAccessibilityType {
                ScrollView(showsIndicators: false) {
                    panelContents
                }
            } else {
                panelContents
            }
        }
        .frame(height: height, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.9), value: selectedSkinTab)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.9), value: selectedThemeImageName)
        .frame(maxWidth: isPadLayout ? 620 : .infinity)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: scaled(14, pad: 18),
                topTrailingRadius: scaled(14, pad: 18),
                style: .continuous
            )
            .fill(Color(red: 0.99, green: 0.99, blue: 0.99))
        )
        .offset(y: cardSkinPanelBottomOffset)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func cardSkinTabButton(title: String, tab: CardSkinTab) -> some View {
        let isSelected = selectedSkinTab == tab

        return Button {
            selectedSkinTab = tab
        } label: {
            Text(title)
                .appDynamicFont(size: scaled(14, pad: 17), weight: .regular, design: .rounded)
                .foregroundStyle(isSelected ? .white : Color(red: 0.51, green: 0.51, blue: 0.51))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: usesAccessibilityType ? scaled(112, pad: 132) : scaled(76, pad: 92))
                .frame(minHeight: usesAccessibilityType ? 44 : scaled(22, pad: 26))
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(red: 0.82, green: 0.64, blue: 0.48) : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emojiSkinPicker: some View {
        VStack(spacing: scaled(14, pad: 18)) {
            if emojiHistory.isEmpty {
                emojiAddButton(showHint: true)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: scaled(10, pad: 12)),
                        count: usesAccessibilityType ? 3 : 4
                    ),
                    spacing: scaled(10, pad: 12)
                ) {
                    emojiAddButton(showHint: false)

                    ForEach(emojiHistory, id: \.self) { emoji in
                        Button {
                            selectedThemeImageName = nil
                            selectedEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: scaled(32, pad: 40)))
                                .frame(maxWidth: .infinity)
                                .frame(height: scaled(52, pad: 64))
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(emoji == selectedEmoji ? Color(red: 0.99, green: 0.92, blue: 0.85) : Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(emoji == selectedEmoji ? Color(red: 0.93, green: 0.45, blue: 0.18) : Color.black.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(emoji == selectedEmoji ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.horizontal, scaled(32, pad: 44))
        .padding(.bottom, scaled(24, pad: 32))
        .frame(height: usesAccessibilityType ? nil : skinPickerContentHeight, alignment: .top)
    }

    @ViewBuilder
    private func emojiAddButton(showHint: Bool) -> some View {
        Button {
            presentEmojiKeyboard()
        } label: {
            if showHint {
                HStack(spacing: scaled(14, pad: 18)) {
                    emojiAddIcon

                    Text(L10n.rewardEmojiKeyboardHint)
                        .appDynamicFont(size: scaled(14, pad: 17), weight: .semibold, design: .rounded)
                        .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, scaled(18, pad: 26))
                .padding(.vertical, scaled(10, pad: 12))
            } else {
                emojiAddIcon
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("Add an emoji", zhHans: "添加表情", zhHant: "新增表情", ja: "絵文字を追加"))
        .accessibilityHint(L10n.rewardEmojiKeyboardHint)
    }

    @ViewBuilder
    private func previewEmoji(scale: CGFloat) -> some View {
        Button {
            presentEmojiKeyboard()
        } label: {
            previewEmojiLabel(scale: scale)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(L10n.emoji)
        .accessibilityValue(selectedEmoji)
        .accessibilityHint(L10n.rewardEmojiKeyboardHint)
    }

    private func previewEmojiLabel(scale: CGFloat) -> some View {
        Text(selectedEmoji)
            .font(.system(size: scaled(112, pad: 142) * scale))
            .minimumScaleFactor(0.72)
            .frame(height: scaled(204, pad: 262) * scale)
            .frame(maxWidth: .infinity)
    }

    private var emojiAddIcon: some View {
        Image(systemName: "plus")
            .font(.appSystem(size: scaled(22, pad: 27), weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: scaled(52, pad: 64))
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.76, blue: 0.73))
            )
            .accessibilityHidden(true)
    }

    private var themeSkinPicker: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: scaled(10, pad: 14)),
            count: usesAccessibilityType ? 2 : 3
        )

        let themeGrid = LazyVGrid(columns: columns, spacing: scaled(10, pad: 14)) {
            ForEach(RewardThemeSkin.all) { skin in
                Button {
                    selectedThemeImageName = skin.imageName
                    endInputSession()
                    emojiInputBuffer = ""
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(skin.imageName)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .aspectRatio(CustomRewardThemeCardImage.aspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        if selectedThemeImageName == skin.imageName {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.appSystem(size: scaled(22, pad: 26), weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                                .padding(scaled(5, pad: 6))
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    L10n.tr(
                        "Reward theme \(skin.id)",
                        zhHans: "奖励主题 \(skin.id)",
                        zhHant: "獎勵主題 \(skin.id)",
                        ja: "報酬テーマ \(skin.id)"
                    )
                )
                .accessibilityAddTraits(selectedThemeImageName == skin.imageName ? .isSelected : [])
                .accessibilityHint(
                    L10n.tr(
                        "Changes the reward card background.",
                        zhHans: "更改奖励卡片背景。",
                        zhHant: "更改獎勵卡片背景。",
                        ja: "報酬カードの背景を変更します。"
                    )
                )
            }
        }

        return Group {
            if usesAccessibilityType {
                themeGrid
            } else {
                ScrollView(showsIndicators: false) {
                    themeGrid
                }
                .frame(height: skinPickerContentHeight)
            }
        }
        .padding(.horizontal, scaled(24, pad: 34))
        .padding(.bottom, 0)
    }

    private func presentEmojiKeyboard() {
        inputSession.endEditing()
        selectedThemeImageName = nil
        selectedSkinTab = .emoji
        emojiInputBuffer = ""
        isEmojiKeyboardPresented = true
    }

    private func dismissKeyboard() {
        endInputSession()
        emojiInputBuffer = ""
    }

    private func updateKeyboardHeight(from notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        // Keyboard frames are reported in screen coordinates. Resolve the overlap against the
        // current window frame so Duo's inner display is not measured against the outer screen.
        let containerMaxY = editorGlobalFrame == .zero ? endFrame.maxY : editorGlobalFrame.maxY
        let overlap = max(0, containerMaxY - endFrame.minY)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.22

        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = overlap
        }
    }

}

private struct RewardInlineTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxLength: Int
    let keyboardType: UIKeyboardType
    let allowsOnlyDigits: Bool
    let font: UIFont
    let textColor: UIColor
    let placeholderColor: UIColor
    let textAlignment: NSTextAlignment
    let field: RewardEditorInputSession.Field
    let inputSession: RewardEditorInputSession

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.keyboardType = keyboardType
        textField.returnKeyType = .done
        textField.adjustsFontForContentSizeCategory = true
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartInsertDeleteType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = max(font.pointSize * 0.72, 10)
        applyConfiguration(to: textField)
        inputSession.register(textField, field: field)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        applyConfiguration(to: uiView)

        if !uiView.isFirstResponder, uiView.text != text, uiView.markedTextRange == nil {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleUIView(_ uiView: UITextField, coordinator: Coordinator) {
        coordinator.parent.inputSession.unregister(uiView)
        uiView.resignFirstResponder()
    }

    private func applyConfiguration(to textField: UITextField) {
        let scaledFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
        textField.font = scaledFont
        textField.minimumFontSize = max(scaledFont.pointSize * 0.72, 10)
        textField.textColor = textColor
        textField.textAlignment = textAlignment
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
        switch field {
        case .title:
            textField.accessibilityLabel = L10n.rewardTitle
            textField.accessibilityHint = L10n.tr(
                "Type a name for this reward.",
                zhHans: "输入这个奖励的名称。",
                zhHant: "輸入這個獎勵的名稱。",
                ja: "この報酬の名前を入力します。"
            )
            textField.accessibilityIdentifier = "customReward.title"
        case .points:
            textField.accessibilityLabel = L10n.rewardPoints
            textField.accessibilityHint = L10n.tr(
                "Enter a number from 1 to 9999.",
                zhHans: "请输入 1 到 9999 之间的数字。",
                zhHant: "請輸入 1 到 9999 之間的數字。",
                ja: "1〜9999の数字を入力してください。"
            )
            textField.accessibilityIdentifier = "customReward.points"
        case .emoji:
            textField.accessibilityLabel = L10n.emoji
            textField.accessibilityHint = L10n.rewardEmojiKeyboardHint
            textField.accessibilityIdentifier = "customReward.emoji"
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RewardInlineTextField

        init(parent: RewardInlineTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if textField.markedTextRange != nil {
                return true
            }

            let currentText = textField.text ?? ""
            guard let textRange = Range(range, in: currentText) else {
                return true
            }

            let proposed = currentText.replacingCharacters(in: textRange, with: string)
            let normalized = normalize(proposed)

            if proposed == normalized {
                return true
            }

            textField.text = normalized
            parent.text = normalized
            return false
        }

        private func syncText(from textField: UITextField) {
            guard textField.markedTextRange == nil else { return }

            let normalized = normalize(textField.text ?? "")
            if textField.text != normalized {
                textField.text = normalized
            }
            parent.text = normalized
        }

        private func normalize(_ rawValue: String) -> String {
            guard parent.allowsOnlyDigits else {
                return String(rawValue.prefix(parent.maxLength))
            }

            var digits = ""
            digits.reserveCapacity(parent.maxLength)
            for character in rawValue {
                guard let digit = character.wholeNumberValue else { continue }
                digits.append(String(digit))
                if digits.count >= parent.maxLength { break }
            }
            return digits
        }
    }
}

private struct EmojiKeyboardHost: UIViewRepresentable {
    @Binding var text: String
    @Binding var isPresented: Bool
    let inputSession: RewardEditorInputSession

    func makeUIView(context: Context) -> UITextField {
        let textField = RewardEmojiTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartInsertDeleteType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.tintColor = .clear
        textField.textColor = .clear
        textField.backgroundColor = .clear
        textField.returnKeyType = .done
        textField.accessibilityLabel = L10n.emoji
        textField.accessibilityHint = L10n.rewardEmojiKeyboardHint
        textField.accessibilityIdentifier = "customReward.emoji"
        inputSession.register(textField, field: .emoji)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if isPresented {
            context.coordinator.requestActivation(for: uiView)
        } else {
            context.coordinator.cancelActivation()
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isPresented: $isPresented, inputSession: inputSession)
    }

    static func dismantleUIView(_ uiView: UITextField, coordinator: Coordinator) {
        coordinator.cancelActivation()
        coordinator.inputSession?.unregister(uiView)
        uiView.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        @Binding private var isPresented: Bool
        weak var inputSession: RewardEditorInputSession?
        private var activationRequestID = 0

        init(
            text: Binding<String>,
            isPresented: Binding<Bool>,
            inputSession: RewardEditorInputSession
        ) {
            _text = text
            _isPresented = isPresented
            self.inputSession = inputSession
        }

        func requestActivation(for textField: UITextField) {
            guard isPresented, !textField.isFirstResponder else { return }

            activationRequestID += 1
            let requestID = activationRequestID
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self,
                      requestID == self.activationRequestID,
                      self.isPresented,
                      let textField,
                      textField.window != nil,
                      !textField.isFirstResponder else {
                    return
                }
                textField.becomeFirstResponder()
            }
        }

        func cancelActivation() {
            activationRequestID += 1
        }

        @objc func editingChanged(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            syncText(from: textField)
            isPresented = false
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            syncText(from: textField)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                guard let currentText = textField.text,
                      let textRange = Range(range, in: currentText) else {
                    return true
                }

                let updatedText = currentText.replacingCharacters(in: textRange, with: string)
                let normalized = normalizedEmoji(from: updatedText)
                textField.text = normalized
                text = normalized
                return false
            }

            let normalized = normalizedEmoji(from: string)
            textField.text = normalized
            text = normalized
            return false
        }

        func syncText(from textField: UITextField) {
            let normalized = normalizedEmoji(from: textField.text ?? "")
            if textField.text != normalized {
                textField.text = normalized
            }
            text = normalized
        }

        private func normalizedEmoji(from rawValue: String) -> String {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.first.map(String.init) ?? ""
        }
    }
}

enum CustomRewardThemeCardImage {
    static let aspectRatio: CGFloat = 561.0 / 680.0
    static let contentTopRatio: CGFloat = 0.66
}
