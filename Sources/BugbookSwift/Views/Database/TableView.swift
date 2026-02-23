import SwiftUI

struct TableView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void
    var onDelete: ((DatabaseRow) -> Void)?
    var onToggleColumn: ((String) -> Void)?
    var onAddProperty: (() -> Void)?
    var onRenameProperty: ((String, String) -> Void)?
    var onDeleteProperty: ((String) -> Void)?
    var onChangePropertyType: ((String, PropertyType) -> Void)?

    @State private var dragWidths: [String: CGFloat] = [:]
    @State private var selectedRowIds: Set<String> = []
    @State private var editingCellKey: String? = nil // "rowId_propId" or "rowId_title"

    private var visibleProperties: [PropertyDefinition] {
        let hidden = Set(viewConfig.hiddenColumns ?? [])
        return schema.properties.filter { !hidden.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Large dataset warning
            if rows.count >= 2000 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Large dataset (\(rows.count) rows). Performance may be affected.")
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }

            // Bulk actions bar
            if !selectedRowIds.isEmpty {
                HStack(spacing: 12) {
                    Text("\(selectedRowIds.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        bulkDelete()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        selectedRowIds.removeAll()
                    } label: {
                        Text("Deselect all")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08))
            }

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    headerRow
                    Divider()
                    ForEach($rows) { $row in
                        dataRow($row)
                        Divider()
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Select-all checkbox
            Toggle("", isOn: Binding(
                get: { !rows.isEmpty && selectedRowIds.count == rows.count },
                set: { selectAll in
                    if selectAll {
                        selectedRowIds = Set(rows.map(\.id))
                    } else {
                        selectedRowIds.removeAll()
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 28)
            .padding(.vertical, 6)

            Text("Title")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 200, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)

            ForEach(visibleProperties) { prop in
                HStack(spacing: 0) {
                    Text(prop.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(width: columnWidth(for: prop) - 6, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.leading, 8)
                        .contextMenu {
                            columnContextMenu(for: prop)
                        }

                    // Resize handle
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 3)
                        .cursor(.resizeLeftRight)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let base = viewConfig.columnWidths?[prop.id] ?? 150
                                    let newWidth = max(60, base + value.translation.width)
                                    dragWidths[prop.id] = newWidth
                                }
                        )
                        .padding(.trailing, 3)
                }
            }

            // Add column button
            Button {
                onAddProperty?()
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .padding(.vertical, 6)
            .help("Add property")

            // Column visibility menu
            if let onToggle = onToggleColumn {
                Menu {
                    ForEach(schema.properties) { prop in
                        let isHidden = (viewConfig.hiddenColumns ?? []).contains(prop.id)
                        Button {
                            onToggle(prop.id)
                        } label: {
                            HStack {
                                Text(prop.name)
                                if !isHidden {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .padding(.vertical, 6)
                .help("Toggle column visibility")
            }
        }
    }

    // MARK: - Column Context Menu

    @ViewBuilder
    private func columnContextMenu(for prop: PropertyDefinition) -> some View {
        Button("Rename") {
            // Trigger rename via callback - the parent handles the actual rename dialog
            onRenameProperty?(prop.id, prop.name)
        }

        Menu("Change Type") {
            ForEach(PropertyType.allCases, id: \.rawValue) { type in
                if type != prop.type {
                    Button(type.rawValue.capitalized) {
                        onChangePropertyType?(prop.id, type)
                    }
                }
            }
        }

        Divider()

        if let onToggle = onToggleColumn {
            Button("Hide Column") {
                onToggle(prop.id)
            }
        }

        Divider()

        Button("Delete Property", role: .destructive) {
            onDeleteProperty?(prop.id)
        }
    }

    // MARK: - Data Row

    private func dataRow(_ row: Binding<DatabaseRow>) -> some View {
        let isSelected = selectedRowIds.contains(row.wrappedValue.id)

        return HStack(spacing: 0) {
            // Row selection checkbox
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { selected in
                    if selected {
                        selectedRowIds.insert(row.wrappedValue.id)
                    } else {
                        selectedRowIds.remove(row.wrappedValue.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 28)

            // Title cell - inline editable
            titleCell(row)
                .frame(width: 200, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)

            // Property cells
            ForEach(visibleProperties) { prop in
                let cellKey = "\(row.wrappedValue.id)_\(prop.id)"
                let propValue = Binding<PropertyValue>(
                    get: { row.wrappedValue.properties[prop.name] ?? .empty },
                    set: { newVal in
                        row.wrappedValue.properties[prop.name] = newVal
                        onSave(row.wrappedValue)
                    }
                )

                PropertyEditorView(definition: prop, value: propValue)
                    .frame(width: columnWidth(for: prop), alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(editingCellKey == cellKey ? Color.accentColor.opacity(0.05) : Color.clear)
                    .cornerRadius(2)
                    .onTapGesture {
                        editingCellKey = cellKey
                    }
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    @ViewBuilder
    private func titleCell(_ row: Binding<DatabaseRow>) -> some View {
        let cellKey = "\(row.wrappedValue.id)_title"
        if editingCellKey == cellKey {
            TextField("Untitled", text: row.title, onCommit: {
                editingCellKey = nil
                onSave(row.wrappedValue)
            })
            .textFieldStyle(.plain)
            .font(.body)
        } else {
            HStack(spacing: 4) {
                Button {
                    onOpenRow(row.wrappedValue)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open page")

                Text(row.wrappedValue.title)
                    .lineLimit(1)
                    .onTapGesture {
                        editingCellKey = cellKey
                    }

                Spacer()
            }
        }
    }

    // MARK: - Bulk Operations

    private func bulkDelete() {
        guard let onDel = onDelete else { return }
        let toDelete = rows.filter { selectedRowIds.contains($0.id) }
        for row in toDelete {
            onDel(row)
        }
        selectedRowIds.removeAll()
    }

    private func columnWidth(for prop: PropertyDefinition) -> CGFloat {
        dragWidths[prop.id] ?? viewConfig.columnWidths?[prop.id] ?? 150
    }
}

// Cursor helper for resize handles
private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() }
            else { NSCursor.pop() }
        }
    }
}
