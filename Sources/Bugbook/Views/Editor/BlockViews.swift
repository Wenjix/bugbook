import SwiftUI

// MARK: - Shared block-deletion keyboard modifier

/// Makes a non-text block focusable and deletable via Delete/Backspace when selected.
private struct BlockDeletableModifier: ViewModifier {
    var document: BlockDocument
    let blockId: UUID
    @FocusState private var isKeyboardFocused: Bool

    private var isSelected: Bool {
        document.selectedBlockIds.contains(blockId)
    }

    private static let deleteKeys: Set<KeyEquivalent> = [
        .delete,
        .init(Character(UnicodeScalar(127))), // backspace
    ]

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isKeyboardFocused)
            .onKeyPress(keys: Self.deleteKeys) { _ in
                guard isSelected else { return .ignored }
                document.deleteSelectedBlocks()
                return .handled
            }
            .onChange(of: isSelected) { _, selected in
                isKeyboardFocused = selected
            }
    }
}

extension View {
    func blockDeletable(document: BlockDocument, blockId: UUID) -> some View {
        modifier(BlockDeletableModifier(document: document, blockId: blockId))
    }
}

/// Horizontal rule block.
struct HorizontalRuleView: View {
    var body: some View {
        Rectangle()
            .fill(Color.fallbackDividerColor)
            .frame(height: 1)
            .padding(.vertical, 6)
    }
}

/// Image block — renders local or remote images with selection and resize support.
struct ImageBlockView: View {
    private enum ResizeBarPosition: CaseIterable {
        case leading
        case trailing

        var alignment: Alignment {
            switch self {
            case .leading: return .leading
            case .trailing: return .trailing
            }
        }

        var horizontalDirection: CGFloat {
            switch self {
            case .leading:
                return -1
            case .trailing:
                return 1
            }
        }
    }

    var document: BlockDocument
    let block: Block
    @State private var cachedImage: NSImage?
    @State private var isHovered = false
    @State private var isResizing = false
    @State private var resizeStartWidth: CGFloat?
    @State private var transientWidth: CGFloat?
    private var isLocalImage: Bool {
        block.imageSource.hasPrefix("/") || block.imageSource.hasPrefix("file://")
    }

    private var currentWidth: CGFloat? {
        block.imageWidth.map { CGFloat($0) }
    }

    private var displayWidth: CGFloat? {
        transientWidth ?? currentWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            imageContent
                .appCursor(isResizing ? .closedHand : .openHand)
                .clipShape(.rect(cornerRadius: 4))
                .overlay {
                    if showsResizeBars {
                        resizeChrome
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                }
                .onTapGesture {
                    document.clearMultiBlockTextSelection()
                    document.clearBlockSelection()
                    document.selectedBlockIds = [block.id]
                    document.focusedBlockId = nil
                }
                .draggable(document.dragPayload(for: block.id)) {
                    imageDragPreview
                }

            if !block.imageAlt.isEmpty {
                Text(block.imageAlt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Tappable region below image — click here to focus/create an
            // empty paragraph underneath instead of selecting the image.
            // Uses a Button (not onTapGesture) so it participates in the
            // responder chain and doesn't get swallowed by parent gestures.
            Button {
                document.clearMultiBlockTextSelection()
                document.clearBlockSelection()
                document.focusOrInsertParagraphAfter(blockId: block.id)
            } label: {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appCursor(.iBeam)
        }
        .blockDeletable(document: document, blockId: block.id)
        .task(id: block.imageSource) {
            guard isLocalImage else { return }
            let source = block.imageSource
            let fileURL = source.hasPrefix("file://")
                ? URL(string: source)!
                : URL(fileURLWithPath: source)
            cachedImage = NSImage(contentsOf: fileURL)
        }
    }

    private var showsResizeBars: Bool {
        isHovered || isResizing
    }

    @ViewBuilder
    private var imageContent: some View {
        if isLocalImage {
            if let nsImage = cachedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: displayWidth ?? .infinity)
            } else {
                imagePlaceholder
            }
        } else if let url = URL(string: block.imageSource) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: displayWidth ?? .infinity)
            } placeholder: {
                imagePlaceholder
            }
        } else {
            imagePlaceholder
        }
    }

    private var resizeChrome: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(ResizeBarPosition.allCases, id: \.self) { position in
                    resizeBar(position)
                        .frame(
                            width: resizeHitArea(for: position, in: geometry.size).width,
                            height: resizeHitArea(for: position, in: geometry.size).height
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
                }
            }
        }
        .padding(2)
    }

    private func resizeBar(_ position: ResizeBarPosition) -> some View {
        ZStack {
            Color.clear
            resizeAffordance()
                .frame(width: 20, height: 124)
        }
            .contentShape(Rectangle())
            .appCursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStartWidth == nil {
                            resizeStartWidth = displayWidth ?? 600
                            isResizing = true
                        }
                        guard let startWidth = resizeStartWidth else { return }
                        let delta = position.horizontalDirection * value.translation.width
                        let newWidth = max(100, startWidth + delta)
                        transientWidth = newWidth
                    }
                    .onEnded { _ in
                        if let finalWidth = transientWidth ?? resizeStartWidth {
                            document.updateImageWidth(blockId: block.id, width: Double(finalWidth))
                        }
                        transientWidth = nil
                        resizeStartWidth = nil
                        isResizing = false
                    }
            )
    }

    private func resizeAffordance() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
            .overlay {
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 4, height: 58)
            }
    }

    private func resizeHitArea(for position: ResizeBarPosition, in size: CGSize) -> CGSize {
        CGSize(width: 28, height: min(max(size.height * 0.6, 88), max(size.height, 88)))
    }

    private var imageDragPreview: some View {
        ZStack {
            imageContent
                .frame(maxWidth: 220)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 6))
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.fallbackSurfaceSubtle)
            .frame(height: 100)
            .overlay(
                Text("Image: \(block.imageSource)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }
}

/// Database embed block — wraps existing DatabaseInlineEmbedView.
struct DatabaseEmbedBlockView: View {
    var document: BlockDocument
    let block: Block
    let dbPath: String
    var onOpenDatabaseTab: ((String) -> Void)?
    var sidebarReferencePayload: SidebarReferenceDragPayload?
    @State private var isHoveringEmbed = false

    private var displayName: String {
        let name = (dbPath as NSString).lastPathComponent
        let ext = ".bugbookdb"
        if name.hasSuffix(ext) {
            return String(name.dropLast(ext.count))
        }
        return name
    }

    var body: some View {
        let content = databaseEmbedView
            .blockDeletable(document: document, blockId: block.id)

        content
    }

    private func sidebarDragHandle(payload: SidebarReferenceDragPayload) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(6)
            .draggable(payload) {
                SidebarDragPreview(systemImage: "tablecells", title: displayName)
            }
    }

    private var databaseEmbedView: some View {
        DatabaseInlineEmbedView(
            dbPath: dbPath,
            onOpenDatabase: { onOpenDatabaseTab?(dbPath) }
        )
        .padding(.vertical, 4)
    }
}
