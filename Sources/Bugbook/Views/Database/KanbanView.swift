import SwiftUI
import BugbookCore

struct KanbanView: View {
    private static let coordinateSpaceName = "kanban"

    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void
    var onUpdateGroupBy: ((String) -> Void)?
    var onUpdateSubGroupBy: ((String?) -> Void)?
    var onAddSelectOption: ((String, SelectOption) -> Void)?
    var onDelete: ((DatabaseRow) -> Void)?
    var onReorderRows: ((String, String?) -> Void)?
    var onClearSorts: (() -> Void)?
    var onRenameSelectOption: ((String, String, String) -> Void)?
    var onDeleteSelectOption: ((String, String) -> Void)?
    var onHideColumn: ((String, String) -> Void)?

    @State private var newOptionName: String = ""
    @State private var addingOptionForColumn: Bool = false
    @State private var showColumnPopover: String? = nil
    @State private var showCardPopover: String? = nil
    @State private var editingColumnName: String = ""
    @State private var collapsedSubGroups: Set<String> = []

    // Custom drag state
    @State private var draggingRowId: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var dragTargetColumn: String? = nil
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var reorderTarget: KanbanReorderTarget?

    private var selectProperties: [PropertyDefinition] {
        schema.properties.filter { $0.type == .select }
    }

    /// Properties eligible for sub-grouping: select and relation types, excluding the primary group-by.
    private var subGroupableProperties: [PropertyDefinition] {
        schema.properties.filter { prop in
            (prop.type == .select || prop.type == .relation) && prop.id != groupProperty?.id
        }
    }

    private var groupProperty: PropertyDefinition? {
        guard let groupId = viewConfig.groupBy else {
            return schema.properties.first(where: { $0.type == .select })
        }
        return schema.properties.first(where: { $0.id == groupId })
    }

    private var subGroupProperty: PropertyDefinition? {
        guard let subGroupId = viewConfig.subGroupBy else { return nil }
        return schema.properties.first(where: { $0.id == subGroupId })
    }

    private var columns: [(id: String, name: String, color: String)] {
        guard let prop = groupProperty else { return [] }
        var cols: [(id: String, name: String, color: String)] = [("__none__", "No \(prop.name)", "gray")]
        if let options = prop.options {
            cols += options.map { ($0.id, $0.name, $0.color) }
        }
        // Hide columns excluded by filters on the group property
        let groupFilters = viewConfig.filters.filter { $0.property == prop.id }
        for filter in groupFilters {
            switch filter.op {
            case "equals":
                cols = cols.filter { $0.id == filter.value || $0.id == "__none__" }
            case "not_equals":
                cols = cols.filter { $0.id != filter.value }
            case "is_empty":
                cols = [("__none__", "No \(prop.name)", "gray")]
            case "is_not_empty":
                cols = cols.filter { $0.id != "__none__" }
            default:
                break
            }
        }
        return cols
    }

    private var columnWidth: CGFloat { DatabaseZoomMetrics.size(250) }
    private var addOptionColumnWidth: CGFloat { DatabaseZoomMetrics.size(200) }
    private var cardCornerRadius: CGFloat { DatabaseZoomMetrics.size(6) }

    private func rowsForColumn(_ columnId: String) -> [DatabaseRow] {
        guard let prop = groupProperty else { return rows }
        return rows.filter { row in
            guard let val = row.properties[prop.id] else { return columnId == "__none__" }
            if case .select(let s) = val {
                return s == columnId
            }
            return columnId == "__none__"
        }
    }

    // MARK: - Sub-Grouping

    /// Extract the sub-group key from a row's property value for the sub-group property.
    private func subGroupKey(for row: DatabaseRow) -> String {
        guard let prop = subGroupProperty,
              let val = row.properties[prop.id] else { return "__none__" }
        switch val {
        case .select(let s): return s.isEmpty ? "__none__" : s
        case .relation(let s): return s.isEmpty ? "__none__" : s
        case .empty: return "__none__"
        default: return "__none__"
        }
    }

    /// Display name for a sub-group key value.
    private func subGroupDisplayName(for key: String) -> String {
        guard let prop = subGroupProperty else { return key }
        if key == "__none__" { return "No \(prop.name)" }
        if prop.type == .select, let options = prop.options {
            return options.first(where: { $0.id == key })?.name ?? key
        }
        // For relations, the key is a row id — just show it as-is
        return key
    }

    /// Partition column rows into ordered sub-groups. "__none__" group is placed last.
    private func subGroups(for columnRows: [DatabaseRow]) -> [(key: String, name: String, rows: [DatabaseRow])] {
        guard subGroupProperty != nil else { return [] }

        var grouped: [String: [DatabaseRow]] = [:]
        var keyOrder: [String] = []
        for row in columnRows {
            let key = subGroupKey(for: row)
            if grouped[key] == nil { keyOrder.append(key) }
            grouped[key, default: []].append(row)
        }

        // Move "__none__" to end
        if let noneIdx = keyOrder.firstIndex(of: "__none__") {
            keyOrder.remove(at: noneIdx)
            keyOrder.append("__none__")
        }

        return keyOrder.map { key in
            (key: key, name: subGroupDisplayName(for: key), rows: grouped[key] ?? [])
        }
    }

    /// Unique key for tracking collapsed state of a sub-group within a column.
    private func subGroupCollapseKey(column: String, subGroup: String) -> String {
        "\(column)::\(subGroup)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // GroupBy / Sub-group by selectors
            if selectProperties.count > 1 || !subGroupableProperties.isEmpty {
                HStack(spacing: 8) {
                    if selectProperties.count > 1 {
                        Text("Group by:")
                            .font(DatabaseZoomMetrics.font(12))
                            .foregroundStyle(.secondary)
                        Menu {
                            ForEach(selectProperties) { prop in
                                Button {
                                    onUpdateGroupBy?(prop.id)
                                } label: {
                                    HStack {
                                        Text(prop.name)
                                        if prop.id == groupProperty?.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(groupProperty?.name ?? "Select property")
                                    .font(DatabaseZoomMetrics.font(12))
                                Image(systemName: "chevron.down")
                                    .font(DatabaseZoomMetrics.font(11))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    if !subGroupableProperties.isEmpty {
                        Text("Sub-group by:")
                            .font(DatabaseZoomMetrics.font(12))
                            .foregroundStyle(.secondary)
                        Menu {
                            Button {
                                onUpdateSubGroupBy?(nil)
                            } label: {
                                HStack {
                                    Text("None")
                                    if viewConfig.subGroupBy == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            ForEach(subGroupableProperties) { prop in
                                Button {
                                    onUpdateSubGroupBy?(prop.id)
                                } label: {
                                    HStack {
                                        Text(prop.name)
                                        if prop.id == viewConfig.subGroupBy {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(subGroupProperty?.name ?? "None")
                                    .font(DatabaseZoomMetrics.font(12))
                                Image(systemName: "chevron.down")
                                    .font(DatabaseZoomMetrics.font(11))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Spacer()
                }
                .padding(.horizontal, DatabaseZoomMetrics.size(12))
                .padding(.vertical, DatabaseZoomMetrics.size(6))
            }

            GeometryReader { geo in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: DatabaseZoomMetrics.size(12)) {
                        ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                            kanbanColumn(column, index: index, availableHeight: geo.size.height - 24)
                        }

                        // Add new option column
                        if groupProperty != nil {
                            addOptionColumn
                        }
                    }
                    .padding(DatabaseZoomMetrics.size(12))
                    .coordinateSpace(name: Self.coordinateSpaceName)
                    .onPreferenceChange(KanbanCardFramePreferenceKey.self) { cardFrames = $0 }
                    .overlay {
                        if let dragId = draggingRowId,
                           let row = rows.first(where: { $0.id == dragId }) {
                            let title = row.title(schema: schema)
                            dragPreview(title)
                                .position(dragLocation)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Drag Preview

    private func dragPreview(_ title: String) -> some View {
        Text(title.isEmpty ? "Untitled" : title)
            .font(DatabaseZoomMetrics.font(17))
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, DatabaseZoomMetrics.size(12))
            .padding(.vertical, DatabaseZoomMetrics.size(8))
            .frame(width: DatabaseZoomMetrics.size(220))
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: cardCornerRadius))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Add Option Column

    private var addOptionColumn: some View {
        VStack(spacing: 8) {
            if addingOptionForColumn {
                VStack(spacing: 6) {
                    TextField("Option name", text: $newOptionName, onCommit: {
                        createNewOption()
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(DatabaseZoomMetrics.font(12))

                    HStack(spacing: 6) {
                        Button("Add") { createNewOption() }
                            .font(DatabaseZoomMetrics.font(12))
                            .disabled(newOptionName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Cancel") {
                            newOptionName = ""
                            addingOptionForColumn = false
                        }
                        .font(DatabaseZoomMetrics.font(12))
                    }
                }
                .padding(DatabaseZoomMetrics.size(8))
            } else {
                Button {
                    addingOptionForColumn = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Status")
                    }
                    .font(DatabaseZoomMetrics.font(12))
                    .foregroundStyle(.secondary)
                    .padding(DatabaseZoomMetrics.size(8))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: addOptionColumnWidth)
        .padding(.vertical, DatabaseZoomMetrics.size(8))
        .background(Color.fallbackSurfaceSubtle)
        .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(8)))
    }

    private func createNewOption() {
        let name = newOptionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let prop = groupProperty else { return }
        let colors = ["blue", "green", "yellow", "purple", "pink", "orange", "teal", "gray"]
        let randomColor = colors.randomElement() ?? "blue"
        let option = SelectOption(id: "opt_\(UUID().uuidString)", name: name, color: randomColor)
        onAddSelectOption?(prop.id, option)
        newOptionName = ""
        addingOptionForColumn = false
    }

    private func openColumnPopover(for column: (id: String, name: String, color: String)) {
        guard column.id != "__none__" else { return }
        editingColumnName = column.name
        showColumnPopover = column.id
    }

    private func columnPopoverBinding(for columnId: String) -> Binding<Bool> {
        guard columnId != "__none__" else { return .constant(false) }
        return Binding(
            get: { showColumnPopover == columnId },
            set: { isPresented in
                if !isPresented && showColumnPopover == columnId {
                    showColumnPopover = nil
                }
            }
        )
    }

    private func commitColumnRename(for column: (id: String, name: String, color: String)) {
        let trimmed = editingColumnName.trimmingCharacters(in: .whitespaces)
        if let prop = groupProperty, !trimmed.isEmpty, trimmed != column.name {
            onRenameSelectOption?(prop.id, column.id, trimmed)
        }
        showColumnPopover = nil
    }

    private func hideColumn(_ columnId: String) {
        guard let prop = groupProperty else { return }
        showColumnPopover = nil
        // Defer so the popover dismisses before the column is removed from the view
        DispatchQueue.main.async {
            onHideColumn?(prop.id, columnId)
        }
    }

    private func deleteColumn(_ columnId: String) {
        guard let prop = groupProperty else { return }
        showColumnPopover = nil
        DispatchQueue.main.async {
            onDeleteSelectOption?(prop.id, columnId)
        }
    }

    @ViewBuilder
    private func columnNameLabel(_ column: (id: String, name: String, color: String), color: Color) -> some View {
        Text(column.name)
            .font(DatabaseZoomMetrics.font(12))
            .fontWeight(.semibold)
            .padding(.horizontal, DatabaseZoomMetrics.size(8))
            .padding(.vertical, DatabaseZoomMetrics.size(3))
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
    }

    @ViewBuilder
    private func columnHeaderNameView(_ column: (id: String, name: String, color: String), color: Color) -> some View {
        if column.id == "__none__" {
            columnNameLabel(column, color: color)
        } else {
            Button {
                openColumnPopover(for: column)
            } label: {
                columnNameLabel(column, color: color)
            }
            .buttonStyle(.plain)
        }
    }

    private func columnPopoverContent(for column: (id: String, name: String, color: String)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Option name", text: $editingColumnName)
                .textFieldStyle(.roundedBorder)
                .font(DatabaseZoomMetrics.font(15))
                .focusEffectDisabled()
                .onSubmit {
                    commitColumnRename(for: column)
                }
                .padding(.horizontal, DatabaseZoomMetrics.size(10))
                .padding(.top, DatabaseZoomMetrics.size(8))
                .padding(.bottom, DatabaseZoomMetrics.size(4))

            popoverButton(icon: "eye.slash", label: "Hide option") {
                hideColumn(column.id)
            }

            popoverDivider

            popoverButton(icon: "trash", label: "Delete option", isDestructive: true) {
                deleteColumn(column.id)
            }
        }
        .frame(width: DatabaseZoomMetrics.size(220))
        .padding(.vertical, DatabaseZoomMetrics.size(4))
        .popoverSurface()
    }

    // MARK: - Popover Helpers

    private func popoverButton(
        icon: String, label: String,
        isDestructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        KanbanPopoverButton(icon: icon, label: label, isDestructive: isDestructive, action: action)
    }

    private var popoverDivider: some View {
        Divider()
            .padding(.vertical, DatabaseZoomMetrics.size(4))
            .padding(.horizontal, DatabaseZoomMetrics.size(10))
    }

    private func cardPopoverBinding(for rowId: String) -> Binding<Bool> {
        Binding(
            get: { showCardPopover == rowId },
            set: { isPresented in
                if !isPresented && showCardPopover == rowId {
                    showCardPopover = nil
                }
            }
        )
    }

    private func openCard(_ row: DatabaseRow) {
        showCardPopover = nil
        onOpenRow(row)
    }

    private func deleteCard(_ row: DatabaseRow) {
        showCardPopover = nil
        DispatchQueue.main.async {
            onDelete?(row)
        }
    }

    private func cardPopoverContent(for row: DatabaseRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverButton(icon: "arrow.up.right", label: "Open") {
                openCard(row)
            }

            popoverDivider

            popoverButton(icon: "trash", label: "Delete", isDestructive: true) {
                deleteCard(row)
            }
        }
        .frame(width: DatabaseZoomMetrics.size(200))
        .padding(.vertical, DatabaseZoomMetrics.size(4))
        .popoverSurface()
    }

    // MARK: - Sub-Group Section Header

    @ViewBuilder
    private func subGroupHeader(name: String, count: Int, collapseKey: String) -> some View {
        let isCollapsed = collapsedSubGroups.contains(collapseKey)
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isCollapsed {
                    collapsedSubGroups.remove(collapseKey)
                } else {
                    collapsedSubGroups.insert(collapseKey)
                }
            }
        } label: {
            HStack(spacing: DatabaseZoomMetrics.size(4)) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(DatabaseZoomMetrics.font(9))
                    .foregroundStyle(.tertiary)
                Text(name)
                    .font(DatabaseZoomMetrics.font(11))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(DatabaseZoomMetrics.font(10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, DatabaseZoomMetrics.size(4))
                    .padding(.vertical, DatabaseZoomMetrics.size(1))
                    .background(Color.fallbackBadgeBg)
                    .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(3)))
                Spacer()
            }
            .padding(.horizontal, DatabaseZoomMetrics.size(8))
            .padding(.vertical, DatabaseZoomMetrics.size(4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Column Card Content

    /// Renders cards for a column, either flat or sub-grouped.
    @ViewBuilder
    private func columnCardContent(columnId: String, columnColor: Color) -> some View {
        let columnRows = rowsForColumn(columnId)

        if subGroupProperty != nil {
            let groups = subGroups(for: columnRows)
            ForEach(groups, id: \.key) { group in
                let collapseKey = subGroupCollapseKey(column: columnId, subGroup: group.key)
                subGroupHeader(name: group.name, count: group.rows.count, collapseKey: collapseKey)

                if !collapsedSubGroups.contains(collapseKey) {
                    ForEach(group.rows) { row in
                        draggableCard(row, columnColor: columnColor)
                    }
                }
            }
        } else {
            ForEach(columnRows) { row in
                draggableCard(row, columnColor: columnColor)
            }
        }
    }

    @ViewBuilder
    private func draggableCard(_ row: DatabaseRow, columnColor: Color) -> some View {
        let title = row.title(schema: schema)
        kanbanCard(row, title: title, columnColor: columnColor)
            .opacity(draggingRowId == row.id ? 0.2 : 1)
            .gesture(
                DragGesture(coordinateSpace: .named(Self.coordinateSpaceName))
                    .onChanged { value in
                        updateDrag(for: row, at: value.location)
                    }
                    .onEnded { value in
                        endDrag(for: row, at: value.location)
                    }
            )
    }

    // MARK: - Kanban Column

    private func kanbanColumn(_ column: (id: String, name: String, color: String), index: Int, availableHeight: CGFloat) -> some View {
        let isTargeted = dragTargetColumn == column.id
        let columnColor = colorForName(column.color)
        return VStack(alignment: .leading, spacing: 0) {
            // Column header with colored label
            HStack {
                columnHeaderNameView(column, color: columnColor)

                Spacer()

                Text("\(rowsForColumn(column.id).count)")
                    .font(DatabaseZoomMetrics.font(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DatabaseZoomMetrics.size(6))
                    .padding(.vertical, DatabaseZoomMetrics.size(2))
                    .background(Color.fallbackBadgeBg)
                    .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
            }
            .padding(.horizontal, DatabaseZoomMetrics.size(8))
            .padding(.vertical, DatabaseZoomMetrics.size(8))
            .contentShape(Rectangle())
            .onNSRightClick {
                openColumnPopover(for: column)
            }
            .floatingPopover(isPresented: columnPopoverBinding(for: column.id), arrowEdge: .bottom) {
                columnPopoverContent(for: column)
            }

            // Cards — scroll vertically within column
            ScrollView(.vertical) {
                LazyVStack(spacing: DatabaseZoomMetrics.size(6)) {
                    columnCardContent(columnId: column.id, columnColor: columnColor)

                    // + New page button at bottom, colored like Notion
                    Button {
                        addCardInColumn(column.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New page")
                        }
                        .font(DatabaseZoomMetrics.font(12))
                        .foregroundStyle(columnColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DatabaseZoomMetrics.size(10))
                        .padding(.vertical, DatabaseZoomMetrics.size(8))
                        .background(columnColor.opacity(0.08))
                        .clipShape(.rect(cornerRadius: cardCornerRadius))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DatabaseZoomMetrics.size(6))
                }
                .padding(.bottom, DatabaseZoomMetrics.size(8))
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: columnWidth)
        .frame(maxHeight: availableHeight)
        .background(
            RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(8))
                .fill(isTargeted ? columnColor.opacity(0.12) : columnColor.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(8))
                .stroke(isTargeted ? columnColor.opacity(0.4) : columnColor.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Move Card

    private func moveCard(_ rowId: String, toColumn columnId: String) {
        guard let prop = groupProperty else { return }
        guard let sourceIdx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        let newValue: PropertyValue = columnId == "__none__" ? .empty : .select(columnId)
        var updated = rows
        updated[sourceIdx].properties[prop.id] = newValue
        let savedRow = updated[sourceIdx]
        rows = updated
        onSave(savedRow)
    }

    /// Update the sub-group property value when a card is dragged to a different sub-group.
    private func moveCardSubGroup(_ rowId: String, toSubGroup subGroupKey: String) {
        guard let prop = subGroupProperty else { return }
        guard let sourceIdx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        let newValue: PropertyValue
        if subGroupKey == "__none__" {
            newValue = .empty
        } else {
            switch prop.type {
            case .select: newValue = .select(subGroupKey)
            case .relation: newValue = .relation(subGroupKey)
            default: return
            }
        }
        var updated = rows
        updated[sourceIdx].properties[prop.id] = newValue
        let savedRow = updated[sourceIdx]
        rows = updated
        onSave(savedRow)
    }

    private func addCardInColumn(_ columnId: String) {
        let now = Date()
        var properties: [String: PropertyValue] = [:]
        if let titleProp = schema.titleProperty {
            properties[titleProp.id] = .text("")
        }
        if let prop = groupProperty, columnId != "__none__" {
            properties[prop.id] = .select(columnId)
        }
        let suffix = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let newRow = DatabaseRow(
            id: "row_\(suffix)",
            properties: properties,
            body: "",
            createdAt: now,
            updatedAt: now
        )
        rows.append(newRow)
        onSave(newRow)
    }

    // MARK: - Kanban Card

    private func kanbanCard(_ row: DatabaseRow, title: String, columnColor: Color) -> some View {
        Text(title.isEmpty ? "Untitled" : title)
            .font(DatabaseZoomMetrics.font(17))
            .fontWeight(.medium)
            .lineLimit(2)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DatabaseZoomMetrics.size(10))
            .background(columnColor.opacity(0.06))
            .clipShape(.rect(cornerRadius: cardCornerRadius))
            .contentShape(Rectangle())
            .onTapGesture { onOpenRow(row) }
            .onNSRightClick {
                showCardPopover = row.id
            }
            .floatingPopover(isPresented: cardPopoverBinding(for: row.id), arrowEdge: .bottom) {
                cardPopoverContent(for: row)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .padding(.horizontal, DatabaseZoomMetrics.size(6))
            .overlay(alignment: .topLeading) {
                if showsInsertionIndicator(for: row.id, placement: .before) {
                    kanbanInsertionIndicator
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsInsertionIndicator(for: row.id, placement: .after) {
                    kanbanInsertionIndicator
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: KanbanCardFramePreferenceKey.self,
                        value: [row.id: proxy.frame(in: .named(Self.coordinateSpaceName))]
                    )
                }
            }
    }

    // MARK: - Helpers

    private var kanbanInsertionIndicator: some View {
        Rectangle()
            .fill(Color.dragIndicator)
            .frame(height: 2)
            .padding(.horizontal, DatabaseZoomMetrics.size(6))
    }

    private func showsInsertionIndicator(for rowId: String, placement: KanbanReorderPlacement) -> Bool {
        reorderTarget?.rowId == rowId && reorderTarget?.placement == placement
    }

    private func updateDrag(for row: DatabaseRow, at location: CGPoint) {
        if draggingRowId == nil {
            draggingRowId = row.id
            if !viewConfig.sorts.isEmpty {
                onClearSorts?()
            }
        }
        dragLocation = location
        dragTargetColumn = targetColumnId(at: location)
        reorderTarget = reorderTarget(for: location)
    }

    private func endDrag(for row: DatabaseRow, at location: CGPoint) {
        dragLocation = location
        let target = reorderTarget(for: location)
        let targetColumn = targetColumnId(at: location)
        let sourceSubGroup = subGroupProperty != nil ? subGroupKey(for: row) : nil
        draggingRowId = nil
        dragTargetColumn = nil
        reorderTarget = nil

        if let targetColumn {
            moveCard(row.id, toColumn: targetColumn)
        }

        // Determine the target sub-group from the drop target row
        if subGroupProperty != nil, let target, let targetRowId = target.rowId,
           let targetRow = rows.first(where: { $0.id == targetRowId }) {
            let destSubGroup = subGroupKey(for: targetRow)
            if destSubGroup != sourceSubGroup {
                moveCardSubGroup(row.id, toSubGroup: destSubGroup)
            }
        }

        guard let target else { return }
        onReorderRows?(row.id, beforeId(for: target))
    }

    private func targetColumnId(at location: CGPoint) -> String? {
        guard !columns.isEmpty else { return nil }
        let columnWidth: CGFloat = 250
        let colIndex = Int(location.x / (columnWidth + 12))
        let clampedIndex = max(0, min(colIndex, columns.count - 1))
        return columns[clampedIndex].id
    }

    private func reorderTarget(for location: CGPoint) -> KanbanReorderTarget? {
        guard let columnId = targetColumnId(at: location) else { return nil }
        let columnRowIds = rowsForColumn(columnId)
            .map(\.id)
            .filter { $0 != draggingRowId }

        guard let firstId = columnRowIds.first else {
            return nil
        }

        for rowId in columnRowIds {
            guard let frame = cardFrames[rowId] else { continue }
            if location.y < frame.minY {
                return KanbanReorderTarget(columnId: columnId, rowId: rowId, placement: .before)
            }
            if location.y <= frame.maxY {
                let placement: KanbanReorderPlacement = location.y < frame.midY ? .before : .after
                return KanbanReorderTarget(columnId: columnId, rowId: rowId, placement: placement)
            }
        }

        if let firstFrame = cardFrames[firstId], location.y < firstFrame.minY {
            return KanbanReorderTarget(columnId: columnId, rowId: firstId, placement: .before)
        }
        if let lastId = columnRowIds.last {
            return KanbanReorderTarget(columnId: columnId, rowId: lastId, placement: .after)
        }
        return nil
    }

    private func beforeId(for target: KanbanReorderTarget) -> String? {
        switch target.placement {
        case .before:
            return target.rowId
        case .after:
            guard let rowId = target.rowId else { return nil }
            return nextVisibleRowId(after: rowId)
        }
    }

    private func nextVisibleRowId(after rowId: String) -> String? {
        guard let index = rows.firstIndex(where: { $0.id == rowId }),
              rows.indices.contains(index + 1) else { return nil }
        return rows[index + 1].id
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "teal": return .teal
        default: return .gray
        }
    }
}

private enum KanbanReorderPlacement {
    case before
    case after
}

private struct KanbanReorderTarget {
    let columnId: String
    let rowId: String?
    let placement: KanbanReorderPlacement
}

/// Self-contained popover menu button with local hover state,
/// avoiding full KanbanView re-renders on hover events.
private struct KanbanPopoverButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DatabaseZoomMetrics.size(8)) {
                Image(systemName: icon)
                    .font(DatabaseZoomMetrics.font(12))
                    .foregroundStyle(isDestructive ? .red.opacity(0.8) : .secondary)
                    .frame(width: DatabaseZoomMetrics.size(16), height: DatabaseZoomMetrics.size(16))
                Text(label)
                    .font(DatabaseZoomMetrics.font(15))
                    .foregroundStyle(isDestructive ? .red.opacity(0.8) : .primary)
                Spacer()
            }
            .padding(.horizontal, DatabaseZoomMetrics.size(10))
            .frame(height: DatabaseZoomMetrics.size(28))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(4))
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, DatabaseZoomMetrics.size(4))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct KanbanCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
