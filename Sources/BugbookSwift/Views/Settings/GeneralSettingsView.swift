import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        GroupBox("Workspace") {
            VStack(alignment: .leading, spacing: 8) {
                if let path = appState.workspacePath {
                    Text("Current: \(path)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Button("Switch Workspace...") {
                    Task { await switchWorkspace() }
                }
            }
            .padding(8)
        }

        GroupBox("Editor") {
            Toggle("Focus mode while typing", isOn: $appState.settings.focusModeOnType)
                .padding(8)
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
