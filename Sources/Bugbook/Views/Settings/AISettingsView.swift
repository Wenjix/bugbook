import SwiftUI

struct AISettingsView: View {
    @Bindable var appState: AppState
    @State private var claudeAvailable = false
    @State private var codexAvailable = false
    @State private var showApiKey = false

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

            if appState.settings.preferredAIEngine == .claudeAPI {
                SettingsSection("Anthropic API Key") {
                    HStack(spacing: 8) {
                        Group {
                            if showApiKey {
                                TextField("sk-ant-...", text: $appState.settings.anthropicApiKey)
                            } else {
                                SecureField("sk-ant-...", text: $appState.settings.anthropicApiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                        Button {
                            showApiKey.toggle()
                        } label: {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    Text("Your key is stored locally and never sent anywhere except the Anthropic API.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                .foregroundStyle(available ? .green : .secondary)
            Text(name)
                .font(.system(size: 14))
            Spacer()
            Text(available ? "Installed" : "Not Found")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
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
