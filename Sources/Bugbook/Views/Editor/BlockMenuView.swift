import SwiftUI

/// Popover menu shown when clicking a block's drag handle.
struct BlockMenuView: View {
    var document: BlockDocument
    let blockId: UUID

    @State private var hoveredItem: String?
    @State private var activeSubmenu: ActiveSubmenu?
    @State private var showMovePicker = false
    /// Debounce timer to avoid flicker when moving between trigger row and submenu panel.
    @State private var dismissTask: Task<Void, Never>?

    private enum ActiveSubmenu: Equatable {
        case turnInto
        case color
    }

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
        HStack(alignment: .top, spacing: 4) {
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

                if let block = currentBlock, block.type == .pageLink,
                   let pagePath = resolvePageLinkPath(block.pageLinkName) {
                    let isFav = document.onIsFavorite?(pagePath) ?? false
                    menuButton(
                        id: "favorite",
                        icon: isFav ? "star.fill" : "star",
                        label: isFav ? "Unfavorite page" : "Favorite page"
                    ) {
                        document.onToggleFavorite?(pagePath)
                        document.dismissBlockMenu()
                    }
                }

                sectionDivider

                // Section 2: Turn Into — hover to open submenu
                submenuRow(
                    id: "turninto",
                    icon: "arrow.triangle.swap",
                    label: "Turn into",
                    submenu: .turnInto
                )

                // Section 3: Color — hover to open submenu
                submenuRow(
                    id: "color",
                    icon: "paintpalette",
                    label: "Color",
                    submenu: .color
                )
            }
            .frame(width: 252)
            .padding(.vertical, 4)
            .popoverSurface()
            .onHover { hovering in
                if !hovering && hoveredItem != "turninto" && hoveredItem != "color" {
                    scheduleDismissSubmenu()
                }
            }

            if activeSubmenu != nil {
                submenuPanel(for: activeSubmenu!)
                    .onHover { hovering in
                        handleSubmenuHover(hovering)
                    }
            }
        }
    }

    // MARK: - Submenu Hover Helpers

    private func showSubmenu(_ submenu: ActiveSubmenu) {
        dismissTask?.cancel()
        dismissTask = nil
        activeSubmenu = submenu
    }

    private func scheduleDismissSubmenu() {
        dismissTask?.cancel()
        dismissTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                activeSubmenu = nil
            } catch {
                // Cancelled — don't dismiss
            }
        }
    }

    private func handleSubmenuHover(_ hovering: Bool) {
        if hovering {
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            scheduleDismissSubmenu()
        }
    }

    @ViewBuilder
    private func submenuPanel(for submenu: ActiveSubmenu) -> some View {
        switch submenu {
        case .turnInto:
            turnIntoSubmenu
        case .color:
            colorSubmenu
        }
    }

    // MARK: - Submenu Row (hover-triggered)

    private func submenuRow(
        id: String,
        icon: String,
        label: String,
        submenu: ActiveSubmenu
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            Text(label)
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
                .fill(hoveredItem == id || activeSubmenu == submenu
                    ? Color.primary.opacity(0.06)
                    : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovering in
            if isHovering {
                hoveredItem = id
                showSubmenu(submenu)
            } else {
                hoveredItem = nil
                scheduleDismissSubmenu()
            }
        }
    }

    // MARK: - Turn Into Submenu

    private var turnIntoSubmenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(turnIntoItems, id: \.name) { item in
                turnIntoRow(item)
            }
        }
        .frame(width: 200)
        .padding(.vertical, 4)
        .popoverSurface()
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
            document.focusedBlockId = blockId
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
            .padding(.horizontal, 12)
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

    // MARK: - Color Submenu

    private var colorSubmenu: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                // Text color section
                Text("TEXT")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(BlockColor.allCases, id: \.rawValue) { color in
                        textColorRow(color)
                    }
                }

                Divider()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)

                // Background color section
                Text("BACKGROUND")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(BlockColor.allCases, id: \.rawValue) { color in
                        backgroundColorRow(color)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .frame(width: 200)
        .frame(maxHeight: 420)
        .popoverSurface()
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

    // MARK: - Color Rows

    private func textColorRow(_ color: BlockColor) -> some View {
        let isSelected = currentBlock?.textColor == color
        let rowId = "tc_\(color.rawValue)"
        return Button {
            document.setTextColor(id: blockId, color: color)
            document.dismissBlockMenu()
            document.focusedBlockId = blockId
        } label: {
            HStack(spacing: 10) {
                // Color swatch: letter "A" with the text color
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 22, height: 22)
                    Text("A")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color == .default ? .primary : color.textColor)
                }
                Text(color.displayName)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredItem == rowId ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredItem = isHovering ? rowId : nil
        }
    }

    private func backgroundColorRow(_ color: BlockColor) -> some View {
        let isSelected = currentBlock?.backgroundColor == color
        let rowId = "bg_\(color.rawValue)"
        return Button {
            document.setBackgroundColor(id: blockId, color: color)
            document.dismissBlockMenu()
            document.focusedBlockId = blockId
        } label: {
            HStack(spacing: 10) {
                // Color swatch: rounded square filled with the background color
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color == .default ? Color.primary.opacity(0.06) : color.backgroundColor)
                        .frame(width: 22, height: 22)
                    if color == .default {
                        // Strikethrough to indicate "no color"
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 14, height: 1.5)
                            .rotationEffect(.degrees(-45))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(color.textColor.opacity(0.3), lineWidth: 1)
                            .frame(width: 22, height: 22)
                    }
                }
                Text(color.displayName)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredItem == rowId ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredItem = isHovering ? rowId : nil
        }
    }

    // MARK: - Helpers

    private struct TurnIntoItem: Identifiable {
        let name: String
        let icon: String
        let blockType: BlockType
        let headingLevel: Int
        var id: String { name }
    }

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

    private func resolvePageLinkPath(_ name: String) -> String? {
        func search(in entries: [FileEntry]) -> String? {
            for entry in entries {
                let entryName = entry.name.replacingOccurrences(of: ".md", with: "")
                if entryName.localizedCaseInsensitiveCompare(name) == .orderedSame {
                    return entry.path
                }
                if let children = entry.children, let found = search(in: children) {
                    return found
                }
            }
            return nil
        }
        return search(in: document.availablePages)
    }
}
