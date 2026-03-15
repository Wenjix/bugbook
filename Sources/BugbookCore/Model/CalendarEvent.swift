import Foundation

// MARK: - Calendar Event

public struct CalendarEvent: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var calendarId: String
    public var attendees: [Attendee]
    public var conferenceURL: String?
    public var htmlLink: String?
    /// Path to a linked Bugbook page (meeting note)
    public var linkedPagePath: String?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        calendarId: String = "primary",
        attendees: [Attendee] = [],
        conferenceURL: String? = nil,
        htmlLink: String? = nil,
        linkedPagePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarId = calendarId
        self.attendees = attendees
        self.conferenceURL = conferenceURL
        self.htmlLink = htmlLink
        self.linkedPagePath = linkedPagePath
    }
}

// MARK: - Attendee

public struct Attendee: Codable, Sendable, Hashable {
    public let email: String
    public var displayName: String?
    public var responseStatus: ResponseStatus

    public init(email: String, displayName: String? = nil, responseStatus: ResponseStatus = .needsAction) {
        self.email = email
        self.displayName = displayName
        self.responseStatus = responseStatus
    }

    public enum ResponseStatus: String, Codable, Sendable, Hashable {
        case accepted
        case declined
        case tentative
        case needsAction
    }
}

// MARK: - Calendar Source

public struct CalendarSource: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var color: String
    public var isVisible: Bool

    public init(id: String, name: String, color: String = "blue", isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.color = color
        self.isVisible = isVisible
    }
}

// MARK: - Calendar Overlay (database date property shown on calendar)

public struct CalendarOverlay: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var databasePath: String
    public var databaseName: String
    public var datePropertyId: String
    public var datePropertyName: String
    public var color: String
    public var isVisible: Bool

    public init(
        id: String = UUID().uuidString,
        databasePath: String,
        databaseName: String,
        datePropertyId: String,
        datePropertyName: String,
        color: String = "gray",
        isVisible: Bool = true
    ) {
        self.id = id
        self.databasePath = databasePath
        self.databaseName = databaseName
        self.datePropertyId = datePropertyId
        self.datePropertyName = datePropertyName
        self.color = color
        self.isVisible = isVisible
    }
}

// MARK: - Database Date Item (a row rendered on the calendar)

public struct CalendarDatabaseItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let rowId: String
    public let title: String
    public let date: Date
    public let endDate: Date?
    public let databasePath: String
    public let color: String

    public init(id: String, rowId: String, title: String, date: Date, endDate: Date? = nil, databasePath: String, color: String) {
        self.id = id
        self.rowId = rowId
        self.title = title
        self.date = date
        self.endDate = endDate
        self.databasePath = databasePath
        self.color = color
    }
}
