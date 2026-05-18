import XCTest
@testable import Bugbook

final class MeetingRecordingNoticeTests: XCTestCase {
    @MainActor
    func testCreatedMeetingPageArmsAutoRecordAndNavigatesToEditor() {
        let state = AppState()
        let path = "/tmp/Bugbook/New Meeting.md"
        var navigatedPaths: [String] = []

        state.currentView = .chat
        state.showSettings = true

        MeetingNavigationCoordinator.openCreatedMeetingPage(
            path,
            appState: state,
            navigateToFile: { navigatedPaths.append($0) }
        )

        XCTAssertEqual(state.currentView, .editor)
        XCTAssertFalse(state.showSettings)
        XCTAssertEqual(state.pendingAutoRecordPath, path)
        XCTAssertEqual(navigatedPaths, [path])
    }

    @MainActor
    func testFloatingStopRoutesToMeetingPageBeforePostingStop() {
        let state = AppState()
        let path = "/tmp/Bugbook/Meeting.md"
        let session = ActiveMeetingSession(meetingPagePath: path)
        var navigatedPaths: [String] = []
        var didPostStopNotification = false

        state.currentView = .chat
        state.showSettings = true

        MeetingNavigationCoordinator.stopActiveRecordingFromFloatingPill(
            session: session,
            appState: state,
            navigateToFile: { navigatedPaths.append($0) },
            postStopNotification: { didPostStopNotification = true }
        )

        XCTAssertTrue(session.stopRequested)
        XCTAssertEqual(state.currentView, .editor)
        XCTAssertFalse(state.showSettings)
        XCTAssertEqual(navigatedPaths, [path])
        XCTAssertTrue(didPostStopNotification)
    }

    func testMicrophoneNoticeOpensMicrophonePrivacyFirst() {
        let message = "Microphone access denied. Enable Bugbook in System Settings."

        XCTAssertTrue(MeetingRecordingNoticePrivacySettings.showsButton(message: message))
        XCTAssertEqual(
            MeetingRecordingNoticePrivacySettings.anchors(for: message),
            ["Privacy_Microphone", "Privacy"]
        )
    }

    func testSystemAudioNoticeOpensAudioCapturePrivacyFirst() {
        let message = "System audio was not captured. Enable Screen & System Audio Recording."

        XCTAssertTrue(MeetingRecordingNoticePrivacySettings.showsButton(message: message))
        XCTAssertEqual(
            MeetingRecordingNoticePrivacySettings.anchors(for: message),
            ["Privacy_AudioCapture", "Privacy_ScreenCapture", "Privacy"]
        )
    }

    func testPrivacyNoticeFallsBackAcrossRelevantPrivacyPanes() {
        let message = "Privacy permission is required before recording."

        XCTAssertTrue(MeetingRecordingNoticePrivacySettings.showsButton(message: message))
        XCTAssertEqual(
            MeetingRecordingNoticePrivacySettings.anchors(for: message),
            ["Privacy_Microphone", "Privacy_AudioCapture", "Privacy_ScreenCapture", "Privacy"]
        )
    }

    func testNonPrivacyNoticeDoesNotShowSettingsButton() {
        XCTAssertFalse(MeetingRecordingNoticePrivacySettings.showsButton(message: "Recording started."))
    }
}
