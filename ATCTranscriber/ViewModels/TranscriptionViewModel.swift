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

    private let speechService = SpeechRecognitionService()

    init() {
        setupSpeechService()
    }

    private func setupSpeechService() {
        speechService.onTranscriptionUpdate = { [weak self] text, isFinal in
            Task { @MainActor in
                guard let self = self else { return }

                if isFinal {
                    if !text.isEmpty {
                        let transcription = Transcription(text: text, isFinal: true)
                        self.transcriptions.append(transcription)
                    }
                    self.currentTranscription = ""
                } else {
                    self.currentTranscription = text
                }
            }
        }
    }

    func checkPermissions() async {
        let speechAuthorized = await speechService.requestAuthorization()
        let microphoneAuthorized = await speechService.requestMicrophoneAccess()

        isAuthorized = speechAuthorized && microphoneAuthorized

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

        do {
            try speechService.startRecording()
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() {
        speechService.stopRecording()
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
