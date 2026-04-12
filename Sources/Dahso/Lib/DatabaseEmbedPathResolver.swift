import Foundation
import DahsoCore

func resolveDatabaseEmbedPath(
    _ storedPath: String,
    pagePath: String,
    workspacePath: String?,
    fileManager: FileManager = .default
) -> String? {
    let normalizedStoredPath = (storedPath as NSString).standardizingPath
    guard !normalizedStoredPath.isEmpty else { return nil }
    if isDatabaseFolderPath(normalizedStoredPath, fileManager: fileManager) {
        return normalizedStoredPath
    }

    let pageContainer = pagePath.hasSuffix(".md") ? String(pagePath.dropLast(3)) : pagePath
    let storedName = (normalizedStoredPath as NSString).lastPathComponent
    var candidates: [String] = []

    if !storedName.isEmpty {
        candidates.append((pageContainer as NSString).appendingPathComponent(storedName))
    }

    candidates.append(contentsOf: matchingDatabaseChildren(
        named: storedName,
        in: pageContainer,
        fileManager: fileManager
    ))

    if let workspacePath, !workspacePath.isEmpty {
        if !storedName.isEmpty {
            candidates.append((workspacePath as NSString).appendingPathComponent(storedName))
        }
        if let uniqueMatch = findUniqueDatabasePath(
            named: storedName,
            in: workspacePath,
            fileManager: fileManager
        ) {
            candidates.append(uniqueMatch)
        }
    }

    var seen: Set<String> = []
    for candidate in candidates.map({ ($0 as NSString).standardizingPath }) where seen.insert(candidate).inserted {
        if isDatabaseFolderPath(candidate, fileManager: fileManager) {
            return candidate
        }
    }

    return nil
}

private func matchingDatabaseChildren(
    named name: String,
    in directory: String,
    fileManager: FileManager
) -> [String] {
    guard !name.isEmpty,
          fileManager.fileExists(atPath: directory),
          let entries = try? fileManager.contentsOfDirectory(atPath: directory) else {
        return []
    }

    return entries.compactMap { entryName in
        let childPath = (directory as NSString).appendingPathComponent(entryName)
        guard isDatabaseFolderPath(childPath, fileManager: fileManager) else { return nil }

        let folderNameMatches = entryName.localizedCaseInsensitiveCompare(name) == .orderedSame
        let schemaNameMatches = databaseDisplayName(at: childPath, fileManager: fileManager)?
            .localizedCaseInsensitiveCompare(name) == .orderedSame

        return (folderNameMatches || schemaNameMatches) ? childPath : nil
    }
}

private func findUniqueDatabasePath(
    named name: String,
    in workspacePath: String,
    fileManager: FileManager
) -> String? {
    guard !name.isEmpty,
          let enumerator = fileManager.enumerator(atPath: workspacePath) else {
        return nil
    }

    var matches: [String] = []

    while let relativePath = enumerator.nextObject() as? String {
        if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) {
            enumerator.skipDescendants()
            continue
        }

        let fullPath = (workspacePath as NSString).appendingPathComponent(relativePath)
        guard isDatabaseFolderPath(fullPath, fileManager: fileManager) else { continue }

        let folderName = (fullPath as NSString).lastPathComponent
        let schemaName = databaseDisplayName(at: fullPath, fileManager: fileManager)
        if folderName.localizedCaseInsensitiveCompare(name) == .orderedSame
            || schemaName?.localizedCaseInsensitiveCompare(name) == .orderedSame {
            matches.append(fullPath)
            if matches.count > 1 {
                return nil
            }
        }

        enumerator.skipDescendants()
    }

    return matches.first
}

private func databaseDisplayName(at path: String, fileManager: FileManager) -> String? {
    let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
    guard fileManager.fileExists(atPath: schemaPath),
          let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
          let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = schema["name"] as? String,
          !name.isEmpty else {
        return nil
    }
    return name
}

private func isDatabaseFolderPath(_ path: String, fileManager: FileManager) -> Bool {
    let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
    return fileManager.fileExists(atPath: schemaPath)
}
