import SwiftUI

/// Popover menu shown when clicking a block's drag handle.
struct BlockMenuView: View {
    var document: BlockDocument
    let blockId: UUID

    @State private var hoveredItem: String?
    @State private var turnIntoExpanded = false
    @State private var colorExpanded = false
    @State private var showMovePicker = false

    private var currentBlock: Block? {
        document.block(for: blockId)
    }

    var body: some View {
        if showMovePicker {
            movePickerContent
        } else {
            menuContent
        }
    }

    // MARK: - Main Menu

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Actions
            sectionHeader("Actions")
            menuButton(id: "delete", icon: "trash", label: "Delete", shortcut: "\u{232B}") {
                document.dismissBlockMenu()
                document.deleteBlock(id: blockId)
            }
            menuButton(id: "duplicate", icon: "doc.on.doc", label: "Duplicate", shortcut: "\u{2318}D") {
                document.dismissBlockMenu()
                document.duplicateBlock(id: blockId)
            }
            moveToButton

            sectionDivider

            // Section 2: Turn Into
            sectionHeader("Turn into")
            turnIntoToggle
            if turnIntoExpanded {
                turnIntoList
            }

            sectionDivider

            // Section 3: Color
            sectionHeader("Color")
            colorToggle
            if colorExpanded {
                colorPalette
            }
        }
        .frame(width: 252)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Move To Button (with arrow)

    private var moveToButton: some View {
        Button {
            showMovePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                Text("Move to")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredItem == "moveto" ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredItem = isHovering ? "moveto" : nil
        }
    }

    // MARK: - Inline Move Picker (reuses MovePagePickerView)

    private var movePickerContent: some View {
        MovePagePickerView(
            fileTree: document.availablePages,
            movingPath: document.filePath ?? "",
            workspacePath: document.workspacePath ?? "",
            onMove: { destDir in
                document.onMoveBlock?(blockId, destDir)
            },
            isPresented: $showMovePicker
        )
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
    }

    // MARK: - Menu Button

    private func menuButton(
        id: String,
        icon: String,
        label: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredItem == id ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredItem = isHovering ? id : nil
        }
    }

    // MARK: - Turn Into

    private var turnIntoToggle: some View {
        Button {
            turnIntoExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                Text(currentBlockTypeName)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .rotationEffect(.degrees(turnIntoExpanded ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredItem == "turninto" ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredItem = isHovering ? "turninto" : nil
        }
    }

    private var turnIntoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(turnIntoItems, id: \.name) { item in
                turnIntoRow(item)
            }
        }
        .padding(.top, 2)
    }

    private func turnIntoRow(_ item: TurnIntoItem) -> some View {
        let itemId = "ti_\(item.name)"
        let isCurrentType = blockMatchesCommand(type: item.blockType, headingLevel: item.headingLevel)
        return Button {
            document.changeBlockType(id: blockId, to: item.blockType)
            if item.blockType == .heading {
                document.setHeadingLevel(id: blockId, level: item.headingLevel)
            }
            document.dismissBlockMenu()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                Text(item.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                if isCurrentType {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredItem == itemId ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredItem = isHovering ? itemId : nil
        }
    }

    // MARK: - Color

    private var colorToggle: some View {
        Button {
            colorExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                Text("Color")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .rotationEffect(.degrees(colorExpanded ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredItem == "color" ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredItem = isHovering ? "color" : nil
        }
    }

    private let colorGridColumns = Array(repeating: GridItem(.fixed(20), spacing: 6), count: 5)

    private var colorPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TEXT")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)

                LazyVGrid(columns: colorGridColumns, spacing: 6) {
                    ForEach(BlockColor.allCases, id: \.rawValue) { color in
                        textColorDot(color)
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("BACKGROUND")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)

                LazyVGrid(columns: colorGridColumns, spacing: 6) {
                    ForEach(BlockColor.allCases, id: \.rawValue) { color in
                        backgroundColorSquare(color)
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func textColorDot(_ color: BlockColor) -> some View {
        let isSelected = currentBlock?.textColor == color
        return Button {
            document.setTextColor(id: blockId, color: color)
            document.dismissBlockMenu()
        } label: {
            ZStack {
                Circle()
                    .fill(color == .default ? Color.primary : color.textColor)
                    .frame(width: 20, height: 20)
                if color == .default {
                    Circle()
                        .strokeBorder(Color.gray.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    // Diagonal strikethrough for "no color"
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 16, height: 1.5)
                        .rotationEffect(.degrees(-45))
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color == .default ? Color(nsColor: .windowBackgroundColor) : .white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
        .help(color.displayName)
    }

    private func backgroundColorSquare(_ color: BlockColor) -> some View {
        let isSelected = currentBlock?.backgroundColor == color
        return Button {
            document.setBackgroundColor(id: blockId, color: color)
            document.dismissBlockMenu()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color == .default ? Color.clear : color.textColor.opacity(0.25))
                    .frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        color == .default ? Color.gray.opacity(0.4) : color.textColor.opacity(0.4),
                        lineWidth: 1
                    )
                    .frame(width: 20, height: 20)
                if color == .default {
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 16, height: 1.5)
                        .rotationEffect(.degrees(-45))
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
        .help(color.displayName)
    }

    // MARK: - Helpers

    /// Simple value type for turn-into items, avoiding nested type reference issues with ForEach.
    private struct TurnIntoItem: Identifiable {
        let name: String
        let icon: String
        let blockType: BlockType
        let headingLevel: Int
        var id: String { name }
    }

    /// Block types that make sense for "Turn into" (excludes image, databaseEmbed, pageLink, column).
    private var turnIntoItems: [TurnIntoItem] {
        BlockDocument.slashCommands.compactMap { command in
            guard case let .blockType(type, headingLevel) = command.action else { return nil }
            switch type {
            case .image, .databaseEmbed, .pageLink, .column:
                return nil
            default:
                return TurnIntoItem(name: command.name, icon: command.icon, blockType: type, headingLevel: headingLevel)
            }
        }
    }

    private func blockMatchesCommand(type: BlockType, headingLevel: Int) -> Bool {
        guard let block = currentBlock else { return false }
        if block.type != type { return false }
        if type == .heading { return block.headingLevel == headingLevel }
        return true
    }

    private var currentBlockTypeName: String {
        guard let block = currentBlock else { return "Text" }
        switch block.type {
        case .paragraph: return "Text"
        case .heading:
            return "Heading \(block.headingLevel)"
        case .bulletListItem: return "Bullet List"
        case .numberedListItem: return "Numbered List"
        case .taskItem: return "To-do"
        case .codeBlock: return "Code"
        case .blockquote: return "Quote"
        case .horizontalRule: return "Divider"
        case .image: return "Image"
        case .databaseEmbed: return "Database"
        case .pageLink: return "Page Link"
        case .toggle: return "Toggle"
        case .column: return "Column"
        }
    }
}
