import Foundation
<<<<<<< HEAD
import AVFoundation
import Speech
=======
import Speech
import AVFoundation

/// A segment of transcribed speech attributed to a speaker.
struct TranscriptSegment: Identifiable {
    let id = UUID()
    let speaker: String        // e.g. "Speaker 1"
    let text: String
    let timestamp: TimeInterval // seconds from start
}
>>>>>>> worktree-agent-a7254eb0

@MainActor
@Observable
class TranscriptionService {
<<<<<<< HEAD
    var currentTranscript: String = ""
    var audioLevel: Float = 0
    var isRecording: Bool = false
    var error: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            error = "Microphone access denied. Enable in System Settings > Privacy > Microphone."
            return false
        }

        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else {
            error = "Speech recognition access denied. Enable in System Settings > Privacy > Speech Recognition."
            return false
        }

        return true
    }

    // MARK: - Recording

    func startRecording() async {
        guard !isRecording else { return }

        let permitted = await requestPermissions()
        guard permitted else { return }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            error = "Speech recognizer not available."
            return
        }

        error = nil
        currentTranscript = ""
        audioLevel = 0

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)

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

        let task = recognizer.recognitionTask(with: request) { [weak self] result, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.currentTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.recognitionTask = nil
                        self.recognitionRequest = nil
                    }
                }
                if let err {
                    let nsError = err as NSError
                    let isNoSpeechDetected = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110
                    if !isNoSpeechDetected {
                        self.error = err.localizedDescription
                    }
                }
            }
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.recognitionTask = task
        self.isRecording = true
    }

    func stopRecording() -> String {
        guard isRecording else { return currentTranscript }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()

        audioEngine = nil
        isRecording = false
        audioLevel = 0

        return currentTranscript
=======
    var isTranscribing = false
    var progress: String = ""
    var error: String?

    private static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aac", "aiff"]

    static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Transcribe Audio File

    /// Transcribe an audio file using SFSpeechRecognizer (on-device when possible).
    /// Returns an array of transcript segments with speaker attribution.
    func transcribe(fileURL: URL) async throws -> [TranscriptSegment] {
        guard Self.isSupportedAudioFile(fileURL) else {
            throw TranscriptionError.unsupportedFormat(fileURL.pathExtension)
        }

        // Request authorization
        let authStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        isTranscribing = true
        progress = "Transcribing..."
        error = nil
        defer {
            isTranscribing = false
            progress = ""
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        // Enable on-device recognition if available (privacy, speed)
        if #available(macOS 13, iOS 16, *) {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
        }

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                cont.resume(returning: result)
            }
        }

        // Build segments with speaker diarization
        let segments = buildSpeakerSegments(from: result)
        return segments
    }

    // MARK: - Speaker Diarization

    /// Extract speaker-attributed segments from the recognition result.
    /// SFSpeechRecognitionResult does not provide built-in speaker diarization,
    /// so we group consecutive transcription segments by detected pauses to
    /// simulate turn-taking with generic "Speaker N" labels.
    private func buildSpeakerSegments(from result: SFSpeechRecognitionResult) -> [TranscriptSegment] {
        let transcription = result.bestTranscription
        guard !transcription.segments.isEmpty else {
            return [TranscriptSegment(speaker: "Speaker 1", text: transcription.formattedString, timestamp: 0)]
        }

        // Group segments by detected pauses (> 1.5 seconds gap = new turn)
        let pauseThreshold: TimeInterval = 1.5
        var turns: [(speaker: Int, text: String, timestamp: TimeInterval)] = []
        var currentSpeaker = 1
        var currentText = ""
        var turnStart: TimeInterval = 0
        var lastEnd: TimeInterval = 0

        for segment in transcription.segments {
            let segStart = segment.timestamp
            let segEnd = segStart + segment.duration

            if !currentText.isEmpty && (segStart - lastEnd) > pauseThreshold {
                turns.append((speaker: currentSpeaker, text: currentText.trimmingCharacters(in: .whitespaces), timestamp: turnStart))
                // Alternate speakers on pause (simple heuristic)
                currentSpeaker = currentSpeaker == 1 ? 2 : 1
                currentText = ""
                turnStart = segStart
            }

            if currentText.isEmpty {
                turnStart = segStart
            }
            currentText += " " + segment.substring
            lastEnd = segEnd
        }

        // Append final turn
        if !currentText.isEmpty {
            turns.append((speaker: currentSpeaker, text: currentText.trimmingCharacters(in: .whitespaces), timestamp: turnStart))
        }

        return turns.map { turn in
            TranscriptSegment(
                speaker: "Speaker \(turn.speaker)",
                text: turn.text,
                timestamp: turn.timestamp
            )
        }
    }

    // MARK: - Format for Markdown

    /// Format transcript segments as markdown text with timestamps and speaker labels.
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
    case notAuthorized
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported audio format: .\(ext). Use M4A, MP3, WAV, or CAF."
        case .notAuthorized:
            return "Speech recognition not authorized. Grant permission in System Settings > Privacy > Speech Recognition."
        case .recognizerUnavailable:
            return "Speech recognizer is not available on this device."
        }
>>>>>>> worktree-agent-a7254eb0
    }
}
