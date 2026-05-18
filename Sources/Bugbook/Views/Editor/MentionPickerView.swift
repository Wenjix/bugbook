import SwiftUI

/// Mention picker popup triggered by typing '@' in a text block.
/// Shows a filtered list of pages; selecting one inserts @[[Page Name]].
struct MentionPickerView: View {
    var document: BlockDocument
    @State private var debouncedEntries: [FileEntry] = []
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        let visible = Array(debouncedEntries.prefix(8))
        VStack(alignment: .leading, spacing: 0) {
            Text("Mention a page")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Display search text
            HStack(spacing: 0) {
                Text("@")
                    .foregroundStyle(.secondary)
                Text(document.mentionPickerFilter.isEmpty ? "Search pages..." : document.mentionPickerFilter)
                    .foregroundStyle(document.mentionPickerFilter.isEmpty ? .secondary : .primary)
                if !document.mentionPickerFilter.isEmpty {
                    Rectangle().fill(Color.accentColor).frame(width: 1, height: 14)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if debouncedEntries.isEmpty {
                Text("No pages found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                let name = entry.name.replacingOccurrences(of: ".md", with: "")
                                document.insertMention(name: name)
                            } label: {
                                HStack(spacing: 8) {
                                    pageIcon(entry)
                                    Text(entry.name.replacingOccurrences(of: ".md", with: ""))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    index == document.mentionPickerSelectedIndex
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
        .onAppear {
            debouncedEntries = document.filteredMentionEntries
        }
        .onChange(of: document.mentionPickerFilter) { _, _ in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                debouncedEntries = document.filteredMentionEntries
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    @ViewBuilder
    private func pageIcon(_ entry: FileEntry) -> some View {
        if let icon = entry.icon, !icon.isEmpty {
            if icon.hasPrefix("custom:") {
                let path = String(icon.dropFirst(7))
                AsyncLocalImageView(path: path, width: 14, height: 14) {
                    defaultIcon(for: entry)
                }
            } else if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 13))
            } else {
                defaultIcon(for: entry)
            }
        } else {
            defaultIcon(for: entry)
        }
    }

    private func defaultIcon(for entry: FileEntry) -> some View {
        Image(systemName: entry.isDatabase ? "tablecells" : "doc.text")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}
