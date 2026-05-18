import XCTest
@testable import Bugbook

@MainActor
final class MeetingFrontmatterTests: XCTestCase {
    func testUpsertingScalarReplacesExistingValue() {
        let yaml = """
        title: Parent Interview
        duration_minutes: 12
        duration: 12m
        """

        let updated = MeetingFrontmatter.upsertingScalar(key: "duration", value: "45m", in: yaml)

        XCTAssertTrue(updated.contains("duration: 45m"))
        XCTAssertFalse(updated.contains("duration: 12m"))
        XCTAssertTrue(updated.contains("duration_minutes: 12"))
    }

    func testUpsertingScalarAppendsMissingValue() {
        let yaml = """
        title: Parent Interview
        """

        let updated = MeetingFrontmatter.upsertingScalar(key: "duration_minutes", value: "45", in: yaml)

        XCTAssertTrue(updated.contains("title: Parent Interview"))
        XCTAssertTrue(updated.contains("duration_minutes: 45"))
    }

    func testUpsertingScalarHandlesEmptyFrontmatter() {
        XCTAssertEqual(
            MeetingFrontmatter.upsertingScalar(key: "duration", value: "45m", in: ""),
            "duration: 45m"
        )
    }

    func testParseInlineAttendees() {
        let yaml = """
        title: Parent Interview
        attendees: [Max, "Avery", 'Jordan']
        """

        XCTAssertEqual(MeetingFrontmatter.parseParticipants(from: yaml), ["Max", "Avery", "Jordan"])
    }

    func testParseParticipantListFallback() {
        let yaml = """
        title: Parent Interview
        participants:
        - Max
        - Avery
        duration: 30m
        """

        XCTAssertEqual(MeetingFrontmatter.parseParticipants(from: yaml), ["Max", "Avery"])
    }

    func testRecordingFinalizerStampsDurationAndCollapsedTranscriptToggle() throws {
        let document = BlockDocument(markdown: """
        ---
        type: meeting
        name: "Parent Interview"
        ---
        # Parent Interview

        Live notes
        """)
        let startDate = try makeUTCDate("2026-05-17T14:30:00Z")
        let recordedAt = try makeUTCDate("2026-05-17T15:15:12Z")

        let entries = MeetingRecordingDocumentFinalizer.finalize(
            document: document,
            finalSegments: ["Alice: hello", "Bob: thanks"],
            fallbackText: "ignored fallback",
            startDate: startDate,
            recordedAt: recordedAt
        )

        XCTAssertEqual(entries, ["Alice: hello", "Bob: thanks"])
        XCTAssertTrue(document.yamlFrontmatter.contains("recorded_at: 2026-05-17T15:15:12Z"))
        XCTAssertTrue(document.yamlFrontmatter.contains("duration_minutes: 45"))
        XCTAssertTrue(document.yamlFrontmatter.contains("duration: 45m"))

        let transcriptBlock = try XCTUnwrap(document.blocks.last)
        XCTAssertEqual(transcriptBlock.type, .toggle)
        XCTAssertEqual(transcriptBlock.text, "Transcript")
        XCTAssertFalse(transcriptBlock.isExpanded)
        XCTAssertEqual(transcriptBlock.children.count, 1)
        XCTAssertEqual(transcriptBlock.children.first?.type, .codeBlock)
        XCTAssertEqual(transcriptBlock.children.first?.language, "text")
        XCTAssertEqual(transcriptBlock.children.first?.text, "Alice: hello\n\nBob: thanks")
    }

    func testRecordingFinalizerReplacesExistingTranscriptToggleFromFallbackText() throws {
        let document = BlockDocument(markdown: "# Parent Interview\n")
        document.blocks.append(Block(
            type: .toggle,
            text: "Transcript",
            children: [Block(type: .codeBlock, text: "Old transcript", language: "text")],
            isExpanded: true
        ))
        let startDate = try makeUTCDate("2026-05-17T14:30:00Z")
        let recordedAt = try makeUTCDate("2026-05-17T14:31:00Z")

        let entries = MeetingRecordingDocumentFinalizer.finalize(
            document: document,
            finalSegments: [],
            fallbackText: "\nFallback transcript\n",
            startDate: startDate,
            recordedAt: recordedAt
        )

        let transcriptToggles = document.blocks.filter {
            $0.type == .toggle && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "Transcript"
        }
        XCTAssertEqual(entries, ["Fallback transcript"])
        XCTAssertEqual(transcriptToggles.count, 1)
        XCTAssertFalse(transcriptToggles[0].isExpanded)
        XCTAssertEqual(transcriptToggles[0].children.first?.text, "Fallback transcript")
    }

    private func makeUTCDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }
}
