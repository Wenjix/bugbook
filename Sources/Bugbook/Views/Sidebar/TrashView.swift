import SwiftUI

struct TrashPopoverView: View {
    var appState: AppState
    var fileSystem: FileSystemService
    var onRestore: () -> Void

    @Environment(\.popoverDismiss) private var dismiss
    @State private var trashItems: [FileSystemService.TrashItem] = []
    @State private var searchText: String = ""
    @State private var hoveredItemId: String?
    @FocusState private var searchFocused: Bool

    private var filteredItems: [FileSystemService.TrashItem] {
        if searchText.isEmpty { return trashItems }
        return trashItems.filter {
            $0.name.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("Search pages in Trash", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))

            Divider()

            if filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 24))
                        .foregroundStyle(.quaternary)
                    Text(trashItems.isEmpty ? "Trash is empty" : "No results")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            trashRow(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !trashItems.isEmpty {
                Divider()
                HStack(spacing: 4) {
                    Text("Auto-deleted after 30 days")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Empty Trash") {
                        guard let workspace = appState.workspacePath else { return }
                        try? fileSystem.emptyTrash(in: workspace)
                        refreshTrash()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 400)
        .popoverSurface()
        .task {
            refreshTrash()
            try? await Task.sleep(for: .milliseconds(100))
            searchFocused = true
        }
    }

    private func trashRow(_ item: FileSystemService.TrashItem) -> some View {
        let displayName = item.name.hasSuffix(".md") ? String(item.name.dropLast(3)) : item.name
        let originalDir = abbreviatedPath(item.originalPath)
        let isHovered = hoveredItemId == item.id

        return HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !originalDir.isEmpty {
                    Text(originalDir)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isHovered {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    guard let workspace = appState.workspacePath else { return }
                    try? fileSystem.restoreFromTrash(item, workspace: workspace)
                    refreshTrash()
                    onRestore()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .help("Restore")

                Button("Delete permanently", systemImage: "trash") {
                    guard let workspace = appState.workspacePath else { return }
                    try? fileSystem.deletePermanently(item, workspace: workspace)
                    refreshTrash()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .help("Delete permanently")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredItemId = hovering ? item.id : nil
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        guard let workspace = appState.workspacePath else { return "" }
        let dir = (path as NSString).deletingLastPathComponent
        guard dir.hasPrefix(workspace) else { return "" }
        let relative = String(dir.dropFirst(workspace.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if relative.isEmpty { return "" }
        let parts = relative.split(separator: "/").map(String.init)
        if parts.count <= 2 {
            return parts.joined(separator: " / ")
        }
        guard let firstPart = parts.first, let lastPart = parts.last else {
            return ""
        }
        return "\(firstPart) / ... / \(lastPart)"
    }

    private func refreshTrash() {
        guard let workspace = appState.workspacePath else { return }
        trashItems = fileSystem.listTrash(in: workspace)
    }
}
