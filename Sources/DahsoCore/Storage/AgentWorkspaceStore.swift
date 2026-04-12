import Foundation

public class AgentWorkspaceStore {
    private struct TaskEnvelope: Codable {
        var version: Int
        var tasks: [AgentTask]
    }

    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let isoFormatter: ISO8601DateFormatter

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }

    public func info(in workspacePath: String) -> AgentWorkspaceInfo {
        let directory = (workspacePath as NSString).appendingPathComponent(".dahso/agents")
        return AgentWorkspaceInfo(
            directory: directory,
            tasksPath: (directory as NSString).appendingPathComponent("tasks.json"),
            runsPath: (directory as NSString).appendingPathComponent("runs.jsonl"),
            eventsPath: (directory as NSString).appendingPathComponent("events.jsonl")
        )
    }

    @discardableResult
    public func ensureWorkspaceFiles(in workspacePath: String) throws -> AgentWorkspaceInfo {
        let paths = info(in: workspacePath)
        if !fm.fileExists(atPath: paths.directory) {
            try fm.createDirectory(atPath: paths.directory, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: paths.tasksPath) {
            let envelope = TaskEnvelope(version: 1, tasks: [])
            let data = try encoder.encode(envelope)
            try data.write(to: URL(fileURLWithPath: paths.tasksPath), options: .atomic)
        }

        if !fm.fileExists(atPath: paths.runsPath) {
            try Data().write(to: URL(fileURLWithPath: paths.runsPath), options: .atomic)
        }

        if !fm.fileExists(atPath: paths.eventsPath) {
            try Data().write(to: URL(fileURLWithPath: paths.eventsPath), options: .atomic)
        }

        return paths
    }

    public func listTasks(in workspacePath: String, status: AgentTaskStatus? = nil) throws -> [AgentTask] {
        let tasks = try loadTasks(in: workspacePath)
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let status else { return tasks }
        return tasks.filter { $0.status == status }
    }

    public func createTask(
        in workspacePath: String,
        title: String,
        detail: String? = nil,
        status: AgentTaskStatus = .todo,
        assignee: String? = nil,
        labels: [String] = [],
        linkedPaths: [String] = []
    ) throws -> AgentTask {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw AgentStoreError.invalidTaskTitle
        }

        let now = timestamp()
        var tasks = try loadTasks(in: workspacePath)
        let task = AgentTask(
            id: generateId(prefix: "task"),
            title: trimmedTitle,
            detail: detail?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            assignee: assignee?.trimmingCharacters(in: .whitespacesAndNewlines),
            labels: normalizeValues(labels),
            linkedPaths: normalizeValues(linkedPaths),
            latestRunId: nil,
            createdAt: now,
            updatedAt: now
        )
        tasks.append(task)
        try saveTasks(tasks, in: workspacePath)
        return task
    }

    public func updateTask(
        in workspacePath: String,
        id taskId: String,
        patch: AgentTaskPatch
    ) throws -> AgentTask {
        var tasks = try loadTasks(in: workspacePath)
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else {
            throw AgentStoreError.taskNotFound(taskId)
        }

        if let title = patch.title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AgentStoreError.invalidTaskTitle }
            tasks[idx].title = trimmed
        }

        if let detail = patch.detail {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            tasks[idx].detail = trimmed.isEmpty ? nil : trimmed
        }

        if let status = patch.status {
            tasks[idx].status = status
        }

        if let assignee = patch.assignee {
            let trimmed = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
            tasks[idx].assignee = trimmed.isEmpty ? nil : trimmed
        }

        if let labels = patch.labels {
            tasks[idx].labels = normalizeValues(labels)
        }

        if let linkedPaths = patch.linkedPaths {
            tasks[idx].linkedPaths = normalizeValues(linkedPaths)
        }

        if let latestRunId = patch.latestRunId {
            let trimmed = latestRunId.trimmingCharacters(in: .whitespacesAndNewlines)
            tasks[idx].latestRunId = trimmed.isEmpty ? nil : trimmed
        }

        tasks[idx].updatedAt = timestamp()
        let updated = tasks[idx]
        try saveTasks(tasks, in: workspacePath)
        return updated
    }

    public func task(in workspacePath: String, id taskId: String) throws -> AgentTask {
        let tasks = try loadTasks(in: workspacePath)
        guard let task = tasks.first(where: { $0.id == taskId }) else {
            throw AgentStoreError.taskNotFound(taskId)
        }
        return task
    }

    public func listRuns(in workspacePath: String, limit: Int? = nil, taskId: String? = nil) throws -> [AgentRun] {
        var runs = try loadRuns(in: workspacePath)
        if let taskId {
            runs = runs.filter { $0.taskId == taskId }
        }
        runs.sort { $0.startedAt > $1.startedAt }

        if let limit, limit > 0 {
            return Array(runs.prefix(limit))
        }
        return runs
    }

    public func startRun(
        in workspacePath: String,
        taskId: String? = nil,
        agent: String,
        cwd: String? = nil,
        branch: String? = nil
    ) throws -> AgentRun {
        _ = try ensureWorkspaceFiles(in: workspacePath)

        let resolvedTaskId: String?
        if let taskId {
            _ = try task(in: workspacePath, id: taskId)
            resolvedTaskId = taskId
        } else {
            resolvedTaskId = nil
        }

        let now = timestamp()
        let run = AgentRun(
            id: generateId(prefix: "run"),
            taskId: resolvedTaskId,
            agent: normalizedSingleValue(agent) ?? "agent",
            cwd: normalizedSingleValue(cwd),
            branch: normalizedSingleValue(branch),
            status: .running,
            summary: nil,
            commit: nil,
            startedAt: now,
            endedAt: nil
        )

        try appendJSONLine(run, to: info(in: workspacePath).runsPath)

        if let taskId = resolvedTaskId {
            _ = try updateTask(
                in: workspacePath,
                id: taskId,
                patch: AgentTaskPatch(status: .inProgress, latestRunId: run.id)
            )
        }

        return run
    }

    public func finishRun(
        in workspacePath: String,
        runId: String,
        status: AgentRunStatus,
        summary: String? = nil,
        commit: String? = nil
    ) throws -> AgentRun {
        var runs = try loadRuns(in: workspacePath)
        guard let idx = runs.firstIndex(where: { $0.id == runId }) else {
            throw AgentStoreError.runNotFound(runId)
        }

        runs[idx].status = status
        runs[idx].summary = normalizedSingleValue(summary)
        runs[idx].commit = normalizedSingleValue(commit)
        runs[idx].endedAt = timestamp()

        let updated = runs[idx]
        try saveJSONLines(runs, to: info(in: workspacePath).runsPath)
        return updated
    }

    public func listEvents(
        in workspacePath: String,
        limit: Int? = nil,
        runId: String? = nil,
        taskId: String? = nil
    ) throws -> [AgentEvent] {
        var events = try loadEvents(in: workspacePath)

        if let runId {
            events = events.filter { $0.runId == runId }
        }

        if let taskId {
            events = events.filter { $0.taskId == taskId }
        }

        events.sort { $0.timestamp > $1.timestamp }
        if let limit, limit > 0 {
            return Array(events.prefix(limit))
        }
        return events
    }

    public func logEvent(
        in workspacePath: String,
        runId: String? = nil,
        taskId: String? = nil,
        level: AgentEventLevel = .info,
        message: String
    ) throws -> AgentEvent {
        _ = try ensureWorkspaceFiles(in: workspacePath)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw AgentStoreError.invalidData("Event message cannot be empty")
        }

        let event = AgentEvent(
            id: generateId(prefix: "evt"),
            runId: normalizedSingleValue(runId),
            taskId: normalizedSingleValue(taskId),
            level: level,
            message: trimmedMessage,
            timestamp: timestamp()
        )

        try appendJSONLine(event, to: info(in: workspacePath).eventsPath)
        return event
    }

    public func dashboard(in workspacePath: String, runLimit: Int = 20, eventLimit: Int = 40) throws -> AgentDashboard {
        let tasks = try listTasks(in: workspacePath)
        let counts = Dictionary(grouping: tasks, by: { $0.status.rawValue }).mapValues(\.count)

        let activeStatuses: Set<AgentTaskStatus> = [.todo, .inProgress, .blocked, .backlog]
        let activeTasks = tasks
            .filter { activeStatuses.contains($0.status) }
            .sorted { $0.updatedAt > $1.updatedAt }

        return AgentDashboard(
            generatedAt: timestamp(),
            taskCounts: counts,
            activeTasks: activeTasks,
            recentRuns: try listRuns(in: workspacePath, limit: runLimit),
            recentEvents: try listEvents(in: workspacePath, limit: eventLimit)
        )
    }

    // MARK: - Private

    private func loadTasks(in workspacePath: String) throws -> [AgentTask] {
        _ = try ensureWorkspaceFiles(in: workspacePath)
        let path = info(in: workspacePath).tasksPath
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard !data.isEmpty else { return [] }

        let envelope: TaskEnvelope
        do {
            envelope = try decoder.decode(TaskEnvelope.self, from: data)
        } catch {
            throw AgentStoreError.invalidData("Could not decode tasks.json")
        }

        return envelope.tasks
    }

    private func saveTasks(_ tasks: [AgentTask], in workspacePath: String) throws {
        _ = try ensureWorkspaceFiles(in: workspacePath)
        let envelope = TaskEnvelope(version: 1, tasks: tasks)
        let data = try encoder.encode(envelope)
        try data.write(to: URL(fileURLWithPath: info(in: workspacePath).tasksPath), options: .atomic)
    }

    private func loadRuns(in workspacePath: String) throws -> [AgentRun] {
        _ = try ensureWorkspaceFiles(in: workspacePath)
        return try loadJSONLines(path: info(in: workspacePath).runsPath, as: AgentRun.self)
    }

    private func loadEvents(in workspacePath: String) throws -> [AgentEvent] {
        _ = try ensureWorkspaceFiles(in: workspacePath)
        return try loadJSONLines(path: info(in: workspacePath).eventsPath, as: AgentEvent.self)
    }

    private func loadJSONLines<T: Decodable>(path: String, as type: T.Type) throws -> [T] {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)

        var decoded: [T] = []
        decoded.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            guard let data = String(line).data(using: .utf8) else {
                throw AgentStoreError.invalidData("Could not parse line \(index + 1) in \((path as NSString).lastPathComponent)")
            }
            do {
                decoded.append(try decoder.decode(T.self, from: data))
            } catch {
                throw AgentStoreError.invalidData("Could not decode line \(index + 1) in \((path as NSString).lastPathComponent)")
            }
        }

        return decoded
    }

    private func saveJSONLines<T: Encodable>(_ values: [T], to path: String) throws {
        let lines = try values.map { value in
            let data = try JSONEncoder().encode(value)
            guard let line = String(data: data, encoding: .utf8) else {
                throw AgentStoreError.invalidData("Failed to encode JSON line")
            }
            return line
        }

        let contents = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to path: String) throws {
        let lineData = try JSONEncoder().encode(value)
        guard var line = String(data: lineData, encoding: .utf8) else {
            throw AgentStoreError.invalidData("Failed to encode JSON line")
        }
        line += "\n"

        guard let data = line.data(using: .utf8) else {
            throw AgentStoreError.invalidData("Failed to encode JSON line data")
        }

        if fm.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(data)
        } else {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    private func generateId(prefix: String) -> String {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)
        return "\(prefix)_\(token)"
    }

    private func timestamp() -> String {
        isoFormatter.string(from: Date())
    }

    private func normalizeValues(_ values: [String]) -> [String] {
        Array(Set(values.compactMap { normalizedSingleValue($0) })).sorted()
    }

    private func normalizedSingleValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
