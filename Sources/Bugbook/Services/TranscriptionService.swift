import Foundation
import Speech
import AVFoundation

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
    }
}
