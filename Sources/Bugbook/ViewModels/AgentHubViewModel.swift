import Foundation
import BugbookCore
import Sentry

@MainActor
final class AgentHubViewModel: ObservableObject {
    @Published var tasks: [AgentTask] = []
    @Published var runs: [AgentRun] = []
    @Published var events: [AgentEvent] = []
    @Published var counts: [String: Int] = [:]
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let store = AgentWorkspaceStore()
    private var refreshTask: Task<Void, Never>?

    func start(workspacePath: String?) {
        SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "agent.start"))
        stop()
        refresh(workspacePath: workspacePath)

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.refresh(workspacePath: workspacePath)
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh(workspacePath: String?) {
        guard let workspacePath, !workspacePath.isEmpty else {
            tasks = []
            runs = []
            events = []
            counts = [:]
            error = "Open a workspace to use Agent Hub."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try store.ensureWorkspaceFiles(in: workspacePath)
            let dashboard = try store.dashboard(in: workspacePath, runLimit: 20, eventLimit: 40)
            tasks = dashboard.activeTasks
            runs = dashboard.recentRuns
            events = dashboard.recentEvents
            counts = dashboard.taskCounts
            error = nil
        } catch {
            SentrySDK.addBreadcrumb(Breadcrumb(level: .error, category: "agent.error"))
            self.error = error.localizedDescription
        }
    }

    func createTask(workspacePath: String?, title: String, assignee: String?) {
        guard let workspacePath, !workspacePath.isEmpty else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try store.createTask(
                in: workspacePath,
                title: trimmed,
                detail: nil,
                status: .todo,
                assignee: assignee,
                labels: [],
                linkedPaths: []
            )
            SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "agent.create"))
            refresh(workspacePath: workspacePath)
        } catch {
            SentrySDK.addBreadcrumb(Breadcrumb(level: .error, category: "agent.error"))
            self.error = error.localizedDescription
        }
    }

    func updateTaskStatus(workspacePath: String?, taskId: String, status: AgentTaskStatus) {
        guard let workspacePath, !workspacePath.isEmpty else { return }

        do {
            _ = try store.updateTask(
                in: workspacePath,
                id: taskId,
                patch: AgentTaskPatch(status: status)
            )
            refresh(workspacePath: workspacePath)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func statusCount(_ status: AgentTaskStatus) -> Int {
        counts[status.rawValue] ?? 0
    }
}
