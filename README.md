# ATC Transcriber

An iOS app that uses **WhisperKit** (OpenAI's Whisper model running on-device) to transcribe Air Traffic Control (ATC) communications in real-time from microphone input.

## Features

- **High-accuracy transcription** powered by Whisper AI (2.2% WER)
- Real-time speech-to-text with on-device processing
- Works completely offline after initial model download
- Continuous recording with automatic speech detection
- Timestamped transcription history
- Copy all transcriptions to clipboard
- Clean, intuitive SwiftUI interface

## Why WhisperKit?

After researching various transcription options (Apple Speech, Deepgram, AssemblyAI, OpenAI Whisper API), WhisperKit was chosen for ATC transcription because:

- **Superior accuracy**: 2.2% Word Error Rate, excellent for specialized audio
- **Offline capability**: Critical for aviation use where connectivity may be limited
- **Privacy**: All processing happens on-device, no data leaves your phone
- **No API costs**: One-time model download, zero ongoing costs
- **Noise handling**: Whisper is trained on diverse audio including noisy environments

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Physical iPhone recommended (for microphone testing)
- ~150MB storage for Whisper base.en model

## Permissions

The app requires the following permissions:
- **Microphone**: To capture ATC audio for transcription

## Installation

1. Clone this repository
2. Open `ATCTranscriber.xcodeproj` in Xcode
3. Wait for Swift Package Manager to resolve dependencies (WhisperKit)
4. Select your development team in Signing & Capabilities
5. Build and run on your device or simulator

## Usage

1. Launch the app
2. Wait for the Whisper model to download (first launch only, ~150MB)
3. Grant microphone permission when prompted
4. Tap the microphone button to start recording
5. Speak or play ATC audio near the device
6. Watch real-time transcriptions appear on screen
7. Tap the stop button to end recording
8. Use the copy button to export all transcriptions

## Architecture

- **SwiftUI** for the user interface
- **WhisperKit** for on-device Whisper transcription
- **AVAudioEngine** for real-time audio capture
- **MVVM** pattern for separation of concerns

## Project Structure

```
ATCTranscriber/
├── ATCTranscriberApp.swift           # App entry point
├── ContentView.swift                 # Main UI
├── Models/
│   └── Transcription.swift           # Data model
├── ViewModels/
│   └── TranscriptionViewModel.swift  # Business logic
└── Services/
    ├── WhisperKitService.swift       # WhisperKit transcription
    └── SpeechRecognitionService.swift # Apple Speech (backup)
```

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - On-device Whisper implementation for Apple Silicon

## License

MIT License
