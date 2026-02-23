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

            // Action buttons
            HStack(spacing: 8) {
                Button(action: createFile) {
                    Label("New Page", systemImage: "doc.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)

                Button(action: createDatabase) {
                    Label("New Database", systemImage: "tablecells.badge.ellipsis")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

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
        guard let workspace = appState.workspacePath else { return }
        if let path = try? fileSystem.createNewFile(in: workspace) {
            refreshTree()
            let entry = FileEntry(
                id: path, name: (path as NSString).lastPathComponent,
                path: path, isDirectory: false, isDatabase: false,
                icon: nil, children: nil
            )
            appState.openFile(entry)
        }
    }

    private func createDatabase() {
        guard let workspace = appState.workspacePath else { return }
        if let path = try? fileSystem.createDatabase(in: workspace, name: "Untitled Database") {
            refreshTree()
            let entry = FileEntry(
                id: path, name: "Untitled Database",
                path: path, isDirectory: false, isDatabase: true,
                icon: nil, children: nil
            )
            appState.openFile(entry)
        }
    }
}
