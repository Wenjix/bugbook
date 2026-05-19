import ArgumentParser
import Foundation
import Yams

extension Context {
    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "open",
            abstract: "Detect and summarize a Context repo workspace"
        )

        @Argument(help: "Local Context repo path")
        var path: String

        func run() throws {
            let repo = try ContextRepo(path: path)
            try outputJSON(repo.summaryJSON())
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List Context records grouped by metadata"
        )

        @OptionGroup var options: Bugbook.Options

        @Option(name: .long, help: "Filter by record type")
        var type: ContextRecordType?

        @Option(name: .long, help: "Filter by record status")
        var status: ContextRecordStatus?

        @Option(name: .long, help: "Filter by folder prefix under records/")
        var folder: String?

        @Option(name: .long, help: "Filter by tag")
        var tag: String?

        @Option(name: .long, help: "Group by type, status, folder, tag, or none")
        var groupBy: ContextRecordGroup = .type

        func run() throws {
            let repo = try ContextRepo(path: options.resolvedWorkspace)
            let records = try repo.records().filter {
                recordMatchesFilters($0, type: type, status: status, folder: folder, tag: tag)
            }
            try outputJSON(contextRecordListJSON(records: records, groupBy: groupBy, repo: repo))
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a valid Context record"
        )

        @OptionGroup var options: Bugbook.Options

        @Option(name: .long, help: "Record type")
        var type: ContextRecordType

        @Option(name: .long, help: "Record status")
        var status: ContextRecordStatus

        @Option(name: .long, help: "Record title")
        var title: String

        @Option(name: .long, help: "Record owner")
        var owner: String = "max"

        @Option(name: .long, parsing: .upToNextOption, help: "Tags")
        var tags: [String] = []

        @Option(name: .long, parsing: .upToNextOption, help: "Source record IDs")
        var sourceRefs: [String] = []

        @Option(name: .long, help: "Summary paragraph")
        var summary: String?

        @Option(name: .long, help: "Body text")
        var body: String?

        @Option(name: .long, help: "Body file path, or - for stdin")
        var bodyFile: String?

        @Option(name: .long, help: "Explicit relative path for the new record")
        var path: String?

        @Option(name: .long, help: "Source system for source_item records")
        var sourceSystem: String = "other"

        func run() throws {
            guard body == nil || bodyFile == nil else {
                throw CLIError.invalidInput("--body and --body-file are mutually exclusive")
            }

            let repo = try ContextRepo(path: options.resolvedWorkspace)
            let request = ContextRecordCreateRequest(
                type: type,
                status: status,
                title: title,
                owner: owner,
                tags: tags,
                sourceRefs: sourceRefs,
                summary: summary,
                body: try bodyFile.map(readTextInput) ?? body,
                path: path,
                sourceSystem: sourceSystem
            )
            let record = try repo.createRecord(request)
            try outputJSON(record.toJSON())
        }
    }

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Run scripts/validate_context.py"
        )

        @OptionGroup var options: Bugbook.Options

        func run() throws {
            let repo = try ContextRepo(path: options.resolvedWorkspace)
            let result = try repo.runScript(ContextRepo.validateScript)
            try outputJSON(result.toJSON())
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export",
            abstract: "Run scripts/export_context_pack.py"
        )

        @OptionGroup var options: Bugbook.Options

        func run() throws {
            let repo = try ContextRepo(path: options.resolvedWorkspace)
            let result = try repo.runScript(ContextRepo.exportScript)
            try outputJSON(result.toJSON())
        }
    }

    struct Pack: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pack",
            abstract: "Print generated/daso-context-pack.md"
        )

        @OptionGroup var options: Bugbook.Options

        func run() throws {
            let repo = try ContextRepo(path: options.resolvedWorkspace)
            let content = try repo.contextPack()
            FileHandle.standardOutput.write(Data(content.utf8))
        }
    }
}

enum ContextRecordType: String, ExpressibleByArgument {
    case decision
    case plan
    case prd
    case research
    case architectureSummary = "architecture_summary"
    case onboarding
    case sourceItem = "source_item"
}

enum ContextRecordStatus: String, ExpressibleByArgument {
    case accepted
    case draft
    case seed
    case superseded
}

enum ContextRecordGroup: String, ExpressibleByArgument {
    case type
    case status
    case folder
    case tag
    case none
}

private struct ContextRepo {
    let path: String

    static let validateScript = "scripts/validate_context.py"
    static let exportScript = "scripts/export_context_pack.py"

    private var recordsPath: String {
        (path as NSString).appendingPathComponent("records")
    }

    init(path rawPath: String) throws {
        path = normalizePath((rawPath as NSString).expandingTildeInPath)
        try Self.validateContextRepo(at: path)
    }

    func summaryJSON() throws -> [String: Any] {
        [
            "path": path,
            "records_count": try records().count,
            "detected": true,
            "required_files": Self.requiredMarkers,
        ]
    }

    func records() throws -> [ContextRecord] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: recordsPath) else {
            return []
        }

        var records: [ContextRecord] = []
        while let relative = enumerator.nextObject() as? String {
            guard relative.hasSuffix(".md") else { continue }
            let fullPath = (recordsPath as NSString).appendingPathComponent(relative)
            guard let record = try ContextRecord(path: fullPath, repoPath: path) else { continue }
            records.append(record)
        }
        return records.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
    }

    func createRecord(_ request: ContextRecordCreateRequest) throws -> ContextRecord {
        let relativePath = request.path ?? defaultRelativePath(for: request)
        let fullPath = normalizePath((path as NSString).appendingPathComponent(relativePath))
        guard isPathInsideWorkspace(fullPath, workspace: path) else {
            throw CLIError.invalidInput("Record path must stay inside Context repo: \(relativePath)")
        }
        guard !FileManager.default.fileExists(atPath: fullPath) else {
            throw CLIError.invalidInput("Record already exists: \(relativePath)")
        }

        try FileManager.default.createDirectory(
            atPath: (fullPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let markdown = request.renderMarkdown()
        try markdown.write(toFile: fullPath, atomically: true, encoding: .utf8)

        guard let record = try ContextRecord(path: fullPath, repoPath: path) else {
            throw CLIError.operationFailed("Created record could not be parsed: \(relativePath)")
        }
        return record
    }

    func runScript(_ relativeScriptPath: String) throws -> ContextScriptResult {
        let scriptPath = (path as NSString).appendingPathComponent(relativeScriptPath)
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw CLIError.fileNotFound(relativeScriptPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", relativeScriptPath]
        process.currentDirectoryURL = URL(fileURLWithPath: path, isDirectory: true)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ContextScriptResult(
            command: "python3 \(relativeScriptPath)",
            exitCode: Int(process.terminationStatus),
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    func contextPack() throws -> String {
        let packPath = (path as NSString).appendingPathComponent("generated/daso-context-pack.md")
        guard FileManager.default.fileExists(atPath: packPath) else {
            throw CLIError.fileNotFound("generated/daso-context-pack.md")
        }
        return try String(contentsOfFile: packPath, encoding: .utf8)
    }

    private func defaultRelativePath(for request: ContextRecordCreateRequest) -> String {
        let folder: String
        switch request.type {
        case .decision:
            folder = "records/decisions"
        case .plan:
            folder = "records/plans"
        case .prd:
            folder = "records/prds"
        case .research:
            folder = "records/research"
        case .architectureSummary:
            folder = "records/architecture"
        case .onboarding:
            folder = "records/onboarding/agents"
        case .sourceItem:
            folder = "records/sources/conversations/\(request.sourceSystem)"
        }
        return "\(folder)/\(slugify(request.title)).md"
    }

    private static let requiredMarkers = [
        "CONTEXT_MANIFEST.md",
        "AGENTS.md",
        "records",
        validateScript,
        exportScript,
    ]

    private static func validateContextRepo(at path: String) throws {
        for marker in requiredMarkers {
            let markerPath = (path as NSString).appendingPathComponent(marker)
            guard FileManager.default.fileExists(atPath: markerPath) else {
                throw CLIError.invalidInput("Not a Context repo; missing \(marker)")
            }
        }
    }
}

private struct ContextRecordCreateRequest {
    let type: ContextRecordType
    let status: ContextRecordStatus
    let title: String
    let owner: String
    let tags: [String]
    let sourceRefs: [String]
    let summary: String?
    let body: String?
    let path: String?
    let sourceSystem: String

    func renderMarkdown() -> String {
        let recordID = idPrefix + "_" + dateKey + "_" + slugify(title).replacingOccurrences(of: "-", with: "_")
        var lines = [
            "---",
            "id: \(recordID)",
            "type: \(type.rawValue)",
            "status: \(status.rawValue)",
            "title: \(yamlQuoted(title))",
            "owner: \(yamlQuoted(owner))",
            "created_at: \(dateValue)",
            "updated_at: \(dateValue)",
        ]
        lines.append(contentsOf: yamlList(key: "tags", values: tags))
        lines.append(contentsOf: yamlList(key: "source_refs", values: sourceRefs))
        lines.append("supersedes: []")
        lines.append("superseded_by: []")
        if type == .sourceItem {
            lines.append("source_system: \(yamlQuoted(sourceSystem))")
            lines.append("participants: []")
            lines.append("seeded_records: []")
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(title)")
        lines.append("")
        lines.append(summaryText)
        if let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private var summaryText: String {
        summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Seed record created from Bugbook Context Mode."
    }

    private var idPrefix: String {
        switch type {
        case .decision:
            return "dec"
        case .plan:
            return "plan"
        case .prd:
            return "prd"
        case .research:
            return "res"
        case .architectureSummary:
            return "arch"
        case .onboarding:
            return "onboarding"
        case .sourceItem:
            return "src"
        }
    }

    private var dateValue: String {
        Self.dateFormatter.string(from: Date())
    }

    private var dateKey: String {
        dateValue.replacingOccurrences(of: "-", with: "_")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct ContextRecord {
    let relativePath: String
    let frontmatter: [String: Any]

    init?(path: String, repoPath: String) throws {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        guard let frontmatter = parseFrontmatter(content) else { return nil }
        relativePath = BugbookCLI.relativePath(from: path, workspace: repoPath)
        self.frontmatter = frontmatter
    }

    var id: String { frontmatter["id"] as? String ?? "" }
    var type: String { frontmatter["type"] as? String ?? "" }
    var status: String { frontmatter["status"] as? String ?? "" }
    var title: String { frontmatter["title"] as? String ?? pageDisplayName(fromPath: relativePath) }
    var owner: String { frontmatter["owner"] as? String ?? "" }
    var tags: [String] { stringList(frontmatter["tags"]) }
    var sourceRefs: [String] { stringList(frontmatter["source_refs"]) }
    var folder: String { (relativePath as NSString).deletingLastPathComponent }

    func toJSON() -> [String: Any] {
        [
            "id": id,
            "type": type,
            "status": status,
            "title": title,
            "owner": owner,
            "tags": tags,
            "source_refs": sourceRefs,
            "relative_path": relativePath,
            "folder": folder,
        ]
    }
}

private struct ContextScriptResult {
    let command: String
    let exitCode: Int
    let stdout: String
    let stderr: String

    func toJSON() -> [String: Any] {
        [
            "command": command,
            "exit_code": exitCode,
            "ok": exitCode == 0,
            "stdout": stdout.trimmingCharacters(in: .newlines),
            "stderr": stderr.trimmingCharacters(in: .newlines),
        ]
    }
}

private func contextRecordListJSON(
    records: [ContextRecord],
    groupBy: ContextRecordGroup,
    repo: ContextRepo
) -> [String: Any] {
    let groups: [[String: Any]]
    switch groupBy {
    case .none:
        groups = [
            [
                "key": "all",
                "count": records.count,
                "records": records.map { $0.toJSON() },
            ],
        ]
    case .tag:
        groups = groupedRecordsByTag(records)
    default:
        groups = groupedRecords(records) { record in
            switch groupBy {
            case .type:
                return record.type
            case .status:
                return record.status
            case .folder:
                return record.folder
            case .none, .tag:
                return "all"
            }
        }
    }

    return [
        "repo_path": repo.path,
        "count": records.count,
        "group_by": groupBy.rawValue,
        "groups": groups,
    ]
}

private func recordMatchesFilters(
    _ record: ContextRecord,
    type: ContextRecordType?,
    status: ContextRecordStatus?,
    folder: String?,
    tag: String?
) -> Bool {
    if let type, record.type != type.rawValue { return false }
    if let status, record.status != status.rawValue { return false }
    if let folder, !record.folder.hasPrefix(folder) { return false }
    if let tag, !record.tags.contains(tag) { return false }
    return true
}

private func groupedRecords(
    _ records: [ContextRecord],
    key: (ContextRecord) -> String
) -> [[String: Any]] {
    Dictionary(grouping: records, by: key)
        .map { groupKey, records in
            [
                "key": groupKey.isEmpty ? "unknown" : groupKey,
                "count": records.count,
                "records": records.map { $0.toJSON() },
            ]
        }
        .sorted { ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "") }
}

private func groupedRecordsByTag(_ records: [ContextRecord]) -> [[String: Any]] {
    var grouped: [String: [ContextRecord]] = [:]
    for record in records {
        let tags = record.tags.isEmpty ? ["untagged"] : record.tags
        for tag in tags {
            grouped[tag, default: []].append(record)
        }
    }
    return grouped
        .map { tag, records in
            [
                "key": tag,
                "count": records.count,
                "records": records.map { $0.toJSON() },
            ]
        }
        .sorted { ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "") }
}

private func parseFrontmatter(_ content: String) -> [String: Any]? {
    guard content.hasPrefix("---\n"),
          let endRange = content.range(of: "\n---\n", range: content.index(content.startIndex, offsetBy: 4)..<content.endIndex) else {
        return nil
    }

    let yamlStart = content.index(content.startIndex, offsetBy: 4)
    let yaml = String(content[yamlStart..<endRange.lowerBound])
    guard let loaded = try? Yams.load(yaml: yaml),
          let frontmatter = jsonCompatibleObject(loaded) as? [String: Any] else {
        return nil
    }
    return frontmatter
}

private func stringList(_ value: Any?) -> [String] {
    if let strings = value as? [String] {
        return strings
    }
    if let items = value as? [Any] {
        return items.compactMap { $0 as? String }
    }
    if let string = value as? String, !string.isEmpty {
        return [string]
    }
    return []
}

private func yamlList(key: String, values: [String]) -> [String] {
    guard !values.isEmpty else {
        return ["\(key): []"]
    }
    return [ "\(key):" ] + values.map { "  - \(yamlQuoted($0))" }
}

private func yamlQuoted(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func slugify(_ value: String) -> String {
    let lowered = value.lowercased()
    let allowed = lowered.map { character -> Character in
        character.isLetter || character.isNumber ? character : "-"
    }
    return String(allowed)
        .split(separator: "-")
        .joined(separator: "-")
}

private func jsonCompatibleObject(_ value: Any) -> Any {
    switch value {
    case let dict as [String: Any]:
        return dict.reduce(into: [String: Any]()) { result, entry in
            result[entry.key] = jsonCompatibleObject(entry.value)
        }
    case let dict as [AnyHashable: Any]:
        return dict.reduce(into: [String: Any]()) { result, entry in
            result[String(describing: entry.key)] = jsonCompatibleObject(entry.value)
        }
    case let array as [Any]:
        return array.map(jsonCompatibleObject)
    case let string as String:
        return string
    case let bool as Bool:
        return bool
    case let number as NSNumber:
        return number
    case is NSNull:
        return NSNull()
    default:
        return String(describing: value)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
