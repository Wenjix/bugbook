import Foundation
import XCTest
import BugbookCore
@testable import Bugbook

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

    func testGoogleCalendarEventRequestEncoderIncludesBlockProfilePrivateProperties() throws {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = CalendarEventDraft(
            title: "Deep Work",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            blockProfile: CalendarBlockProfile(name: "Deep Focus", identifier: "deep-focus")
        )

        let data = try GoogleCalendarEventRequestEncoder.requestBody(for: draft)
        let json = try decodedJSON(data)
        let extendedProperties = try XCTUnwrap(json["extendedProperties"] as? [String: Any])
        let privateProperties = try XCTUnwrap(extendedProperties["private"] as? [String: Any])

        XCTAssertEqual(privateProperties["bugbook.blockProfile.name"] as? String, "Deep Focus")
        XCTAssertEqual(privateProperties["bugbook.blockProfile.identifier"] as? String, "deep-focus")
    }

    func testLegacyCalendarEventsDecodeWithoutBlockProfile() throws {
        let data = Data(
            """
            [
              {
                "id": "primary::event-1",
                "title": "Legacy Event",
                "startDate": "2026-04-28T17:00:00Z",
                "endDate": "2026-04-28T18:00:00Z"
              }
            ]
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let events = try decoder.decode([CalendarEvent].self, from: data)

        XCTAssertEqual(events.first?.title, "Legacy Event")
        XCTAssertNil(events.first?.blockProfile)
    }

    func testCalendarStoreRoundTripsBlockProfileAndExportsStoneContract() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let store = CalendarEventStore()
        let startDate = futureWholeSecondDate(offset: 3600)
        let event = makeCalendarEvent(
            id: "primary::focus",
            title: "Focus Block",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            blockProfile: CalendarBlockProfile(name: "Work")
        )

        try store.saveEvents([event], in: workspace.path)
        let loaded = store.loadEvents(in: workspace.path)
        let loadedEvent = try XCTUnwrap(loaded.first)
        XCTAssertEqual(loadedEvent.blockProfile?.name, "Work")
        XCTAssertEqual(loadedEvent.blockProfile?.identifier, "work")

        let contractURL = URL(fileURLWithPath: store.calendarBlockWindowsPath(in: workspace.path))
        let contractData = try Data(contentsOf: contractURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let windows = try decoder.decode([CalendarBlockWindow].self, from: contractData)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.title, "Focus Block")
        XCTAssertEqual(window.profile, "Work")
        XCTAssertEqual(window.profileIdentifier, "work")
        XCTAssertEqual(window.startDate, startDate)
        XCTAssertEqual(window.endDate, startDate.addingTimeInterval(3600))

        let json = try decodedJSONArray(contractData)
        let exportedWindow = try XCTUnwrap(json.first)
        XCTAssertNotNil(exportedWindow["start"])
        XCTAssertNotNil(exportedWindow["end"])
        XCTAssertNil(exportedWindow["startDate"])
        XCTAssertNil(exportedWindow["endDate"])
    }

    func testCalendarStoreUpsertPreservesLocalBlockProfile() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let store = CalendarEventStore()
        let startDate = Date(timeIntervalSince1970: 1_777_392_000)
        let existing = makeCalendarEvent(
            id: "primary::focus",
            title: "Focus Block",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            blockProfile: CalendarBlockProfile(name: "Evening")
        )
        let incoming = makeCalendarEvent(
            id: "primary::focus",
            title: "Focus Block Updated",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(7200)
        )

        try store.saveEvents([existing], in: workspace.path)
        try store.upsertEvents([incoming], in: workspace.path)
        let loaded = try XCTUnwrap(store.loadEvents(in: workspace.path).first)

        XCTAssertEqual(loaded.title, "Focus Block Updated")
        XCTAssertEqual(loaded.blockProfile?.name, "Evening")
        XCTAssertEqual(loaded.blockProfile?.identifier, "evening")
    }

    func testCalendarStoreFindsActiveAndUpcomingBlockWindows() {
        let store = CalendarEventStore()
        let now = Date(timeIntervalSince1970: 1_777_392_000)
        let active = makeCalendarEvent(
            id: "primary::active",
            title: "Active",
            startDate: now.addingTimeInterval(-600),
            endDate: now.addingTimeInterval(600),
            blockProfile: CalendarBlockProfile(name: "Work")
        )
        let upcoming = makeCalendarEvent(
            id: "primary::upcoming",
            title: "Upcoming",
            startDate: now.addingTimeInterval(1800),
            endDate: now.addingTimeInterval(3600),
            blockProfile: CalendarBlockProfile(name: "Deep Focus")
        )
        let past = makeCalendarEvent(
            id: "primary::past",
            title: "Past",
            startDate: now.addingTimeInterval(-7200),
            endDate: now.addingTimeInterval(-3600),
            blockProfile: CalendarBlockProfile(name: "Work")
        )
        let normal = makeCalendarEvent(
            id: "primary::normal",
            title: "Normal",
            startDate: now.addingTimeInterval(1200),
            endDate: now.addingTimeInterval(1800)
        )

        let windows = store.blockWindows(
            from: [upcoming, normal, past, active],
            now: now,
            horizon: 2 * 60 * 60
        )

        XCTAssertEqual(windows.map(\.eventId), ["primary::active", "primary::upcoming"])
        XCTAssertEqual(windows.map(\.profile), ["Work", "Deep Focus"])
    }

    private func decodedJSON(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func decodedJSONArray(_ data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [[String: Any]])
    }

    private func makeTemporaryWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bugbook-calendar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func futureWholeSecondDate(offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + offset)
    }

    private func makeCalendarEvent(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        blockProfile: CalendarBlockProfile? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendarId: "primary",
            blockProfile: blockProfile
        )
    }
}
