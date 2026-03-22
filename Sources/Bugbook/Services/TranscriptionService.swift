import Foundation
import AVFoundation
import Speech

<<<<<<< HEAD
/// Captures microphone audio and streams live transcription using on-device SFSpeechRecognizer.
@MainActor
@Observable
class TranscriptionService {
    var isRecording = false
    var currentTranscript = ""
=======
@MainActor
@Observable
class TranscriptionService {
    var currentTranscript: String = ""
    var audioLevel: Float = 0
    var isRecording: Bool = false
>>>>>>> worktree-agent-af1aa33e
    var error: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
<<<<<<< HEAD
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
=======
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

>>>>>>> worktree-agent-af1aa33e
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

<<<<<<< HEAD
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
=======
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
>>>>>>> worktree-agent-af1aa33e
        }

        do {
            engine.prepare()
            try engine.start()
<<<<<<< HEAD
            audioEngine = engine
            recognitionRequest = request
            isRecording = true
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            stopRecording()
        }
=======
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
>>>>>>> worktree-agent-af1aa33e
    }
}
