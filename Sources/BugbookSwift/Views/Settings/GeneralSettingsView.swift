import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Workspace") {
                if let path = appState.workspacePath {
                    HStack {
                        Text(path)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Change...") {
                            Task { await switchWorkspace() }
                        }
                    }
                } else {
                    Button("Select Workspace...") {
                        Task { await switchWorkspace() }
                    }
                }
            }

            SettingsSection("Editor") {
                Toggle("Focus mode while typing", isOn: $appState.settings.focusModeOnType)
            }

            SettingsSection("App") {
                infoRow(label: "Bundle ID", value: bundleIdentifier)
                infoRow(label: "Version", value: appVersion)
                infoRow(label: "Build", value: appBuild)
                infoRow(label: "Executable", value: executableName)
            }
        }
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private var executableName: String {
        Bundle.main.executableURL?.lastPathComponent ?? "Unknown"
    }

    private func switchWorkspace() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Notes Folder"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        appState.workspacePath = url.path
    }
}
