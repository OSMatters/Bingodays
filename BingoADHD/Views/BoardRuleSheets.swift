import SwiftUI
import Foundation

struct SidebarGlassToggleStyle: ToggleStyle {
    var accentColor: Color = NeumorphicColors.accent

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.interpolatingSpring(stiffness: 210, damping: 18)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? accentColor.opacity(0.78) : Color.white.opacity(0.18))
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
    @State private var isCountdownEnabled: Bool
    @State private var countdownDays: Int
    @State private var countdownHours: Int
    @State private var countdownMinutes: Int
    @State private var isCancelCountdownConfirmationPresented = false

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
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

                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button(L10n.cancel) {
                            onCancel()
                        }
                        .buttonStyle(.plain)
                        .font(.appSystem(size: scaled(17, pad: 19), weight: .regular, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))

                        Spacer()

                        Button(L10n.save) {
                            onSave(resolvedTotalMinutes)
                        }
                        .buttonStyle(.plain)
                        .font(.appSystem(size: scaled(17, pad: 19), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.boardCountdownTitle)
                                    .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)
                            }

                            Spacer()

                            Toggle("", isOn: $isCountdownEnabled)
                                .labelsHidden()
                                .toggleStyle(NeumorphicSwitchToggleStyle())
                        }

                        if isCountdownEnabled {
                            HStack(spacing: 12) {
                                countdownNumberField(
                                    title: L10n.tr("Days", zhHans: "天", zhHant: "天"),
                                    value: $countdownDays,
                                    range: 0...30
                                )

                                countdownNumberField(
                                    title: L10n.hours,
                                    value: $countdownHours,
                                    range: 0...23
                                )

                                countdownNumberField(
                                    title: L10n.minutes,
                                    value: $countdownMinutes,
                                    range: 0...59
                                )
                            }

                            Text(countdownSummaryText)
                                .font(.appSystem(size: scaled(12, pad: 14), design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.62))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }

                        if hasExistingCountdown {
                            Button {
                                isCancelCountdownConfirmationPresented = true
                            } label: {
                                Text(L10n.tr("Cancel countdown", zhHans: "取消倒计时", zhHant: "取消倒計時"))
                                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.82))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: scaled(42, pad: 48))
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(NeumorphicColors.background.opacity(0.94))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(24)
                .padding(.top, 14)
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
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .frame(maxWidth: .infinity, alignment: .center)

            TextField("0", value: value, formatter: Self.integerFormatter)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.appSystem(size: scaled(18, pad: 22), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(48, pad: 56))
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
                        .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
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

struct BoardRulesSheet: View {
    let countdownEndsAt: Date?
    let initialResetMode: BoardTaskResetMode
    let initialCustomResetMinutes: Int?
    let onSave: (Int?, BoardTaskResetMode, Int?) -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(
        countdownEndsAt: Date?,
        initialResetMode: BoardTaskResetMode,
        initialCustomResetMinutes: Int?,
        onSave: @escaping (Int?, BoardTaskResetMode, Int?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let countdownTotalMinutes = Self.remainingMinutes(until: countdownEndsAt)
        let (initialDays, initialHours, initialMinutes) = Self.makeTimeValues(from: countdownTotalMinutes ?? 1)
        let initialCustomResetTime = Self.makeClockDate(from: initialCustomResetMinutes ?? 0)
        let normalizedInitialMode: BoardTaskResetMode = initialResetMode == .customResetStatusTime
            ? .resetStatusNextDay
            : initialResetMode
        let shouldEnableCustomResetTime = initialCustomResetMinutes != nil || initialResetMode == .customResetStatusTime

        self.countdownEndsAt = countdownEndsAt
        self.initialResetMode = initialResetMode
        self.initialCustomResetMinutes = initialCustomResetMinutes
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
        NavigationStack {
            ZStack {
                NeumorphicColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("Board Countdown", zhHans: "面板倒计时", zhHant: "面板倒計時"))
                                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            HStack(spacing: 12) {
                                Text(L10n.tr("Enable countdown", zhHans: "开启倒计时", zhHant: "開啟倒計時"))
                                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)
                                Spacer()
                                Toggle("", isOn: $isCountdownEnabled)
                                    .labelsHidden()
                                    .toggleStyle(NeumorphicSwitchToggleStyle())
                            }

                            if isCountdownEnabled {
                                HStack(spacing: 12) {
                                    countdownNumberField(
                                        title: L10n.tr("Days", zhHans: "天", zhHant: "天"),
                                        value: $countdownDays,
                                        range: 0...30
                                    )

                                    countdownNumberField(
                                        title: L10n.hours,
                                        value: $countdownHours,
                                        range: 0...23
                                    )

                                    countdownNumberField(
                                        title: L10n.minutes,
                                        value: $countdownMinutes,
                                        range: 0...59
                                    )
                                }

                                Text(countdownSummaryText)
                                    .font(.appSystem(size: scaled(12, pad: 14), design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.tr("Board task reset mode", zhHans: "面板任务重置方式", zhHant: "面板任務重置方式"))
                                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            resetOptionRow(
                                mode: .resetStatusNextDay,
                                title: L10n.tr(
                                    "Auto reset task status every other day",
                                    zhHans: "隔天自动重置任务状态",
                                    zhHant: "隔天自動重置任務狀態",
                                    ja: "翌日にタスク状態を自動リセット"
                                ),
                                hint: L10n.tr(
                                    "Regular tasks reset to incomplete the next day. Repeating tasks start fresh each time they appear.",
                                    zhHans: "普通任务会在第二天变回未完成，重复任务会在每次显示时重新开始。",
                                    zhHant: "普通任務會在第二天變回未完成，重複任務會在每次顯示時重新開始。",
                                    ja: "通常タスクは翌日に未完了へ戻り、繰り返しタスクは表示されるたびに新しく始まります。"
                                )
                            )

                            if selectedResetMode == .resetStatusNextDay {
                                customResetTimeSection
                            }

                            resetOptionRow(
                                mode: .clearTasksNextDay,
                                title: L10n.tr(
                                    "Auto clear regular tasks every other day",
                                    zhHans: "隔天自动清空普通任务",
                                    zhHant: "隔天自動清空普通任務",
                                    ja: "翌日に通常タスクを自動クリア"
                                ),
                                hint: L10n.tr(
                                    "Regular tile tasks clear the next day. Tasks with a time or repeat rule keep their plan and appear on schedule.",
                                    zhHans: "普通格子任务会在第二天清空，已设置时间或重复规则的任务会保留计划并按时显示。",
                                    zhHant: "普通格子任務會在第二天清空，已設定時間或重複規則的任務會保留計劃並按時顯示。",
                                    ja: "通常の格子タスクは翌日にクリアされます。時刻または繰り返しを設定したタスクは計画を保ち、予定どおり表示されます。"
                                )
                            )

                            resetOptionRow(
                                mode: .keepTaskStatus,
                                title: L10n.tr(
                                    "Keep regular task status",
                                    zhHans: "保持普通任务状态",
                                    zhHant: "保持普通任務狀態",
                                    ja: "通常タスクの状態を保持"
                                ),
                                hint: L10n.tr(
                                    "Regular tile tasks keep their current status. Repeating tasks start fresh each time they appear.",
                                    zhHans: "普通格子任务会保持当前状态，重复任务会在每次显示时重新开始。",
                                    zhHant: "普通格子任務會保持目前狀態，重複任務會在每次顯示時重新開始。",
                                    ja: "通常の格子タスクは現在の状態を保持します。繰り返しタスクは表示されるたびに新しく始まります。"
                                )
                            )
                        }
                    }
                    .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(24)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(L10n.tr("Board Rules", zhHans: "面板规则", zhHant: "面板規則"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { onCancel() }
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        onSave(resolvedTotalMinutes, selectedResetMode, resolvedCustomResetMinutes)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }

    private func resetOptionRow(mode: BoardTaskResetMode, title: String, hint: String) -> some View {
        let isSelected = selectedResetMode == mode
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                selectedResetMode = mode
                if mode != .resetStatusNextDay {
                    isCustomResetTimeEnabled = false
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold))
                        .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.45))

                    Text(title)
                        .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isSelected {
                Text(hint)
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .regular, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                    .padding(.leading, 28)
            }
        }
    }

    private var customResetTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isCustomResetTimeEnabled.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isCustomResetTimeEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold))
                        .foregroundColor(isCustomResetTimeEnabled ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.45))
                    Text(L10n.tr("Custom task status reset time", zhHans: "自定义重置任务状态时间", zhHant: "自訂重置任務狀態時間"))
                        .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                    proBadge
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.leading, 28)
            }
            .buttonStyle(.plain)

            if isCustomResetTimeEnabled {
                DatePicker(
                    "",
                    selection: $customResetTimeOfDay,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.wheel)
                .environment(\.colorScheme, .light)
                .tint(.black)
                .foregroundStyle(.black)
                .colorMultiply(.black)
                .compositingGroup()
                .frame(maxWidth: .infinity)
                .frame(height: isPadLayout ? 160 : 148)
                .clipped()
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(NeumorphicColors.background.opacity(0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.leading, 28)

                Text(customResetTimeSummaryText)
                    .font(.appSystem(size: scaled(12, pad: 14), design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var proBadge: some View {
        Text("Pro")
            .font(.appSystem(size: scaled(11, pad: 12), weight: .bold, design: .rounded))
            .foregroundColor(NeumorphicColors.accent)
            .padding(.horizontal, 8)
            .frame(height: scaled(22, pad: 24))
            .background(
                RoundedRectangle(cornerRadius: scaled(11, pad: 12), style: .continuous)
                    .stroke(NeumorphicColors.accent.opacity(0.82), lineWidth: 1)
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
        guard selectedResetMode == .resetStatusNextDay, isCustomResetTimeEnabled else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: customResetTimeOfDay)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        return hour * 60 + minute
    }

    private var countdownSummaryText: String {
        return L10n.tr(
            "When the countdown ends, you can choose to complete, abandon, or postpone.",
            zhHans: "倒计时结束后，你可以选择完成、放弃或延后。",
            zhHant: "倒計時結束後，你可以選擇完成、放棄或延後。",
            ja: "カウントダウン終了後、完了・放棄・延期を選べます。"
        )
    }

    private var customResetTimeSummaryText: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: customResetTimeOfDay)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        return L10n.tr(
            "Resets every day at \(String(format: "%02d:%02d", hour, minute)).",
            zhHans: "每天将在 \(String(format: "%02d:%02d", hour, minute)) 自动重置。",
            zhHant: "每天將在 \(String(format: "%02d:%02d", hour, minute)) 自動重置。",
            ja: "毎日 \(String(format: "%02d:%02d", hour, minute)) に自動リセットされます。"
        )
    }

    private func countdownNumberField(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .frame(maxWidth: .infinity, alignment: .center)

            TextField("0", value: value, formatter: Self.integerFormatter)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.appSystem(size: scaled(18, pad: 22), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(48, pad: 56))
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
                        .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
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

    private static func makeClockDate(from totalMinutes: Int) -> Date {
        let clamped = min(max(totalMinutes, 0), 23 * 60 + 59)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: clamped, to: start) ?? Date()
    }
}
