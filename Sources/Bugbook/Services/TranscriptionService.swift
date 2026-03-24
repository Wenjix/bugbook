import Foundation
import AVFoundation
import Speech

@MainActor
@Observable
class TranscriptionService {
    var isRecording = false
    var currentTranscript = ""
    var audioLevel: Float = 0
    var error: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else {
            error = "Speech recognition permission denied"
            return false
        }

        let micAuthorized: Bool
        if #available(macOS 14.0, *) {
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = true  // Pre-14 macOS doesn't require explicit mic permission
        }
        guard micAuthorized else {
            error = "Microphone permission denied"
            return false
        }

        return true
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }

        currentTranscript = ""
        audioLevel = 0
        error = nil

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            // Calculate RMS audio level from buffer
            let level = Self.rmsLevel(from: buffer)
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }

        do {
            try engine.start()
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.currentTranscript = result.bestTranscription.formattedString
                }
                if let error {
                    // Only surface errors that aren't just "recording stopped"
                    if self.isRecording {
                        self.error = error.localizedDescription
                    }
                }
            }
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil

        isRecording = false
        audioLevel = 0
    }

    // MARK: - Audio Level

    private static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<count {
            let sample = channelDataValue[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        // Normalize to 0...1 range (typical speech RMS is ~0.01-0.1)
        return min(rms * 10, 1.0)
    }
}
