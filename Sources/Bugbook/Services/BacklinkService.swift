import Foundation
import BugbookCore

private let backlinkLinkPattern = #"\[\[([^\]]+)\]\]"#

struct Backlink: Identifiable {
    let sourcePath: String
    let sourceName: String
    var id: String { sourcePath }
}

@MainActor
@Observable
class BacklinkService {
    /// Maps page name (lowercased) → list of backlinks
    private var index: [String: [Backlink]] = [:]
    /// Reverse index: source path → set of keys it contributed to
    @ObservationIgnored private var sourceToKeys: [String: Set<String>] = [:]
    @ObservationIgnored private var indexedWorkspace: String?
    @ObservationIgnored private var rebuildingWorkspace: String?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?

    func rebuild(workspace: String) {
        ensureIndex(workspace: workspace)
    }

    func ensureIndex(workspace: String) {
        if indexedWorkspace == workspace { return }
        if rebuildingWorkspace == workspace { return }

        rebuildTask?.cancel()
        if indexedWorkspace != workspace {
            index = [:]
            sourceToKeys = [:]
            indexedWorkspace = nil
        }

        rebuildingWorkspace = workspace
        rebuildTask = Task {
            let newIndex = await Task.detached(priority: .utility) {
                Self.buildIndex(workspace: workspace)
            }.value

            guard !Task.isCancelled else { return }
            index = newIndex
            sourceToKeys = Self.buildReverseIndex(from: newIndex)
            indexedWorkspace = workspace
            rebuildingWorkspace = nil
            rebuildTask = nil
        }
    }

    func awaitIndex(workspace: String) async {
        ensureIndex(workspace: workspace)
        await rebuildTask?.value
    }

    func backlinksFor(pageName: String) -> [Backlink] {
        index[pageName.lowercased()] ?? []
    }

    /// Incrementally update: remove old entries for a file, re-scan it, add new entries.
    func updateFile(at path: String, in workspace: String) {
        guard indexedWorkspace == workspace, rebuildTask == nil else { return }
        guard !WorkspacePathRules.shouldIgnoreAbsolutePath(path) else { return }

        let filename = (path as NSString).lastPathComponent
        guard filename.hasSuffix(".md") else { return }
        let sourceName = String(filename.dropLast(3))

        // Remove old entries using reverse index (O(affected keys) instead of O(all keys))
        if let oldKeys = sourceToKeys.removeValue(forKey: path) {
            for key in oldKeys {
                index[key]?.removeAll { $0.sourcePath == path }
                if index[key]?.isEmpty == true {
                    index.removeValue(forKey: key)
                }
            }
        }

        // Re-scan if file exists
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        guard let regex = try? NSRegularExpression(pattern: backlinkLinkPattern) else { return }
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        var newKeys = Set<String>()
        for match in matches {
            if let linkRange = Range(match.range(at: 1), in: content) {
                let linkedPage = String(content[linkRange])
                let key = linkedPage.lowercased()
                newKeys.insert(key)
                var existing = index[key] ?? []
                if !existing.contains(where: { $0.sourcePath == path }) {
                    existing.append(Backlink(sourcePath: path, sourceName: sourceName))
                }
                index[key] = existing
            }
        }
        if !newKeys.isEmpty {
            sourceToKeys[path] = newKeys
        }
    }

    // MARK: - Background I/O

    private nonisolated static func buildIndex(workspace: String) -> [String: [Backlink]] {
        let fm = FileManager.default
        var newIndex: [String: [Backlink]] = [:]
        guard let regex = try? NSRegularExpression(pattern: backlinkLinkPattern) else { return [:] }
        guard let enumerator = fm.enumerator(atPath: workspace) else { return [:] }

        while let relativePath = enumerator.nextObject() as? String {
            if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) { continue }
            let components = relativePath.components(separatedBy: "/")
            if components.contains(where: { $0.hasPrefix(".") }) { continue }
            let filename = (relativePath as NSString).lastPathComponent
            guard filename.hasSuffix(".md") else { continue }

            let fullPath = (workspace as NSString).appendingPathComponent(relativePath)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            let sourceName = String(filename.dropLast(3))
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)

            for match in matches {
                if let linkRange = Range(match.range(at: 1), in: content) {
                    let linkedPage = String(content[linkRange])
                    let key = linkedPage.lowercased()
                    var existing = newIndex[key] ?? []
                    if !existing.contains(where: { $0.sourcePath == fullPath }) {
                        existing.append(Backlink(sourcePath: fullPath, sourceName: sourceName))
                    }
                    newIndex[key] = existing
                }
            }
        }

        return newIndex
    }

    private static func buildReverseIndex(from index: [String: [Backlink]]) -> [String: Set<String>] {
        var reverse: [String: Set<String>] = [:]
        for (key, backlinks) in index {
            for backlink in backlinks {
                reverse[backlink.sourcePath, default: []].insert(key)
            }
        }
        return reverse
    }
}
