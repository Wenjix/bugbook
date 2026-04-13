import SwiftUI

struct MobileSettingsView: View {
    var workspace: MobileWorkspaceService

    var body: some View {
        NavigationStack {
            List {
                Section("Workspace") {
                    LabeledContent("Path") {
                        Text(shortenedPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack {
                        Image(systemName: workspace.isICloudAvailable ? "checkmark.icloud.fill" : "xmark.icloud")
                            .foregroundStyle(workspace.isICloudAvailable ? .green : .red)
                        Text(workspace.isICloudAvailable ? "iCloud Connected" : "iCloud Not Available")
                    }
                }

                Section("Storage") {
                    LabeledContent("Notes") {
                        Text("\(workspace.files.count) files")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App") {
                        Text("Dahso")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Platform") {
                        Text("iOS")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var shortenedPath: String {
        let path = workspace.workspacePath
        if let range = path.range(of: "/Library/Mobile Documents/") {
            return "iCloud/" + String(path[range.upperBound...])
        }
        if let range = path.range(of: "/Documents/") {
            return "Documents/" + String(path[range.upperBound...])
        }
        return path
    }
}
