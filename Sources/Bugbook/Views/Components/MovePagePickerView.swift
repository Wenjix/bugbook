import SwiftUI

/// Modal picker for choosing a destination when moving a page.
struct MovePagePickerView: View {
    let fileTree: [FileEntry]
    let movingPath: String
    let workspacePath: String
    var onMove: (String) -> Void  // destination directory path
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFieldFocused: Bool

    private var destinations: [Destination] {
        var result: [Destination] = []

        // Workspace root
        let movingParent = (movingPath as NSString).deletingLastPathComponent
        if movingParent != workspacePath {
            result.append(Destination(
                id: workspacePath,
                name: "Workspace",
                icon: nil,
                sfSymbol: "house",
                destDir: workspacePath,
                hasChildren: true
            ))
        }

        // Flatten file tree into page destinations
        flattenPages(fileTree, into: &result)

        if searchText.isEmpty { return result }
        return result.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Move page to...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isSearchFieldFocused)
                    .onSubmit { selectCurrent() }
            }
            .padding(12)

            Divider()

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let items = destinations
                        if items.isEmpty {
                            Text("No pages found")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, dest in
                                destinationRow(dest, index: index)
                                    .id(dest.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
                .onChange(of: selectedIndex) { _, newIndex in
                    let items = destinations
                    if newIndex >= 0, newIndex < items.count {
                        proxy.scrollTo(items[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: 460)
        .background(Color.fallbackBgPrimary)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(destinations.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onAppear {
            NSApp.keyWindow?.makeFirstResponder(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private func destinationRow(_ dest: Destination, index: Int) -> some View {
        Button {
            selectedIndex = index
            onMove(dest.destDir)
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                if dest.hasChildren {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                destinationIcon(dest)

                Text(dest.name)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(index == selectedIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destinationIcon(_ dest: Destination) -> some View {
        if let sfSymbol = dest.sfSymbol {
            Image(systemName: sfSymbol)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
        } else if let icon = dest.icon, !icon.isEmpty {
            if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 15)).frame(width: 20)
            } else {
                defaultPageIcon.frame(width: 20)
            }
        } else {
            defaultPageIcon.frame(width: 20)
        }
    }

    private var defaultPageIcon: some View {
        Image(systemName: "doc.text")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
    }

    private func selectCurrent() {
        let items = destinations
        guard !items.isEmpty else { return }
        let idx = min(selectedIndex, items.count - 1)
        onMove(items[idx].destDir)
        isPresented = false
    }

    // MARK: - Data

    private struct Destination: Identifiable {
        let id: String
        let name: String
        let icon: String?
        let sfSymbol: String?
        let destDir: String
        let hasChildren: Bool
    }

    private func flattenPages(_ entries: [FileEntry], into result: inout [Destination]) {
        for entry in entries {
            // Skip the page being moved and its descendants
            if entry.path == movingPath { continue }
            if isDescendant(entry.path, of: movingPath) { continue }

            if entry.kind == .page && entry.name.hasSuffix(".md") {
                // Moving into this page means moving into its companion folder
                let companionDir = String(entry.path.dropLast(3)) // remove .md
                result.append(Destination(
                    id: entry.path,
                    name: entry.name.replacingOccurrences(of: ".md", with: ""),
                    icon: entry.icon,
                    sfSymbol: nil,
                    destDir: companionDir,
                    hasChildren: entry.children != nil && !(entry.children?.isEmpty ?? true)
                ))
            } else if entry.isDatabase {
                // Skip databases as move targets
            } else if entry.isCanvas {
                // Skip canvases as move targets
            }

            if let children = entry.children {
                flattenPages(children, into: &result)
            }
        }
    }

    private func isDescendant(_ path: String, of ancestorPath: String) -> Bool {
        // Check if path is inside the companion folder of ancestorPath
        guard ancestorPath.hasSuffix(".md") else { return false }
        let companionDir = String(ancestorPath.dropLast(3))
        return path.hasPrefix(companionDir + "/")
    }
}
