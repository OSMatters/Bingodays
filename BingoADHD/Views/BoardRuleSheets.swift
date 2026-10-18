import SwiftUI
import Foundation

struct SidebarGlassToggleStyle: ToggleStyle {
    var accentColor: Color = NeumorphicColors.modalAccent
    var inactiveColor: Color = Color.white.opacity(0.18)

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            Toggle(configuration)
                .toggleStyle(.switch)
                .tint(accentColor)
        } else {
            legacyBody(configuration: configuration)
        }
    }

    private func legacyBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.interpolatingSpring(stiffness: 210, damping: 18)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? accentColor.opacity(0.78) : inactiveColor)
                    .frame(width: 42, height: 24)
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(configuration.isOn ? 0.22 : 0.12),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.12), radius: 4, x: 1, y: 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.58), lineWidth: 0.6)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.14), radius: 4, x: 1.5, y: 1.5)
                    .shadow(color: Color.white.opacity(0.28), radius: 1.5, x: -0.8, y: -0.8)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

struct BoardCountdownSheet: View {
    let countdownEndsAt: Date?
    let onSave: (Int?) -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isCountdownEnabled: Bool
    @State private var countdownDays: Int
    @State private var countdownHours: Int
    @State private var countdownMinutes: Int
    @State private var isCancelCountdownConfirmationPresented = false

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var usesAccessibilityType: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var hasExistingCountdown: Bool {
        guard let countdownEndsAt else { return false }
        return countdownEndsAt > Date()
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(countdownEndsAt: Date?, onSave: @escaping (Int?) -> Void, onCancel: @escaping () -> Void) {
        let countdownTotalMinutes = Self.remainingMinutes(until: countdownEndsAt)
        self.countdownEndsAt = countdownEndsAt
        self.onSave = onSave
        self.onCancel = onCancel

        let (initialDays, initialHours, initialMinutes) = Self.makeTimeValues(from: countdownTotalMinutes ?? 1)
        _isCountdownEnabled = State(initialValue: countdownTotalMinutes != nil)
        _countdownDays = State(initialValue: initialDays)
        _countdownHours = State(initialValue: initialHours)
        _countdownMinutes = State(initialValue: initialMinutes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Button(L10n.cancel) {
                                onCancel()
                            }
                            .buttonStyle(.plain)
                            .appDynamicFont(size: scaled(17, pad: 19), weight: .regular, design: .rounded)
                            .foregroundStyle(NeumorphicColors.text.opacity(0.8))
                            .frame(minWidth: 44, minHeight: 44)

                            Spacer()

                            Button(L10n.save) {
                                onSave(resolvedTotalMinutes)
                            }
                            .buttonStyle(.plain)
                            .appDynamicFont(size: scaled(17, pad: 19), weight: .semibold, design: .rounded)
                            .foregroundStyle(NeumorphicColors.modalAccent)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Text(L10n.boardCountdownTitle)
                                    .appDynamicFont(size: scaled(17, pad: 20), weight: .bold, design: .rounded)
                                    .foregroundStyle(NeumorphicColors.text)

                                Spacer()

                                Toggle("", isOn: $isCountdownEnabled)
                                    .labelsHidden()
                                    .toggleStyle(NeumorphicSwitchToggleStyle())
                                    .accessibilityLabel(L10n.boardCountdownTitle)
                            }

                            if isCountdownEnabled {
                                Group {
                                    if usesAccessibilityType {
                                        VStack(spacing: 12) {
                                            countdownNumberField(title: L10n.tr("Days", zhHans: "天", zhHant: "天"), value: $countdownDays, range: 0...30)
                                            countdownNumberField(title: L10n.hours, value: $countdownHours, range: 0...23)
                                            countdownNumberField(title: L10n.minutes, value: $countdownMinutes, range: 0...59)
                                        }
                                    } else {
                                        HStack(spacing: 12) {
                                            countdownNumberField(title: L10n.tr("Days", zhHans: "天", zhHant: "天"), value: $countdownDays, range: 0...30)
                                            countdownNumberField(title: L10n.hours, value: $countdownHours, range: 0...23)
                                            countdownNumberField(title: L10n.minutes, value: $countdownMinutes, range: 0...59)
                                        }
                                    }
                                }

                                Text(countdownSummaryText)
                                    .appDynamicFont(size: scaled(12, pad: 14), design: .rounded)
                                    .foregroundStyle(NeumorphicColors.text.opacity(0.62))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .multilineTextAlignment(.center)
                            }

                            if hasExistingCountdown {
                                Button {
                                    isCancelCountdownConfirmationPresented = true
                                } label: {
                                    Text(L10n.tr("Cancel countdown", zhHans: "取消倒计时", zhHant: "取消倒計時"))
                                        .appDynamicFont(size: scaled(14, pad: 16), weight: .semibold, design: .rounded)
                                        .foregroundStyle(NeumorphicColors.text.opacity(0.82))
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 44)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(NeumorphicColors.background.opacity(0.94))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .stroke(NeumorphicColors.modalAccent.opacity(0.58), lineWidth: 1)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(24)
                    .padding(.top, 14)
                }
            }
            .alert(
                L10n.tr("Cancel countdown?", zhHans: "取消倒计时？", zhHant: "取消倒計時？"),
                isPresented: $isCancelCountdownConfirmationPresented
            ) {
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.tr("Confirm", zhHans: "确认", zhHant: "確認"), role: .destructive) {
                    onSave(nil)
                }
            } message: {
                Text(
                    L10n.tr(
                        "After canceling, the board countdown will stop immediately.",
                        zhHans: "取消后，面板倒计时会立即停止。",
                        zhHant: "取消後，面板倒計時會立即停止。",
                        ja: "キャンセルすると、ボードのカウントダウンはすぐに停止します。"
                    )
                )
            }
        }
    }

    private var totalMinutes: Int {
        let rawMinutes = (countdownDays * 24 * 60) + (countdownHours * 60) + countdownMinutes
        return min(max(rawMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }

    private var resolvedTotalMinutes: Int? {
        guard isCountdownEnabled else { return nil }
        return totalMinutes
    }

    private var countdownSummaryText: String {
        return L10n.tr(
            "When the countdown ends, you can choose to complete, abandon, or postpone.",
            zhHans: "倒计时结束后，你可以选择完成、放弃或延后。",
            zhHant: "倒計時結束後，你可以選擇完成、放棄或延後。",
            ja: "カウントダウン終了後、完了・放棄・延期を選べます。"
        )
    }

    private func countdownNumberField(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(title)
                .appDynamicFont(size: scaled(12, pad: 14), weight: .semibold, design: .rounded)
                .foregroundStyle(NeumorphicColors.text)
                .frame(maxWidth: .infinity, alignment: .center)

            TextField("0", value: value, formatter: Self.integerFormatter)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .accessibilityLabel(title)
                .appDynamicFont(size: scaled(18, pad: 22), weight: .bold, design: .rounded)
                .foregroundStyle(NeumorphicColors.text)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .onChange(of: value.wrappedValue) { _, newValue in
                    value.wrappedValue = min(max(newValue, range.lowerBound), range.upperBound)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NeumorphicColors.background.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NeumorphicColors.modalAccent.opacity(0.58), lineWidth: 1)
                )
        )
    }

    private static func remainingMinutes(until date: Date?) -> Int? {
        guard let date, date > Date() else { return nil }
        let seconds = date.timeIntervalSinceNow
        let totalMinutes = Int(ceil(seconds / 60))
        return min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }

    private static var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = BingoViewModel.maxCountdownMinutes as NSNumber
        return formatter
    }

    private static func makeTimeValues(from totalMinutes: Int) -> (Int, Int, Int) {
        let clamped = min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
        let days = clamped / (24 * 60)
        let hours = (clamped % (24 * 60)) / 60
        let minutes = clamped % 60
        return (days, hours, minutes)
    }
}

struct BoardRulesDraft: Equatable {
    let boardID: UUID
    let countdownMinutes: Int?
    let resetMode: BoardTaskResetMode
    let customResetMinutes: Int?
}

enum BoardRulesPremiumReturnRules {
    static func restorableDraft(
        from pendingDraft: BoardRulesDraft?,
        hasPremiumAccess: Bool,
        availableBoardIDs: Set<UUID>
    ) -> BoardRulesDraft? {
        guard hasPremiumAccess,
              let pendingDraft,
              availableBoardIDs.contains(pendingDraft.boardID) else {
            return nil
        }
        return pendingDraft
    }
}

struct BoardRulesSheet: View {
    let boardName: String?
    let countdownEndsAt: Date?
    let initialResetMode: BoardTaskResetMode
    let initialCustomResetMinutes: Int?
    let restoredDraft: BoardRulesDraft?
    let onSave: (Int?, BoardTaskResetMode, Int?) -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isCountdownEnabled: Bool
    @State private var countdownDays: Int
    @State private var countdownHours: Int
    @State private var countdownMinutes: Int
    @State private var selectedResetMode: BoardTaskResetMode
    @State private var isCustomResetTimeEnabled: Bool
    @State private var customResetTimeOfDay: Date

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var usesAccessibilityType: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var sheetBackgroundColor: Color { Color(hex: "FAF9F3") }
    private var contentTopOffset: CGFloat { 20 }
    private static let titleMaxCharacterCount = 12
    private static let resetTimeSectionID = "board-rules-reset-time-section"
    private static let countdownSectionID = "board-rules-countdown-section"

    init(
        boardName: String? = nil,
        countdownEndsAt: Date?,
        initialResetMode: BoardTaskResetMode,
        initialCustomResetMinutes: Int?,
        restoredDraft: BoardRulesDraft? = nil,
        onSave: @escaping (Int?, BoardTaskResetMode, Int?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let draftResetMode = restoredDraft?.resetMode ?? initialResetMode
        let draftCustomResetMinutes = restoredDraft == nil
            ? initialCustomResetMinutes
            : restoredDraft?.customResetMinutes
        let countdownTotalMinutes = restoredDraft == nil
            ? Self.remainingMinutes(until: countdownEndsAt)
            : restoredDraft?.countdownMinutes
        let (initialDays, initialHours, initialMinutes) = Self.makeTimeValues(from: countdownTotalMinutes ?? 1)
        let initialCustomResetTime = Self.makeClockDate(from: draftCustomResetMinutes ?? 0)
        let normalizedInitialMode: BoardTaskResetMode = draftResetMode == .customResetStatusTime
            ? .resetStatusNextDay
            : draftResetMode
        let normalizedInitialCustomResetMinutes = BoardResetRuleEngine.normalizedCustomResetMinutes(
            draftCustomResetMinutes,
            mode: normalizedInitialMode
        )
        let shouldEnableCustomResetTime = normalizedInitialCustomResetMinutes != nil

        self.boardName = boardName
        self.countdownEndsAt = countdownEndsAt
        self.initialResetMode = initialResetMode
        self.initialCustomResetMinutes = initialCustomResetMinutes
        self.restoredDraft = restoredDraft
        self.onSave = onSave
        self.onCancel = onCancel

        _isCountdownEnabled = State(initialValue: countdownTotalMinutes != nil)
        _countdownDays = State(initialValue: initialDays)
        _countdownHours = State(initialValue: initialHours)
        _countdownMinutes = State(initialValue: initialMinutes)
        _selectedResetMode = State(initialValue: normalizedInitialMode)
        _isCustomResetTimeEnabled = State(initialValue: shouldEnableCustomResetTime)
        _customResetTimeOfDay = State(initialValue: initialCustomResetTime)
    }

    var body: some View {
        ZStack {
            sheetBackgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: scaled(34, pad: 40)) {
                            resetRulesSection

                            if selectedResetMode != .keepTaskStatus {
                                resetTimeSection
                                    .id(Self.resetTimeSectionID)
                            }

                            countdownSection
                                .id(Self.countdownSectionID)
                        }
                        .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, scaled(22, pad: 30))
                        .padding(.bottom, scaled(42, pad: 54))
                    }
                    .background(sheetBackgroundColor)
                    .onAppear {
                        guard restoredDraft?.customResetMinutes != nil else { return }
                        scrollResetTimeIntoView(using: scrollProxy)
                    }
                    .onChange(of: isCountdownEnabled) { _, isEnabled in
                        guard isEnabled else { return }
                        scrollCountdownIntoView(using: scrollProxy)
                    }
                }
            }
            .padding(.top, contentTopOffset)
        }
        .background(sheetBackgroundColor.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sheetBackgroundColor
                .frame(height: 1)
        }
    }

    private var header: some View {
        Group {
            if usesAccessibilityType {
                VStack(spacing: 8) {
                    HStack {
                        cancelButton
                        Spacer()
                        saveButton
                    }

                    Text(sheetTitle)
                        .appDynamicFont(size: scaled(18, pad: 20), weight: .medium, design: .rounded)
                        .foregroundStyle(NeumorphicColors.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 12) {
                    cancelButton

                    Text(sheetTitle)
                        .appDynamicFont(size: scaled(18, pad: 20), weight: .medium, design: .rounded)
                        .foregroundStyle(NeumorphicColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)

                    saveButton
                }
            }
        }
        .padding(.horizontal, scaled(22, pad: 30))
        .padding(.top, scaled(20, pad: 24))
        .padding(.bottom, scaled(30, pad: 34))
        .frame(maxWidth: isPadLayout ? 620 : .infinity)
    }

    private var cancelButton: some View {
        Button(L10n.cancel, action: onCancel)
            .buttonStyle(.plain)
            .appDynamicFont(size: scaled(16, pad: 18), weight: .regular, design: .rounded)
            .foregroundStyle(NeumorphicColors.text.opacity(0.86))
            .frame(width: usesAccessibilityType ? nil : scaled(72, pad: 86), alignment: .leading)
            .frame(minWidth: 44, minHeight: 44)
            .fixedSize(horizontal: usesAccessibilityType, vertical: false)
    }

    private var saveButton: some View {
        Button(L10n.save) {
            onSave(resolvedTotalMinutes, selectedResetMode, resolvedCustomResetMinutes)
        }
        .buttonStyle(.plain)
        .appDynamicFont(size: scaled(16, pad: 18), weight: .medium, design: .rounded)
        .foregroundStyle(NeumorphicColors.modalAccent)
        .frame(width: usesAccessibilityType ? nil : scaled(72, pad: 86), alignment: .trailing)
        .frame(minWidth: 44, minHeight: 44)
        .fixedSize(horizontal: usesAccessibilityType, vertical: false)
    }

    private var sheetTitle: String {
        guard let trimmedName = boardName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty else {
            return L10n.tr("Board Rules", zhHans: "面板规则", zhHant: "面板規則", ja: "ボードルール")
        }
        guard trimmedName.count > Self.titleMaxCharacterCount else {
            return trimmedName
        }
        return "\(trimmedName.prefix(Self.titleMaxCharacterCount))..."
    }

    private var resetRulesSection: some View {
        VStack(alignment: .leading, spacing: scaled(18, pad: 22)) {
            sectionTitle(
                L10n.tr("Reset Rules", zhHans: "重置规则", zhHant: "重置規則", ja: "リセットルール"),
                systemImage: "arrow.clockwise"
            )

            VStack(alignment: .leading, spacing: scaled(20, pad: 24)) {
                resetOptionRow(
                    mode: .resetStatusNextDay,
                    title: L10n.tr("Reset status", zhHans: "重置状态", zhHant: "重置狀態", ja: "状態をリセット"),
                    hint: L10n.tr(
                        "At the reset time each day, completed one-time tasks leave the board, unfinished one-time tasks stay, and repeating tasks return to incomplete.",
                        zhHans: "每天到达重置时间后，已完成的单次任务会离开棋盘，未完成的单次任务会保留，重复任务会回到未完成。",
                        zhHant: "每天到達重置時間後，已完成的單次任務會離開棋盤，未完成的單次任務會保留，重複任務會回到未完成。",
                        ja: "毎日リセット時刻になると、完了した単発タスクはボードから消え、未完了の単発タスクは残り、繰り返しタスクは未完了に戻ります。"
                    )
                )

                resetOptionRow(
                    mode: .clearTasksNextDay,
                    title: L10n.tr("Clear tasks", zhHans: "清空任务", zhHant: "清空任務", ja: "タスクをクリア"),
                    hint: L10n.tr(
                        "Regular tasks are cleared. Repeating tasks keep their schedule and return to incomplete. The board countdown ends.",
                        zhHans: "单次任务会被清空；重复任务保留原计划并回到未完成；面板倒计时同时结束。",
                        zhHant: "單次任務會被清空；重複任務保留原計劃並回到未完成；面板倒計時同時結束。",
                        ja: "通常タスクはクリアされ、繰り返しタスクは予定を維持したまま未完了に戻り、ボードのカウントダウンも終了します。"
                    )
                )

                resetOptionRow(
                    mode: .keepTaskStatus,
                    title: L10n.tr("Keep status", zhHans: "保持状态", zhHant: "保持狀態", ja: "状態を保持"),
                    hint: L10n.tr(
                        "All tasks keep their completion status.",
                        zhHans: "所有任务的完成状态保持不变。",
                        zhHant: "所有任務的完成狀態保持不變。",
                        ja: "すべてのタスクの完了状態を維持します。"
                    )
                )
            }
        }
    }

    private var resetTimeSection: some View {
        VStack(alignment: .leading, spacing: scaled(18, pad: 22)) {
            sectionTitle(
                L10n.tr("Reset Time", zhHans: "重置时间", zhHant: "重置時間", ja: "リセット時刻"),
                systemImage: "clock"
            )

            VStack(alignment: .leading, spacing: scaled(22, pad: 26)) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCustomResetTimeEnabled = false
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(L10n.tr("Default every night 24:00", zhHans: "默认每晚 24:00", zhHant: "預設每晚 24:00", ja: "毎晩 24:00"))
                            .appDynamicFont(size: scaled(16, pad: 18), design: .rounded)
                            .foregroundStyle(NeumorphicColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        selectionCircle(isSelected: !isCustomResetTimeEnabled)
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityAddTraits(!isCustomResetTimeEnabled ? .isSelected : [])
                .accessibilityValue(
                    isCustomResetTimeEnabled
                        ? L10n.tr("Not selected", zhHans: "未选中", zhHant: "未選取", ja: "未選択")
                        : L10n.tr("Selected", zhHans: "已选中", zhHant: "已選取", ja: "選択中")
                )

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCustomResetTimeEnabled = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(L10n.tr("Custom time", zhHans: "自定义时间", zhHant: "自訂時間", ja: "カスタム時刻"))
                            .appDynamicFont(size: scaled(16, pad: 18), design: .rounded)
                            .foregroundStyle(NeumorphicColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        selectionCircle(isSelected: isCustomResetTimeEnabled)
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityAddTraits(isCustomResetTimeEnabled ? .isSelected : [])
                .accessibilityValue(
                    isCustomResetTimeEnabled
                        ? L10n.tr("Selected", zhHans: "已选中", zhHant: "已選取", ja: "選択中")
                        : L10n.tr("Not selected", zhHans: "未选中", zhHant: "未選取", ja: "未選択")
                )

                if isCustomResetTimeEnabled {
                    Text(customResetDailySummaryText)
                        .appDynamicFont(size: scaled(13, pad: 15), design: .rounded)
                        .foregroundStyle(NeumorphicColors.text.opacity(0.58))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)

                    DatePicker(
                        "",
                        selection: $customResetTimeOfDay,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .environment(\.colorScheme, .light)
                    .tint(NeumorphicColors.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: usesAccessibilityType ? scaled(190, pad: 210) : scaled(148, pad: 166))
                    .clipped()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var countdownSection: some View {
        VStack(alignment: .leading, spacing: scaled(14, pad: 18)) {
            HStack(spacing: 12) {
                sectionTitle(
                    L10n.tr("Board Countdown", zhHans: "面板倒计时", zhHant: "面板倒計時", ja: "ボードカウントダウン"),
                    systemImage: "timer"
                )

                Spacer()

                Toggle("", isOn: $isCountdownEnabled.animation(.easeInOut(duration: 0.18)))
                    .labelsHidden()
                    .toggleStyle(BoardRulesCountdownToggleStyle(onTint: NeumorphicColors.modalAccent))
                    .scaleEffect(scaled(0.92, pad: 1.0), anchor: .trailing)
                    .accessibilityLabel(L10n.tr("Board countdown", zhHans: "面板倒计时", zhHant: "面板倒計時", ja: "ボードカウントダウン"))
                    .frame(minWidth: 44, minHeight: 44)
            }

            if isCountdownEnabled {
                countdownWheelPicker

                Text(countdownSummaryText)
                    .appDynamicFont(size: scaled(13, pad: 15), design: .rounded)
                    .foregroundStyle(NeumorphicColors.text.opacity(0.58))
                    .multilineTextAlignment(.leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(countdownDisabledHint)
                    .appDynamicFont(size: scaled(13, pad: 15), design: .rounded)
                    .foregroundStyle(NeumorphicColors.text.opacity(0.52))
            }
        }
    }

private struct BoardRulesCountdownToggleStyle: ToggleStyle {
    let onTint: Color

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            Toggle(configuration)
                .toggleStyle(.switch)
                .tint(onTint)
        } else {
            legacyBody(configuration: configuration)
        }
    }

    private func legacyBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(configuration.isOn ? onTint : Color(hex: "A8AAA8"))
                    .frame(width: 51, height: 31)

                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, x: 0, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityValue(
            configuration.isOn
                ? L10n.tr("On", zhHans: "开启", zhHant: "開啟", ja: "オン")
                : L10n.tr("Off", zhHans: "关闭", zhHant: "關閉", ja: "オフ")
        )
    }
}

    private var countdownWheelPicker: some View {
        HStack(spacing: scaled(8, pad: 12)) {
            countdownPickerColumn(
                title: L10n.tr("Days", zhHans: "天", zhHant: "天", ja: "日"),
                value: $countdownDays,
                range: 0...30
            )

            countdownPickerColumn(
                title: L10n.hours,
                value: $countdownHours,
                range: 0...23
            )

            countdownPickerColumn(
                title: L10n.minutes,
                value: $countdownMinutes,
                range: 0...59
            )
        }
        .frame(height: usesAccessibilityType ? scaled(220, pad: 244) : scaled(174, pad: 194))
        .clipped()
    }

    private func resetOptionRow(mode: BoardTaskResetMode, title: String, hint: String) -> some View {
        let isSelected = selectedResetMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedResetMode = mode
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .appDynamicFont(size: scaled(16, pad: 18), design: .rounded)
                        .foregroundStyle(isSelected ? NeumorphicColors.modalAccent : NeumorphicColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isSelected {
                        Text(hint)
                            .appDynamicFont(size: scaled(13, pad: 15), design: .rounded)
                            .foregroundStyle(NeumorphicColors.text.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                selectionCircle(isSelected: isSelected)
                    .padding(.top, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(
            isSelected
                ? L10n.tr("Selected", zhHans: "已选中", zhHant: "已選取", ja: "選択中")
                : L10n.tr("Not selected", zhHans: "未选中", zhHant: "未選取", ja: "未選択")
        )
    }

    private func countdownPickerColumn(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .appDynamicFont(size: scaled(13, pad: 15), design: .rounded)
                .foregroundStyle(NeumorphicColors.text.opacity(0.58))
                .frame(minHeight: usesAccessibilityType ? 44 : scaled(24, pad: 28))

            Picker(title, selection: value) {
                ForEach(Array(range), id: \.self) { item in
                    Text("\(item)")
                        .appDynamicFont(size: scaled(22, pad: 26), design: .rounded)
                        .foregroundStyle(NeumorphicColors.text)
                        .tag(item)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: usesAccessibilityType ? scaled(176, pad: 190) : scaled(146, pad: 164))
            .clipped()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func selectionCircle(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .appDynamicFont(size: scaled(22, pad: 24), weight: .medium, design: .rounded)
            .foregroundStyle(isSelected ? NeumorphicColors.modalAccent : NeumorphicColors.text.opacity(0.24))
            .frame(width: scaled(26, pad: 30), height: scaled(26, pad: 30))
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: scaled(7, pad: 8)) {
            Image(systemName: systemImage)
                .appDynamicFont(size: scaled(15, pad: 18), weight: .medium, design: .rounded)
                .foregroundStyle(NeumorphicColors.modalAccent)
                .frame(width: scaled(19, pad: 22), alignment: .center)

            Text(title)
                .appDynamicFont(size: scaled(17, pad: 20), weight: .medium, design: .rounded)
                .foregroundStyle(NeumorphicColors.text)
        }
    }

    private func scrollCountdownIntoView(using proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(Self.countdownSectionID, anchor: .bottom)
            }
        }
    }

    private func scrollResetTimeIntoView(using proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(Self.resetTimeSectionID, anchor: .center)
            }
        }
    }

    private var countdownDisabledHint: String {
        L10n.tr(
            "Turn it on to set a countdown duration. The board must be completed within the selected time.",
            zhHans: "开启后，才设置倒计时时长；需要在设定时间内完成面板所有任务。",
            zhHant: "開啟後，才設定倒計時時長；需要在設定時間內完成面板所有任務。",
            ja: "オンにするとカウントダウン時間を設定できます。設定時間内にボードの全タスクを完了する必要があります。"
        )
    }

    private var totalMinutes: Int {
        let rawMinutes = (countdownDays * 24 * 60) + (countdownHours * 60) + countdownMinutes
        return min(max(rawMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }

    private var resolvedTotalMinutes: Int? {
        guard isCountdownEnabled else { return nil }
        return totalMinutes
    }

    private var resolvedCustomResetMinutes: Int? {
        guard isCustomResetTimeEnabled, selectedResetMode != .keepTaskStatus else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: customResetTimeOfDay)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        return BoardResetRuleEngine.normalizedCustomResetMinutes(
            hour * 60 + minute,
            mode: selectedResetMode
        )
    }

    private var customResetDailySummaryText: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: customResetTimeOfDay)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        let time = String(format: "%02d:%02d", hour, minute)
        return L10n.tr(
            "Resets every day at \(time)",
            zhHans: "每天 \(time) 重置",
            zhHant: "每天 \(time) 重置",
            ja: "毎日 \(time) にリセット"
        )
    }

    private var countdownSummaryText: String {
        return L10n.tr(
            "After turning it on, all board tasks must be completed within the selected time.",
            zhHans: "开启后，需要在设定时间内完成面板所有任务。",
            zhHant: "開啟後，需要在設定時間內完成面板所有任務。",
            ja: "オンにすると、設定時間内にボードの全タスクを完了する必要があります。"
        )
    }

    private static func remainingMinutes(until date: Date?) -> Int? {
        guard let date, date > Date() else { return nil }
        let seconds = date.timeIntervalSinceNow
        let totalMinutes = Int(ceil(seconds / 60))
        return min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }

    private static func makeTimeValues(from totalMinutes: Int) -> (Int, Int, Int) {
        let clamped = min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
        let days = clamped / (24 * 60)
        let hours = (clamped % (24 * 60)) / 60
        let minutes = clamped % 60
        return (days, hours, minutes)
    }

    private static func makeClockDate(from totalMinutes: Int) -> Date {
        let clamped = min(max(totalMinutes, 0), 23 * 60 + 59)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: clamped, to: start) ?? Date()
    }
}
