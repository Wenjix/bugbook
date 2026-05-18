import Foundation
import BugbookCore
import Yams

struct WorkspaceSkillRecord {
    let path: String
    let relativePath: String
    let name: String
    let title: String
    let description: String?
    let content: String
    let body: String
    let frontmatter: [String: Any]
    let modifiedAt: String?

    func toSummaryJSON() -> [String: Any] {
        var json: [String: Any] = [
            "path": path,
            "relative_path": relativePath,
            "name": name,
            "title": title,
        ]

        if let description, !description.isEmpty {
            json["description"] = description
        }

        if let modifiedAt {
            json["modified_at"] = modifiedAt
        }

        return json
    }

    func toDetailJSON(includeContent: Bool = true) -> [String: Any] {
        var json = toSummaryJSON()
        json["frontmatter"] = frontmatter
        if includeContent {
            json["content"] = content
            json["body"] = body
        }
        return json
    }
}

func listWorkspaceSkills(
    in workspace: String,
    pathPrefix: String? = nil,
    fileManager: FileManager = .default
) throws -> [WorkspaceSkillRecord] {
    guard let skillsRoot = existingSkillsRootPath(in: workspace, fileManager: fileManager) else {
        return []
    }

    var skills: [WorkspaceSkillRecord] = []
    guard let enumerator = fileManager.enumerator(atPath: skillsRoot) else {
        return []
    }

    while let relativeToSkills = enumerator.nextObject() as? String {
        let absolutePath = (skillsRoot as NSString).appendingPathComponent(relativeToSkills)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: absolutePath, isDirectory: &isDirectory) else { continue }
        if isDirectory.boolValue { continue }

        guard relativeToSkills.hasSuffix(".skill.md") else { continue }

        let relativeToWorkspace = relativePath(from: absolutePath, workspace: normalizePath(workspace))
        guard !WorkspacePathRules.shouldIgnoreRelativePath(relativeToWorkspace) else { continue }

        guard let record = try? loadWorkspaceSkill(
            at: absolutePath,
            relativeTo: workspace,
            relativePathOverride: relativeToWorkspace
        ) else {
            continue
        }

        skills.append(record)
    }

    if let pathPrefix, !pathPrefix.isEmpty {
        let normalized = normalizePageLookup(pathPrefix)
        skills = skills.filter { normalizePageLookup($0.relativePath).hasPrefix(normalized) }
    }

    return skills.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
}

func resolveWorkspaceSkill(_ query: String, workspace: String) throws -> WorkspaceSkillRecord {
    let path = try resolveWorkspaceSkillPath(query, workspace: workspace)
    return try loadWorkspaceSkill(at: path, relativeTo: workspace)
}

func createWorkspaceSkill(
    rawName: String,
    workspace: String,
    title: String? = nil,
    description: String? = nil,
    content: String? = nil
) throws -> WorkspaceSkillRecord {
    let path = normalizedSkillDestination(rawName, workspace: workspace)
    let skillTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        ?? defaultSkillTitle(from: rawName)
    let skillContent = content ?? defaultSkillContent(title: skillTitle, description: description)

    let page = try createWorkspacePage(
        rawPath: path,
        workspace: workspace,
        title: nil,
        content: skillContent
    )

    return try loadWorkspaceSkill(at: page.path, relativeTo: workspace)
}

func resolveWorkspaceSkillPath(_ query: String, workspace: String) throws -> String {
    let expanded = (query as NSString).expandingTildeInPath
    let normalizedWorkspace = normalizePath(workspace)

    if expanded.hasPrefix("/") {
        let candidate = normalizePath(expanded)
        guard isPathInsideWorkspace(candidate, workspace: normalizedWorkspace) else {
            throw CLIError.invalidInput("Skill path must be inside workspace: \(query)")
        }
        guard FileManager.default.fileExists(atPath: candidate) else {
            throw CLIError.fileNotFound(candidate)
        }
        guard candidate.hasSuffix(".skill.md"), !WorkspacePathRules.shouldIgnoreAbsolutePath(candidate) else {
            throw CLIError.invalidInput("Not a visible skill file: \(query)")
        }
        return candidate
    }

    for direct in directSkillCandidates(for: query, workspace: normalizedWorkspace) {
        if FileManager.default.fileExists(atPath: direct),
           direct.hasSuffix(".skill.md"),
           !WorkspacePathRules.shouldIgnoreAbsolutePath(direct) {
            return direct
        }
    }

    let skills = try listWorkspaceSkills(in: normalizedWorkspace)
    let needle = normalizePageLookup(query)
    let matches = skills.filter { skill in
        normalizePageLookup(skill.relativePath) == needle
            || normalizePageLookup(skill.name) == needle
            || normalizePageLookup(skill.title) == needle
            || normalizePageLookup(skill.relativePath.replacingOccurrences(of: ".skill.md", with: "")) == needle
    }

    if matches.count == 1, let match = matches.first {
        return match.path
    }

    if matches.isEmpty {
        throw CLIError.invalidInput("Skill not found: \(query)")
    }

    let options = matches.map(\.relativePath).sorted().joined(separator: ", ")
    throw CLIError.invalidInput("Skill reference is ambiguous: \(query). Matches: \(options)")
}

func loadWorkspaceSkill(
    at path: String,
    relativeTo workspace: String,
    relativePathOverride: String? = nil
) throws -> WorkspaceSkillRecord {
    let page = try loadWorkspacePage(at: path, relativeTo: workspace, relativePathOverride: relativePathOverride)
    return WorkspaceSkillRecord(
        path: page.path,
        relativePath: page.relativePath,
        name: skillDisplayName(fromPath: page.path),
        title: page.title,
        description: skillDescription(frontmatter: page.frontmatter, body: page.body),
        content: page.content,
        body: page.body,
        frontmatter: page.frontmatter,
        modifiedAt: page.modifiedAt
    )
}

private func existingSkillsRootPath(in workspace: String, fileManager: FileManager) -> String? {
    for candidate in skillRootCandidates(in: workspace) {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
    }
    return nil
}

private func directSkillCandidates(for query: String, workspace: String) -> [String] {
    let normalizedWorkspace = normalizePath(workspace)
    let expanded = (query as NSString).expandingTildeInPath

    if expanded.hasPrefix("/") {
        return [normalizePath(expanded)]
    }

    let baseCandidates = [
        query,
        query.hasSuffix(".skill.md") ? query : "\(query).skill.md",
    ]

    var results = Set<String>()
    for rawCandidate in baseCandidates {
        results.insert(normalizePath((normalizedWorkspace as NSString).appendingPathComponent(rawCandidate)))
        for skillsRoot in skillRootCandidates(in: normalizedWorkspace) {
            results.insert(normalizePath((skillsRoot as NSString).appendingPathComponent(rawCandidate)))
        }
    }

    return Array(results)
}

private func normalizedSkillDestination(_ rawName: String, workspace: String) -> String {
    let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    let relativePath: String
    if trimmed.hasPrefix("/") {
        relativePath = trimmed
    } else if trimmed.hasPrefix("Skills/") || trimmed.hasPrefix("skills/") {
        relativePath = trimmed
    } else {
        relativePath = "Skills/\(trimmed)"
    }

    if relativePath.hasSuffix(".skill.md") {
        return relativePath
    }

    return "\(relativePath).skill.md"
}

private func skillRootCandidates(in workspace: String) -> [String] {
    [
        normalizePath((workspace as NSString).appendingPathComponent("Skills")),
        normalizePath((workspace as NSString).appendingPathComponent("skills")),
    ]
}

private func skillDisplayName(fromPath path: String) -> String {
    let filename = (path as NSString).lastPathComponent
    if filename.hasSuffix(".skill.md") {
        return String(filename.dropLast(".skill.md".count))
    }
    return pageDisplayName(fromPath: path)
}

private func skillDescription(frontmatter: [String: Any], body: String) -> String? {
    if let description = frontmatter["description"] as? String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }

    for line in body.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if trimmed.hasPrefix("#") { continue }
        return trimmed
    }

    return nil
}

private func defaultSkillTitle(from rawName: String) -> String {
    let leaf = ((rawName as NSString).lastPathComponent as NSString).deletingPathExtension
    return leaf
        .replacingOccurrences(of: ".skill", with: "")
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { fragment in
            fragment.prefix(1).uppercased() + fragment.dropFirst()
        }
        .joined(separator: " ")
}

private func defaultSkillContent(title: String, description: String?) -> String {
    var lines: [String] = []

    if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("---")
        lines.append(yamlFrontmatterLine(key: "description", value: description))
        lines.append("---")
        lines.append("")
    }

    lines.append("# \(title)")
    lines.append("")

    if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append(description)
        lines.append("")
    }

    return lines.joined(separator: "\n")
}

private func yamlFrontmatterLine(key: String, value: String) -> String {
    if let dumped = try? Yams.dump(object: [key: value], sortKeys: false) {
        return dumped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\(key): \"\(escaped)\""
}
