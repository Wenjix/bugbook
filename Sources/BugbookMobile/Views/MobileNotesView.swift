import SwiftUI

struct MobileNotesView: View {
    var workspace: MobileWorkspaceService

    @State private var searchText = ""
    @State private var showSearch = false
    @State private var fileTree: [MobileNoteFile] = []

    var body: some View {
        NavigationStack {
            Group {
                if fileTree.isEmpty && searchText.isEmpty {
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "doc.text",
                        description: Text("Tap + to create your first note.")
                    )
                } else if !filteredTree.isEmpty {
                    List {
                        ForEach(filteredTree) { node in
                            FileTreeRow(node: node, workspace: workspace, searchText: searchText)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter files")
            #else
            .searchable(text: $searchText, prompt: "Filter files")
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        _ = workspace.createNote()
                        reloadTree()
                    } label: {
                        Label("New Note", systemImage: "plus")
                    }
                }
            }
            .refreshable {
                workspace.refreshFiles()
                reloadTree()
            }
            .onAppear {
                reloadTree()
            }
            .sheet(isPresented: $showSearch) {
                MobileSearchView(workspacePath: workspace.workspacePath, workspace: workspace)
            }
        }
    }

    private var filteredTree: [MobileNoteFile] {
        if searchText.isEmpty { return fileTree }
        return filterTree(fileTree, query: searchText)
    }

    private func filterTree(_ nodes: [MobileNoteFile], query: String) -> [MobileNoteFile] {
        var results: [MobileNoteFile] = []
        for node in nodes {
            if let children = node.children {
                let matchedChildren = filterTree(children, query: query)
                if node.name.localizedCaseInsensitiveContains(query) || !matchedChildren.isEmpty {
                    var copy = node
                    copy.children = matchedChildren.isEmpty ? nil : matchedChildren
                    results.append(copy)
                }
            } else if node.name.localizedCaseInsensitiveContains(query) {
                results.append(node)
            }
        }
        return results
    }

    private func reloadTree() {
        fileTree = workspace.buildHierarchicalFileTree()
    }
}

// MARK: - File Tree Row

private struct FileTreeRow: View {
    let node: MobileNoteFile
    var workspace: MobileWorkspaceService
    var searchText: String

    @State private var isExpanded = false

    private var hasExpandableChildren: Bool {
        if node.isDirectory && !node.isDatabase { return true }
        if let children = node.children, !children.isEmpty, !node.isDatabase { return true }
        return false
    }

    var body: some View {
        if hasExpandableChildren {
            expandableRow
        } else {
            leafRow
        }
    }

    private var expandableRow: some View {
        DisclosureGroup(isExpanded: expandedBinding) {
            if let children = node.children {
                ForEach(children) { child in
                    FileTreeRow(node: child, workspace: workspace, searchText: searchText)
                }
            }
        } label: {
            if node.isDirectory {
                Label(node.name, systemImage: iconName)
                    .font(.body)
            } else {
                NavigationLink {
                    MobilePageEditorView(note: node, workspace: workspace)
                } label: {
                    fileLabel
                }
            }
        }
    }

    @ViewBuilder
    private var leafRow: some View {
        if node.isDatabase {
            NavigationLink {
                MobileDatabaseView(dbPath: node.path)
            } label: {
                fileLabel
            }
        } else {
            NavigationLink {
                MobilePageEditorView(note: node, workspace: workspace)
            } label: {
                fileLabel
            }
        }
    }

    private var fileLabel: some View {
        HStack(spacing: 8) {
            if let icon = node.icon, !icon.isEmpty, icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.body)
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Text(displayName)
                .font(.body)
                .lineLimit(1)
        }
    }

    private var displayName: String {
        if node.name.hasSuffix(".md") && !node.isDatabase {
            return String(node.name.dropLast(3))
        }
        return node.name
    }

    private var iconName: String {
        if node.isDatabase { return "tablecells" }
        if node.isDirectory { return "folder" }
        return "doc.text"
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { searchText.isEmpty ? isExpanded : true },
            set: { isExpanded = $0 }
        )
    }
}
