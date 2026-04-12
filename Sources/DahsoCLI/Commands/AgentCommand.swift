import ArgumentParser
import Foundation
import DahsoCore

struct Agent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "Agent workflow commands (tasks, runs, events)",
        subcommands: [Init.self, Dashboard.self, Task.self, Run.self, Event.self]
    )

    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "init",
            abstract: "Initialize workspace files for agent tracking"
        )

        @OptionGroup var options: Dahso.Options

        @Flag(name: .long, help: "Also write AGENTS.md template in workspace")
        var writeAgentsMd: Bool = false

        @Flag(name: .long, help: "Overwrite existing AGENTS.md if present")
        var force: Bool = false

        func run() throws {
            let store = AgentWorkspaceStore()
            let paths = try store.ensureWorkspaceFiles(in: options.resolvedWorkspace)

            var output: [String: Any] = [
                "workspace": options.resolvedWorkspace,
                "directory": paths.directory,
                "tasks": paths.tasksPath,
                "runs": paths.runsPath,
                "events": paths.eventsPath,
                "initialized": true,
            ]

            if writeAgentsMd {
                let agentsPath = (options.resolvedWorkspace as NSString).appendingPathComponent("AGENTS.md")
                let exists = FileManager.default.fileExists(atPath: agentsPath)
                if exists && !force {
                    output["agents_md"] = [
                        "path": agentsPath,
                        "updated": false,
                        "reason": "already_exists",
                    ]
                } else {
                    let content = defaultAgentsTemplate(workspace: options.resolvedWorkspace)
                    try content.write(toFile: agentsPath, atomically: true, encoding: .utf8)
                    output["agents_md"] = [
                        "path": agentsPath,
                        "updated": true,
                    ]
                }
            }

            try outputJSON(output)
        }
    }

    struct Dashboard: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dashboard",
            abstract: "Show task/run/event summary"
        )

        @OptionGroup var options: Dahso.Options

        @Option(help: "Limit for recent runs")
        var runLimit: Int = 20

        @Option(help: "Limit for recent events")
        var eventLimit: Int = 40

        func run() throws {
            let store = AgentWorkspaceStore()
            let dashboard = try store.dashboard(
                in: options.resolvedWorkspace,
                runLimit: runLimit,
                eventLimit: eventLimit
            )
            try outputEncodable(dashboard)
        }
    }

    struct Task: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "task",
            abstract: "Manage agent tasks",
            subcommands: [List.self, Create.self, Update.self]
        )

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "list", abstract: "List tasks")

            @OptionGroup var options: Dahso.Options

            @Option(help: "Filter by status")
            var status: AgentTaskStatus?

            func run() throws {
                let store = AgentWorkspaceStore()
                let tasks = try store.listTasks(in: options.resolvedWorkspace, status: status)
                try outputEncodable(tasks)
            }
        }

        struct Create: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a task")

            @OptionGroup var options: Dahso.Options

            @Option(help: "Task title")
            var title: String

            @Option(help: "Task detail")
            var detail: String?

            @Option(help: "Task status")
            var status: AgentTaskStatus = .todo

            @Option(help: "Task assignee")
            var assignee: String?

            @Option(name: .long, parsing: .singleValue, help: "Label (repeatable)")
            var label: [String] = []

            @Option(name: .long, parsing: .singleValue, help: "Linked file path (repeatable)")
            var path: [String] = []

            func run() throws {
                let store = AgentWorkspaceStore()
                let task = try store.createTask(
                    in: options.resolvedWorkspace,
                    title: title,
                    detail: detail,
                    status: status,
                    assignee: assignee,
                    labels: label,
                    linkedPaths: path
                )
                try outputEncodable(task)
            }
        }

        struct Update: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "update", abstract: "Update a task")

            @OptionGroup var options: Dahso.Options

            @Argument(help: "Task ID")
            var id: String

            @Option(help: "Task title")
            var title: String?

            @Option(help: "Task detail")
            var detail: String?

            @Flag(name: .long, help: "Clear task detail")
            var clearDetail: Bool = false

            @Option(help: "Task status")
            var status: AgentTaskStatus?

            @Option(help: "Task assignee")
            var assignee: String?

            @Flag(name: .long, help: "Clear task assignee")
            var clearAssignee: Bool = false

            @Option(name: .long, parsing: .singleValue, help: "Replace labels with these values")
            var label: [String] = []

            @Flag(name: .long, help: "Clear all labels")
            var clearLabels: Bool = false

            @Option(name: .long, parsing: .singleValue, help: "Replace linked file paths with these values")
            var path: [String] = []

            @Flag(name: .long, help: "Clear all linked paths")
            var clearPaths: Bool = false

            @Option(help: "Latest run ID")
            var latestRunId: String?

            @Flag(name: .long, help: "Clear latest run ID")
            var clearLatestRunId: Bool = false

            func run() throws {
                let patch = AgentTaskPatch(
                    title: title,
                    detail: clearDetail ? "" : detail,
                    status: status,
                    assignee: clearAssignee ? "" : assignee,
                    labels: clearLabels ? [] : (label.isEmpty ? nil : label),
                    linkedPaths: clearPaths ? [] : (path.isEmpty ? nil : path),
                    latestRunId: clearLatestRunId ? "" : latestRunId
                )

                let store = AgentWorkspaceStore()
                let task = try store.updateTask(in: options.resolvedWorkspace, id: id, patch: patch)
                try outputEncodable(task)
            }
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Track agent runs",
            subcommands: [List.self, Start.self, Finish.self]
        )

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "list", abstract: "List runs")

            @OptionGroup var options: Dahso.Options

            @Option(help: "Filter by task ID")
            var task: String?

            @Option(help: "Max runs to return")
            var limit: Int = 20

            func run() throws {
                let store = AgentWorkspaceStore()
                let runs = try store.listRuns(in: options.resolvedWorkspace, limit: limit, taskId: task)
                try outputEncodable(runs)
            }
        }

        struct Start: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "start", abstract: "Start a run")

            @OptionGroup var options: Dahso.Options

            @Option(help: "Task ID")
            var task: String?

            @Option(help: "Agent name (e.g. codex, claude)")
            var agent: String = "agent"

            @Option(help: "Working directory")
            var cwd: String?

            @Option(help: "Git branch")
            var branch: String?

            func run() throws {
                let store = AgentWorkspaceStore()
                let run = try store.startRun(
                    in: options.resolvedWorkspace,
                    taskId: task,
                    agent: agent,
                    cwd: cwd,
                    branch: branch
                )
                try outputEncodable(run)
            }
        }

        struct Finish: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "finish", abstract: "Finish a run")

            @OptionGroup var options: Dahso.Options

            @Argument(help: "Run ID")
            var runId: String

            @Option(help: "Final run status")
            var status: AgentRunStatus = .succeeded

            @Option(help: "Run summary")
            var summary: String?

            @Option(help: "Commit SHA")
            var commit: String?

            func run() throws {
                let store = AgentWorkspaceStore()
                let run = try store.finishRun(
                    in: options.resolvedWorkspace,
                    runId: runId,
                    status: status,
                    summary: summary,
                    commit: commit
                )
                try outputEncodable(run)
            }
        }
    }

    struct Event: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "event",
            abstract: "Manage run events",
            subcommands: [Log.self, List.self]
        )

        struct Log: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "log", abstract: "Append an event")

            @OptionGroup var options: Dahso.Options

            @Option(help: "Run ID")
            var runId: String?

            @Option(help: "Task ID")
            var task: String?

            @Option(help: "Event level")
            var level: AgentEventLevel = .info

            @Option(help: "Event message")
            var message: String?

            func run() throws {
                let resolvedMessage: String
                if let message {
                    resolvedMessage = message
                } else {
                    var input = ""
                    while let line = readLine(strippingNewline: false) {
                        input += line
                    }
                    resolvedMessage = input
                }

                let store = AgentWorkspaceStore()
                let event = try store.logEvent(
                    in: options.resolvedWorkspace,
                    runId: runId,
                    taskId: task,
                    level: level,
                    message: resolvedMessage
                )
                try outputEncodable(event)
            }
        }

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "list", abstract: "List events")

            @OptionGroup var options: Dahso.Options

            @Option(help: "Filter by run ID")
            var runId: String?

            @Option(help: "Filter by task ID")
            var task: String?

            @Option(help: "Max events to return")
            var limit: Int = 50

            func run() throws {
                let store = AgentWorkspaceStore()
                let events = try store.listEvents(
                    in: options.resolvedWorkspace,
                    limit: limit,
                    runId: runId,
                    taskId: task
                )
                try outputEncodable(events)
            }
        }
    }
}

private func outputEncodable<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    if let string = String(data: data, encoding: .utf8) {
        print(string)
    }
}

private func defaultAgentsTemplate(workspace: String) -> String {
    AgentWorkspaceTemplate.agentsMarkdown(workspace: workspace)
}

extension AgentTaskStatus: ExpressibleByArgument {}
extension AgentRunStatus: ExpressibleByArgument {}
extension AgentEventLevel: ExpressibleByArgument {}
