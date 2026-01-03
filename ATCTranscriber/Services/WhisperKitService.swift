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
    @Published var downloadProgress: Double = 0.0
    @Published var error: WhisperKitError?

    var onTranscriptionUpdate: ((String, Bool) -> Void)?

    // Audio settings optimized for speech
    private let sampleRate: Double = 16000
    private let bufferDuration: TimeInterval = 4.0 // Process every 4 seconds for large model
    private var lastProcessedSampleCount: Int = 0

    // Model configuration - using the most advanced model
    private let modelName = "large-v3"

    init() {
        Task {
            await initializeWhisperKit()
        }
    }

    private func initializeWhisperKit() async {
        do {
            loadingProgress = "Downloading large-v3 model (~1.5GB)..."
            downloadProgress = 0.1

            // Initialize WhisperKit with the large-v3 model for maximum accuracy
            whisperKit = try await WhisperKit(
                model: modelName,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: true
            )

            loadingProgress = "Model ready (large-v3)"
            isModelLoaded = true
            downloadProgress = 1.0
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
                // Process every 3 seconds for responsive transcription
                try? await Task.sleep(nanoseconds: UInt64(3 * 1_000_000_000))

                guard let self = self, self.isRecording else { break }

                await self.processAccumulatedAudio()
            }
        }
    }

    private func processAccumulatedAudio() async {
        guard !isTranscribing else { return }

        let samplesNeeded = Int(sampleRate * bufferDuration)
        let newSamples = audioBuffer.count - lastProcessedSampleCount

        guard newSamples >= samplesNeeded / 2 else { return } // At least 2 seconds of new audio

        isTranscribing = true

        // Get recent audio (last 8 seconds for better context with large model)
        let contextSamples = min(audioBuffer.count, Int(sampleRate * 8))
        let audioToProcess = Array(audioBuffer.suffix(contextSamples))

        lastProcessedSampleCount = audioBuffer.count

        do {
            guard let whisperKit = whisperKit else { return }

            // Optimized decoding options for large-v3 model
            let results = try await whisperKit.transcribe(
                audioArray: audioToProcess,
                decodeOptions: DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: "en",
                    temperature: 0.0,              // Greedy decoding for consistency
                    temperatureFallbackCount: 5,   // More fallback attempts for accuracy
                    sampleLength: 224,             // Full context length
                    usePrefillPrompt: true,
                    usePrefillCache: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: false,      // Enable timestamps for better segmentation
                    clipTimestamps: [],
                    suppressBlank: true,
                    supressTokens: [-1],           // Suppress end-of-text token hallucinations
                    compressionRatioThreshold: 2.4,
                    logProbThreshold: -1.0,
                    noSpeechThreshold: 0.6         // Better silence detection
                )
            )

            if let result = results.first, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Check if this is meaningful text (not just noise)
                if transcribedText.count > 2 && !isLikelyNoise(transcribedText) {
                    await MainActor.run {
                        self.onTranscriptionUpdate?(transcribedText, true)
                    }
                }
            }
        } catch {
            // Silently handle transcription errors during continuous operation
        }

        isTranscribing = false

        // Trim buffer to prevent memory issues (keep last 15 seconds for large model context)
        let maxSamples = Int(sampleRate * 15)
        if audioBuffer.count > maxSamples {
            audioBuffer = Array(audioBuffer.suffix(maxSamples))
            lastProcessedSampleCount = audioBuffer.count
        }
    }

    // Filter out likely noise/hallucinations
    private func isLikelyNoise(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Common Whisper hallucinations
        let hallucinations = [
            "thank you",
            "thanks for watching",
            "subscribe",
            "like and subscribe",
            "see you next time",
            "bye",
            "music",
            "[music]",
            "(music)",
            "♪"
        ]

        for hallucination in hallucinations {
            if lowercased.contains(hallucination) && text.count < 30 {
                return true
            }
        }

        return false
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
