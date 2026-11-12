import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
protocol SpeechRecordingBackend: AnyObject {
    var isAvailable: Bool { get }
    func requestSpeechPermission() async -> Bool
    func requestMicrophonePermission() async -> Bool
    func start(onResult: @escaping @MainActor (String?, Bool) -> Void) throws
    func stop()
}

/// Permission callbacks and transcripts belong to one editor session only.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    private let backend: any SpeechRecordingBackend
    private var sessionID = UUID()
    private var permissionTask: Task<Void, Never>?
    private var interruptionObserver: AnyCancellable?

    init(backend: (any SpeechRecordingBackend)? = nil) {
        self.backend = backend ?? LiveSpeechRecordingBackend()
        interruptionObserver = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
                let began = AVAudioSession.InterruptionType(rawValue: value) == .began
                Task { @MainActor [weak self] in self?.handleAudioInterruption(isBeginning: began) }
            }
    }

    deinit { permissionTask?.cancel() }

    @discardableResult
    func startRecording(onResult: @escaping @MainActor (String) -> Void) -> Task<Void, Never> {
        stopRecording()
        let id = UUID()
        sessionID = id
        isPreparing = true
        let backend = backend
        let task = Task { [weak self, backend] in
            let speechAllowed = await backend.requestSpeechPermission()
            guard let self, self.sessionID == id, !Task.isCancelled else { return }
            guard speechAllowed else { self.stopRecording(); return }
            let micAllowed = await backend.requestMicrophonePermission()
            guard self.sessionID == id, !Task.isCancelled else { return }
            guard micAllowed, backend.isAvailable else { self.stopRecording(); return }
            do {
                try backend.start { [weak self] transcript, finished in
                    guard let self, self.sessionID == id else { return }
                    if let transcript { onResult(transcript) }
                    if finished { self.stopRecording() }
                }
                self.isRecording = true
                self.isPreparing = false
                self.permissionTask = nil
            } catch { self.stopRecording() }
        }
        permissionTask = task
        return task
    }

    func handleSceneInactivity(isBackground: Bool) {
        // System permission dialogs may make the scene inactive: keep that request alive.
        if isBackground || isRecording { stopRecording() }
    }

    func handleAudioInterruption(isBeginning: Bool) {
        if isBeginning { stopRecording() }
    }

    func stopRecording() {
        sessionID = UUID()
        permissionTask?.cancel()
        permissionTask = nil
        backend.stop()
        isRecording = false
        isPreparing = false
    }
}

@MainActor
private final class LiveSpeechRecordingBackend: SpeechRecordingBackend {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: AppLanguage.speechLocaleIdentifier))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isTapInstalled = false
    private var ownsAudioSession = false
    var isAvailable: Bool { recognizer?.isAvailable == true }

    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    func start(onResult: @escaping @MainActor (String?, Bool) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else { throw RecordingError.unavailable }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        ownsAudioSession = true
        let request = SFSpeechAudioBufferRecognitionRequest()
        self.request = request
        request.shouldReportPartialResults = true
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            let transcript = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in onResult(transcript, finished) }
        }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecordingError.unavailable }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        isTapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        audioEngine.stop()
        if isTapInstalled { audioEngine.inputNode.removeTap(onBus: 0); isTapInstalled = false }
        request?.endAudio()
        request = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if ownsAudioSession {
            AppAudioSessionConfigurator.deactivateRecordingSession()
            ownsAudioSession = false
        }
    }

    private enum RecordingError: Error { case unavailable }
}
