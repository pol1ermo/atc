import Foundation
import AVFoundation
import WhisperKit

enum WhisperKitError: Error, LocalizedError {
    case notInitialized
    case modelNotLoaded
    case audioError
    case transcriptionError(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "WhisperKit not initialized"
        case .modelNotLoaded:
            return "Model not loaded"
        case .audioError:
            return "Audio capture error"
        case .transcriptionError(let message):
            return "Transcription error: \(message)"
        }
    }
}

@MainActor
class WhisperKitService: ObservableObject {
    private var whisperKit: WhisperKit?
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var isTranscribing = false
    private var transcriptionTask: Task<Void, Never>?

    @Published var isRecording = false
    @Published var isModelLoaded = false
    @Published var loadingProgress: String = "Initializing..."
    @Published var error: WhisperKitError?

    var onTranscriptionUpdate: ((String, Bool) -> Void)?

    // Audio settings optimized for speech
    private let sampleRate: Double = 16000
    private let bufferDuration: TimeInterval = 3.0 // Process every 3 seconds
    private var lastProcessedSampleCount: Int = 0

    init() {
        Task {
            await initializeWhisperKit()
        }
    }

    private func initializeWhisperKit() async {
        do {
            loadingProgress = "Downloading model..."

            // Use base.en model for best balance of speed and accuracy
            // Options: tiny, tiny.en, base, base.en, small, small.en, medium, medium.en, large-v2, large-v3
            whisperKit = try await WhisperKit(
                model: "base.en",
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: true
            )

            loadingProgress = "Model ready"
            isModelLoaded = true
        } catch {
            loadingProgress = "Failed to load model"
            self.error = .transcriptionError(error.localizedDescription)
        }
    }

    func startRecording() throws {
        guard isModelLoaded, whisperKit != nil else {
            throw WhisperKitError.notInitialized
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create converter to 16kHz mono
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw WhisperKitError.audioError
        }

        // Reset buffer
        audioBuffer.removeAll()
        lastProcessedSampleCount = 0

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        startContinuousTranscription()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { return }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let channelData = convertedBuffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))
            DispatchQueue.main.async { [weak self] in
                self?.audioBuffer.append(contentsOf: samples)
            }
        }
    }

    private func startContinuousTranscription() {
        transcriptionTask = Task { [weak self] in
            while self?.isRecording == true {
                try? await Task.sleep(nanoseconds: UInt64(2 * 1_000_000_000)) // Every 2 seconds

                guard let self = self, self.isRecording else { break }

                await self.processAccumulatedAudio()
            }
        }
    }

    private func processAccumulatedAudio() async {
        guard !isTranscribing else { return }

        let samplesNeeded = Int(sampleRate * bufferDuration)
        let newSamples = audioBuffer.count - lastProcessedSampleCount

        guard newSamples >= samplesNeeded / 2 else { return } // At least 1.5 seconds of new audio

        isTranscribing = true

        // Get recent audio (last 5 seconds for context)
        let contextSamples = min(audioBuffer.count, Int(sampleRate * 5))
        let audioToProcess = Array(audioBuffer.suffix(contextSamples))

        lastProcessedSampleCount = audioBuffer.count

        do {
            guard let whisperKit = whisperKit else { return }

            let results = try await whisperKit.transcribe(
                audioArray: audioToProcess,
                decodeOptions: DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: "en",
                    temperatureFallbackCount: 3,
                    sampleLength: 224,
                    usePrefillPrompt: true,
                    usePrefillCache: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: true,
                    suppressBlank: true
                )
            )

            if let result = results.first, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Check if this is meaningful text (not just noise)
                if transcribedText.count > 2 {
                    await MainActor.run {
                        self.onTranscriptionUpdate?(transcribedText, true)
                    }
                }
            }
        } catch {
            // Silently handle transcription errors during continuous operation
        }

        isTranscribing = false

        // Trim buffer to prevent memory issues (keep last 10 seconds)
        let maxSamples = Int(sampleRate * 10)
        if audioBuffer.count > maxSamples {
            audioBuffer = Array(audioBuffer.suffix(maxSamples))
            lastProcessedSampleCount = audioBuffer.count
        }
    }

    func stopRecording() {
        transcriptionTask?.cancel()
        transcriptionTask = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        isTranscribing = false

        // Process any remaining audio
        Task {
            if !audioBuffer.isEmpty {
                await processAccumulatedAudio()
            }
            audioBuffer.removeAll()
            lastProcessedSampleCount = 0
        }

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
