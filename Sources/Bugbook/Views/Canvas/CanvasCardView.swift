import SwiftUI

struct CanvasCardView: View {
    var document: CanvasDocument
    let node: CanvasNodeMeta
    let zoom: CGFloat
    var onNavigateToFile: ((String) -> Void)?

    @State private var isDragging = false
    @State private var isResizing = false
    @State private var dragStart: CGPoint = .zero
    @State private var resizeStart: CGSize = .zero
    @State private var isEditingLabel = false
    @State private var editingLabelText = ""
    @State private var pagePreview: PagePreview?

    private var isSelected: Bool { document.selectedNodeIds.contains(node.id) }
    private var isEditing: Bool { document.editingNodeId == node.id }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if node.type.isShape {
                shapeContent
                    .frame(width: node.width, height: node.height)
            } else {
                cardContent
                    .frame(width: node.width, height: node.height)
                    .background(cardBackground)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }

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
                case .rectangle, .roundedRect, .ellipse, .diamond:
                    isEditingLabel = true
                    editingLabelText = node.file ?? ""
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
        case .rectangle, .roundedRect, .ellipse, .diamond:
            EmptyView() // shapes rendered by shapeContent
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
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(12)
                } else {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
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
        VStack(alignment: .leading, spacing: 0) {
            // Header: icon + title + navigation arrow
            HStack(spacing: 8) {
                pageIconView(pagePreview?.icon)
                    .frame(width: 20, height: 20)
                Text(document.fileNodeDisplayName(for: node))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Content preview (first 2-3 lines)
            if let preview = pagePreview, !preview.contentLines.isEmpty {
                Divider()
                    .padding(.horizontal, 12)
                Text(preview.contentLines.joined(separator: "\n"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear { loadPagePreview() }
    }

    @ViewBuilder
    private func pageIconView(_ icon: String?) -> some View {
        if let icon = icon, !icon.isEmpty {
            if icon.hasPrefix("custom:") {
                let path = String(icon.dropFirst(7))
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            } else if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 16))
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func loadPagePreview() {
        guard node.type == .file, let resolvedPath = document.resolveFilePath(for: node) else { return }
        // For .md files, read the file and parse metadata + first few content lines
        let filePath: String
        if FileManager.default.fileExists(atPath: resolvedPath) {
            filePath = resolvedPath
        } else if !resolvedPath.hasSuffix(".md"),
                  FileManager.default.fileExists(atPath: resolvedPath + ".md") {
            filePath = resolvedPath + ".md"
        } else {
            return
        }
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }
        let (metadata, body) = MarkdownBlockParser.parseMetadata(content)
        // Grab the first 3 non-empty, non-metadata, non-heading content lines
        let lines = body.components(separatedBy: "\n")
        var previewLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("<!--") { continue }
            // Strip heading markers for preview
            if trimmed.hasPrefix("#") {
                continue
            }
            // Strip markdown formatting for cleaner preview
            var clean = trimmed
            // Remove leading list markers
            if let bullet = clean.firstIndex(of: "-"), clean[clean.startIndex...bullet].allSatisfy({ $0 == " " || $0 == "-" }) {
                clean = String(clean[clean.index(after: bullet)...]).trimmingCharacters(in: .whitespaces)
            }
            previewLines.append(clean)
            if previewLines.count >= 3 { break }
        }
        pagePreview = PagePreview(icon: metadata.icon, contentLines: previewLines)
    }

    @ViewBuilder
    private var imageCardContent: some View {
        if let file = node.file {
            let imagePath = (document.canvasPath as NSString).appendingPathComponent(file)
            if let nsImage = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .contentShape(Rectangle())
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Image not found")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Shape Content

    @ViewBuilder
    private var shapeContent: some View {
        let fillColor = canvasColor(node.color ?? "blue").opacity(0.15)
        let strokeColor = isSelected ? Color.accentColor : canvasColor(node.borderColor ?? node.color ?? "blue")

        ZStack {
            shapeFillAndStroke(fill: fillColor, stroke: strokeColor)

            // Label
            if isEditingLabel {
                TextField("Label", text: $editingLabelText, onCommit: {
                    document.updateShapeLabel(id: node.id, label: editingLabelText)
                    isEditingLabel = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .padding(16)
                .onExitCommand { isEditingLabel = false }
            } else if let label = node.file, !label.isEmpty {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(16)
            }
        }
    }

    @ViewBuilder
    private func shapeFillAndStroke(fill: Color, stroke: Color) -> some View {
        let lineWidth: CGFloat = isSelected ? 2.5 : 1.5
        switch node.type {
        case .rectangle:
            Rectangle().fill(fill)
            Rectangle().stroke(stroke, lineWidth: lineWidth)
        case .roundedRect:
            RoundedRectangle(cornerRadius: 12).fill(fill)
            RoundedRectangle(cornerRadius: 12).stroke(stroke, lineWidth: lineWidth)
        case .ellipse:
            Ellipse().fill(fill)
            Ellipse().stroke(stroke, lineWidth: lineWidth)
        case .diamond:
            DiamondShape().fill(fill)
            DiamondShape().stroke(stroke, lineWidth: lineWidth)
        default:
            EmptyView()
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
            .clipShape(.rect(cornerRadius: 2))
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

// MARK: - Page Preview

private struct PagePreview {
    let icon: String?
    let contentLines: [String]
}

// MARK: - TextEditor Wrapper

private struct TextEditorWrapper: View {
    @Binding var text: String
    var onCommit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onKeyPress(.escape) {
                onCommit()
                return .handled
            }
    }
}

// MARK: - Diamond Shape

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
