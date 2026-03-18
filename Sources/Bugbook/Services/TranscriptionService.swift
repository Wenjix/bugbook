@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import CoreMedia
import FluidAudio
import os

// MARK: - Models

enum TranscriptionSpeaker: String, Codable, Sendable {
    case mic
    case system
}

struct TranscriptionSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    let speaker: TranscriptionSpeaker
    let timestamp: Date

    init(text: String, speaker: TranscriptionSpeaker, timestamp: Date = .now) {
        self.id = UUID()
        self.text = text
        self.speaker = speaker
        self.timestamp = timestamp
    }
}

// MARK: - Model Download State

enum ModelDownloadState: Sendable {
    case notStarted
    case downloading(progress: Double)
    case ready
    case failed(String)
}

// MARK: - TranscriptionService

/// Dual-stream transcription service using FluidAudio (Parakeet-TDT v2 ASR + Silero VAD).
/// Captures mic via AVAudioEngine and system audio via ScreenCaptureKit, runs VAD to filter
/// silence, and emits streaming partial results every ~3 seconds.
@MainActor
@Observable
final class TranscriptionService {
    // MARK: - Public State

    private(set) var isRecording = false
    private(set) var modelState: ModelDownloadState = .notStarted
    private(set) var segments: [TranscriptionSegment] = []
    private(set) var lastError: String?

    // MARK: - Private

    private var asrManager: AsrManager?
    private var vadManager: VadManager?

    private var micTask: Task<Void, Never>?
    private var systemTask: Task<Void, Never>?

    private let micCapture = MicAudioCapture()
    private let systemCapture = SystemAudioCapture()

    // MARK: - Lifecycle

    /// Load ASR + VAD models. Call once at app launch or before first recording.
    /// Safe to call multiple times — returns immediately if already loaded.
    func loadModels() async {
        switch modelState {
        case .notStarted, .failed:
            break // proceed to load
        case .downloading, .ready:
            return // already loading or loaded
        }

        modelState = .downloading(progress: 0.0)
        Log.transcription.info("Loading FluidAudio ASR models...")

        do {
            modelState = .downloading(progress: 0.1)
            let models = try await AsrModels.downloadAndLoad(version: .v2)
            modelState = .downloading(progress: 0.7)

            let asr = AsrManager(config: .default)
            try await asr.initialize(models: models)
            self.asrManager = asr
            modelState = .downloading(progress: 0.9)

            let vad = try await VadManager()
            self.vadManager = vad

            modelState = .ready
            Log.transcription.info("FluidAudio models loaded successfully")
        } catch {
            let msg = "Model load failed: \(error.localizedDescription)"
            Log.transcription.error("\(msg)")
            modelState = .failed(msg)
            lastError = msg
        }
    }

    // MARK: - Recording

    func startRecording() async {
        guard !isRecording else { return }
        lastError = nil

        // Ensure models are loaded
        switch modelState {
        case .notStarted, .failed: await loadModels()
        default: break
        }
        guard case .ready = modelState else {
            lastError = "Models not ready"
            return
        }
        guard let asrManager, let vadManager else { return }

        // Check mic permission
        guard await ensureMicPermission() else { return }

        isRecording = true
        segments.removeAll()

        // Start mic stream
        let micStream = micCapture.startCapture()
        let micTranscriber = StreamingTranscriberWorker(
            asrManager: asrManager,
            vadManager: vadManager,
            speaker: .mic,
            onSegment: { [weak self] text in
                Task { @MainActor in
                    self?.segments.append(TranscriptionSegment(text: text, speaker: .mic))
                }
            }
        )
        micTask = Task.detached {
            await micTranscriber.run(stream: micStream)
        }

        // Start system audio stream
        do {
            let sysStream = try await systemCapture.startCapture()
            let sysTranscriber = StreamingTranscriberWorker(
                asrManager: asrManager,
                vadManager: vadManager,
                speaker: .system,
                onSegment: { [weak self] text in
                    Task { @MainActor in
                        self?.segments.append(TranscriptionSegment(text: text, speaker: .system))
                    }
                }
            )
            systemTask = Task.detached {
                await sysTranscriber.run(stream: sysStream)
            }
        } catch {
            let msg = "System audio capture failed: \(error.localizedDescription)"
            Log.transcription.error("\(msg)")
            lastError = msg
            // Continue with mic-only — system audio failure is not fatal
        }

        Log.transcription.info("Recording started")
    }

    func stopRecording() -> [TranscriptionSegment] {
        micTask?.cancel()
        systemTask?.cancel()
        micTask = nil
        systemTask = nil

        micCapture.stopCapture()
        Task { await systemCapture.stopCapture() }

        isRecording = false

        Log.transcription.info("Recording stopped, \(self.segments.count) segments")
        return segments
    }

    // MARK: - Mic Permission

    private func ensureMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                lastError = "Microphone access denied. Enable in System Settings > Privacy & Security > Microphone."
            }
            return granted
        case .denied, .restricted:
            lastError = "Microphone access disabled. Enable in System Settings > Privacy & Security > Microphone."
            return false
        @unknown default:
            lastError = "Unable to verify microphone permission."
            return false
        }
    }
}

// MARK: - Mic Audio Capture (AVAudioEngine)

private final class MicAudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()

    func startCapture() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            guard format.sampleRate > 0, format.channelCount > 0 else {
                Log.transcription.error("Invalid mic format: sr=\(format.sampleRate) ch=\(format.channelCount)")
                continuation.finish()
                return
            }

            guard let tapFormat = AVAudioFormat(
                standardFormatWithSampleRate: format.sampleRate,
                channels: format.channelCount
            ) else {
                continuation.finish()
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
                continuation.yield(buffer)
            }

            continuation.onTermination = { [engine] _ in
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }

            do {
                engine.prepare()
                try engine.start()
            } catch {
                Log.transcription.error("Mic engine start failed: \(error.localizedDescription)")
                continuation.finish()
            }
        }
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

// MARK: - System Audio Capture (ScreenCaptureKit)

private final class SystemAudioCapture: NSObject, @unchecked Sendable, SCStreamDelegate, SCStreamOutput {
    private let _stream = OSAllocatedUnfairLock<SCStream?>(uncheckedState: nil)
    private let _continuation = OSAllocatedUnfairLock<AsyncStream<AVAudioPCMBuffer>.Continuation?>(uncheckedState: nil)

    func startCapture() async throws -> AsyncStream<AVAudioPCMBuffer> {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.channelCount = 1
        config.sampleRate = 48000

        // Minimal video — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        let stream = AsyncStream<AVAudioPCMBuffer> { cont in
            self._continuation.withLock { $0 = cont }
        }

        _stream.withLock { $0 = scStream }
        try await scStream.startCapture()

        return stream
    }

    func stopCapture() async {
        try? await _stream.withLock { $0 }?.stopCapture()
        _stream.withLock { $0 = nil }
        _continuation.withLock { $0?.finish(); $0 = nil }
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let formatDesc = sampleBuffer.formatDescription,
              var asbd = formatDesc.audioStreamBasicDescription else { return }
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return }

        _ = _continuation.withLock { $0?.yield(pcmBuffer) }
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Log.transcription.error("System audio stream stopped: \(error.localizedDescription)")
        _continuation.withLock { $0?.finish(); $0 = nil }
    }

    enum CaptureError: Error, LocalizedError {
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display found for screen capture"
            }
        }
    }
}

// MARK: - Streaming Transcriber Worker (VAD + ASR pipeline)

/// Consumes an audio buffer stream, detects speech via Silero VAD,
/// and transcribes completed speech segments via Parakeet-TDT.
private final class StreamingTranscriberWorker: @unchecked Sendable {
    private let asrManager: AsrManager
    private let vadManager: VadManager
    private let speaker: TranscriptionSpeaker
    private let onSegment: @Sendable (String) -> Void

    /// Resampler from source format to 16kHz mono Float32.
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Silero VAD expects chunks of 4096 samples (256ms at 16kHz).
    private static let vadChunkSize = 4096
    /// Flush speech for transcription every ~3 seconds (48,000 samples at 16kHz).
    private static let flushInterval = 48_000

    init(
        asrManager: AsrManager,
        vadManager: VadManager,
        speaker: TranscriptionSpeaker,
        onSegment: @escaping @Sendable (String) -> Void
    ) {
        self.asrManager = asrManager
        self.vadManager = vadManager
        self.speaker = speaker
        self.onSegment = onSegment
    }

    /// Main loop: reads audio buffers, runs VAD, transcribes speech segments.
    func run(stream: AsyncStream<AVAudioPCMBuffer>) async {
        var vadState = await vadManager.makeStreamState()
        var speechSamples: [Float] = []
        var vadBuffer: [Float] = []
        var isSpeaking = false

        for await buffer in stream {
            guard let samples = extractSamples(buffer) else { continue }

            vadBuffer.append(contentsOf: samples)

            while vadBuffer.count >= Self.vadChunkSize {
                let chunk = Array(vadBuffer.prefix(Self.vadChunkSize))
                vadBuffer.removeFirst(Self.vadChunkSize)

                do {
                    let result = try await vadManager.processStreamingChunk(
                        chunk,
                        state: vadState,
                        config: .default,
                        returnSeconds: true,
                        timeResolution: 2
                    )
                    vadState = result.state

                    if let event = result.event {
                        switch event.kind {
                        case .speechStart:
                            isSpeaking = true
                            speechSamples.removeAll(keepingCapacity: true)

                        case .speechEnd:
                            isSpeaking = false
                            if speechSamples.count > 8000 {
                                await transcribeSegment(speechSamples)
                            }
                            speechSamples.removeAll(keepingCapacity: true)
                        }
                    }

                    if isSpeaking {
                        speechSamples.append(contentsOf: chunk)

                        // Flush every ~3s for streaming results
                        if speechSamples.count >= Self.flushInterval {
                            await transcribeSegment(speechSamples)
                            speechSamples.removeAll(keepingCapacity: true)
                        }
                    }
                } catch {
                    Log.transcription.error("VAD error [\(self.speaker.rawValue)]: \(error.localizedDescription)")
                }
            }
        }

        // Flush remaining speech at stream end
        if speechSamples.count > 8000 {
            await transcribeSegment(speechSamples)
        }
    }

    private func transcribeSegment(_ samples: [Float]) async {
        do {
            let result = try await asrManager.transcribe(samples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Log.transcription.info("[\(self.speaker.rawValue)] transcribed: \(text.prefix(80))")
            onSegment(text)
        } catch {
            Log.transcription.error("ASR error [\(self.speaker.rawValue)]: \(error.localizedDescription)")
        }
    }

    /// Extract [Float] samples from an AVAudioPCMBuffer, resampling to 16kHz mono if needed.
    private func extractSamples(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        // Fast path: already Float32 at 16kHz
        if sourceFormat.commonFormat == .pcmFormatFloat32, sourceFormat.sampleRate == 16000 {
            guard let channelData = buffer.floatChannelData else { return nil }
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        // Resample via AVAudioConverter
        if converter == nil || converter?.inputFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrames
        ) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            Log.transcription.error("Resample error: \(error.localizedDescription)")
            return nil
        }

        guard let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))
    }
}
