import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @Binding var isPresented: Bool
    var onSelectFile: (FileEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search pages...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit { selectCurrent() }
            }
            .padding(12)

            Divider()

            // Results
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 8) {
                            if entry.isDatabase {
                                Image(systemName: "tablecells").font(.system(size: 12))
                            } else {
                                Image(systemName: "doc.text").font(.system(size: 12))
                            }
                            Text(entry.name.replacingOccurrences(of: ".md", with: ""))
                                .font(.system(size: 14))
                            Spacer()
                            Text(relativePath(for: entry))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectFile(entry)
                            isPresented = false
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 500)
        .background(Color.fallbackBgPrimary)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onKeyPress(.upArrow) { selectedIndex = max(0, selectedIndex - 1); return .handled }
        .onKeyPress(.downArrow) { selectedIndex = min(filteredEntries.count - 1, selectedIndex + 1); return .handled }
        .onKeyPress(.escape) { isPresented = false; return .handled }
    }

    private var filteredEntries: [FileEntry] {
        let allFiles = flattenFileTree(appState.fileTree)
        if searchText.isEmpty { return allFiles }
        return allFiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func flattenFileTree(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries {
            if !entry.isDirectory || entry.isDatabase {
                result.append(entry)
            }
            if let children = entry.children {
                result.append(contentsOf: flattenFileTree(children))
            }
        }
        return result
    }

    private func selectCurrent() {
        guard selectedIndex < filteredEntries.count else { return }
        onSelectFile(filteredEntries[selectedIndex])
        isPresented = false
    }

    private func relativePath(for entry: FileEntry) -> String {
        guard let workspace = appState.workspacePath else { return "" }
        return entry.path.replacingOccurrences(of: workspace + "/", with: "")
    }
}
