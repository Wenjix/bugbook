import SwiftUI

struct AISettingsView: View {
    @ObservedObject var appState: AppState
    @State private var claudeAvailable = false
    @State private var codexAvailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Engine Status") {
                engineRow("Claude CLI", available: claudeAvailable)
                engineRow("Codex CLI", available: codexAvailable)
            }

            SettingsSection("Preferred Engine") {
                Picker("Engine", selection: $appState.settings.preferredAIEngine) {
                    ForEach(PreferredAIEngine.allCases, id: \.self) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SettingsSection("Execution Policy") {
                Picker("Policy", selection: $appState.settings.executionPolicy) {
                    ForEach(ExecutionPolicy.allCases, id: \.self) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .labelsHidden()
            }
        }
        .onAppear { detectEngines() }
    }

    @ViewBuilder
    private func engineRow(_ name: String, available: Bool) -> some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(available ? .green : .secondary)
            Text(name)
                .font(.system(size: 14))
            Spacer()
            Text(available ? "Installed" : "Not Found")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private func detectEngines() {
        claudeAvailable = cliExists("claude")
        codexAvailable = cliExists("codex")
    }

    private func cliExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which \(name)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
