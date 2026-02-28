import SwiftUI

// MARK: - Data Model

struct GraphNode: Identifiable {
    let id: String       // file path
    let name: String     // page display name
    var position: CGPoint
    var velocity: CGPoint = .zero
    var connectionCount: Int = 0
}

struct GraphEdge: Identifiable {
    let source: String   // source node id (file path)
    let target: String   // target node id (file path)
    var isParentChild: Bool = false
    var id: String { "\(source)→\(target)\(isParentChild ? ":pc" : "")" }
}

// MARK: - Force Simulation

@MainActor
class ForceSimulation: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []

    private var timer: Timer?
    private var settledFrames = 0
    private let settleThreshold: CGFloat = 0.3
    private let maxSettledFrames = 60

    func start() {
        settledFrames = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func tick() {
        guard !nodes.isEmpty else { return }

        let damping: CGFloat = 0.9
        let repulsionStrength: CGFloat = 8000
        let attractionStrength: CGFloat = 0.005
        let centerGravity: CGFloat = 0.01
        let maxRepulsionDist: CGFloat = 300

        // Build index for quick node lookup
        var nodeIndex: [String: Int] = [:]
        for i in nodes.indices {
            nodeIndex[nodes[i].id] = i
        }

        // Compute center
        let center = CGPoint(x: 0, y: 0)

        // Repulsion: all pairs push apart
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                guard dist < maxRepulsionDist else { continue }

                let force = repulsionStrength / (dist * dist)
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force

                nodes[i].velocity.x += fx
                nodes[i].velocity.y += fy
                nodes[j].velocity.x -= fx
                nodes[j].velocity.y -= fy
            }
        }

        // Attraction: connected nodes pull together
        for edge in edges {
            guard let si = nodeIndex[edge.source],
                  let ti = nodeIndex[edge.target] else { continue }

            let dx = nodes[ti].position.x - nodes[si].position.x
            let dy = nodes[ti].position.y - nodes[si].position.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let idealLength: CGFloat = 120

            let force = (dist - idealLength) * attractionStrength
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force

            nodes[si].velocity.x += fx
            nodes[si].velocity.y += fy
            nodes[ti].velocity.x -= fx
            nodes[ti].velocity.y -= fy
        }

        // Center gravity + apply velocity + damping
        var maxVel: CGFloat = 0
        for i in nodes.indices {
            // Gravity toward center
            nodes[i].velocity.x += (center.x - nodes[i].position.x) * centerGravity
            nodes[i].velocity.y += (center.y - nodes[i].position.y) * centerGravity

            // Damping
            nodes[i].velocity.x *= damping
            nodes[i].velocity.y *= damping

            // Apply
            nodes[i].position.x += nodes[i].velocity.x
            nodes[i].position.y += nodes[i].velocity.y

            let vel = sqrt(nodes[i].velocity.x * nodes[i].velocity.x + nodes[i].velocity.y * nodes[i].velocity.y)
            maxVel = max(maxVel, vel)
        }

        // Stop simulation when settled
        if maxVel < settleThreshold {
            settledFrames += 1
            if settledFrames >= maxSettledFrames {
                stop()
            }
        } else {
            settledFrames = 0
        }
    }
}

// MARK: - Graph Cache

private struct GraphCache {
    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var zoom: CGFloat
    var baseZoom: CGFloat
    var offset: CGSize
    var fileCount: Int
}

// MARK: - GraphView

struct GraphView: View {
    nonisolated(unsafe) private static var cache: [String: GraphCache] = [:]
    let backlinkService: BacklinkService
    let workspacePath: String
    let currentPagePath: String?
    var onNavigateToFile: ((String) -> Void)?

    @StateObject private var simulation = ForceSimulation()
    @State private var offset: CGSize = .zero
    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var hoveredNodeId: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.fallbackEditorBg

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let totalOffset = CGSize(
                        width: offset.width + dragOffset.width,
                        height: offset.height + dragOffset.height
                    )

                    // Index for O(1) lookups
                    let nodeById = Dictionary(uniqueKeysWithValues: simulation.nodes.map { ($0.id, $0) })

                    // Draw edges
                    for edge in simulation.edges {
                        guard let source = nodeById[edge.source],
                              let target = nodeById[edge.target] else { continue }

                        let isHighlighted = hoveredNodeId == edge.source || hoveredNodeId == edge.target

                        var path = Path()
                        let p1 = screenPoint(source.position, center: center, offset: totalOffset)
                        let p2 = screenPoint(target.position, center: center, offset: totalOffset)
                        path.move(to: p1)
                        path.addLine(to: p2)

                        if edge.isParentChild {
                            // Dashed line in muted color for parent-child
                            context.stroke(
                                path,
                                with: .color(isHighlighted ? .accentColor.opacity(0.5) : .secondary.opacity(0.15)),
                                style: StrokeStyle(
                                    lineWidth: isHighlighted ? 1.5 : 1.0,
                                    dash: [6, 4]
                                )
                            )
                        } else {
                            // Solid line for wiki-link edges
                            context.stroke(
                                path,
                                with: .color(isHighlighted ? .accentColor.opacity(0.6) : .secondary.opacity(0.2)),
                                lineWidth: isHighlighted ? 1.5 : 1.0
                            )
                        }
                    }

                    // Draw nodes
                    for node in simulation.nodes {
                        let screenPos = screenPoint(node.position, center: center, offset: totalOffset)
                        let radius = nodeRadius(for: node)
                        let isCurrentPage = node.id == currentPagePath
                        let isHovered = node.id == hoveredNodeId

                        let nodeRect = CGRect(
                            x: screenPos.x - radius,
                            y: screenPos.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )

                        let fillColor: Color = isCurrentPage ? .accentColor : (isHovered ? .accentColor.opacity(0.7) : .secondary.opacity(0.6))
                        context.fill(Circle().path(in: nodeRect), with: .color(fillColor))

                        // Label
                        let label = String(node.name.prefix(20))
                        let labelText = Text(label)
                            .font(.system(size: max(10, 11 * zoom)))
                            .foregroundColor(isCurrentPage ? .accentColor : .primary.opacity(0.8))
                        let labelPoint = CGPoint(x: screenPos.x, y: screenPos.y + radius + 8 * zoom)
                        context.draw(
                            context.resolve(labelText),
                            at: labelPoint,
                            anchor: .top
                        )
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                            dragOffset = .zero
                        }
                )
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = max(0.3, min(3.0, baseZoom * value.magnification))
                        }
                        .onEnded { _ in
                            baseZoom = zoom
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let totalOffset = CGSize(
                            width: offset.width + dragOffset.width,
                            height: offset.height + dragOffset.height
                        )
                        hoveredNodeId = hitTestNode(at: location, center: center, offset: totalOffset)
                    case .ended:
                        hoveredNodeId = nil
                    }
                }
                .onTapGesture { location in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    let totalOffset = CGSize(
                        width: offset.width + dragOffset.width,
                        height: offset.height + dragOffset.height
                    )
                    if let nodeId = hitTestNode(at: location, center: center, offset: totalOffset) {
                        onNavigateToFile?(nodeId)
                    }
                }
            }
        }
        .task {
            let currentFileCount = countWorkspaceFiles()
            if let cached = Self.cache[workspacePath],
               cached.fileCount == currentFileCount {
                simulation.nodes = cached.nodes
                simulation.edges = cached.edges
                zoom = cached.zoom
                baseZoom = cached.baseZoom
                offset = cached.offset
            } else {
                await buildGraph()
                simulation.start()
            }
        }
        .onDisappear {
            simulation.stop()
            Self.cache[workspacePath] = GraphCache(
                nodes: simulation.nodes,
                edges: simulation.edges,
                zoom: zoom,
                baseZoom: baseZoom,
                offset: offset,
                fileCount: countWorkspaceFiles()
            )
        }
    }

    // MARK: - Graph Building

    private func buildGraph() async {
        let workspace = workspacePath
        let service = backlinkService

        // File walk off main thread
        let filePaths: [String] = await Task.detached {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(atPath: workspace) else { return [String]() }
            // Pre-scan for database folders (contain _schema.json) and canvas folders (contain _canvas.json)
            var excludedDirs: Set<String> = []
            if let scanner = fm.enumerator(atPath: workspace) {
                while let rel = scanner.nextObject() as? String {
                    let filename = (rel as NSString).lastPathComponent
                    if filename == "_schema.json" || filename == "_canvas.json" {
                        let dir = (workspace as NSString).appendingPathComponent(
                            (rel as NSString).deletingLastPathComponent
                        )
                        excludedDirs.insert(dir)
                    }
                }
            }

            var paths: [String] = []
            while let relativePath = enumerator.nextObject() as? String {
                let components = relativePath.components(separatedBy: "/")
                if components.contains(where: { $0.hasPrefix(".") }) { continue }
                if components.contains(where: { $0.hasPrefix("_") }) { continue }
                let filename = (relativePath as NSString).lastPathComponent
                guard filename.hasSuffix(".md") else { continue }
                let fullPath = (workspace as NSString).appendingPathComponent(relativePath)
                // Skip database row files and canvas node files
                let parentDir = (fullPath as NSString).deletingLastPathComponent
                if excludedDirs.contains(parentDir) { continue }
                paths.append(fullPath)
            }
            return paths
        }.value

        // Build nodes
        var nodeMap: [String: GraphNode] = [:]
        for fullPath in filePaths {
            let filename = (fullPath as NSString).lastPathComponent
            let name = String(filename.dropLast(3))
            let angle = CGFloat.random(in: 0..<(.pi * 2))
            let radius = CGFloat.random(in: 50...250)
            nodeMap[fullPath] = GraphNode(
                id: fullPath,
                name: name,
                position: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            )
        }

        // Build edges from backlink index (wiki-links)
        var edgeSet: Set<String> = []
        var edges: [GraphEdge] = []
        for (_, node) in nodeMap {
            let backlinks = service.backlinksFor(pageName: node.name)
            for backlink in backlinks {
                guard nodeMap[backlink.sourcePath] != nil else { continue }
                let edgeId = "\(backlink.sourcePath)→\(node.id)"
                if !edgeSet.contains(edgeId) {
                    edgeSet.insert(edgeId)
                    edges.append(GraphEdge(source: backlink.sourcePath, target: node.id))
                }
            }
        }

        // Build parent-child edges from companion folders
        // Skip if a wiki-link edge already exists between the same pair (either direction)
        for (fullPath, _) in nodeMap {
            let parentDir = (fullPath as NSString).deletingLastPathComponent
            let parentDirName = (parentDir as NSString).lastPathComponent
            let grandparentDir = (parentDir as NSString).deletingLastPathComponent
            let potentialParentPage = (grandparentDir as NSString).appendingPathComponent("\(parentDirName).md")
            if nodeMap[potentialParentPage] != nil {
                let fwd = "\(potentialParentPage)→\(fullPath)"
                let rev = "\(fullPath)→\(potentialParentPage)"
                if !edgeSet.contains(fwd) && !edgeSet.contains(rev) {
                    edgeSet.insert(fwd)
                    edges.append(GraphEdge(source: potentialParentPage, target: fullPath, isParentChild: true))
                }
            }
        }

        // Count connections per node
        var connectionCounts: [String: Int] = [:]
        for edge in edges {
            connectionCounts[edge.source, default: 0] += 1
            connectionCounts[edge.target, default: 0] += 1
        }
        for key in nodeMap.keys {
            nodeMap[key]?.connectionCount = connectionCounts[key] ?? 0
        }

        simulation.nodes = Array(nodeMap.values)
        simulation.edges = edges
    }

    // MARK: - Rendering Helpers

    private func screenPoint(_ graphPoint: CGPoint, center: CGPoint, offset: CGSize) -> CGPoint {
        CGPoint(
            x: center.x + graphPoint.x * zoom + offset.width,
            y: center.y + graphPoint.y * zoom + offset.height
        )
    }

    private func nodeRadius(for node: GraphNode) -> CGFloat {
        let base: CGFloat = 5
        let scaled = base + CGFloat(node.connectionCount) * 1.5
        return min(scaled, 16) * zoom
    }

    private func countWorkspaceFiles() -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: workspacePath) else { return 0 }
        var count = 0
        while let rel = enumerator.nextObject() as? String {
            let components = rel.components(separatedBy: "/")
            if components.contains(where: { $0.hasPrefix(".") }) { continue }
            if components.contains(where: { $0.hasPrefix("_") }) { continue }
            if (rel as NSString).pathExtension == "md" {
                count += 1
            }
        }
        return count
    }

    private func hitTestNode(at point: CGPoint, center: CGPoint, offset: CGSize) -> String? {
        let hitRadius: CGFloat = 20 * zoom
        for node in simulation.nodes {
            let screenPos = screenPoint(node.position, center: center, offset: offset)
            let dx = point.x - screenPos.x
            let dy = point.y - screenPos.y
            if sqrt(dx * dx + dy * dy) < hitRadius {
                return node.id
            }
        }
        return nil
    }
}
