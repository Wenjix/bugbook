import SwiftUI
import BugbookCore

struct AgentsSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var installedAgents: [(name: String, path: String)] = []
    @State private var agentsMdText: String = ""
    @State private var saveGeneration: Int = 0
    @State private var workspaceMessage: String?
    @State private var workspaceInfo: AgentWorkspaceInfo?

    private let agentStore = AgentWorkspaceStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Installed Agents") {
                if installedAgents.isEmpty {
                    Text("No agents detected")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(installedAgents, id: \.path) { agent in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(agent.name)
                                .font(.system(size: 14))
                            Spacer()
                            Text(agent.path)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Button("Refresh") { scanAgents() }
            }

            SettingsSection("Agent Workspace") {
                if let workspace = appState.workspacePath {
                    Text(workspace)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let info = workspaceInfo {
                        keyValue("Tasks", info.tasksPath)
                        keyValue("Runs", info.runsPath)
                        keyValue("Events", info.eventsPath)
                    }

                    HStack {
                        Button("Initialize Files") {
                            initializeAgentWorkspace()
                        }

                        Button("Refresh Paths") {
                            refreshWorkspaceInfo()
                        }
                    }
                } else {
                    Text("Select a workspace first in General settings.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                if let workspaceMessage {
                    Text(workspaceMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            SettingsSection("Bugbook Skill") {
                Toggle("Install bugbook skill for agents", isOn: $appState.settings.bugbookSkillEnabled)
            }

            SettingsSection("AGENTS.md") {
                Text("Custom agent instructions (auto-saved to app settings)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                TextEditor(text: $agentsMdText)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .onChange(of: agentsMdText) { _, _ in
                        scheduleSave()
                    }

                HStack {
                    Button("Generate Template") {
                        agentsMdText = defaultAgentsTemplate(workspace: appState.workspacePath ?? "<workspace>")
                        scheduleSave()
                    }

                    Button("Load Workspace File") {
                        loadWorkspaceAgentsFile()
                    }

                    Button("Write Workspace File") {
                        writeWorkspaceAgentsFile()
                    }

                    Spacer()

                    Button("Reset") {
                        agentsMdText = ""
                        appState.settings.agentsMdContent = ""
                    }
                }
            }
        }
        .task {
            scanAgents()
            agentsMdText = appState.settings.agentsMdContent
            refreshWorkspaceInfo()
        }
        .onChange(of: appState.workspacePath) { _, _ in
            refreshWorkspaceInfo()
        }
    }

    @ViewBuilder
    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(key):")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func scanAgents() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [(String, String)] = [
            ("Claude Code", "\(home)/.claude"),
            ("Cursor", "\(home)/.cursor"),
            ("Codex", "\(home)/.codex"),
        ]
        installedAgents = candidates.compactMap { name, path in
            FileManager.default.fileExists(atPath: path) ? (name: name, path: path) : nil
        }
    }

    private func initializeAgentWorkspace() {
        guard let workspace = appState.workspacePath else {
            workspaceMessage = "No workspace selected."
            return
        }

        do {
            workspaceInfo = try agentStore.ensureWorkspaceFiles(in: workspace)
            workspaceMessage = "Initialized agent files in \(workspaceInfo?.directory ?? workspace)."
        } catch {
            workspaceMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    private func refreshWorkspaceInfo() {
        guard let workspace = appState.workspacePath else {
            workspaceInfo = nil
            return
        }

        workspaceInfo = agentStore.info(in: workspace)
    }

    private func workspaceAgentsPath() -> String? {
        guard let workspace = appState.workspacePath else { return nil }
        return (workspace as NSString).appendingPathComponent("AGENTS.md")
    }

    private func loadWorkspaceAgentsFile() {
        guard let path = workspaceAgentsPath() else {
            workspaceMessage = "No workspace selected."
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            workspaceMessage = "No AGENTS.md found at workspace root."
            return
        }

        do {
            agentsMdText = try String(contentsOfFile: path, encoding: .utf8)
            appState.settings.agentsMdContent = agentsMdText
            workspaceMessage = "Loaded AGENTS.md from workspace."
        } catch {
            workspaceMessage = "Failed to load AGENTS.md: \(error.localizedDescription)"
        }
    }

    private func writeWorkspaceAgentsFile() {
        guard let path = workspaceAgentsPath() else {
            workspaceMessage = "No workspace selected."
            return
        }

        do {
            try agentsMdText.write(toFile: path, atomically: true, encoding: .utf8)
            appState.settings.agentsMdContent = agentsMdText
            workspaceMessage = "Wrote AGENTS.md to workspace root."
        } catch {
            workspaceMessage = "Failed to write AGENTS.md: \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        saveGeneration += 1
        let generation = saveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == self.saveGeneration else { return }
            appState.settings.agentsMdContent = agentsMdText
        }
    }

    private func defaultAgentsTemplate(workspace: String) -> String {
        """
# AGENTS.md

## Workspace
- Root: \(workspace)
- Agent data: `.bugbook/agents/tasks.json`, `.bugbook/agents/runs.jsonl`, `.bugbook/agents/events.jsonl`

## Workflow
1. Create or pick a task.
2. Start a run for that task.
3. Log major events.
4. Finish the run with summary + commit.
5. Update task status.

## CLI Examples
```bash
bugbook agent init --write-agents-md
bugbook agent task create --title "Fix editor regression" --status todo --label bug
bugbook agent run start --task task_xxx --agent codex --branch codex/fix-editor
bugbook agent event log --run run_xxx --level info --message "Added regression test"
bugbook agent run finish run_xxx --status succeeded --summary "Fixed selection bug" --commit abc1234
bugbook agent task update task_xxx --status done
```

## Statuses
- Task: `backlog`, `todo`, `in_progress`, `blocked`, `done`, `cancelled`
- Run: `running`, `succeeded`, `failed`, `cancelled`
- Event: `info`, `warning`, `error`
"""
    }
}
