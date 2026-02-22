import Foundation
import Speech
import AVFoundation

final class SpeechTranscriptionManager {
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let processingQueue = DispatchQueue(label: "SpeechTranscriptionManager.queue")

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var shouldBeRunning = false
    private var restartWorkItem: DispatchWorkItem?

    var onTextUpdate: ((String, Bool) -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?
    var onStatusUpdate: ((String) -> Void)?

    func start() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.shouldBeRunning = true
            self.restartWorkItem?.cancel()

            if self.audioEngine.isRunning || self.recognitionTask != nil {
                return
            }

            self.publishStatus("Requesting speech permissions…")
            self.requestPermissionsAndStart()
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.shouldBeRunning = false
            self.restartWorkItem?.cancel()
            self.teardownRecognitionSession()
        }
    }

    private func requestPermissionsAndStart() {
        requestSpeechPermission { [weak self] speechAuthorized in
            guard let self else { return }
            guard speechAuthorized else {
                self.publishAvailability(false)
                self.publishStatus("Speech permission denied")
                return
            }

            self.requestMicrophonePermission { [weak self] micAuthorized in
                guard let self else { return }
                guard micAuthorized else {
                    self.publishAvailability(false)
                    self.publishStatus("Microphone permission denied")
                    return
                }

                self.processingQueue.async {
                    guard self.shouldBeRunning else { return }
                    self.startRecognitionSession()
                }
            }
        }
    }

    private func startRecognitionSession() {
        guard let speechRecognizer else {
            publishAvailability(false)
            publishStatus("Speech recognizer unavailable for locale \(Locale.current.identifier)")
            return
        }

        guard speechRecognizer.isAvailable else {
            publishAvailability(false)
            publishStatus("Speech recognizer temporarily unavailable")
            scheduleRestartIfNeeded()
            return
        }

        teardownRecognitionSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            publishAvailability(false)
            publishStatus("Audio session error: \(error.localizedDescription)")
            scheduleRestartIfNeeded()
            return
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            publishAvailability(false)
            publishStatus("Unable to start microphone: \(error.localizedDescription)")
            teardownRecognitionSession()
            scheduleRestartIfNeeded()
            return
        }

        publishAvailability(true)
        publishStatus("Listening…")

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.publishText(result.bestTranscription.formattedString, isFinal: result.isFinal)
                if result.isFinal {
                    self.processingQueue.async {
                        self.teardownRecognitionSession()
                        self.scheduleRestartIfNeeded()
                    }
                }
            }

            if let error {
                self.publishStatus("Speech error: \(error.localizedDescription)")
                self.processingQueue.async {
                    self.teardownRecognitionSession()
                    self.scheduleRestartIfNeeded()
                }
            }
        }
    }

    private func teardownRecognitionSession() {
        restartWorkItem?.cancel()
        restartWorkItem = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // no-op
        }
    }

    private func scheduleRestartIfNeeded() {
        guard shouldBeRunning else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.shouldBeRunning else { return }
            self.startRecognitionSession()
        }
        restartWorkItem = item
        processingQueue.asyncAfter(deadline: .now() + 0.75, execute: item)
    }

    private func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                completion(status == .authorized)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            completion(granted)
        }
    }

    private func publishText(_ text: String, isFinal: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onTextUpdate?(text, isFinal)
        }
    }

    private func publishAvailability(_ available: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onAvailabilityChanged?(available)
        }
    }

    private func publishStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusUpdate?(status)
        }
    }
}
