import Foundation
import SwiftUI

@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var transcriptions: [Transcription] = []
    @Published var currentTranscription: String = ""
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var isAuthorized = false
    @Published var showingPermissionAlert = false
    @Published var isModelLoading = true
    @Published var loadingStatus: String = "Initializing..."

    private let whisperService = WhisperKitService()

    init() {
        setupWhisperService()
    }

    private func setupWhisperService() {
        whisperService.onTranscriptionUpdate = { [weak self] text, isFinal in
            Task { @MainActor in
                guard let self = self else { return }

                if isFinal {
                    if !text.isEmpty {
                        // Avoid duplicate transcriptions
                        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let lastTranscription = self.transcriptions.last {
                            // Don't add if it's the same as the last one
                            if lastTranscription.text != cleanText {
                                let transcription = Transcription(text: cleanText, isFinal: true)
                                self.transcriptions.append(transcription)
                            }
                        } else {
                            let transcription = Transcription(text: cleanText, isFinal: true)
                            self.transcriptions.append(transcription)
                        }
                    }
                    self.currentTranscription = ""
                } else {
                    self.currentTranscription = text
                }
            }
        }

        // Monitor model loading
        Task {
            while !whisperService.isModelLoaded {
                loadingStatus = whisperService.loadingProgress
                isModelLoading = true
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
            isModelLoading = false
            loadingStatus = "Ready"
        }
    }

    var isModelReady: Bool {
        whisperService.isModelLoaded
    }

    func checkPermissions() async {
        let microphoneAuthorized = await whisperService.requestMicrophoneAccess()

        isAuthorized = microphoneAuthorized

        if !isAuthorized {
            showingPermissionAlert = true
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard isAuthorized else {
            showingPermissionAlert = true
            return
        }

        guard whisperService.isModelLoaded else {
            errorMessage = "Please wait for model to finish loading"
            return
        }

        do {
            try whisperService.startRecording()
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() {
        whisperService.stopRecording()
        isRecording = false

        // Save any pending transcription
        if !currentTranscription.isEmpty {
            let transcription = Transcription(text: currentTranscription, isFinal: true)
            transcriptions.append(transcription)
            currentTranscription = ""
        }
    }

    func clearTranscriptions() {
        transcriptions.removeAll()
        currentTranscription = ""
    }

    func copyAllTranscriptions() {
        let allText = transcriptions.map { "[\($0.formattedTime)] \($0.text)" }.joined(separator: "\n")
        UIPasteboard.general.string = allText
    }

    var hasTranscriptions: Bool {
        !transcriptions.isEmpty || !currentTranscription.isEmpty
    }
}
