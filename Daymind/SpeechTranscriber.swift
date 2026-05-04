//
//  SpeechTranscriber.swift
//  Daymind
//
//  Created by Codex on 4.5.26.
//

import AVFoundation
import Speech

enum SpeechTranscriberError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case speechRestricted
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required to listen."
        case .speechDenied:
            "Speech recognition access is required to transcribe."
        case .speechRestricted:
            "Speech recognition is restricted on this device."
        case .recognizerUnavailable:
            "Speech recognition is not available right now."
        case .onDeviceRecognitionUnavailable:
            "On-device speech recognition is not available for this language."
        case .audioInputUnavailable:
            "No audio input is available."
        }
    }
}

final class SpeechTranscriber: NSObject {
    var onTranscriptChange: ((String) -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onRecordingEnded: (() -> Void)?

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var accumulatedTranscript = ""
    private var currentPartialTranscript = ""
    private var recognitionGeneration = 0
    private var isRecording = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    static func requestRecordingPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func start(locale: Locale = .current) async throws {
        guard await Self.requestRecordingPermission() else {
            throw SpeechTranscriberError.microphoneDenied
        }

        switch await Self.requestSpeechAuthorization() {
        case .authorized:
            break
        case .denied:
            throw SpeechTranscriberError.speechDenied
        case .restricted:
            throw SpeechTranscriberError.speechRestricted
        case .notDetermined:
            throw SpeechTranscriberError.speechDenied
        @unknown default:
            throw SpeechTranscriberError.speechDenied
        }

        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer else {
            throw SpeechTranscriberError.recognizerUnavailable
        }
        recognizer.queue = .main

        guard recognizer.isAvailable else {
            throw SpeechTranscriberError.recognizerUnavailable
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechTranscriberError.onDeviceRecognitionUnavailable
        }

        speechRecognizer = recognizer
        accumulatedTranscript = ""
        currentPartialTranscript = ""
        isRecording = true

        try configureAudioSession()
        try startAudioEngine()
        startRecognitionTask()
        scheduleRecognitionRestart()
        onStatusChange?("Listening on device.")
    }

    func stop() {
        isRecording = false
        restartTimer?.invalidate()
        restartTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        if !currentPartialTranscript.isEmpty {
            accumulatedTranscript = combinedTranscript
            currentPartialTranscript = ""
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onTranscriptChange?(accumulatedTranscript)
        onStatusChange?("Recording stopped.")
        onRecordingEnded?()
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw SpeechTranscriberError.audioInputUnavailable
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func startRecognitionTask() {
        guard let speechRecognizer else { return }

        recognitionGeneration += 1
        let generation = recognitionGeneration

        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        recognitionRequest = request
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, generation == self.recognitionGeneration else { return }

            if let result {
                self.currentPartialTranscript = result.bestTranscription.formattedString
                self.onTranscriptChange?(self.combinedTranscript)

                if result.isFinal {
                    self.accumulatedTranscript = self.combinedTranscript
                    self.currentPartialTranscript = ""
                }
            }

            if let error {
                if self.isRecording {
                    self.stop()
                }
                self.onFailure?(error)
                return
            }

            if result?.isFinal == true, self.isRecording {
                self.startRecognitionTask()
            }
        }
    }

    private func scheduleRecognitionRestart() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 55, repeats: true) { [weak self] _ in
            self?.rotateRecognitionTask()
        }
    }

    private func rotateRecognitionTask() {
        guard isRecording else { return }

        accumulatedTranscript = combinedTranscript
        currentPartialTranscript = ""
        recognitionRequest?.endAudio()
        startRecognitionTask()
        onStatusChange?("Listening on device.")
    }

    private var combinedTranscript: String {
        let partial = currentPartialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return accumulatedTranscript }
        guard !accumulatedTranscript.isEmpty else { return partial }
        return accumulatedTranscript + "\n" + partial
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard isRecording else { return }
        stop()
        onStatusChange?("Recording stopped because audio was interrupted.")
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isRecording else { return }
        onStatusChange?("Audio route changed. Still listening on device.")
    }
}
