import Foundation
import Observation
import BugbookCore

@MainActor
@Observable final class MobileAgentHubViewModel {
    var tasks: [AgentTask] = []
    var runs: [AgentRun] = []
    var events: [AgentEvent] = []
    var error: String?

    private let store = AgentWorkspaceStore()
    private let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso8601FormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

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

    func setTaskStatus(_ taskId: String, status: AgentTaskStatus, workspacePath: String) {
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

    // MARK: - Timestamp Formatting

    func parseISO8601(_ string: String) -> Date? {
        iso8601Formatter.date(from: string) ?? iso8601FormatterNoFrac.date(from: string)
    }

    func relativeTime(from iso8601String: String) -> String {
        guard let date = parseISO8601(iso8601String) else { return iso8601String }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
