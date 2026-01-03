# ATC Transcriber

An iOS app that uses Apple's Speech framework to transcribe Air Traffic Control (ATC) communications in real-time from microphone input.

## Features

- Real-time speech-to-text transcription
- Continuous recording with automatic speech detection
- Timestamped transcription history
- Copy all transcriptions to clipboard
- Clean, intuitive SwiftUI interface

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Physical iPhone recommended (for microphone testing)

## Permissions

The app requires the following permissions:
- **Microphone**: To capture ATC audio for transcription
- **Speech Recognition**: To transcribe audio to text

## Installation

1. Clone this repository
2. Open `ATCTranscriber.xcodeproj` in Xcode
3. Select your development team in Signing & Capabilities
4. Build and run on your device or simulator

## Usage

1. Launch the app
2. Grant microphone and speech recognition permissions when prompted
3. Tap the microphone button to start recording
4. Speak or play ATC audio near the device
5. Watch real-time transcriptions appear on screen
6. Tap the stop button to end recording
7. Use the copy button to export all transcriptions

## Architecture

- **SwiftUI** for the user interface
- **AVAudioEngine** for real-time audio capture
- **SFSpeechRecognizer** for speech-to-text conversion
- **MVVM** pattern for separation of concerns

## Project Structure

```
ATCTranscriber/
├── ATCTranscriberApp.swift      # App entry point
├── ContentView.swift            # Main UI
├── Models/
│   └── Transcription.swift      # Data model
├── ViewModels/
│   └── TranscriptionViewModel.swift  # Business logic
└── Services/
    └── SpeechRecognitionService.swift  # Audio & speech handling
```

## License

MIT License
