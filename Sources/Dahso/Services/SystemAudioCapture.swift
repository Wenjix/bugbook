@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

@available(macOS 14.2, *)
final class SystemAudioCapture: @unchecked Sendable {
    private let stateLock = NSLock()
    private let callbackQueue = DispatchQueue(
        label: "com.maxforsey.dahso.system-audio-capture",
        qos: .userInteractive
    )

    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        stop()

        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.withStateLock {
                self.continuation = continuation
            }
        }

        do {
            try startCoreAudioTap()
        } catch {
            finishStream()
            throw error
        }

        return stream
    }

    func stop() {
        let snapshot = withStateLock {
            let snapshot = (
                aggregateDeviceID: aggregateDeviceID,
                tapID: tapID,
                ioProcID: ioProcID,
                continuation: continuation
            )
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            tapID = AudioObjectID(kAudioObjectUnknown)
            ioProcID = nil
            continuation = nil
            return snapshot
        }

        snapshot.continuation?.finish()

        if snapshot.aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            if let ioProcID = snapshot.ioProcID {
                _ = AudioDeviceStop(snapshot.aggregateDeviceID, ioProcID)
                _ = AudioDeviceDestroyIOProcID(snapshot.aggregateDeviceID, ioProcID)
            }
            _ = AudioHardwareDestroyAggregateDevice(snapshot.aggregateDeviceID)
        }

        if snapshot.tapID != AudioObjectID(kAudioObjectUnknown) {
            _ = AudioHardwareDestroyProcessTap(snapshot.tapID)
        }
    }

    private func startCoreAudioTap() throws {
        let outputDeviceID = try Self.defaultOutputDeviceID()
        let outputDeviceUID = try Self.deviceUID(for: outputDeviceID)
        let excludedProcessIDs = Self.currentProcessObjectID().map { [$0] } ?? []
        let tapUUID = UUID()

        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: excludedProcessIDs)
        tapDescription.name = "Dahso System Audio"
        tapDescription.uuid = tapUUID
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted
        tapDescription.deviceUID = outputDeviceUID
        tapDescription.stream = 0

        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard status == noErr else {
            throw CaptureError.tapCreationFailed(status)
        }

        do {
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Dahso System Audio",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [
                        kAudioSubDeviceUIDKey: outputDeviceUID,
                        kAudioSubDeviceInputChannelsKey: []
                    ]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: tapUUID.uuidString,
                        kAudioSubTapDriftCompensationKey: true
                    ]
                ]
            ]

            var createdAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &createdAggregateDeviceID
            )
            guard status == noErr else {
                throw CaptureError.aggregateDeviceCreationFailed(status)
            }

            do {
                let streamDescription = try Self.tapStreamDescription(for: createdTapID)
                var mutableStreamDescription = streamDescription
                guard let format = AVAudioFormat(streamDescription: &mutableStreamDescription) else {
                    throw CaptureError.invalidTapFormat
                }

                var createdIOProcID: AudioDeviceIOProcID?
                status = AudioDeviceCreateIOProcIDWithBlock(
                    &createdIOProcID,
                    createdAggregateDeviceID,
                    callbackQueue
                ) { [weak self] _, inputData, _, _, _ in
                    self?.handleInputData(inputData, format: format)
                }
                guard status == noErr, let createdIOProcID else {
                    throw CaptureError.ioProcCreationFailed(status)
                }

                status = AudioDeviceStart(createdAggregateDeviceID, createdIOProcID)
                guard status == noErr else {
                    _ = AudioDeviceDestroyIOProcID(createdAggregateDeviceID, createdIOProcID)
                    throw CaptureError.startFailed(status)
                }

                withStateLock {
                    aggregateDeviceID = createdAggregateDeviceID
                    tapID = createdTapID
                    ioProcID = createdIOProcID
                }
            } catch {
                _ = AudioHardwareDestroyAggregateDevice(createdAggregateDeviceID)
                throw error
            }
        } catch {
            _ = AudioHardwareDestroyProcessTap(createdTapID)
            throw error
        }
    }

    private func handleInputData(
        _ inputData: UnsafePointer<AudioBufferList>,
        format: AVAudioFormat
    ) {
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )

        guard let firstBuffer = sourceBuffers.first else { return }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }

        let frameCount = AVAudioFrameCount(Int(firstBuffer.mDataByteSize) / bytesPerFrame)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            return
        }

        pcmBuffer.frameLength = frameCount

        let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        guard destinationBuffers.count == sourceBuffers.count else { return }

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

        let currentContinuation = withStateLock { continuation }
        currentContinuation?.yield(pcmBuffer)
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

    private static func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    private static func currentProcessObjectID() -> AudioObjectID? {
        var pid = getpid()
        var address = propertyAddress(selector: kAudioHardwarePropertyTranslatePIDToProcessObject)
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &dataSize,
                &processObjectID
            )
        }

        guard status == noErr, processObjectID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }
        return processObjectID
    }

    private static func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = propertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            throw CaptureError.noOutputDevice
        }
        return deviceID
    }

    private static func deviceUID(for deviceID: AudioDeviceID) throws -> String {
        var address = propertyAddress(selector: kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &uid
        )

        guard status == noErr, let uid else {
            throw CaptureError.outputDeviceUIDUnavailable(status)
        }
        return uid.takeUnretainedValue() as String
    }

    private static func tapStreamDescription(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = propertyAddress(selector: kAudioTapPropertyFormat)
        var streamDescription = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioObjectGetPropertyData(
            tapID,
            &address,
            0,
            nil,
            &dataSize,
            &streamDescription
        )

        guard status == noErr else {
            throw CaptureError.tapFormatUnavailable(status)
        }
        return streamDescription
    }

    enum CaptureError: LocalizedError {
        case noOutputDevice
        case outputDeviceUIDUnavailable(OSStatus)
        case tapCreationFailed(OSStatus)
        case aggregateDeviceCreationFailed(OSStatus)
        case tapFormatUnavailable(OSStatus)
        case invalidTapFormat
        case ioProcCreationFailed(OSStatus)
        case startFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .noOutputDevice:
                return "No audio output device is currently available."
            case .outputDeviceUIDUnavailable(let status):
                return "Unable to inspect the system output device (OSStatus \(status))."
            case .tapCreationFailed(let status):
                return "System audio capture could not start. Enable System Audio Recording for Dahso in System Settings > Privacy & Security (OSStatus \(status))."
            case .aggregateDeviceCreationFailed(let status):
                return "Unable to create the Core Audio aggregate device (OSStatus \(status))."
            case .tapFormatUnavailable(let status):
                return "Unable to inspect the system audio tap format (OSStatus \(status))."
            case .invalidTapFormat:
                return "System audio capture produced an unsupported audio format."
            case .ioProcCreationFailed(let status):
                return "Unable to create the system audio IO callback (OSStatus \(status))."
            case .startFailed(let status):
                return "Unable to start system audio capture (OSStatus \(status))."
            }
        }
    }
}
