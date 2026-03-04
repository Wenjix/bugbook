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
    var onUpdateSelectOption: ((String, String, String?, String?) -> Void)?
    var onDeleteSelectOption: ((String, String) -> Void)?
    var onResizeColumn: ((String, CGFloat) -> Void)?
    var onNewRow: (() -> Void)?
    var scrollToRowId: String? = nil
    var showVerticalLines: Bool = true

    @State private var dragWidths: [String: CGFloat] = [:]
    @State private var hoveredRowId: String?
    @State private var hoveredResizeKey: String?
    @State private var draggingResizeKey: String?
    @State private var selectedRowIds: Set<String> = []
    @State private var lastSelectedRowId: String? = nil

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

            // Header
            headerRow
            Divider()

            // Selection toolbar
            if !selectedRowIds.isEmpty {
                selectionBar
                Divider()
            }

            // Rows
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach($rows) { $row in
                            dataRow($row)
                                .id($row.wrappedValue.id)
                            Divider().opacity(0.5)
                        }
                        // Phantom rows so the table always looks populated
                        ForEach(0..<max(0, 3 - rows.count), id: \.self) { i in
                            phantomRow(isFirst: rows.isEmpty && i == 0)
                            Divider().opacity(0.5)
                        }
                    }  // end VStack
                }
                .frame(maxHeight: .infinity)
                .onChange(of: scrollToRowId) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    // MARK: - Selection Bar

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedRowIds.count) selected")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            Button {
                selectedRowIds.removeAll()
            } label: {
                Text("Deselect")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            Button {
                let toDelete = rows.filter { selectedRowIds.contains($0.id) }
                selectedRowIds.removeAll()
                toDelete.forEach { onDelete?($0) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.caption)
                    Text("Delete")
                        .font(.callout)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.05))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Title column header
            Text(schema.titleProperty?.name ?? "Name")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .frame(width: titleColumnWidth)
                .overlay(alignment: .trailing) {
                    resizeHandle(key: titleColumnKey, baseWidth: viewConfig.columnWidths?[titleColumnKey] ?? 240)
                }

            // Property column headers
            ForEach(visibleProperties) { prop in
                ColumnHeaderCell(
                    prop: prop,
                    onRename: onRenameProperty,
                    onChangeType: onChangePropertyType,
                    onToggleColumn: onToggleColumn,
                    onDelete: onDeleteProperty
                )
                .frame(width: columnWidth(for: prop))
                .overlay(alignment: .trailing) {
                    resizeHandle(key: prop.id, baseWidth: viewConfig.columnWidths?[prop.id] ?? 150)
                }
            }

            // Add property
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
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("Add property")
                        .font(.callout)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    // MARK: - Resize Handle (overlaid on column trailing edge)

    private func resizeHandle(key: String, baseWidth: Double) -> some View {
        let isActive = hoveredResizeKey == key || draggingResizeKey == key
        return Color.clear
            .frame(width: 8)
            .overlay {
                Rectangle()
                    .fill(isActive ? Color.fallbackBadgeBg : Color.clear)
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .onHover { hoveredResizeKey = $0 ? key : nil }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        draggingResizeKey = key
                        dragWidths[key] = max(80, CGFloat(baseWidth) + value.translation.width)
                    }
                    .onEnded { _ in
                        if let finalWidth = dragWidths[key] {
                            onResizeColumn?(key, finalWidth)
                        }
                        draggingResizeKey = nil
                    }
            )
    }

    // MARK: - Data Row

    private func dataRow(_ row: Binding<DatabaseRow>) -> some View {
        let isHovered = hoveredRowId == row.wrappedValue.id

        return HStack(spacing: 0) {
            titleCell(row)
                .padding(.horizontal, 8)
                .frame(width: titleColumnWidth, alignment: .leading)
                .contentShape(Rectangle())
                .cursor(.pointingHand)

            ForEach(visibleProperties) { prop in
                let propValue = Binding<PropertyValue>(
                    get: { row.wrappedValue.properties[prop.id] ?? .empty },
                    set: { newVal in
                        var updatedRow = row.wrappedValue
                        updatedRow.properties[prop.id] = newVal
                        row.wrappedValue = updatedRow
                        onSave(updatedRow)
                    }
                )
                PropertyEditorView(definition: prop, value: propValue, onAddOption: onAddSelectOption, onUpdateOption: onUpdateSelectOption, onDeleteOption: onDeleteSelectOption)
                    .padding(.horizontal, 8)
                    .frame(width: columnWidth(for: prop), alignment: .leading)
                    .contentShape(Rectangle())
                    .cursor(.pointingHand)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .background(isHovered ? Color.fallbackSurfaceHover : Color.clear)
        .overlay { columnDividers().allowsHitTesting(false) }
        .onHover { hoveredRowId = $0 ? row.wrappedValue.id : nil }
    }

    // MARK: - Column Dividers (row-level overlay)

    @ViewBuilder
    private func columnDividers() -> some View {
        if showVerticalLines {
            HStack(spacing: 0) {
                Color.clear.frame(width: 8 + titleColumnWidth)
                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1)
                ForEach(visibleProperties) { prop in
                    Color.clear.frame(width: columnWidth(for: prop))
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, -15)
        }
    }

    // MARK: - Title Cell

    private func titleCell(_ row: Binding<DatabaseRow>) -> some View {
        let titlePropId = schema.titleProperty?.id
        let rowId = row.wrappedValue.id
        let isSelected = selectedRowIds.contains(rowId)
        let isHoveredRow = hoveredRowId == rowId
        // Show checkbox when: hovering, this row is selected, OR any row is already selected
        // (so the user can see all checkboxes and easily Shift-select a range)
        let showCheckbox = isHoveredRow || isSelected || !selectedRowIds.isEmpty

        return HStack(spacing: 6) {
            // Select checkbox
            if showCheckbox {
                Button {
                    if NSEvent.modifierFlags.contains(.shift),
                       let lastId = lastSelectedRowId,
                       let lastIdx = rows.firstIndex(where: { $0.id == lastId }),
                       let currentIdx = rows.firstIndex(where: { $0.id == rowId }) {
                        // Range-select between last clicked and current
                        let lo = min(lastIdx, currentIdx)
                        let hi = max(lastIdx, currentIdx)
                        for i in lo...hi { selectedRowIds.insert(rows[i].id) }
                    } else {
                        if isSelected {
                            selectedRowIds.remove(rowId)
                        } else {
                            selectedRowIds.insert(rowId)
                            lastSelectedRowId = rowId
                        }
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Open page icon (only on hover)
            if isHoveredRow {
                Button {
                    onOpenRow(row.wrappedValue)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Open page")
            }

            TextField("New Page", text: Binding(
                get: {
                    guard let propId = titlePropId,
                          let val = row.wrappedValue.properties[propId],
                          case .text(let s) = val else { return "" }
                    return s
                },
                set: { newVal in
                    guard let propId = titlePropId else { return }
                    var updatedRow = row.wrappedValue
                    updatedRow.properties[propId] = .text(newVal)
                    row.wrappedValue = updatedRow
                    onSave(updatedRow)
                }
            ))
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundColor(.primary)
        }
    }

    // MARK: - Phantom Row

    private func phantomRow(isFirst: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if isFirst {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(Color.primary.opacity(0.25))
                }
                TextField(isFirst ? "New page" : "", text: .constant(""))
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundColor(Color.primary.opacity(0.25))
                    .disabled(true)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 8)
            .frame(width: titleColumnWidth, alignment: .leading)
            ForEach(visibleProperties) { prop in
                TextField("", text: .constant(""))
                    .textFieldStyle(.plain)
                    .disabled(true)
                    .allowsHitTesting(false)
                    .padding(.horizontal, 8)
                    .frame(width: columnWidth(for: prop), alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay { columnDividers().allowsHitTesting(false) }
        .onTapGesture { onNewRow?() }
    }

    // MARK: - Helpers

    private func columnWidth(for prop: PropertyDefinition) -> CGFloat {
        dragWidths[prop.id] ?? viewConfig.columnWidths?[prop.id] ?? 180
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

// MARK: - Column Header Cell (own View for independent popover)

private struct ColumnHeaderCell: View {
    let prop: PropertyDefinition
    var onRename: ((String, String) -> Void)?
    var onChangeType: ((String, PropertyType) -> Void)?
    var onToggleColumn: ((String) -> Void)?
    var onDelete: ((String) -> Void)?

    @State private var isHovered = false
    @State private var showPopover = false
    @State private var editingName: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconForType(prop.type))
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(prop.name)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background(isHovered || showPopover ? Color.gray.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
            if inside { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
        .onTapGesture {
            editingName = prop.name
            showPopover = true
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Property name", text: $editingName)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onSubmit {
                    let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && trimmed != prop.name {
                        onRename?(prop.id, trimmed)
                    }
                    showPopover = false
                }

            HStack {
                Text("Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Menu {
                    ForEach(PropertyType.allCases, id: \.rawValue) { type in
                        if type != prop.type && type != .title {
                            Button {
                                onChangeType?(prop.id, type)
                                showPopover = false
                            } label: {
                                Label(type.rawValue.capitalized, systemImage: iconForType(type))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: iconForType(prop.type))
                            .font(.caption)
                        Text(prop.type.rawValue.capitalized)
                            .font(.callout)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Divider()

            if onToggleColumn != nil {
                Button {
                    onToggleColumn?(prop.id)
                    showPopover = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                        Text("Hide property")
                            .font(.callout)
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }

            Button {
                onDelete?(prop.id)
                showPopover = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.caption)
                    Text("Delete property")
                        .font(.callout)
                }
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 220)
    }

    private func iconForType(_ type: PropertyType) -> String {
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
