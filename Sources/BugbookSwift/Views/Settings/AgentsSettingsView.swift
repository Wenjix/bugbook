import SwiftUI

struct AgentsSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var installedAgents: [(name: String, path: String)] = []
    @State private var agentsMdText: String = ""
    @State private var saveGeneration: Int = 0

    var body: some View {
        GroupBox("Installed Agents") {
            VStack(alignment: .leading, spacing: 8) {
                if installedAgents.isEmpty {
                    Text("No agents detected")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(installedAgents, id: \.path) { agent in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(agent.name)
                                .font(.system(size: 13))
                            Spacer()
                            Text(agent.path)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                HStack {
                    Button("Refresh") { scanAgents() }
                }
            }
            .padding(8)
        }

        GroupBox("Bugbook Skill") {
            Toggle("Install bugbook skill for agents", isOn: $appState.settings.bugbookSkillEnabled)
                .padding(8)
        }

        GroupBox("AGENTS.md") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom agent instructions (auto-saved)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextEditor(text: $agentsMdText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 150)
                    .onChange(of: agentsMdText) { _, _ in
                        scheduleSave()
                    }

                HStack {
                    Spacer()
                    Button("Reset") {
                        agentsMdText = ""
                        appState.settings.agentsMdContent = ""
                    }
                }
            }
            .padding(8)
        }
        .onAppear {
            scanAgents()
            agentsMdText = appState.settings.agentsMdContent
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

    private func scheduleSave() {
        saveGeneration += 1
        let generation = saveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == self.saveGeneration else { return }
            appState.settings.agentsMdContent = agentsMdText
        }
    }
}
