import Foundation

public enum AgentTaskStatus: String, Codable, CaseIterable, Sendable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case blocked
    case done
    case cancelled
}

public enum AgentRunStatus: String, Codable, CaseIterable, Sendable {
    case running
    case succeeded
    case failed
    case cancelled
}

public enum AgentEventLevel: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case error
}

public struct AgentTask: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var detail: String?
    public var status: AgentTaskStatus
    public var assignee: String?
    public var labels: [String]
    public var linkedPaths: [String]
    public var latestRunId: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        status: AgentTaskStatus = .todo,
        assignee: String? = nil,
        labels: [String] = [],
        linkedPaths: [String] = [],
        latestRunId: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.assignee = assignee
        self.labels = labels
        self.linkedPaths = linkedPaths
        self.latestRunId = latestRunId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AgentRun: Identifiable, Codable, Sendable {
    public let id: String
    public var taskId: String?
    public var agent: String
    public var cwd: String?
    public var branch: String?
    public var status: AgentRunStatus
    public var summary: String?
    public var commit: String?
    public var startedAt: String
    public var endedAt: String?

    public init(
        id: String,
        taskId: String? = nil,
        agent: String,
        cwd: String? = nil,
        branch: String? = nil,
        status: AgentRunStatus,
        summary: String? = nil,
        commit: String? = nil,
        startedAt: String,
        endedAt: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.agent = agent
        self.cwd = cwd
        self.branch = branch
        self.status = status
        self.summary = summary
        self.commit = commit
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct AgentEvent: Identifiable, Codable, Sendable {
    public let id: String
    public var runId: String?
    public var taskId: String?
    public var level: AgentEventLevel
    public var message: String
    public var timestamp: String

    public init(
        id: String,
        runId: String? = nil,
        taskId: String? = nil,
        level: AgentEventLevel,
        message: String,
        timestamp: String
    ) {
        self.id = id
        self.runId = runId
        self.taskId = taskId
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

public struct AgentTaskPatch: Sendable {
    public var title: String?
    public var detail: String?
    public var status: AgentTaskStatus?
    public var assignee: String?
    public var labels: [String]?
    public var linkedPaths: [String]?
    public var latestRunId: String?

    public init(
        title: String? = nil,
        detail: String? = nil,
        status: AgentTaskStatus? = nil,
        assignee: String? = nil,
        labels: [String]? = nil,
        linkedPaths: [String]? = nil,
        latestRunId: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.status = status
        self.assignee = assignee
        self.labels = labels
        self.linkedPaths = linkedPaths
        self.latestRunId = latestRunId
    }
}

public struct AgentWorkspaceInfo: Sendable {
    public let directory: String
    public let tasksPath: String
    public let runsPath: String
    public let eventsPath: String

    public init(directory: String, tasksPath: String, runsPath: String, eventsPath: String) {
        self.directory = directory
        self.tasksPath = tasksPath
        self.runsPath = runsPath
        self.eventsPath = eventsPath
    }
}

public struct AgentDashboard: Codable, Sendable {
    public var generatedAt: String
    public var taskCounts: [String: Int]
    public var activeTasks: [AgentTask]
    public var recentRuns: [AgentRun]
    public var recentEvents: [AgentEvent]

    public init(
        generatedAt: String,
        taskCounts: [String: Int],
        activeTasks: [AgentTask],
        recentRuns: [AgentRun],
        recentEvents: [AgentEvent]
    ) {
        self.generatedAt = generatedAt
        self.taskCounts = taskCounts
        self.activeTasks = activeTasks
        self.recentRuns = recentRuns
        self.recentEvents = recentEvents
    }
}

public enum AgentStoreError: Error, CustomStringConvertible {
    case invalidTaskTitle
    case taskNotFound(String)
    case runNotFound(String)
    case invalidData(String)

    public var description: String {
        switch self {
        case .invalidTaskTitle:
            return "Task title cannot be empty."
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        case .runNotFound(let id):
            return "Run not found: \(id)"
        case .invalidData(let message):
            return "Invalid agent data: \(message)"
        }
    }
}
