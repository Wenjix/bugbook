import XCTest
import ScreenCaptureKit
@testable import Bugbook

@MainActor
final class TranscriptionServiceTests: XCTestCase {
    @available(macOS 14.0, *)
    func testSystemAudioCaptureMapsScreenCaptureKitOutputSources() {
        XCTAssertEqual(SystemAudioCapture.audioSource(for: .audio), .system)

        if #available(macOS 15.0, *) {
            XCTAssertEqual(SystemAudioCapture.audioSource(for: .microphone), .microphone)
        }
    }

    @available(macOS 14.0, *)
    func testSystemAudioCaptureConfigurationUsesAudioOnlyStreamDefaults() throws {
        let configuration = try SystemAudioCapture.makeConfiguration(capturesMicrophone: false)

        XCTAssertEqual(configuration.width, 2)
        XCTAssertEqual(configuration.height, 2)
        XCTAssertEqual(configuration.minimumFrameInterval, CMTime(value: 1, timescale: 1))
        XCTAssertEqual(configuration.queueDepth, 1)
        XCTAssertFalse(configuration.showsCursor)
        XCTAssertTrue(configuration.capturesAudio)
        XCTAssertTrue(configuration.excludesCurrentProcessAudio)
        XCTAssertEqual(configuration.sampleRate, 48_000)
        XCTAssertEqual(configuration.channelCount, 2)
        if #available(macOS 15.0, *) {
            XCTAssertFalse(configuration.captureMicrophone)
        }
    }

    @available(macOS 14.0, *)
    func testSystemAudioCaptureConfigurationRequiresMacOS15ForScreenCaptureKitMicrophone() throws {
        if #available(macOS 15.0, *) {
            let configuration = try SystemAudioCapture.makeConfiguration(capturesMicrophone: true)
            XCTAssertTrue(configuration.captureMicrophone)
        } else {
            XCTAssertThrowsError(try SystemAudioCapture.makeConfiguration(capturesMicrophone: true)) { error in
                XCTAssertEqual(error as? SystemAudioCapture.CaptureError, .microphoneRequiresMacOS15)
            }
        }
    }

    func testMicrophonePermissionPolicyAllowsAuthorizedCapture() {
        let decision = RecordingPermissionPolicy.microphoneDecision(
            authorizationStatus: AVAuthorizationStatus.authorized,
            environment: ["BUGBOOK_PROFILE_AUTO_START_MEETING": "1"]
        )

        XCTAssertEqual(decision, RecordingPermissionDecision.granted)
    }

    func testMicrophonePermissionPolicyPromptsDuringInteractiveStart() {
        let decision = RecordingPermissionPolicy.microphoneDecision(
            authorizationStatus: AVAuthorizationStatus.notDetermined,
            environment: [:]
        )

        XCTAssertEqual(decision, RecordingPermissionDecision.requestSystemPrompt)
    }

    func testMicrophonePermissionPolicyFailsFastDuringUnattendedProfile() {
        let decision = RecordingPermissionPolicy.microphoneDecision(
            authorizationStatus: AVAuthorizationStatus.notDetermined,
            environment: ["BUGBOOK_PROFILE_AUTO_START_MEETING": "1"]
        )

        XCTAssertEqual(
            decision,
            RecordingPermissionDecision.denied(
                message: RecordingPermissionPolicy.microphoneUnattendedProfileMessage,
                marker: "meetingMicPermissionUnavailable"
            )
        )
    }

    func testMicrophonePermissionPolicyRejectsDeniedAccess() {
        let decision = RecordingPermissionPolicy.microphoneDecision(
            authorizationStatus: AVAuthorizationStatus.denied,
            environment: [:]
        )

        XCTAssertEqual(
            decision,
            RecordingPermissionDecision.denied(
                message: RecordingPermissionPolicy.microphoneDeniedMessage,
                marker: "meetingMicPermissionDenied"
            )
        )
    }

    func testMicrophonePermissionPolicyCanAllowProfilePermissionPrompt() {
        let decision = RecordingPermissionPolicy.microphoneDecision(
            authorizationStatus: AVAuthorizationStatus.notDetermined,
            environment: [
                "BUGBOOK_PROFILE_AUTO_START_MEETING": "1",
                "BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT": "1"
            ]
        )

        XCTAssertEqual(decision, RecordingPermissionDecision.requestSystemPrompt)
    }

    func testMicrophonePermissionPolicySupportsAudioApplicationStatus() {
        XCTAssertEqual(
            RecordingPermissionPolicy.microphoneDecision(
                authorizationStatus: MicrophonePermissionStatus.authorized,
                environment: ["BUGBOOK_PROFILE_AUTO_START_MEETING": "1"]
            ),
            RecordingPermissionDecision.granted
        )

        XCTAssertEqual(
            RecordingPermissionPolicy.microphoneDecision(
                authorizationStatus: MicrophonePermissionStatus.notDetermined,
                environment: [
                    "BUGBOOK_PROFILE_AUTO_START_MEETING": "1",
                    "BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT": "1"
                ]
            ),
            RecordingPermissionDecision.requestSystemPrompt
        )
    }

    func testMicrophonePermissionPreflightSkipsScreenCaptureKitMicrophonePath() {
        #if canImport(FluidAudio)
        XCTAssertFalse(
            TranscriptionService.shouldRequestMicrophonePermissionBeforeRecording(
                screenCaptureKitMicrophoneAvailable: true
            )
        )
        #else
        XCTAssertTrue(
            TranscriptionService.shouldRequestMicrophonePermissionBeforeRecording(
                screenCaptureKitMicrophoneAvailable: true
            )
        )
        #endif
    }

    func testMicrophonePermissionPreflightRunsForLegacyMicrophonePath() {
        XCTAssertTrue(
            TranscriptionService.shouldRequestMicrophonePermissionBeforeRecording(
                screenCaptureKitMicrophoneAvailable: false
            )
        )
    }

    func testMicrophonePermissionPromptUsesShorterTimeoutForProfiles() {
        let timeout = RecordingPermissionPolicy.microphonePromptTimeoutSeconds(
            environment: ["BUGBOOK_PROFILE_AUTO_START_MEETING": "1"]
        )

        XCTAssertEqual(timeout, 20)
    }

    func testMicrophonePermissionPromptTimeoutCanBeOverridden() {
        let timeout = RecordingPermissionPolicy.microphonePromptTimeoutSeconds(
            environment: [
                "BUGBOOK_PROFILE_AUTO_START_MEETING": "1",
                "BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS": "3.5"
            ]
        )

        XCTAssertEqual(timeout, 3.5)
    }

    func testProfileMeetingAutoStartDelayOnlyAppliesToProfileRuns() {
        XCTAssertEqual(ProfileMeetingAutoStartDelay.seconds(environment: [:]), 0)

        XCTAssertEqual(
            ProfileMeetingAutoStartDelay.seconds(environment: ["BUGBOOK_PROFILE_AUTO_START_MEETING": "1"]),
            2
        )
    }

    func testProfileMeetingAutoStartDelayCanBeOverridden() {
        let delay = ProfileMeetingAutoStartDelay.seconds(
            environment: [
                "BUGBOOK_PROFILE_AUTO_START_MEETING": "1",
                "BUGBOOK_PROFILE_AUTO_START_DELAY_SECONDS": "0.25"
            ]
        )

        XCTAssertEqual(delay, 0.25)
    }

    func testLiveTranscriptionChunkSchedulerLimitsActiveWorkAndPreservesOrder() {
        var scheduler = LiveTranscriptionChunkScheduler<Int>(maxActive: 1, warningThreshold: 3)

        XCTAssertEqual(scheduler.enqueue(0), [0])
        XCTAssertEqual(scheduler.activeCount, 1)
        XCTAssertEqual(scheduler.queuedChunks, [])

        XCTAssertEqual(scheduler.enqueue(1), [])
        XCTAssertEqual(scheduler.enqueue(2), [])
        XCTAssertEqual(scheduler.queuedChunks, [1, 2])
        XCTAssertTrue(scheduler.shouldReportBackpressure)

        XCTAssertEqual(scheduler.completeActiveChunk(), [1])
        XCTAssertEqual(scheduler.activeCount, 1)
        XCTAssertEqual(scheduler.queuedChunks, [2])

        XCTAssertEqual(scheduler.completeActiveChunk(), [2])
        XCTAssertEqual(scheduler.completeActiveChunk(), [])
        XCTAssertEqual(scheduler.activeCount, 0)
        XCTAssertEqual(scheduler.queuedChunks, [])
    }

    func testLiveTranscriptionChunkSchedulerAllowsBoundedParallelWork() {
        var scheduler = LiveTranscriptionChunkScheduler<Int>(maxActive: 2, warningThreshold: 4)

        XCTAssertEqual(scheduler.enqueue(0), [0])
        XCTAssertEqual(scheduler.enqueue(1), [1])
        XCTAssertEqual(scheduler.enqueue(2), [])
        XCTAssertEqual(scheduler.activeCount, 2)
        XCTAssertEqual(scheduler.queuedChunks, [2])

        XCTAssertEqual(scheduler.completeActiveChunk(), [2])
        XCTAssertEqual(scheduler.activeCount, 2)
        XCTAssertEqual(scheduler.queuedChunks, [])
    }

    func testLiveTranscriptionChunkSchedulerCanCancelQueuedWorkWithoutTouchingActiveWork() {
        var scheduler = LiveTranscriptionChunkScheduler<Int>(maxActive: 1, warningThreshold: 4)

        XCTAssertEqual(scheduler.enqueue(0), [0])
        XCTAssertEqual(scheduler.enqueue(1), [])
        XCTAssertEqual(scheduler.enqueue(2), [])

        XCTAssertEqual(scheduler.cancelQueuedChunks(), [1, 2])
        XCTAssertEqual(scheduler.activeCount, 1)
        XCTAssertEqual(scheduler.queuedChunks, [])

        scheduler.reset()
        XCTAssertEqual(scheduler.activeCount, 0)
        XCTAssertEqual(scheduler.queuedChunks, [])
    }

    func testLiveAudioCaptureMarkersEmitOncePerSource() {
        var markerState = LiveAudioCaptureMarkerState()

        XCTAssertEqual(markerState.markerName(for: .microphone), "meetingMicAudioCapture")
        XCTAssertNil(markerState.markerName(for: .microphone))
        XCTAssertEqual(markerState.markerName(for: .system), "meetingSystemAudioCapture")
        XCTAssertNil(markerState.markerName(for: .system))

        markerState.reset()

        XCTAssertEqual(markerState.markerName(for: .system), "meetingSystemAudioCapture")
        XCTAssertEqual(markerState.markerName(for: .microphone), "meetingMicAudioCapture")
    }

    func testStopRecordingAndWaitReturnsCurrentTranscriptWhenAlreadyStopped() async {
        let service = TranscriptionService()
        service.currentTranscript = "Me: hello there"
        service.confirmedSegments = ["Me: hello there"]

        let result = await service.stopRecordingAndWaitForFinalTranscript(timeoutSeconds: 0.01)

        XCTAssertEqual(result.fullText, "Me: hello there")
        XCTAssertEqual(result.confirmedSegments, ["Me: hello there"])
    }

    func testStopRecordingAndWaitBuildsFullTextFromConfirmedSegments() async {
        let service = TranscriptionService()
        service.confirmedSegments = ["Me: first point", "Other: second point"]

        let result = await service.stopRecordingAndWaitForFinalTranscript(timeoutSeconds: 0.01)

        XCTAssertEqual(result.fullText, "Me: first point Other: second point")
        XCTAssertEqual(result.confirmedSegments, ["Me: first point", "Other: second point"])
    }

    func testStopRecordingAndWaitPreservesLongSessionSegments() async {
        let service = TranscriptionService()
        let segments = (0..<1_440).map { index in
            "\(index.isMultiple(of: 2) ? "Me" : "Other"): simulated five-second transcript chunk \(index)"
        }
        service.confirmedSegments = segments

        let result = await service.stopRecordingAndWaitForFinalTranscript(timeoutSeconds: 0.01)

        XCTAssertEqual(result.confirmedSegments.count, 1_440)
        XCTAssertEqual(result.confirmedSegments.first, segments.first)
        XCTAssertEqual(result.confirmedSegments.last, segments.last)
        XCTAssertTrue(result.fullText.contains(segments[0]))
        XCTAssertTrue(result.fullText.contains(segments[1_439]))
    }
}
