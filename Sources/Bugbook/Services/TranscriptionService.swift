import Foundation
import AVFoundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// A segment of transcribed speech attributed to a speaker.
struct TranscriptSegment: Identifiable {
    let id = UUID()
    let speaker: String        // e.g. "Speaker 1"
    let text: String
    let timestamp: TimeInterval // seconds from start
}

@MainActor
@Observable
class TranscriptionService {
    // MARK: - Live Recording State
    var currentTranscript: String = ""
    var confirmedSegments: [String] = []
    var volatileText: String = ""
    var audioLevel: Float = 0
    var isRecording: Bool = false
    var error: String?

    // MARK: - File Transcription State
    var isTranscribing = false
    var progress: String = ""

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    #if canImport(FluidAudio)
    @ObservationIgnored private var streamingManager: StreamingAsrManager?
    #endif
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    private static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aac", "aiff"]

    static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Permissions

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Live Recording (FluidAudio / Whisper)

    func startRecording() async {
        guard !isRecording else { return }

        let micGranted = await requestMicPermission()
        guard micGranted else {
            error = "Microphone access denied. Enable in System Settings > Privacy > Microphone."
            return
        }

        error = nil
        currentTranscript = ""
        confirmedSegments = []
        volatileText = ""
        audioLevel = 0

        #if canImport(FluidAudio)
        // Configure chunk sizes so the total window (left + chunk + right) = 15s = 240000 samples,
        // matching the parakeet-tdt-0.6b-v3 CoreML model's fixed input shape (1 x 240000).
        // Default config uses chunkSeconds=15 + rightContext=2 = 17s = 272000 samples, which
        // exceeds the model limit and causes a shape mismatch error.
        let manager = StreamingAsrManager(config: StreamingAsrConfig(
            chunkSeconds: 11.0,
            hypothesisChunkSeconds: 1.0,
            leftContextSeconds: 2.0,
            rightContextSeconds: 2.0,
            minContextForConfirmation: 3.0,
            confirmationThreshold: 0.40
        ))
        self.streamingManager = manager

        do {
            try await manager.start(source: .microphone)
        } catch {
            self.error = "Failed to start speech recognition: \(error.localizedDescription)"
            return
        }
        #else
        self.error = "Speech recognition unavailable (FluidAudio not linked)"
        return
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            #if canImport(FluidAudio)
            Task { [weak self] in
                await self?.streamingManager?.streamAudio(buffer)
            }
            #endif

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrtf(sum / Float(max(frameCount, 1)))
            let normalized = min(1.0, rms * 10)

            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            inputNode.removeTap(onBus: 0)
            return
        }

        self.audioEngine = engine
        self.isRecording = true

        #if canImport(FluidAudio)
        updateTask = Task { [weak self] in
            guard let manager = self?.streamingManager else { return }
            for await update in await manager.transcriptionUpdates {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    let text = update.text.trimmingCharacters(in: .whitespaces)
                    if update.isConfirmed {
                        if !text.isEmpty {
                            self?.confirmedSegments.append(text)
                            self?.currentTranscript = self?.confirmedSegments.joined(separator: " ") ?? ""
                        }
                        self?.volatileText = ""
                    } else {
                        self?.volatileText = text
                    }
                }
            }
        }
        #endif
    }

    func stopRecording() -> String {
        guard isRecording else { return currentTranscript }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        audioLevel = 0

        updateTask?.cancel()
        updateTask = nil

        // Include any volatile text that never got confirmed
        if !volatileText.isEmpty {
            confirmedSegments.append(volatileText)
            currentTranscript = confirmedSegments.joined(separator: " ")
            volatileText = ""
        }

        #if canImport(FluidAudio)
        let manager = streamingManager
        streamingManager = nil
        // Fire-and-forget finalization -- transcript already captured above
        Task {
            let finalText = try? await manager?.finish()
            await MainActor.run { [weak self] in
                if let finalText, !finalText.isEmpty {
                    self?.currentTranscript = finalText
                }
            }
        }
        #endif
        return currentTranscript
    }

    // MARK: - Transcribe Audio File (FluidAudio batch)

    func transcribe(fileURL: URL) async throws -> [TranscriptSegment] {
        guard Self.isSupportedAudioFile(fileURL) else {
            throw TranscriptionError.unsupportedFormat(fileURL.pathExtension)
        }

        isTranscribing = true
        progress = "Loading model..."
        error = nil
        defer {
            isTranscribing = false
            progress = ""
        }

        #if canImport(FluidAudio)
        let models = try await AsrModels.downloadAndLoad()
        let asr = AsrManager(config: .default)
        try await asr.initialize(models: models)

        progress = "Transcribing..."
        let result = try await asr.transcribe(fileURL, source: .system)
        return [TranscriptSegment(speaker: "Speaker 1", text: result.text, timestamp: 0)]
        #else
        throw TranscriptionError.transcriptionFailed("FluidAudio not available")
        #endif
    }

    // MARK: - Format for Markdown

    static func markdownFromSegments(_ segments: [TranscriptSegment]) -> String {
        var lines: [String] = ["## Transcript", ""]
        for segment in segments {
            let minutes = Int(segment.timestamp) / 60
            let seconds = Int(segment.timestamp) % 60
            let ts = String(format: "%02d:%02d", minutes, seconds)
            lines.append("**[\(ts)] \(segment.speaker):** \(segment.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

enum TranscriptionError: LocalizedError {
    case unsupportedFormat(String)
    case modelLoadFailed
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported audio format: .\(ext). Use M4A, MP3, WAV, or CAF."
        case .modelLoadFailed:
            return "Failed to load Whisper model. Check your internet connection for first-time download."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
