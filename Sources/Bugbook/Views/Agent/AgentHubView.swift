import SwiftUI
import BugbookCore

struct AgentHubView: View {
    var workspacePath: String?

    @StateObject private var viewModel = AgentHubViewModel()
    @State private var newTaskTitle: String = ""
    @State private var newTaskAssignee: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            metricsRow
            createTaskSection
            activityList
        }
        .padding(20)
        .background(Color.fallbackEditorBg)
        .onAppear {
            viewModel.start(workspacePath: workspacePath)
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: workspacePath) { _, newValue in
            viewModel.start(workspacePath: newValue)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent Hub")
                    .font(.system(size: 28, weight: .bold))
                if let workspacePath {
                    Text((workspacePath as NSString).lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                viewModel.refresh(workspacePath: workspacePath)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    private var metricsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statusCard(.backlog, color: .gray)
                statusCard(.todo, color: .blue)
                statusCard(.inProgress, color: .orange)
                statusCard(.blocked, color: .red)
                statusCard(.done, color: .green)
                statusCard(.cancelled, color: .secondary)
            }
        }
    }

    private func statusCard(_ status: AgentTaskStatus, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusLabel(status))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Text("\(viewModel.statusCount(status))")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
        }
        .frame(width: 92, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
    }

    private var createTaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Add Task")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("Task title", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Assignee (optional)", text: $newTaskAssignee)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("Add") {
                    viewModel.createTask(
                        workspacePath: workspacePath,
                        title: newTaskTitle,
                        assignee: newTaskAssignee
                    )
                    newTaskTitle = ""
                    newTaskAssignee = ""
                }
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
    }

    private var activityList: some View {
        List {
            if let error = viewModel.error {
                Section("Status") {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Section("Active Tasks") {
                if viewModel.tasks.isEmpty {
                    Text("No active tasks")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                ForEach(viewModel.tasks) { task in
                    taskRow(task)
                }
            }

            Section("Recent Runs") {
                if viewModel.runs.isEmpty {
                    Text("No runs yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                ForEach(viewModel.runs) { run in
                    HStack(spacing: 8) {
                        statusDot(run.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.id)
                                .font(.system(size: 12, design: .monospaced))
                            Text(run.summary ?? "\(run.agent) • \(run.status.rawValue)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(shortTime(run.endedAt ?? run.startedAt))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Recent Events") {
                if viewModel.events.isEmpty {
                    Text("No events yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                ForEach(viewModel.events) { event in
                    HStack(spacing: 8) {
                        eventIcon(event.level)
                            .foregroundColor(eventColor(event.level))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.message)
                                .font(.system(size: 13))
                                .lineLimit(2)
                            Text("\(event.runId ?? "No run") • \(shortTime(event.timestamp))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.inset)
    }

    private func taskRow(_ task: AgentTask) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                let metadata = [task.assignee, task.id].compactMap { $0 }.joined(separator: " • ")
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Menu {
                ForEach(AgentTaskStatus.allCases, id: \.self) { status in
                    Button(statusLabel(status)) {
                        viewModel.updateTaskStatus(
                            workspacePath: workspacePath,
                            taskId: task.id,
                            status: status
                        )
                    }
                }
            } label: {
                Text(statusLabel(task.status))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusColor(task.status).opacity(0.18))
                    .foregroundColor(statusColor(task.status))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func shortTime(_ value: String) -> String {
        if let date = ISO8601DateFormatter().date(from: value) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return value
    }

    private func statusLabel(_ status: AgentTaskStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .blocked: return "Blocked"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    private func statusColor(_ status: AgentTaskStatus) -> Color {
        switch status {
        case .backlog: return .gray
        case .todo: return .blue
        case .inProgress: return .orange
        case .blocked: return .red
        case .done: return .green
        case .cancelled: return .secondary
        }
    }

    private func statusDot(_ status: AgentRunStatus) -> some View {
        Circle()
            .fill(runColor(status))
            .frame(width: 8, height: 8)
    }

    private func runColor(_ status: AgentRunStatus) -> Color {
        switch status {
        case .running: return .orange
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    private func eventIcon(_ level: AgentEventLevel) -> Image {
        switch level {
        case .info: return Image(systemName: "info.circle.fill")
        case .warning: return Image(systemName: "exclamationmark.triangle.fill")
        case .error: return Image(systemName: "xmark.octagon.fill")
        }
    }

    private func eventColor(_ level: AgentEventLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
