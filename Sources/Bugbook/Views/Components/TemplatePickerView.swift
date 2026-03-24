import SwiftUI

struct TemplatePickerView: View {
    let templates: [FileEntry]
    let onSelect: (FileEntry) -> Void
    let onDismiss: () -> Void
    let onCreateTemplate: (() -> Void)?
    let onDelete: ((FileEntry) -> Void)?

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var hoveredIndex: Int?
    @State private var createHovered = false
    @State private var templateToDelete: FileEntry?
    @FocusState private var searchFocused: Bool

    private var filtered: [FileEntry] {
        if searchText.isEmpty { return templates }
        let query = searchText.lowercased()
        return templates.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if templates.isEmpty {
                emptyState
            } else {
                searchField
                Divider()

                if filtered.isEmpty {
                    noResults
                } else {
                    templateList
                }
            }

            if let onCreateTemplate {
                Divider()
                createButton(action: onCreateTemplate)
            }
        }
        .frame(width: 280)
        .popoverSurface(cornerRadius: Radius.lg)
        .onAppear { searchFocused = true }
        .alert("Delete Template?", isPresented: .init(
            get: { templateToDelete != nil },
            set: { if !$0 { templateToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { templateToDelete = nil }
            Button("Delete", role: .destructive) {
                if let entry = templateToDelete {
                    onDelete?(entry)
                    templateToDelete = nil
                }
            }
        } message: {
            if let entry = templateToDelete {
                let name = entry.name.hasSuffix(".md")
                    ? String(entry.name.dropLast(3)) : entry.name
                Text("\"\(name)\" will be permanently deleted.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Templates")
                .font(.system(size: Typography.bodySmall, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: Typography.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Typography.caption))
                .foregroundStyle(.tertiary)
            TextField("Filter templates...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: Typography.bodySmall))
                .focused($searchFocused)
                .onSubmit { selectCurrent() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Template List

    private var templateList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, template in
                        templateRow(template, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 260)
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func templateRow(_ template: FileEntry, index: Int) -> some View {
        let displayName = template.name.hasSuffix(".md")
            ? String(template.name.dropLast(3))
            : template.name
        let isSelected = index == selectedIndex
        let isHovered = hoveredIndex == index

        return Button(action: { onSelect(template) }) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(.secondary)
                Text(displayName)
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if isHovered && onDelete != nil {
                    Button {
                        templateToDelete = template
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: Typography.caption2))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.accentColor.opacity(Opacity.light)
                    : isHovered
                        ? Color.primary.opacity(Opacity.subtle)
                        : Color.clear
            )
            .clipShape(.rect(cornerRadius: Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredIndex = hovering ? index : nil }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No templates yet")
                .font(.system(size: Typography.bodySmall, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Save any note as a template to\nreuse its structure for new pages.")
                .font(.system(size: Typography.caption))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var noResults: some View {
        Text("No matching templates")
            .font(.system(size: Typography.caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Create Button

    private func createButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(Color.accentColor)
                Text("Save current note as template")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(createHovered ? Color.primary.opacity(Opacity.subtle) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in createHovered = hovering }
    }

    // MARK: - Keyboard Navigation

    private func moveSelection(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func selectCurrent() {
        guard !filtered.isEmpty, selectedIndex < filtered.count else { return }
        onSelect(filtered[selectedIndex])
    }
}
