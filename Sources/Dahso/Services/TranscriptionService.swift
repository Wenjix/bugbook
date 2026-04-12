import Foundation
import AVFoundation
#if canImport(FluidAudio)
import FluidAudio
#else
import Speech
#endif

/// A segment of transcribed speech attributed to a speaker.
struct TranscriptSegment: Identifiable {
    let id = UUID()
    let speaker: String        // e.g. "Speaker 1"
    let text: String
    let timestamp: TimeInterval // seconds from start
}

#if canImport(FluidAudio)
private final class FluidAudioChunkRecorder {
    private let lock = NSLock()
    private let fileManager = FileManager.default

    private var sessionDirectoryURL: URL?
    private var recordingFormat: AVAudioFormat?
    private var currentChunkURL: URL?
    private var currentChunkFile: AVAudioFile?
    private var currentChunkFrameCount: AVAudioFramePosition = 0
    private var chunkIndex = 0

    func start(format: AVAudioFormat) throws {
        lock.lock()
        defer { lock.unlock() }

        resetLocked()

        let sessionDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("dahso-live-transcription-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)

        self.sessionDirectoryURL = sessionDirectoryURL
        self.recordingFormat = format
        try openNextChunkLocked()
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let currentChunkFile else { return }
        try currentChunkFile.write(from: buffer)
        currentChunkFrameCount += AVAudioFramePosition(buffer.frameLength)
    }

    func rotateChunk() throws -> URL? {
        lock.lock()
        defer { lock.unlock() }

        guard recordingFormat != nil else { return nil }
        let completedChunkURL = currentChunkFrameCount > 0 ? currentChunkURL : nil
        try openNextChunkLocked()
        return completedChunkURL
    }

    func finish() -> URL? {
        lock.lock()
        defer { lock.unlock() }

        let completedChunkURL = currentChunkFrameCount > 0 ? currentChunkURL : nil
        currentChunkURL = nil
        currentChunkFile = nil
        currentChunkFrameCount = 0
        recordingFormat = nil
        chunkIndex = 0
        return completedChunkURL
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        resetLocked()
    }

    func cleanupChunk(at url: URL) {
        try? fileManager.removeItem(at: url)

        lock.lock()
        defer { lock.unlock() }

        guard let sessionDirectoryURL else { return }
        if let contents = try? fileManager.contentsOfDirectory(at: sessionDirectoryURL, includingPropertiesForKeys: nil),
           contents.isEmpty {
            try? fileManager.removeItem(at: sessionDirectoryURL)
            self.sessionDirectoryURL = nil
        }
    }

    private func openNextChunkLocked() throws {
        guard let sessionDirectoryURL, let recordingFormat else { return }

        currentChunkURL = nil
        currentChunkFile = nil
        currentChunkFrameCount = 0

        let chunkURL = sessionDirectoryURL.appendingPathComponent("chunk-\(chunkIndex).caf")
        chunkIndex += 1
        currentChunkFile = try AVAudioFile(
            forWriting: chunkURL,
            settings: recordingFormat.settings,
            commonFormat: recordingFormat.commonFormat,
            interleaved: recordingFormat.isInterleaved
        )
        currentChunkURL = chunkURL
    }

    private func resetLocked() {
        currentChunkURL = nil
        currentChunkFile = nil
        currentChunkFrameCount = 0
        recordingFormat = nil
        chunkIndex = 0

        if let sessionDirectoryURL {
            try? fileManager.removeItem(at: sessionDirectoryURL)
        }
        sessionDirectoryURL = nil
    }
}

private enum FluidChunkOutcome {
    case text(String)
    case empty
}
#endif

@MainActor
@Observable
class TranscriptionService {
    // MARK: - Live Recording State
    var currentTranscript: String = ""
    var confirmedSegments: [String] = []

    private static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
        return min(1.0, sqrtf(sum / Float(max(frameCount, 1))) * 10)
    }
    var volatileText: String = ""
    var audioLevel: Float = 0
    var isRecording: Bool = false
    var error: String?

    // MARK: - File Transcription State
    var isTranscribing = false
    var progress: String = ""

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    #if canImport(FluidAudio)
    @ObservationIgnored private var fluidChunkRecorder = FluidAudioChunkRecorder()
    @ObservationIgnored private var fluidAsrManager: AsrManager?
    @ObservationIgnored private var fluidChunkTimer: Timer?
    @ObservationIgnored private var fluidPendingChunkTranscriptions = 0
    @ObservationIgnored private var fluidCapturingAudio = false
    @ObservationIgnored private var fluidCompletedChunkOutcomes: [Int: FluidChunkOutcome] = [:]
    @ObservationIgnored private var fluidNextChunkIndexToCommit = 0
    @ObservationIgnored private var fluidNextChunkSequence = 0
    @ObservationIgnored private var liveRecordingSessionID = UUID()
    #else
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    #endif

    private static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aac", "aiff"]
    #if canImport(FluidAudio)
    private let chunkDuration: TimeInterval = 5
    #endif

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

    #if !canImport(FluidAudio)
    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    #endif

    // MARK: - Live Recording

    func startRecording() async {
        guard !isRecording else { return }

        let micGranted = await requestMicPermission()
        guard micGranted else {
            error = "Microphone access denied. Enable in System Settings > Privacy > Microphone."
            return
        }

        #if canImport(FluidAudio)
        do {
            try await startFluidAudioRecording()
        } catch {
            self.error = "Failed to start live transcription: \(error.localizedDescription)"
            fluidChunkRecorder.reset()
            fluidChunkTimer?.invalidate()
            fluidChunkTimer = nil
            fluidCapturingAudio = false
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            audioLevel = 0
        }
        #else
        let speechGranted = await requestSpeechPermission()
        guard speechGranted else {
            error = "Speech recognition permission denied. Enable in System Settings > Privacy > Speech Recognition."
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            error = "Speech recognizer not available."
            return
        }

        error = nil
        currentTranscript = ""
        confirmedSegments = []
        volatileText = ""
        audioLevel = 0

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.confirmedSegments = [text]
                        self.currentTranscript = text
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                        self.currentTranscript = text
                    }
                }
                // Error code 1110 = "no speech detected" — not a real error
                if let taskError, (taskError as NSError).code != 1110 {
                    self.error = taskError.localizedDescription
                }
            }
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)

            let normalized = TranscriptionService.rmsLevel(from: buffer)
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
            recognitionRequest = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            return
        }

        self.audioEngine = engine
        self.isRecording = true
        #endif
    }

    func stopRecording() -> String {
        guard isRecording else { return currentTranscript }

        #if canImport(FluidAudio)
        fluidChunkTimer?.invalidate()
        fluidChunkTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        fluidCapturingAudio = false
        audioLevel = 0
        volatileText = ""

        flushFluidChunk(final: true)
        completeFluidStopIfPossible()
        #else
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        audioLevel = 0

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // Capture any in-progress volatile text
        if !volatileText.isEmpty {
            currentTranscript = volatileText
            confirmedSegments = [currentTranscript]
            volatileText = ""
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

#if canImport(FluidAudio)
extension TranscriptionService {
    func startFluidAudioRecording() async throws {
        _ = try await prepareFluidAsrManager()

        error = nil
        currentTranscript = ""
        confirmedSegments = []
        volatileText = ""
        audioLevel = 0

        liveRecordingSessionID = UUID()
        fluidPendingChunkTranscriptions = 0
        fluidCapturingAudio = true
        fluidCompletedChunkOutcomes = [:]
        fluidNextChunkIndexToCommit = 0
        fluidNextChunkSequence = 0
        fluidChunkRecorder.reset()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        try fluidChunkRecorder.start(format: recordingFormat)

        let recorder = fluidChunkRecorder
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            do {
                try recorder.append(buffer)
            } catch {
                Task { @MainActor [weak self] in
                    self?.error = "Failed to write live audio chunk: \(error.localizedDescription)"
                }
            }

            let normalized = TranscriptionService.rmsLevel(from: buffer)
            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            fluidChunkRecorder.reset()
            throw error
        }

        audioEngine = engine
        isRecording = true
        startFluidChunkTimer()
    }

    func prepareFluidAsrManager() async throws -> AsrManager {
        if let fluidAsrManager {
            return fluidAsrManager
        }

        let models = try await AsrModels.downloadAndLoad()
        let asrManager = AsrManager(config: .default)
        try await asrManager.initialize(models: models)
        fluidAsrManager = asrManager
        return asrManager
    }

    func startFluidChunkTimer() {
        fluidChunkTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushFluidChunk(final: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fluidChunkTimer = timer
    }

    func flushFluidChunk(final: Bool) {
        let sequence = fluidNextChunkSequence
        let chunkURL: URL?

        do {
            chunkURL = final ? fluidChunkRecorder.finish() : try fluidChunkRecorder.rotateChunk()
        } catch {
            self.error = "Failed to finalize live audio chunk: \(error.localizedDescription)"
            if final {
                isRecording = false
                fluidChunkRecorder.reset()
            } else {
                fluidChunkTimer?.invalidate()
                fluidChunkTimer = nil
            }
            return
        }

        guard let chunkURL else { return }

        fluidNextChunkSequence += 1
        fluidPendingChunkTranscriptions += 1
        let sessionID = liveRecordingSessionID

        Task { [weak self] in
            guard let self else { return }

            let outcome: FluidChunkOutcome
            do {
                let text = try await self.transcribeLiveFluidChunk(at: chunkURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                outcome = text.isEmpty ? .empty : .text(text)
            } catch {
                await MainActor.run {
                    if self.liveRecordingSessionID == sessionID {
                        self.error = "Live transcription failed: \(error.localizedDescription)"
                    }
                }
                outcome = .empty
            }

            await MainActor.run {
                self.fluidChunkRecorder.cleanupChunk(at: chunkURL)

                guard self.liveRecordingSessionID == sessionID else {
                    self.fluidPendingChunkTranscriptions = max(0, self.fluidPendingChunkTranscriptions - 1)
                    self.completeFluidStopIfPossible()
                    return
                }

                self.fluidCompletedChunkOutcomes[sequence] = outcome
                self.commitCompletedFluidChunks()
                self.fluidPendingChunkTranscriptions = max(0, self.fluidPendingChunkTranscriptions - 1)
                self.completeFluidStopIfPossible()
            }
        }
    }

    func transcribeLiveFluidChunk(at url: URL) async throws -> String {
        guard let fluidAsrManager else {
            throw TranscriptionError.transcriptionFailed("FluidAudio not initialized")
        }
        let result = try await fluidAsrManager.transcribe(url, source: .microphone)
        return result.text
    }

    func commitCompletedFluidChunks() {
        while let outcome = fluidCompletedChunkOutcomes.removeValue(forKey: fluidNextChunkIndexToCommit) {
            if case .text(let text) = outcome {
                confirmedSegments.append(text)
                currentTranscript = currentTranscript.isEmpty ? text : currentTranscript + " " + text
            }
            fluidNextChunkIndexToCommit += 1
        }
        volatileText = ""
    }

    func completeFluidStopIfPossible() {
        guard !fluidCapturingAudio, fluidPendingChunkTranscriptions == 0 else { return }
        isRecording = false
        fluidCompletedChunkOutcomes.removeAll()
        fluidChunkRecorder.reset()
    }
}
#else
extension TranscriptionService {
    func prepareFluidAsrManager() async throws {}
}
#endif

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
