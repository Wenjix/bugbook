import SwiftUI

/// Highlighted callout container with icon, editable title, and nested child blocks.
/// Default: neutral gray background with a lightbulb icon.
/// Click the icon to open a picker for changing color and icon.
struct CalloutBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var textHeight: CGFloat = 24
    @State private var showPicker = false

    private var calloutBlockColor: BlockColor {
        BlockColor(rawValue: block.calloutColor) ?? .default
    }

    /// The accent color used for the left border and icon tint.
    private var accentColor: Color {
        switch calloutBlockColor {
        case .default: return Color.fallbackTextSecondary
        default: return calloutBlockColor.textColor
        }
    }

    /// The background fill for the callout container.
    private var fillColor: Color {
        switch calloutBlockColor {
        case .default: return Color.primary.opacity(Opacity.subtle)
        default: return calloutBlockColor.backgroundColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: icon + editable title
            HStack(alignment: .top, spacing: 6) {
                Button {
                    showPicker.toggle()
                } label: {
                    Image(systemName: block.calloutIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accentColor)
                        .frame(width: 20, height: 24)
                }
                .buttonStyle(.plain)
                .appCursor(.pointingHand)
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    CalloutPickerView(
                        document: document,
                        blockId: block.id,
                        currentIcon: block.calloutIcon,
                        currentColor: block.calloutColor
                    )
                }

                BlockTextView(
                    document: document,
                    blockId: block.id,
                    selectionVersion: document.selectionVersion,
                    font: .systemFont(ofSize: EditorTypography.bodyFontSize, weight: .semibold),
                    textColor: .labelColor,
                    placeholder: "Callout",
                    onTextChange: onTyping,
                    textHeight: $textHeight
                )
                .frame(height: textHeight)
            }

            // Children
            if !block.children.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(block.children.enumerated()), id: \.element.id) { idx, child in
                        let prevType = idx > 0 ? block.children[idx - 1].type : nil
                        let nextType = idx + 1 < block.children.count ? block.children[idx + 1].type : nil
                        BlockCellView(document: document, block: child, previousBlockType: prevType, nextBlockType: nextType, onTyping: onTyping)
                            .padding(.vertical, 1)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.primary.opacity(Opacity.light), lineWidth: 1)
        )
    }
}

// MARK: - Callout Picker

/// Popover for choosing callout color and icon.
private struct CalloutPickerView: View {
    var document: BlockDocument
    let blockId: UUID
    let currentIcon: String
    let currentColor: String

    private static let colorOptions: [(String, String)] = [
        ("default", "Default"),
        ("gray", "Gray"),
        ("brown", "Brown"),
        ("orange", "Orange"),
        ("yellow", "Yellow"),
        ("green", "Green"),
        ("blue", "Blue"),
        ("purple", "Purple"),
        ("pink", "Pink"),
        ("red", "Red"),
    ]

    private static let iconOptions: [(String, String)] = [
        ("lightbulb", "Lightbulb"),
        ("info.circle", "Info"),
        ("exclamationmark.triangle", "Warning"),
        ("checkmark.circle", "Success"),
        ("xmark.circle", "Error"),
        ("star", "Star"),
        ("heart", "Heart"),
        ("bolt", "Bolt"),
        ("flag", "Flag"),
        ("bookmark", "Bookmark"),
        ("bell", "Bell"),
        ("pin", "Pin"),
        ("pencil", "Pencil"),
        ("link", "Link"),
        ("questionmark.circle", "Question"),
        ("flame", "Fire"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Color section
            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(Color.fallbackTextSecondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 5), spacing: 6) {
                    ForEach(Self.colorOptions, id: \.0) { key, _ in
                        let blockColor = BlockColor(rawValue: key) ?? .default
                        let swatchColor: Color = key == "default"
                            ? Color.primary.opacity(Opacity.medium)
                            : blockColor.textColor

                        Button {
                            setColor(key)
                        } label: {
                            Circle()
                                .fill(swatchColor)
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if currentColor == key {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Icon section
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(Color.fallbackTextSecondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 4), spacing: 4) {
                    ForEach(Self.iconOptions, id: \.0) { symbol, _ in
                        Button {
                            setIcon(symbol)
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(currentIcon == symbol ? Color.accentColor : Color.fallbackTextSecondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.xs)
                                        .fill(currentIcon == symbol ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 180)
    }

    private func setColor(_ color: String) {
        document.updateBlockProperty(id: blockId) { block in
            block.calloutColor = color
        }
    }

    private func setIcon(_ icon: String) {
        document.updateBlockProperty(id: blockId) { block in
            block.calloutIcon = icon
        }
    }
}
