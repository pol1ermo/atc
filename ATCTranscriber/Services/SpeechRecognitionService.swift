import Foundation
import Speech
import AVFoundation

enum SpeechRecognitionError: Error, LocalizedError {
    case notAuthorized
    case notAvailable
    case audioEngineError
    case recognitionError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized"
        case .notAvailable:
            return "Speech recognition not available"
        case .audioEngineError:
            return "Audio engine error"
        case .recognitionError(let error):
            return "Recognition error: \(error.localizedDescription)"
        }
    }
}

@MainActor
class SpeechRecognitionService: ObservableObject {
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var isRecording = false
    @Published var error: SpeechRecognitionError?

    var onTranscriptionUpdate: ((String, Bool) -> Void)?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() throws {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.notAvailable
        }

        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.audioEngineError
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let error = error {
                    self?.error = .recognitionError(error)
                    self?.stopRecording()
                    return
                }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    self?.onTranscriptionUpdate?(text, isFinal)

                    if isFinal {
                        self?.restartRecognition()
                    }
                }
            }
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func restartRecognition() {
        // Stop current recognition
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // Remove existing tap
        audioEngine.inputNode.removeTap(onBus: 0)

        // Restart if still recording
        if isRecording {
            do {
                try startRecordingInternal()
            } catch {
                self.error = .audioEngineError
                stopRecording()
            }
        }
    }

    private func startRecordingInternal() throws {
        guard let speechRecognizer = speechRecognizer else {
            throw SpeechRecognitionError.notAvailable
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.audioEngineError
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let error = error {
                    // Ignore "no speech detected" errors during continuous recognition
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        self?.restartRecognition()
                        return
                    }
                    self?.error = .recognitionError(error)
                    self?.stopRecording()
                    return
                }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    self?.onTranscriptionUpdate?(text, isFinal)

                    if isFinal {
                        self?.restartRecognition()
                    }
                }
            }
        }

        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }
    }
}
