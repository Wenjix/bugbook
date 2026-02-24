import SwiftUI
import BugbookCore

struct TableView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void
    var onDelete: ((DatabaseRow) -> Void)?
    var onToggleColumn: ((String) -> Void)?
    var onAddProperty: ((PropertyType) -> Void)?
    var onRenameProperty: ((String, String) -> Void)?
    var onDeleteProperty: ((String) -> Void)?
    var onChangePropertyType: ((String, PropertyType) -> Void)?
    var onAddSelectOption: ((String, SelectOption) -> Void)?
    var onResizeColumn: ((String, CGFloat) -> Void)?

    @State private var dragWidths: [String: CGFloat] = [:]
    @State private var selectedRowIds: Set<String> = []
    @State private var editingCellKey: String? = nil
    @State private var hoveredRowId: String?

    private let titleColumnKey = "__title__"

    private var visibleProperties: [PropertyDefinition] {
        let hidden = Set(viewConfig.hiddenColumns ?? [])
        return schema.properties.filter { $0.type != .title && !hidden.contains($0.id) }
    }

    private var titleColumnWidth: CGFloat {
        dragWidths[titleColumnKey] ?? viewConfig.columnWidths?[titleColumnKey] ?? 240
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .background(Color.orange.opacity(0.08))
            }

            if !selectedRowIds.isEmpty {
                bulkActionsBar
            }

            // Header
            headerRow
            Divider()

            // Rows
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach($rows) { $row in
                        dataRow($row)
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }

    // MARK: - Bulk Actions

    private var bulkActionsBar: some View {
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

            Button("Deselect all") {
                selectedRowIds.removeAll()
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Select-all
            Toggle("", isOn: Binding(
                get: { !rows.isEmpty && selectedRowIds.count == rows.count },
                set: { selectAll in
                    selectedRowIds = selectAll ? Set(rows.map(\.id)) : []
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 32)
            .padding(.vertical, 6)

            // Title column header + resize handle
            HStack(spacing: 0) {
                Text(schema.titleProperty?.name ?? "Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: titleColumnWidth - 4, alignment: .leading)
                    .padding(.leading, 8)

                resizeHandle(key: titleColumnKey, baseWidth: viewConfig.columnWidths?[titleColumnKey] ?? 240)
            }

            // Property column headers
            ForEach(visibleProperties) { prop in
                HStack(spacing: 0) {
                    Text(prop.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: columnWidth(for: prop) - 4, alignment: .leading)
                        .padding(.leading, 8)
                        .contextMenu { columnContextMenu(for: prop) }

                    resizeHandle(key: prop.id, baseWidth: viewConfig.columnWidths?[prop.id] ?? 150)
                }
            }

            // Add column
            Menu {
                ForEach(PropertyType.allCases, id: \.rawValue) { type in
                    if type != .title {
                        Button {
                            onAddProperty?(type)
                        } label: {
                            Label(type.rawValue.capitalized, systemImage: iconForPropertyType(type))
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .help("Add property")

            // Column visibility
            if let onToggle = onToggleColumn {
                Menu {
                    ForEach(schema.properties.filter({ $0.type != .title })) { prop in
                        let isHidden = (viewConfig.hiddenColumns ?? []).contains(prop.id)
                        Button {
                            onToggle(prop.id)
                        } label: {
                            HStack {
                                Text(prop.name)
                                if !isHidden { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 32)
                .help("Toggle columns")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Resize Handle

    private func resizeHandle(key: String, baseWidth: Double) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 2, height: 18)
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        dragWidths[key] = max(80, CGFloat(baseWidth) + value.translation.width)
                    }
                    .onEnded { _ in
                        if let finalWidth = dragWidths[key] {
                            onResizeColumn?(key, finalWidth)
                        }
                    }
            )
            .padding(.horizontal, 1)
    }

    // MARK: - Column Context Menu

    @ViewBuilder
    private func columnContextMenu(for prop: PropertyDefinition) -> some View {
        Button("Rename") {
            onRenameProperty?(prop.id, prop.name)
        }
        Menu("Change Type") {
            ForEach(PropertyType.allCases, id: \.rawValue) { type in
                if type != prop.type && type != .title {
                    Button(type.rawValue.capitalized) {
                        onChangePropertyType?(prop.id, type)
                    }
                }
            }
        }
        Divider()
        if let onToggle = onToggleColumn {
            Button("Hide Column") { onToggle(prop.id) }
        }
        Divider()
        Button("Delete Property", role: .destructive) {
            onDeleteProperty?(prop.id)
        }
    }

    // MARK: - Data Row

    private func dataRow(_ row: Binding<DatabaseRow>) -> some View {
        let isSelected = selectedRowIds.contains(row.wrappedValue.id)
        let isHovered = hoveredRowId == row.wrappedValue.id

        return HStack(spacing: 0) {
            // Checkbox
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { selected in
                    if selected { selectedRowIds.insert(row.wrappedValue.id) }
                    else { selectedRowIds.remove(row.wrappedValue.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 32)

            // Title cell
            titleCell(row)
                .frame(width: titleColumnWidth, alignment: .leading)
                .padding(.horizontal, 8)

            // Property cells
            ForEach(visibleProperties) { prop in
                let propValue = Binding<PropertyValue>(
                    get: { row.wrappedValue.properties[prop.id] ?? .empty },
                    set: { newVal in
                        row.wrappedValue.properties[prop.id] = newVal
                        onSave(row.wrappedValue)
                    }
                )
                PropertyEditorView(definition: prop, value: propValue, onAddOption: onAddSelectOption)
                    .frame(width: columnWidth(for: prop), alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.06) : isHovered ? Color.gray.opacity(0.04) : Color.clear)
        .onHover { hoveredRowId = $0 ? row.wrappedValue.id : nil }
    }

    // MARK: - Title Cell

    @ViewBuilder
    private func titleCell(_ row: Binding<DatabaseRow>) -> some View {
        let cellKey = "\(row.wrappedValue.id)_title"
        let titlePropId = schema.titleProperty?.id
        let rawTitle = rawTitleText(row.wrappedValue)
        let displayTitle = row.wrappedValue.title(schema: schema)

        if editingCellKey == cellKey {
            TextField("New Page", text: Binding(
                get: { rawTitle },
                set: { newVal in
                    if let propId = titlePropId {
                        row.wrappedValue.properties[propId] = .text(newVal)
                    }
                }
            ), onCommit: {
                editingCellKey = nil
                onSave(row.wrappedValue)
            })
            .textFieldStyle(.plain)
            .font(.body)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
        } else {
            HStack(spacing: 6) {
                // Open page icon (only on hover)
                if hoveredRowId == row.wrappedValue.id {
                    Button {
                        onOpenRow(row.wrappedValue)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Open page")
                }

                Text(displayTitle)
                    .lineLimit(1)
                    .foregroundColor(rawTitle.isEmpty ? .secondary : .primary)

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                editingCellKey = cellKey
            }
        }
    }

    private func rawTitleText(_ row: DatabaseRow) -> String {
        guard let titlePropId = schema.titleProperty?.id,
              let val = row.properties[titlePropId],
              case .text(let s) = val else { return "" }
        return s
    }

    // MARK: - Helpers

    private func bulkDelete() {
        guard let onDel = onDelete else { return }
        for row in rows where selectedRowIds.contains(row.id) {
            onDel(row)
        }
        selectedRowIds.removeAll()
    }

    private func columnWidth(for prop: PropertyDefinition) -> CGFloat {
        dragWidths[prop.id] ?? viewConfig.columnWidths?[prop.id] ?? 150
    }

    private func iconForPropertyType(_ type: PropertyType) -> String {
        switch type {
        case .title: return "textformat"
        case .text: return "doc.text"
        case .number: return "number"
        case .select: return "list.bullet"
        case .multiSelect: return "tag"
        case .date: return "calendar"
        case .checkbox: return "checkmark.square"
        case .url: return "link"
        case .email: return "envelope"
        case .relation: return "arrow.triangle.branch"
        }
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
