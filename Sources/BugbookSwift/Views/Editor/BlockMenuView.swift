import SwiftUI

/// Popover menu shown when clicking a block's drag handle.
struct BlockMenuView: View {
    @ObservedObject var document: BlockDocument
    let blockId: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Delete
            Button {
                document.dismissBlockMenu()
                document.deleteBlock(id: blockId)
            } label: {
                menuRow(icon: "trash", label: "Delete")
            }
            .buttonStyle(.plain)

            // Duplicate
            Button {
                document.dismissBlockMenu()
                document.duplicateBlock(id: blockId)
            } label: {
                menuRow(icon: "doc.on.doc", label: "Duplicate")
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 4)

            // Turn Into submenu
            Menu {
                turnIntoItems
            } label: {
                menuRow(icon: "arrow.triangle.swap", label: "Turn into")
            }

            Divider().padding(.vertical, 4)

            // Color submenu
            Menu {
                colorItems
            } label: {
                menuRow(icon: "paintpalette", label: "Color")
            }
        }
        .frame(width: 200)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    @ViewBuilder
    private var turnIntoItems: some View {
        ForEach(BlockDocument.slashCommands, id: \.name) { command in
            Button {
                document.changeBlockType(id: blockId, to: command.type)
                if command.type == .heading {
                    document.setHeadingLevel(id: blockId, level: command.headingLevel)
                }
                document.dismissBlockMenu()
            } label: {
                Label(command.name, systemImage: command.icon)
            }
        }
    }

    @ViewBuilder
    private var colorItems: some View {
        Section("Text color") {
            ForEach(BlockColor.allCases, id: \.rawValue) { color in
                Button {
                    document.setTextColor(id: blockId, color: color)
                    document.dismissBlockMenu()
                } label: {
                    HStack {
                        Text("A")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(color.textColor)
                            .frame(width: 20)
                        Text(color.displayName)
                        if document.block(for: blockId)?.textColor == color {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Section("Background") {
            ForEach(BlockColor.allCases, id: \.rawValue) { color in
                Button {
                    document.setBackgroundColor(id: blockId, color: color)
                    document.dismissBlockMenu()
                } label: {
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color == .default ? .clear : color.backgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: color == .default ? 1 : 0)
                            )
                            .frame(width: 20, height: 20)
                        Text(color.displayName)
                        if document.block(for: blockId)?.backgroundColor == color {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    private func menuRow(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)
            Text(label)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
