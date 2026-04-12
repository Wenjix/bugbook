import SwiftUI
import DahsoCore

struct MobileSearchView: View {
    let workspacePath: String
    var workspace: MobileWorkspaceService

    @Environment(\.dismiss) private var dismiss
    @FocusState private var queryFieldFocused: Bool

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
            }
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search notes...", text: $query)
                .focused($queryFieldFocused)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                queryFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if query.isEmpty {
            ContentUnavailableView(
                "Search your notes",
                systemImage: "magnifyingglass",
                description: Text("Type a query to search file contents.")
            )
        } else if isSearching && results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(results) { result in
                NavigationLink {
                    MobilePageEditorView(
                        note: MobileNoteFile(path: result.filePath, name: result.fileName),
                        workspace: workspace
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.fileName)
                            .font(.subheadline).fontWeight(.medium)
                        HStack(spacing: 4) {
                            Text("L\(result.lineNumber)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                            Text(result.snippet)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Search Logic

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = await performSearch(query: trimmed)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    private func performSearch(query: String) async -> [SearchResult] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: URL(fileURLWithPath: workspacePath),
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.resume(returning: [])
                    return
                }

                let lowered = query.lowercased()
                var matches: [SearchResult] = []

                for case let url as URL in enumerator {
                    if matches.count >= 50 { break }

                    guard url.pathExtension.lowercased() == "md" else { continue }
                    let name = url.lastPathComponent
                    if name.hasPrefix("_") { continue }

                    let relativePath = String(url.path.dropFirst(workspacePath.count))
                    if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) { continue }

                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    let lines = content.components(separatedBy: .newlines)
                    for (index, line) in lines.enumerated() {
                        if matches.count >= 50 { break }
                        if line.lowercased().contains(lowered) {
                            let snippet = line.trimmingCharacters(in: .whitespaces)
                            let truncated = snippet.count > 120 ? String(snippet.prefix(120)) + "..." : snippet
                            let displayName = String(name.dropLast(3))
                            matches.append(SearchResult(
                                filePath: url.path,
                                fileName: displayName,
                                lineNumber: index + 1,
                                snippet: truncated
                            ))
                        }
                    }
                }

                continuation.resume(returning: matches)
            }
        }
    }
}

// MARK: - Search Result Model

private struct SearchResult: Identifiable {
    let id = UUID()
    let filePath: String
    let fileName: String
    let lineNumber: Int
    let snippet: String
}
