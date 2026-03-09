import SwiftUI
import BugbookCore

private enum HapticStyle {
    case light, medium
}

struct MobileAgentHubView: View {
    let workspacePath: String

    @State private var viewModel = MobileAgentHubViewModel()
    @State private var taskTitle: String = ""

    var body: some View {
        NavigationStack {
            List {
                if let error = viewModel.error {
                    Section("Status") {
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }

                quickAddSection
                activeTasksSection
                recentRunsSection
                recentEventsSection
            }
            .navigationTitle("Agent Hub")
            .refreshable {
                viewModel.refresh(workspacePath: workspacePath)
            }
        }
        .onAppear {
            viewModel.refresh(workspacePath: workspacePath)
        }
    }

    // MARK: - Sections

    private var quickAddSection: some View {
        Section("Quick Add") {
            TextField("Task title", text: $taskTitle)
            Button("Create Task") {
                viewModel.createTask(workspacePath: workspacePath, title: taskTitle)
                haptic(.medium)
                taskTitle = ""
            }
            .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var activeTasksSection: some View {
        Section("Active Tasks") {
            if viewModel.tasks.isEmpty {
                Text("No active tasks")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.tasks) { task in
                taskRow(task)
            }
        }
    }

    private func taskRow(_ task: AgentTask) -> some View {
        HStack(spacing: 8) {
            statusIndicator(task.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                Text(viewModel.relativeTime(from: task.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu(statusLabel(task.status)) {
                ForEach(AgentTaskStatus.allCases, id: \.self) { status in
                    Button(statusLabel(status)) {
                        viewModel.setTaskStatus(task.id, status: status, workspacePath: workspacePath)
                        haptic(.light)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            Button {
                viewModel.setTaskStatus(task.id, status: .done, workspacePath: workspacePath)
                haptic(.light)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .leading) {
            Button {
                viewModel.setTaskStatus(task.id, status: .cancelled, workspacePath: workspacePath)
                haptic(.light)
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .tint(.red)
        }
    }

    private var recentRunsSection: some View {
        Section("Recent Runs") {
            if viewModel.runs.isEmpty {
                Text("No runs yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.runs) { run in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.summary ?? "\(run.agent)")
                            .font(.subheadline)
                        Text(viewModel.relativeTime(from: run.startedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    runStatusBadge(run.status)
                }
            }
        }
    }

    private var recentEventsSection: some View {
        Section("Recent Events") {
            if viewModel.events.isEmpty {
                Text("No events yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.message)
                        .font(.footnote)
                    Text(viewModel.relativeTime(from: event.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private func statusIndicator(_ status: AgentTaskStatus) -> some View {
        switch status {
        case .backlog:
            Image(systemName: "circle")
                .foregroundStyle(.gray)
                .font(.caption2)
        case .todo:
            Image(systemName: "circle")
                .foregroundStyle(.blue)
                .font(.caption2)
        case .inProgress:
            Image(systemName: "circle")
                .foregroundStyle(.orange)
                .font(.caption2)
        case .blocked:
            Image(systemName: "circle")
                .foregroundStyle(.red)
                .font(.caption2)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption2)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.gray)
                .font(.caption2)
        }
    }

    // MARK: - Run Status Badge

    private func runStatusBadge(_ status: AgentRunStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(runStatusColor(status).opacity(0.15))
            .foregroundStyle(runStatusColor(status))
            .clipShape(Capsule())
    }

    private func runStatusColor(_ status: AgentRunStatus) -> Color {
        switch status {
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    // MARK: - Helpers

    private func haptic(_ style: HapticStyle) {
        #if os(iOS)
        switch style {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #endif
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
}
