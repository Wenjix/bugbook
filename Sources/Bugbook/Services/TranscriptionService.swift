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

struct LiveRecordingStopResult: Equatable {
    var fullText: String
    var confirmedSegments: [String]
}

enum LiveTranscriptionAudioSource: Sendable {
    case microphone
    case system

    var transcriptLabel: String {
        switch self {
        case .microphone: return "Me"
        case .system: return "Other"
        }
    }

    func labeledTranscript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\(transcriptLabel): \(trimmed)"
    }
}

enum RecordingPermissionDecision: Equatable {
    case granted
    case requestSystemPrompt
    case denied(message: String, marker: String)
}

enum RecordingPermissionPolicy {
    static let microphoneDeniedMessage =
        "Microphone access denied. Enable Bugbook in System Settings > Privacy & Security > Microphone."
    static let microphoneUnattendedProfileMessage =
        "Microphone access is not granted. Grant Microphone permission to Bugbook before running an unattended meeting profile."
    static let microphonePromptTimedOutMessage =
        "Microphone permission prompt timed out. Open System Settings > Privacy & Security > Microphone " +
        "and enable Bugbook, then start recording again."
    private static let autoStartMeetingEnvironmentKey = "BUGBOOK_PROFILE_AUTO_START_MEETING"
    private static let allowPermissionPromptEnvironmentKey = "BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT"
    private static let promptTimeoutEnvironmentKey = "BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS"

    static func shouldFailFastForProfilePermission(environment: [String: String]) -> Bool {
        truthy(environment[autoStartMeetingEnvironmentKey]) &&
            !truthy(environment[allowPermissionPromptEnvironmentKey])
    }

    static func microphoneDecision(
        authorizationStatus: AVAuthorizationStatus,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RecordingPermissionDecision {
        switch authorizationStatus {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied(message: microphoneDeniedMessage, marker: "meetingMicPermissionDenied")
        case .notDetermined:
            if shouldFailFastForProfilePermission(environment: environment) {
                return .denied(
                    message: microphoneUnattendedProfileMessage,
                    marker: "meetingMicPermissionUnavailable"
                )
            }
            return .requestSystemPrompt
        @unknown default:
            return .denied(message: microphoneDeniedMessage, marker: "meetingMicPermissionDenied")
        }
    }

    static func microphonePromptTimeoutSeconds(environment: [String: String] = ProcessInfo.processInfo.environment) -> TimeInterval {
        if let rawValue = environment[promptTimeoutEnvironmentKey],
           let timeout = TimeInterval(rawValue),
           timeout > 0 {
            return timeout
        }
        if truthy(environment[autoStartMeetingEnvironmentKey]) {
            return 20
        }
        return 60
    }

    private static func truthy(_ value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

private final class SingleResumeContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        let currentContinuation: CheckedContinuation<Value, Never>? = {
            lock.lock()
            defer { lock.unlock() }
            let current = continuation
            continuation = nil
            return current
        }()
        currentContinuation?.resume(returning: value)
    }
}

struct LiveTranscriptionChunkScheduler<Chunk> {
    private(set) var activeCount = 0
    private(set) var queuedChunks: [Chunk] = []

    private let maxActive: Int
    private let warningThreshold: Int

    init(maxActive: Int, warningThreshold: Int) {
        self.maxActive = max(1, maxActive)
        self.warningThreshold = max(1, warningThreshold)
    }

    var queuedCount: Int {
        queuedChunks.count
    }

    var pendingCount: Int {
        activeCount + queuedChunks.count
    }

    var shouldReportBackpressure: Bool {
        pendingCount >= warningThreshold
    }

    mutating func enqueue(_ chunk: Chunk) -> [Chunk] {
        queuedChunks.append(chunk)
        return drainAvailableSlots()
    }

    mutating func completeActiveChunk() -> [Chunk] {
        activeCount = max(0, activeCount - 1)
        return drainAvailableSlots()
    }

    mutating func cancelQueuedChunks() -> [Chunk] {
        let chunks = queuedChunks
        queuedChunks = []
        return chunks
    }

    mutating func reset() {
        activeCount = 0
        queuedChunks = []
    }

    private mutating func drainAvailableSlots() -> [Chunk] {
        var chunksToStart: [Chunk] = []
        while activeCount < maxActive, !queuedChunks.isEmpty {
            activeCount += 1
            chunksToStart.append(queuedChunks.removeFirst())
        }
        return chunksToStart
    }
}

struct LiveAudioCaptureMarkerState: Equatable {
    private var capturedMicrophone = false
    private var capturedSystemAudio = false

    mutating func markerName(for source: LiveTranscriptionAudioSource) -> String? {
        switch source {
        case .microphone:
            guard !capturedMicrophone else { return nil }
            capturedMicrophone = true
            return "meetingMicAudioCapture"
        case .system:
            guard !capturedSystemAudio else { return nil }
            capturedSystemAudio = true
            return "meetingSystemAudioCapture"
        }
    }

    mutating func reset() {
        capturedMicrophone = false
        capturedSystemAudio = false
    }
}

#if canImport(FluidAudio)
private actor FluidLiveTranscriptionWorker {
    private var asrManager: AsrManager?

    func prepare() async throws {
        if asrManager != nil { return }

        let models = try await AsrModels.downloadAndLoad()
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        asrManager = manager
    }

    func transcribe(_ url: URL, source: LiveTranscriptionAudioSource) async throws -> String {
        try await prepare()
        guard let asrManager else {
            throw TranscriptionError.transcriptionFailed("FluidAudio not initialized")
        }

        let text: String
        switch source {
        case .microphone:
            text = try await asrManager.transcribe(url, source: .microphone).text
        case .system:
            text = try await asrManager.transcribe(url, source: .system).text
        }
        return source.labeledTranscript(text)
    }
}

private final class FluidAudioChunkRecorder: @unchecked Sendable {
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

        try startLocked(format: format)
    }

    func appendStartingIfNeeded(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }

        if recordingFormat == nil {
            try startLocked(format: buffer.format)
        }

        guard let currentChunkFile else { return }
        try currentChunkFile.write(from: buffer)
        currentChunkFrameCount += AVAudioFramePosition(buffer.frameLength)
    }

    private func startLocked(format: AVAudioFormat) throws {
        resetLocked()
        let sessionDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("bugbook-live-transcription-\(UUID().uuidString)", isDirectory: true)
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

private enum FluidChunkOutcome: Sendable {
    case text(String)
    case empty
}

private struct FluidTranscriptionChunk: Sendable {
    let sequence: Int
    let url: URL
    let source: LiveTranscriptionAudioSource
    let sessionID: UUID
}
#endif

@MainActor
@Observable
class TranscriptionService {
    // MARK: - Live Recording State
    var currentTranscript: String = ""
    var confirmedSegments: [String] = []

    private nonisolated static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
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
    @ObservationIgnored private var systemAudioCapture: SystemAudioCapture?
    @ObservationIgnored private var systemAudioCaptureTask: Task<Void, Never>?
    @ObservationIgnored private var systemAudioFallbackNoticeShown = false
    @ObservationIgnored private var liveAudioCaptureMarkers = LiveAudioCaptureMarkerState()
    #if canImport(FluidAudio)
    @ObservationIgnored private var fluidChunkRecorder = FluidAudioChunkRecorder()
    @ObservationIgnored private var fluidSystemChunkRecorder = FluidAudioChunkRecorder()
    @ObservationIgnored private let fluidTranscriptionWorker = FluidLiveTranscriptionWorker()
    @ObservationIgnored private var fluidChunkTimer: Timer?
    @ObservationIgnored private var fluidChunkScheduler = LiveTranscriptionChunkScheduler<FluidTranscriptionChunk>(
        maxActive: 1,
        warningThreshold: 6
    )
    @ObservationIgnored private var fluidCapturingAudio = false
    @ObservationIgnored private var fluidCompletedChunkOutcomes: [Int: FluidChunkOutcome] = [:]
    @ObservationIgnored private var fluidNextChunkIndexToCommit = 0
    @ObservationIgnored private var fluidNextChunkSequence = 0
    @ObservationIgnored private var fluidBackpressureNoticeShown = false
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
        let decision = RecordingPermissionPolicy.microphoneDecision(
            authorizationStatus: AVCaptureDevice.authorizationStatus(for: .audio)
        )

        switch decision {
        case .granted:
            return true
        case .denied(let message, let marker):
            Log.profileMarker(marker)
            error = message
            return false
        case .requestSystemPrompt:
            Log.profileMarker("meetingMicPermissionPrompt")
        }

        let timeoutSeconds = RecordingPermissionPolicy.microphonePromptTimeoutSeconds()
        let promptResult = await Self.requestMicrophoneAccess(timeoutSeconds: timeoutSeconds)
        guard let granted = promptResult else {
            Log.profileMarker("meetingMicPermissionTimedOut")
            error = RecordingPermissionPolicy.microphonePromptTimedOutMessage
            return false
        }
        if !granted {
            Log.profileMarker("meetingMicPermissionDenied")
            error = RecordingPermissionPolicy.microphoneDeniedMessage
        }
        return granted
    }

    private nonisolated static func requestMicrophoneAccess(timeoutSeconds: TimeInterval) async -> Bool? {
        await withCheckedContinuation { continuation in
            let prompt = SingleResumeContinuation<Bool?>(continuation)
            let timeoutNanoseconds = UInt64(max(0.001, timeoutSeconds) * 1_000_000_000)

            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                prompt.resume(returning: nil)
            }

            AVCaptureDevice.requestAccess(for: .audio) { granted in
                prompt.resume(returning: granted)
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
        liveAudioCaptureMarkers.reset()

        let micGranted = await requestMicPermission()
        guard micGranted else {
            if error == nil {
                error = RecordingPermissionPolicy.microphoneDeniedMessage
            }
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
            stopSystemAudioCapture()
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            audioLevel = 0
        }
        #else
        let speechGranted = await requestSpeechPermission()
        guard speechGranted else {
            error = "Speech recognition permission denied. Enable Bugbook in System Settings > Privacy & Security > Speech Recognition."
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
        systemAudioFallbackNoticeShown = false

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
                self?.markLiveAudioCaptured(.microphone)
                self?.audioLevel = normalized
            }
        }
        await startSystemAudioCapture { buffer in
            request.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            stopSystemAudioCapture()
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

        stopSystemAudioCapture()
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
        stopSystemAudioCapture()
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
        return fullTranscriptText()
    }

    func stopRecordingAndWaitForFinalTranscript(timeoutSeconds: TimeInterval = 30) async -> LiveRecordingStopResult {
        let textAtStop = stopRecording()

        #if canImport(FluidAudio)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while isRecording && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }

        if isRecording {
            error = "Live transcription is still catching up. Saved the transcript captured so far."
            forceFinishFluidStopAfterTimeout()
        }
        #endif

        let finalText = firstNonEmptyTranscript([
            fullTranscriptText(),
            textAtStop,
            currentTranscript
        ])
        return LiveRecordingStopResult(
            fullText: finalText,
            confirmedSegments: confirmedSegments
        )
    }

    private func fullTranscriptText() -> String {
        firstNonEmptyTranscript([
            confirmedSegments.joined(separator: " "),
            currentTranscript
        ])
    }

    private func firstNonEmptyTranscript(_ candidates: [String]) -> String {
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private func startSystemAudioCapture(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) async {
        do {
            try await startScreenCaptureKitAudioCapture(capturesMicrophone: false) { source, buffer in
                guard source == .system else { return }
                onBuffer(buffer)
            }
        } catch {
            reportSystemAudioFallback(
                "System audio was not captured. Enable Bugbook in System Settings > Privacy & Security > Screen & System Audio Recording to include other meeting participants. Recording microphone audio only. (\(error.localizedDescription))"
            )
        }
    }

    private func startScreenCaptureKitAudioCapture(
        capturesMicrophone: Bool,
        onBuffer: @escaping @Sendable (LiveTranscriptionAudioSource, AVAudioPCMBuffer) -> Void
    ) async throws {
        stopSystemAudioCapture()

        let capture = SystemAudioCapture()
        let stream = try await capture.start(capturesMicrophone: capturesMicrophone)
        systemAudioCapture = capture
        systemAudioCaptureTask = Task.detached(priority: .userInitiated) { [weak self] in
            for await capturedAudio in stream {
                guard !Task.isCancelled else { break }
                if let marker = await MainActor.run(body: { [weak self] () -> String? in
                    guard let self else { return nil }
                    return self.liveAudioCaptureMarkers.markerName(for: capturedAudio.source)
                }) {
                    Log.profileMarker(marker)
                }
                onBuffer(capturedAudio.source, capturedAudio.buffer)

                let normalized = Self.rmsLevel(from: capturedAudio.buffer)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.audioLevel = max(self.audioLevel, normalized)
                }
            }
        }
    }

    private func stopSystemAudioCapture() {
        systemAudioCaptureTask?.cancel()
        systemAudioCaptureTask = nil

        systemAudioCapture?.stop()
        systemAudioCapture = nil
    }

    private func reportSystemAudioFallback(_ message: String) {
        Log.transcription.warning("\(message, privacy: .public)")
        guard !systemAudioFallbackNoticeShown else { return }
        systemAudioFallbackNoticeShown = true
        error = message
    }

    private func markLiveAudioCaptured(_ source: LiveTranscriptionAudioSource) {
        guard let marker = liveAudioCaptureMarkers.markerName(for: source) else { return }
        Log.profileMarker(marker)
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
        error = nil
        currentTranscript = ""
        confirmedSegments = []
        volatileText = ""
        audioLevel = 0
        systemAudioFallbackNoticeShown = false
        liveAudioCaptureMarkers.reset()

        liveRecordingSessionID = UUID()
        cleanupQueuedFluidChunks()
        fluidChunkScheduler.reset()
        fluidCapturingAudio = true
        fluidCompletedChunkOutcomes = [:]
        fluidNextChunkIndexToCommit = 0
        fluidNextChunkSequence = 0
        fluidBackpressureNoticeShown = false
        fluidChunkRecorder.reset()
        fluidSystemChunkRecorder.reset()

        if #available(macOS 15.0, *) {
            do {
                let microphoneRecorder = fluidChunkRecorder
                let systemRecorder = fluidSystemChunkRecorder
                try await startScreenCaptureKitAudioCapture(capturesMicrophone: true) { source, buffer in
                    do {
                        switch source {
                        case .microphone:
                            try microphoneRecorder.appendStartingIfNeeded(buffer)
                        case .system:
                            try systemRecorder.appendStartingIfNeeded(buffer)
                        }
                    } catch {
                        Task { @MainActor [weak self] in
                            self?.error = "Failed to write live audio chunk: \(error.localizedDescription)"
                        }
                    }
                }

                isRecording = true
                startFluidChunkTimer()
                return
            } catch {
                reportSystemAudioFallback(
                    "ScreenCaptureKit microphone capture was not available. Falling back to the microphone engine. (\(error.localizedDescription))"
                )
            }
        }

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
                self?.markLiveAudioCaptured(.microphone)
                self?.audioLevel = normalized
            }
        }
        await startSystemAudioCapture { [systemRecorder = fluidSystemChunkRecorder] buffer in
            do {
                try systemRecorder.appendStartingIfNeeded(buffer)
            } catch {
                Task { @MainActor [weak self] in
                    self?.error = "Failed to write system audio chunk: \(error.localizedDescription)"
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            stopSystemAudioCapture()
            fluidChunkRecorder.reset()
            fluidSystemChunkRecorder.reset()
            throw error
        }

        audioEngine = engine
        isRecording = true
        startFluidChunkTimer()
    }

    func prepareFluidAsrManager() async throws {
        try await fluidTranscriptionWorker.prepare()
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
        let chunks: [(url: URL, source: LiveTranscriptionAudioSource)]

        do {
            let microphoneChunkURL = final ? fluidChunkRecorder.finish() : try fluidChunkRecorder.rotateChunk()
            let systemChunkURL = final ? fluidSystemChunkRecorder.finish() : try fluidSystemChunkRecorder.rotateChunk()
            chunks = [
                microphoneChunkURL.map { ($0, .microphone) },
                systemChunkURL.map { ($0, .system) }
            ].compactMap { $0 }
        } catch {
            self.error = "Failed to finalize live audio chunk: \(error.localizedDescription)"
            if final {
                isRecording = false
                fluidChunkRecorder.reset()
                fluidSystemChunkRecorder.reset()
            } else {
                fluidChunkTimer?.invalidate()
                fluidChunkTimer = nil
            }
            return
        }

        guard !chunks.isEmpty else { return }

        for chunk in chunks {
            enqueueFluidChunkTranscription(url: chunk.url, source: chunk.source)
        }
    }

    private func reportFluidBackpressureIfNeeded() {
        guard !fluidBackpressureNoticeShown else { return }
        fluidBackpressureNoticeShown = true
        let message = "Live transcription is catching up. Audio is still recording."
        Log.transcription.warning(
            """
            \(message, privacy: .public) \
            active=\(self.fluidChunkScheduler.activeCount, privacy: .public) \
            queued=\(self.fluidChunkScheduler.queuedCount, privacy: .public)
            """
        )
        error = message
    }

    private func enqueueFluidChunkTranscription(url chunkURL: URL, source: LiveTranscriptionAudioSource) {
        let sequence = fluidNextChunkSequence
        fluidNextChunkSequence += 1
        let chunksToStart = fluidChunkScheduler.enqueue(FluidTranscriptionChunk(
            sequence: sequence,
            url: chunkURL,
            source: source,
            sessionID: liveRecordingSessionID
        ))

        if fluidChunkScheduler.shouldReportBackpressure {
            reportFluidBackpressureIfNeeded()
        }

        for chunk in chunksToStart {
            startFluidChunkTranscription(chunk)
        }
    }

    private func startFluidChunkTranscription(_ chunk: FluidTranscriptionChunk) {
        let transcriptionWorker = fluidTranscriptionWorker

        Task.detached(priority: .utility) { [weak self, transcriptionWorker, chunk] in
            guard let self else { return }

            let outcome: FluidChunkOutcome
            do {
                Log.profileMarker("liveTranscriptionChunk")
                let signpostState = Log.signpost.beginInterval("liveTranscriptionChunk")
                defer { Log.signpost.endInterval("liveTranscriptionChunk", signpostState) }

                let text = try await transcriptionWorker.transcribe(chunk.url, source: chunk.source)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                outcome = text.isEmpty ? .empty : .text(text)
            } catch {
                await MainActor.run {
                    if self.liveRecordingSessionID == chunk.sessionID {
                        self.error = "Live transcription failed: \(error.localizedDescription)"
                    }
                }
                outcome = .empty
            }

            await MainActor.run {
                self.cleanupFluidChunk(at: chunk)

                guard self.liveRecordingSessionID == chunk.sessionID else {
                    return
                }

                self.fluidCompletedChunkOutcomes[chunk.sequence] = outcome
                self.commitCompletedFluidChunks()
                let chunksToStart = self.fluidChunkScheduler.completeActiveChunk()
                for nextChunk in chunksToStart {
                    self.startFluidChunkTranscription(nextChunk)
                }
                self.completeFluidStopIfPossible()
            }
        }
    }

    private func cleanupFluidChunk(at chunk: FluidTranscriptionChunk) {
        switch chunk.source {
        case .microphone:
            fluidChunkRecorder.cleanupChunk(at: chunk.url)
        case .system:
            fluidSystemChunkRecorder.cleanupChunk(at: chunk.url)
        }
    }

    private func cleanupQueuedFluidChunks() {
        for chunk in fluidChunkScheduler.cancelQueuedChunks() {
            cleanupFluidChunk(at: chunk)
        }
    }

    func commitCompletedFluidChunks() {
        while let outcome = fluidCompletedChunkOutcomes.removeValue(forKey: fluidNextChunkIndexToCommit) {
            if case .text(let text) = outcome {
                confirmedSegments.append(text)
                currentTranscript = text
            }
            fluidNextChunkIndexToCommit += 1
        }
        volatileText = ""
    }

    func completeFluidStopIfPossible() {
        guard !fluidCapturingAudio,
              fluidChunkScheduler.activeCount == 0,
              fluidChunkScheduler.queuedChunks.isEmpty
        else { return }
        isRecording = false
        fluidCompletedChunkOutcomes.removeAll()
        fluidChunkRecorder.reset()
        fluidSystemChunkRecorder.reset()
        stopSystemAudioCapture()
    }

    private func forceFinishFluidStopAfterTimeout() {
        liveRecordingSessionID = UUID()
        fluidCapturingAudio = false
        cleanupQueuedFluidChunks()
        fluidChunkScheduler.reset()
        fluidCompletedChunkOutcomes.removeAll()
        fluidChunkRecorder.reset()
        fluidSystemChunkRecorder.reset()
        stopSystemAudioCapture()
        isRecording = false
        audioLevel = 0
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
