import Foundation

/// App-level state for an active meeting recording session.
/// Owned by AppState, independent of any pane — survives pane navigation.
@MainActor
@Observable
class ActiveMeetingSession {
    /// Path to the meeting page file being recorded.
    var meetingPagePath: String
    /// When the recording started.
    var startDate: Date
    /// Live transcript segments (confirmed).
    var confirmedSegments: [String] = []
    /// In-progress speech recognition text (not yet confirmed).
    var volatileText: String = ""
    /// Current audio input level (0–1).
    var audioLevel: Float = 0

    init(meetingPagePath: String, startDate: Date = .now) {
        self.meetingPagePath = meetingPagePath
        self.startDate = startDate
    }

    /// Full transcript text from all confirmed segments.
    var fullTranscript: String {
        confirmedSegments.joined(separator: " ")
    }
}
