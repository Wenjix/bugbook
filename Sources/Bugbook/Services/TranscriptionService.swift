import Foundation
import AVFoundation
import Speech

/// Captures microphone audio and streams live transcription using on-device SFSpeechRecognizer.
@MainActor
@Observable
class TranscriptionService {
    var isRecording = false
    var currentTranscript = ""
    var error: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?

    // MARK: - Lifecycle

    func loadModels() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func startRecording() {
        guard !isRecording else { return }
        error = nil
        currentTranscript = ""

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognition is not available on this device."
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginAudioSession()
                case .denied, .restricted:
                    self.error = "Microphone or speech recognition permission denied. Check System Settings > Privacy."
                case .notDetermined:
                    self.error = "Speech recognition authorization not determined."
                @unknown default:
                    self.error = "Unknown speech recognition authorization status."
                }
            }
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    // MARK: - Private

    private func beginAudioSession() {
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        guard let speechRecognizer else {
            error = "Speech recognizer not initialized."
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, err in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.currentTranscript = result.bestTranscription.formattedString
                }
                if let err, (err as NSError).code != 216 /* cancelled */ {
                    self.error = err.localizedDescription
                }
                if result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            audioEngine = engine
            recognitionRequest = request
            isRecording = true
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            stopRecording()
        }
    }
}
