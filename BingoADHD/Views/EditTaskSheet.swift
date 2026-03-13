import SwiftUI
import Speech

struct EditTaskSheet: View {
    @State var text: String
    @State var isForcedTask: Bool
    let onApplyGroup: ([String]) -> Bool
    let onSave: (String, Bool) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @StateObject private var speechRecognizer = SpeechRecognizer()
    @FocusState private var isTextFieldFocused: Bool
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @State private var showGroupApplyAlert = false

    init(text: String, isForcedTask: Bool, onApplyGroup: @escaping ([String]) -> Bool, onSave: @escaping (String, Bool) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: text)
        _isForcedTask = State(initialValue: isForcedTask)
        self.onApplyGroup = onApplyGroup
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            ZStack {
                NeumorphicColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 16) {
                                TextField(L10n.enterTaskForDay, text: $text, axis: .vertical)
                                    .font(.body)
                                    .foregroundColor(NeumorphicColors.text)
                                    .padding(16)
                                    .frame(minHeight: 74, alignment: .topLeading)
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
                                        .font(.system(size: 20, weight: .regular))
                                        .foregroundColor(speechRecognizer.isRecording ? NeumorphicColors.bingoAccent : NeumorphicColors.accent)
                                        .frame(width: 42, height: 42)
                                        .background(
                                            Color.clear
                                                .neumorphicConvex(radius: 21, isPressed: speechRecognizer.isRecording)
                                        )
                                        .animation(.easeInOut(duration: 0.3), value: speechRecognizer.isRecording)
                                }
                            }

                            HStack(spacing: 12) {
                                Text(L10n.forceCompletion)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(NeumorphicColors.text)

                                Spacer()

                                Toggle("", isOn: $isForcedTask)
                                    .labelsHidden()
                                    .toggleStyle(NeumorphicSwitchToggleStyle())
                            }

                            if speechRecognizer.isRecording {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(NeumorphicColors.bingoAccent)
                                        .frame(width: 8, height: 8)
                                        .scaleEffect(speechRecognizer.isRecording ? 1.2 : 0.8)
                                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: speechRecognizer.isRecording)
                                    Text(L10n.recording)
                                        .font(.caption)
                                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                                }
                                .transition(.opacity)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.quickAdd)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundColor(NeumorphicColors.text)

                            if !quickAddGroups.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(L10n.groups)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(NeumorphicColors.text.opacity(0.66))

                                    HStack(spacing: 12) {
                                        ForEach(quickAddGroups) { group in
                                            Button {
                                                let didApply = onApplyGroup(group.tasks)
                                                if !didApply {
                                                    showGroupApplyAlert = true
                                                }
                                            } label: {
                                                Text(group.name)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(NeumorphicColors.text)
                                                    .lineLimit(1)
                                                    .multilineTextAlignment(.center)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 8)
                                                    .background(Color.clear.neumorphicConvex(radius: 9))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.tasks)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.66))

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                                    ForEach(quickTasks, id: \.self) { task in
                                        Button {
                                            text = task
                                        } label: {
                                            Text(task)
                                                .font(.caption)
                                                .foregroundColor(NeumorphicColors.text)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(Color.clear.neumorphicConvex(radius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if !text.isEmpty {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label(L10n.deleteTask, systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(NeumorphicColors.bingoAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.clear.neumorphicConvex(radius: 12))
                            }
                            .padding(.top, 16)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 82)
                    .padding(.bottom, 40)
                }
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
                    Button(L10n.save) { onSave(text, isForcedTask) }
                        .fontWeight(.semibold)
                        .foregroundColor(NeumorphicColors.accent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isTextFieldFocused = true }
            .alert(L10n.unableToApplyGroup, isPresented: $showGroupApplyAlert) {
                Button(L10n.ok, role: .cancel) { }
            } message: {
                Text(L10n.applyGroupFailedMessage)
            }
        }
    }

    private var quickTasks: [String] {
        let library = CommonTasksStore.loadLibrary()
        if library.tasks.isEmpty {
            return [
                L10n.tr("Brush Teeth", zhHans: "刷牙"),
                L10n.tr("Shower", zhHans: "洗澡"),
                L10n.tr("Exercise", zhHans: "运动"),
                L10n.tr("Drink Water", zhHans: "喝水"),
                L10n.tr("Eat", zhHans: "吃饭"),
                L10n.tr("Sweep", zhHans: "扫地"),
                L10n.tr("Wash Dishes", zhHans: "洗碗"),
                L10n.tr("Laundry", zhHans: "洗衣服")
            ]
        }
        return library.tasks
    }

    private var quickAddGroups: [MyTaskGroup] {
        CommonTasksStore.loadGroups().filter { !$0.tasks.isEmpty }
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
