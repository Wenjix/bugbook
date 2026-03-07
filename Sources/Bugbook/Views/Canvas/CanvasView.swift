import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CanvasView: View {
    @ObservedObject var document: CanvasDocument
    var onNavigateToFile: ((String) -> Void)?
    var availablePages: [FileEntry] = []

    @State private var panOffset: CGSize = .zero
    @State private var isPanning = false
    @State private var showFilePicker = false
    @State private var baseZoom: CGFloat = 1.0
    @State private var dropTargetActive = false

    private var zoom: CGFloat { document.viewport.zoom }

    var body: some View {
        ZStack {
            // Canvas background
            canvasBackground

            // Viewport-transformed content
            canvasContent
                .scaleEffect(zoom)
                .offset(
                    x: document.viewport.x + panOffset.width,
                    y: document.viewport.y + panOffset.height
                )

            // Error overlay for corrupted canvas
            if case .corrupted(let message) = document.loadResult {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("Canvas data is corrupted")
                        .font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                    Text("The original file has been preserved.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            // Floating toolbar
            VStack {
                Spacer()
                CanvasToolbar(
                    document: document,
                    onAddFilePicker: { showFilePicker = true },
                    onAddImage: { pickImageFromDisk() }
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
            }
        }
        .clipped()
        .overlay(CanvasScrollZoomView(document: document, baseZoom: $baseZoom))
        .onKeyPress(.delete) {
            deleteSelected()
            return .handled
        }
        .onKeyPress(.init(Character(UnicodeScalar(127)))) { // backspace
            deleteSelected()
            return .handled
        }
        .focusable()
        .focusEffectDisabled()
        .onCommand(#selector(UndoManager.undo)) { document.undo() }
        .onCommand(#selector(UndoManager.redo)) { document.redo() }
        .onPasteCommand(of: [UTType.png, UTType.tiff, UTType.image]) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data = data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        let x = -document.viewport.x + 400
                        let y = -document.viewport.y + 300
                        document.addImageNode(at: CGPoint(x: x, y: y), image: image)
                    }
                }
            }
        }
        .task { baseZoom = document.viewport.zoom }
        .task(id: document.isDirty) {
            guard document.isDirty else { return }
            try? await Task.sleep(for: .seconds(1))
            document.save()
        }
        .onDisappear {
            if document.isDirty { document.save() }
        }
        .sheet(isPresented: $showFilePicker) {
            CanvasFilePickerView(
                pages: availablePages,
                onSelect: { entry in
                    let x = -document.viewport.x + 400
                    let y = -document.viewport.y + 300
                    document.addFileNode(at: CGPoint(x: x, y: y), filePath: entry.path)
                    showFilePicker = false
                },
                onDismiss: { showFilePicker = false }
            )
        }
    }

    // MARK: - Background

    private var canvasBackground: some View {
        ZStack {
            Color.fallbackEditorBg

            // Dot grid pattern
            Canvas { context, size in
                let spacing: CGFloat = 24 * zoom
                guard spacing > 6 else { return } // hide dots when too zoomed out
                let offsetX = document.viewport.x.truncatingRemainder(dividingBy: spacing) + panOffset.width.truncatingRemainder(dividingBy: spacing)
                let offsetY = document.viewport.y.truncatingRemainder(dividingBy: spacing) + panOffset.height.truncatingRemainder(dividingBy: spacing)
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

            // Empty state hint
            if document.nodes.isEmpty {
                VStack(spacing: 8) {
                    Text("Drag from below or double click")
                    Text("Space + Drag to pan")
                    Text("\u{2318} + Scroll to zoom")
                }
                .font(.system(size: 15))
                .foregroundColor(.secondary.opacity(0.5))
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            document.clearSelection()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                // Double-click creates a text node at the location
                let x = -document.viewport.x + 400
                let y = -document.viewport.y + 300
                document.addTextNode(at: CGPoint(x: x, y: y))
            }
        )
        .gesture(backgroundPanGesture)
        .gesture(zoomGesture)
        .onDrop(of: [.fileURL, .image, .png, .tiff, .jpeg], isTargeted: $dropTargetActive) { providers, location in
            for provider in providers {
                // Try loading as a file URL first (drag from Finder)
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil),
                              let image = NSImage(contentsOf: url) else { return }
                        DispatchQueue.main.async {
                            let x = -document.viewport.x + location.x / document.viewport.zoom
                            let y = -document.viewport.y + location.y / document.viewport.zoom
                            document.addImageNode(at: CGPoint(x: x, y: y), image: image)
                        }
                    }
                    return true
                }
                // Try loading as image data directly
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data = data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        let x = -document.viewport.x + location.x / document.viewport.zoom
                        let y = -document.viewport.y + location.y / document.viewport.zoom
                        document.addImageNode(at: CGPoint(x: x, y: y), image: image)
                    }
                }
            }
            return true
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        ZStack {
            // Edge layer
            Canvas { context, size in
                for edge in document.edges {
                    guard let fromNode = document.nodes.first(where: { $0.id == edge.fromNode }),
                          let toNode = document.nodes.first(where: { $0.id == edge.toNode }) else { continue }

                    let isSelected = document.selectedEdgeId == edge.id
                    let fromPoint = anchorPoint(node: fromNode, side: edge.fromSide ?? "right")
                    let toPoint = anchorPoint(node: toNode, side: edge.toSide ?? "left")

                    var path = Path()
                    path.move(to: fromPoint)
                    path.addLine(to: toPoint)

                    context.stroke(
                        path,
                        with: .color(isSelected ? .accentColor : .secondary.opacity(0.4)),
                        lineWidth: isSelected ? 2 : 1.5
                    )

                    // Arrow head
                    if edge.toEnd == "arrow" {
                        drawArrowHead(context: &context, from: fromPoint, to: toPoint, isSelected: isSelected)
                    }

                    // Label
                    if let label = edge.label, !label.isEmpty {
                        let midPoint = CGPoint(
                            x: (fromPoint.x + toPoint.x) / 2,
                            y: (fromPoint.y + toPoint.y) / 2 - 12
                        )
                        let text = Text(label)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        context.draw(context.resolve(text), at: midPoint, anchor: .center)
                    }
                }
            }
            .allowsHitTesting(false)

            // Edge hit test overlay (invisible wider lines for easier clicking)
            ForEach(document.edges) { edge in
                if let fromNode = document.nodes.first(where: { $0.id == edge.fromNode }),
                   let toNode = document.nodes.first(where: { $0.id == edge.toNode }) {
                    let fromPoint = anchorPoint(node: fromNode, side: edge.fromSide ?? "right")
                    let toPoint = anchorPoint(node: toNode, side: edge.toSide ?? "left")
                    Path { path in
                        path.move(to: fromPoint)
                        path.addLine(to: toPoint)
                    }
                    .stroke(Color.clear, lineWidth: 10)
                    .contentShape(
                        Path { path in
                            path.move(to: fromPoint)
                            path.addLine(to: toPoint)
                        }.strokedPath(StrokeStyle(lineWidth: 10))
                    )
                    .onTapGesture {
                        document.selectedNodeId = nil
                        document.selectedEdgeId = edge.id
                    }
                }
            }

            // Node layer
            ForEach(document.nodes) { node in
                CanvasCardView(
                    document: document,
                    node: node,
                    zoom: zoom,
                    onNavigateToFile: onNavigateToFile
                )
            }
        }
    }

    // MARK: - Gestures

    private var backgroundPanGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                panOffset = value.translation
            }
            .onEnded { value in
                document.viewport.x += value.translation.width
                document.viewport.y += value.translation.height
                panOffset = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                document.viewport.zoom = max(0.3, min(3.0, baseZoom * value.magnification))
            }
            .onEnded { _ in
                baseZoom = document.viewport.zoom
            }
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

    private func drawArrowHead(context: inout GraphicsContext, from: CGPoint, to: CGPoint, isSelected: Bool) {
        let arrowLength: CGFloat = 10
        let arrowAngle: CGFloat = .pi / 6
        let angle = atan2(to.y - from.y, to.x - from.x)

        let p1 = CGPoint(
            x: to.x - arrowLength * cos(angle - arrowAngle),
            y: to.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: to.x - arrowLength * cos(angle + arrowAngle),
            y: to.y - arrowLength * sin(angle + arrowAngle)
        )

        var arrowPath = Path()
        arrowPath.move(to: to)
        arrowPath.addLine(to: p1)
        arrowPath.addLine(to: p2)
        arrowPath.closeSubpath()

        context.fill(
            arrowPath,
            with: .color(isSelected ? .accentColor : .secondary.opacity(0.4))
        )
    }

    private func pickImageFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let image = NSImage(contentsOf: url) else { return }
        let x = -document.viewport.x + 400
        let y = -document.viewport.y + 300
        document.addImageNode(at: CGPoint(x: x, y: y), image: image)
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        // Check for image data on the pasteboard
        guard let imageType = pb.availableType(from: [.tiff, .png]),
              let data = pb.data(forType: imageType),
              let image = NSImage(data: data) else { return }

        let x = -document.viewport.x + 400
        let y = -document.viewport.y + 300
        document.addImageNode(at: CGPoint(x: x, y: y), image: image)
    }

    private func deleteSelected() {
        document.deleteSelection()
    }
}

// MARK: - File Picker for Canvas

struct CanvasFilePickerView: View {
    let pages: [FileEntry]
    var onSelect: (FileEntry) -> Void
    var onDismiss: () -> Void

    @State private var searchText = ""

    private var filteredPages: [FileEntry] {
        let flat = flattenEntries(pages)
        if searchText.isEmpty { return flat }
        return flat.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Link a Page")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding()

            TextField("Search pages...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filteredPages, id: \.id) { entry in
                Button(action: { onSelect(entry) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                        Text(entry.name.replacingOccurrences(of: ".md", with: ""))
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 300)
        }
        .frame(width: 400)
        .padding(.bottom)
    }

    private func flattenEntries(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries {
            if !entry.isDirectory && !entry.isDatabase && !entry.isCanvas {
                result.append(entry)
            }
            if let children = entry.children {
                result.append(contentsOf: flattenEntries(children))
            }
        }
        return result
    }
}

// MARK: - Scroll Wheel Zoom (Cmd+Scroll)

private struct CanvasScrollZoomView: NSViewRepresentable {
    @ObservedObject var document: CanvasDocument
    @Binding var baseZoom: CGFloat

    private var zoomHandler: (CGFloat) -> Void {
        { [document, baseZoom = _baseZoom] deltaY in
            let sensitivity: CGFloat = 0.01
            let newZoom = max(0.3, min(3.0, document.viewport.zoom + deltaY * sensitivity))
            document.viewport.zoom = newZoom
            baseZoom.wrappedValue = newZoom
        }
    }

    func makeNSView(context: Context) -> CanvasScrollCaptureNSView {
        let view = CanvasScrollCaptureNSView()
        view.onCmdScroll = zoomHandler
        return view
    }

    func updateNSView(_ nsView: CanvasScrollCaptureNSView, context: Context) {
        nsView.onCmdScroll = zoomHandler
    }
}

private class CanvasScrollCaptureNSView: NSView {
    var onCmdScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            onCmdScroll?(event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
