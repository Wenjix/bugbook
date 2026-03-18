import Foundation
import AuthenticationServices
import BugbookCore

enum CalendarError: LocalizedError {
    case notAuthenticated
    case apiError(String)
    case tokenRefreshFailed
    case oauthFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Google Calendar."
        case .apiError(let msg): return msg
        case .tokenRefreshFailed: return "Failed to refresh Google Calendar token. Try signing in again."
        case .oauthFailed(let msg): return "Google sign-in failed: \(msg)"
        }
    }
}

// MARK: - Google OAuth Token

struct GoogleOAuthToken: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }
}

// MARK: - Google OAuth Browser Flow

struct GoogleOAuthResult {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String
}

enum GoogleOAuthFlow {
    // Register a "Desktop app" OAuth client in Google Cloud Console with the Calendar API enabled.
    // For installed/desktop apps, Google documents that the client ID and secret are not truly secret.
    // Replace these with your registered credentials.
    static let clientID = "YOUR_CLIENT_ID_HERE"
    static let clientSecret = "YOUR_CLIENT_SECRET_HERE"
    private static let redirectURI = "http://127.0.0.1"
    private static let scopes = "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/userinfo.email"

    @MainActor
    static func signIn() async throws -> GoogleOAuthResult {
        let authCode = try await requestAuthCode()
        let tokenResult = try await exchangeCode(authCode)
        let email = try await fetchUserEmail(accessToken: tokenResult.0)
        return GoogleOAuthResult(
            accessToken: tokenResult.0,
            refreshToken: tokenResult.1,
            expiresAt: tokenResult.2,
            email: email
        )
    }

    @MainActor
    private static func requestAuthCode() async throws -> String {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "http"
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: CalendarError.oauthFailed(error.localizedDescription))
                    return
                }
                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = items.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: CalendarError.oauthFailed("No authorization code received."))
                    return
                }
                continuation.resume(returning: code)
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = OAuthPresentationContext.shared
            session.start()
        }
    }

    private static func exchangeCode(_ code: String) async throws -> (String, String, Date) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
        ]
        request.httpBody = body.query?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw CalendarError.oauthFailed("Token exchange failed: \(msg)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw CalendarError.oauthFailed("Unexpected token response format.")
        }
        return (accessToken, refreshToken, Date().addingTimeInterval(TimeInterval(expiresIn)))
    }

    private static func fetchUserEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return ""
        }
        return email
    }
}

private class OAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthPresentationContext()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
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

    func syncGoogleCalendar(workspace: String, token: GoogleOAuthToken) async {
        guard !isSyncing else { return }
        isSyncing = true
        error = nil
        defer { isSyncing = false }

        do {
            var currentToken = token
            if currentToken.isExpired {
                currentToken = try await refreshToken(currentToken)
            }

            let syncToken = store.loadSyncToken(in: workspace)
            let result = try await fetchGoogleEvents(token: currentToken, syncToken: syncToken)

            try store.upsertEvents(result.events, in: workspace)
            if let newSyncToken = result.nextSyncToken {
                try store.saveSyncToken(newSyncToken, in: workspace)
            }

            events = store.loadEvents(in: workspace)
            lastSyncDate = Date()

            let calendars = try await fetchGoogleCalendarList(token: currentToken)
            let existingSources = store.loadSources(in: workspace)
            let existingVisibility: [String: Bool] = Dictionary(
                existingSources.map { ($0.id, $0.isVisible) },
                uniquingKeysWith: { first, _ in first }
            )
            let mergedSources = calendars.map { cal in
                CalendarSource(
                    id: cal.id,
                    name: cal.name,
                    color: cal.color,
                    isVisible: existingVisibility[cal.id] ?? true
                )
            }
            try store.saveSources(mergedSources, in: workspace)
            sources = mergedSources
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Database Overlay Items

    func loadDatabaseOverlayItems(workspace: String) async {
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

    private func fetchGoogleEvents(token: GoogleOAuthToken, syncToken: String? = nil, calendarId: String = "primary") async throws -> FetchResult {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events")!
        var queryItems: [URLQueryItem] = []
        if let syncToken {
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            queryItems.append(contentsOf: [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250"),
            ])
            let now = Date()
            queryItems.append(URLQueryItem(name: "timeMin", value: CalendarFormatters.isoFallback.string(from: now.addingTimeInterval(-30 * 86400))))
            queryItems.append(URLQueryItem(name: "timeMax", value: CalendarFormatters.isoFallback.string(from: now.addingTimeInterval(90 * 86400))))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CalendarError.apiError("No response from Google Calendar API")
        }

        if http.statusCode == 410 {
            return try await fetchGoogleEvents(token: token, syncToken: nil)
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CalendarError.apiError("Google Calendar API error \(http.statusCode): \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CalendarError.apiError("Invalid JSON response")
        }

        let items = json["items"] as? [[String: Any]] ?? []
        var events = items.compactMap { parseGoogleEvent($0, calendarId: calendarId) }

        if let nextPageToken = json["nextPageToken"] as? String {
            var pageComponents = components
            var pageQueryItems = queryItems
            pageQueryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            pageComponents.queryItems = pageQueryItems
            let nextPage = try await fetchGoogleEventsPage(url: pageComponents.url!, token: token, calendarId: calendarId, queryItems: pageQueryItems, baseComponents: pageComponents)
            events.append(contentsOf: nextPage)
        }

        let nextSyncToken = json["nextSyncToken"] as? String
        return FetchResult(events: events, nextSyncToken: nextSyncToken)
    }

    private func fetchGoogleEventsPage(url: URL, token: GoogleOAuthToken, calendarId: String, queryItems: [URLQueryItem], baseComponents: URLComponents) async throws -> [CalendarEvent] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let items = json["items"] as? [[String: Any]] ?? []
        var events = items.compactMap { parseGoogleEvent($0, calendarId: calendarId) }

        if let nextPageToken = json["nextPageToken"] as? String {
            var pageComponents = baseComponents
            var pageQueryItems = queryItems.filter { $0.name != "pageToken" }
            pageQueryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            pageComponents.queryItems = pageQueryItems
            let more = try await fetchGoogleEventsPage(url: pageComponents.url!, token: token, calendarId: calendarId, queryItems: pageQueryItems, baseComponents: pageComponents)
            events.append(contentsOf: more)
        }

        return events
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

    private func parseGoogleEvent(_ json: [String: Any], calendarId: String = "primary") -> CalendarEvent? {
        guard let id = json["id"] as? String,
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
            id: id,
            title: summary,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: json["location"] as? String,
            notes: json["description"] as? String,
            calendarId: calendarId,
            attendees: attendees,
            conferenceURL: conferenceURL,
            htmlLink: json["htmlLink"] as? String
        )
    }

    // MARK: - Token Refresh

    private func refreshToken(_ token: GoogleOAuthToken) async throws -> GoogleOAuthToken {
        var components = URLComponents(string: "https://oauth2.googleapis.com/token")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthFlow.clientID),
            URLQueryItem(name: "client_secret", value: GoogleOAuthFlow.clientSecret),
            URLQueryItem(name: "refresh_token", value: token.refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CalendarError.tokenRefreshFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw CalendarError.tokenRefreshFailed
        }

        return GoogleOAuthToken(
            accessToken: accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

}
