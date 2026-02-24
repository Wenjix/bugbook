import SwiftUI

struct SidebarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var fileSystem: FileSystemService
    var onSelectFile: (FileEntry) -> Void
    var onToggleSidebar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(workspaceName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: createFile) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("New Page")
                Button(action: onToggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Sidebar")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // File tree
            ScrollView {
                FileTreeView(
                    entries: appState.fileTree,
                    activeFilePath: appState.activeTab?.path,
                    fileSystem: fileSystem,
                    workspacePath: appState.workspacePath,
                    onSelectFile: onSelectFile,
                    onRefreshTree: refreshTree
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }

            Divider()

            // Bottom bar with settings
            HStack {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Settings")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        .background(Color.fallbackSidebarBg)
    }

    private var workspaceName: String {
        guard let path = appState.workspacePath else { return "Workspace" }
        return (path as NSString).lastPathComponent
    }

    private func refreshTree() {
        guard let workspace = appState.workspacePath else { return }
        appState.fileTree = fileSystem.buildFileTree(at: workspace)
    }

    private func createFile() {
        // Use the shared createNewFile path via notification so the document
        // is loaded and the title block gets focus + placeholder
        NotificationCenter.default.post(name: .newNote, object: nil)
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}
