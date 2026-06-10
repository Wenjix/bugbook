import SwiftUI

/// Page picker popup for the "Link to Page" slash command.
/// Keyboard input is intercepted by BlockTextView and routed to document.pagePickerSearch.
struct PagePickerView: View {
    var document: BlockDocument
    @State private var debouncedEntries: [FileEntry] = []
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        let visible = Array(debouncedEntries.prefix(8))
        VStack(alignment: .leading, spacing: 0) {
            Text("Link to page")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Display search text (input comes from text view, not this field)
            HStack(spacing: 0) {
                Text(document.pagePickerSearch.isEmpty ? "Search pages..." : document.pagePickerSearch)
                    .foregroundStyle(document.pagePickerSearch.isEmpty ? .secondary : .primary)
                if !document.pagePickerSearch.isEmpty {
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
                                document.insertPageLink(name: name)
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
                                    index == document.pagePickerSelectedIndex
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
            debouncedEntries = document.filteredPagePickerEntries
        }
        .onChange(of: document.pagePickerSearch) { _, _ in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000) // 120ms debounce
                guard !Task.isCancelled else { return }
                debouncedEntries = document.filteredPagePickerEntries
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    private func pageIcon(_ entry: FileEntry) -> some View {
        PageIconView(icon: entry.icon) {
            defaultIcon(for: entry)
        }
        .foregroundStyle(.secondary)
    }

    private func defaultIcon(for entry: FileEntry) -> some View {
        Image(systemName: entry.isDatabase ? "tablecells" : "doc.text")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}
