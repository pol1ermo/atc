# ATC Transcriber

An iOS app that uses **WhisperKit Large-v3** (OpenAI's most accurate Whisper model running on-device) to transcribe Air Traffic Control (ATC) communications in real-time from microphone input.

## Features

- **Maximum accuracy transcription** powered by Whisper Large-v3 (lowest WER available)
- Real-time speech-to-text with on-device processing
- Neural Engine acceleration for fast inference
- Works completely offline after initial model download
- Hallucination filtering for cleaner output
- Timestamped transcription history
- Copy all transcriptions to clipboard
- Clean, intuitive SwiftUI interface

## Why Whisper Large-v3?

The **large-v3** model is OpenAI's most advanced and accurate speech recognition model:

- **Highest accuracy**: Lowest Word Error Rate across all Whisper models
- **Best for specialized audio**: Trained on 680,000 hours of multilingual data
- **Superior noise handling**: Excellent performance on noisy radio communications
- **Better context understanding**: Larger model captures more nuanced speech patterns

### Model Comparison

| Model | Size | Accuracy | Speed |
|-------|------|----------|-------|
| tiny | ~75MB | Good | Fastest |
| base | ~150MB | Better | Fast |
| small | ~500MB | Good | Medium |
| medium | ~1.5GB | Very Good | Slower |
| **large-v3** | **~1.5GB** | **Best** | Slower |

## Requirements

- iOS 17.0+
- Xcode 15.0+
- iPhone 12 or newer recommended (Neural Engine acceleration)
- ~1.5GB storage for Whisper large-v3 model
- Physical iPhone recommended for testing

## Permissions

The app requires:
- **Microphone**: To capture ATC audio for transcription

## Installation

1. Clone this repository
2. Open `ATCTranscriber.xcodeproj` in Xcode
3. Wait for Swift Package Manager to resolve dependencies (WhisperKit)
4. Select your development team in Signing & Capabilities
5. Build and run on your device

## Usage

1. Launch the app
2. Wait for the large-v3 model to download (first launch only, ~1.5GB)
3. Grant microphone permission when prompted
4. Tap the microphone button to start recording
5. Speak or play ATC audio near the device
6. Watch real-time transcriptions appear on screen
7. Tap the stop button to end recording
8. Use the copy button to export all transcriptions

## Architecture

- **SwiftUI** for the user interface
- **WhisperKit** with large-v3 model for on-device transcription
- **AVAudioEngine** for real-time audio capture
- **Neural Engine** acceleration for optimal performance
- **MVVM** pattern for separation of concerns

## Technical Details

### Decoding Options (Optimized for ATC)

```swift
DecodingOptions(
    temperature: 0.0,              // Greedy decoding for consistency
    temperatureFallbackCount: 5,   // Multiple fallback attempts
    noSpeechThreshold: 0.6,        // Better silence detection
    compressionRatioThreshold: 2.4 // Hallucination prevention
)
```

### Audio Processing

- 16kHz sample rate (Whisper native)
- 8-second context window for large model
- Continuous processing every 3 seconds
- Automatic hallucination filtering

## Project Structure

```
ATCTranscriber/
├── ATCTranscriberApp.swift           # App entry point
├── ContentView.swift                 # Main UI with download progress
├── Models/
│   └── Transcription.swift           # Data model
├── ViewModels/
│   └── TranscriptionViewModel.swift  # Business logic
└── Services/
    ├── WhisperKitService.swift       # Large-v3 transcription
    └── SpeechRecognitionService.swift # Apple Speech (backup)
```

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - On-device Whisper implementation for Apple Silicon

## License

MIT License
