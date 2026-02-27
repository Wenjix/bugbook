import SwiftUI
import BugbookCore

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

                Section("Quick Add") {
                    TextField("Task title", text: $taskTitle)
                    Button("Create Task") {
                        viewModel.createTask(workspacePath: workspacePath, title: taskTitle)
                        taskTitle = ""
                    }
                    .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Active Tasks") {
                    if viewModel.tasks.isEmpty {
                        Text("No active tasks")
                            .foregroundColor(.secondary)
                    }

                    ForEach(viewModel.tasks) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                Text(task.id)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Menu(statusLabel(task.status)) {
                                ForEach(AgentTaskStatus.allCases, id: \.self) { status in
                                    Button(statusLabel(status)) {
                                        viewModel.setStatus(
                                            workspacePath: workspacePath,
                                            taskId: task.id,
                                            status: status
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Recent Runs") {
                    if viewModel.runs.isEmpty {
                        Text("No runs yet")
                            .foregroundColor(.secondary)
                    }

                    ForEach(viewModel.runs) { run in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.id)
                                .font(.system(size: 12, design: .monospaced))
                            Text(run.summary ?? "\(run.agent) • \(run.status.rawValue)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Recent Events") {
                    if viewModel.events.isEmpty {
                        Text("No events yet")
                            .foregroundColor(.secondary)
                    }

                    ForEach(viewModel.events) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.message)
                                .font(.system(size: 13))
                            Text(event.timestamp)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
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
