import SwiftUI

/// Renders a table block as an interactive grid with editable cells,
/// resizable columns, and row/column management.
struct TableBlockView: View {
    var document: BlockDocument
    let block: Block

    @State private var selectedCell: CellPosition?
    @State private var columnWidths: [CGFloat] = []
    @State private var isHovering = false
    @State private var dragColumnIndex: Int?
    @State private var dragStartWidth: CGFloat = 0
    @State private var draggingRowIndex: Int?
    @State private var rowDropTarget: RowDropTarget?
    @State private var rowFrames: [Int: CGRect] = [:]

    private struct CellPosition: Equatable {
        let row: Int
        let col: Int
    }

    private enum RowDropPlacement {
        case before, after
    }

    private struct RowDropTarget: Equatable {
        let row: Int
        let placement: RowDropPlacement
    }

    private var rows: [[String]] { block.tableData }
    private var colCount: Int { rows.map(\.count).max() ?? 3 }
    private var rowCount: Int { rows.count }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Main table
            VStack(alignment: .leading, spacing: 0) {
                tableGrid
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )

                // Add row bar
                addRowBar
                    .opacity(isHovering ? 1 : 0)
            }

            // Add column button — outside the table, to the right
            addColumnButton
                .opacity(isHovering ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedCell = nil }
        .onAppear { initColumnWidths() }
        .onChange(of: colCount) { _, _ in initColumnWidths() }
        .onHover { isHovering = $0 }
    }

    // MARK: - Table Grid

    private var tableGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { rowIdx in
                if rowIdx > 0 {
                    if showsInsertionIndicator(forRow: rowIdx, placement: .before) {
                        Rectangle().fill(Color.dragIndicator).frame(height: 2)
                    } else {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 0.5)
                    }
                }
                tableRow(rowIdx)
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: TableRowFramePreferenceKey.self,
                            value: [rowIdx: geo.frame(in: .named("tableReorder"))]
                        )
                    })
                    .opacity(draggingRowIndex == rowIdx ? 0.4 : 1)

                // Insertion indicator after the last row
                if rowIdx == rowCount - 1, showsInsertionIndicator(forRow: rowIdx, placement: .after) {
                    Rectangle().fill(Color.dragIndicator).frame(height: 2)
                }
            }
        }
        .coordinateSpace(name: "tableReorder")
        .onPreferenceChange(TableRowFramePreferenceKey.self) { rowFrames = $0 }
    }

    // MARK: - Table Row

    @ViewBuilder
    private func tableRow(_ rowIdx: Int) -> some View {
        let isHeader = block.hasHeaderRow && rowIdx == 0

        HStack(spacing: 0) {
            // Row drag handle
            rowDragHandle(rowIdx)
                .opacity(isHovering ? 1 : 0)

            ForEach(0..<colCount, id: \.self) { colIdx in
                if colIdx > 0 {
                    // Resize handle doubles as the column separator
                    columnResizeHandle(colIdx - 1)
                }
                cellView(row: rowIdx, col: colIdx, isHeader: isHeader)
            }
        }
        .background(isHeader ? Color(nsColor: .windowBackgroundColor).opacity(0.6) : Color.clear)
        .contextMenu { rowContextMenu(rowIdx) }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cellView(row: Int, col: Int, isHeader: Bool) -> some View {
        let cellText = cellValue(row: row, col: col)
        let isSelected = selectedCell == CellPosition(row: row, col: col)

        ZStack(alignment: .leading) {
            Text(cellText.isEmpty && !isSelected ? " " : cellText)
                .font(.system(size: Typography.content, weight: isHeader ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .opacity(isSelected ? 0 : 1)

            if isSelected {
                TableCellTextField(
                    text: cellText,
                    isHeader: isHeader,
                    onCommit: { updateCell(row: row, col: col, text: $0) },
                    onTab: { moveToNextCell(from: row, col: col) },
                    onShiftTab: { moveToPreviousCell(from: row, col: col) }
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 32)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded { selectedCell = CellPosition(row: row, col: col) }
        )
    }

    // MARK: - Column Resize Handle

    private func columnResizeHandle(_ colIdx: Int) -> some View {
        Rectangle()
            .fill(dragColumnIndex == colIdx ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor))
            .frame(width: dragColumnIndex == colIdx ? 2 : 0.5)
            .padding(.horizontal, dragColumnIndex == colIdx ? 0 : 1.75)
            .contentShape(Rectangle().size(width: 8, height: .infinity))
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragColumnIndex == nil {
                            dragColumnIndex = colIdx
                            dragStartWidth = colIdx < columnWidths.count ? columnWidths[colIdx] : 150
                        }
                        let newWidth = max(60, dragStartWidth + value.translation.width)
                        if colIdx < columnWidths.count {
                            columnWidths[colIdx] = newWidth
                        }
                    }
                    .onEnded { _ in dragColumnIndex = nil }
            )
    }

    // MARK: - Add Row/Column Controls

    private var addRowBar: some View {
        Button { addRow() } label: {
            HStack {
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to add a new row")
    }

    private var addColumnButton: some View {
        Button { addColumn() } label: {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 24)
        .help("Add column")
    }

    // MARK: - Row Context Menu

    @ViewBuilder
    private func rowContextMenu(_ rowIdx: Int) -> some View {
        if rowIdx == 0 {
            Toggle("Header row", isOn: Binding(
                get: { block.hasHeaderRow },
                set: { _ in toggleHeaderRow() }
            ))
        }
        Divider()
        Button("Insert above") { insertRow(at: rowIdx) }
        Button("Insert below") { insertRow(at: rowIdx + 1) }
        Divider()
        Button("Duplicate") { duplicateRow(rowIdx) }
        Button("Clear contents") { clearRow(rowIdx) }
        Divider()
        Button("Delete", role: .destructive) { deleteRow(rowIdx) }
            .disabled(rowCount <= 1)
    }

    // MARK: - Row Drag Handle

    private func rowDragHandle(_ rowIdx: Int) -> some View {
        GripDotsView()
            .fixedSize()
            .frame(width: 20, height: 32)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("tableReorder"))
                    .onChanged { value in
                        if draggingRowIndex == nil {
                            draggingRowIndex = rowIdx
                        }
                        rowDropTarget = computeDropTarget(at: value.location)
                    }
                    .onEnded { value in
                        let target = computeDropTarget(at: value.location)
                        if let source = draggingRowIndex, let target {
                            let destIndex = target.placement == .before ? target.row : target.row + 1
                            if destIndex != source && destIndex != source + 1 {
                                moveRow(from: source, to: destIndex)
                            }
                        }
                        draggingRowIndex = nil
                        rowDropTarget = nil
                    }
            )
    }

    // MARK: - Row Reorder Helpers

    private func computeDropTarget(at location: CGPoint) -> RowDropTarget? {
        for rowIdx in 0..<rowCount {
            guard let frame = rowFrames[rowIdx] else { continue }
            if location.y < frame.minY {
                return RowDropTarget(row: rowIdx, placement: .before)
            }
            if location.y <= frame.maxY {
                let placement: RowDropPlacement = location.y < frame.midY ? .before : .after
                return RowDropTarget(row: rowIdx, placement: placement)
            }
        }
        // Below all rows
        if let lastFrame = rowFrames[rowCount - 1], location.y > lastFrame.maxY {
            return RowDropTarget(row: rowCount - 1, placement: .after)
        }
        // Above all rows
        if let firstFrame = rowFrames[0], location.y < firstFrame.minY {
            return RowDropTarget(row: 0, placement: .before)
        }
        return nil
    }

    private func showsInsertionIndicator(forRow rowIdx: Int, placement: RowDropPlacement) -> Bool {
        rowDropTarget?.row == rowIdx && rowDropTarget?.placement == placement
    }

    private func moveRow(from source: Int, to dest: Int) {
        document.updateBlockProperty(id: block.id) { block in
            guard source < block.tableData.count else { return }
            let row = block.tableData.remove(at: source)
            let adjustedDest = dest > source ? dest - 1 : dest
            block.tableData.insert(row, at: min(adjustedDest, block.tableData.count))
        }
    }

    // MARK: - Data Helpers

    private func cellValue(row: Int, col: Int) -> String {
        guard row < rows.count, col < rows[row].count else { return "" }
        return rows[row][col]
    }

    private func initColumnWidths() {
        if columnWidths.count != colCount {
            columnWidths = Array(repeating: 150, count: colCount)
        }
    }

    // MARK: - Cell Navigation

    private func moveToNextCell(from row: Int, col: Int) {
        if col + 1 < colCount { selectedCell = CellPosition(row: row, col: col + 1) }
        else if row + 1 < rowCount { selectedCell = CellPosition(row: row + 1, col: 0) }
    }

    private func moveToPreviousCell(from row: Int, col: Int) {
        if col > 0 { selectedCell = CellPosition(row: row, col: col - 1) }
        else if row > 0 { selectedCell = CellPosition(row: row - 1, col: colCount - 1) }
    }

    // MARK: - Mutations

    private func updateCell(row: Int, col: Int, text: String) {
        document.updateTableCell(id: block.id, row: row, col: col, text: text)
    }

    private func addRow() {
        document.addTableRow(id: block.id, colCount: colCount)
    }

    private func addColumn() {
        document.addTableColumn(id: block.id)
        columnWidths.append(150)
    }

    private func insertRow(at index: Int) {
        document.insertTableRow(id: block.id, at: index, colCount: colCount)
    }

    private func deleteRow(_ index: Int) {
        guard rowCount > 1 else { return }
        document.deleteTableRow(id: block.id, at: index)
        if selectedCell?.row == index { selectedCell = nil }
    }

    private func duplicateRow(_ index: Int) {
        document.duplicateTableRow(id: block.id, at: index)
    }

    private func clearRow(_ index: Int) {
        document.clearTableRow(id: block.id, at: index)
    }

    private func toggleHeaderRow() {
        document.toggleTableHeaderRow(id: block.id)
    }

    private func deleteColumn(_ index: Int) {
        guard colCount > 1 else { return }
        document.deleteTableColumn(id: block.id, at: index)
        if index < columnWidths.count { columnWidths.remove(at: index) }
    }
}

// MARK: - Cell Text Field

struct TableCellTextField: NSViewRepresentable {
    let text: String
    let isHeader: Bool
    let onCommit: (String) -> Void
    let onTab: () -> Void
    let onShiftTab: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.font = NSFont.systemFont(
            ofSize: Typography.content,
            weight: isHeader ? .semibold : .regular
        )
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Don't update while editing to avoid cursor jumps
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit, onTab: onTab, onShiftTab: onShiftTab)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onCommit: (String) -> Void
        let onTab: () -> Void
        let onShiftTab: () -> Void
        private var committedViaTab = false

        init(onCommit: @escaping (String) -> Void, onTab: @escaping () -> Void, onShiftTab: @escaping () -> Void) {
            self.onCommit = onCommit
            self.onTab = onTab
            self.onShiftTab = onShiftTab
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if committedViaTab { committedViaTab = false; return }
            guard let field = notification.object as? NSTextField else { return }
            onCommit(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertTab(_:)) {
                committedViaTab = true
                if let field = control as? NSTextField { onCommit(field.stringValue) }
                onTab()
                return true
            }
            if selector == #selector(NSResponder.insertBacktab(_:)) {
                committedViaTab = true
                if let field = control as? NSTextField { onCommit(field.stringValue) }
                onShiftTab()
                return true
            }
            return false
        }
    }
}

// MARK: - Preference Key for Row Frames

private struct TableRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
