import Foundation

/// A recursive tree where each leaf is a content pane and each internal
/// node is a horizontal or vertical split with a draggable ratio.
indirect enum PaneNode: Identifiable, Codable, Equatable {
    case leaf(Leaf)
    case split(Split)

    var id: UUID {
        switch self {
        case .leaf(let leaf): return leaf.id
        case .split(let split): return split.id
        }
    }

    struct Leaf: Identifiable, Codable, Equatable {
        let id: UUID
        var content: PaneContent
    }

    struct Split: Identifiable, Codable, Equatable {
        let id: UUID
        var axis: Axis
        var ratio: Double
        var first: PaneNode
        var second: PaneNode

        enum Axis: String, Codable, Equatable {
            case horizontal   // children laid out left | right
            case vertical     // children laid out top / bottom
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case leaf
        case split
    }

    private enum NodeType: String, Codable {
        case leaf
        case split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)
        switch type {
        case .leaf:
            let leaf = try container.decode(Leaf.self, forKey: .leaf)
            self = .leaf(leaf)
        case .split:
            let split = try container.decode(Split.self, forKey: .split)
            self = .split(split)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let leaf):
            try container.encode(NodeType.leaf, forKey: .type)
            try container.encode(leaf, forKey: .leaf)
        case .split(let split):
            try container.encode(NodeType.split, forKey: .type)
            try container.encode(split, forKey: .split)
        }
    }

    // MARK: - Tree Queries

    /// Find a leaf by its ID anywhere in the tree.
    func findLeaf(id: UUID) -> Leaf? {
        switch self {
        case .leaf(let leaf):
            return leaf.id == id ? leaf : nil
        case .split(let split):
            return split.first.findLeaf(id: id) ?? split.second.findLeaf(id: id)
        }
    }

    /// The first leaf in depth-first order.
    var firstLeaf: Leaf? {
        switch self {
        case .leaf(let leaf): return leaf
        case .split(let split): return split.first.firstLeaf
        }
    }

    /// All leaves flattened in depth-first order.
    var allLeaves: [Leaf] {
        switch self {
        case .leaf(let leaf): return [leaf]
        case .split(let split): return split.first.allLeaves + split.second.allLeaves
        }
    }

    /// Replace the leaf at `targetId` with a split containing the original leaf and a new sibling.
    func insertingSplit(
        replacing targetId: UUID,
        axis: Split.Axis,
        newSibling: PaneNode
    ) -> PaneNode {
        switch self {
        case .leaf(let leaf):
            guard leaf.id == targetId else { return self }
            return .split(Split(
                id: UUID(),
                axis: axis,
                ratio: 0.5,
                first: self,
                second: newSibling
            ))
        case .split(let split):
            let newFirst = split.first.insertingSplit(replacing: targetId, axis: axis, newSibling: newSibling)
            if newFirst != split.first {
                return .split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: newFirst, second: split.second))
            }
            let newSecond = split.second.insertingSplit(replacing: targetId, axis: axis, newSibling: newSibling)
            return .split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: split.first, second: newSecond))
        }
    }

    /// Remove a leaf by ID. Returns the new tree (or nil if the tree is now empty)
    /// and the ID of the sibling that took its place.
    func removingLeaf(id: UUID) -> (tree: PaneNode?, siblingId: UUID?) {
        switch self {
        case .leaf(let leaf):
            if leaf.id == id { return (nil, nil) }
            return (self, nil)
        case .split(let split):
            // If the target is a direct child, collapse the split
            if case .leaf(let left) = split.first, left.id == id {
                return (split.second, split.second.firstLeaf?.id)
            }
            if case .leaf(let right) = split.second, right.id == id {
                return (split.first, split.first.firstLeaf?.id)
            }
            // Recurse into children
            let (newFirst, sibId1) = split.first.removingLeaf(id: id)
            if let newFirst, newFirst != split.first {
                return (.split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: newFirst, second: split.second)), sibId1)
            }
            let (newSecond, sibId2) = split.second.removingLeaf(id: id)
            if let newSecond, newSecond != split.second {
                return (.split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: split.first, second: newSecond)), sibId2)
            }
            return (self, nil)
        }
    }

    /// Update the ratio of a specific split node.
    func updatingRatio(splitId: UUID, ratio: Double) -> PaneNode {
        switch self {
        case .leaf: return self
        case .split(let split):
            if split.id == splitId {
                return .split(Split(id: split.id, axis: split.axis, ratio: ratio, first: split.first, second: split.second))
            }
            let newFirst = split.first.updatingRatio(splitId: splitId, ratio: ratio)
            let newSecond = split.second.updatingRatio(splitId: splitId, ratio: ratio)
            return .split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: newFirst, second: newSecond))
        }
    }

    /// Replace the content of a specific leaf.
    func updatingLeafContent(leafId: UUID, content: PaneContent) -> PaneNode {
        switch self {
        case .leaf(let leaf):
            guard leaf.id == leafId else { return self }
            return .leaf(Leaf(id: leaf.id, content: content))
        case .split(let split):
            let newFirst = split.first.updatingLeafContent(leafId: leafId, content: content)
            let newSecond = split.second.updatingLeafContent(leafId: leafId, content: content)
            return .split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: newFirst, second: newSecond))
        }
    }
}
