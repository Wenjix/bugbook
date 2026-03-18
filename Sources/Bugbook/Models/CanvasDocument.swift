import Foundation
import SwiftUI
import os
import Sentry

// MARK: - Canvas JSON Structs

struct CanvasViewport: Codable {
    var x: CGFloat
    var y: CGFloat
    var zoom: CGFloat
}

struct CanvasNodeMeta: Codable, Identifiable {
    let id: String
    var type: CanvasNodeType
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var file: String?      // relative path for file nodes
    var color: String?
}

enum CanvasNodeType: String, Codable {
    case text
    case file
    case image
}

struct CanvasEdgeMeta: Codable, Identifiable {
    let id: String
    var fromNode: String
    var toNode: String
    var fromSide: String?
    var toSide: String?
    var toEnd: String?
    var label: String?
    var color: String?
}

struct CanvasFileMeta: Codable {
    var id: String
    var name: String
    var version: Int
    var viewport: CanvasViewport
    var nodes: [CanvasNodeMeta]
    var edges: [CanvasEdgeMeta]
}

enum CanvasLoadResult {
    case loaded
    case newCanvas
    case corrupted(String)
}

// MARK: - CanvasDocument

@MainActor
@Observable
class CanvasDocument {
    var nodes: [CanvasNodeMeta] = []
    var edges: [CanvasEdgeMeta] = []
    var nodeTexts: [String: String] = [:]  // node_id → markdown content
    var viewport: CanvasViewport = CanvasViewport(x: 0, y: 0, zoom: 1.0)
    var selectedNodeIds: Set<String> = []
    var selectedEdgeId: String?
    var editingNodeId: String?
    private(set) var dragStartPositions: [String: CGPoint] = [:]

    /// Convenience: returns the single selected node ID (nil if 0 or 2+ selected)
    var selectedNodeId: String? {
        get { selectedNodeIds.count == 1 ? selectedNodeIds.first : nil }
        set {
            if let id = newValue {
                selectedNodeIds = [id]
            } else {
                selectedNodeIds.removeAll()
            }
        }
    }
    var isDirty: Bool = false
    var loadResult: CanvasLoadResult = .newCanvas

    @ObservationIgnored private(set) var canvasPath: String = ""
    @ObservationIgnored private(set) var canvasName: String = ""
    @ObservationIgnored private var canvasId: String = ""

    @ObservationIgnored private var undoStack: [CanvasState] = []
    @ObservationIgnored private var redoStack: [CanvasState] = []

    private struct CanvasState {
        let nodes: [CanvasNodeMeta]
        let edges: [CanvasEdgeMeta]
        let nodeTexts: [String: String]
    }

    // MARK: - Load / Save

    func load(from folderPath: String) {
        canvasPath = folderPath
        let metaPath = (folderPath as NSString).appendingPathComponent("_canvas.json")

        // Distinguish "no file" (new canvas) from "corrupted JSON"
        guard FileManager.default.fileExists(atPath: metaPath) else {
            canvasName = (folderPath as NSString).lastPathComponent
            canvasId = "canvas_\(UUID().uuidString.prefix(8).lowercased())"
            loadResult = .newCanvas
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: metaPath))
            let meta = try JSONDecoder().decode(CanvasFileMeta.self, from: data)

            canvasId = meta.id
            canvasName = meta.name
            viewport = meta.viewport
            nodes = meta.nodes
            edges = meta.edges

            // Load text content for text nodes
            for node in nodes where node.type == .text {
                let mdPath = (folderPath as NSString).appendingPathComponent("\(node.id).md")
                if let content = try? String(contentsOfFile: mdPath, encoding: .utf8) {
                    nodeTexts[node.id] = content
                } else {
                    nodeTexts[node.id] = ""
                }
            }

            loadResult = .loaded
            isDirty = false
            SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "canvas.load"))
        } catch {
            canvasName = (folderPath as NSString).lastPathComponent
            canvasId = ""
            loadResult = .corrupted(error.localizedDescription)
        }
    }

    func save() {
        guard !canvasPath.isEmpty else { return }
        if case .corrupted = loadResult { return }
        let metaPath = (canvasPath as NSString).appendingPathComponent("_canvas.json")

        let meta = CanvasFileMeta(
            id: canvasId,
            name: canvasName,
            version: 1,
            viewport: viewport,
            nodes: nodes,
            edges: edges
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(meta)
            try data.write(to: URL(fileURLWithPath: metaPath), options: .atomic)

            for node in nodes where node.type == .text {
                let mdPath = (canvasPath as NSString).appendingPathComponent("\(node.id).md")
                let content = nodeTexts[node.id] ?? ""
                try content.write(toFile: mdPath, atomically: true, encoding: .utf8)
            }

            isDirty = false
            SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "canvas.save"))
        } catch {
            Log.canvas.error("Save failed: \(error.localizedDescription)")
            SentrySDK.capture(error: error)
        }
    }

    // MARK: - ID Generation

    private func generateId(prefix: String) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let suffix = String((0..<6).map { _ in chars.randomElement()! })
        return "\(prefix)_\(suffix)"
    }

    // MARK: - Node CRUD

    func addTextNode(at position: CGPoint) {
        saveUndo()
        let id = generateId(prefix: "node")
        let node = CanvasNodeMeta(
            id: id,
            type: .text,
            x: position.x,
            y: position.y,
            width: 300,
            height: 200
        )
        nodes.append(node)
        nodeTexts[id] = ""
        selectedNodeId = id
        editingNodeId = id
        isDirty = true
    }

    func addFileNode(at position: CGPoint, filePath: String) {
        saveUndo()
        let id = generateId(prefix: "node")
        let relativePath = Self.relativePath(from: canvasPath, to: filePath)
        let node = CanvasNodeMeta(
            id: id,
            type: .file,
            x: position.x,
            y: position.y,
            width: 300,
            height: 80,
            file: relativePath
        )
        nodes.append(node)
        selectedNodeId = id
        isDirty = true
    }

    func addImageNode(at position: CGPoint, image: NSImage) {
        saveUndo()
        let id = generateId(prefix: "node")
        let filename = "\(id).png"
        let imagePath = (canvasPath as NSString).appendingPathComponent(filename)

        // Save image as PNG to canvas folder
        // Use CGImage path for broader format support (HEIC, etc.)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Log.canvas.error("Failed to get CGImage from NSImage")
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            Log.canvas.error("Failed to convert image to PNG")
            return
        }
        do {
            try pngData.write(to: URL(fileURLWithPath: imagePath), options: .atomic)
        } catch {
            Log.canvas.error("Failed to write image: \(error.localizedDescription)")
            return
        }

        // Size the node proportionally, capping width at 400
        let maxWidth: CGFloat = 400
        let scale = image.size.width > maxWidth ? maxWidth / image.size.width : 1.0
        let width = image.size.width * scale
        let height = image.size.height * scale

        let node = CanvasNodeMeta(
            id: id,
            type: .image,
            x: position.x,
            y: position.y,
            width: max(120, width),
            height: max(60, height),
            file: filename
        )
        nodes.append(node)
        selectedNodeId = id
        isDirty = true
    }

    func removeNode(id: String) {
        saveUndo()
        let removedNode = nodes.first { $0.id == id }
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.fromNode == id || $0.toNode == id }
        nodeTexts.removeValue(forKey: id)
        // Delete associated file for text/image nodes
        if let node = removedNode {
            if node.type == .text {
                let mdPath = (canvasPath as NSString).appendingPathComponent("\(id).md")
                try? FileManager.default.removeItem(atPath: mdPath)
            } else if node.type == .image, let file = node.file {
                let imgPath = (canvasPath as NSString).appendingPathComponent(file)
                try? FileManager.default.removeItem(atPath: imgPath)
            }
        }
        selectedNodeIds.remove(id)
        isDirty = true
    }

    func moveNode(id: String, to position: CGPoint) {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[idx].x = position.x
        nodes[idx].y = position.y
        isDirty = true
    }

    func moveSelectedNodes(delta: CGSize) {
        for id in selectedNodeIds {
            guard let start = dragStartPositions[id],
                  let idx = nodes.firstIndex(where: { $0.id == id }) else { continue }
            nodes[idx].x = start.x + delta.width
            nodes[idx].y = start.y + delta.height
        }
        isDirty = true
    }

    func storeDragStartPositions() {
        dragStartPositions = [:]
        for id in selectedNodeIds {
            if let node = nodes.first(where: { $0.id == id }) {
                dragStartPositions[id] = CGPoint(x: node.x, y: node.y)
            }
        }
    }

    func clearDragStartPositions() {
        dragStartPositions = [:]
    }

    func resizeNode(id: String, width: CGFloat, height: CGFloat) {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[idx].width = max(120, width)
        nodes[idx].height = max(60, height)
        isDirty = true
    }

    func updateNodeText(id: String, text: String) {
        nodeTexts[id] = text
        isDirty = true
    }

    // MARK: - Edge CRUD

    func addEdge(from: String, to: String, fromSide: String? = nil, toSide: String? = nil) {
        guard from != to else { return }
        // Don't add duplicate edges
        if edges.contains(where: { $0.fromNode == from && $0.toNode == to }) { return }
        saveUndo()
        let id = generateId(prefix: "edge")
        let edge = CanvasEdgeMeta(
            id: id,
            fromNode: from,
            toNode: to,
            fromSide: fromSide,
            toSide: toSide,
            toEnd: "arrow"
        )
        edges.append(edge)
        isDirty = true
    }

    func removeEdge(id: String) {
        saveUndo()
        edges.removeAll { $0.id == id }
        if selectedEdgeId == id { selectedEdgeId = nil }
        isDirty = true
    }

    // MARK: - Selection

    func clearSelection() {
        selectedNodeIds.removeAll()
        selectedEdgeId = nil
        editingNodeId = nil
    }

    func toggleNodeSelection(_ id: String) {
        if selectedNodeIds.contains(id) {
            selectedNodeIds.remove(id)
        } else {
            selectedNodeIds.insert(id)
        }
        selectedEdgeId = nil
    }

    func deleteSelection() {
        if !selectedNodeIds.isEmpty {
            for nodeId in selectedNodeIds {
                removeNode(id: nodeId)
            }
        } else if let edgeId = selectedEdgeId {
            removeEdge(id: edgeId)
        }
    }

    // MARK: - Undo/Redo

    private func saveUndo() {
        undoStack.append(CanvasState(nodes: nodes, edges: edges, nodeTexts: nodeTexts))
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(CanvasState(nodes: nodes, edges: edges, nodeTexts: nodeTexts))
        nodes = prev.nodes
        edges = prev.edges
        nodeTexts = prev.nodeTexts
        isDirty = true
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(CanvasState(nodes: nodes, edges: edges, nodeTexts: nodeTexts))
        nodes = next.nodes
        edges = next.edges
        nodeTexts = next.nodeTexts
        isDirty = true
    }

    // MARK: - File Node Resolution

    /// Resolve a file node's relative path to an absolute path
    func resolveFilePath(for node: CanvasNodeMeta) -> String? {
        guard let file = node.file else { return nil }
        if file.hasPrefix("/") { return file }
        // Relative paths are stored relative to the canvas folder itself
        let resolved = (canvasPath as NSString).appendingPathComponent(file)
        return URL(fileURLWithPath: resolved).standardizedFileURL.path
    }

    /// Get display name for a file node
    func fileNodeDisplayName(for node: CanvasNodeMeta) -> String {
        guard let file = node.file else { return "Unknown" }
        let name = (file as NSString).lastPathComponent
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    /// Compute a relative path from the canvas folder to a target file.
    static func relativePath(from canvasFolder: String, to filePath: String) -> String {
        let canvasComponents = canvasFolder.components(separatedBy: "/").filter { !$0.isEmpty }
        let fileComponents = filePath.components(separatedBy: "/").filter { !$0.isEmpty }

        // Find common prefix length
        var commonLength = 0
        while commonLength < canvasComponents.count && commonLength < fileComponents.count
                && canvasComponents[commonLength] == fileComponents[commonLength] {
            commonLength += 1
        }

        // Number of ".." to go up from canvas folder to common ancestor
        let ups = canvasComponents.count - commonLength
        var parts = Array(repeating: "..", count: ups)
        // Append remaining file path components
        parts.append(contentsOf: fileComponents[commonLength...])
        return parts.joined(separator: "/")
    }
}
