import Foundation
import AVFoundation
import Speech

@MainActor
@Observable
class TranscriptionService {
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
    }
}
