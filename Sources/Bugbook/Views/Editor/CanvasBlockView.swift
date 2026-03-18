import SwiftUI
import AppKit

/// Inline canvas block rendered within the block editor.
/// Supports text nodes with drag-to-move, pan, zoom, double-click to add,
/// click to select, and Delete to remove.
struct CanvasBlockView: View {
    var document: BlockDocument
    let block: Block

    @State private var canvasData: CanvasBlockData
    @State private var panOffset: CGSize = .zero
    @State private var baseZoom: CGFloat = 1.0
    @State private var selectedNodeId: String?
    @State private var editingNodeId: String?
    @State private var lastMouseLocation: CGPoint = CGPoint(x: 200, y: 150)
    @State private var canvasSize: CGSize = CGSize(width: 600, height: 300)

    init(document: BlockDocument, block: Block) {
        self.document = document
        self.block = block
        self._canvasData = State(initialValue: CanvasBlockData.from(json: block.text))
    }

    private var zoom: CGFloat { canvasData.viewport.zoom }

    var body: some View {
        ZStack {
            canvasBackground
            canvasContent
                .scaleEffect(zoom)
                .offset(
                    x: canvasData.viewport.x + panOffset.width,
                    y: canvasData.viewport.y + panOffset.height
                )
        }
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 400)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .overlay(scrollZoomOverlay)
        .onKeyPress(.delete) {
            guard let id = selectedNodeId else { return .ignored }
            deleteNode(id: id)
            return .handled
        }
        .onKeyPress(.init(Character(UnicodeScalar(127)))) { // backspace
            guard let id = selectedNodeId else { return .ignored }
            deleteNode(id: id)
            return .handled
        }
        .focusable()
        .focusEffectDisabled()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                lastMouseLocation = location
            }
        }
    }

    // MARK: - Background

    private var canvasBackground: some View {
        ZStack {
            Color.fallbackEditorBg

            // Dot grid
            Canvas { context, size in
                let spacing: CGFloat = 24 * zoom
                guard spacing > 6 else { return }
                let offsetX = canvasData.viewport.x.truncatingRemainder(dividingBy: spacing) + panOffset.width.truncatingRemainder(dividingBy: spacing)
                let offsetY = canvasData.viewport.y.truncatingRemainder(dividingBy: spacing) + panOffset.height.truncatingRemainder(dividingBy: spacing)
                let dotSize: CGFloat = max(1.0, 1.5 * zoom)
                let cols = Int(size.width / spacing) + 2
                let rows = Int(size.height / spacing) + 2
                for col in 0..<cols {
                    for row in 0..<rows {
                        let x = CGFloat(col) * spacing + offsetX
                        let y = CGFloat(row) * spacing + offsetY
                        guard x >= -spacing, x <= size.width + spacing,
                              y >= -spacing, y <= size.height + spacing else { continue }
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                            with: .color(.secondary.opacity(0.15))
                        )
                    }
                }
            }
            .allowsHitTesting(false)

            if canvasData.nodes.isEmpty {
                Text("Double-click to add a text node")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedNodeId = nil
            editingNodeId = nil
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                addTextNode(at: canvasCenter)
            }
        )
        .gesture(backgroundPanGesture)
        .gesture(zoomGesture)
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        ZStack {
            // Edges
            Canvas { context, _ in
                for edge in canvasData.edges {
                    guard let fromNode = canvasData.nodes.first(where: { $0.id == edge.fromNode }),
                          let toNode = canvasData.nodes.first(where: { $0.id == edge.toNode }) else { continue }

                    let fromPoint = anchorPoint(node: fromNode, side: edge.fromSide ?? "right")
                    let toPoint = anchorPoint(node: toNode, side: edge.toSide ?? "left")

                    var path = Path()
                    path.move(to: fromPoint)
                    path.addLine(to: toPoint)
                    context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)

                    if edge.toEnd == "arrow" {
                        drawArrowHead(context: &context, from: fromPoint, to: toPoint)
                    }
                }
            }
            .allowsHitTesting(false)

            // Nodes
            ForEach(canvasData.nodes) { node in
                canvasNodeView(node: node)
            }
        }
    }

    @ViewBuilder
    private func canvasNodeView(node: CanvasNodeMeta) -> some View {
        let isSelected = selectedNodeId == node.id
        let isEditing = editingNodeId == node.id

        CanvasBlockTextNodeView(
            text: nodeText(for: node.id),
            isEditing: isEditing,
            onTextChange: { newText in
                updateNodeText(id: node.id, text: newText)
            }
        )
        .frame(width: node.width, height: node.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .position(x: node.x + node.width / 2, y: node.y + node.height / 2)
        .onTapGesture {
            selectedNodeId = node.id
            editingNodeId = nil
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                selectedNodeId = node.id
                editingNodeId = node.id
            }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    moveNode(id: node.id, delta: value.translation)
                }
                .onEnded { value in
                    commitNodeMove(id: node.id, delta: value.translation)
                }
        )
    }

    // MARK: - Scroll Zoom Overlay

    private var scrollZoomOverlay: some View {
        CanvasBlockScrollZoomView(
            zoom: canvasData.viewport.zoom,
            onZoom: { deltaY, mouseLocation in
                let sensitivity: CGFloat = 0.01
                let oldZoom = canvasData.viewport.zoom
                guard oldZoom > 0 else { return }
                let newZoom = max(0.3, min(3.0, oldZoom + deltaY * sensitivity))
                canvasData.viewport.x += mouseLocation.x * (1 - newZoom / oldZoom)
                canvasData.viewport.y += mouseLocation.y * (1 - newZoom / oldZoom)
                canvasData.viewport.zoom = newZoom
                baseZoom = newZoom
                persistCanvas()
            }
        )
    }

    // MARK: - Gestures

    private var backgroundPanGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                panOffset = value.translation
            }
            .onEnded { value in
                canvasData.viewport.x += value.translation.width
                canvasData.viewport.y += value.translation.height
                panOffset = .zero
                persistCanvas()
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let oldZoom = canvasData.viewport.zoom
                guard oldZoom > 0 else { return }
                let newZoom = max(0.3, min(3.0, baseZoom * value.magnification))
                canvasData.viewport.x += lastMouseLocation.x * (1 - newZoom / oldZoom)
                canvasData.viewport.y += lastMouseLocation.y * (1 - newZoom / oldZoom)
                canvasData.viewport.zoom = newZoom
            }
            .onEnded { _ in
                baseZoom = canvasData.viewport.zoom
                persistCanvas()
            }
    }

    // MARK: - Canvas Center

    private var canvasCenter: CGPoint {
        CGPoint(
            x: (canvasSize.width / 2 - canvasData.viewport.x) / zoom,
            y: (canvasSize.height / 2 - canvasData.viewport.y) / zoom
        )
    }

    // MARK: - Node Operations

    /// Node text content — stored inline in the node's `file` field (repurposed for inline canvas).
    private func nodeText(for id: String) -> String {
        canvasData.nodes.first(where: { $0.id == id })?.file ?? ""
    }

    private func addTextNode(at position: CGPoint) {
        let id = "node_\(UUID().uuidString.prefix(8).lowercased())"
        let node = CanvasNodeMeta(
            id: id,
            type: .text,
            x: position.x - 75,
            y: position.y - 30,
            width: 150,
            height: 60,
            file: ""
        )
        canvasData.nodes.append(node)
        selectedNodeId = id
        editingNodeId = id
        persistCanvas()
    }

    private func deleteNode(id: String) {
        canvasData.nodes.removeAll { $0.id == id }
        canvasData.edges.removeAll { $0.fromNode == id || $0.toNode == id }
        if selectedNodeId == id { selectedNodeId = nil }
        if editingNodeId == id { editingNodeId = nil }
        persistCanvas()
    }

    @State private var dragStartPositions: [String: CGPoint] = [:]

    private func moveNode(id: String, delta: CGSize) {
        guard let idx = canvasData.nodes.firstIndex(where: { $0.id == id }) else { return }
        if dragStartPositions[id] == nil {
            dragStartPositions[id] = CGPoint(x: canvasData.nodes[idx].x, y: canvasData.nodes[idx].y)
        }
        if let start = dragStartPositions[id] {
            canvasData.nodes[idx].x = start.x + delta.width / zoom
            canvasData.nodes[idx].y = start.y + delta.height / zoom
        }
    }

    private func commitNodeMove(id: String, delta: CGSize) {
        guard let idx = canvasData.nodes.firstIndex(where: { $0.id == id }) else { return }
        if let start = dragStartPositions[id] {
            canvasData.nodes[idx].x = start.x + delta.width / zoom
            canvasData.nodes[idx].y = start.y + delta.height / zoom
        }
        dragStartPositions.removeValue(forKey: id)
        persistCanvas()
    }

    private func updateNodeText(id: String, text: String) {
        guard let idx = canvasData.nodes.firstIndex(where: { $0.id == id }) else { return }
        canvasData.nodes[idx].file = text
        persistCanvas()
    }

    // MARK: - Helpers

    private func anchorPoint(node: CanvasNodeMeta, side: String) -> CGPoint {
        switch side {
        case "top": return CGPoint(x: node.x + node.width / 2, y: node.y)
        case "right": return CGPoint(x: node.x + node.width, y: node.y + node.height / 2)
        case "bottom": return CGPoint(x: node.x + node.width / 2, y: node.y + node.height)
        case "left": return CGPoint(x: node.x, y: node.y + node.height / 2)
        default: return CGPoint(x: node.x + node.width / 2, y: node.y + node.height / 2)
        }
    }

    private func drawArrowHead(context: inout GraphicsContext, from: CGPoint, to: CGPoint) {
        let arrowLength: CGFloat = 10
        let arrowAngle: CGFloat = .pi / 6
        let angle = atan2(to.y - from.y, to.x - from.x)
        let p1 = CGPoint(x: to.x - arrowLength * cos(angle - arrowAngle), y: to.y - arrowLength * sin(angle - arrowAngle))
        let p2 = CGPoint(x: to.x - arrowLength * cos(angle + arrowAngle), y: to.y - arrowLength * sin(angle + arrowAngle))
        var arrowPath = Path()
        arrowPath.move(to: to)
        arrowPath.addLine(to: p1)
        arrowPath.addLine(to: p2)
        arrowPath.closeSubpath()
        context.fill(arrowPath, with: .color(.secondary.opacity(0.4)))
    }

    // MARK: - Persistence

    private func persistCanvas() {
        let json = canvasData.toJSON()
        document.updateBlockProperty(id: block.id) { $0.text = json }
    }
}

// MARK: - Text Node View

private struct CanvasBlockTextNodeView: View {
    let text: String
    let isEditing: Bool
    var onTextChange: (String) -> Void

    @State private var editText: String = ""

    var body: some View {
        if isEditing {
            TextEditor(text: $editText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .onAppear { editText = text }
                .onChange(of: editText) { _, newVal in
                    onTextChange(newVal)
                }
        } else {
            Text(text.isEmpty ? "Type here..." : text)
                .font(.system(size: 13))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Scroll Wheel Zoom

private struct CanvasBlockScrollZoomView: NSViewRepresentable {
    let zoom: CGFloat
    let onZoom: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> CanvasBlockScrollNSView {
        let view = CanvasBlockScrollNSView()
        view.onCmdScroll = onZoom
        return view
    }

    func updateNSView(_ nsView: CanvasBlockScrollNSView, context: Context) {
        nsView.onCmdScroll = onZoom
    }
}

private class CanvasBlockScrollNSView: NSView {
    var onCmdScroll: ((CGFloat, CGPoint) -> Void)?

    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let locationInView = convert(event.locationInWindow, from: nil)
            onCmdScroll?(event.scrollingDeltaY, locationInView)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
