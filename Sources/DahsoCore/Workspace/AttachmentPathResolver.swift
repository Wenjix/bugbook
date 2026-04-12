import Foundation

public func resolveWorkspaceAttachmentPath(
    _ storedPath: String,
    pagePath: String?,
    workspacePath: String?,
    fileManager: FileManager = .default
) -> String? {
    let trimmedPath = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else { return nil }

    if trimmedPath.hasPrefix("file://"),
       let url = URL(string: trimmedPath) {
        return url.path
    }

    if let url = URL(string: trimmedPath),
       let scheme = url.scheme,
       !scheme.isEmpty {
        return nil
    }

    let normalizedPath: String
    if trimmedPath.contains("%"),
       let decodedPath = trimmedPath.removingPercentEncoding {
        normalizedPath = decodedPath
    } else {
        normalizedPath = trimmedPath
    }

    if normalizedPath.hasPrefix("/") {
        return (normalizedPath as NSString).standardizingPath
    }

    var candidates: [String] = []

    if normalizedPath.hasPrefix("Attachments/"),
       let workspacePath,
       !workspacePath.isEmpty {
        candidates.append((workspacePath as NSString).appendingPathComponent(normalizedPath))
    }

    if let pagePath,
       !pagePath.isEmpty {
        let pageDirectory = (pagePath as NSString).deletingLastPathComponent
        candidates.append((pageDirectory as NSString).appendingPathComponent(normalizedPath))
    }

    if let workspacePath,
       !workspacePath.isEmpty {
        candidates.append((workspacePath as NSString).appendingPathComponent(normalizedPath))
    }

    var seen: Set<String> = []
    let normalizedCandidates = candidates
        .map { ($0 as NSString).standardizingPath }
        .filter { seen.insert($0).inserted }

    for candidate in normalizedCandidates where fileManager.fileExists(atPath: candidate) {
        return candidate
    }

    return normalizedCandidates.first
}
