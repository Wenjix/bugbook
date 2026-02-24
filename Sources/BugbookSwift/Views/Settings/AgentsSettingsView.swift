import SwiftUI

struct AgentsSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var installedAgents: [(name: String, path: String)] = []
    @State private var agentsMdText: String = ""
    @State private var saveGeneration: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Installed Agents") {
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

                Button("Refresh") { scanAgents() }
            }

            SettingsSection("Bugbook Skill") {
                Toggle("Install bugbook skill for agents", isOn: $appState.settings.bugbookSkillEnabled)
            }

            SettingsSection("AGENTS.md") {
                Text("Custom agent instructions (auto-saved)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextEditor(text: $agentsMdText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 180)
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
                    Spacer()
                    Button("Reset") {
                        agentsMdText = ""
                        appState.settings.agentsMdContent = ""
                    }
                }
            }
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
