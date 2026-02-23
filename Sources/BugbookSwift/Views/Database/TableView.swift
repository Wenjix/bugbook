import SwiftUI

struct TableView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void
    var onDelete: ((DatabaseRow) -> Void)?
    var onToggleColumn: ((String) -> Void)?

    @State private var dragWidths: [String: CGFloat] = [:]

    private var visibleProperties: [PropertyDefinition] {
        let hidden = Set(viewConfig.hiddenColumns ?? [])
        return schema.properties.filter { !hidden.contains($0.id) }
    }

    var body: some View {
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

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
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
                    Image(systemName: "plus.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Data Row

    private func dataRow(_ row: Binding<DatabaseRow>) -> some View {
        HStack(spacing: 0) {
            // Title cell
            HStack(spacing: 4) {
                Button {
                    onOpenRow(row.wrappedValue)
                } label: {
                    Text(row.wrappedValue.title)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Spacer()

                // Delete button (appears on hover would be ideal, always visible for simplicity)
                if let onDel = onDelete {
                    Button {
                        onDel(row.wrappedValue)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 200, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)

            // Property cells
            ForEach(visibleProperties) { prop in
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
            }
        }
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
