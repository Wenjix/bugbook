import Foundation

// MARK: - Calendar Event

public struct CalendarEvent: Identifiable, Codable, Sendable, Hashable {
    public struct IDComponents: Sendable, Hashable {
        public let accountEmail: String?
        public let calendarId: String
        public let remoteID: String

        public var isAccountQualified: Bool { accountEmail != nil }
    }

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
    /// Path to a linked Dahso page (meeting note)
    public var linkedPagePath: String?
    /// Email of the Google account that owns this event. Nil for legacy cached events from
    /// before multi-account support — those are treated as belonging to the primary account.
    public var accountEmail: String?
    /// Optional local block profile consumed by scheduled screen-time/blocking integrations.
    public var blockProfile: CalendarBlockProfile?

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
        linkedPagePath: String? = nil,
        accountEmail: String? = nil,
        blockProfile: CalendarBlockProfile? = nil
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
        self.accountEmail = Self.normalizedAccountEmail(accountEmail) ?? Self.idComponents(for: id)?.accountEmail
        self.blockProfile = blockProfile
    }

    public static let idSeparator = "::"

    public static func normalizedAccountEmail(_ accountEmail: String?) -> String? {
        guard let accountEmail else { return nil }
        let trimmed = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func composeID(accountEmail: String?, calendarId: String, remoteID: String) -> String {
        var parts: [String] = []
        if let email = normalizedAccountEmail(accountEmail) {
            parts.append(email)
        }
        parts.append(calendarId)
        parts.append(remoteID)
        return parts.joined(separator: idSeparator)
    }

    public static func idComponents(for id: String) -> IDComponents? {
        let parts = id.components(separatedBy: idSeparator)
        switch parts.count {
        case 2:
            guard !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return IDComponents(accountEmail: nil, calendarId: parts[0], remoteID: parts[1])
        case 3:
            guard !parts[0].isEmpty, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
            return IDComponents(
                accountEmail: normalizedAccountEmail(parts[0]),
                calendarId: parts[1],
                remoteID: parts[2]
            )
        default:
            return nil
        }
    }

    public var idComponents: IDComponents? {
        Self.idComponents(for: id)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, endDate, isAllDay, location, notes
        case calendarId, attendees, conferenceURL, htmlLink, linkedPagePath, accountEmail, blockProfile
    }

    // Custom decoder so legacy cached events without `accountEmail` still decode cleanly.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        location = try container.decodeIfPresent(String.self, forKey: .location)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        calendarId = try container.decodeIfPresent(String.self, forKey: .calendarId) ?? "primary"
        attendees = try container.decodeIfPresent([Attendee].self, forKey: .attendees) ?? []
        conferenceURL = try container.decodeIfPresent(String.self, forKey: .conferenceURL)
        htmlLink = try container.decodeIfPresent(String.self, forKey: .htmlLink)
        linkedPagePath = try container.decodeIfPresent(String.self, forKey: .linkedPagePath)
        accountEmail = Self.normalizedAccountEmail(
            try container.decodeIfPresent(String.self, forKey: .accountEmail)
        ) ?? Self.idComponents(for: id)?.accountEmail
        blockProfile = try container.decodeIfPresent(CalendarBlockProfile.self, forKey: .blockProfile)
    }
}

// MARK: - Calendar Block Profile

/// Block metadata attached to a calendar event and exported for local blocking tools.
public struct CalendarBlockProfile: Codable, Sendable, Hashable {
    public var name: String
    public var identifier: String

    public init(name: String, identifier: String? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Block" : trimmedName
        self.name = displayName
        self.identifier = Self.normalizedIdentifier(identifier) ?? Self.generatedIdentifier(from: displayName)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case identifier
    }

    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let name = try? singleValue.decode(String.self) {
            self.init(name: name)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Block"
        let identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        self.init(name: name, identifier: identifier)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(identifier, forKey: .identifier)
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func generatedIdentifier(from name: String) -> String {
        let parts = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "block" : parts.joined(separator: "-")
    }
}

// MARK: - Calendar Block Window

/// Stable JSON contract exported to `.dahso/calendar/block_windows.json`.
public struct CalendarBlockWindow: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let eventId: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let profile: String
    public let profileIdentifier: String
    public let calendarId: String
    public let accountEmail: String?
    public let isAllDay: Bool

    public init(event: CalendarEvent, profile: CalendarBlockProfile) {
        self.id = event.id
        self.eventId = event.id
        self.title = event.title
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.profile = profile.name
        self.profileIdentifier = profile.identifier
        self.calendarId = event.calendarId
        self.accountEmail = event.accountEmail
        self.isAllDay = event.isAllDay
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case eventId
        case title
        case startDate = "start"
        case endDate = "end"
        case profile
        case profileIdentifier
        case calendarId
        case accountEmail
        case isAllDay
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
