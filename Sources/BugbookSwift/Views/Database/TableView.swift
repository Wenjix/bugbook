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
    var showVerticalLines: Bool = true

    @State private var dragWidths: [String: CGFloat] = [:]
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

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Title column header
            Text(schema.titleProperty?.name ?? "Name")
                .font(.subheadline)
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
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add property")

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Resize Handle (overlaid on column trailing edge)

    private func resizeHandle(key: String, baseWidth: Double) -> some View {
        Color.clear
            .frame(width: 8)
            .overlay {
                Rectangle()
                    .fill(showVerticalLines ? Color.gray.opacity(0.2) : Color.clear)
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
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
    }

    // MARK: - Data Row

    private func dataRow(_ row: Binding<DatabaseRow>) -> some View {
        let isHovered = hoveredRowId == row.wrappedValue.id

        return HStack(spacing: 0) {
            // Title cell
            titleCell(row)
                .padding(.horizontal, 8)
                .frame(width: titleColumnWidth, alignment: .leading)
                .contentShape(Rectangle())
                .cursor(.pointingHand)
                .overlay(alignment: .trailing) {
                    if showVerticalLines {
                        Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1)
                            .padding(.vertical, -7)
                    }
                }

            // Property cells
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
                    .overlay(alignment: .trailing) {
                        if showVerticalLines {
                            Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1)
                                .padding(.vertical, -7)
                        }
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.gray.opacity(0.04) : Color.clear)
        .onHover { hoveredRowId = $0 ? row.wrappedValue.id : nil }
    }

    // MARK: - Title Cell

    @ViewBuilder
    private func titleCell(_ row: Binding<DatabaseRow>) -> some View {
        let titlePropId = schema.titleProperty?.id

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
            .foregroundColor(.primary)
        }
    }

    // MARK: - Helpers

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
                .font(.subheadline)
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
