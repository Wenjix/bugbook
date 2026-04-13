import Foundation
import DahsoCore

func moveWorkspaceDatabase(
    query: String,
    workspace: String,
    destinationDirectory rawDirectory: String?,
    destinationPageQuery rawPageQuery: String?,
    dryRun: Bool = false
) throws -> [String: Any] {
    let normalizedWorkspace = normalizePath(workspace)
    let fileManager = FileManager.default
    let (resolvedPath, schema) = try resolveDatabase(query, workspace: normalizedWorkspace)
    let currentPath = normalizePath(resolvedPath)
    let destination = try resolveDatabaseMoveDestination(
        workspace: normalizedWorkspace,
        rawDirectory: rawDirectory,
        rawPageQuery: rawPageQuery
    )
    let nextPath = normalizePath(
        (destination.directory as NSString).appendingPathComponent(
            sanitizeDatabaseFolderName(schema.name)
        )
    )

    guard isPathInsideWorkspace(nextPath, workspace: normalizedWorkspace) else {
        throw CLIError.invalidInput("Database destination must stay inside the workspace")
    }
    guard !WorkspacePathRules.shouldIgnoreAbsolutePath(nextPath) else {
        throw CLIError.invalidInput("Database destination is not a visible workspace path")
    }

    let plannedEmbedUpdates = try collectDatabaseEmbedUpdates(
        workspace: normalizedWorkspace,
        from: currentPath,
        to: nextPath
    )
    let changed = currentPath != nextPath

    if changed, fileManager.fileExists(atPath: nextPath) {
        throw CLIError.invalidInput("Database already exists at \(nextPath)")
    }

    var prunedDirectories: [String] = []
    if changed, !dryRun {
        try fileManager.createDirectory(atPath: destination.directory, withIntermediateDirectories: true)
        try fileManager.moveItem(atPath: currentPath, toPath: nextPath)
        try applyDatabaseEmbedUpdates(
            plannedEmbedUpdates,
            movedFrom: currentPath,
            movedTo: nextPath
        )
        prunedDirectories = try pruneEmptyWorkspaceDirectories(
            startingAt: (currentPath as NSString).deletingLastPathComponent,
            workspace: normalizedWorkspace,
            fileManager: fileManager
        )
    }

    var json: [String: Any] = [
        "changed": changed,
        "dry_run": dryRun,
        "database": [
            "id": schema.id,
            "name": schema.name,
        ],
        "old_path": currentPath,
        "old_relative_path": relativePath(from: currentPath, workspace: normalizedWorkspace),
        "new_path": nextPath,
        "new_relative_path": relativePath(from: nextPath, workspace: normalizedWorkspace),
        "embed_update_count": plannedEmbedUpdates.count,
        "embed_updates": plannedEmbedUpdates.map(\.relativePath),
    ]

    if dryRun {
        json["planned_move"] = changed
    } else {
        json["moved"] = changed
    }

    if let page = destination.page {
        json["destination_page"] = [
            "name": page.name,
            "relative_path": page.relativePath,
        ]
    } else {
        json["destination_directory"] = relativePath(from: destination.directory, workspace: normalizedWorkspace)
    }

    if !prunedDirectories.isEmpty {
        json["pruned_directories"] = prunedDirectories.map { relativePath(from: $0, workspace: normalizedWorkspace) }
    }

    return json
}

func databaseParentPageInfo(for dbPath: String, workspace: String) -> [String: Any]? {
    let normalizedWorkspace = normalizePath(workspace)
    let normalizedDBPath = normalizePath(dbPath)
    let parentDirectory = (normalizedDBPath as NSString).deletingLastPathComponent
    guard parentDirectory != normalizedWorkspace else {
        return nil
    }

    let parentName = (parentDirectory as NSString).lastPathComponent
    guard !parentName.isEmpty else {
        return nil
    }

    let parentPagePath = normalizePath(
        ((parentDirectory as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent("\(parentName).md")
    )
    guard FileManager.default.fileExists(atPath: parentPagePath) else {
        return nil
    }

    return [
        "name": pageDisplayName(fromPath: parentPagePath),
        "path": parentPagePath,
        "relative_path": relativePath(from: parentPagePath, workspace: normalizedWorkspace),
    ]
}

private struct DatabaseMoveDestination {
    let directory: String
    let page: WorkspacePageRecord?
}

private struct DatabaseEmbedUpdate {
    let path: String
    let relativePath: String
    let oldMarker: String
    let newMarker: String
}

private func resolveDatabaseMoveDestination(
    workspace: String,
    rawDirectory: String?,
    rawPageQuery: String?
) throws -> DatabaseMoveDestination {
    let trimmedDirectory = rawDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPageQuery = rawPageQuery?.trimmingCharacters(in: .whitespacesAndNewlines)

    switch (trimmedDirectory?.isEmpty == false ? trimmedDirectory : nil, trimmedPageQuery?.isEmpty == false ? trimmedPageQuery : nil) {
    case let (directory?, nil):
        return DatabaseMoveDestination(
            directory: try normalizeWorkspaceDirectory(directory, workspace: workspace),
            page: nil
        )
    case let (nil, pageQuery?):
        let page = try resolveWorkspacePage(pageQuery, workspace: workspace)
        return DatabaseMoveDestination(
            directory: companionFolderPath(for: page.path),
            page: page
        )
    case (nil, nil):
        throw CLIError.invalidInput("Pass either --directory or --page")
    default:
        throw CLIError.invalidInput("Pass only one of --directory or --page")
    }
}


private func collectDatabaseEmbedUpdates(
    workspace: String,
    from oldDatabasePath: String,
    to newDatabasePath: String
) throws -> [DatabaseEmbedUpdate] {
    let oldMarker = "<!-- database: \(oldDatabasePath) -->"
    let newMarker = "<!-- database: \(newDatabasePath) -->"
    guard oldMarker != newMarker else {
        return []
    }

    var updates: [DatabaseEmbedUpdate] = []
    walkWorkspaceMarkdownFiles(in: workspace, includeStructuredContent: true) { filePath, relativePath in
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8),
              content.contains(oldMarker) else {
            return
        }
        updates.append(
            DatabaseEmbedUpdate(
                path: filePath,
                relativePath: relativePath,
                oldMarker: oldMarker,
                newMarker: newMarker
            )
        )
    }
    return updates.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
}

private func applyDatabaseEmbedUpdates(
    _ updates: [DatabaseEmbedUpdate],
    movedFrom oldDatabasePath: String,
    movedTo newDatabasePath: String
) throws {
    for update in updates {
        let actualPath: String
        if update.path == oldDatabasePath {
            actualPath = newDatabasePath
        } else if update.path.hasPrefix(oldDatabasePath + "/") {
            actualPath = newDatabasePath + String(update.path.dropFirst(oldDatabasePath.count))
        } else {
            actualPath = update.path
        }

        let content = try String(contentsOfFile: actualPath, encoding: .utf8)
        let nextContent = content.replacingOccurrences(of: update.oldMarker, with: update.newMarker)
        guard nextContent != content else {
            continue
        }
        try nextContent.write(toFile: actualPath, atomically: true, encoding: .utf8)
    }
}

private func pruneEmptyWorkspaceDirectories(
    startingAt initialDirectory: String,
    workspace: String,
    fileManager: FileManager
) throws -> [String] {
    var removed: [String] = []
    var currentDirectory = normalizePath(initialDirectory)
    let normalizedWorkspace = normalizePath(workspace)

    while currentDirectory != normalizedWorkspace, isPathInsideWorkspace(currentDirectory, workspace: normalizedWorkspace) {
        let contents = try fileManager.contentsOfDirectory(
            atPath: currentDirectory
        ).filter { $0 != ".DS_Store" }
        guard contents.isEmpty else {
            break
        }
        try fileManager.removeItem(atPath: currentDirectory)
        removed.append(currentDirectory)
        currentDirectory = (currentDirectory as NSString).deletingLastPathComponent
    }

    return removed
}

