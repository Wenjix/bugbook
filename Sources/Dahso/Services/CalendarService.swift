import Foundation
import DahsoCore

enum CalendarError: LocalizedError {
    case notAuthenticated
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Google Calendar."
        case .apiError(let msg): return msg
        }
    }
}

// MARK: - Recurrence Rule

enum RecurrenceFrequency: String, CaseIterable, Identifiable, Equatable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

enum RecurrenceRule: Equatable {
    case none
    case preset(RecurrenceFrequency)
    /// Custom rule — the raw RRULE value string after "RRULE:", e.g. "FREQ=WEEKLY;BYDAY=MO,WE"
    case custom(String)

    var label: String {
        switch self {
        case .none: return "Does not repeat"
        case .preset(let freq): return freq.label
        case .custom: return "Custom…"
        }
    }

    /// Returns the full "RRULE:…" string to send to Google Calendar, or nil for .none.
    func rruleString(for startDate: Date) -> String? {
        switch self {
        case .none:
            return nil
        case .preset(let freq):
            switch freq {
            case .daily:
                return "RRULE:FREQ=DAILY"
            case .weekly:
                let weekday = RecurrenceRule.googleWeekdayAbbreviation(for: startDate)
                return "RRULE:FREQ=WEEKLY;BYDAY=\(weekday)"
            case .monthly:
                return "RRULE:FREQ=MONTHLY"
            case .yearly:
                return "RRULE:FREQ=YEARLY"
            }
        case .custom(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            return trimmed.hasPrefix("RRULE:") ? trimmed : "RRULE:\(trimmed)"
        }
    }

    private static func googleWeekdayAbbreviation(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let abbrevs = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        return abbrevs[max(0, min(weekday - 1, 6))]
    }
}

struct CalendarEventDraft: Equatable {
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var calendarId: String
    var recurrence: RecurrenceRule

    init(
        title: String = "",
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String = "",
        notes: String = "",
        calendarId: String = "primary",
        recurrence: RecurrenceRule = .none
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarId = calendarId
        self.recurrence = recurrence
    }

    func normalized(calendar: Calendar = .current) -> CalendarEventDraft {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if isAllDay {
            let normalizedStart = calendar.startOfDay(for: startDate)
            let normalizedEnd = max(calendar.startOfDay(for: endDate), normalizedStart)
            return CalendarEventDraft(
                title: trimmedTitle,
                startDate: normalizedStart,
                endDate: normalizedEnd,
                isAllDay: true,
                location: trimmedLocation,
                notes: trimmedNotes,
                calendarId: calendarId,
                recurrence: recurrence
            )
        }

        let normalizedEnd = endDate > startDate ? endDate : startDate.addingTimeInterval(3600)
        return CalendarEventDraft(
            title: trimmedTitle,
            startDate: startDate,
            endDate: normalizedEnd,
            isAllDay: false,
            location: trimmedLocation,
            notes: trimmedNotes,
            calendarId: calendarId,
            recurrence: recurrence
        )
    }
}

enum GoogleCalendarEventRequestEncoder {
    static func requestBody(for draft: CalendarEventDraft, timeZone: TimeZone = .current) throws -> Data {
        let normalized = draft.normalized()
        let eventTitle = normalized.title.isEmpty ? "Untitled event" : normalized.title
        var payload: [String: Any] = [
            "summary": eventTitle,
        ]

        if !normalized.location.isEmpty {
            payload["location"] = normalized.location
        }
        if !normalized.notes.isEmpty {
            payload["description"] = normalized.notes
        }
        if let rrule = normalized.recurrence.rruleString(for: normalized.startDate) {
            payload["recurrence"] = [rrule]
        }

        if normalized.isAllDay {
            let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: normalized.endDate) ?? normalized.endDate.addingTimeInterval(86400)
            payload["start"] = [
                "date": CalendarFormatters.allDay.string(from: normalized.startDate),
            ]
            payload["end"] = [
                "date": CalendarFormatters.allDay.string(from: exclusiveEnd),
            ]
        } else {
            payload["start"] = [
                "dateTime": CalendarFormatters.isoFallback.string(from: normalized.startDate),
                "timeZone": timeZone.identifier,
            ]
            payload["end"] = [
                "dateTime": CalendarFormatters.isoFallback.string(from: normalized.endDate),
                "timeZone": timeZone.identifier,
            ]
        }

        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

// MARK: - Cached Formatters

private enum CalendarFormatters {
    static let allDay: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df
    }()
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoFallback = ISO8601DateFormatter()
}

@MainActor
@Observable
class CalendarService {
    var events: [CalendarEvent] = []
    var sources: [CalendarSource] = []
    var overlays: [CalendarOverlay] = []
    var databaseItems: [CalendarDatabaseItem] = []
    var isLoading = false
    var isSyncing = false
    var error: String?
    var lastSyncDate: Date?

    @ObservationIgnored private let store = CalendarEventStore()
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    // MARK: - Load from Cache

    func loadCachedData(workspace: String) {
        events = store.loadEvents(in: workspace)
        sources = store.loadSources(in: workspace)
        overlays = store.loadOverlays(in: workspace)
    }

    // MARK: - Google Calendar Sync

    /// Sync every connected Google account in `settings`. Events from all accounts are
    /// merged into the same cache; each event is tagged with its owning account email
    /// so per-account stale detection works when accounts are added or removed.
    ///
    /// Token refreshes happen serially up front (they mutate `settings`); network fetches
    /// and store writes for each account then run in parallel.
    func syncAllGoogleAccounts(workspace: String, settings: inout AppSettings) async {
        guard !isSyncing else { return }
        isSyncing = true
        error = nil
        defer { isSyncing = false }

        // Phase 1: refresh tokens serially so `inout settings` is consistent.
        var validatedAccounts: [(email: String, token: GoogleOAuthToken)] = []
        var authFailedEmails: [String] = []
        for account in settings.connectedGoogleAccounts {
            do {
                let token = try await GoogleAuthService.validToken(
                    using: &settings,
                    forAccount: account.email,
                    requiredScopes: GoogleScopeSet.calendar
                )
                validatedAccounts.append((account.email, token))
            } catch {
                authFailedEmails.append(account.email)
                Log.app.error("Failed to auth calendar for \(account.email): \(error.localizedDescription)")
            }
        }

        // Phase 2: fetch events in parallel. Each task uses a stable token and touches
        // only its own account's cache slice, so there's no shared mutable state.
        let results = await withTaskGroup(of: Result<AccountSyncResult, AccountSyncFailure>.self) { group in
            for entry in validatedAccounts {
                group.addTask { [weak self] in
                    guard let self else {
                        return .failure(AccountSyncFailure(email: entry.email))
                    }
                    do {
                        let result = try await self.syncAccountEvents(
                            accountEmail: entry.email,
                            token: entry.token,
                            workspace: workspace
                        )
                        return .success(result)
                    } catch {
                        Log.app.error("Failed to sync calendar for \(entry.email): \(error.localizedDescription)")
                        return .failure(AccountSyncFailure(email: entry.email))
                    }
                }
            }
            var collected: [Result<AccountSyncResult, AccountSyncFailure>] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        var aggregatedCalendars: [CalendarSource] = []
        var failedAccountEmails: [String] = authFailedEmails
        var totalFetched = 0
        for outcome in results {
            switch outcome {
            case .success(let ok):
                aggregatedCalendars.append(contentsOf: ok.calendars)
                totalFetched += ok.eventCount
            case .failure(let fail):
                failedAccountEmails.append(fail.email)
            }
        }

        do {
            try persistSources(aggregatedCalendars, in: workspace, ensuringVisible: "primary")
        } catch {
            Log.app.error("Failed to persist calendar sources: \(error.localizedDescription)")
        }

        events = store.loadEvents(in: workspace)
        lastSyncDate = Date()
        if !failedAccountEmails.isEmpty {
            error = "Some Google calendars could not be synced. Loaded \(totalFetched) events from the rest."
        }
    }

    private struct AccountSyncFailure: Error {
        let email: String
    }

    private struct AccountSyncResult {
        let calendars: [CalendarSource]
        let eventCount: Int
    }

    /// Sync one account's events + calendar list, tagging each event with the account email.
    /// Cleans up stale events belonging to this account (present in cache, missing from fetch)
    /// and sweeps legacy (untagged) events on first multi-account sync.
    private func syncAccountEvents(
        accountEmail: String,
        token: GoogleOAuthToken,
        workspace: String
    ) async throws -> AccountSyncResult {
        let calendars = try await fetchGoogleCalendarList(token: token)
        let calendarIds = syncedCalendarIDs(from: calendars)

        var fetchedEvents: [CalendarEvent] = []
        for calendarId in calendarIds {
            let result = try await fetchGoogleEvents(
                token: token,
                syncToken: nil,
                calendarId: calendarId,
                accountEmail: accountEmail
            )
            fetchedEvents.append(contentsOf: result.events)
        }

        let existingEvents = store.loadEvents(in: workspace)
        let fetchedIds = Set(fetchedEvents.map(\.id))
        let syncedSourceIds = Set(calendarIds)

        // Events from THIS account that disappeared from the remote → stale.
        // Legacy events (accountEmail == nil) also get swept when their calendarId matches
        // this account's calendar IDs (one-shot migration on first post-upgrade sync).
        let staleIds = Set(
            existingEvents
                .filter { event in
                    guard syncedSourceIds.contains(event.calendarId) else { return false }
                    let isOwnedByThisAccount = event.accountEmail?.caseInsensitiveCompare(accountEmail) == .orderedSame
                    let isLegacy = event.accountEmail == nil
                    guard isOwnedByThisAccount || isLegacy else { return false }
                    return !fetchedIds.contains(event.id)
                }
                .map(\.id)
        )

        try store.upsertEvents(fetchedEvents, in: workspace)
        if !staleIds.isEmpty {
            try store.removeEvents(withIds: staleIds, in: workspace)
        }

        return AccountSyncResult(calendars: calendars, eventCount: fetchedEvents.count)
    }

    func createGoogleEvent(
        workspace: String,
        accountEmail: String,
        token: GoogleOAuthToken,
        draft: CalendarEventDraft
    ) async throws -> CalendarEvent {
        let normalizedDraft = draft.normalized()
        var request = URLRequest(url: googleEventsURL(calendarId: normalizedDraft.calendarId))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try GoogleCalendarEventRequestEncoder.requestBody(for: normalizedDraft)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CalendarError.apiError("No response from Google Calendar API")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CalendarError.apiError("Google Calendar create error \(http.statusCode): \(body)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = parseGoogleEvent(json, calendarId: normalizedDraft.calendarId, accountEmail: accountEmail) else {
            throw CalendarError.apiError("Google Calendar returned an unreadable event response.")
        }

        try store.upsertEvents([event], in: workspace)
        events = store.loadEvents(in: workspace)
        lastSyncDate = Date()

        try ensureLocalSourceExists(for: event.calendarId, in: workspace)
        if let calendars = try? await fetchGoogleCalendarList(token: token) {
            try? persistSources(calendars, in: workspace, ensuringVisible: event.calendarId)
        }

        return event
    }

    // MARK: - Database Overlay Items

    func loadDatabaseOverlayItems(workspace: String) async {
        let start = CFAbsoluteTimeGetCurrent()
        var items: [CalendarDatabaseItem] = []
        let dbStore = DatabaseStore()
        let visibleOverlays = overlays.filter(\.isVisible)

        for overlay in visibleOverlays {
            guard let schema = try? dbStore.loadSchema(at: overlay.databasePath) else { continue }
            let titleProp = schema.titleProperty
            let dateProp = schema.properties.first(where: { $0.id == overlay.datePropertyId })
            guard dateProp != nil else { continue }

            let rowStore = RowStore()
            let allRows = rowStore.loadAllRows(in: overlay.databasePath, schema: schema, skipBody: true)

            for row in allRows {
                guard let dateVal = row.properties[overlay.datePropertyId] else { continue }
                let dateStr = dateVal.stringValue
                guard !dateStr.isEmpty,
                      let dateValue = DatabaseDateValue.decode(from: dateStr),
                      let date = dateValue.startDate else { continue }

                let title: String
                if let titleId = titleProp?.id, let titleVal = row.properties[titleId] {
                    let s = titleVal.stringValue
                    title = s.isEmpty ? "Untitled" : s
                } else {
                    title = "Untitled"
                }

                items.append(CalendarDatabaseItem(
                    id: "\(overlay.id)_\(row.id)",
                    rowId: row.id,
                    title: title,
                    date: date,
                    databasePath: overlay.databasePath,
                    color: overlay.color
                ))
            }
        }

        databaseItems = items
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 500 {
            print("[Perf] loadDatabaseOverlayItems took \(Int(elapsed))ms (\(items.count) items)")
        }
    }

    // MARK: - Overlay Management

    func addOverlay(_ overlay: CalendarOverlay, workspace: String) {
        overlays.append(overlay)
        try? store.saveOverlays(overlays, in: workspace)
    }

    func removeOverlay(id: String, workspace: String) {
        overlays.removeAll { $0.id == id }
        try? store.saveOverlays(overlays, in: workspace)
    }

    func toggleOverlayVisibility(id: String, workspace: String) {
        guard let idx = overlays.firstIndex(where: { $0.id == id }) else { return }
        overlays[idx].isVisible.toggle()
        try? store.saveOverlays(overlays, in: workspace)
    }

    func toggleSourceVisibility(id: String, workspace: String) {
        guard let idx = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[idx].isVisible.toggle()
        try? store.saveSources(sources, in: workspace)
    }

    func updateSourceColor(id: String, color: String, workspace: String) {
        guard let idx = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[idx].color = color
        try? store.saveSources(sources, in: workspace)
    }

    // MARK: - Event Linking

    func linkEventToPage(eventId: String, pagePath: String, workspace: String) {
        try? store.linkEventToPage(eventId: eventId, pagePath: pagePath, in: workspace)
        if let idx = events.firstIndex(where: { $0.id == eventId }) {
            events[idx].linkedPagePath = pagePath
        }
    }

    // MARK: - Google Calendar API

    private struct FetchResult {
        let events: [CalendarEvent]
        let nextSyncToken: String?
    }

    private func fetchGoogleEvents(
        token: GoogleOAuthToken,
        syncToken: String? = nil,
        calendarId: String = "primary",
        accountEmail: String? = nil
    ) async throws -> FetchResult {
        let baseURL = googleEventsURL(calendarId: calendarId)
        var baseQueryItems: [URLQueryItem] = []
        if let syncToken {
            baseQueryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            baseQueryItems.append(contentsOf: [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250"),
            ])
            let now = Date()
            baseQueryItems.append(URLQueryItem(name: "timeMin", value: CalendarFormatters.isoFallback.string(from: now.addingTimeInterval(-30 * 86400))))
            baseQueryItems.append(URLQueryItem(name: "timeMax", value: CalendarFormatters.isoFallback.string(from: now.addingTimeInterval(90 * 86400))))
        }
        var pageToken: String?
        var events: [CalendarEvent] = []
        var nextSyncToken: String?

        repeat {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            var pageQueryItems = baseQueryItems
            if let pageToken {
                pageQueryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = pageQueryItems

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CalendarError.apiError("No response from Google Calendar API")
            }

            if http.statusCode == 410 {
                return try await fetchGoogleEvents(token: token, syncToken: nil, calendarId: calendarId, accountEmail: accountEmail)
            }

            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw CalendarError.apiError("Google Calendar API error \(http.statusCode): \(body)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CalendarError.apiError("Invalid JSON response")
            }

            let items = json["items"] as? [[String: Any]] ?? []
            events.append(contentsOf: items.compactMap { parseGoogleEvent($0, calendarId: calendarId, accountEmail: accountEmail) })

            if let nextToken = json["nextSyncToken"] as? String {
                nextSyncToken = nextToken
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil

        return FetchResult(events: events, nextSyncToken: nextSyncToken)
    }

    private func fetchGoogleCalendarList(token: GoogleOAuthToken) async throws -> [CalendarSource] {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let summary = item["summary"] as? String else { return nil }
            let color = item["backgroundColor"] as? String ?? "#4285F4"
            return CalendarSource(id: id, name: summary, color: color)
        }
    }

    private func persistSources(_ calendars: [CalendarSource], in workspace: String, ensuringVisible ensuredSourceID: String? = nil) throws {
        let existingSources = store.loadSources(in: workspace)
        let existingVisibility: [String: Bool] = Dictionary(
            existingSources.map { ($0.id, $0.isVisible) },
            uniquingKeysWith: { first, _ in first }
        )
        var mergedSources = calendars.map { cal in
            CalendarSource(
                id: cal.id,
                name: cal.name,
                color: cal.color,
                isVisible: existingVisibility[cal.id] ?? true
            )
        }

        if let ensuredSourceID,
           !mergedSources.contains(where: { $0.id == ensuredSourceID }) {
            let fallbackName = ensuredSourceID == "primary" ? "Primary" : ensuredSourceID
            mergedSources.append(
                CalendarSource(
                    id: ensuredSourceID,
                    name: fallbackName,
                    color: "#4285F4",
                    isVisible: existingVisibility[ensuredSourceID] ?? true
                )
            )
        }

        try store.saveSources(mergedSources, in: workspace)
        sources = mergedSources
    }

    private func ensureLocalSourceExists(for calendarId: String, in workspace: String) throws {
        guard !sources.contains(where: { $0.id == calendarId }) else { return }
        var updatedSources = sources
        updatedSources.append(
            CalendarSource(
                id: calendarId,
                name: calendarId == "primary" ? "Primary" : calendarId,
                color: "#4285F4",
                isVisible: true
            )
        )
        try store.saveSources(updatedSources, in: workspace)
        sources = updatedSources
    }

    private func googleEventsURL(calendarId: String) -> URL {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let encodedCalendarID = calendarId.addingPercentEncoding(withAllowedCharacters: allowed) ?? calendarId
        return URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events")!
    }

    private func syncedCalendarIDs(from calendars: [CalendarSource]) -> [String] {
        var orderedIds = ["primary"]
        for calendar in calendars where orderedIds.contains(calendar.id) == false {
            orderedIds.append(calendar.id)
        }
        return orderedIds
    }

    private func eventID(remoteID: String, calendarId: String) -> String {
        "\(calendarId)::\(remoteID)"
    }

    private func parseGoogleEvent(_ json: [String: Any], calendarId: String = "primary", accountEmail: String? = nil) -> CalendarEvent? {
        guard let remoteID = json["id"] as? String,
              let summary = json["summary"] as? String else { return nil }

        let start = json["start"] as? [String: Any] ?? [:]
        let end = json["end"] as? [String: Any] ?? [:]

        let isAllDay = start["date"] != nil
        let startDate: Date
        let endDate: Date

        if isAllDay {
            guard let startStr = start["date"] as? String,
                  let endStr = end["date"] as? String else { return nil }
            guard let s = CalendarFormatters.allDay.date(from: startStr),
                  let e = CalendarFormatters.allDay.date(from: endStr) else { return nil }
            startDate = s
            endDate = e
        } else {
            guard let startStr = start["dateTime"] as? String,
                  let endStr = end["dateTime"] as? String else { return nil }
            guard let s = CalendarFormatters.isoFractional.date(from: startStr) ?? CalendarFormatters.isoFallback.date(from: startStr),
                  let e = CalendarFormatters.isoFractional.date(from: endStr) ?? CalendarFormatters.isoFallback.date(from: endStr) else { return nil }
            startDate = s
            endDate = e
        }

        let attendeesJSON = json["attendees"] as? [[String: Any]] ?? []
        let attendees: [Attendee] = attendeesJSON.compactMap { att in
            guard let email = att["email"] as? String else { return nil }
            let name = att["displayName"] as? String
            let status = att["responseStatus"] as? String ?? "needsAction"
            return Attendee(
                email: email,
                displayName: name,
                responseStatus: Attendee.ResponseStatus(rawValue: status) ?? .needsAction
            )
        }

        var conferenceURL: String?
        if let entryPoints = (json["conferenceData"] as? [String: Any])?["entryPoints"] as? [[String: Any]] {
            conferenceURL = entryPoints.first(where: { ($0["entryPointType"] as? String) == "video" })?["uri"] as? String
        }

        return CalendarEvent(
            id: eventID(remoteID: remoteID, calendarId: calendarId),
            title: summary,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: json["location"] as? String,
            notes: json["description"] as? String,
            calendarId: calendarId,
            attendees: attendees,
            conferenceURL: conferenceURL,
            htmlLink: json["htmlLink"] as? String,
            accountEmail: accountEmail
        )
    }
}
