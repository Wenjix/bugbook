import SwiftUI
import BugbookCore

private enum HapticStyle {
    case light, medium
}

struct MobileAgentHubView: View {
    let workspacePath: String

    @StateObject private var viewModel = MobileAgentHubViewModel()
    @State private var taskTitle: String = ""

    var body: some View {
        NavigationStack {
            List {
                if let error = viewModel.error {
                    Section("Status") {
                        Text(error)
                            .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
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
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
            .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
            }

            ForEach(viewModel.runs) { run in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.summary ?? "\(run.agent)")
                            .font(.system(size: 14))
                        Text(viewModel.relativeTime(from: run.startedAt))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
            }

            ForEach(viewModel.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.message)
                        .font(.system(size: 13))
                    Text(viewModel.relativeTime(from: event.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
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
                .foregroundColor(.gray)
                .font(.system(size: 10))
        case .todo:
            Image(systemName: "circle")
                .foregroundColor(.blue)
                .font(.system(size: 10))
        case .inProgress:
            Image(systemName: "circle")
                .foregroundColor(.orange)
                .font(.system(size: 10))
        case .blocked:
            Image(systemName: "circle")
                .foregroundColor(.red)
                .font(.system(size: 10))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 10))
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.gray)
                .font(.system(size: 10))
        }
    }

    // MARK: - Run Status Badge

    private func runStatusBadge(_ status: AgentRunStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(runStatusColor(status).opacity(0.15))
            .foregroundColor(runStatusColor(status))
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
