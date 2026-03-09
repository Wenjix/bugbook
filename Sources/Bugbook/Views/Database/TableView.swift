import SwiftUI
import BugbookCore

struct TableView: View {
    static let rowControlsInset: CGFloat = 46

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
    var onReorderRows: ((String, String?) -> Void)?
    var onNewRow: (() -> Void)?
    var scrollToRowId: String? = nil
    var showVerticalLines: Bool = true
    var usesInnerScroll: Bool = true

    @State private var dragWidths: [String: CGFloat] = [:]
    @State private var hoveredResizeKey: String?
    @State private var draggingResizeKey: String?
    @State private var selectedRowIds: Set<String> = []
    @State private var lastSelectedRowId: String? = nil
    @State private var didInitialScroll = false

    private let titleColumnKey = "__title__"
    private let topAnchorKey = "__table_top__"
    private let rowHandleWidth: CGFloat = 12
    private let checkboxWidth: CGFloat = 18
    private let rowControlsSpacing: CGFloat = 6

    private var visibleProperties: [PropertyDefinition] {
        let hidden = Set(viewConfig.hiddenColumns ?? [])
        return schema.properties.filter { $0.type != .title && !hidden.contains($0.id) }
    }

    private var titleColumnWidth: CGFloat {
        dragWidths[titleColumnKey] ?? viewConfig.columnWidths?[titleColumnKey] ?? 320
    }

    private var wrapCellText: Bool {
        viewConfig.wrapCellText ?? false
    }

    private var canReorderRows: Bool {
        viewConfig.sorts.isEmpty
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
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
            }

            // Header
            headerRow
            tableDivider

            // Selection toolbar
            if !selectedRowIds.isEmpty {
                selectionBar
                tableDivider
            }

            rowsRegion
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: usesInnerScroll ? .infinity : nil,
            alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: !usesInnerScroll)
        .databasePointerCursor()
    }

    // MARK: - Selection Bar

    private var selectionBar: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Self.rowControlsInset)

            HStack(spacing: 16) {
                Text("\(selectedRowIds.count) selected")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)

                Button {
                    let toDelete = rows.filter { selectedRowIds.contains($0.id) }
                    selectedRowIds.removeAll()
                    toDelete.forEach { onDelete?($0) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Delete")
                            .font(.callout)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.red.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    selectedRowIds.removeAll()
                } label: {
                    Text("Deselect all")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.03))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Self.rowControlsInset)

            // Title column header
            Text(schema.titleProperty?.name ?? "Name")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .frame(width: titleColumnWidth)
                .overlay(alignment: .trailing) {
                    resizeHandle(key: titleColumnKey, baseWidth: viewConfig.columnWidths?[titleColumnKey] ?? 320)
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
                            Label(type.rawValue.capitalized, systemImage: type.systemImageName)
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
                .foregroundStyle(.secondary)
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
        let hitWidth: CGFloat = 16
        return Color.clear
            .frame(width: hitWidth)
            .overlay {
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: isActive ? 2 : 1)
                    .padding(.vertical, -8)
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
            .offset(x: hitWidth / 2)
            .zIndex(10)
    }

    // MARK: - Data Row

    private func dataRow(_ row: Binding<DatabaseRow>) -> some View {
        HoverRow { isHovered in
            HStack(alignment: .center, spacing: 0) {
                rowControls(for: row.wrappedValue, isHovered: isHovered)
                    .frame(width: Self.rowControlsInset)

                HStack(alignment: .top, spacing: 0) {
                    titleCell(row, isHovered: isHovered)
                        .padding(.horizontal, 8)
                        .frame(width: titleColumnWidth, alignment: .leading)
                        .contentShape(Rectangle())
                        .databasePointerCursor()

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
                        PropertyEditorView(definition: prop, value: propValue, wrapText: wrapCellText, compact: true, onAddOption: onAddSelectOption, onUpdateOption: onUpdateSelectOption, onDeleteOption: onDeleteSelectOption)
                            .padding(.horizontal, 8)
                            .frame(width: columnWidth(for: prop), alignment: .leading)
                            .contentShape(Rectangle())
                            .databasePointerCursor()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
                )
                .overlay { columnDividers().allowsHitTesting(false) }
                .dropDestination(for: String.self) { droppedIds, _ in
                    guard canReorderRows,
                          let draggedId = droppedIds.first,
                          draggedId != row.wrappedValue.id else { return false }
                    onReorderRows?(draggedId, row.wrappedValue.id)
                    return true
                }
            }
        }
    }

    // MARK: - Column Dividers (row-level overlay)

    @ViewBuilder
    private func columnDividers() -> some View {
        if showVerticalLines {
            HStack(spacing: 0) {
                Color.clear.frame(width: 8 + titleColumnWidth)
                Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 1)
                ForEach(visibleProperties) { prop in
                    Color.clear.frame(width: columnWidth(for: prop))
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Title Cell

    private func titleCell(_ row: Binding<DatabaseRow>, isHovered: Bool) -> some View {
        let titlePropId = schema.titleProperty?.id
        let openPillSize = CGSize(width: 74, height: 24)
        let titleBinding = Binding(
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
        )

        return titleTextField(titleBinding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .databasePointerCursor()
            .overlay(alignment: .trailing) {
                if isHovered {
                    Button {
                        onOpenRow(row.wrappedValue)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("OPEN")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.3)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: openPillSize.width, height: openPillSize.height)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.fallbackBgSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.fallbackBorderColor.opacity(0.9), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Open in side peek")
                    .padding(.trailing, 4)
                }
            }
    }

    // MARK: - Phantom Row

    private func phantomRow(isFirst: Bool) -> some View {
        Button { onNewRow?() } label: {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: Self.rowControlsInset)
                    .overlay(alignment: .trailing) {
                        if isFirst {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.25))
                                .padding(.trailing, 8)
                        }
                    }

                HStack(spacing: 0) {
                    TextField(isFirst ? "New page" : "", text: .constant(""))
                        .textFieldStyle(.plain)
                        .font(.system(size: EditorTypography.bodyFontSize))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .disabled(true)
                        .allowsHitTesting(false)
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
            }
            .contentShape(Rectangle())
            .overlay { columnDividers().allowsHitTesting(false) }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func columnWidth(for prop: PropertyDefinition) -> CGFloat {
        dragWidths[prop.id] ?? viewConfig.columnWidths?[prop.id] ?? 180
    }

    @ViewBuilder
    private var rowsRegion: some View {
        if usesInnerScroll {
            ScrollViewReader { proxy in
                ScrollView {
                    rowsStack
                }
                .onAppear {
                    guard !didInitialScroll else { return }
                    didInitialScroll = true
                    DispatchQueue.main.async {
                        scrollToCurrentTarget(using: proxy, animated: false)
                    }
                }
                .onChange(of: scrollToRowId) { _, _ in
                    DispatchQueue.main.async {
                        scrollToCurrentTarget(using: proxy, animated: true)
                    }
                }
            }
        } else {
            rowsStack
        }
    }

    private var rowsStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .id(topAnchorKey)

            ForEach($rows) { $row in
                dataRow($row)
                    .id($row.wrappedValue.id)
                tableDivider.opacity(0.5)
            }

            ForEach(0..<max(0, 3 - rows.count), id: \.self) { i in
                phantomRow(isFirst: rows.isEmpty && i == 0)
                tableDivider.opacity(0.5)
            }

            if canReorderRows && !rows.isEmpty {
                tailDropTarget
            }
        }
    }

    private func scrollToCurrentTarget(using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            if let scrollToRowId {
                proxy.scrollTo(scrollToRowId, anchor: .top)
            } else {
                proxy.scrollTo(topAnchorKey, anchor: .top)
            }
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                action()
            }
        } else {
            action()
        }
    }

    private var tableDivider: some View {
        Divider()
            .padding(.leading, Self.rowControlsInset + 8)
    }

    private func rowControls(for row: DatabaseRow, isHovered: Bool) -> some View {
        HStack(spacing: rowControlsSpacing) {
            if canReorderRows {
                dragHandle(for: row, isHovered: isHovered)
                    .frame(width: rowHandleWidth, height: 18)
            }

            checkbox(for: row.id, isHovered: isHovered)
                .frame(width: checkboxWidth, height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private func checkbox(for rowId: String, isHovered: Bool) -> some View {
        let isSelected = selectedRowIds.contains(rowId)
        let showCheckbox = isHovered || isSelected || !selectedRowIds.isEmpty

        if showCheckbox {
            Button {
                toggleSelection(for: rowId)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect row" : "Select row")
        } else {
            Color.clear
        }
    }

    private func dragHandle(for row: DatabaseRow, isHovered: Bool) -> some View {
        RowDragHandleDots()
            .foregroundStyle(Color.secondary.opacity(isHovered ? 0.8 : 0.35))
            .help("Drag to reorder row")
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .draggable(row.id) {
                Text(row.title(schema: schema))
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 6))
            }
    }

    private var tailDropTarget: some View {
        Color.clear
            .frame(height: 20)
            .dropDestination(for: String.self) { droppedIds, _ in
                guard let draggedId = droppedIds.first else { return false }
                onReorderRows?(draggedId, nil)
                return true
            }
    }

    private func toggleSelection(for rowId: String) {
        if NSEvent.modifierFlags.contains(.shift),
           let lastId = lastSelectedRowId,
           let lastIdx = rows.firstIndex(where: { $0.id == lastId }),
           let currentIdx = rows.firstIndex(where: { $0.id == rowId }) {
            let lo = min(lastIdx, currentIdx)
            let hi = max(lastIdx, currentIdx)
            for i in lo...hi {
                selectedRowIds.insert(rows[i].id)
            }
            return
        }

        if selectedRowIds.contains(rowId) {
            selectedRowIds.remove(rowId)
        } else {
            selectedRowIds.insert(rowId)
            lastSelectedRowId = rowId
        }
    }

    @ViewBuilder
    private func titleTextField(_ text: Binding<String>) -> some View {
        if wrapCellText {
            TextField("New Page", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: EditorTypography.bodyFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1...4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .cursor(.pointingHand)
        } else {
            TextField("New Page", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: EditorTypography.bodyFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .cursor(.pointingHand)
        }
    }

}

// MARK: - HoverRow (per-row hover state to avoid full-tree re-renders)

private struct HoverRow<Content: View>: View {
    @State private var isHovered = false
    let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isHovered)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct RowDragHandleDots: View {
    var body: some View {
        HStack(spacing: 2) {
            VStack(spacing: 2) {
                dot
                dot
                dot
            }
            VStack(spacing: 2) {
                dot
                dot
                dot
            }
        }
        .frame(width: 10, height: 14)
    }

    private var dot: some View {
        Circle()
            .frame(width: 2, height: 2)
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
        Button {
            editingName = prop.name
            showPopover = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: prop.type.systemImageName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(prop.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .background(isHovered || showPopover ? Color.gray.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            isHovered = inside
            if inside { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
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
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(PropertyType.allCases, id: \.rawValue) { type in
                        if type != prop.type && type != .title {
                            Button {
                                onChangeType?(prop.id, type)
                                showPopover = false
                            } label: {
                                Label(type.rawValue.capitalized, systemImage: type.systemImageName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: prop.type.systemImageName)
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
                    .foregroundStyle(.primary)
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
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 220)
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
