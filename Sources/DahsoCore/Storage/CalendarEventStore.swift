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
            if let idx = indexById[event.id] {
                // Preserve linked page path from existing event
                var updated = event
                if updated.linkedPagePath == nil {
                    updated.linkedPagePath = existing[idx].linkedPagePath
                }
                existing[idx] = updated
            } else {
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
        guard let idx = events.firstIndex(where: { $0.id == eventId }) else { return }
        events[idx].linkedPagePath = pagePath
        try saveEvents(events, in: workspace)
    }
}

// MARK: - Sync State

struct SyncState: Codable {
    let syncToken: String
    let lastSync: Date
}
