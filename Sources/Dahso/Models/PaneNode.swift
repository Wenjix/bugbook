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
        var tabs: [PaneContent]
        var selectedTabIndex: Int

        init(id: UUID, tabs: [PaneContent], selectedTabIndex: Int = 0) {
            self.id = id
            self.tabs = tabs.isEmpty ? [.emptyDocument()] : tabs
            self.selectedTabIndex = selectedTabIndex
            normalizeSelection()
        }

        init(id: UUID, content: PaneContent) {
            self.init(id: id, tabs: [content], selectedTabIndex: 0)
        }

        var content: PaneContent { activeContent }

        var activeContent: PaneContent {
            tabs[selectedTabIndex]
        }

        var activeTabID: UUID {
            activeContent.id
        }

        var activeOpenFile: OpenFile? {
            activeContent.openFile
        }

        var hasMultipleTabs: Bool {
            tabs.count > 1
        }

        var containsDocumentContent: Bool {
            tabs.contains { $0.openFile != nil }
        }

        func tabIndex(for tabID: UUID) -> Int? {
            tabs.firstIndex { $0.id == tabID }
        }

        func contains(tabID: UUID) -> Bool {
            tabIndex(for: tabID) != nil
        }

        mutating func selectTab(at index: Int) {
            guard tabs.indices.contains(index) else { return }
            selectedTabIndex = index
        }

        mutating func selectTab(id tabID: UUID) {
            guard let index = tabIndex(for: tabID) else { return }
            selectedTabIndex = index
        }

        @discardableResult
        mutating func appendTab(_ content: PaneContent, select: Bool = true) -> Bool {
            guard activeContent.supportsPaneTabs, content.supportsPaneTabs else { return false }
            tabs.append(content)
            if select {
                selectedTabIndex = tabs.count - 1
            } else {
                normalizeSelection()
            }
            return true
        }

        @discardableResult
        mutating func removeTab(at index: Int) -> PaneContent? {
            guard tabs.indices.contains(index) else { return nil }
            let removed = tabs.remove(at: index)
            if tabs.isEmpty {
                selectedTabIndex = 0
            } else if selectedTabIndex >= tabs.count {
                selectedTabIndex = tabs.count - 1
            } else if index < selectedTabIndex {
                selectedTabIndex -= 1
            }
            return removed
        }

        @discardableResult
        mutating func removeTab(id tabID: UUID) -> PaneContent? {
            guard let index = tabIndex(for: tabID) else { return nil }
            return removeTab(at: index)
        }

        mutating func replaceActiveContent(with content: PaneContent) {
            guard tabs.indices.contains(selectedTabIndex) else {
                tabs = [content]
                selectedTabIndex = 0
                return
            }
            tabs[selectedTabIndex] = content
        }

        mutating func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
            guard sourceIndex != destinationIndex,
                  sourceIndex >= 0, sourceIndex < tabs.count,
                  destinationIndex >= 0, destinationIndex <= tabs.count else { return }

            let selectedTabID = activeTabID
            let tab = tabs.remove(at: sourceIndex)
            let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
            tabs.insert(tab, at: adjustedDestination)
            selectTab(id: selectedTabID)
        }

        mutating func normalizeSelection() {
            if tabs.isEmpty {
                tabs = [.emptyDocument()]
            }
            selectedTabIndex = min(max(selectedTabIndex, 0), tabs.count - 1)
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case tabs
            case selectedTabIndex
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            if let tabs = try container.decodeIfPresent([PaneContent].self, forKey: .tabs), !tabs.isEmpty {
                self.tabs = tabs
                selectedTabIndex = try container.decodeIfPresent(Int.self, forKey: .selectedTabIndex) ?? 0
            } else {
                let content = try container.decode(PaneContent.self, forKey: .content)
                self.tabs = [content]
                selectedTabIndex = 0
            }
            normalizeSelection()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(tabs, forKey: .tabs)
            try container.encode(selectedTabIndex, forKey: .selectedTabIndex)
        }
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

    /// First document leaf in depth-first order (short-circuits without materializing the full tree).
    var firstDocumentLeaf: Leaf? {
        switch self {
        case .leaf(let leaf):
            if leaf.containsDocumentContent { return leaf }
            return nil
        case .split(let split):
            return split.first.firstDocumentLeaf ?? split.second.firstDocumentLeaf
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
            var updatedLeaf = leaf
            updatedLeaf.replaceActiveContent(with: content)
            return .leaf(updatedLeaf)
        case .split(let split):
            let newFirst = split.first.updatingLeafContent(leafId: leafId, content: content)
            let newSecond = split.second.updatingLeafContent(leafId: leafId, content: content)
            return .split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: newFirst, second: newSecond))
        }
    }

    func updatingLeaf(id targetId: UUID, transform: (Leaf) -> Leaf) -> PaneNode {
        switch self {
        case .leaf(let leaf):
            guard leaf.id == targetId else { return self }
            return .leaf(transform(leaf))
        case .split(let split):
            let newFirst = split.first.updatingLeaf(id: targetId, transform: transform)
            let newSecond = split.second.updatingLeaf(id: targetId, transform: transform)
            return .split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: newFirst, second: newSecond))
        }
    }

    func findLeaf(containingTabId tabId: UUID) -> Leaf? {
        switch self {
        case .leaf(let leaf):
            return leaf.contains(tabID: tabId) ? leaf : nil
        case .split(let split):
            return split.first.findLeaf(containingTabId: tabId) ?? split.second.findLeaf(containingTabId: tabId)
        }
    }

    func updatingTabContent(tabId: UUID, transform: (PaneContent) -> PaneContent) -> PaneNode {
        switch self {
        case .leaf(let leaf):
            guard let index = leaf.tabIndex(for: tabId) else { return self }
            var updatedLeaf = leaf
            updatedLeaf.tabs[index] = transform(updatedLeaf.tabs[index])
            updatedLeaf.normalizeSelection()
            return .leaf(updatedLeaf)
        case .split(let split):
            let newFirst = split.first.updatingTabContent(tabId: tabId, transform: transform)
            let newSecond = split.second.updatingTabContent(tabId: tabId, transform: transform)
            return .split(Split(id: split.id, axis: split.axis, ratio: split.ratio, first: newFirst, second: newSecond))
        }
    }
}
