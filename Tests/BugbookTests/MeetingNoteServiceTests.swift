import XCTest
@testable import Bugbook
import BugbookCore

@MainActor
final class MeetingNoteServiceTests: XCTestCase {
    func testCreateAdHocMeetingPageUsesFirstPartyMeetingsDatabaseWhenAvailable() throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let service = MeetingNoteService()
        let fileSystem = FileSystemService()
        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 11, minute: 45)

        let path = try XCTUnwrap(service.createAdHocMeetingPage(
            title: "Parent Interview",
            date: date,
            workspace: workspace,
            fileSystem: fileSystem
        ))

        XCTAssertEqual(
            path,
            (workspace as NSString)
                .appendingPathComponent("Meetings/Meetings Database/2026-05-17 1145 Parent Interview.md")
        )

        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("id: meeting_"))
        XCTAssertTrue(content.contains("name: \"Parent Interview\""))
        XCTAssertTrue(content.contains("type: meeting"))
        XCTAssertTrue(content.contains("meeting_id: meeting_"))
        XCTAssertTrue(content.contains("# "))
        XCTAssertFalse(content.contains("properties:"))
    }

    func testCreateOrOpenMeetingNoteUsesFirstPartyMeetingsDatabaseWhenAvailable() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let service = MeetingNoteService()
        let fileSystem = FileSystemService()
        let start = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 14, minute: 30)
        let end = try XCTUnwrap(Calendar.current.date(byAdding: .minute, value: 45, to: start))
        let event = CalendarEvent(
            id: "primary::event-1",
            title: "Parent Interview",
            startDate: start,
            endDate: end,
            attendees: [
                Attendee(email: "alice@example.com", displayName: "Alice"),
                Attendee(email: "bob@example.com", displayName: "Bob")
            ]
        )

        let createdPath = await service.createOrOpenMeetingNote(
            for: event,
            workspace: workspace,
            fileSystem: fileSystem
        )
        let path = try XCTUnwrap(createdPath)

        XCTAssertEqual(
            path,
            (workspace as NSString)
                .appendingPathComponent("Meetings/Meetings Database/2026-05-17 1430 Parent Interview.md")
        )

        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("id: meeting_"))
        XCTAssertTrue(content.contains("name: \"Parent Interview\""))
        XCTAssertTrue(content.contains("date: 2026-05-17T"))
        XCTAssertTrue(content.contains("duration_minutes: 45"))
        XCTAssertTrue(content.contains("duration: 45m"))
        XCTAssertTrue(content.contains("attendees: [Alice, Bob]"))
        XCTAssertTrue(content.contains("type: meeting"))
        XCTAssertTrue(content.contains("meeting_id: meeting_"))
        XCTAssertTrue(content.contains("# Parent Interview"))
        XCTAssertFalse(content.contains("properties:"))
    }

    private func makeTemporaryDirectory() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookMeetingNoteServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    private func makeLocalDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}
