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
    private var progressTask: Task<Void, Never>?

    @Published var isRecording = false
    @Published var isModelLoaded = false
    @Published var loadingProgress: String = "Initializing..."
    @Published var downloadProgress: Double = 0.0
    @Published var error: WhisperKitError?

    var onTranscriptionUpdate: ((String, Bool) -> Void)?

    // Audio settings optimized for speech
    private let sampleRate: Double = 16000
    private let bufferDuration: TimeInterval = 4.0
    private var lastProcessedSampleCount: Int = 0

    // Large V3 Turbo for Neural Engine - optimized for speed and quality
    private let modelName = "large-v3-turbo"

    init() {
        Task {
            await initializeWhisperKit()
        }
    }

    private func initializeWhisperKit() async {
        // Start animated progress
        startProgressAnimation()

        // First load can take 5-10 minutes for ANE compilation
        // Try loading, if fails clear cache and retry
        for attempt in 1...2 {
            do {
                if attempt == 1 {
                    loadingProgress = "Loading ATC model (first time: 5-10 min)..."
                } else {
                    loadingProgress = "Downloading ATC model..."
                }

                // Use large-v3 with Neural Engine for maximum performance
                whisperKit = try await WhisperKit(
                    model: modelName,
                    computeOptions: ModelComputeOptions(
                        audioEncoderCompute: .cpuAndNeuralEngine,
                        textDecoderCompute: .cpuAndNeuralEngine
                    ),
                    verbose: true,
                    logLevel: .debug,
                    prewarm: false,
                    load: true,
                    download: true
                )

                stopProgressAnimation()
                loadingProgress = "ATC Ready (\(modelName))"
                isModelLoaded = true
                downloadProgress = 1.0
                return // Success

            } catch {
                if attempt == 1 {
                    // First attempt failed - clear cache and retry
                    loadingProgress = "Clearing cache..."
                    await clearModelCache()
                    continue
                } else {
                    // Second attempt also failed
                    stopProgressAnimation()
                    loadingProgress = "Error: \(error.localizedDescription)"
                    self.error = .transcriptionError(error.localizedDescription)
                }
            }
        }
    }

    private func clearModelCache() async {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let huggingfaceDir = documentsURL.appendingPathComponent("huggingface")

        do {
            if fileManager.fileExists(atPath: huggingfaceDir.path) {
                try fileManager.removeItem(at: huggingfaceDir)
            }
        } catch {
            // Ignore cache clear errors
        }
    }

    private func startProgressAnimation() {
        progressTask = Task {
            var progress = 0.0

            while !Task.isCancelled && !isModelLoaded {
                // Slowly increment progress
                progress += 0.003

                // Clamp to 0.95 (leave room for final loading)
                if progress > 0.95 {
                    progress = 0.95
                }

                // Update progress bar
                await MainActor.run {
                    self.downloadProgress = progress
                }

                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
            }
        }
    }

    private func stopProgressAnimation() {
        progressTask?.cancel()
        progressTask = nil
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

        guard newSamples >= samplesNeeded / 2 else { return }

        isTranscribing = true

        let contextSamples = min(audioBuffer.count, Int(sampleRate * 8))
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
                    temperature: 0.0,
                    temperatureFallbackCount: 3,
                    sampleLength: 224,
                    usePrefillPrompt: true,
                    usePrefillCache: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: false,
                    clipTimestamps: [],
                    suppressBlank: true,
                    supressTokens: [-1],
                    compressionRatioThreshold: 2.4,
                    logProbThreshold: -0.8,
                    firstTokenLogProbThreshold: -1.5,
                    noSpeechThreshold: 0.5
                )
            )

            if let result = results.first, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                if transcribedText.count > 2 && !isLikelyNoise(transcribedText) {
                    await MainActor.run {
                        self.onTranscriptionUpdate?(transcribedText, true)
                    }
                }
            }
        } catch {
            // Silently handle transcription errors
        }

        isTranscribing = false

        let maxSamples = Int(sampleRate * 15)
        if audioBuffer.count > maxSamples {
            audioBuffer = Array(audioBuffer.suffix(maxSamples))
            lastProcessedSampleCount = audioBuffer.count
        }
    }

    private func isLikelyNoise(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let hallucinations = [
            "thank you", "thanks for watching", "subscribe",
            "like and subscribe", "see you next time", "bye",
            "music", "[music]", "(music)", "♪",
            "...", "you", "the", "and"
        ]

        // Filter very short text that's likely noise
        if text.count < 3 {
            return true
        }

        for hallucination in hallucinations {
            if lowercased == hallucination || (lowercased.contains(hallucination) && text.count < 20) {
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
