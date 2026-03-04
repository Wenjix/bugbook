import SwiftUI

struct CanvasCardView: View {
    @ObservedObject var document: CanvasDocument
    let node: CanvasNodeMeta
    let zoom: CGFloat
    var onNavigateToFile: ((String) -> Void)?

    @State private var isDragging = false
    @State private var isResizing = false
    @State private var dragStart: CGPoint = .zero
    @State private var resizeStart: CGSize = .zero

    private var isSelected: Bool { document.selectedNodeIds.contains(node.id) }
    private var isEditing: Bool { document.editingNodeId == node.id }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            cardContent
                .frame(width: node.width, height: node.height)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

            // Resize handle (single-select only)
            if isSelected && document.selectedNodeIds.count == 1 {
                resizeHandle
            }

            // Anchor dots for edge creation (single-select only)
            if isSelected && document.selectedNodeIds.count == 1 {
                ForEach(["top", "right", "bottom", "left"], id: \.self) { side in
                    anchorDot(side: side)
                }
            }
        }
        .position(x: node.x + node.width / 2, y: node.y + node.height / 2)
        .onTapGesture {
            document.selectedEdgeId = nil
            if NSEvent.modifierFlags.contains(.shift) {
                document.toggleNodeSelection(node.id)
            } else {
                document.selectedNodeId = node.id
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                switch node.type {
                case .text:
                    document.editingNodeId = node.id
                case .file:
                    if let path = document.resolveFilePath(for: node) {
                        onNavigateToFile?(path)
                    }
                case .image:
                    break
                }
            }
        )
        .gesture(nodeDragGesture)
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        switch node.type {
        case .text:
            textCardContent
        case .file:
            fileCardContent
        case .image:
            imageCardContent
        }
    }

    @ViewBuilder
    private var textCardContent: some View {
        let text = document.nodeTexts[node.id] ?? ""
        if isEditing {
            TextEditorWrapper(
                text: Binding(
                    get: { document.nodeTexts[node.id] ?? "" },
                    set: { document.updateNodeText(id: node.id, text: $0) }
                ),
                onCommit: { document.editingNodeId = nil }
            )
            .padding(12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if text.isEmpty {
                    Text("Double-click to edit")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(12)
                } else {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .padding(12)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var fileCardContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.fileNodeDisplayName(for: node))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if let file = node.file {
                    Text(file)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
    }

    @ViewBuilder
    private var imageCardContent: some View {
        if let file = node.file {
            let imagePath = (document.canvasPath as NSString).appendingPathComponent(file)
            if let nsImage = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("Image not found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Style

    private var cardBackground: Color {
        if let colorName = node.color {
            return canvasColor(colorName).opacity(0.15)
        }
        return Color.fallbackBgPrimary
    }

    private func canvasColor(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        default: return .gray
        }
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.3))
            .frame(width: 12, height: 12)
            .cornerRadius(2)
            .padding(4)
            .contentShape(Rectangle().size(width: 20, height: 20))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            resizeStart = CGSize(width: node.width, height: node.height)
                        }
                        let newWidth = resizeStart.width + value.translation.width / zoom
                        let newHeight = resizeStart.height + value.translation.height / zoom
                        document.resizeNode(id: node.id, width: newWidth, height: newHeight)
                    }
                    .onEnded { _ in
                        isResizing = false
                    }
            )
    }

    // MARK: - Anchor Dots

    @ViewBuilder
    private func anchorDot(side: String) -> some View {
        let dotSize: CGFloat = 8
        Circle()
            .fill(Color.accentColor)
            .frame(width: dotSize, height: dotSize)
            .position(anchorPosition(side: side))
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onEnded { value in
                        // Find target node at drop location
                        let dropPoint = CGPoint(
                            x: node.x + node.width / 2 + value.translation.width / zoom,
                            y: node.y + node.height / 2 + value.translation.height / zoom
                        )
                        if let targetId = hitTestNode(at: dropPoint, excluding: node.id) {
                            let toSide = oppositeSide(side)
                            document.addEdge(from: node.id, to: targetId, fromSide: side, toSide: toSide)
                        }
                    }
            )
    }

    private func anchorPosition(side: String) -> CGPoint {
        switch side {
        case "top": return CGPoint(x: node.width / 2, y: -4)
        case "right": return CGPoint(x: node.width + 4, y: node.height / 2)
        case "bottom": return CGPoint(x: node.width / 2, y: node.height + 4)
        case "left": return CGPoint(x: -4, y: node.height / 2)
        default: return .zero
        }
    }

    private func oppositeSide(_ side: String) -> String {
        switch side {
        case "top": return "bottom"
        case "bottom": return "top"
        case "left": return "right"
        case "right": return "left"
        default: return "left"
        }
    }

    private func hitTestNode(at point: CGPoint, excluding nodeId: String) -> String? {
        for n in document.nodes where n.id != nodeId {
            let rect = CGRect(x: n.x, y: n.y, width: n.width, height: n.height)
            if rect.contains(point) {
                return n.id
            }
        }
        return nil
    }

    // MARK: - Drag Gesture

    private var nodeDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = CGPoint(x: node.x, y: node.y)
                }
                let newX = dragStart.x + value.translation.width / zoom
                let newY = dragStart.y + value.translation.height / zoom
                document.moveNode(id: node.id, to: CGPoint(x: newX, y: newY))
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}

// MARK: - TextEditor Wrapper

private struct TextEditorWrapper: View {
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onKeyPress(.escape) {
                onCommit()
                return .handled
            }
    }
}
