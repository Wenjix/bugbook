import Foundation
import XCTest
@testable import Dahso

final class CalendarFeatureTests: XCTestCase {
    func testGoogleScopeSetCalendarIncludesEventWriteAndCalendarListRead() {
        XCTAssertTrue(GoogleScopeSet.calendar.contains(GoogleScopeSet.calendarEvents))
        XCTAssertTrue(GoogleScopeSet.calendar.contains(GoogleScopeSet.calendarListReadonly))
        XCTAssertTrue(GoogleScopeSet.calendar.contains(GoogleScopeSet.userEmail))
        XCTAssertFalse(GoogleScopeSet.calendar.contains(GoogleScopeSet.calendarReadonly))
    }

    func testGoogleCalendarEventRequestEncoderBuildsTimedBody() throws {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let endDate = startDate.addingTimeInterval(5400)
        let draft = CalendarEventDraft(
            title: "Roadmap Review",
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: "https://meet.example.com/room",
            notes: "Agenda and open questions."
        )

        let data = try GoogleCalendarEventRequestEncoder.requestBody(
            for: draft,
            timeZone: TimeZone(identifier: "America/Los_Angeles") ?? .current
        )
        let json = try decodedJSON(data)

        XCTAssertEqual(json["summary"] as? String, "Roadmap Review")
        XCTAssertEqual(json["location"] as? String, "https://meet.example.com/room")
        XCTAssertEqual(json["description"] as? String, "Agenda and open questions.")

        let start = try XCTUnwrap(json["start"] as? [String: Any])
        let end = try XCTUnwrap(json["end"] as? [String: Any])
        XCTAssertEqual(start["timeZone"] as? String, "America/Los_Angeles")
        XCTAssertEqual(end["timeZone"] as? String, "America/Los_Angeles")
        XCTAssertNotNil(start["dateTime"] as? String)
        XCTAssertNotNil(end["dateTime"] as? String)
        XCTAssertNil(start["date"] as? String)
        XCTAssertNil(end["date"] as? String)
    }

    func testGoogleCalendarEventRequestEncoderBuildsAllDayBodyWithExclusiveEndDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 2))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 3))!
        let draft = CalendarEventDraft(
            title: "Offsite",
            startDate: startDate,
            endDate: endDate,
            isAllDay: true,
            notes: "Bring notes."
        )

        let data = try GoogleCalendarEventRequestEncoder.requestBody(for: draft)
        let json = try decodedJSON(data)
        let start = try XCTUnwrap(json["start"] as? [String: Any])
        let end = try XCTUnwrap(json["end"] as? [String: Any])

        XCTAssertEqual(start["date"] as? String, "2026-04-02")
        XCTAssertEqual(end["date"] as? String, "2026-04-04")
        XCTAssertNil(start["dateTime"] as? String)
        XCTAssertNil(end["dateTime"] as? String)
    }

    private func decodedJSON(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
