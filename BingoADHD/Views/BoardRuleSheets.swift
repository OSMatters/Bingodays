import SwiftUI
import Foundation

struct SidebarGlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.interpolatingSpring(stiffness: 210, damping: 18)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? NeumorphicColors.accent.opacity(0.78) : Color.white.opacity(0.18))
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
                        zhHant: "取消後，面板倒計時會立即停止。"
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
        let summaryDays = totalMinutes / (24 * 60)
        let summaryHours = (totalMinutes % (24 * 60)) / 60
        let summaryMinutes = totalMinutes % 60
        return L10n.tr(
            "Board clears in \(summaryDays)d \(summaryHours)h \(summaryMinutes)m.",
            zhHans: "面板将在 \(summaryDays)天 \(summaryHours)小时 \(summaryMinutes)分钟后清空任务。",
            zhHant: "面板將在 \(summaryDays)天 \(summaryHours)小時 \(summaryMinutes)分鐘後清空任務。"
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
                                title: L10n.tr("Auto reset task status every other day", zhHans: "隔天自动重置任务状态", zhHant: "隔天自動重置任務狀態"),
                                hint: L10n.tr("Task status will reset to incomplete at 24:00.", zhHans: "将在24:00自动将任务状态重置为未完成", zhHant: "將在24:00自動將任務狀態重置為未完成")
                            )

                            if selectedResetMode == .resetStatusNextDay {
                                customResetTimeSection
                            }

                            resetOptionRow(
                                mode: .clearTasksNextDay,
                                title: L10n.tr("Auto clear all tiles every other day", zhHans: "隔天自动清空格子任务", zhHant: "隔天自動清空格子任務"),
                                hint: L10n.tr("All tile tasks will be cleared on the next day.", zhHans: "将在第二天自动清空所有格子任务", zhHant: "將在第二天自動清空所有格子任務")
                            )

                            resetOptionRow(
                                mode: .keepTaskStatus,
                                title: L10n.tr("Keep task status unchanged", zhHans: "保持任务状态不自动重置", zhHant: "保持任務狀態不自動重置"),
                                hint: L10n.tr("Tasks remain in their current state until you update them manually.", zhHans: "任务会保持当前状态，直到你手动修改。", zhHant: "任務會保持目前狀態，直到你手動修改。")
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
        let summaryDays = totalMinutes / (24 * 60)
        let summaryHours = (totalMinutes % (24 * 60)) / 60
        let summaryMinutes = totalMinutes % 60
        return L10n.tr(
            "Board clears in \(summaryDays)d \(summaryHours)h \(summaryMinutes)m.",
            zhHans: "面板将在 \(summaryDays)天 \(summaryHours)小时 \(summaryMinutes)分钟后清空任务。",
            zhHant: "面板將在 \(summaryDays)天 \(summaryHours)小時 \(summaryMinutes)分鐘後清空任務。"
        )
    }

    private var customResetTimeSummaryText: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: customResetTimeOfDay)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        return L10n.tr(
            "Resets every day at \(String(format: "%02d:%02d", hour, minute)).",
            zhHans: "每天将在 \(String(format: "%02d:%02d", hour, minute)) 自动重置。",
            zhHant: "每天將在 \(String(format: "%02d:%02d", hour, minute)) 自動重置。"
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
