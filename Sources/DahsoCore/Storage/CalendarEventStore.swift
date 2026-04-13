import Foundation

/// Persists calendar events and sources to a local JSON cache.
/// Storage location: `<workspace>/.dahso/calendar/`
public class CalendarEventStore {
    private let fm = FileManager.default

    public init() {}

    // MARK: - Paths

    private func calendarDir(in workspace: String) -> String {
        (workspace as NSString).appendingPathComponent(".dahso/calendar")
    }

    private func eventsPath(in workspace: String) -> String {
        (calendarDir(in: workspace) as NSString).appendingPathComponent("events.json")
    }

    private func sourcesPath(in workspace: String) -> String {
        (calendarDir(in: workspace) as NSString).appendingPathComponent("sources.json")
    }

    private func overlaysPath(in workspace: String) -> String {
        (calendarDir(in: workspace) as NSString).appendingPathComponent("overlays.json")
    }

    private func syncStatePath(in workspace: String) -> String {
        (calendarDir(in: workspace) as NSString).appendingPathComponent("sync_state.json")
    }

    private func ensureDirectory(in workspace: String) throws {
        let dir = calendarDir(in: workspace)
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Events

    public func loadEvents(in workspace: String) -> [CalendarEvent] {
        let path = eventsPath(in: workspace)
        guard let data = fm.contents(atPath: path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CalendarEvent].self, from: data)) ?? []
    }

    public func saveEvents(_ events: [CalendarEvent], in workspace: String) throws {
        try ensureDirectory(in: workspace)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(events)
        try data.write(to: URL(fileURLWithPath: eventsPath(in: workspace)), options: .atomic)
    }

    /// Upsert events by ID — update existing, add new, keep others untouched.
    public func upsertEvents(_ incoming: [CalendarEvent], in workspace: String) throws {
        var existing = loadEvents(in: workspace)
        var indexById: [String: Int] = [:]
        for (i, event) in existing.enumerated() {
            indexById[event.id] = i
        }
        for event in incoming {
            if let idx = indexById[event.id] ?? indexOfEvent(withID: event.id, in: existing) {
                // Preserve linked page path from existing event
                let previousID = existing[idx].id
                var updated = event
                if updated.linkedPagePath == nil {
                    updated.linkedPagePath = existing[idx].linkedPagePath
                }
                if updated.accountEmail == nil {
                    updated.accountEmail = existing[idx].accountEmail
                }
                existing[idx] = updated
                if previousID != updated.id {
                    indexById.removeValue(forKey: previousID)
                }
                indexById[updated.id] = idx
            } else {
                indexById[event.id] = existing.count
                existing.append(event)
            }
        }
        try saveEvents(existing, in: workspace)
    }

    /// Remove events that no longer exist in the remote calendar.
    public func removeEvents(withIds ids: Set<String>, in workspace: String) throws {
        var events = loadEvents(in: workspace)
        events.removeAll { ids.contains($0.id) }
        try saveEvents(events, in: workspace)
    }

    @discardableResult
    public func migrateLegacyIDs(in workspace: String, using activeAccountEmail: String?) throws -> [String: String] {
        let existingEvents = loadEvents(in: workspace)
        guard !existingEvents.isEmpty else { return [:] }

        let fallbackAccountEmail = CalendarEvent.normalizedAccountEmail(activeAccountEmail)
        var rewrittenEvents: [CalendarEvent] = []
        var indexById: [String: Int] = [:]
        var idMapping: [String: String] = [:]
        var didChange = false

        for event in existingEvents {
            let migrated = migratedEvent(from: event, fallbackAccountEmail: fallbackAccountEmail)
            if migrated.id != event.id || migrated.accountEmail != event.accountEmail {
                didChange = true
            }
            if migrated.id != event.id {
                idMapping[event.id] = migrated.id
            }

            if let idx = indexById[migrated.id] {
                let merged = mergeMigratedDuplicate(existing: rewrittenEvents[idx], incoming: migrated)
                if merged != rewrittenEvents[idx] {
                    rewrittenEvents[idx] = merged
                    didChange = true
                }
            } else {
                indexById[migrated.id] = rewrittenEvents.count
                rewrittenEvents.append(migrated)
            }
        }

        if didChange {
            try saveEvents(rewrittenEvents, in: workspace)
        }
        if !idMapping.isEmpty {
            try rewriteMarkdownReferenceIDs(idMapping, in: workspace)
        }
        return idMapping
    }

    // MARK: - Sources

    public func loadSources(in workspace: String) -> [CalendarSource] {
        let path = sourcesPath(in: workspace)
        guard let data = fm.contents(atPath: path) else { return [] }
        return (try? JSONDecoder().decode([CalendarSource].self, from: data)) ?? []
    }

    public func saveSources(_ sources: [CalendarSource], in workspace: String) throws {
        try ensureDirectory(in: workspace)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sources)
        try data.write(to: URL(fileURLWithPath: sourcesPath(in: workspace)), options: .atomic)
    }

    // MARK: - Overlays

    public func loadOverlays(in workspace: String) -> [CalendarOverlay] {
        let path = overlaysPath(in: workspace)
        guard let data = fm.contents(atPath: path) else { return [] }
        return (try? JSONDecoder().decode([CalendarOverlay].self, from: data)) ?? []
    }

    public func saveOverlays(_ overlays: [CalendarOverlay], in workspace: String) throws {
        try ensureDirectory(in: workspace)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(overlays)
        try data.write(to: URL(fileURLWithPath: overlaysPath(in: workspace)), options: .atomic)
    }

    // MARK: - Sync State

    public func loadSyncToken(in workspace: String) -> String? {
        let path = syncStatePath(in: workspace)
        guard let data = fm.contents(atPath: path),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return nil }
        return state.syncToken
    }

    public func saveSyncToken(_ token: String, in workspace: String) throws {
        try ensureDirectory(in: workspace)
        let state = SyncState(syncToken: token, lastSync: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(state)
        let path = syncStatePath(in: workspace)
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Link Management

    public func linkEventToPage(eventId: String, pagePath: String, in workspace: String) throws {
        var events = loadEvents(in: workspace)
        guard let idx = indexOfEvent(withID: eventId, in: events) else { return }
        events[idx].linkedPagePath = pagePath
        try saveEvents(events, in: workspace)
    }

    private func indexOfEvent(withID eventId: String, in events: [CalendarEvent]) -> Int? {
        if let exactIndex = events.firstIndex(where: { $0.id == eventId }) {
            return exactIndex
        }
        guard let targetComponents = CalendarEvent.idComponents(for: eventId) else {
            return nil
        }

        return events.firstIndex { event in
            guard let eventComponents = event.idComponents else { return false }
            guard eventComponents.calendarId == targetComponents.calendarId,
                  eventComponents.remoteID == targetComponents.remoteID else {
                return false
            }

            switch (CalendarEvent.normalizedAccountEmail(targetComponents.accountEmail), CalendarEvent.normalizedAccountEmail(eventComponents.accountEmail)) {
            case let (targetEmail?, eventEmail?):
                return targetEmail.caseInsensitiveCompare(eventEmail) == .orderedSame
            case (nil, _), (_, nil):
                return true
            }
        }
    }

    private func migratedEvent(from event: CalendarEvent, fallbackAccountEmail: String?) -> CalendarEvent {
        let explicitAccountEmail = CalendarEvent.normalizedAccountEmail(event.accountEmail)
        let idComponents = event.idComponents
        let resolvedAccountEmail = explicitAccountEmail ?? idComponents?.accountEmail ?? fallbackAccountEmail
        let rewrittenID: String

        if let remoteID = idComponents?.remoteID {
            rewrittenID = CalendarEvent.composeID(
                accountEmail: resolvedAccountEmail,
                calendarId: event.calendarId,
                remoteID: remoteID
            )
        } else {
            rewrittenID = event.id
        }

        if rewrittenID == event.id, resolvedAccountEmail == event.accountEmail {
            return event
        }

        return CalendarEvent(
            id: rewrittenID,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            calendarId: event.calendarId,
            attendees: event.attendees,
            conferenceURL: event.conferenceURL,
            htmlLink: event.htmlLink,
            linkedPagePath: event.linkedPagePath,
            accountEmail: resolvedAccountEmail
        )
    }

    private func mergeMigratedDuplicate(existing: CalendarEvent, incoming: CalendarEvent) -> CalendarEvent {
        let shouldPreferIncoming = CalendarEvent.normalizedAccountEmail(existing.accountEmail) == nil &&
            CalendarEvent.normalizedAccountEmail(incoming.accountEmail) != nil

        var preferred = shouldPreferIncoming ? incoming : existing
        let fallback = shouldPreferIncoming ? existing : incoming

        if preferred.linkedPagePath == nil {
            preferred.linkedPagePath = fallback.linkedPagePath
        }
        if preferred.accountEmail == nil {
            preferred.accountEmail = fallback.accountEmail
        }

        return preferred
    }

    private func rewriteMarkdownReferenceIDs(_ idMapping: [String: String], in workspace: String) throws {
        guard let enumerator = fm.enumerator(atPath: workspace) else { return }

        for case let relativePath as String in enumerator {
            if relativePath == ".git" || relativePath == ".build" {
                enumerator.skipDescendants()
                continue
            }
            guard relativePath.hasSuffix(".md") else { continue }

            let path = (workspace as NSString).appendingPathComponent(relativePath)
            guard let data = fm.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            let rewritten = rewriteEventIDs(in: content, using: idMapping)
            guard rewritten != content else { continue }
            try rewritten.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func rewriteEventIDs(in content: String, using idMapping: [String: String]) -> String {
        let orderedMappings = idMapping
            .filter { $0.key != $0.value }
            .sorted { lhs, rhs in lhs.key.count > rhs.key.count }

        return orderedMappings.reduce(content) { partial, entry in
            let pattern = idRewritePattern(oldID: entry.key, newID: entry.value)
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return partial
            }

            let range = NSRange(partial.startIndex..<partial.endIndex, in: partial)
            return regex.stringByReplacingMatches(
                in: partial,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: entry.value)
            )
        }
    }

    private func idRewritePattern(oldID: String, newID: String) -> String {
        let escapedOldID = NSRegularExpression.escapedPattern(for: oldID)
        guard newID.hasSuffix(oldID) else { return escapedOldID }

        let prefix = String(newID.dropLast(oldID.count))
        guard !prefix.isEmpty else { return escapedOldID }
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        return "(?<!\(escapedPrefix))\(escapedOldID)"
    }
}

// MARK: - Sync State

struct SyncState: Codable {
    let syncToken: String
    let lastSync: Date
}
