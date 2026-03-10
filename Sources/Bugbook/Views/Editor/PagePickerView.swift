import SwiftUI

/// Page picker popup for the "Link to Page" slash command.
struct PagePickerView: View {
    var document: BlockDocument
    @State private var searchText = ""
    @State private var selectedIndex = 0

    private var flatPages: [FileEntry] {
        flattenEntries(document.availablePages)
            .filter { !$0.isDirectory && !$0.isDatabase && $0.name.hasSuffix(".md") }
    }

    private var filtered: [FileEntry] {
        if searchText.isEmpty { return flatPages }
        return flatPages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Link to page")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            TextField("Search pages...", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .onChange(of: searchText) { _, _ in
                    selectedIndex = 0
                }
                .onSubmit {
                    selectCurrent()
                }

            Divider()

            if filtered.isEmpty {
                Text("No pages found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filtered.prefix(8).enumerated()), id: \.element.id) { index, entry in
                            Button {
                                selectEntry(entry)
                            } label: {
                                HStack(spacing: 8) {
                                    if let icon = entry.icon {
                                        Text(icon).font(.system(size: 13))
                                    } else {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(entry.name.replacingOccurrences(of: ".md", with: ""))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    index == selectedIndex
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 240)
        .popoverSurface()
    }

    private func selectCurrent() {
        let items = filtered
        guard !items.isEmpty else { return }
        let idx = min(selectedIndex, items.count - 1)
        selectEntry(items[idx])
    }

    private func selectEntry(_ entry: FileEntry) {
        let name = entry.name.replacingOccurrences(of: ".md", with: "")
        document.insertPageLink(name: name)
    }

    private func flattenEntries(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries {
            result.append(entry)
            if let children = entry.children {
                result.append(contentsOf: flattenEntries(children))
            }
        }
        return result
    }
}
