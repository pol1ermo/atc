import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status indicator
                HStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(viewModel.isRecording ? "Recording..." : "Ready")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Transcription display
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.transcriptions) { transcription in
                                TranscriptionRow(transcription: transcription)
                                    .id(transcription.id)
                            }

                            // Current (partial) transcription
                            if !viewModel.currentTranscription.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)

                                    Text(viewModel.currentTranscription)
                                        .font(.body)
                                        .foregroundColor(.primary.opacity(0.7))
                                        .italic()
                                }
                                .padding(.horizontal)
                                .id("current")
                            }

                            if !viewModel.hasTranscriptions && !viewModel.isRecording {
                                VStack(spacing: 16) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    Text("Tap the microphone button to start transcribing ATC communications")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: viewModel.transcriptions.count) { _, _ in
                        if let lastId = viewModel.transcriptions.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.currentTranscription) { _, _ in
                        if !viewModel.currentTranscription.isEmpty {
                            withAnimation {
                                proxy.scrollTo("current", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Control buttons
                HStack(spacing: 20) {
                    // Clear button
                    Button(action: viewModel.clearTranscriptions) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                    }
                    .disabled(!viewModel.hasTranscriptions)

                    Spacer()

                    // Record button
                    Button(action: viewModel.toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(viewModel.isRecording ? Color.red : Color.blue)
                                .frame(width: 72, height: 72)

                            if viewModel.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                        }
                    }

                    Spacer()

                    // Copy button
                    Button(action: viewModel.copyAllTranscriptions) {
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                    }
                    .disabled(!viewModel.hasTranscriptions)
                }
                .padding()
            }
            .navigationTitle("ATC Transcriber")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.checkPermissions()
            }
            .alert("Permissions Required", isPresented: $viewModel.showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable microphone and speech recognition access in Settings to use this app.")
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
}

struct TranscriptionRow: View {
    let transcription: Transcription

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(transcription.formattedTime)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(transcription.text)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
}
