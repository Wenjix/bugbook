import Foundation
import BugbookCore

@MainActor
final class MobileAgentHubViewModel: ObservableObject {
    @Published var tasks: [AgentTask] = []
    @Published var runs: [AgentRun] = []
    @Published var events: [AgentEvent] = []
    @Published var error: String?

    private let store = AgentWorkspaceStore()

    func refresh(workspacePath: String) {
        do {
            _ = try store.ensureWorkspaceFiles(in: workspacePath)
            tasks = try store.listTasks(in: workspacePath).filter { task in
                task.status != .done && task.status != .cancelled
            }
            runs = try store.listRuns(in: workspacePath, limit: 12)
            events = try store.listEvents(in: workspacePath, limit: 20)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createTask(workspacePath: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try store.createTask(in: workspacePath, title: trimmed, status: .todo)
            refresh(workspacePath: workspacePath)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setStatus(workspacePath: String, taskId: String, status: AgentTaskStatus) {
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
}
