import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Workspace") {
                if let path = appState.workspacePath {
                    HStack {
                        Text(path)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
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

            SettingsSection("New Workspace") {
                HStack {
                    if appState.settings.defaultNewTabPage.isEmpty {
                        Text("Dahso start page")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(displayName(for: appState.settings.defaultNewTabPage))
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if !appState.settings.defaultNewTabPage.isEmpty {
                        Button("Reset") {
                            appState.settings.defaultNewTabPage = ""
                        }
                    }
                    Menu("Choose Page...") {
                        ForEach(flatPages(from: appState.fileTree), id: \.path) { entry in
                            Button(entry.name.hasSuffix(".md") ? String(entry.name.dropLast(3)) : entry.name) {
                                appState.settings.defaultNewTabPage = entry.path
                            }
                        }
                    }
                    .fixedSize()
                }
                Text("Opens this page instead of the default start page when creating a new workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection("App") {
                if AppEnvironment.isDev {
                    HStack(spacing: 6) {
                        Text("DEV")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(.capsule)
                        Text("Development build")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
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
                .foregroundStyle(.secondary)
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

    private func displayName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    private func flatPages(from entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries {
            if !entry.isDirectory || entry.isDatabase {
                result.append(entry)
            }
            if let children = entry.children {
                result.append(contentsOf: flatPages(from: children))
            }
        }
        return result
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
