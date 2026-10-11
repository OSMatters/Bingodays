import AVFoundation
import Combine
import Foundation
import Speech

/// Owns microphone and speech framework state for task editing.
///
/// Keeping this service outside the sheet prevents the view from also owning
/// the audio session lifecycle and makes the recognizer reusable by other
/// input surfaces.
final class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isInputTapInstalled = false
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
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeInputTapIfNeeded()

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
        isInputTapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            stopRecording()
            return
        }
    }

    func stopRecording() {
        audioEngine.stop()
        removeInputTapIfNeeded()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        AppAudioSessionConfigurator.deactivateRecordingSession()
        DispatchQueue.main.async { self.isRecording = false }
    }

    private func removeInputTapIfNeeded() {
        guard isInputTapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        isInputTapInstalled = false
    }
}
