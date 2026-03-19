import SwiftUI
import Speech

struct EditTaskSheet: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var text: String
    @State var isForcedTask: Bool
    @State var residentWeekdays: Set<Int>
    let onSave: (String, Bool, Set<Int>, Int?) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @StateObject private var speechRecognizer = SpeechRecognizer()
    @FocusState private var isTextFieldFocused: Bool
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(
        text: String,
        isForcedTask: Bool,
        residentWeekdays: Set<Int>,
        estimatedDurationMinutes: Int?,
        onSave: @escaping (String, Bool, Set<Int>, Int?) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _text = State(initialValue: text)
        _isForcedTask = State(initialValue: isForcedTask)
        _residentWeekdays = State(initialValue: residentWeekdays)
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        let initialTotalMinutes = min(max(estimatedDurationMinutes ?? 30, 1), BingoViewModel.maxCountdownMinutes)
        _isTaskTimerEnabled = State(initialValue: estimatedDurationMinutes != nil)
        _taskTimerHours = State(initialValue: min(initialTotalMinutes / 60, 24))
        _taskTimerMinutes = State(initialValue: initialTotalMinutes % 60)
    }

    @State private var isTaskTimerEnabled = false
    @State private var taskTimerHours = 0
    @State private var taskTimerMinutes = 30

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isTextFieldFocused = false
                    }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 16) {
                                TextField(L10n.enterTaskForDay, text: $text, axis: .vertical)
                                    .font(.system(size: scaled(17, pad: 20), weight: .medium, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)
                                    .padding(16)
                                    .frame(minHeight: isPadLayout ? 84 : 74, alignment: .topLeading)
                                    .background(Color.clear.neumorphicConcave(radius: 12))
                                    .focused($isTextFieldFocused)
                                    .lineLimit(3...5)
                                    .onChange(of: text) { _, newValue in
                                        if newValue.count > BingoViewModel.maxTaskLength {
                                            text = String(newValue.prefix(BingoViewModel.maxTaskLength))
                                        }
                                    }

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
                                        .font(.system(size: scaled(20, pad: 24), weight: .regular))
                                        .foregroundColor(speechRecognizer.isRecording ? NeumorphicColors.bingoAccent : NeumorphicColors.accent)
                                        .frame(width: isPadLayout ? 48 : 42, height: isPadLayout ? 48 : 42)
                                        .background(
                                            Color.clear
                                                .neumorphicConvex(radius: isPadLayout ? 24 : 21, isPressed: speechRecognizer.isRecording)
                                        )
                                        .animation(.easeInOut(duration: 0.3), value: speechRecognizer.isRecording)
                                }
                            }

                            HStack(spacing: 12) {
                                Text(L10n.forceCompletion)
                                    .font(.system(size: scaled(15, pad: 18), weight: .semibold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)

                                Spacer()

                                Toggle("", isOn: $isForcedTask)
                                    .labelsHidden()
                                    .toggleStyle(NeumorphicSwitchToggleStyle())
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Text(L10n.residentDays)
                                        .font(.system(size: scaled(15, pad: 18), weight: .semibold, design: .rounded))
                                        .foregroundColor(NeumorphicColors.text)

                                    if residentWeekdays.isEmpty {
                                        Text(L10n.alwaysVisible)
                                            .font(.system(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                                            .foregroundColor(NeumorphicColors.text.opacity(0.52))
                                    }
                                }

                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                    ForEach(weekdayOptions, id: \.value) { option in
                                        Button {
                                            if residentWeekdays.contains(option.value) {
                                                residentWeekdays.remove(option.value)
                                            } else {
                                                residentWeekdays.insert(option.value)
                                            }
                                        } label: {
                                            Text(option.label)
                                                .font(.system(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                                                .foregroundColor(residentWeekdays.contains(option.value) ? .white : NeumorphicColors.text)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(
                                                    Group {
                                                        if residentWeekdays.contains(option.value) {
                                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                                .fill(NeumorphicColors.accent)
                                                                .shadow(color: NeumorphicColors.accent.opacity(0.25), radius: 10, x: 0, y: 4)
                                                        } else {
                                                            Color.clear.neumorphicConvex(radius: 10)
                                                        }
                                                    }
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Text(L10n.estimatedCompletionTime)
                                        .font(.system(size: scaled(15, pad: 18), weight: .semibold, design: .rounded))
                                        .foregroundColor(NeumorphicColors.text)

                                    Spacer()

                                    Toggle("", isOn: $isTaskTimerEnabled)
                                        .labelsHidden()
                                        .toggleStyle(NeumorphicSwitchToggleStyle())
                                }

                                Text(L10n.taskTimerEnabled)
                                    .font(.system(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.58))

                                if isTaskTimerEnabled {
                                    HStack(spacing: 10) {
                                        taskTimerValuePicker(
                                            title: L10n.hours,
                                            valueText: L10n.hourValue(taskTimerHours)
                                        ) {
                                            ForEach(0...24, id: \.self) { hour in
                                                Button(L10n.hourValue(hour)) {
                                                    taskTimerHours = hour
                                                    if taskTimerHours == 24 {
                                                        taskTimerMinutes = 0
                                                    }
                                                }
                                            }
                                        }

                                        taskTimerValuePicker(
                                            title: L10n.minutes,
                                            valueText: L10n.minuteValue(taskTimerMinutes)
                                        ) {
                                            ForEach(taskTimerMinuteOptions, id: \.self) { minute in
                                                Button(L10n.minuteValue(minute)) {
                                                    taskTimerMinutes = minute
                                                }
                                                .disabled(taskTimerHours == 24 && minute != 0)
                                            }
                                        }
                                    }

                                    Text(taskTimerSummaryText)
                                        .font(.system(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                                        .foregroundColor(NeumorphicColors.text.opacity(0.64))
                                }
                            }

                            if speechRecognizer.isRecording {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(NeumorphicColors.bingoAccent)
                                        .frame(width: 8, height: 8)
                                        .scaleEffect(speechRecognizer.isRecording ? 1.2 : 0.8)
                                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: speechRecognizer.isRecording)
                                    Text(L10n.recording)
                                        .font(.system(size: scaled(12, pad: 14), design: .rounded))
                                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                                }
                                .transition(.opacity)
                            }
                        }

                        if !text.isEmpty {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label(L10n.deleteTask, systemImage: "trash")
                                    .font(.system(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.bingoAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.clear.neumorphicConvex(radius: 12))
                            }
                            .padding(.top, 16)
                        }
                    }
                    .frame(maxWidth: isPadLayout ? 720 : .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 82)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { onCancel() }
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) { onSave(text, isForcedTask, residentWeekdays, normalizedEstimatedDurationMinutes) }
                        .fontWeight(.semibold)
                        .foregroundColor(NeumorphicColors.accent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button(L10n.done) {
                        isTextFieldFocused = false
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
            .onChange(of: taskTimerHours) { _, newHours in
                if newHours == 24 {
                    taskTimerMinutes = 0
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

    private var taskTimerMinuteOptions: [Int] {
        taskTimerHours == 24 ? [0] : Array(stride(from: 0, through: 55, by: 5))
    }

    private var normalizedEstimatedDurationMinutes: Int? {
        guard isTaskTimerEnabled else { return nil }
        let totalMinutes = min((taskTimerHours * 60) + taskTimerMinutes, BingoViewModel.maxCountdownMinutes)
        return totalMinutes > 0 ? totalMinutes : 5
    }

    private var taskTimerSummaryText: String {
        if taskTimerHours == 24 {
            return L10n.taskTimerSummary24Hours
        }
        return L10n.taskTimerSummary(hours: taskTimerHours, minutes: taskTimerMinutes)
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
                    .font(.system(size: scaled(11, pad: 13), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.58))
                Text(valueText)
                    .font(.system(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.clear.neumorphicConvex(radius: 12))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(configuration.isOn ? .white : NeumorphicColors.text.opacity(0.65))
                    )
                    .padding(3)
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
