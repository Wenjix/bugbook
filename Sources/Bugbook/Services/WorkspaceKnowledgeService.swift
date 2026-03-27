import Foundation

/// Result from a workspace knowledge query.
struct KnowledgeResult: Identifiable {
    let id = UUID()
    let title: String
    let snippet: String
    let filePath: String
    let relevanceScore: Double
}

/// Indexes workspace .md files and provides keyword-based search using TF-IDF scoring.
/// Designed for live knowledge retrieval during meetings — no external dependencies.
@MainActor
@Observable
class WorkspaceKnowledgeService {
    private(set) var isIndexed = false
    private(set) var indexedFileCount = 0

    // Inverted index: term -> [(filePath, termFrequency)]
    @ObservationIgnored private var invertedIndex: [String: [(path: String, tf: Double)]] = [:]
    // Document metadata: filePath -> (title, content, termCount)
    @ObservationIgnored private var documents: [String: DocumentEntry] = [:]
    // Total document count for IDF calculation
    @ObservationIgnored private var documentCount = 0

    private struct DocumentEntry {
        let title: String
        let content: String
        let termCount: Int
    }

    // MARK: - Indexing

    /// Scans workspace .md files recursively and builds a TF-IDF keyword index.
    func index(workspacePath: String) async {
        let fm = FileManager.default
        let mdFiles = collectMarkdownFiles(at: workspacePath, fm: fm)

        var newIndex: [String: [(path: String, tf: Double)]] = [:]
        var newDocs: [String: DocumentEntry] = [:]

        for filePath in mdFiles {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let title = extractTitle(from: content, filePath: filePath)
            let terms = tokenize(content)
            guard !terms.isEmpty else { continue }

            newDocs[filePath] = DocumentEntry(title: title, content: content, termCount: terms.count)

            // Count term frequencies for this document
            var termCounts: [String: Int] = [:]
            for term in terms {
                termCounts[term, default: 0] += 1
            }

            for (term, count) in termCounts {
                let tf = Double(count) / Double(terms.count)
                newIndex[term, default: []].append((path: filePath, tf: tf))
            }
        }

        invertedIndex = newIndex
        documents = newDocs
        documentCount = newDocs.count
        indexedFileCount = newDocs.count
        isIndexed = true
    }

    // MARK: - Query

    /// Searches the index for documents relevant to the query text.
    func query(_ text: String, limit: Int = 5) -> [KnowledgeResult] {
        guard isIndexed, documentCount > 0 else { return [] }

        let queryTerms = tokenize(text)
        guard !queryTerms.isEmpty else { return [] }

        // Score each document using TF-IDF
        var scores: [String: Double] = [:]

        for term in Set(queryTerms) {
            guard let postings = invertedIndex[term] else { continue }
            let idf = log(Double(documentCount) / Double(postings.count + 1)) + 1.0

            for posting in postings {
                scores[posting.path, default: 0] += posting.tf * idf
            }
        }

        // Sort by score and take top results
        let ranked = scores.sorted { $0.value > $1.value }.prefix(limit)

        return ranked.compactMap { (path, score) -> KnowledgeResult? in
            guard let doc = documents[path] else { return nil }
            let snippet = extractSnippet(from: doc.content, queryTerms: Set(queryTerms))
            return KnowledgeResult(
                title: doc.title,
                snippet: snippet,
                filePath: path,
                relevanceScore: score
            )
        }
    }

    // MARK: - Private Helpers

    private func collectMarkdownFiles(at path: String, fm: FileManager) -> [String] {
        var results: [String] = []
        collectMarkdownFilesRecursive(at: path, fm: fm, results: &results, depth: 0)
        return results
    }

    private func collectMarkdownFilesRecursive(
        at path: String,
        fm: FileManager,
        results: inout [String],
        depth: Int
    ) {
        guard depth < 5 else { return }
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return }

        for name in contents {
            if name.hasPrefix(".") { continue }
            if name == "_schema.json" || name == "_index.json" { continue }

            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                collectMarkdownFilesRecursive(at: fullPath, fm: fm, results: &results, depth: depth + 1)
            } else if name.hasSuffix(".md") {
                results.append(fullPath)
            }
        }
    }

    private func extractTitle(from content: String, filePath: String) -> String {
        // Try to find a markdown heading
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }
        // Fall back to filename
        return ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    private func extractSnippet(from content: String, queryTerms: Set<String>, maxLength: Int = 150) -> String {
        let lines = content.components(separatedBy: .newlines)

        // Find the first line containing a query term (skip the title)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let lower = trimmed.lowercased()
            let hasMatch = queryTerms.contains { lower.contains($0) }
            if hasMatch {
                if trimmed.count <= maxLength { return trimmed }
                return String(trimmed.prefix(maxLength)) + "..."
            }
        }

        // Fall back to first non-empty, non-heading line
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.count <= maxLength { return trimmed }
            return String(trimmed.prefix(maxLength)) + "..."
        }

        return ""
    }

    private let stopWords: Set<String> = [
        "the", "be", "to", "of", "and", "in", "that", "have", "it",
        "for", "not", "on", "with", "he", "as", "you", "do", "at",
        "this", "but", "his", "by", "from", "they", "we", "say", "her",
        "she", "or", "an", "will", "my", "one", "all", "would", "there",
        "their", "what", "so", "up", "out", "if", "about", "who", "get",
        "which", "go", "me", "when", "make", "can", "like", "time", "no",
        "just", "him", "know", "take", "people", "into", "year", "your",
        "good", "some", "could", "them", "see", "other", "than", "then",
        "now", "look", "only", "come", "its", "over", "think", "also",
        "back", "after", "use", "two", "how", "our", "work", "first",
        "well", "way", "even", "new", "want", "because", "any", "these",
        "give", "day", "most", "us", "is", "are", "was", "were", "been",
        "has", "had", "did", "am",
    ]
}
