import SwiftUI
import Speech

struct EditTaskSheet: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var text: String
    @State var isForcedTask: Bool
    @State var residentWeekdays: Set<Int>
    @State var isOneTimeTask: Bool
    @State var startVisibleAt: Date?
    @State var endVisibleAt: Date?
    let isCompletedTask: Bool
    let autoFocusTaskField: Bool
    let onSave: (String, Bool, Set<Int>, Bool, Int?, Date?, Date?) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @StateObject private var speechRecognizer = SpeechRecognizer()
    @FocusState private var focusedField: FocusField?
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @State private var isDatePickerPresented = false
    @State private var pickerSelectionDate = Date()
    @State private var isDeleteConfirmationPresented = false
    @State private var blockedSaveToastMessage: String?
    @State private var hideBlockedSaveToastWorkItem: DispatchWorkItem?
    @State private var activeDatePickerField: ActiveDatePickerField = .start
    @State private var didRequestInitialTaskFocus = false
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue

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

    private enum ActiveDatePickerField {
        case start
        case end
    }

    init(
        text: String,
        isForcedTask: Bool,
        residentWeekdays: Set<Int>,
        isOneTimeTask: Bool,
        startVisibleAt: Date?,
        endVisibleAt: Date?,
        isCompletedTask: Bool,
        estimatedDurationMinutes: Int?,
        autoFocusTaskField: Bool = false,
        onSave: @escaping (String, Bool, Set<Int>, Bool, Int?, Date?, Date?) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _text = State(initialValue: text)
        _isForcedTask = State(initialValue: isForcedTask)
        _residentWeekdays = State(initialValue: residentWeekdays)
        _isOneTimeTask = State(initialValue: isOneTimeTask)
        _startVisibleAt = State(initialValue: startVisibleAt)
        _endVisibleAt = State(initialValue: endVisibleAt)
        self.isCompletedTask = isCompletedTask
        self.autoFocusTaskField = autoFocusTaskField
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        let normalizedDuration = estimatedDurationMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }
        self.initialEstimatedDurationMinutes = normalizedDuration
        self.initialStartVisibleAt = startVisibleAt
        self.initialEndVisibleAt = endVisibleAt
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
    private let initialStartVisibleAt: Date?
    private let initialEndVisibleAt: Date?

    private let screenOverlayColor = Color.black.opacity(0.80)
    private let fieldColor = Color(hex: "3F3F3F")
    private let fieldBorderColor = Color.clear
    private let primaryTextColor = Color.white
    private let secondaryTextColor = Color(hex: "828282")
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var accentColor: Color { activeTheme.color }
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
        guard !isPadLayout else { return 0 }
        return baseVerticalOffset + (repeatMode == .custom ? expandedCustomLiftOffset : collapsedExtraOffset)
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
        GeometryReader { geo in
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
                            timeWindowSection
                            forceCompletionSection
                            repeatSection
                            timerSection

                            saveButton
                        }
                        .frame(width: contentColumnWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, max(26, geo.safeAreaInsets.bottom + (isPadLayout ? 40 : 26)))
                    }
                    .frame(maxHeight: .infinity)
                    .scrollDismissesKeyboard(.interactively)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, isPadLayout ? geo.safeAreaInsets.top : 0)
                .offset(y: sheetVerticalOffset)
                .animation(.easeInOut(duration: 0.22), value: repeatMode)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $isDatePickerPresented) {
            datePickerSheet
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
        .onAppear {
            focusTaskFieldIfNeeded()
        }
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
                        .submitLabel(.done)
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

    private var timeWindowSection: some View {
        sectionSurface {
            HStack(alignment: .top, spacing: 12) {
                timeFieldColumn(
                    icon: "calendar",
                    title: L10n.tr(
                        "Start time",
                        zhHans: "开始时间",
                        zhHant: "開始時間"
                    ),
                    text: startDateDisplayText,
                    isConfigured: hasStartDate,
                    inputTopInset: 4
                ) {
                    focusedField = nil
                    activeDatePickerField = .start
                    pickerSelectionDate = max(startVisibleAt ?? Date(), minimumSelectableDate)
                    isDatePickerPresented = true
                }

                timeFieldColumn(
                    icon: "calendar.badge.clock",
                    title: L10n.tr(
                        "End time",
                        zhHans: "结束时间",
                        zhHant: "結束時間"
                    ),
                    text: endDateDisplayText,
                    isConfigured: endVisibleAt != nil
                ) {
                    focusedField = nil
                    activeDatePickerField = .end
                    pickerSelectionDate = max(endVisibleAt ?? startVisibleAt ?? Date(), minimumSelectableDateForActiveField(.end))
                    isDatePickerPresented = true
                }
            }

            Text(
                L10n.tr(
                    "Tasks show at the start time and end at the end time.",
                    zhHans: "任务会在开始时间显示，在结束时间结束。",
                    zhHant: "任務會在開始時間顯示，在結束時間結束。",
                    ja: "タスクは開始時刻に表示され、終了時刻に終了します。"
                )
            )
            .font(bodySFont.weight(.medium))
            .foregroundColor(secondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    zhHant: "自訂輸入",
                    ja: "カスタム入力"
                ),
                text: $timerCustomMinutesText
            )
            .keyboardType(.numberPad)
            .submitLabel(.done)
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
        if isCompletedTask,
           startVisibleAt != initialStartVisibleAt || endVisibleAt != initialEndVisibleAt {
            showBlockedSaveToast(
                L10n.tr(
                    "Completed tasks can't change start or end time.",
                    zhHans: "已完成任务不可修改开始或结束时间。",
                    zhHant: "已完成任務不可修改開始或結束時間。"
                )
            )
            return
        }
        if let startVisibleAt, startVisibleAt < minimumSelectableDate {
            showBlockedSaveToast(
                L10n.tr(
                    "Start time can't be in the past.",
                    zhHans: "开始时间不能早于当前时间。",
                    zhHant: "開始時間不能早於目前時間。"
                )
            )
            return
        }
        if let startVisibleAt, let endVisibleAt, endVisibleAt <= startVisibleAt {
            showBlockedSaveToast(
                L10n.tr(
                    "End time must be later than start time.",
                    zhHans: "结束时间必须晚于开始时间。",
                    zhHant: "結束時間必須晚於開始時間。"
                )
            )
            return
        }
        if let endVisibleAt, endVisibleAt < minimumSelectableDateForActiveField(.end) {
            showBlockedSaveToast(
                L10n.tr(
                    "End time can't be in the past.",
                    zhHans: "结束时间不能早于当前时间。",
                    zhHant: "結束時間不能早於目前時間。"
                )
            )
            return
        }
        onSave(text, isForcedTask, residentWeekdays, isOneTimeTask, normalizedEstimatedDurationMinutes, startVisibleAt, endVisibleAt)
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

    private func focusTaskFieldIfNeeded() {
        guard autoFocusTaskField, !didRequestInitialTaskFocus else { return }
        didRequestInitialTaskFocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            focusedField = .task
        }
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

    private func timeFieldColumn(
        icon: String,
        title: String,
        text: String,
        isConfigured: Bool,
        inputTopInset: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldHeader(icon: icon, title: title)

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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: scaled(56, pad: 64), alignment: .leading)
                .background(inputBackground(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, inputTopInset)
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
        startVisibleAt != nil
    }

    private var startDateDisplayText: String {
        if let startVisibleAt {
            return formattedDateTime(startVisibleAt)
        }
        return L10n.tr(
            "Select start time",
            zhHans: "选择开始时间",
            zhHant: "選擇開始時間",
            ja: "開始時刻を選択"
        )
    }

    private var endDateDisplayText: String {
        if let endVisibleAt {
            return formattedDateTime(endVisibleAt)
        }
        return L10n.tr(
            "Add end time",
            zhHans: "添加结束时间",
            zhHant: "添加結束時間",
            ja: "終了時刻を追加"
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

    private var minimumSelectableDate: Date {
        Date()
    }

    private func minimumSelectableDateForActiveField(_ field: ActiveDatePickerField) -> Date {
        switch field {
        case .start:
            return minimumSelectableDate
        case .end:
            if let startVisibleAt {
                return max(startVisibleAt, minimumSelectableDate)
            }
            return minimumSelectableDate
        }
    }

    private var datePickerSheet: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Text(
                        activeDatePickerField == .start
                        ? L10n.tr("Start time", zhHans: "开始时间", zhHant: "開始時間")
                        : L10n.tr("End time", zhHans: "结束时间", zhHant: "結束時間")
                    )
                    .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))

                    Spacer()
                    Button(L10n.done) {
                        switch activeDatePickerField {
                        case .start:
                            guard pickerSelectionDate >= minimumSelectableDate else {
                                showBlockedSaveToast(
                                    L10n.tr(
                                        "Start time can't be in the past.",
                                        zhHans: "开始时间不能早于当前时间。",
                                        zhHant: "開始時間不能早於目前時間。"
                                    )
                                )
                                return
                            }
                            startVisibleAt = pickerSelectionDate
                            if let endVisibleAt, endVisibleAt <= pickerSelectionDate {
                                self.endVisibleAt = nil
                            }
                        case .end:
                            guard pickerSelectionDate >= minimumSelectableDateForActiveField(.end) else {
                                showBlockedSaveToast(
                                    L10n.tr(
                                        "End time must be later than start time.",
                                        zhHans: "结束时间必须晚于开始时间。",
                                        zhHant: "結束時間必須晚於開始時間。"
                                    )
                                )
                                return
                            }
                            endVisibleAt = pickerSelectionDate
                        }
                        isDatePickerPresented = false
                    }
                    .buttonStyle(.plain)
                    .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 23)

                DatePicker(
                    "",
                    selection: $pickerSelectionDate,
                    in: minimumSelectableDateForActiveField(activeDatePickerField)...,
                    displayedComponents: [.date, .hourAndMinute]
                )
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

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "MdyHm",
            options: 0,
            locale: AppLanguage.displayLocale
        ) ?? "M/d HH:mm"
        return formatter.string(from: date)
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
