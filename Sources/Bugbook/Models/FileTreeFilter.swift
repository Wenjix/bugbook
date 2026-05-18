import Foundation

enum FileTreeFilter {
    static func filteredEntries(_ entries: [FileEntry], query: String) -> [FileEntry] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return entries }

        return flatten(entries)
            .compactMap { entry -> (entry: FileEntry, score: Int)? in
                guard !entry.isDirectory,
                      let score = matchScore(name: entry.name, query: normalizedQuery) else {
                    return nil
                }
                return (flattened(entry), score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.entry.name.localizedCaseInsensitiveCompare(rhs.entry.name) == .orderedAscending
            }
            .map(\.entry)
    }

    private static func flatten(_ entries: [FileEntry]) -> [FileEntry] {
        entries.flatMap { entry in
            [entry] + flatten(entry.children ?? [])
        }
    }

    private static func flattened(_ entry: FileEntry) -> FileEntry {
        FileEntry(
            id: entry.id,
            name: entry.name,
            path: entry.path,
            isDirectory: entry.isDirectory,
            kind: entry.kind,
            icon: entry.icon,
            children: nil,
            isSidebarReference: entry.isSidebarReference
        )
    }

    private static func matchScore(name: String, query: String) -> Int? {
        let normalizedName = normalize((name as NSString).deletingPathExtension)
        guard !normalizedName.isEmpty else { return nil }

        if normalizedName == query { return 1_000 }
        if normalizedName.hasPrefix(query) { return 900 - normalizedName.count }
        if let range = normalizedName.range(of: query) {
            let distance = normalizedName.distance(from: normalizedName.startIndex, to: range.lowerBound)
            return 700 - distance
        }

        return subsequenceScore(name: normalizedName, query: query)
    }

    private static func subsequenceScore(name: String, query: String) -> Int? {
        var score = 300
        var searchStart = name.startIndex
        var previousMatch: String.Index?

        for character in query {
            guard let match = name[searchStart...].firstIndex(of: character) else {
                return nil
            }
            if let previousMatch, name.index(after: previousMatch) == match {
                score += 8
            }
            score -= name.distance(from: searchStart, to: match)
            previousMatch = match
            searchStart = name.index(after: match)
        }

        return score
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
