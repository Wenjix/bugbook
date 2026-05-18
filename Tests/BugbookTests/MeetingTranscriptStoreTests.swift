import XCTest
@testable import Bugbook

final class MeetingTranscriptStoreTests: XCTestCase {
    func testFormatterBuildsCopyTextFromEntries() {
        let entries = [
            MeetingTranscriptEntry(text: "Me: first note", timestamp: 1, speaker: "self"),
            MeetingTranscriptEntry(text: "System: second note", timestamp: 2, speaker: "other")
        ]

        XCTAssertEqual(
            MeetingTranscriptFormatter.copyText(entries: entries),
            "first note\nSystem: second note"
        )
    }

    func testFormatterAppendsTrimmedVolatileText() {
        let entries = [
            MeetingTranscriptEntry(text: "confirmed", timestamp: 1, speaker: "self")
        ]

        XCTAssertEqual(
            MeetingTranscriptFormatter.copyText(entries: entries, volatileText: "\nMe: in progress\n"),
            "confirmed\nin progress"
        )
    }

    func testFormatterAllowsCopyingVolatileTextWithoutEntries() {
        XCTAssertEqual(
            MeetingTranscriptFormatter.copyText(entries: [], volatileText: "Me: live words"),
            "live words"
        )
    }

    func testAsyncSaveAndLoadRoundTrip() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookTranscriptStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let store = MeetingTranscriptStore()
        let meetingId = UUID().uuidString
        let transcript = MeetingTranscript(
            entries: [
                MeetingTranscriptEntry(text: "Me: first note", timestamp: 1, speaker: "self"),
                MeetingTranscriptEntry(text: "Other: second note", timestamp: 2, speaker: "other")
            ],
            summary: ["Decision made"],
            actionItems: ["Follow up"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        await store.saveAsync(transcript, meetingId: meetingId, workspace: workspace.path)
        let loaded = await store.loadAsync(meetingId: meetingId, workspace: workspace.path)

        XCTAssertEqual(loaded, transcript)
    }
}
