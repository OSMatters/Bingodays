import SwiftUI

struct EditTaskSheet: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismissSheet
    @State var text: String
    @State var isForcedTask: Bool
    @State var residentWeekdays: Set<Int>
    @State var isOneTimeTask: Bool
    @State private var scheduleMode: TaskScheduleMode
    @State private var didExplicitlySelectScheduleMode = false
    private let wasLegacyUnspecifiedTask: Bool
    @State private var recurrenceKind: TaskRecurrenceRule.Kind
    @State private var recurrenceMonthDay: Int
    @State private var recurrenceDayInterval: Int
    @State private var recurrenceAnchorDate: Date
    @State var startVisibleAt: Date?
    @State var endVisibleAt: Date?
    @State var startReminderEnabled: Bool
    @State var startReminderOffsetMinutes: Int
    let isCompletedTask: Bool
    let usesClearPresentationBackground: Bool
    let completionHistoryCountProvider: (String) -> Int
    let diagnosticCellID: UUID?
    let diagnosticSource: String
    let onSave: (String, Bool, Set<Int>, Bool, TaskRecurrenceRule?, Int?, Date?, Date?, Bool, Int) -> Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    @StateObject private var speechRecognizer = SpeechRecognizer()
    @FocusState private var focusedField: FocusField?
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @State private var isDatePickerPresented = false
    @State private var pickerSelectionDate = Date()
    @State private var pickerMinimumDate = Date()
    @State private var isDeleteConfirmationPresented = false
    @State private var blockedSaveToastMessage: String?
    @State private var hideBlockedSaveToastWorkItem: DispatchWorkItem?
    @State private var activeDatePickerField: ActiveDatePickerField = .start
    @State private var isRecurrencePickerPresented = false
    @State private var activeRecurrencePickerField: ActiveRecurrencePickerField = .monthlyDay
    @State private var isTimeWindowExpanded: Bool
    @State private var activeSpeechInputSessionID: UUID?
    @State private var isApplyingSpeechTranscript = false
    @State private var didRequestInitialTaskFocus = false
    @State private var isClosingSheet = false

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private enum FocusField: Hashable {
        case task
    }

    private enum ActiveDatePickerField {
        case start
        case end
    }

    private enum ActiveRecurrencePickerField {
        case monthlyDay
        case everyNDays
    }

    private enum TaskScheduleMode: Equatable {
        case single
        case repeating
    }

    init(
        text: String,
        isForcedTask: Bool,
        residentWeekdays: Set<Int>,
        isOneTimeTask: Bool,
        recurrenceRule: TaskRecurrenceRule? = nil,
        startVisibleAt: Date?,
        endVisibleAt: Date?,
        startReminderEnabled: Bool = false,
        startReminderOffsetMinutes: Int = BingoCell.defaultStartReminderOffsetMinutes,
        isCompletedTask: Bool,
        estimatedDurationMinutes: Int?,
        usesClearPresentationBackground: Bool = false,
        completionHistoryCountProvider: @escaping (String) -> Int = { _ in 0 },
        diagnosticCellID: UUID? = nil,
        diagnosticSource: String = "task_editor",
        onSave: @escaping (String, Bool, Set<Int>, Bool, TaskRecurrenceRule?, Int?, Date?, Date?, Bool, Int) -> Bool,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        wasLegacyUnspecifiedTask = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            recurrenceRule == nil && residentWeekdays.isEmpty && !isOneTimeTask
        let recurrenceDefaultDate = recurrenceRule?.anchorDate ?? startVisibleAt ?? Date()
        let normalizedRecurrenceRule = recurrenceRule?.normalized(
            defaultWeekday: Calendar.current.component(.weekday, from: recurrenceDefaultDate),
            defaultMonthDay: Calendar.current.component(.day, from: recurrenceDefaultDate),
            defaultAnchorDate: recurrenceDefaultDate
        )
        let hasRepeatingSchedule = normalizedRecurrenceRule.map { $0.kind != .none } ?? !residentWeekdays.isEmpty
        let resolvedKind: TaskRecurrenceRule.Kind
        if hasRepeatingSchedule, let normalizedRecurrenceRule {
            resolvedKind = normalizedRecurrenceRule.kind
        } else if hasRepeatingSchedule {
            resolvedKind = .weekly
        } else {
            resolvedKind = .none
        }

        let isNewTask = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let initialScheduleMode: TaskScheduleMode = hasRepeatingSchedule || isNewTask
            ? .repeating
            : .single
        let initialRecurrenceKind: TaskRecurrenceRule.Kind = hasRepeatingSchedule
            ? resolvedKind
            : (isNewTask ? .daily : .none)

        _text = State(initialValue: text)
        _isForcedTask = State(initialValue: isForcedTask)
        _residentWeekdays = State(initialValue: normalizedRecurrenceRule?.kind == .weekly ? normalizedRecurrenceRule?.weekdays ?? residentWeekdays : residentWeekdays)
        _isOneTimeTask = State(initialValue: initialScheduleMode == .single)
        _scheduleMode = State(initialValue: initialScheduleMode)
        _recurrenceKind = State(initialValue: initialRecurrenceKind)
        _recurrenceMonthDay = State(initialValue: normalizedRecurrenceRule?.monthDay ?? Calendar.current.component(.day, from: recurrenceDefaultDate))
        _recurrenceDayInterval = State(initialValue: normalizedRecurrenceRule?.interval ?? TaskRecurrenceRule.defaultDayInterval)
        _recurrenceAnchorDate = State(initialValue: normalizedRecurrenceRule?.anchorDate ?? recurrenceDefaultDate)
        let resolvedStartVisibleAt = hasRepeatingSchedule ? nil : startVisibleAt
        let resolvedEndVisibleAt = hasRepeatingSchedule ? nil : endVisibleAt
        _startVisibleAt = State(initialValue: resolvedStartVisibleAt)
        _endVisibleAt = State(initialValue: resolvedEndVisibleAt)
        _startReminderEnabled = State(initialValue: startReminderEnabled && resolvedStartVisibleAt != nil && resolvedEndVisibleAt != nil && !isCompletedTask)
        _startReminderOffsetMinutes = State(initialValue: TaskStartReminderService.normalizedOffsetMinutes(startReminderOffsetMinutes))
        _isTimeWindowExpanded = State(initialValue: resolvedStartVisibleAt != nil || resolvedEndVisibleAt != nil)
        self.isCompletedTask = isCompletedTask
        self.usesClearPresentationBackground = usesClearPresentationBackground
        self.completionHistoryCountProvider = completionHistoryCountProvider
        self.diagnosticCellID = diagnosticCellID
        self.diagnosticSource = diagnosticSource
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        let normalizedDuration = estimatedDurationMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }
        self.initialStartVisibleAt = resolvedStartVisibleAt
        self.initialEndVisibleAt = resolvedEndVisibleAt
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
    private let initialStartVisibleAt: Date?
    private let initialEndVisibleAt: Date?

    private let sheetBackgroundColor = Color(hex: "202020")
    private let fieldColor = Color(hex: "3F3F3F")
    private let fieldBorderColor = Color.clear
    private let primaryTextColor = Color.white

    private var taskCompletionHistoryPreviewCount: Int? {
        let count = completionHistoryCountProvider(text)
        return TaskCompletionHistoryRuleEngine.shouldDisplayCompletionHistoryBadge(count: count)
            ? count
            : nil
    }
    private let secondaryTextColor = Color(hex: "828282")
    private var accentColor: Color { NeumorphicColors.modalAccent }
    private var contentColumnWidth: CGFloat { isPadLayout ? 420 : 313 }
    private var voiceInputButtonWidth: CGFloat {
        speechRecognizer.isRecording ? scaled(108, pad: 132) : scaled(36, pad: 44)
    }
    private var taskInputTrailingInset: CGFloat {
        voiceInputButtonWidth + scaled(22, pad: 26)
    }
    private var actionTitleFont: Font { .custom("Outfit", size: scaled(24, pad: 28)) }
    private var bodySFont: Font { .custom("Outfit", size: scaled(14, pad: 16)) }
    private var bodyLRegularFont: Font { .custom("Outfit", size: scaled(16, pad: 18)) }
    private var bodySLetterSpacing: CGFloat { -0.15 }
    private var bodyLLetterSpacing: CGFloat { -0.31 }
    private var fieldTitleLeadingInset: CGFloat { 26 }
    private var normalizedTaskText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasTaskText: Bool {
        !normalizedTaskText.isEmpty
    }
    private var hasValidTaskLength: Bool {
        !normalizedTaskText.isEmpty
    }
    private var taskTimeWindowTitle: String {
        L10n.tr(
            "Task start/end time",
            zhHans: "任务起止时间",
            zhHant: "任務起止時間",
            ja: "タスク開始/終了時刻"
        )
    }

    private var repeatingRuleNeedsAnchorDate: Bool {
        scheduleMode == .repeating && recurrenceKind == .everyNDays
    }
    private var activeDatePickerIncludesDate: Bool {
        scheduleMode == .single || (activeDatePickerField == .start && repeatingRuleNeedsAnchorDate)
    }
    private var activeStartFieldUsesDate: Bool {
        scheduleMode == .single || repeatingRuleNeedsAnchorDate
    }
    private var shouldValidateStartDateAgainstNow: Bool {
        scheduleMode == .single || repeatingRuleNeedsAnchorDate
    }
    private var shouldValidateEndDateAgainstNow: Bool {
        scheduleMode == .single
    }
    private var canConfigureCountdown: Bool {
        scheduleMode == .single && !hasConfiguredTimeWindow
    }
    private var countdownMinutesForSave: Int? {
        canConfigureCountdown ? normalizedEstimatedDurationMinutes : nil
    }
    private var hasConfiguredTimeWindow: Bool {
        startVisibleAt != nil || endVisibleAt != nil
    }
    private var shouldShowRepeatPreviewUnderTimeWindow: Bool {
        scheduleMode == .repeating && hasConfiguredTimeWindow
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView(showsIndicators: false) {
                formSections
                    .padding(.top, 8)
                    .padding(.bottom, scaled(22, pad: 28))
            }
            .scrollDismissesKeyboard(.interactively)
            .background(
                sheetBackgroundColor
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
            )
        }
        .background(
            sheetBackgroundColor
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButtonDock
        }
        .overlay(alignment: .bottom) {
            if let blockedSaveToastMessage {
                IOSNativeToastView(
                    blockedSaveToastMessage,
                    isPadLayout: isPadLayout
                )
                .padding(.horizontal, 18)
                .padding(.bottom, blockedSaveToastBottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $isDatePickerPresented) {
            datePickerSheet
        }
        .sheet(isPresented: $isRecurrencePickerPresented) {
            recurrencePickerSheet
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
        .presentationBackground(usesClearPresentationBackground ? Color.clear : sheetBackgroundColor)
        .onChange(of: speechRecognizer.isRecording) { _, isRecording in
            if !isRecording {
                activeSpeechInputSessionID = nil
            }
        }
        .onChange(of: startVisibleAt) { _, newValue in
            if newValue == nil {
                startReminderEnabled = false
            }
            reconcileCountdownAvailability()
        }
        .onChange(of: endVisibleAt) { _, newValue in
            if newValue == nil {
                startReminderEnabled = false
            }
        }
        .onChange(of: scheduleMode) { _, _ in
            reconcileCountdownAvailability()
        }
        .onAppear {
            requestInitialTaskFocusIfNeeded()
        }
    }

    private var formSections: some View {
        VStack(spacing: 24) {
            taskInputSection
            scheduleModeSection
            if scheduleMode == .repeating {
                repeatSection
            } else {
                timeWindowSection
            }
            forceCompletionSection
        }
        .frame(width: contentColumnWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var headerBar: some View {
        HStack {
            Button(role: .destructive) {
                dismissKeyboard()
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
                closeSheet()
            } label: {
                Image(systemName: "xmark")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.88))
                    .frame(width: scaled(44, pad: 48), height: scaled(44, pad: 48))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: contentColumnWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.top, isPadLayout ? 20 : 14)
        .padding(.bottom, isPadLayout ? 28 : 24)
    }

    private var taskInputSection: some View {
        sectionSurface {
            fieldHeader(
                icon: "square.and.pencil",
                title: L10n.tr("Task", zhHans: "任务", zhHant: "任務", ja: "タスク"),
                isRequired: true
            )

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
                        .submitLabel(.done)
                        .padding(.leading, 12)
                        .padding(.trailing, 12)
                        .padding(.trailing, taskInputTrailingInset)
                        .focused($focusedField, equals: .task)
                        .lineLimit(1)
                        .onChange(of: text) { _, newValue in
                            if newValue.count > BingoViewModel.maxTaskLength {
                                text = String(newValue.prefix(BingoViewModel.maxTaskLength))
                                if speechRecognizer.isRecording && !isApplyingSpeechTranscript {
                                    activeSpeechInputSessionID = nil
                                    speechRecognizer.stopRecording()
                                }
                                return
                            }

                            if speechRecognizer.isRecording && !isApplyingSpeechTranscript {
                                activeSpeechInputSessionID = nil
                                speechRecognizer.stopRecording()
                            }
                        }
                }
                .frame(height: scaled(80, pad: 92), alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(inputBackground(cornerRadius: 14))

                voiceInputButton
                    .padding(.trailing, 12)
            }

            if let taskCompletionHistoryPreviewCount {
                Label(L10n.taskCompletionHistoryPreview(taskCompletionHistoryPreviewCount), systemImage: "clock.arrow.circlepath")
                    .font(bodySFont.weight(.medium))
                    .foregroundColor(accentColor.opacity(0.92))
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
            dismissKeyboard()
            if isHapticsEnabled {
                AppHaptics.control()
            }
            if speechRecognizer.isRecording {
                activeSpeechInputSessionID = nil
                speechRecognizer.stopRecording()
            } else {
                let sessionID = UUID()
                activeSpeechInputSessionID = sessionID
                speechRecognizer.startRecording { result in
                    applySpeechTranscript(result, sessionID: sessionID)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic")
                    .font(.appSystem(size: scaled(20, pad: 24), weight: .semibold))

                if speechRecognizer.isRecording {
                    Text(L10n.stopRecording)
                        .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .foregroundColor(.white)
            .frame(width: voiceInputButtonWidth, height: scaled(36, pad: 44))
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speechRecognizer.isRecording ? L10n.stopRecording : L10n.voiceInput)
    }

    private func applySpeechTranscript(_ transcript: String, sessionID: UUID) {
        guard activeSpeechInputSessionID == sessionID else { return }
        let normalizedTranscript = String(transcript.prefix(BingoViewModel.maxTaskLength))
        guard !normalizedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isApplyingSpeechTranscript = true
        text = normalizedTranscript
        DispatchQueue.main.async {
            isApplyingSpeechTranscript = false
        }
    }

    private var scheduleModeSection: some View {
        sectionSurface {
            fieldHeader(
                icon: "calendar.badge.clock",
                title: L10n.tr(
                    "Task rule",
                    zhHans: "任务规则",
                    zhHant: "任務規則",
                    ja: "タスクルール"
                ),
                isRequired: true
            )

            HStack(spacing: 8) {
                selectionButton(
                    title: L10n.tr("Repeat", zhHans: "重复", zhHant: "重複", ja: "繰り返し"),
                    isSelected: scheduleMode == .repeating
                ) {
                    selectScheduleMode(.repeating)
                }

                selectionButton(
                    title: L10n.tr("Single", zhHans: "单次", zhHant: "單次", ja: "単発"),
                    isSelected: scheduleMode == .single
                ) {
                    selectScheduleMode(.single)
                }
            }

            if scheduleMode == .single {
                Text(
                    L10n.tr(
                        "After the daily reset, completed tasks leave the board and unfinished tasks remain.",
                        zhHans: "次日格子重置后，已完成任务移出棋盘，未完成任务将保留。",
                        zhHant: "隔日格子重置後，已完成任務會移出棋盤，未完成任務會保留。",
                        ja: "翌日のタスクのリセット後、完了したタスクはボードから外れ、未完了のタスクは残ります。"
                    )
                )
                .font(bodySFont.weight(.medium))
                .foregroundColor(secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var timeWindowSection: some View {
        sectionSurface {
            expandableOptionHeader(
                icon: "calendar",
                title: taskTimeWindowTitle,
                isSelected: isTimeWindowExpanded,
                isRequired: false
            ) {
                toggleTimeWindowExpansion()
            }

            if isTimeWindowExpanded {
                HStack(alignment: .top, spacing: 12) {
                    timeValueButton(
                        text: startDateDisplayText,
                        isConfigured: hasStartDate
                    ) {
                        dismissKeyboard()
                        activeDatePickerField = .start
                        prepareDatePicker(for: .start, preferredDate: startVisibleAt ?? Date())
                        isDatePickerPresented = true
                    }

                    timeValueButton(
                        text: endDateDisplayText,
                        isConfigured: endVisibleAt != nil
                    ) {
                        dismissKeyboard()
                        activeDatePickerField = .end
                        prepareDatePicker(for: .end, preferredDate: endVisibleAt ?? startVisibleAt ?? Date())
                        isDatePickerPresented = true
                    }
                }

                if let timeWindowSupportingText {
                    Text(timeWindowSupportingText)
                        .font(bodySFont.weight(.medium))
                        .foregroundColor(secondaryTextColor)
                        .padding(.leading, fieldTitleLeadingInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if canUseStartReminder {
                    startReminderControls
                        .transition(.opacity)
                }
            }
        }
    }

    private var startReminderControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: startReminderEnabled ? "bell.fill" : "bell")
                    .font(.appSystem(size: scaled(17, pad: 19), weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.88))
                    .frame(width: 18)

                Text(L10n.tr("Start reminder", zhHans: "开始前提醒", zhHant: "開始前提醒", ja: "開始前の通知"))
                    .font(bodySFont.weight(.medium))
                    .kerning(bodySLetterSpacing)
                    .foregroundColor(Color.white.opacity(0.96))

                Spacer(minLength: 0)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { startReminderEnabled },
                        set: { handleStartReminderToggle($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(DarkSheetToggleStyle(onTint: accentColor))
            }
            .frame(height: scaled(34, pad: 42))

            if startReminderEnabled {
                HStack(spacing: 8) {
                    ForEach(TaskStartReminderService.allowedOffsetMinutes, id: \.self) { minutes in
                        reminderOffsetButton(minutes)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: startReminderEnabled)
    }

    private var forceCompletionSection: some View {
        sectionSurface {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.88))
                    .frame(width: 16)

                Text(L10n.forceCompletion)
                    .font(bodySFont.weight(.medium))
                    .kerning(bodySLetterSpacing)
                    .foregroundColor(Color.white.opacity(0.96))

                Spacer(minLength: 0)

                Toggle("", isOn: $isForcedTask)
                    .onChange(of: isForcedTask) { _, _ in
                        dismissKeyboard()
                    }
                    .labelsHidden()
                    .toggleStyle(DarkSheetToggleStyle(onTint: accentColor))
            }
            .frame(height: scaled(36, pad: 44))

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
                .padding(.leading, fieldTitleLeadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }

    private var repeatSection: some View {
        sectionSurface {
            fieldHeader(icon: "repeat", title: repeatRuleTitle, isRequired: true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(recurrenceKindOptions, id: \.kind) { option in
                    selectionButton(
                        title: option.title,
                        isSelected: recurrenceKind == option.kind
                    ) {
                        selectRecurrenceKind(option.kind)
                    }
                }
            }

            if recurrenceKind == .weekly {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(weekdayOptions, id: \.value) { option in
                        selectionButton(
                            title: option.label,
                            isSelected: residentWeekdays.contains(option.value)
                        ) {
                            if residentWeekdays.contains(option.value) {
                                residentWeekdays.remove(option.value)
                            } else {
                                residentWeekdays.insert(option.value)
                            }
                            ensureWeeklyRecurrenceHasAWeekday()
                        }
                    }
                }
                .padding(.top, 2)
            } else if recurrenceKind == .monthlyDay {
                HStack(spacing: 8) {
                    recurrenceValueButton(
                        title: L10n.tr("Monthly day", zhHans: "每月日期", zhHant: "每月日期", ja: "毎月の日付"),
                        valueText: monthlyDayValueText
                    ) {
                        activeRecurrencePickerField = .monthlyDay
                        isRecurrencePickerPresented = true
                    }
                }
                .padding(.top, 2)
            } else if recurrenceKind == .everyNDays {
                HStack(spacing: 8) {
                    recurrenceValueButton(
                        title: L10n.tr("Interval", zhHans: "间隔", zhHant: "間隔", ja: "間隔"),
                        valueText: everyNDaysValueText
                    ) {
                        activeRecurrencePickerField = .everyNDays
                        isRecurrencePickerPresented = true
                    }
                }
                .padding(.top, 2)
            }

            if let repeatPreviewBelowRepeatRuleText {
                Text(repeatPreviewBelowRepeatRuleText)
                    .font(bodySFont.weight(.medium))
                    .foregroundColor(secondaryTextColor)
                    .padding(.leading, fieldTitleLeadingInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    private var saveButton: some View {
        Button {
            dismissKeyboard()
            DispatchQueue.main.async {
                saveTask()
            }
        } label: {
            Text(L10n.save)
                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: saveButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: 100, style: .continuous)
                        .fill(accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasValidTaskLength)
        .opacity(hasValidTaskLength ? 1 : 0.5)
        .shadow(color: accentColor.opacity(0.28), radius: 16, x: 0, y: 8)
    }

    private var saveButtonHeight: CGFloat {
        scaled(60, pad: 68)
    }

    private var saveButtonDock: some View {
        VStack(spacing: 0) {
            saveButton
                .frame(width: contentColumnWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, scaled(10, pad: 12))
                .padding(.bottom, scaled(12, pad: 16))
        }
        .background(sheetBackgroundColor.ignoresSafeArea(edges: .bottom))
    }

    private var blockedSaveToastBottomPadding: CGFloat {
        saveButtonHeight + scaled(34, pad: 42)
    }

    private func saveTask() {
        guard hasValidTaskLength else { return }
        let saveStartVisibleAt = scheduleMode == .repeating ? nil : startVisibleAt
        let saveEndVisibleAt = scheduleMode == .repeating ? nil : endVisibleAtForSave()
        let saveEstimatedDurationMinutes = countdownMinutesForSave
        if isCompletedTask, saveEstimatedDurationMinutes != nil {
            showBlockedSaveToast(L10n.completedTaskCountdownBlocked)
            return
        }
        if isCompletedTask,
           saveStartVisibleAt != initialStartVisibleAt || saveEndVisibleAt != initialEndVisibleAt {
            showBlockedSaveToast(
                L10n.tr(
                    "Completed tasks can't change start or end time.",
                    zhHans: "已完成任务不可修改开始或结束时间。",
                    zhHant: "已完成任務不可修改開始或結束時間。",
                    ja: "完了済みタスクの開始時刻や終了時刻は変更できません。"
                )
            )
            return
        }
        if shouldValidateStartDateAgainstNow,
           !TaskTimeWindowValidationRules.isStartTimeAllowed(
               saveStartVisibleAt,
               now: minimumSelectableDate
           ) {
            showBlockedSaveToast(
                L10n.tr(
                    "Start time can't be in the past.",
                    zhHans: "开始时间不能早于当前时间。",
                    zhHant: "開始時間不能早於目前時間。",
                    ja: "開始時刻は現在時刻より前にできません。"
                )
            )
            return
        }
        if let saveStartVisibleAt, let saveEndVisibleAt, saveEndVisibleAt <= saveStartVisibleAt {
            showBlockedSaveToast(
                L10n.tr(
                    "End time must be later than start time.",
                    zhHans: "结束时间必须晚于开始时间。",
                    zhHant: "結束時間必須晚於開始時間。",
                    ja: "終了時刻は開始時刻より後にしてください。"
                )
            )
            return
        }
        if let saveEstimatedDurationMinutes,
           let saveStartVisibleAt,
           let saveEndVisibleAt,
           Double(saveEstimatedDurationMinutes * 60) > saveEndVisibleAt.timeIntervalSince(saveStartVisibleAt) {
            showBlockedSaveToast(
                L10n.tr(
                    "Countdown is longer than the task time window. Shorten the countdown or extend the end time.",
                    zhHans: "倒计时时长超过任务起止时间，请缩短倒计时或延长结束时间。",
                    zhHant: "倒計時長度超過任務起止時間，請縮短倒計時或延長結束時間。",
                    ja: "カウントダウンがタスク時間を超えています。短くするか終了時刻を延ばしてください。"
                )
            )
            return
        }
        if shouldValidateEndDateAgainstNow,
           !TaskTimeWindowValidationRules.isEndTimeAllowed(
               saveEndVisibleAt,
               now: minimumSelectableDateForActiveField(.end)
           ) {
            showBlockedSaveToast(
                L10n.tr(
                    "End time can't be in the past.",
                    zhHans: "结束时间不能早于当前时间。",
                    zhHant: "結束時間不能早於目前時間。",
                    ja: "終了時刻は現在時刻より前にできません。"
                )
            )
            return
        }
        let resolvedStartReminderEnabled = canUseStartReminder && startReminderEnabled
        if resolvedStartReminderEnabled, shouldValidateStartDateAgainstNow, let saveStartVisibleAt {
            let reminderDate = saveStartVisibleAt.addingTimeInterval(Double(-startReminderOffsetMinutes * 60))
            if reminderDate <= Date() {
                showBlockedSaveToast(
                    L10n.tr(
                        "Reminder time has already passed.",
                        zhHans: "提醒时间已过，请选择更短的提前时间。",
                        zhHant: "提醒時間已過，請選擇更短的提前時間。",
                        ja: "通知時刻はすでに過ぎています。もっと短い事前通知を選んでください。"
                    )
                )
                return
            }
        }
        let recurrenceRule = recurrenceRuleForSave()
        let legacyResidentWeekdays = recurrenceRule?.kind == .weekly ? recurrenceRule?.weekdays ?? [] : []
        let legacyIsOneTimeTask = recurrenceRule == nil && (saveStartVisibleAt != nil || saveEndVisibleAt != nil)
        let diagnosticDetails = [
            "operation_id": UUID().uuidString,
            "source": diagnosticSource,
            "cell_id": diagnosticCellID?.uuidString ?? "new",
            "selected_mode": scheduleMode == .repeating ? "repeating" : "single",
            "selected_kind": recurrenceKind.rawValue,
            "submitted_rule": recurrenceRule?.kind.rawValue ?? "single"
        ]
        DiagnosticLogStore.recordUserAction("task_rule.editor_submitted", details: diagnosticDetails)
        let didSave = onSave(
            text,
            isForcedTask,
            legacyResidentWeekdays,
            legacyIsOneTimeTask,
            recurrenceRule,
            saveEstimatedDurationMinutes,
            saveStartVisibleAt,
            saveEndVisibleAt,
            resolvedStartReminderEnabled,
            startReminderOffsetMinutes
        )
        DiagnosticLogStore.recordStateChange("task_rule.editor_save_result", details:
            diagnosticDetails.merging(["accepted": String(didSave)]) { current, _ in current })
        if !didSave {
            showBlockedSaveToast(L10n.tr(
                "Couldn't save. Your changes are still here. Please try again.",
                zhHans: "保存未成功，已保留编辑内容，请重试。",
                zhHant: "儲存未成功，已保留編輯內容，請重試。",
                ja: "保存できませんでした。入力内容は保持されています。もう一度お試しください。"
            ))
        }
    }

    private func clearCountdownSelection() {
        timerPresetMinutes = nil
        timerCustomMinutesText = ""
    }

    private func reconcileCountdownAvailability() {
        guard !canConfigureCountdown else { return }
        clearCountdownSelection()
    }

    private func toggleTimeWindowExpansion() {
        dismissKeyboard()
        guard !repeatingRuleNeedsAnchorDate else {
            isTimeWindowExpanded = true
            return
        }
        if isTimeWindowExpanded {
            startVisibleAt = nil
            endVisibleAt = nil
            startReminderEnabled = false
            isTimeWindowExpanded = false
        } else {
            isTimeWindowExpanded = true
        }
    }

    private func requestInitialTaskFocusIfNeeded() {
        guard !didRequestInitialTaskFocus else { return }
        didRequestInitialTaskFocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            guard !isClosingSheet else { return }
            focusedField = .task
        }
    }

    private func closeSheet() {
        isClosingSheet = true
        dismissKeyboard()
        onCancel()
        dismissSheet()
    }

    private func dismissKeyboard() {
        focusedField = nil
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

    private func lightOptionBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
    }

    private func fieldHeader(icon: String, title: String, isRequired: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .medium))
                .foregroundColor(Color.white.opacity(0.88))
                .frame(width: 16)

            Text(title)
                .font(bodySFont.weight(.medium))
                .kerning(bodySLetterSpacing)
                .foregroundColor(Color.white.opacity(0.96))

            if isRequired {
                requiredBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var requiredBadge: some View {
        Text(L10n.tr("Required", zhHans: "必填", zhHant: "必填", ja: "必須"))
            .font(.appSystem(size: scaled(10, pad: 11), weight: .bold, design: .rounded))
            .foregroundColor(accentColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.14))
            )
    }

    private func expandableOptionHeader(
        icon: String,
        title: String,
        isSelected: Bool,
        isRequired: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .medium))
                    .foregroundColor(Color.white.opacity(0.88))
                    .frame(width: 16)

                HStack(spacing: 8) {
                    Text(title)
                        .font(bodySFont.weight(.medium))
                        .kerning(bodySLetterSpacing)
                        .foregroundColor(Color.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if isRequired {
                        requiredBadge
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .bold))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(minHeight: scaled(44, pad: 52), alignment: .center)
        }
        .buttonStyle(.plain)
    }

    private func timeFieldColumn(
        icon: String,
        title: String,
        text: String,
        isConfigured: Bool,
        isRequired: Bool = false,
        inputTopInset: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldHeader(icon: icon, title: title, isRequired: isRequired)

            Button(action: action) {
                HStack {
                    Text(text)
                        .font(bodySFont.weight(.medium))
                        .kerning(bodySLetterSpacing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(isConfigured ? Color.white : secondaryTextColor)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(height: scaled(56, pad: 64), alignment: .leading)
                .background(inputBackground(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, inputTopInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeValueButton(
        text: String,
        isConfigured: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(bodySFont.weight(.medium))
                    .kerning(bodySLetterSpacing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(isConfigured ? Color.white : secondaryTextColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(height: scaled(56, pad: 64), alignment: .leading)
            .background(lightOptionBackground(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderOffsetButton(_ minutes: Int) -> some View {
        Button {
            dismissKeyboard()
            startReminderOffsetMinutes = TaskStartReminderService.normalizedOffsetMinutes(minutes)
        } label: {
            Text(TaskStartReminderService.offsetTitle(minutes: minutes))
                .font(.appSystem(size: scaled(11, pad: 13), weight: .semibold, design: .rounded))
                .foregroundColor(startReminderOffsetMinutes == minutes ? Color.white : Color.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity)
                .frame(height: scaled(32, pad: 38))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(startReminderOffsetMinutes == minutes ? accentColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func handleStartReminderToggle(_ enabled: Bool) {
        dismissKeyboard()
        guard enabled else {
            startReminderEnabled = false
            return
        }
        guard startVisibleAt != nil else {
            startReminderEnabled = false
            showBlockedSaveToast(
                L10n.tr(
                    "Select a start time first.",
                    zhHans: "请先选择开始时间。",
                    zhHant: "請先選擇開始時間。"
                )
            )
            return
        }

        Task {
            let granted = await TaskStartReminderService.requestAuthorizationIfNeeded()
            await MainActor.run {
                if granted {
                    startReminderEnabled = true
                } else {
                    startReminderEnabled = false
                    showBlockedSaveToast(
                        L10n.tr(
                            "Notifications are disabled.",
                            zhHans: "系统通知未开启，请在设置中允许通知。",
                            zhHant: "系統通知未開啟，請在設定中允許通知。"
                        )
                    )
                }
            }
        }
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

    private var recurrenceKindOptions: [(kind: TaskRecurrenceRule.Kind, title: String)] {
        [
            (.daily, L10n.tr("Daily", zhHans: "每天", zhHant: "每天", ja: "毎日")),
            (.weekly, L10n.tr("Weekly", zhHans: "每周", zhHant: "每週", ja: "毎週")),
            (.monthlyDay, L10n.tr("Monthly", zhHans: "每月", zhHant: "每月", ja: "毎月")),
            (.everyNDays, L10n.tr("Every few days", zhHans: "每隔几天", zhHant: "每隔幾天", ja: "数日ごと"))
        ]
    }

    private var repeatRuleTitle: String {
        L10n.tr(
            "Repeat rule",
            zhHans: "重复规则",
            zhHant: "重複規則",
            ja: "繰り返しルール"
        )
    }

    private var monthlyDayValueText: String {
        L10n.tr(
            "Day \(recurrenceMonthDay) each month",
            zhHans: "每月第 \(recurrenceMonthDay) 天",
            zhHant: "每月第 \(recurrenceMonthDay) 天",
            ja: "毎月\(recurrenceMonthDay)日"
        )
    }

    private var everyNDaysValueText: String {
        L10n.tr(
            "Every \(recurrenceDayInterval) days",
            zhHans: "每隔 \(recurrenceDayInterval) 天",
            zhHant: "每隔 \(recurrenceDayInterval) 天",
            ja: "\(recurrenceDayInterval)日ごと"
        )
    }

    private func monthlyDayMenuTitle(_ day: Int) -> String {
        L10n.tr("Day \(day)", zhHans: "第 \(day) 天", zhHant: "第 \(day) 天", ja: "\(day)日")
    }

    private func everyNDaysMenuTitle(_ interval: Int) -> String {
        L10n.tr("Every \(interval) days", zhHans: "每隔 \(interval) 天", zhHant: "每隔 \(interval) 天", ja: "\(interval)日ごと")
    }

    private func selectScheduleMode(_ mode: TaskScheduleMode) {
        dismissKeyboard()
        didExplicitlySelectScheduleMode = true
        scheduleMode = mode
        switch mode {
        case .single:
            recurrenceKind = .none
            isOneTimeTask = startVisibleAt != nil || endVisibleAt != nil
            residentWeekdays.removeAll()
        case .repeating:
            isOneTimeTask = false
            startVisibleAt = nil
            endVisibleAt = nil
            startReminderEnabled = false
            isTimeWindowExpanded = false
            clearCountdownSelection()
            if recurrenceKind == .none {
                recurrenceKind = .daily
            }
            if recurrenceKind == .weekly {
                ensureWeeklyRecurrenceHasAWeekday()
            }
        }
    }

    private func selectRecurrenceKind(_ kind: TaskRecurrenceRule.Kind) {
        dismissKeyboard()
        let previousKind = recurrenceKind
        scheduleMode = .repeating
        recurrenceKind = kind
        startVisibleAt = nil
        endVisibleAt = nil
        startReminderEnabled = false
        isTimeWindowExpanded = false
        clearCountdownSelection()
        switch kind {
        case .none:
            isOneTimeTask = true
            residentWeekdays.removeAll()
        case .daily:
            isOneTimeTask = false
            residentWeekdays.removeAll()
        case .weekly:
            isOneTimeTask = false
            ensureWeeklyRecurrenceHasAWeekday()
        case .monthlyDay:
            isOneTimeTask = false
            residentWeekdays.removeAll()
            recurrenceMonthDay = min(max(recurrenceMonthDay, 1), 31)
        case .everyNDays:
            isOneTimeTask = false
            residentWeekdays.removeAll()
            recurrenceDayInterval = min(max(recurrenceDayInterval, 2), TaskRecurrenceRule.maxDayInterval)
            if previousKind != .everyNDays {
                recurrenceAnchorDate = Date()
            }
        }
    }

    private func ensureWeeklyRecurrenceHasAWeekday() {
        let normalizedWeekdays = Set(residentWeekdays.filter { (1...7).contains($0) })
        if normalizedWeekdays.isEmpty {
            residentWeekdays = [Calendar.current.component(.weekday, from: Date())]
        } else {
            residentWeekdays = normalizedWeekdays
        }
    }

    private func recurrenceRuleForSave() -> TaskRecurrenceRule? {
        guard scheduleMode == .repeating else {
            if wasLegacyUnspecifiedTask && !didExplicitlySelectScheduleMode &&
                startVisibleAt == initialStartVisibleAt && endVisibleAt == initialEndVisibleAt {
                return nil
            }
            return TaskRecurrenceRule(kind: .none)
        }
        return recurrenceRuleForCurrentRepeatingDraft(defaultDate: recurrenceAnchorDate)
    }

    private func recurrenceRuleForCurrentRepeatingDraft(defaultDate: Date) -> TaskRecurrenceRule {
        let defaultWeekday = Calendar.current.component(.weekday, from: defaultDate)
        let defaultMonthDay = Calendar.current.component(.day, from: defaultDate)
        let normalizedKind = recurrenceKind == .none ? TaskRecurrenceRule.Kind.daily : recurrenceKind

        let rule: TaskRecurrenceRule
        switch normalizedKind {
        case .daily:
            rule = TaskRecurrenceRule(kind: .daily)
        case .weekly:
            rule = TaskRecurrenceRule(kind: .weekly, weekdays: residentWeekdays)
        case .monthlyDay:
            rule = TaskRecurrenceRule(kind: .monthlyDay, monthDay: recurrenceMonthDay)
        case .everyNDays:
            rule = TaskRecurrenceRule(kind: .everyNDays, interval: recurrenceDayInterval, anchorDate: defaultDate)
        case .none:
            rule = TaskRecurrenceRule(kind: .daily)
        }

        return rule.normalized(
            defaultWeekday: defaultWeekday,
            defaultMonthDay: defaultMonthDay,
            defaultAnchorDate: defaultDate
        )
    }

    private var hasStartDate: Bool {
        startVisibleAt != nil
    }

    private var canUseStartReminder: Bool {
        hasStartDate && hasEndDate && !isCompletedTask
    }

    private var hasEndDate: Bool {
        endVisibleAt != nil
    }

    private var startTimeFieldTitle: String {
        L10n.tr("Start time", zhHans: "开始时间", zhHant: "開始時間", ja: "開始時刻")
    }

    private var endTimeFieldTitle: String {
        switch scheduleMode {
        case .single:
            return L10n.tr("End time", zhHans: "结束时间", zhHant: "結束時間", ja: "終了時刻")
        case .repeating:
            return L10n.tr(
                "End time",
                zhHans: "结束时间",
                zhHant: "結束時間",
                ja: "終了時刻"
            )
        }
    }

    private var timeWindowHintText: String {
        if let concreteHint = concreteTimeWindowHintText {
            return concreteHint
        }
        switch scheduleMode {
        case .single:
            return L10n.tr(
                "Tasks show at the start time and end at the end time.",
                zhHans: "任务会在开始时间显示，在结束时间结束。",
                zhHant: "任務會在開始時間顯示，在結束時間結束。",
                ja: "タスクは開始時刻に表示され、終了時刻に終了します。"
            )
        case .repeating:
            if repeatingRuleNeedsAnchorDate {
                return L10n.tr(
                    "The start date is when the interval begins. The task appears every N days and can be completed during this time window.",
                    zhHans: "起算日期用于计算间隔；任务会每隔 N 天出现一次，并在所选时段内可完成。",
                    zhHant: "起算日期用於計算間隔；任務會每隔 N 天出現一次，並在所選時段內可完成。",
                    ja: "開始日は間隔計算の基準です。タスクはN日ごとに表示され、この時間帯に完了できます。"
                )
            }
            return L10n.tr(
                "The repeat rule chooses the dates. Set the time window for each occurrence here.",
                zhHans: "重复规则决定显示日期，这里只设置每次可完成的时间段。",
                zhHant: "重複規則決定顯示日期，這裡只設定每次可完成的時間段。",
                ja: "表示日は繰り返しルールで決まります。ここでは各回で完了できる時間帯だけを設定します。"
            )
        }
    }

    private var timeWindowSupportingText: String? {
        if shouldShowRepeatPreviewUnderTimeWindow {
            return repeatPreviewText
        }
        guard scheduleMode == .single else {
            return nil
        }
        return timeWindowHintText
    }

    private var repeatPreviewBelowRepeatRuleText: String? {
        guard !shouldShowRepeatPreviewUnderTimeWindow else {
            return nil
        }
        return repeatPreviewText
    }

    private var concreteTimeWindowHintText: String? {
        switch (startVisibleAt, endVisibleAt) {
        case let (start?, end?):
            return L10n.tr(
                "The task shows at \(timeSummaryText(start, isStart: true)) and ends at \(timeSummaryText(end, isStart: false)).",
                zhHans: "任务会在 \(timeSummaryText(start, isStart: true)) 显示，在 \(timeSummaryText(end, isStart: false)) 结束。",
                zhHant: "任務會在 \(timeSummaryText(start, isStart: true)) 顯示，在 \(timeSummaryText(end, isStart: false)) 結束。",
                ja: "タスクは\(timeSummaryText(start, isStart: true))に表示され、\(timeSummaryText(end, isStart: false))に終了します。"
            )
        case let (start?, nil):
            return L10n.tr(
                "The task shows from \(timeSummaryText(start, isStart: true)).",
                zhHans: "任务会从 \(timeSummaryText(start, isStart: true)) 开始显示。",
                zhHant: "任務會從 \(timeSummaryText(start, isStart: true)) 開始顯示。",
                ja: "タスクは\(timeSummaryText(start, isStart: true))から表示されます。"
            )
        case let (nil, end?):
            return L10n.tr(
                "The task ends at \(timeSummaryText(end, isStart: false)).",
                zhHans: "任务会在 \(timeSummaryText(end, isStart: false)) 结束。",
                zhHant: "任務會在 \(timeSummaryText(end, isStart: false)) 結束。",
                ja: "タスクは\(timeSummaryText(end, isStart: false))に終了します。"
            )
        case (nil, nil):
            return nil
        }
    }

    private var startDateDisplayText: String {
        if let startVisibleAt {
            return activeStartFieldUsesDate ? formattedDateTime(startVisibleAt) : formattedTime(startVisibleAt)
        }
        switch scheduleMode {
        case .single:
            return L10n.tr(
                "Start time",
                zhHans: "开始时间",
                zhHant: "開始時間",
                ja: "開始時刻"
            )
        case .repeating:
            guard repeatingRuleNeedsAnchorDate else {
                return L10n.tr(
                    "Start time",
                    zhHans: "开始时间",
                    zhHant: "開始時間",
                    ja: "開始時刻"
                )
            }
            return L10n.tr(
                "Start time",
                zhHans: "开始时间",
                zhHant: "開始時間",
                ja: "開始時刻"
            )
        }
    }

    private var endDateDisplayText: String {
        if let endVisibleAt {
            return scheduleMode == .repeating ? formattedTime(endVisibleAt) : formattedDateTime(endVisibleAt)
        }
        return L10n.tr(
            "End time",
            zhHans: "结束时间",
            zhHant: "結束時間",
            ja: "終了時刻"
        )
    }

    private func timeSummaryText(_ date: Date, isStart: Bool) -> String {
        if isStart {
            return activeStartFieldUsesDate ? formattedDateTime(date) : formattedTime(date)
        }
        return scheduleMode == .single ? formattedDateTime(date) : formattedTime(date)
    }

    private var repeatPreviewText: String? {
        guard scheduleMode == .repeating else { return nil }
        let rule = recurrenceRuleForCurrentRepeatingDraft(defaultDate: recurrenceAnchorDate)
        let separator = AppLanguage.current == .english ? ", " : "、"

        switch rule.kind {
        case .daily:
            return repeatPreviewWithTime(
                L10n.tr(
                "Repeats every day.",
                zhHans: "每天显示。",
                zhHant: "每天顯示。",
                ja: "毎日表示されます。"
                )
            )
        case .weekly:
            let weekdayText = weekdayOptions
                .filter { rule.weekdays.contains($0.value) }
                .map(\.label)
                .joined(separator: separator)
            guard !weekdayText.isEmpty else { return nil }
            return repeatPreviewWithTime(
                L10n.tr(
                "Repeats weekly on \(weekdayText).",
                zhHans: "每周在\(weekdayText)显示。",
                zhHant: "每週在\(weekdayText)顯示。",
                ja: "毎週\(weekdayText)に表示されます。"
                )
            )
        case .monthlyDay:
            let day = rule.monthDay ?? recurrenceMonthDay
            return repeatPreviewWithTime(
                L10n.tr(
                "Repeats on day \(day) each month.",
                zhHans: "每月 \(day) 日显示。",
                zhHant: "每月 \(day) 日顯示。",
                ja: "毎月\(day)日に表示されます。"
                )
            )
        case .everyNDays:
            let dates = nextOccurrenceDates(for: rule, from: Date(), count: 3)
            guard !dates.isEmpty else { return nil }
            let dateText = dates.map(shortPreviewDate).joined(separator: separator)
            return repeatPreviewWithTime(
                L10n.tr(
                "Every \(rule.interval) days means once every \(rule.interval) days from the start date. Next: \(dateText)",
                zhHans: "每隔 \(rule.interval) 天表示从起算日期开始，每 \(rule.interval) 天出现一次。接下来：\(dateText)",
                zhHant: "每隔 \(rule.interval) 天表示從起算日期開始，每 \(rule.interval) 天出現一次。接下來：\(dateText)",
                ja: "\(rule.interval)日ごとは、開始日から\(rule.interval)日ごとに1回表示されます。次回：\(dateText)"
                )
            )
        case .none:
            return nil
        }
    }

    private func repeatPreviewWithTime(_ ruleText: String) -> String {
        let allDayText = L10n.tr(
            "Available all day on repeat dates.",
            zhHans: "在重复日期全天可完成。",
            zhHant: "在重複日期全天可完成。",
            ja: "繰り返し日は終日完了できます。"
        )
        let separator = AppLanguage.current == .english ? " " : ""
        return "\(ruleText)\(separator)\(allDayText)"
    }

    private var repeatTimeWindowPreviewText: String? {
        switch (startVisibleAt, endVisibleAt) {
        case let (start?, end?):
            return L10n.tr(
                "Completion window: \(formattedTime(start))-\(formattedTime(end)).",
                zhHans: "可完成时间：\(formattedTime(start))-\(formattedTime(end))。",
                zhHant: "可完成時間：\(formattedTime(start))-\(formattedTime(end))。",
                ja: "完了できる時間：\(formattedTime(start))〜\(formattedTime(end))。"
            )
        case let (start?, nil):
            return L10n.tr(
                "Can be completed from \(formattedTime(start)).",
                zhHans: "可从 \(formattedTime(start)) 开始完成。",
                zhHant: "可從 \(formattedTime(start)) 開始完成。",
                ja: "\(formattedTime(start))から完了できます。"
            )
        case let (nil, end?):
            return L10n.tr(
                "Can be completed until \(formattedTime(end)).",
                zhHans: "可在 \(formattedTime(end)) 前完成。",
                zhHant: "可在 \(formattedTime(end)) 前完成。",
                ja: "\(formattedTime(end))まで完了できます。"
            )
        case (nil, nil):
            return nil
        }
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

    private var minimumSelectableDate: Date {
        Date()
    }

    private var isPickerSelectionValid: Bool {
        if activeDatePickerIncludesDate {
            return normalizedPickerSelectionDate >= pickerMinimumDate
        }
        if scheduleMode == .repeating,
           activeDatePickerField == .end,
           let startVisibleAt {
            return normalizedPickerSelectionDate > startVisibleAt
        }
        return true
    }

    private var datePickerInvalidSelectionMessage: String {
        switch activeDatePickerField {
        case .start:
            return L10n.tr(
                "Start time can't be in the past.",
                zhHans: "开始时间不能早于当前时间。",
                zhHant: "開始時間不能早於目前時間。",
                ja: "開始時刻は現在時刻より前にできません。"
            )
        case .end:
            return L10n.tr(
                "End time must be later than start time.",
                zhHans: "结束时间必须晚于开始时间。",
                zhHant: "結束時間必須晚於開始時間。",
                ja: "終了時刻は開始時刻より後にしてください。"
            )
        }
    }

    private var normalizedPickerSelectionDate: Date {
        guard scheduleMode == .repeating else {
            return pickerSelectionDate
        }
        switch activeDatePickerField {
        case .start:
            guard !repeatingRuleNeedsAnchorDate else { return pickerSelectionDate }
            return dateByCombiningDay(
                of: startVisibleAt ?? Date(),
                timeOf: pickerSelectionDate
            )
        case .end:
            return dateByCombiningDay(
                of: startVisibleAt ?? Date(),
                timeOf: pickerSelectionDate
            )
        }
    }

    private var datePickerDisplayedComponents: DatePickerComponents {
        activeDatePickerIncludesDate ? [.date, .hourAndMinute] : [.hourAndMinute]
    }

    private var datePickerTitle: String {
        activeDatePickerField == .start ? startTimeFieldTitle : endTimeFieldTitle
    }

    private func prepareDatePicker(for field: ActiveDatePickerField, preferredDate: Date) {
        let minimumDate = minimumSelectableDateForActiveField(field, now: Date())
        pickerMinimumDate = minimumDate
        if scheduleMode == .repeating, field == .end {
            pickerSelectionDate = dateByCombiningDay(of: startVisibleAt ?? Date(), timeOf: preferredDate)
        } else if scheduleMode == .repeating, field == .start, !repeatingRuleNeedsAnchorDate {
            pickerSelectionDate = dateByCombiningDay(of: startVisibleAt ?? Date(), timeOf: preferredDate)
        } else {
            pickerSelectionDate = max(preferredDate, minimumDate)
        }
    }

    private func minimumSelectableDateForActiveField(_ field: ActiveDatePickerField) -> Date {
        minimumSelectableDateForActiveField(field, now: Date())
    }

    private func minimumSelectableDateForActiveField(_ field: ActiveDatePickerField, now: Date) -> Date {
        switch field {
        case .start:
            if scheduleMode == .repeating, !repeatingRuleNeedsAnchorDate {
                return now
            }
            return now
        case .end:
            if scheduleMode == .repeating {
                return startVisibleAt ?? now
            }
            if let startVisibleAt {
                return max(startVisibleAt, now)
            }
            return now
        }
    }

    private var datePickerSheet: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Text(datePickerTitle)
                    .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))

                    Spacer()
                    Button(L10n.done) {
                        guard isPickerSelectionValid else {
                            showBlockedSaveToast(datePickerInvalidSelectionMessage)
                            return
                        }
                        switch activeDatePickerField {
                        case .start:
                            startVisibleAt = normalizedPickerSelectionDate
                            if scheduleMode == .repeating {
                                if let endVisibleAt {
                                    let normalizedEnd = dateByCombiningDay(of: normalizedPickerSelectionDate, timeOf: endVisibleAt)
                                    self.endVisibleAt = normalizedEnd > normalizedPickerSelectionDate ? normalizedEnd : nil
                                }
                            } else if let endVisibleAt, endVisibleAt <= normalizedPickerSelectionDate {
                                self.endVisibleAt = nil
                            }
                        case .end:
                            endVisibleAt = normalizedPickerSelectionDate
                        }
                        isDatePickerPresented = false
                    }
                    .buttonStyle(.plain)
                    .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(isPickerSelectionValid ? accentColor : secondaryTextColor)
                    .disabled(!isPickerSelectionValid)
                }
                .padding(.horizontal, 16)
                .padding(.top, 23)

                Group {
                    if activeDatePickerIncludesDate {
                        DatePicker(
                            "",
                            selection: $pickerSelectionDate,
                            in: pickerMinimumDate...,
                            displayedComponents: datePickerDisplayedComponents
                        )
                    } else {
                        DatePicker(
                            "",
                            selection: $pickerSelectionDate,
                            displayedComponents: datePickerDisplayedComponents
                        )
                    }
                }
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 216)
                .clipped()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.20, blue: 0.20))
                )
                .environment(\.colorScheme, .dark)
                .tint(accentColor)
                .padding(.horizontal, 12)

                HStack {
                    Spacer()
                    Button(
                        activeDatePickerField == .start
                        ? L10n.tr("No start time", zhHans: "不设置开始时间", zhHant: "不設定開始時間", ja: "開始時刻を設定しない")
                        : L10n.tr("No end time", zhHans: "不设置结束时间", zhHant: "不設定結束時間", ja: "終了時刻を設定しない")
                    ) {
                        switch activeDatePickerField {
                        case .start:
                            startVisibleAt = nil
                        case .end:
                            endVisibleAt = nil
                        }
                        isDatePickerPresented = false
                    }
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.red.opacity(0.8))
                    Spacer()
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 30)
        }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
        .preferredColorScheme(.dark)
    }

    private var recurrencePickerSheet: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Text(recurrencePickerTitle)
                        .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))

                    Spacer()

                    Button(L10n.done) {
                        isRecurrencePickerPresented = false
                    }
                    .buttonStyle(.plain)
                    .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 23)

                Group {
                    switch activeRecurrencePickerField {
                    case .monthlyDay:
                        Picker("", selection: $recurrenceMonthDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text(monthlyDayMenuTitle(day))
                                    .tag(day)
                            }
                        }
                    case .everyNDays:
                        Picker("", selection: $recurrenceDayInterval) {
                            ForEach(2...TaskRecurrenceRule.maxDayInterval, id: \.self) { interval in
                                Text(everyNDaysMenuTitle(interval))
                                    .tag(interval)
                            }
                        }
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 216)
                .clipped()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.20, blue: 0.20))
                )
                .environment(\.colorScheme, .dark)
                .tint(accentColor)
                .padding(.horizontal, 12)

                Spacer(minLength: 0)
            }
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
        .preferredColorScheme(.dark)
    }

    private var recurrencePickerTitle: String {
        switch activeRecurrencePickerField {
        case .monthlyDay:
            return L10n.tr("Monthly day", zhHans: "每月日期", zhHant: "每月日期", ja: "毎月の日付")
        case .everyNDays:
            return L10n.tr("Interval", zhHans: "间隔", zhHant: "間隔", ja: "間隔")
        }
    }

    private func endVisibleAtForSave() -> Date? {
        guard let endVisibleAt else { return nil }
        guard scheduleMode == .repeating else { return endVisibleAt }
        return dateByCombiningDay(of: startVisibleAt ?? Date(), timeOf: endVisibleAt)
    }

    private func dateByCombiningDay(of dayDate: Date, timeOf timeDate: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: dayDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: timeDate)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        components.nanosecond = timeComponents.nanosecond
        return calendar.date(from: components) ?? timeDate
    }

    private func nextOccurrenceDates(
        for rule: TaskRecurrenceRule,
        from referenceDate: Date,
        count: Int
    ) -> [Date] {
        var dates: [Date] = []
        var cursor = referenceDate
        let calendar = Calendar.current

        while dates.count < count {
            guard let nextDate = rule.nextActiveDate(onOrAfter: cursor, calendar: calendar) else {
                break
            }
            dates.append(nextDate)
            guard let followingDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: nextDate)) else {
                break
            }
            cursor = followingDay
        }

        return dates
    }

    private func shortPreviewDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.calendar = Calendar.current
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = AppLanguage.displayLocale
        dateFormatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "yMd",
            options: 0,
            locale: AppLanguage.displayLocale
        ) ?? "M/d/y"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = AppLanguage.displayLocale
        timeFormatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "Hm",
            options: 0,
            locale: AppLanguage.displayLocale
        ) ?? "HH:mm"

        return "\(dateFormatter.string(from: date)) \(timeFormatter.string(from: date))"
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "Hm",
            options: 0,
            locale: AppLanguage.displayLocale
        ) ?? "HH:mm"
        return formatter.string(from: date)
    }

    private func recurrenceValueButton(
        title: String,
        valueText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismissKeyboard()
            action()
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
        Button {
            dismissKeyboard()
            action()
        } label: {
            Text(title)
                .font(bodySFont.weight(.medium))
                .kerning(bodySLetterSpacing)
                .foregroundColor(isSelected ? Color.white : primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
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
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            Toggle(configuration)
                .toggleStyle(.switch)
                .tint(NeumorphicColors.modalAccent)
        } else {
            legacyBody(configuration: configuration)
        }
    }

    private func legacyBody(configuration: Configuration) -> some View {
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
                    .fill(configuration.isOn ? NeumorphicColors.modalAccent : NeumorphicColors.background)
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
