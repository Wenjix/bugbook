import SwiftUI
import BugbookCore

private enum TableViewLayoutMetrics {
    static let compactHeaderHeight: CGFloat = 32
}

struct TableView: View {
    static let rowControlsInset: CGFloat = 44
    private static let reorderCoordinateSpace = "table-reorder"

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
    var onLoadRelationRows: ((PropertyDefinition) -> [RelationRowCandidate])?
    var onListDatabases: (() -> [RelationDatabaseCandidate])?
    var onSetRelationTarget: ((String, String) -> Void)?
    var onResizeColumn: ((String, CGFloat) -> Void)?
    var onReorderRows: ((String, String?) -> Void)?
    var onClearSorts: (() -> Void)?
    var onNewRow: (() -> Void)?
    var scrollToRowId: String? = nil
    var showVerticalLines: Bool = true
    var usesInnerScroll: Bool = true
    var containerWidth: CGFloat? = nil

    @State private var dragWidths: [String: CGFloat] = [:]
    @State private var hoveredResizeKey: String?
    @State private var draggingResizeKey: String?
    @State private var dragStartWidths: [String: CGFloat] = [:]
    @State private var dragStartX: [String: CGFloat] = [:]
    @State private var selectedRowIds: Set<String> = []
    @State private var lastSelectedRowId: String? = nil
    @State private var didInitialScroll = false
    @State private var displayedRowCount: Int = 20
    @State private var draggingRowId: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var reorderTarget: TableReorderTarget?
    @State private var hoveredEmptyRow: Int?
    @State private var focusedCellId: String?

    private let titleColumnKey = "__title__"
    private let topAnchorKey = "__table_top__"
    private let rowHandleWidth: CGFloat = DatabaseZoomMetrics.size(12)
    private let checkboxWidth: CGFloat = DatabaseZoomMetrics.size(14)
    private let rowControlsSpacing: CGFloat = DatabaseZoomMetrics.size(2)
    private var scaledRowControlsInset: CGFloat { DatabaseZoomMetrics.size(Self.rowControlsInset) }

    private var visibleProperties: [PropertyDefinition] {
        let hidden = Set(viewConfig.hiddenColumns ?? [])
        return schema.properties.filter { $0.type != .title && !hidden.contains($0.id) }
    }

    private var titleColumnWidth: CGFloat {
        dragWidths[titleColumnKey] ?? viewConfig.columnWidths?[titleColumnKey] ?? DatabaseZoomMetrics.size(240)
    }

    private var wrapCellText: Bool {
        viewConfig.wrapCellText ?? false
    }

    /// Minimum width the table content needs (columns + controls + padding).
    private var contentMinWidth: CGFloat {
        let columnsWidth = titleColumnWidth + visibleProperties.reduce(0) { $0 + columnWidth(for: $1) }
        // row controls + horizontal padding on row HStack + approx "Add property" button
        let extras = scaledRowControlsInset + DatabaseZoomMetrics.size(8) + DatabaseZoomMetrics.size(120)
        return columnsWidth + extras
    }

    /// The effective minimum width: at least as wide as column content OR the container.
    private var effectiveMinWidth: CGFloat {
        max(contentMinWidth, containerWidth ?? 0)
    }

    private var canReorderRows: Bool {
        viewConfig.sorts.isEmpty
    }

    private var compactHeaderHeight: CGFloat {
        DatabaseZoomMetrics.size(TableViewLayoutMetrics.compactHeaderHeight)
    }

    private var draggingRow: DatabaseRow? {
        guard let draggingRowId else { return nil }
        return rows.first(where: { $0.id == draggingRowId })
    }

    private var visibleRowIds: [String] {
        Array(rows.prefix(min(displayedRowCount, rows.count)).map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with selection bar overlay
            headerRow
                .overlay(alignment: .leading) {
                    if !selectedRowIds.isEmpty {
                        selectionBar
                    }
                }
            tableDivider

            rowsRegion
        }
        .overlay {
            if let draggingRow {
                dragPreview(for: draggingRow)
                    .position(dragLocation)
                    .allowsHitTesting(false)
            }
        }
        .frame(
            minWidth: effectiveMinWidth,
            maxWidth: .infinity,
            maxHeight: usesInnerScroll ? .infinity : nil,
            alignment: .topLeading
        )
        .fixedSize(horizontal: !usesInnerScroll, vertical: !usesInnerScroll)
        .databasePointerCursor()
        .coordinateSpace(name: Self.reorderCoordinateSpace)
        .onPreferenceChange(TableRowFramePreferenceKey.self) { newFrames in
            // Only update during active row drag to avoid re-render loop on scroll
            if draggingRowId != nil { rowFrames = newFrames }
        }
    }

    // MARK: - Selection Bar

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button {
                selectedRowIds.removeAll()
            } label: {
                Text("\(selectedRowIds.count) selected")
                    .font(DatabaseZoomMetrics.font(13))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Button {
                let toDelete = rows.filter { selectedRowIds.contains($0.id) }
                selectedRowIds.removeAll()
                toDelete.forEach { onDelete?($0) }
            } label: {
                Image(systemName: "trash")
                    .font(DatabaseZoomMetrics.font(13))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DatabaseZoomMetrics.size(10))
        .padding(.vertical, DatabaseZoomMetrics.size(4))
        .background(
            RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(6))
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(6))
                        .stroke(Color.fallbackBorderColor.opacity(0.9), lineWidth: 1)
                )
        )
        .padding(.leading, scaledRowControlsInset + DatabaseZoomMetrics.size(4))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Leading spacer matching row controls width
            Color.clear.frame(width: scaledRowControlsInset, height: 1)

            // Title column header
            TitleColumnHeaderCell(
                name: schema.titleProperty?.name ?? "Name",
                propertyId: schema.titleProperty?.id,
                height: compactHeaderHeight,
                onRename: onRenameProperty
            )
            .frame(width: titleColumnWidth)
            .overlay(alignment: .trailing) {
                resizeHandle(key: titleColumnKey, baseWidth: viewConfig.columnWidths?[titleColumnKey] ?? 240)
            }

            // Property column headers
            ForEach(visibleProperties) { prop in
                ColumnHeaderCell(
                    prop: prop,
                    height: compactHeaderHeight,
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
                        .font(DatabaseZoomMetrics.font(11))
                    Text("Add property")
                        .font(DatabaseZoomMetrics.font(13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, DatabaseZoomMetrics.size(8))
                .padding(.vertical, DatabaseZoomMetrics.size(4))
                .frame(height: compactHeaderHeight)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, DatabaseZoomMetrics.size(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: compactHeaderHeight)
        .overlay(alignment: .leading) {
            if !selectedRowIds.isEmpty {
                headerCheckbox
                    .offset(x: -scaledRowControlsInset + rowHandleWidth + rowControlsSpacing)
            }
        }
    }

    @ViewBuilder
    private var headerCheckbox: some View {
        let visibleCount = min(displayedRowCount, rows.count)
        let allSelected = !rows.isEmpty && selectedRowIds.count == visibleCount
        let someSelected = !selectedRowIds.isEmpty && !allSelected

        Button {
            if allSelected {
                selectedRowIds.removeAll()
            } else {
                selectedRowIds = Set(rows.prefix(visibleCount).map(\.id))
            }
        } label: {
            Image(systemName: allSelected ? "checkmark.square.fill" : someSelected ? "minus.square.fill" : "square")
                .font(DatabaseZoomMetrics.font(13))
                .foregroundStyle(allSelected || someSelected ? Color.dragIndicator : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Resize Handle (overlaid on column trailing edge)

    private func resizeHandle(key: String, baseWidth: Double) -> some View {
        let isActive = hoveredResizeKey == key || draggingResizeKey == key
        let hitWidth = DatabaseZoomMetrics.size(24)
        return Color.clear
            .frame(width: hitWidth)
            .overlay {
                Rectangle()
                    .fill(isActive ? Color.dragIndicator : Color.clear)
                    .frame(width: isActive ? 2 : 1)
                    .padding(.vertical, -8)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if draggingResizeKey == nil {
                    hoveredResizeKey = inside ? key : nil
                    if inside { NSCursor.resizeLeftRight.push() }
                    else { NSCursor.pop() }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if draggingResizeKey != key {
                            draggingResizeKey = key
                            dragStartWidths[key] = dragWidths[key] ?? CGFloat(baseWidth)
                            dragStartX[key] = value.startLocation.x
                            NSCursor.resizeLeftRight.push()
                        }
                        let startWidth = dragStartWidths[key] ?? CGFloat(baseWidth)
                        let startX = dragStartX[key] ?? value.startLocation.x
                        let delta = value.location.x - startX
                        dragWidths[key] = max(DatabaseZoomMetrics.size(80), startWidth + delta)
                    }
                    .onEnded { _ in
                        if let finalWidth = dragWidths[key] {
                            onResizeColumn?(key, finalWidth)
                        }
                        dragStartWidths.removeValue(forKey: key)
                        dragStartX.removeValue(forKey: key)
                        draggingResizeKey = nil
                        hoveredResizeKey = nil
                        NSCursor.pop()
                    }
            )
            .offset(x: hitWidth / 2)
            .zIndex(10)
    }

    // MARK: - Data Row

    private func dataRow(_ row: Binding<DatabaseRow>) -> some View {
        let isSelected = selectedRowIds.contains(row.wrappedValue.id)
        return HoverRow { isHovered in
            HStack(alignment: .center, spacing: 0) {
                // Controls in gutter — no hover background
                rowControls(for: row.wrappedValue, isHovered: isHovered)
                    .frame(width: scaledRowControlsInset, alignment: .center)

                // Content cells — hover/selection background only here
                HStack(alignment: .center, spacing: 0) {
                    let titleCellId = "\(row.wrappedValue.id)__title"
                    titleCell(row, isHovered: isHovered)
                        .padding(.horizontal, DatabaseZoomMetrics.size(8))
                        .frame(width: titleColumnWidth, alignment: .leading)
                        .background(focusedCellId == titleCellId ? Color.accentColor.opacity(0.06) : Color.clear)
                        .contentShape(Rectangle())
                        .databasePointerCursor()
                        .simultaneousGesture(TapGesture().onEnded { focusedCellId = titleCellId })

                    ForEach(visibleProperties) { prop in
                        let cellId = "\(row.wrappedValue.id)_\(prop.id)"
                        PropertyEditorView(
                            definition: prop,
                            value: propertyBinding(row: row, propertyId: prop.id),
                            wrapText: wrapCellText,
                            compact: true,
                            onAddOption: onAddSelectOption,
                            onUpdateOption: onUpdateSelectOption,
                            onDeleteOption: onDeleteSelectOption,
                            onLoadRelationRows: prop.type == .relation ? { onLoadRelationRows?(prop) ?? [] } : nil,
                            onListDatabases: prop.type == .relation ? { onListDatabases?() ?? [] } : nil,
                            onSetRelationTarget: prop.type == .relation ? onSetRelationTarget : nil
                        )
                        .padding(.horizontal, DatabaseZoomMetrics.size(8))
                        .frame(width: columnWidth(for: prop), alignment: .leading)
                        .background(focusedCellId == cellId ? Color.accentColor.opacity(0.06) : Color.clear)
                        .contentShape(Rectangle())
                        .databasePointerCursor()
                        .simultaneousGesture(TapGesture().onEnded { focusedCellId = cellId })
                    }
                }
                .frame(height: compactHeaderHeight)
                .padding(.horizontal, DatabaseZoomMetrics.size(4))
                .background(
                    RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(4))
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.08)
                                : isHovered ? Color.primary.opacity(0.04) : Color.clear
                        )
                )
                .overlay { columnDividers().allowsHitTesting(false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if draggingRowId != nil,
                   showsInsertionIndicator(for: row.wrappedValue.id, placement: .before) {
                    insertionIndicator
                }
            }
            .overlay(alignment: .bottomLeading) {
                if draggingRowId != nil,
                   showsInsertionIndicator(for: row.wrappedValue.id, placement: .after) {
                    insertionIndicator
                }
            }
            .background {
                if draggingRowId != nil {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TableRowFramePreferenceKey.self,
                            value: [row.wrappedValue.id: proxy.frame(in: .named(Self.reorderCoordinateSpace))]
                        )
                    }
                }
            }
        }
    }

    // MARK: - Column Dividers (row-level overlay)

    /// Pre-compute divider x-offsets so each row draws a single Canvas instead of N+1 view pairs.
    private var columnDividerOffsets: [CGFloat] {
        guard showVerticalLines else { return [] }
        var offsets: [CGFloat] = []
        var x = DatabaseZoomMetrics.size(4) + titleColumnWidth
        offsets.append(x)
        for prop in visibleProperties {
            x += columnWidth(for: prop)
            offsets.append(x)
        }
        return offsets
    }

    @ViewBuilder
    private func columnDividers() -> some View {
        if showVerticalLines {
            let offsets = columnDividerOffsets
            Canvas { context, size in
                for x in offsets {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                        with: .color(.gray.opacity(0.15))
                    )
                }
            }
        }
    }

    // MARK: - Title Cell

    private func titleCell(_ row: Binding<DatabaseRow>, isHovered: Bool) -> some View {
        let openPillSize = CGSize(width: DatabaseZoomMetrics.size(60), height: DatabaseZoomMetrics.size(20))
        let titleBinding = titleBinding(row: row)

        return titleTextField(titleBinding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .databasePointerCursor()
            .overlay(alignment: .trailing) {
                if isHovered {
                    Button {
                        onOpenRow(row.wrappedValue)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sidebar.right")
                                .font(DatabaseZoomMetrics.font(9, weight: .semibold))
                            Text("OPEN")
                                .font(DatabaseZoomMetrics.font(10, weight: .semibold))
                                .tracking(0.3)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: openPillSize.width, height: openPillSize.height)
                        .background(
                            RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(7))
                                .fill(Color.fallbackBgSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(7))
                                        .stroke(Color.fallbackBorderColor.opacity(0.9), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(NoFeedbackButtonStyle())
                    .fixedSize()
                    .help("Open in side peek")
                    .padding(.trailing, DatabaseZoomMetrics.size(4))
                }
            }
    }

    // MARK: - Filler Row & New Page Button

    private var fillerRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: scaledRowControlsInset + titleColumnWidth)
            ForEach(visibleProperties) { prop in
                Color.clear.frame(width: columnWidth(for: prop))
            }
        }
        .padding(.horizontal, DatabaseZoomMetrics.size(4))
        .frame(height: compactHeaderHeight)
        .overlay { columnDividers().allowsHitTesting(false) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyTableRow(index: Int) -> some View {
        let isHovered = hoveredEmptyRow == index
        // Show "+ New page" on the hovered row, or on row 0 if nothing is hovered
        let showLabel = isHovered || (hoveredEmptyRow == nil && index == 0)

        return Button { onNewRow?() } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: scaledRowControlsInset, height: 1)
                HStack(spacing: DatabaseZoomMetrics.size(4)) {
                    if showLabel {
                        Image(systemName: "plus")
                            .font(DatabaseZoomMetrics.font(11))
                            .foregroundStyle(Color.primary.opacity(0.25))
                        Text("New page")
                            .font(DatabaseZoomMetrics.font(13))
                            .foregroundStyle(Color.primary.opacity(0.25))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DatabaseZoomMetrics.size(8))
                .frame(width: titleColumnWidth, alignment: .leading)

                ForEach(visibleProperties) { prop in
                    Color.clear.frame(width: columnWidth(for: prop))
                }
            }
            .padding(.horizontal, DatabaseZoomMetrics.size(4))
            .frame(height: compactHeaderHeight)
            .overlay { columnDividers().allowsHitTesting(false) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredEmptyRow = inside ? index : nil
        }
    }

    private var newPageButton: some View {
        Button { onNewRow?() } label: {
            HStack(spacing: DatabaseZoomMetrics.size(4)) {
                Image(systemName: "plus")
                    .font(DatabaseZoomMetrics.font(11))
                Text("New page")
                    .font(DatabaseZoomMetrics.font(13))
            }
            .foregroundStyle(Color.primary.opacity(0.25))
            .padding(.leading, scaledRowControlsInset + DatabaseZoomMetrics.size(8))
            .padding(.trailing, DatabaseZoomMetrics.size(8))
            .padding(.vertical, DatabaseZoomMetrics.size(6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func columnWidth(for prop: PropertyDefinition) -> CGFloat {
        dragWidths[prop.id] ?? viewConfig.columnWidths?[prop.id] ?? DatabaseZoomMetrics.size(180)
    }

    private func propertyBinding(row: Binding<DatabaseRow>, propertyId: String) -> Binding<PropertyValue> {
        Binding(
            get: { row.wrappedValue.properties[propertyId] ?? .empty },
            set: { newVal in
                var updatedRow = row.wrappedValue
                updatedRow.properties[propertyId] = newVal
                row.wrappedValue = updatedRow
                onSave(updatedRow)
            }
        )
    }

    private func titleBinding(row: Binding<DatabaseRow>) -> Binding<String> {
        let titlePropId = schema.titleProperty?.id
        return Binding(
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
    }

    @ViewBuilder
    private var rowsRegion: some View {
        if usesInnerScroll {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        rowsStack
                            .frame(minWidth: geo.size.width)
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
            }
        } else {
            rowsStack
        }
    }

    private var rowsStack: some View {
        let totalCount = rows.count
        let visibleCount = min(displayedRowCount, totalCount)

        return LazyVStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .id(topAnchorKey)

            ForEach($rows.prefix(visibleCount)) { $row in
                dataRow($row)
                    .id($row.wrappedValue.id)
                tableDivider.opacity(0.5)
            }

            if visibleCount < totalCount {
                Button {
                    displayedRowCount += 20
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(DatabaseZoomMetrics.font(11))
                        Text("Load more (\(totalCount - visibleCount) remaining)")
                            .font(DatabaseZoomMetrics.font(15))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DatabaseZoomMetrics.size(10))
                }
                .buttonStyle(.plain)
            }

            if rows.isEmpty {
                // All empty rows are clickable; "+ New page" follows hover
                emptyTableRow(index: 0)
                tableDivider.opacity(0.5)
                emptyTableRow(index: 1)
                tableDivider.opacity(0.5)
                emptyTableRow(index: 2)
                tableDivider.opacity(0.5)
            } else {
                // When data exists, simple button below
                newPageButton
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
            .padding(.leading, scaledRowControlsInset + DatabaseZoomMetrics.size(4))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowControls(for row: DatabaseRow, isHovered: Bool) -> some View {
        HStack(spacing: rowControlsSpacing) {
            dragHandle(for: row, isHovered: isHovered)

            checkbox(for: row.id, isHovered: isHovered)
                .frame(width: checkboxWidth, height: DatabaseZoomMetrics.size(18))
        }
        .padding(.trailing, DatabaseZoomMetrics.size(4))
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
                    .font(DatabaseZoomMetrics.font(13))
                    .foregroundStyle(isSelected ? Color.dragIndicator : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect row" : "Select row")
        } else {
            Color.clear
        }
    }

    private func dragHandle(for row: DatabaseRow, isHovered: Bool) -> some View {
        let isVisible = isHovered || selectedRowIds.contains(row.id) || draggingRowId == row.id

        return RowDragHandleDots()
            .opacity(isVisible ? 1 : 0)
            .contentShape(Rectangle())
            .allowsHitTesting(isVisible)
            .help(canReorderRows ? "Drag to reorder row" : "Drag to reorder (will clear sort)")
            .appCursor(draggingRowId == row.id ? .closedHand : .openHand)
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.reorderCoordinateSpace))
                    .onChanged { value in
                        beginRowDrag(row, at: value.location)
                    }
                    .onEnded { value in
                        endRowDrag(for: row, at: value.location)
                    }
            )
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
                .font(DatabaseZoomMetrics.font(14))
                .foregroundStyle(.primary)
                .lineLimit(1...4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        } else {
            TextField("New Page", text: text)
                .textFieldStyle(.plain)
                .font(DatabaseZoomMetrics.font(14))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
    }

    private var insertionIndicator: some View {
        Rectangle()
            .fill(Color.dragIndicator)
            .frame(height: 2)
    }

    private func showsInsertionIndicator(for rowId: String, placement: TableReorderPlacement) -> Bool {
        reorderTarget?.rowId == rowId && reorderTarget?.placement == placement
    }

    private func dragPreview(for row: DatabaseRow) -> some View {
        Text(row.title(schema: schema).isEmpty ? "Untitled" : row.title(schema: schema))
            .font(DatabaseZoomMetrics.font(15))
            .lineLimit(1)
            .padding(.horizontal, DatabaseZoomMetrics.size(8))
            .padding(.vertical, DatabaseZoomMetrics.size(6))
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(6)))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private func beginRowDrag(_ row: DatabaseRow, at location: CGPoint) {
        if draggingRowId == nil {
            draggingRowId = row.id
            if !canReorderRows {
                onClearSorts?()
            }
        }
        dragLocation = location
        reorderTarget = reorderTarget(for: location)
    }

    private func endRowDrag(for row: DatabaseRow, at location: CGPoint) {
        dragLocation = location
        let target = reorderTarget(for: location)
        draggingRowId = nil
        reorderTarget = nil

        guard let target else { return }
        guard !(target.rowId == row.id && target.placement == .before) else { return }

        let beforeId = insertionTargetId(for: row.id, target: target)
        onReorderRows?(row.id, beforeId)
    }

    private func reorderTarget(for location: CGPoint) -> TableReorderTarget? {
        let candidateIds = visibleRowIds
        guard let firstId = candidateIds.first,
              let lastId = candidateIds.last else { return nil }

        for rowId in candidateIds {
            guard let frame = rowFrames[rowId] else { continue }
            if location.y < frame.minY {
                return TableReorderTarget(rowId: rowId, placement: .before)
            }
            if location.y <= frame.maxY {
                let placement: TableReorderPlacement = location.y < frame.midY ? .before : .after
                return TableReorderTarget(rowId: rowId, placement: placement)
            }
        }

        if let firstFrame = rowFrames[firstId], location.y < firstFrame.minY {
            return TableReorderTarget(rowId: firstId, placement: .before)
        }
        if let lastFrame = rowFrames[lastId], location.y >= lastFrame.maxY {
            return TableReorderTarget(rowId: lastId, placement: .after)
        }
        return nil
    }

    private func insertionTargetId(for draggedId: String, target: TableReorderTarget) -> String? {
        switch target.placement {
        case .before:
            return target.rowId
        case .after:
            return nextRowId(after: target.rowId)
        }
    }

    private func nextRowId(after rowId: String) -> String? {
        guard let index = rows.firstIndex(where: { $0.id == rowId }),
              rows.indices.contains(index + 1) else { return nil }
        return rows[index + 1].id
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
        GripDotsView()
    }
}

private enum TableReorderPlacement {
    case before
    case after
}

private struct TableReorderTarget {
    let rowId: String
    let placement: TableReorderPlacement
}

private struct TableRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Column Header Cell (own View for independent popover)

private struct ColumnHeaderCell: View {
    let prop: PropertyDefinition
    let height: CGFloat
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
                    .font(DatabaseZoomMetrics.font(11))
                    .foregroundStyle(.secondary)
                Text(prop.name)
                    .font(DatabaseZoomMetrics.font(13))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DatabaseZoomMetrics.size(8))
            .padding(.vertical, DatabaseZoomMetrics.size(6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .background(isHovered || showPopover ? Color.gray.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
        }
        .floatingPopover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Property name", text: $editingName)
                .textFieldStyle(.roundedBorder)
                .font(DatabaseZoomMetrics.font(13))
                .focusEffectDisabled()
                .onSubmit {
                    let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && trimmed != prop.name {
                        onRename?(prop.id, trimmed)
                    }
                    showPopover = false
                }

            HStack {
                Text("Type")
                    .font(DatabaseZoomMetrics.font(12))
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
                            .font(DatabaseZoomMetrics.font(12))
                        Text(prop.type.rawValue.capitalized)
                            .font(DatabaseZoomMetrics.font(15))
                    }
                    .foregroundStyle(.primary)
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
                            .font(DatabaseZoomMetrics.font(12))
                        Text("Hide property")
                            .font(DatabaseZoomMetrics.font(15))
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
                        .font(DatabaseZoomMetrics.font(12))
                    Text("Delete property")
                        .font(DatabaseZoomMetrics.font(15))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(DatabaseZoomMetrics.size(12))
        .frame(width: DatabaseZoomMetrics.size(220))
        .popoverSurface()
    }

}

// MARK: - Title Column Header Cell

private struct TitleColumnHeaderCell: View {
    let name: String
    let propertyId: String?
    let height: CGFloat
    var onRename: ((String, String) -> Void)?

    @State private var isHovered = false
    @State private var showPopover = false
    @State private var editingName: String = ""

    var body: some View {
        Button {
            editingName = name
            showPopover = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "textformat")
                    .font(DatabaseZoomMetrics.font(11))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(DatabaseZoomMetrics.font(13))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DatabaseZoomMetrics.size(8))
            .padding(.vertical, DatabaseZoomMetrics.size(6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .background(isHovered || showPopover ? Color.gray.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .floatingPopover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Column name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .font(DatabaseZoomMetrics.font(13))
                    .focusEffectDisabled()
                    .onSubmit {
                        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && trimmed != name, let propId = propertyId {
                            onRename?(propId, trimmed)
                        }
                        showPopover = false
                    }

                HStack {
                    Text("Type")
                        .font(DatabaseZoomMetrics.font(12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "textformat")
                            .font(DatabaseZoomMetrics.font(12))
                        Text("Title")
                            .font(DatabaseZoomMetrics.font(15))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(DatabaseZoomMetrics.size(12))
            .frame(width: DatabaseZoomMetrics.size(220))
            .popoverSurface()
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

private struct NoFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
