@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

struct CapturedAudioBuffer {
    let source: LiveTranscriptionAudioSource
    let buffer: AVAudioPCMBuffer
}

@available(macOS 14.0, *)
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let stateLock = NSLock()
    private let callbackQueue = DispatchQueue(
        label: "com.maxforsey.bugbook.system-audio-capture",
        qos: .userInteractive
    )

    private var stream: SCStream?
    private var continuation: AsyncStream<CapturedAudioBuffer>.Continuation?

    static func audioSource(for outputType: SCStreamOutputType) -> LiveTranscriptionAudioSource? {
        if outputType == .audio {
            return .system
        }
        if #available(macOS 15.0, *), outputType == .microphone {
            return .microphone
        }
        return nil
    }

    static func makeConfiguration(capturesMicrophone: Bool) throws -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        if capturesMicrophone {
            if #available(macOS 15.0, *) {
                configuration.captureMicrophone = true
            } else {
                throw CaptureError.microphoneRequiresMacOS15
            }
        }
        return configuration
    }

    func start(capturesMicrophone: Bool = false) async throws -> AsyncStream<CapturedAudioBuffer> {
        stop()

        let audioStream = AsyncStream<CapturedAudioBuffer>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            self.withStateLock {
                self.continuation = continuation
            }
        }

        do {
            let captureStream = try await makeStream(capturesMicrophone: capturesMicrophone)
            try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: callbackQueue)
            if capturesMicrophone {
                if #available(macOS 15.0, *) {
                    try captureStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: callbackQueue)
                } else {
                    throw CaptureError.microphoneRequiresMacOS15
                }
            }
            try await captureStream.startCapture()
            withStateLock {
                stream = captureStream
            }
        } catch {
            finishStream()
            throw error
        }

        return audioStream
    }

    func stop() {
        let snapshot = withStateLock {
            let snapshot = (
                stream: stream,
                continuation: continuation
            )
            stream = nil
            continuation = nil
            return snapshot
        }

        snapshot.continuation?.finish()

        guard let stream = snapshot.stream else { return }
        Task.detached(priority: .utility) {
            try? await stream.stopCapture()
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard let source = Self.audioSource(for: outputType) else {
            return
        }

        guard let pcmBuffer = Self.pcmBuffer(from: sampleBuffer) else {
            return
        }

        let currentContinuation = withStateLock { continuation }
        currentContinuation?.yield(CapturedAudioBuffer(source: source, buffer: pcmBuffer))
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        finishStream()
    }

    private func makeStream(capturesMicrophone: Bool) async throws -> SCStream {
        let shareableContent = try await SCShareableContent.current
        guard let display = shareableContent.displays.first else {
            throw CaptureError.noDisplay
        }

        let excludedApplications = shareableContent.applications.filter { application in
            application.processID == getpid()
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )

        let configuration = try Self.makeConfiguration(capturesMicrophone: capturesMicrophone)
        return SCStream(filter: filter, configuration: configuration, delegate: self)
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        var mutableStreamDescription = streamDescription.pointee
        guard let format = AVAudioFormat(streamDescription: &mutableStreamDescription) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            return nil
        }
        pcmBuffer.frameLength = frameCount

        guard copyAudio(from: sampleBuffer, format: format, to: pcmBuffer) else {
            return nil
        }

        return pcmBuffer
    }

    private static func copyAudio(
        from sampleBuffer: CMSampleBuffer,
        format: AVAudioFormat,
        to pcmBuffer: AVAudioPCMBuffer
    ) -> Bool {
        let maximumBuffers = max(1, Int(format.channelCount))
        let audioBufferList = AudioBufferList.allocate(maximumBuffers: maximumBuffers)
        defer {
            audioBufferList.unsafeMutablePointer.deallocate()
        }
        var retainedBlockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList.unsafeMutablePointer,
            bufferListSize: audioBufferListSize(maximumBuffers: maximumBuffers),
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )

        guard status == noErr else {
            return false
        }

        return withExtendedLifetime(retainedBlockBuffer) {
            let sourceBuffers = audioBufferList
            let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
            guard destinationBuffers.count == sourceBuffers.count else { return false }

            for index in 0..<sourceBuffers.count {
                let source = sourceBuffers[index]
                let destination = destinationBuffers[index]
                let byteCount = min(Int(source.mDataByteSize), Int(destination.mDataByteSize))
                guard byteCount > 0,
                      let sourceData = source.mData,
                      let destinationData = destination.mData
                else {
                    continue
                }

                memcpy(destinationData, sourceData, byteCount)
                destinationBuffers[index].mDataByteSize = UInt32(byteCount)
            }

            return true
        }
    }

    private static func audioBufferListSize(maximumBuffers: Int) -> Int {
        MemoryLayout<AudioBufferList>.size + max(0, maximumBuffers - 1) * MemoryLayout<AudioBuffer>.size
    }

    private func finishStream() {
        let currentContinuation = withStateLock {
            let current = continuation
            continuation = nil
            return current
        }
        currentContinuation?.finish()
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    enum CaptureError: LocalizedError {
        case noDisplay
        case microphoneRequiresMacOS15

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                return "No display is available for ScreenCaptureKit system audio capture."
            case .microphoneRequiresMacOS15:
                return "ScreenCaptureKit microphone capture requires macOS 15 or newer."
            }
        }
    }
}
