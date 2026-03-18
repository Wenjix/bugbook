import Foundation

/// Lightweight wrapper for inline canvas block JSON stored in the block's `text` field.
/// Reuses the same node/edge/viewport types as the standalone CanvasDocument.
struct CanvasBlockData: Codable {
    var nodes: [CanvasNodeMeta]
    var edges: [CanvasEdgeMeta]
    var viewport: CanvasViewport

    init(nodes: [CanvasNodeMeta] = [], edges: [CanvasEdgeMeta] = [], viewport: CanvasViewport = CanvasViewport(x: 0, y: 0, zoom: 1.0)) {
        self.nodes = nodes
        self.edges = edges
        self.viewport = viewport
    }

    /// Decode from a JSON string (block's text field). Returns default empty canvas on failure.
    static func from(json: String) -> CanvasBlockData {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CanvasBlockData.self, from: data) else {
            return CanvasBlockData()
        }
        return decoded
    }

    /// Encode to a compact JSON string for storage in the block's text field.
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
