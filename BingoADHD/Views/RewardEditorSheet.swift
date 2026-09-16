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
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardScale: CGFloat
    let cardCenterY: CGFloat
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
    @State private var emojiHistory: [String]
    @StateObject private var inputSession = RewardEditorInputSession()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
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

    private var normalizedTitle: String {
        String(titleText.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPoints: Int? {
        guard let points = Int(pointsText), points > 0 else { return nil }
        return min(points, 9_999)
    }

    private var canSave: Bool {
        !normalizedTitle.isEmpty && normalizedPoints != nil
    }

    private func saveReward() {
        guard !isSaving else { return }
        endInputSession()
        guard let requiredPoints = normalizedPoints, !normalizedTitle.isEmpty else { return }
        commitSave(requiredPoints: requiredPoints)
    }

    private func commitSave(requiredPoints: Int) {
        rememberEmoji(selectedEmoji)
        onSave(normalizedTitle, requiredPoints, selectedEmoji, selectedThemeImageName)
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
        scaled(220, pad: 288)
    }

    private var cardSkinPanelHeight: CGFloat {
        scaled(350, pad: 430)
    }

    private var cardSkinPanelBottomOffset: CGFloat {
        scaled(34, pad: 42)
    }

    private var isKeyboardVisible: Bool {
        keyboardHeight > 0 || isEmojiKeyboardPresented
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = editorLayout(for: proxy.size)

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
                        .padding(.horizontal, scaled(24, pad: 34))

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
                    cardSkinPanel
                        .allowsHitTesting(!isKeyboardVisible)
                        .zIndex(3)
                } else if !isKeyboardVisible {
                    cardSkinPanel
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
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .dynamicTypeSize(.xSmall...DynamicTypeSize.xxxLarge)
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

    private func editorLayout(for size: CGSize) -> RewardEditorLayout {
        let usesExpandedPadPortraitLayout = UIDevice.current.userInterfaceIdiom == .pad
            && size.height > size.width
        let baseCardWidth = scaled(280, pad: 360)
        let baseCardHeight = scaled(347, pad: 446)
        let expandedCardWidth = min(440, size.width * 0.54)
        let defaultCardWidth = usesExpandedPadPortraitLayout
            ? max(baseCardWidth, expandedCardWidth)
            : baseCardWidth
        let defaultCardHeight = baseCardHeight * (defaultCardWidth / baseCardWidth)
        let headerTopPadding = scaled(3, pad: 17)
        let cardAnchorTopPadding = scaled(48, pad: 62)
        let headerHeight = scaled(56, pad: 66)
        let minimumCardTop = cardAnchorTopPadding + headerHeight + scaled(8, pad: 12)
        let panelTop = size.height - cardSkinPanelHeight + cardSkinPanelBottomOffset
        let cardBottom = panelTop - scaled(10, pad: 14)
        let availableCardHeight = max(scaled(148, pad: 190), cardBottom - minimumCardTop)
        let cardFitScale = min(1, max(0.62, availableCardHeight / defaultCardHeight))
        let cardHeight = defaultCardHeight * cardFitScale
        let cardWidth = defaultCardWidth * cardFitScale

        return RewardEditorLayout(
            headerTopPadding: headerTopPadding,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            cardScale: cardWidth / baseCardWidth,
            cardCenterY: usesExpandedPadPortraitLayout
                ? (minimumCardTop + cardBottom) / 2
                : cardBottom - cardHeight / 2
        )
    }

    private var editorHeader: some View {
        HStack {
            Button {
                cancelEditing()
            } label: {
                LiquidGlassIconBadge(
                    systemName: "chevron.left",
                    size: scaled(48, pad: 56),
                    iconSize: scaled(18, pad: 22),
                    foregroundColor: NeumorphicColors.text
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.rewardCard)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer()

            Button {
                saveReward()
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(NeumorphicColors.text)
                    } else {
                        Text(L10n.save)
                            .font(.appSystem(size: scaled(16, pad: 19), weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .foregroundColor(NeumorphicColors.text)
                .frame(width: scaled(60, pad: 72), height: scaled(40, pad: 46))
                .appLiquidGlass(in: Capsule(style: .continuous), interactive: canSave && !isSaving)
                .opacity(canSave ? 1 : 0.52)
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isSaving)
        }
        .appGlassEffectContainer()
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
            inputSession: inputSession
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func pointsEditor(scale: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: scaled(4, pad: 6) * scale) {
            Text(L10n.rewardSetRedeem)
                .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51))

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
                inputSession: inputSession
            )
                .frame(width: max(scaled(64, pad: 80) * scale, scaled(44, pad: 54)))

            Text(L10n.pointsUnit)
                .foregroundColor(NeumorphicColors.text)
        }
        .font(.appSystem(size: max(scaled(15, pad: 18) * scale, scaled(12, pad: 14)), weight: .medium, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var cardSkinPanel: some View {
        VStack(spacing: scaled(18, pad: 22)) {
            Text(L10n.cardSkin)
                .font(.appSystem(size: scaled(16, pad: 20), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .padding(.top, scaled(23, pad: 28))

            HStack {
                cardSkinTabButton(title: L10n.emoji, tab: .emoji)

                Spacer()

                cardSkinTabButton(title: L10n.rewardTheme, tab: .theme)
            }
            .font(.appSystem(size: scaled(14, pad: 17), weight: .regular, design: .rounded))
            .padding(.horizontal, scaled(34, pad: 120))

            if selectedSkinTab == .emoji {
                emojiSkinPicker
            } else {
                themeSkinPicker
            }
        }
        .frame(height: cardSkinPanelHeight, alignment: .top)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: selectedSkinTab)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: selectedThemeImageName)
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
                .foregroundColor(isSelected ? .white : Color(red: 0.51, green: 0.51, blue: 0.51))
                .frame(width: scaled(76, pad: 92), height: scaled(22, pad: 26))
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(red: 0.82, green: 0.64, blue: 0.48) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var emojiSkinPicker: some View {
        VStack(spacing: scaled(14, pad: 18)) {
            if emojiHistory.isEmpty {
                emojiAddButton(showHint: true)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: scaled(10, pad: 12)), count: 4),
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
                    }
                }
            }
        }
        .padding(.horizontal, scaled(32, pad: 44))
        .padding(.bottom, scaled(24, pad: 32))
        .frame(height: skinPickerContentHeight, alignment: .top)
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
                        .font(.appSystem(size: scaled(14, pad: 17), weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51))
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
    }

    @ViewBuilder
    private func previewEmoji(scale: CGFloat) -> some View {
        if isPadDevice {
            Button {
                presentEmojiKeyboard()
            } label: {
                previewEmojiLabel(scale: scale)
            }
            .buttonStyle(.plain)
        } else {
            previewEmojiLabel(scale: scale)
        }
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
            .foregroundColor(.white)
            .frame(height: scaled(52, pad: 64))
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.76, blue: 0.73))
            )
    }

    private var themeSkinPicker: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: scaled(10, pad: 14)), count: 3)

        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: scaled(10, pad: 14)) {
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
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                                    .padding(scaled(5, pad: 6))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: skinPickerContentHeight)
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

        let screenHeight = UIScreen.main.bounds.height
        let overlap = max(0, screenHeight - endFrame.minY)
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
    let inputSession: RewardEditorInputSession

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.keyboardType = keyboardType
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartInsertDeleteType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = max(font.pointSize * 0.72, 10)
        applyConfiguration(to: textField)
        inputSession.register(textField)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        applyConfiguration(to: uiView)

        if uiView.text != text, uiView.markedTextRange == nil {
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
        textField.font = font
        textField.textColor = textColor
        textField.textAlignment = textAlignment
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
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
        let textField = UITextField(frame: .zero)
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
        inputSession.register(textField)
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

private final class RewardEditorInputSession: ObservableObject {
    private final class WeakTextField {
        weak var value: UITextField?

        init(_ value: UITextField) {
            self.value = value
        }
    }

    private var textFields: [ObjectIdentifier: WeakTextField] = [:]

    func register(_ textField: UITextField) {
        removeReleasedTextFields()
        textFields[ObjectIdentifier(textField)] = WeakTextField(textField)
    }

    func unregister(_ textField: UITextField) {
        textFields.removeValue(forKey: ObjectIdentifier(textField))
    }

    func endEditing() {
        removeReleasedTextFields()
        textFields.values.compactMap(\.value).forEach { textField in
            textField.resignFirstResponder()
        }
    }

    private func removeReleasedTextFields() {
        textFields = textFields.filter { $0.value.value != nil }
    }
}
