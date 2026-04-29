import SwiftUI
import Speech

struct EditTaskSheet: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var text: String
    @State var isForcedTask: Bool
    @State var residentWeekdays: Set<Int>
    @State var isOneTimeTask: Bool
    @State var startVisibleMonthText: String
    @State var startVisibleDayText: String
    let isCompletedTask: Bool
    let onSave: (String, Bool, Set<Int>, Bool, Int?, Int?, Int?) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @StateObject private var speechRecognizer = SpeechRecognizer()
    @FocusState private var focusedField: FocusField?
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @State private var isStartDatePickerPresented = false
    @State private var startDatePickerDate = Date()
    @State private var isDeleteConfirmationPresented = false
    @State private var blockedSaveToastMessage: String?
    @State private var hideBlockedSaveToastWorkItem: DispatchWorkItem?

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private enum FocusField: Hashable {
        case task
        case timerCustom
    }

    init(
        text: String,
        isForcedTask: Bool,
        residentWeekdays: Set<Int>,
        isOneTimeTask: Bool,
        startVisibleMonth: Int?,
        startVisibleDay: Int?,
        isCompletedTask: Bool,
        estimatedDurationMinutes: Int?,
        onSave: @escaping (String, Bool, Set<Int>, Bool, Int?, Int?, Int?) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _text = State(initialValue: text)
        _isForcedTask = State(initialValue: isForcedTask)
        _residentWeekdays = State(initialValue: residentWeekdays)
        _isOneTimeTask = State(initialValue: isOneTimeTask)
        _startVisibleMonthText = State(initialValue: startVisibleMonth.map(String.init) ?? "")
        _startVisibleDayText = State(initialValue: startVisibleDay.map(String.init) ?? "")
        self.isCompletedTask = isCompletedTask
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        let normalizedDuration = estimatedDurationMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }
        self.initialEstimatedDurationMinutes = normalizedDuration
        let presetCandidates = [15, 30, 45, 60]
        if let normalizedDuration, presetCandidates.contains(normalizedDuration) {
            _timerPresetMinutes = State(initialValue: normalizedDuration)
            _timerCustomMinutesText = State(initialValue: "")
        } else {
            _timerPresetMinutes = State(initialValue: nil)
            _timerCustomMinutesText = State(initialValue: normalizedDuration.map(String.init) ?? "")
        }
    }

    @State private var timerPresetMinutes: Int?
    @State private var timerCustomMinutesText: String
    private let initialEstimatedDurationMinutes: Int?

    private let screenOverlayColor = Color.black.opacity(0.80)
    private let fieldColor = Color(hex: "3F3F3F")
    private let fieldBorderColor = Color.clear
    private let primaryTextColor = Color.white
    private let secondaryTextColor = Color(hex: "828282")
    private let accentColor = Color(hex: "D3A375")
    private let baseVerticalOffset: CGFloat = 60
    private let collapsedExtraOffset: CGFloat = 30
    private let expandedCustomLiftOffset: CGFloat = -20
    private var contentColumnWidth: CGFloat { isPadLayout ? 420 : 313 }
    private var actionTitleFont: Font { .custom("Outfit", size: scaled(24, pad: 28)) }
    private var bodySFont: Font { .custom("Outfit", size: scaled(14, pad: 16)) }
    private var bodyLRegularFont: Font { .custom("Outfit", size: scaled(16, pad: 18)) }
    private var bodySLetterSpacing: CGFloat { -0.15 }
    private var bodyLLetterSpacing: CGFloat { -0.31 }
    private var sheetVerticalOffset: CGFloat {
        baseVerticalOffset + (repeatMode == .custom ? expandedCustomLiftOffset : collapsedExtraOffset)
    }
    private var normalizedTaskText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasTaskText: Bool {
        !normalizedTaskText.isEmpty
    }
    private var hasValidTaskLength: Bool {
        !normalizedTaskText.isEmpty
    }
    private var shouldShowCountdownCancelInline: Bool {
        normalizedEstimatedDurationMinutes != nil
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .blur(radius: 10)
                .ignoresSafeArea()

            screenOverlayColor
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    handleBackgroundTap()
                }

            VStack(spacing: 0) {
                headerBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        taskInputSection
                        startDateSection
                        forceCompletionSection
                        repeatSection
                        timerSection

                        saveButton
                    }
                    .frame(width: contentColumnWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 26)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .offset(y: sheetVerticalOffset)
            .animation(.easeInOut(duration: 0.22), value: repeatMode)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.done) {
                    focusedField = nil
                }
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(accentColor)
            }
        }
        .sheet(isPresented: $isStartDatePickerPresented) {
            startDatePickerSheet
        }
        .alert(L10n.deleteConfirmationTitle, isPresented: $isDeleteConfirmationPresented) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.deleteTask, role: .destructive) {
                onDelete()
            }
        } message: {
            Text(L10n.deleteTaskConfirmationMessage)
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.clear)
        .overlay(alignment: .bottom) {
            if let blockedSaveToastMessage {
                Text(blockedSaveToastMessage)
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.55))
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 34)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Button(role: .destructive) {
                focusedField = nil
                isDeleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: scaled(24, pad: 26), height: scaled(24, pad: 26))
            }
            .buttonStyle(.plain)
            .opacity(hasTaskText ? 1 : 0)
            .disabled(!hasTaskText)
            .padding(.leading, 10)

            Spacer(minLength: 12)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.88))
                    .frame(width: scaled(24, pad: 26), height: scaled(24, pad: 26))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .frame(width: contentColumnWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.top, isPadLayout ? 20 : 14)
        .padding(.bottom, 12)
    }

    private var taskInputSection: some View {
        sectionSurface {
            ZStack(alignment: .trailing) {
                ZStack(alignment: .leading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L10n.enterTaskForDay)
                            .font(bodyLRegularFont)
                            .kerning(bodyLLetterSpacing)
                            .foregroundColor(secondaryTextColor)
                            .padding(.leading, 12)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $text)
                        .font(bodyLRegularFont)
                        .kerning(bodyLLetterSpacing)
                        .foregroundColor(primaryTextColor)
                        .padding(.leading, 12)
                        .padding(.trailing, 12)
                        .padding(.trailing, isPadLayout ? 66 : 58)
                        .focused($focusedField, equals: .task)
                        .lineLimit(1)
                        .onChange(of: text) { _, newValue in
                            if newValue.count > BingoViewModel.maxTaskLength {
                                text = String(newValue.prefix(BingoViewModel.maxTaskLength))
                            }
                        }
                }
                .frame(height: scaled(80, pad: 92), alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(inputBackground(cornerRadius: 14))

                voiceInputButton
                    .padding(.trailing, 12)
            }

            if speechRecognizer.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(speechRecognizer.isRecording ? 1.2 : 0.8)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: speechRecognizer.isRecording)
                    Text(L10n.recording)
                        .font(bodySFont.weight(.medium))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.top, 10)
            }
        }
    }

    private var voiceInputButton: some View {
        Button {
            if isHapticsEnabled {
                AppHaptics.control()
            }
            if speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
            } else {
                speechRecognizer.startRecording { result in
                    text = result
                }
            }
        } label: {
            Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                .font(.appSystem(size: scaled(20, pad: 24), weight: .semibold))
                .foregroundColor(.white)
                .frame(width: scaled(36, pad: 44), height: scaled(36, pad: 44))
                .background(
                    Circle()
                        .fill(accentColor)
                )
        }
        .buttonStyle(.plain)
    }

    private var startDateSection: some View {
        sectionSurface {
            fieldHeader(
                icon: "calendar",
                title: L10n.tr(
                    "Start date (shows on the board at the selected time)",
                    zhHans: "开始日期(将会在设定的时间展示在棋盘上)",
                    zhHant: "開始日期(將會在設定的時間顯示在棋盤上)"
                )
            )

            Button {
                focusedField = nil
                startDatePickerDate = initialStartDate
                isStartDatePickerPresented = true
            } label: {
                HStack {
                    Text(startDateDisplayText)
                        .font(bodySFont.weight(.medium))
                        .kerning(bodySLetterSpacing)
                        .lineLimit(1)
                        .foregroundColor(hasStartDate ? Color.white : secondaryTextColor)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(height: scaled(48, pad: 56))
                .background(inputBackground(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var forceCompletionSection: some View {
        sectionSurface {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.88))

                Text(L10n.forceCompletion)
                    .font(bodySFont.weight(.medium))
                    .kerning(bodySLetterSpacing)
                    .foregroundColor(Color.white.opacity(0.96))

                Spacer(minLength: 0)

                Toggle("", isOn: $isForcedTask)
                    .labelsHidden()
                    .toggleStyle(DarkSheetToggleStyle(onTint: accentColor))
            }
            .padding(.horizontal, 16)
            .frame(height: scaled(36, pad: 44))
            .background(inputBackground(cornerRadius: 14))

            if isForcedTask {
                Text(
                    L10n.tr(
                        "Other tasks will be locked until this task is completed.",
                        zhHans: "其他任务将会变为锁定不可点击状态，直到此任务完成",
                        zhHant: "其他任務將會鎖定不可點擊，直到此任務完成"
                    )
                )
                .font(bodySFont.weight(.medium))
                .foregroundColor(secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }

    private var repeatSection: some View {
        sectionSurface {
            fieldHeader(icon: "repeat", title: L10n.residentDays)

            HStack(spacing: 8) {
                repeatModeButton(
                    title: L10n.tr("Always", zhHans: "始终", zhHant: "始終"),
                    isSelected: repeatMode == .always
                ) {
                    isOneTimeTask = false
                    residentWeekdays.removeAll()
                }

                repeatModeButton(
                    title: L10n.tr("Custom", zhHans: "自定义", zhHant: "自訂"),
                    isSelected: repeatMode == .custom
                ) {
                    if repeatMode == .always {
                        isOneTimeTask = false
                        residentWeekdays = [Calendar.current.component(.weekday, from: Date())]
                    }
                }
            }

            if repeatMode == .custom {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    selectionButton(
                        title: L10n.tr("Today", zhHans: "仅当天", zhHant: "僅當天"),
                        isSelected: isOneTimeTask
                    ) {
                        isOneTimeTask.toggle()
                        if isOneTimeTask {
                            residentWeekdays.removeAll()
                        }
                    }

                    ForEach(weekdayOptions, id: \.value) { option in
                        selectionButton(
                            title: option.label,
                            isSelected: residentWeekdays.contains(option.value)
                        ) {
                            if residentWeekdays.contains(option.value) {
                                residentWeekdays.remove(option.value)
                            } else {
                                residentWeekdays.insert(option.value)
                                isOneTimeTask = false
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var timerSection: some View {
        sectionSurface {
            HStack(spacing: 12) {
                fieldHeader(
                    icon: "clock",
                    title: L10n.tr("Set countdown (minutes)", zhHans: "设置倒计时（分钟）", zhHant: "設置倒計時（分鐘）")
                )

                if shouldShowCountdownCancelInline {
                    Button {
                        focusedField = nil
                        clearCountdownSelection()
                    } label: {
                        Text(L10n.cancel)
                            .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60], id: \.self) { minute in
                    presetMinuteButton(minute)
                }
            }

            TextField(
                L10n.tr(
                    "Custom input",
                    zhHans: "自定义输入",
                    zhHant: "自訂輸入"
                ),
                text: $timerCustomMinutesText
            )
            .keyboardType(.numberPad)
            .focused($focusedField, equals: .timerCustom)
            .font(bodyLRegularFont)
            .kerning(bodyLLetterSpacing)
            .foregroundColor(primaryTextColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(height: scaled(48, pad: 56))
            .background(inputBackground(cornerRadius: 14))
            .onChange(of: timerCustomMinutesText) { _, newValue in
                timerCustomMinutesText = String(newValue.filter(\.isNumber))
                if !timerCustomMinutesText.isEmpty {
                    timerPresetMinutes = nil
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            focusedField = nil
            DispatchQueue.main.async {
                saveTask()
            }
        } label: {
            Text(L10n.save)
                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(60, pad: 68))
                .background(
                    RoundedRectangle(cornerRadius: 100, style: .continuous)
                        .fill(accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasValidTaskLength)
        .opacity(hasValidTaskLength ? 1 : 0.5)
        .padding(.top, 8)
    }

    private func saveTask() {
        guard hasValidTaskLength else { return }
        if isCompletedTask, normalizedEstimatedDurationMinutes != nil {
            showBlockedSaveToast(L10n.completedTaskCountdownBlocked)
            return
        }
        let (month, day) = normalizedStartVisibleMonthDay
        onSave(text, isForcedTask, residentWeekdays, isOneTimeTask, normalizedEstimatedDurationMinutes, month, day)
    }

    private var hasPendingCountdownChange: Bool {
        normalizedEstimatedDurationMinutes != initialEstimatedDurationMinutes
    }

    private func clearCountdownSelection() {
        timerPresetMinutes = nil
        timerCustomMinutesText = ""
    }

    private func handleBackgroundTap() {
        focusedField = nil
        if hasPendingCountdownChange, normalizedEstimatedDurationMinutes != nil {
            clearCountdownSelection()
            return
        }
        onCancel()
    }

    private func showBlockedSaveToast(_ message: String) {
        hideBlockedSaveToastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            blockedSaveToastMessage = message
        }
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                blockedSaveToastMessage = nil
            }
        }
        hideBlockedSaveToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    private func sectionSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
    }

    private func inputBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fieldColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(fieldBorderColor, lineWidth: 1)
            )
    }

    private func fieldHeader(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .medium))
                .foregroundColor(Color.white.opacity(0.88))
                .frame(width: 16)

            Text(title)
                .font(bodySFont.weight(.medium))
                .kerning(bodySLetterSpacing)
                .foregroundColor(Color.white.opacity(0.96))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presetMinuteButton(_ minute: Int) -> some View {
        Button {
            timerPresetMinutes = minute
            timerCustomMinutesText = ""
            focusedField = nil
        } label: {
            Text("\(minute)")
                .font(bodySFont.weight(.medium))
                .kerning(bodySLetterSpacing)
                .foregroundColor(timerPresetMinutes == minute ? Color.white : Color.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(36, pad: 44))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(timerPresetMinutes == minute ? accentColor : fieldColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(fieldBorderColor, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var weekdayOptions: [(value: Int, label: String)] {
        [
            (2, L10n.mondayShort),
            (3, L10n.tuesdayShort),
            (4, L10n.wednesdayShort),
            (5, L10n.thursdayShort),
            (6, L10n.fridayShort),
            (7, L10n.saturdayShort),
            (1, L10n.sundayShort)
        ]
    }

    private enum RepeatMode {
        case always
        case custom
    }

    private var repeatMode: RepeatMode {
        (!isOneTimeTask && residentWeekdays.isEmpty) ? .always : .custom
    }

    private var hasStartDate: Bool {
        normalizedStartVisibleMonthDay.0 != nil && normalizedStartVisibleMonthDay.1 != nil
    }

    private var startDateDisplayText: String {
        if let month = normalizedStartVisibleMonthDay.0, let day = normalizedStartVisibleMonthDay.1 {
            return "\(month)/\(day)"
        }
        return L10n.tr(
            "Select date",
            zhHans: "选择日期",
            zhHant: "選擇日期"
        )
    }

    private var normalizedEstimatedDurationMinutes: Int? {
        if let timerPresetMinutes {
            return min(max(timerPresetMinutes, 1), BingoViewModel.maxCountdownMinutes)
        }
        guard let customMinutes = Int(timerCustomMinutesText), customMinutes > 0 else {
            return nil
        }
        return min(customMinutes, BingoViewModel.maxCountdownMinutes)
    }

    private var startDatePickerSheet: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button(L10n.done) {
                        isStartDatePickerPresented = false
                    }
                    .buttonStyle(.plain)
                    .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                DatePicker(
                    "",
                    selection: $startDatePickerDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.20, blue: 0.20))
                )
                .environment(\.colorScheme, .dark)
                .tint(accentColor)
                .padding(.horizontal, 12)
                .onChange(of: startDatePickerDate) { _, newDate in
                    let components = Calendar.current.dateComponents([.month, .day], from: newDate)
                    if let month = components.month, let day = components.day {
                        startVisibleMonthText = "\(month)"
                        startVisibleDayText = "\(day)"
                    }
                }

                Button(L10n.quickEditTaskNoStartDate) {
                    startVisibleMonthText = ""
                    startVisibleDayText = ""
                    isStartDatePickerPresented = false
                }
                .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.red.opacity(0.8))

                Spacer(minLength: 0)
            }
        }
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
        .preferredColorScheme(.dark)
    }

    private var initialStartDate: Date {
        if let month = normalizedStartVisibleMonthDay.0, let day = normalizedStartVisibleMonthDay.1 {
            var comps = Calendar.current.dateComponents([.year], from: Date())
            comps.month = month
            comps.day = day
            if let date = Calendar.current.date(from: comps) {
                return date
            }
        }
        return Date()
    }

    private var normalizedStartVisibleMonthDay: (Int?, Int?) {
        let monthText = startVisibleMonthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dayText = startVisibleDayText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !monthText.isEmpty || !dayText.isEmpty else {
            return (nil, nil)
        }

        guard let month = Int(monthText), let day = Int(dayText) else {
            return (nil, nil)
        }

        guard (1...12).contains(month), (1...31).contains(day) else {
            return (nil, nil)
        }

        var components = DateComponents()
        components.year = 2000
        components.month = month
        components.day = day
        guard Calendar.current.date(from: components) != nil else {
            return (nil, nil)
        }

        return (month, day)
    }

    private func taskTimerValuePicker<Content: View>(
        title: String,
        valueText: String,
        @ViewBuilder menuContent: () -> Content
    ) -> some View {
        Menu {
            menuContent()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: scaled(11, pad: 13), weight: .medium, design: .rounded))
                    .foregroundColor(secondaryTextColor)
                Text(valueText)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(inputBackground(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func selectionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(bodySFont.weight(.medium))
                .kerning(bodySLetterSpacing)
                .foregroundColor(isSelected ? Color.white : primaryTextColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(36, pad: 44))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? accentColor : fieldColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(fieldBorderColor, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func repeatModeButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(bodySFont.weight(.medium))
                .kerning(bodySLetterSpacing)
                .foregroundColor(isSelected ? Color.white : primaryTextColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(36, pad: 44))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? accentColor : fieldColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(fieldBorderColor, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

struct NeumorphicSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(NeumorphicColors.background)
                    .frame(width: 62, height: 34)
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.35), radius: 5, x: 3, y: 3)
                    .shadow(color: NeumorphicColors.lightShadow.opacity(0.85), radius: 5, x: -3, y: -3)

                Circle()
                    .fill(configuration.isOn ? NeumorphicColors.accent : NeumorphicColors.background)
                    .frame(width: 28, height: 28)
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.28), radius: 4, x: 2, y: 2)
                    .shadow(color: NeumorphicColors.lightShadow.opacity(0.85), radius: 4, x: -2, y: -2)
                    .overlay(
                        Image(systemName: configuration.isOn ? "exclamationmark" : "lock.open")
                            .font(.appSystem(size: 11, weight: .bold))
                            .foregroundColor(configuration.isOn ? .white : NeumorphicColors.text.opacity(0.65))
                    )
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

struct DarkSheetToggleStyle: ToggleStyle {
    let onTint: Color
    private let offTint = Color(hex: "CBCED4")

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(configuration.isOn ? onTint : offTint)
                    .frame(width: 32, height: 18)

                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .padding(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Speech Recognizer
class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: AppLanguage.speechLocaleIdentifier))

    func startRecording(onResult: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else { return }
                self?.beginRecording(onResult: onResult)
            }
        }
    }

    private func beginRecording(onResult: @escaping (String) -> Void) {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                DispatchQueue.main.async {
                    onResult(result.bestTranscription.formattedString)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self?.stopRecording()
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            return
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        DispatchQueue.main.async { self.isRecording = false }
    }
}
