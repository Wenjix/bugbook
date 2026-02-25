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
        }
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
