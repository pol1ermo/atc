import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status indicator
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()

                    if viewModel.isModelLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Model loading overlay or transcription display
                if viewModel.isModelLoading {
                    VStack(spacing: 24) {
                        // Large model icon
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        VStack(spacing: 8) {
                            Text("WhisperKit")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Neural Engine")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // Download progress
                        VStack(spacing: 12) {
                            if viewModel.isDownloading {
                                ProgressView(value: viewModel.downloadProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(width: 250)

                                Text("\(Int(viewModel.downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ProgressView()
                                    .scaleEffect(1.2)
                            }

                            Text(viewModel.loadingStatus)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        // Model info
                        VStack(spacing: 4) {
                            Text("~1.5GB download required")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Optimized for ATC communications")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
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
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.system(size: 48))
                                            .foregroundColor(.secondary)
                                        Text("ATC Transcriber Ready")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        Text("Tap the microphone button to start transcribing Air Traffic Control communications")
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
                    .disabled(!viewModel.hasTranscriptions || viewModel.isModelLoading)

                    Spacer()

                    // Record button
                    Button(action: viewModel.toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(recordButtonColor)
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
                    .disabled(viewModel.isModelLoading)

                    Spacer()

                    // Copy button
                    Button(action: viewModel.copyAllTranscriptions) {
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                    }
                    .disabled(!viewModel.hasTranscriptions || viewModel.isModelLoading)
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
                Text("Please enable microphone access in Settings to use this app.")
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

    private var statusColor: Color {
        if viewModel.isModelLoading {
            return .orange
        } else if viewModel.isRecording {
            return .red
        } else {
            return .green
        }
    }

    private var statusText: String {
        if viewModel.isModelLoading {
            return viewModel.loadingStatus
        } else if viewModel.isRecording {
            return "Recording..."
        } else {
            return viewModel.loadingStatus
        }
    }

    private var recordButtonColor: Color {
        if viewModel.isModelLoading {
            return .gray
        } else if viewModel.isRecording {
            return .red
        } else {
            return .blue
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
