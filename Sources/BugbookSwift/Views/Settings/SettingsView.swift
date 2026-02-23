import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = "general"

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("General").tag("general")
                Text("Appearance").tag("appearance")
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case "general":
                        generalSettings
                    case "appearance":
                        appearanceSettings
                    default:
                        EmptyView()
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var generalSettings: some View {
        GroupBox("Workspace") {
            VStack(alignment: .leading, spacing: 8) {
                if let path = appState.workspacePath {
                    Text("Current: \(path)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Button("Switch Workspace...") {
                    // TODO: Open folder picker
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var appearanceSettings: some View {
        GroupBox("Theme") {
            Picker("Theme", selection: $appState.settings.theme) {
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
                Text("System").tag(ThemeMode.system)
            }
            .pickerStyle(.segmented)
            .padding(8)
        }

        GroupBox("Editor") {
            Toggle("Focus mode while typing", isOn: $appState.settings.focusModeOnType)
                .padding(8)
        }
    }
}
