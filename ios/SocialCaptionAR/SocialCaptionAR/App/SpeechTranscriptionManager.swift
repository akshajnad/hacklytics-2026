import Foundation
import Speech
import AVFoundation

final class SpeechTranscriptionManager {
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer()
    private let processingQueue = DispatchQueue(label: "SpeechTranscriptionManager.queue")

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var shouldBeRunning = false
    private var restartWorkItem: DispatchWorkItem?

    var onTextUpdate: ((String, Bool) -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?

    func start() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.shouldBeRunning = true
            self.restartWorkItem?.cancel()

            if self.audioEngine.isRunning || self.recognitionTask != nil {
                return
            }

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
                return
            }

            self.requestMicrophonePermission { [weak self] micAuthorized in
                guard let self else { return }
                guard micAuthorized else {
                    self.publishAvailability(false)
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
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            publishAvailability(false)
            scheduleRestartIfNeeded()
            return
        }

        teardownRecognitionSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        recognitionRequest = request

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            publishAvailability(false)
            scheduleRestartIfNeeded()
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            publishAvailability(false)
            teardownRecognitionSession()
            scheduleRestartIfNeeded()
            return
        }

        publishAvailability(true)

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

            if error != nil {
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
        SFSpeechRecognizer.requestAuthorization { status in
            completion(status == .authorized)
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
}
