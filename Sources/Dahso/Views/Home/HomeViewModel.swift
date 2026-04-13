import Foundation
import SwiftUI
import DahsoCore

@MainActor
@Observable
final class HomeViewModel {
    enum TimeState: Sendable {
        case morning
        case midday
        case evening
    }

    struct InsightPill: Identifiable {
        let id = UUID()
        let label: String
        let isUrgent: Bool
    }

    struct ActivityLine: Identifiable, Sendable {
        let id = UUID()
        let text: String
        let isAgentActivity: Bool
    }

    struct CalendarItem: Identifiable, Sendable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let context: String?
        let isPast: Bool
        let isAllDay: Bool
        let calendarColor: String?
        let contextLine: String?
    }

    struct CalendarTimelineItem: Identifiable, Sendable {
        enum Kind: Sendable {
            case event(CalendarItem)
            case freeGap(String)
        }

        let id: String
        let kind: Kind
    }

    struct CarryOverItem: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let databaseName: String
    }

    struct InboxItem: Identifiable, Sendable {
        let id: String
        let sender: String
        let subject: String
        let showsReplyBadge: Bool
        let date: Date?
    }

    var timeState: TimeState = .morning
    var activeAgentCount: Int = 0
    var blockedAgentCount: Int = 0
    var blockedAgentTask: String? = nil
    var blockedAgentFinishedAt: String? = nil
    var agentCompletedToday: Int = 0
    var humanCompletedToday: Int = 0
    var humanMeetingsToday: Int = 0
    var totalEventsToday: Int = 0
    var carryOverItems: [CarryOverItem] = []
    var pills: [InsightPill] = []
    @ObservationIgnored
    @AppStorage("home.pinnedDatabasePaths") private var pinnedPathsJSON: String = "[]"
    var pinnedDatabases: [DatabaseSummary] = []
    @ObservationIgnored
    @AppStorage("home.lastSeenTimestamp") var lastSeenTimestamp: Double = 0

    var overnightItems: [ActivityLine] = []
    var overnightCount: Int = 0
    var deltaItems: [ActivityLine] = []
    var deltaCount: Int = 0
    var staleItems: [String] = []
    var todayEvents: [CalendarItem] = []
    var todayTimeline: [CalendarTimelineItem] = []
    var inboxThreads: [InboxItem] = []
    var unreadInboxCount: Int = 0
    var needsReplyCount: Int = 0
    var firstFreeGapLabel: String = "No free block left today"
    var freeUntilLabel: String? = nil
    var freedUpCount: Int = 0

    var lastSeenDate: Date {
        lastSeenTimestamp > 0
            ? Date(timeIntervalSince1970: lastSeenTimestamp)
            : Calendar.current.date(
                bySettingHour: 18,
                minute: 0,
                second: 0,
                of: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            ) ?? Date()
    }

    @ObservationIgnored private let appState: AppState
    private(set) var allDatabases: [DatabaseSummary] = []

    init(appState: AppState) {
        self.appState = appState
    }

    func load(workspacePath: String) async {
        let currentState = Self.timeState(for: Date())
        timeState = currentState

        let lastSeen = lastSeenDate
        let pinnedPaths = decodedPinnedPaths()
        let connectedEmail = appState.settings.googleConnectedEmail

        let snapshot = await Task.detached(priority: .userInitiated) {
            Self.buildSnapshot(
                workspacePath: workspacePath,
                connectedEmail: connectedEmail,
                lastSeenDate: lastSeen,
                pinnedPaths: pinnedPaths,
                timeState: currentState
            )
        }.value

        timeState = snapshot.timeState
        activeAgentCount = snapshot.activeAgentCount
        blockedAgentCount = snapshot.blockedAgentCount
        blockedAgentTask = snapshot.blockedAgentTask
        blockedAgentFinishedAt = snapshot.blockedAgentFinishedAt
        agentCompletedToday = snapshot.agentCompletedToday
        humanCompletedToday = snapshot.humanCompletedToday
        humanMeetingsToday = snapshot.humanMeetingsToday
        totalEventsToday = snapshot.totalEventsToday
        carryOverItems = snapshot.carryOverItems
        pills = snapshot.pills.map { InsightPill(label: $0.label, isUrgent: $0.isUrgent) }
        overnightItems = snapshot.overnightItems
        overnightCount = snapshot.overnightCount
        deltaItems = snapshot.deltaItems
        deltaCount = snapshot.deltaCount
        staleItems = snapshot.staleItems
        todayEvents = snapshot.todayEvents
        todayTimeline = snapshot.todayTimeline
        inboxThreads = snapshot.inboxThreads
        unreadInboxCount = snapshot.unreadInboxCount
        needsReplyCount = snapshot.needsReplyCount
        firstFreeGapLabel = snapshot.firstFreeGapLabel
        freeUntilLabel = snapshot.freeUntilLabel
        freedUpCount = snapshot.freedUpCount
        allDatabases = snapshot.allDatabases
        pinnedDatabases = snapshot.pinnedDatabases
    }

    func refreshTimeState() {
        timeState = Self.timeState(for: Date())
    }

    func markSeen() {
        lastSeenTimestamp = Date().timeIntervalSince1970
    }

    func togglePin(_ path: String) {
        pinnedPathsJSON = PinnedDatabasesHelper.togglePath(path, in: pinnedPathsJSON)
        let paths = PinnedDatabasesHelper.decodePaths(from: pinnedPathsJSON)
        let byPath = Dictionary(uniqueKeysWithValues: allDatabases.map { ($0.path, $0) })
        pinnedDatabases = paths.compactMap { byPath[$0] }
    }

    private func decodedPinnedPaths() -> [String] {
        PinnedDatabasesHelper.decodePaths(from: pinnedPathsJSON)
    }
}

struct DatabaseSummary: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let reviewCount: Int
    let todoCount: Int
    let inProgressCount: Int
    let doneCount: Int
    var reviewLabel: String
    var todoLabel: String
    var inProgressLabel: String
    var doneLabel: String
    var narrativeLine: String
    var agentActiveCount: Int
}

enum PinnedDatabasesHelper {
    static func decodePaths(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func togglePath(_ path: String, in json: String) -> String {
        var paths = decodePaths(from: json)
        if let index = paths.firstIndex(of: path) {
            paths.remove(at: index)
        } else {
            paths.append(path)
        }
        if let data = try? JSONEncoder().encode(paths),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return json
    }
}

extension HomeViewModel {
    struct Snapshot: Sendable {
        let timeState: TimeState
        let activeAgentCount: Int
        let blockedAgentCount: Int
        let blockedAgentTask: String?
        let blockedAgentFinishedAt: String?
        let agentCompletedToday: Int
        let humanCompletedToday: Int
        let humanMeetingsToday: Int
        let totalEventsToday: Int
        let carryOverItems: [CarryOverItem]
        let pills: [PillData]
        let overnightItems: [ActivityLine]
        let overnightCount: Int
        let deltaItems: [ActivityLine]
        let deltaCount: Int
        let staleItems: [String]
        let todayEvents: [CalendarItem]
        let todayTimeline: [CalendarTimelineItem]
        let inboxThreads: [InboxItem]
        let unreadInboxCount: Int
        let needsReplyCount: Int
        let firstFreeGapLabel: String
        let freeUntilLabel: String?
        let freedUpCount: Int
        let allDatabases: [DatabaseSummary]
        let pinnedDatabases: [DatabaseSummary]
    }

    struct PillData: Sendable {
        let label: String
        let isUrgent: Bool
    }

    struct DatedLine: Sendable {
        let date: Date
        let line: ActivityLine
    }

    struct TaskLinkSummary {
        let activeTasks: [AgentTask]
        let succeededLinkPathsToday: [String]
        let blockedTask: AgentTask?
        let blockedTaskFinishedAt: String?
    }

    struct RowSummary {
        let title: String
        let databaseName: String
        let updatedAt: Date
    }

    nonisolated static func buildSnapshot(
        workspacePath: String,
        connectedEmail: String,
        lastSeenDate: Date,
        pinnedPaths: [String],
        timeState: TimeState,
        mailCacheStore: MailCacheStore = MailCacheStore()
    ) -> Snapshot {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let staleCutoff = calendar.date(byAdding: .day, value: -3, to: now) ?? now

        let agentStore = AgentWorkspaceStore()
        let tasks = (try? agentStore.listTasks(in: workspacePath)) ?? []
        let runs = (try? agentStore.listRuns(in: workspacePath, limit: 200)) ?? []
        let mailSnapshot = connectedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : mailCacheStore.load(accountEmail: connectedEmail)
        let allInboxThreads = (mailSnapshot?.mailboxThreads[.inbox] ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let inboxUnreadThreads = allInboxThreads.filter(\.isUnread)

        let taskLinks = taskLinkSummary(tasks: tasks, runs: runs, startOfToday: startOfToday)
        let databaseSnapshot = databaseSnapshot(
            workspacePath: workspacePath,
            activeTasks: taskLinks.activeTasks,
            succeededLinkPathsToday: taskLinks.succeededLinkPathsToday,
            startOfToday: startOfToday,
            staleCutoff: staleCutoff
        )

        let calendarStore = CalendarEventStore()
        let todayEventsRaw = calendarStore.loadEvents(in: workspacePath)
            .filter { event in
                calendar.isDate(event.startDate, inSameDayAs: now) ||
                    calendar.isDate(event.endDate, inSameDayAs: now)
            }
            .sorted { $0.startDate < $1.startDate }

        // Deduplicate events with same title + start time (multi-calendar sync)
        var seenKeys = Set<String>()
        let todayEvents = todayEventsRaw.filter { event in
            let key = "\(event.title)|\(event.startDate.timeIntervalSince1970)"
            return seenKeys.insert(key).inserted
        }

        // Meeting = event with 2+ attendees or a video conference link
        let meetingCount = todayEvents.filter {
            $0.attendees.count >= 2 || $0.conferenceURL != nil
        }.count

        let sources = calendarStore.loadSources(in: workspacePath)
        let sourceColorMap = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.color) })

        let calendarSummary = calendarSummary(events: todayEvents, now: now, calendar: calendar, sourceColorMap: sourceColorMap)
        // Show recent inbox threads (not just unread) in the home inbox list
        let inboxItems = Array(allInboxThreads.map { thread in
            InboxItem(
                id: thread.id,
                sender: parseDisplayName(from: thread.participants.first ?? "Unknown sender"),
                subject: thread.subject,
                showsReplyBadge: thread.annotation?.statusFlags.contains(.needsReply) == true,
                date: thread.date
            )
        }.prefix(5))

        let mailItems = inboxUnreadThreads
            .compactMap { thread -> DatedLine? in
                guard let date = thread.date, date >= lastSeenDate else { return nil }
                let sender = thread.participants.first ?? "Unknown sender"
                return DatedLine(
                    date: date,
                    line: ActivityLine(
                        text: "\(sender): \(thread.subject)",
                        isAgentActivity: false
                    )
                )
            }

        let runItems = runs.compactMap { run -> DatedLine? in
            let date = agentDate(run.endedAt ?? run.startedAt)
            guard let date, date >= lastSeenDate else { return nil }
            let label = agentLine(for: run, tasks: tasks)
            return DatedLine(date: date, line: ActivityLine(text: label, isAgentActivity: true))
        }

        let blockedItems = tasks.compactMap { task -> DatedLine? in
            guard task.status == .blocked,
                  let updatedAt = agentDate(task.updatedAt),
                  updatedAt >= lastSeenDate else {
                return nil
            }
            return DatedLine(
                date: updatedAt,
                line: ActivityLine(text: "Blocked on \(task.title)", isAgentActivity: true)
            )
        }

        let combinedActivity = (mailItems + runItems + blockedItems)
            .sorted { $0.date > $1.date }
        let visibleActivity = Array(combinedActivity.prefix(4)).map(\.line)

        let staleMailItems = inboxUnreadThreads
            .filter { ($0.date ?? .distantFuture) < staleCutoff }
            .prefix(2)
            .map { thread in
                let sender = thread.participants.first ?? "Unknown sender"
                return "\(sender) waiting on \(thread.subject)"
            }
        let unreadInboxCount = inboxUnreadThreads.count
        let needsReplyCount = inboxUnreadThreads.filter {
            $0.annotation?.statusFlags.contains(.needsReply) == true
        }.count
        let freedUpCount = runs.filter { run in
            run.status == .succeeded &&
                (agentDate(run.endedAt) ?? .distantPast) >= lastSeenDate
        }.count
        let agentCompletedToday = runs.filter { run in
            guard run.status == .succeeded,
                  let endedAt = agentDate(run.endedAt) else {
                return false
            }
            return endedAt >= startOfToday
        }.count

        let activeAgentCount = taskLinks.activeTasks.count
        let blockedAgentCount = tasks.filter { $0.status == .blocked }.count

        let pills = buildPills(
            timeState: timeState,
            blockedAgentCount: blockedAgentCount,
            activeAgentCount: activeAgentCount,
            needsReplyCount: needsReplyCount,
            unreadInboxCount: unreadInboxCount,
            freedUpCount: freedUpCount,
            totalClosed: databaseSnapshot.humanCompletedToday + agentCompletedToday,
            carryOverCount: databaseSnapshot.carryOverItems.count,
            freeUntilLabel: calendarSummary.freeUntilLabel,
            eventCount: todayEvents.count,
            meetingCount: meetingCount
        )

        let allDatabases = databaseSnapshot.databases
        let byPath = Dictionary(uniqueKeysWithValues: allDatabases.map { ($0.path, $0) })
        let pinnedDatabases = pinnedPaths.compactMap { byPath[$0] }

        return Snapshot(
            timeState: timeState,
            activeAgentCount: activeAgentCount,
            blockedAgentCount: blockedAgentCount,
            blockedAgentTask: taskLinks.blockedTask?.title,
            blockedAgentFinishedAt: taskLinks.blockedTaskFinishedAt,
            agentCompletedToday: agentCompletedToday,
            humanCompletedToday: databaseSnapshot.humanCompletedToday,
            humanMeetingsToday: meetingCount,
            totalEventsToday: todayEvents.count,
            carryOverItems: databaseSnapshot.carryOverItems,
            pills: pills,
            overnightItems: visibleActivity,
            overnightCount: combinedActivity.count,
            deltaItems: visibleActivity,
            deltaCount: combinedActivity.count,
            staleItems: Array((databaseSnapshot.staleItems + staleMailItems).prefix(4)),
            todayEvents: calendarSummary.items,
            todayTimeline: calendarSummary.timeline,
            inboxThreads: inboxItems,
            unreadInboxCount: unreadInboxCount,
            needsReplyCount: needsReplyCount,
            firstFreeGapLabel: calendarSummary.firstFreeGapLabel,
            freeUntilLabel: calendarSummary.freeUntilLabel,
            freedUpCount: freedUpCount,
            allDatabases: allDatabases,
            pinnedDatabases: pinnedDatabases
        )
    }

    nonisolated static func timeState(for date: Date) -> TimeState {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 12 {
            return .morning
        }
        if hour < 17 {
            return .midday
        }
        return .evening
    }

    nonisolated static func taskLinkSummary(
        tasks: [AgentTask],
        runs: [AgentRun],
        startOfToday: Date
    ) -> TaskLinkSummary {
        let runByID = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        let activeTasks = tasks.filter { $0.status == .inProgress }

        let succeededTasksToday = tasks.filter { task in
            guard let runID = task.latestRunId,
                  let run = runByID[runID],
                  run.status == .succeeded,
                  let endedAt = agentDate(run.endedAt) else {
                return false
            }
            return endedAt >= startOfToday
        }

        let blockedTask = tasks
            .filter { $0.status == .blocked }
            .sorted { lhs, rhs in
                (agentDate(lhs.updatedAt) ?? .distantPast) > (agentDate(rhs.updatedAt) ?? .distantPast)
            }
            .first

        let blockedFinishedAt: String?
        if let blockedTask,
           let runID = blockedTask.latestRunId,
           let endedAt = runByID[runID].flatMap({ agentDate($0.endedAt) ?? agentDate($0.startedAt) }) {
            blockedFinishedAt = endedAt.formatted(.dateTime.hour().minute())
        } else if let blockedTask,
                  let updatedAt = agentDate(blockedTask.updatedAt) {
            blockedFinishedAt = updatedAt.formatted(.dateTime.hour().minute())
        } else {
            blockedFinishedAt = nil
        }

        return TaskLinkSummary(
            activeTasks: activeTasks,
            succeededLinkPathsToday: succeededTasksToday.flatMap(\.linkedPaths),
            blockedTask: blockedTask,
            blockedTaskFinishedAt: blockedFinishedAt
        )
    }

    nonisolated static func databaseSnapshot(
        workspacePath: String,
        activeTasks: [AgentTask],
        succeededLinkPathsToday: [String],
        startOfToday: Date,
        staleCutoff: Date
    ) -> (
        databases: [DatabaseSummary],
        humanCompletedToday: Int,
        carryOverItems: [CarryOverItem],
        staleItems: [String]
    ) {
        let dbStore = DatabaseStore()
        let rowStore = RowStore()

        var databases: [DatabaseSummary] = []
        var humanCompletedToday = 0
        var carryOverRows: [RowSummary] = []
        var staleRows: [RowSummary] = []

        for info in dbStore.listDatabases(in: workspacePath) {
            guard let schema = try? dbStore.loadSchema(at: info.path) else { continue }
            let detailedRows = rowStore.loadAllRowsDetailed(in: info.path, schema: schema)
            let statusProperty = schema.properties.first(where: { $0.type == .select })
            let optionMap = Dictionary(
                uniqueKeysWithValues: (statusProperty?.options ?? []).map { ($0.id, $0.name) }
            )

            var reviewCount = 0
            var todoCount = 0
            var inProgressCount = 0
            var doneCount = 0
            var reviewLabel: String?
            var todoLabel: String?
            var inProgressLabel: String?
            var doneLabel: String?
            let agentActiveCount = activeTasks.filter { task in
                task.linkedPaths.contains { linkPath in
                    linkPath == info.path ||
                        linkPath.hasPrefix(info.path) ||
                        info.path.hasPrefix(linkPath)
                }
            }.count

            for detail in detailedRows {
                let row = detail.row
                let rowPath = (info.path as NSString).appendingPathComponent(detail.filename)
                let title = row.title(schema: schema)
                let statusValue: String?
                if let statusProperty,
                   case .select(let optionID) = row.properties[statusProperty.id] {
                    statusValue = optionMap[optionID] ?? optionID
                } else {
                    statusValue = nil
                }

                switch statusBucket(for: statusValue) {
                case .review:
                    reviewCount += 1
                    if reviewLabel == nil { reviewLabel = statusValue }
                case .todo:
                    todoCount += 1
                    if todoLabel == nil { todoLabel = statusValue }
                case .inProgress:
                    inProgressCount += 1
                    if inProgressLabel == nil { inProgressLabel = statusValue }
                case .done:
                    doneCount += 1
                    if doneLabel == nil { doneLabel = statusValue }
                case .none:
                    break
                }

                let isDone = statusBucket(for: statusValue) == .done
                if !isDone && row.updatedAt < startOfToday {
                    carryOverRows.append(RowSummary(title: title, databaseName: info.name, updatedAt: row.updatedAt))
                }
                if !isDone && row.updatedAt < staleCutoff {
                    staleRows.append(RowSummary(title: title, databaseName: info.name, updatedAt: row.updatedAt))
                }

                if isDone && row.updatedAt >= startOfToday {
                    let coveredByAgent = succeededLinkPathsToday.contains { linkPath in
                        rowPath.hasPrefix(linkPath) || linkPath == info.path
                    }
                    if !coveredByAgent {
                        humanCompletedToday += 1
                    }
                }
            }

            let rl = reviewLabel ?? "Review"
            let tl = todoLabel ?? "To Do"
            let pl = inProgressLabel ?? "In Progress"
            let dl = doneLabel ?? "Done"

            databases.append(
                DatabaseSummary(
                    name: info.name,
                    path: info.path,
                    reviewCount: reviewCount,
                    todoCount: todoCount,
                    inProgressCount: inProgressCount,
                    doneCount: doneCount,
                    reviewLabel: rl,
                    todoLabel: tl,
                    inProgressLabel: pl,
                    doneLabel: dl,
                    narrativeLine: narrativeLine(
                        reviewCount: reviewCount, reviewLabel: rl,
                        todoCount: todoCount, todoLabel: tl,
                        inProgressCount: inProgressCount, inProgressLabel: pl,
                        doneCount: doneCount, doneLabel: dl,
                        agentActiveCount: agentActiveCount
                    ),
                    agentActiveCount: agentActiveCount
                )
            )
        }

        databases.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return (
            databases: databases,
            humanCompletedToday: humanCompletedToday,
            carryOverItems: carryOverRows
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(4)
                .map { CarryOverItem(title: $0.title, databaseName: $0.databaseName) },
            staleItems: staleRows
                .sorted { $0.updatedAt < $1.updatedAt }
                .prefix(4)
                .map { "\($0.title) — \($0.databaseName)" }
        )
    }

    nonisolated static func calendarSummary(
        events: [CalendarEvent],
        now: Date,
        calendar: Calendar,
        sourceColorMap: [String: String] = [:]
    ) -> (items: [CalendarItem], timeline: [CalendarTimelineItem], firstFreeGapLabel: String, freeUntilLabel: String?, largestGapMinutes: Int) {
        let items = events.map { event in
            CalendarItem(
                id: event.id,
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                context: event.isAllDay ? nil : durationLabel(start: event.startDate, end: event.endDate),
                isPast: event.endDate < now,
                isAllDay: event.isAllDay,
                calendarColor: sourceColorMap[event.calendarId],
                contextLine: eventContextLine(event)
            )
        }

        var largestGapMinutes = 0
        var largestGapInsertIndex: Int?
        if items.count > 1 {
            for index in 0..<(items.count - 1) {
                let current = items[index]
                let next = items[index + 1]
                let gapMinutes = max(0, Int(next.startDate.timeIntervalSince(current.endDate) / 60))
                if gapMinutes > largestGapMinutes {
                    largestGapMinutes = gapMinutes
                    largestGapInsertIndex = index + 1
                }
            }
        }

        var timeline: [CalendarTimelineItem] = []
        for (index, item) in items.enumerated() {
            if let largestGapInsertIndex,
               largestGapInsertIndex == index,
               largestGapMinutes > 0 {
                timeline.append(
                    CalendarTimelineItem(
                        id: "gap-\(index)",
                        kind: .freeGap("\(formatFreeTime(minutes: largestGapMinutes)) free")
                    )
                )
            }
            timeline.append(CalendarTimelineItem(id: item.id, kind: .event(item)))
        }

        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let firstFreeGapLabel = Self.firstFreeGap(events: events, now: now, dayEnd: dayEnd)
        let freeUntilLabel = Self.freeUntil(events: events, now: now)

        return (items, timeline, firstFreeGapLabel, freeUntilLabel, largestGapMinutes)
    }

    nonisolated static func firstFreeGap(events: [CalendarEvent], now: Date, dayEnd: Date) -> String {
        var cursor = now

        for event in events where event.endDate > now {
            if event.startDate > cursor {
                let minutes = max(0, Int(event.startDate.timeIntervalSince(cursor) / 60))
                if minutes > 0 {
                    return "\(formatFreeTime(minutes: minutes)) at \(cursor.formatted(.dateTime.hour().minute()))"
                }
            }
            cursor = max(cursor, event.endDate)
        }

        let remainingMinutes = max(0, Int(dayEnd.timeIntervalSince(cursor) / 60))
        if remainingMinutes > 0 {
            return "\(formatFreeTime(minutes: remainingMinutes)) at \(cursor.formatted(.dateTime.hour().minute()))"
        }

        return "No free block left today"
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "a"
        f.pmSymbol = "p"
        return f
    }()

    /// Returns "Free until HH:MM" for the pill, or nil if currently in an event or no events remain.
    nonisolated static func freeUntil(events: [CalendarEvent], now: Date) -> String? {
        var cursor = now

        for event in events where event.endDate > now {
            if event.startDate > cursor {
                return "Free until \(shortTimeFormatter.string(from: event.startDate))"
            }
            cursor = max(cursor, event.endDate)
        }

        if cursor <= now {
            return "Free rest of day"
        }
        return nil
    }

    nonisolated static func buildPills(
        timeState: TimeState,
        blockedAgentCount: Int,
        activeAgentCount: Int,
        needsReplyCount: Int,
        unreadInboxCount: Int,
        freedUpCount: Int,
        totalClosed: Int,
        carryOverCount: Int,
        freeUntilLabel: String?,
        eventCount: Int,
        meetingCount: Int
    ) -> [PillData] {
        switch timeState {
        case .morning:
            return [
                blockedAgentCount > 0 ? PillData(label: "\(blockedAgentCount) agent\(blockedAgentCount == 1 ? "" : "s") waiting on you", isUrgent: true) : nil,
                activeAgentCount > 0 ? PillData(label: "\(activeAgentCount) agent\(activeAgentCount == 1 ? "" : "s") running", isUrgent: false) : nil,
                needsReplyCount > 0 ? PillData(label: "\(needsReplyCount) email\(needsReplyCount == 1 ? "" : "s") need reply", isUrgent: true) : nil,
                meetingCount > 0 ? PillData(label: "\(meetingCount) meeting\(meetingCount == 1 ? "" : "s") today", isUrgent: false) : nil,
                freeUntilLabel.map { PillData(label: $0, isUrgent: false) },
                eventCount > 0 && meetingCount == 0 ? PillData(label: "\(eventCount) events on calendar", isUrgent: false) : nil,
            ].compactMap { $0 }
        case .midday:
            return [
                blockedAgentCount > 0 ? PillData(label: "\(blockedAgentCount) agent\(blockedAgentCount == 1 ? "" : "s") waiting on you", isUrgent: true) : nil,
                freedUpCount > 0 ? PillData(label: "\(freedUpCount) agent task\(freedUpCount == 1 ? "" : "s") completed", isUrgent: true) : nil,
                needsReplyCount > 0 ? PillData(label: "\(needsReplyCount) email\(needsReplyCount == 1 ? "" : "s") need reply", isUrgent: false) : nil,
                unreadInboxCount > 0 ? PillData(label: "\(unreadInboxCount) unread email\(unreadInboxCount == 1 ? "" : "s")", isUrgent: false) : nil,
                freeUntilLabel.map { PillData(label: $0, isUrgent: false) },
            ].compactMap { $0 }
        case .evening:
            return [
                totalClosed > 0 ? PillData(label: "\(totalClosed) ticket\(totalClosed == 1 ? "" : "s") closed today", isUrgent: false) : nil,
                meetingCount > 0 ? PillData(label: "\(meetingCount) meeting\(meetingCount == 1 ? "" : "s") today", isUrgent: false) : nil,
                carryOverCount > 0 ? PillData(label: "\(carryOverCount) task\(carryOverCount == 1 ? "" : "s") carrying to tomorrow", isUrgent: false) : nil,
                unreadInboxCount == 0 ? PillData(label: "Inbox at zero", isUrgent: false) : PillData(label: "\(unreadInboxCount) email\(unreadInboxCount == 1 ? "" : "s") in inbox", isUrgent: false),
            ].compactMap { $0 }
        }
    }

    enum StatusBucket {
        case review
        case todo
        case inProgress
        case done
    }

    nonisolated static func statusBucket(for rawValue: String?) -> StatusBucket? {
        guard let rawValue else { return nil }
        let value = rawValue.lowercased()
        if value.contains("review") {
            return .review
        }
        if value.contains("done") || value.contains("complete") || value.contains("closed") {
            return .done
        }
        if value.contains("progress") || value.contains("doing") {
            return .inProgress
        }
        if value.contains("todo") || value.contains("to do") || value.contains("not started") || value.contains("backlog") || value.contains("queued") {
            return .todo
        }
        return nil
    }

    nonisolated static func narrativeLine(
        reviewCount: Int, reviewLabel: String,
        todoCount: Int, todoLabel: String,
        inProgressCount: Int, inProgressLabel: String,
        doneCount: Int, doneLabel: String,
        agentActiveCount: Int
    ) -> String {
        var parts: [String] = []
        if reviewCount > 0 { parts.append("\(reviewCount) \(reviewLabel)") }
        if todoCount > 0 { parts.append("\(todoCount) \(todoLabel)") }
        if inProgressCount > 0 { parts.append("\(inProgressCount) \(inProgressLabel)") }
        if doneCount > 0 && parts.count < 2 { parts.append("\(doneCount) \(doneLabel)") }
        if agentActiveCount > 0 { parts.append("\(agentActiveCount) agent active") }
        if parts.isEmpty {
            return "Quiet right now."
        }
        return parts.prefix(3).joined(separator: " · ")
    }

    nonisolated static func agentLine(for run: AgentRun, tasks: [AgentTask]) -> String {
        let taskTitle = tasks.first(where: { $0.id == run.taskId })?.title ?? run.summary ?? "background task"
        switch run.status {
        case .running:
            return "Agent running \(taskTitle)"
        case .succeeded:
            return "Agent finished \(taskTitle)"
        case .failed:
            return "Agent failed \(taskTitle)"
        case .cancelled:
            return "Agent cancelled \(taskTitle)"
        }
    }

    nonisolated static func eventContextLine(_ event: CalendarEvent) -> String? {
        var parts: [String] = []
        if let url = event.conferenceURL, !url.isEmpty {
            if url.contains("meet.google") { parts.append("Google Meet") }
            else if url.contains("zoom") { parts.append("Zoom") }
            else if url.contains("teams") { parts.append("Teams") }
            else { parts.append("Video call") }
        }
        if event.attendees.count >= 2 {
            parts.append("\(event.attendees.count) attendees")
        }
        if event.linkedPagePath != nil {
            parts.append("notes linked")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    nonisolated static func parseDisplayName(from raw: String) -> String {
        if let idx = raw.firstIndex(of: "<") {
            let name = raw[raw.startIndex..<idx].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return raw
    }

    nonisolated static func formatFreeTime(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours) hr\(hours == 1 ? "" : "s")" }
        return "\(hours)h \(remainder)m"
    }

    nonisolated static func durationLabel(start: Date, end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return "\(minutes)m"
    }

    private static let agentDateFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let agentDateFormatterBasic = ISO8601DateFormatter()

    nonisolated static func agentDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        return agentDateFormatterFractional.date(from: rawValue)
            ?? agentDateFormatterBasic.date(from: rawValue)
    }
}
