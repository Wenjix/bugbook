import ArgumentParser
import Foundation
import BugbookCore

struct Artifact: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "artifact",
        abstract: "Create, validate, and list self-contained HTML artifacts",
        discussion: """
        Artifacts are single self-contained .html files rendered in a sandboxed,
        offline pane. All CSS, JS, and data must be inline; external network
        references are rejected. Markdown remains the source of truth — always
        link an artifact from its parent page or row body.
        """,
        subcommands: [Create.self, Validate.self, List.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Validate HTML artifact content and write it into the workspace"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Target path inside the workspace, ending in .html (e.g. \"Weekly Review/sleep-trends.html\" or \"Tickets/_artifacts/2026-W23-board.html\")")
        var path: String

        @Option(name: .long, help: "HTML content file path, or - for stdin")
        var contentFile: String

        func run() throws {
            let workspace = normalizePath(options.resolvedWorkspace)
            let target = try resolveArtifactWritePath(path, workspace: workspace)
            let content = try readTextInput(from: contentFile)
            let report = validateArtifactContent(content)
            let relative = relativePath(from: target, workspace: workspace)

            guard report.isValid else {
                var json = report.toJSON()
                json["created"] = false
                json["path"] = target
                json["relative_path"] = relative
                try outputJSON(json)
                throw ExitCode.failure
            }

            let fm = FileManager.default
            let replacedExisting = fm.fileExists(atPath: target)
            try fm.createDirectory(
                atPath: (target as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try content.write(toFile: target, atomically: true, encoding: .utf8)

            let fallbackTitle = ((target as NSString).lastPathComponent as NSString).deletingPathExtension
            var json = report.toJSON()
            json["created"] = true
            json["replaced_existing"] = replacedExisting
            json["path"] = target
            json["relative_path"] = relative
            json["markdown_link"] = "[\(report.title ?? fallbackTitle)](\(relative))"
            try outputJSON(json)
        }
    }

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Validate an HTML artifact (marker, self-containment, size); exits nonzero on errors"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Artifact path (workspace-relative or absolute)")
        var path: String

        func run() throws {
            let workspace = normalizePath(options.resolvedWorkspace)
            let target = try resolveArtifactReadPath(path, workspace: workspace)
            guard let content = try? String(contentsOfFile: target, encoding: .utf8) else {
                throw CLIError.invalidInput("Artifact is not readable UTF-8 text: \(path)")
            }
            let report = validateArtifactContent(content)
            var json = report.toJSON()
            json["path"] = target
            if isPathInsideWorkspace(target, workspace: workspace) {
                json["relative_path"] = relativePath(from: target, workspace: workspace)
            }
            try outputJSON(json)
            if !report.isValid {
                throw ExitCode.failure
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List HTML artifacts in the workspace (files carrying the bugbook-artifact marker)"
        )

        @OptionGroup var options: Bugbook.Options

        func run() throws {
            let workspace = normalizePath(options.resolvedWorkspace)
            let fm = FileManager.default
            var items: [[String: Any]] = []

            if let enumerator = fm.enumerator(atPath: workspace) {
                while let relative = enumerator.nextObject() as? String {
                    if WorkspacePathRules.shouldIgnoreRelativePath(relative) { continue }
                    guard relative.lowercased().hasSuffix(".html") else { continue }
                    let absolute = (workspace as NSString).appendingPathComponent(relative)

                    guard let handle = FileHandle(forReadingAtPath: absolute) else { continue }
                    let prefixData = handle.readData(ofLength: ArtifactManifest.scanByteLimit)
                    try? handle.close()
                    let prefix = String(decoding: prefixData, as: UTF8.self)
                    guard let manifest = ArtifactManifest.parse(prefix) else { continue }

                    let attrs = (try? fm.attributesOfItem(atPath: absolute)) ?? [:]
                    var item: [String: Any] = [
                        "relative_path": relative,
                        "path": absolute,
                        "size_bytes": (attrs[.size] as? NSNumber)?.intValue ?? 0,
                    ]
                    if let title = manifest.title { item["title"] = title }
                    if let icon = manifest.icon { item["icon"] = icon }
                    if let generator = manifest.generator { item["generator"] = generator }
                    if let modified = attrs[.modificationDate] as? Date {
                        item["modified_at"] = iso8601String(from: modified)
                    }
                    items.append(item)
                }
            }

            items.sort {
                (($0["relative_path"] as? String) ?? "") < (($1["relative_path"] as? String) ?? "")
            }
            try outputJSON(items)
        }
    }
}

// MARK: - Validation engine

let artifactSizeWarnBytes = 2 * 1024 * 1024
let artifactSizeErrorBytes = 10 * 1024 * 1024

struct ArtifactValidationReport {
    var errors: [String] = []
    var warnings: [String] = []
    var title: String?
    var icon: String?
    var generator: String?
    var sizeBytes: Int = 0

    var isValid: Bool { errors.isEmpty }

    func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "valid": isValid,
            "errors": errors,
            "warnings": warnings,
            "size_bytes": sizeBytes,
        ]
        if let title { json["title"] = title }
        if let icon { json["icon"] = icon }
        if let generator { json["generator"] = generator }
        return json
    }
}

/// Validate artifact HTML for the agent feedback loop. This is a lint, not the
/// security boundary — the rendering sandbox (CSP + content rule list) is the
/// enforcement. Pure function so tests can assert on specific findings.
func validateArtifactContent(_ html: String) -> ArtifactValidationReport {
    var report = ArtifactValidationReport()
    report.sizeBytes = html.utf8.count

    if report.sizeBytes > artifactSizeErrorBytes {
        report.errors.append("Artifact is \(report.sizeBytes) bytes; the maximum is \(artifactSizeErrorBytes) bytes (10 MB). Slim the embedded data or split the artifact.")
    } else if report.sizeBytes > artifactSizeWarnBytes {
        report.warnings.append("Artifact is \(report.sizeBytes) bytes; artifacts over \(artifactSizeWarnBytes) bytes (2 MB) load slowly. Consider slimming the embedded data.")
    }

    if let manifest = ArtifactManifest.parse(artifactScanPrefix(of: html)) {
        report.title = manifest.title
        report.icon = manifest.icon
        report.generator = manifest.generator
        if manifest.version != 1 {
            report.warnings.append("Unknown bugbook-artifact format version \(manifest.version); this build understands version 1.")
        }
        if manifest.title == nil {
            report.warnings.append("Missing <meta name=\"bugbook-title\" ...>; the pane title will fall back to the file name.")
        }
    } else {
        let ns = html as NSString
        if markerMetaRegex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)) != nil {
            report.errors.append("<meta name=\"bugbook-artifact\"> appears after the first \(ArtifactManifest.scanByteLimit) bytes; Bugbook only scans the first \(ArtifactManifest.scanByteLimit) bytes. Move the bugbook meta tags to the top of <head>.")
        } else {
            report.errors.append("Missing required <meta name=\"bugbook-artifact\" content=\"1\"> marker. Add the bugbook meta tags to <head>.")
        }
    }

    validateEmbeddedManifestJSON(in: html, report: &report)
    appendExternalReferenceFindings(in: html, report: &report)
    return report
}

private func artifactScanPrefix(of html: String) -> String {
    String(decoding: Data(html.utf8.prefix(ArtifactManifest.scanByteLimit)), as: UTF8.self)
}

// MARK: - External reference scanning

private let tagRegex = try! NSRegularExpression(
    pattern: "<([a-zA-Z][a-zA-Z0-9:-]*)((?:\"[^\"]*\"|'[^']*'|[^>\"'])*)>",
    options: []
)
private let attributeRegex = try! NSRegularExpression(
    pattern: "(?:^|\\s)(srcset|src|xlink:href|href|poster|formaction|action|data)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
    options: [.caseInsensitive]
)
private let cssURLRegex = try! NSRegularExpression(
    pattern: "url\\(\\s*[\"']?\\s*(?:https?:|wss?:|ws:|file:|//)",
    options: [.caseInsensitive]
)
private let cssImportRegex = try! NSRegularExpression(
    pattern: "@import\\s*(?:url\\(\\s*)?[\"']?\\s*(?:https?:|wss?:|ws:|file:|//)",
    options: [.caseInsensitive]
)
private let markerMetaRegex = try! NSRegularExpression(
    pattern: "<meta\\s[^>]*name\\s*=\\s*[\"']bugbook-artifact[\"']",
    options: [.caseInsensitive]
)
private let manifestScriptRegex = try! NSRegularExpression(
    pattern: "<script\\s[^>]*type\\s*=\\s*[\"']application/bugbook-manifest[\"'][^>]*>(.*?)</script>",
    options: [.caseInsensitive, .dotMatchesLineSeparators]
)
private let httpEquivRefreshRegex = try! NSRegularExpression(
    pattern: "http-equiv\\s*=\\s*[\"']?\\s*refresh",
    options: [.caseInsensitive]
)
private let metaRefreshURLRegex = try! NSRegularExpression(
    pattern: "url\\s*=\\s*[\"']?\\s*(?:https?:|wss?:|//)",
    options: [.caseInsensitive]
)
private let networkAPIRegex = try! NSRegularExpression(
    pattern: "(?:fetch|XMLHttpRequest|WebSocket|EventSource|sendBeacon|importScripts)\\s*\\(\\s*[\"'](?:https?:|wss?:|ws:|//)",
    options: [.caseInsensitive]
)

/// Tags whose href is user-activated navigation (gated behind the native
/// confirmation sheet at render time) rather than a silent resource load.
private let clickNavigationTags: Set<String> = ["a", "area"]

private func appendExternalReferenceFindings(in html: String, report: inout ArtifactValidationReport) {
    let ns = html as NSString
    let fullRange = NSRange(location: 0, length: ns.length)

    for tagMatch in tagRegex.matches(in: html, options: [], range: fullRange) {
        let tagName = ns.substring(with: tagMatch.range(at: 1)).lowercased()
        guard tagMatch.range(at: 2).length > 0 else { continue }
        let attrText = ns.substring(with: tagMatch.range(at: 2))
        let attrNS = attrText as NSString
        let attrRange = NSRange(location: 0, length: attrNS.length)
        let line = lineNumber(at: tagMatch.range.location, in: ns)

        for attrMatch in attributeRegex.matches(in: attrText, options: [], range: attrRange) {
            let name = attrNS.substring(with: attrMatch.range(at: 1)).lowercased()
            let value = unquotedAttributeValue(attrNS.substring(with: attrMatch.range(at: 2)))

            if name == "srcset" {
                for candidate in srcsetCandidates(value) where isExternalReference(candidate) {
                    report.errors.append(externalReferenceError(line: line, context: "srcset on <\(tagName)>", value: candidate))
                }
                continue
            }
            if name == "href", clickNavigationTags.contains(tagName) {
                continue
            }
            if isExternalReference(value) {
                report.errors.append(externalReferenceError(line: line, context: "\(name) on <\(tagName)>", value: value))
            }
        }

        if tagName == "meta",
           httpEquivRefreshRegex.firstMatch(in: attrText, options: [], range: attrRange) != nil,
           metaRefreshURLRegex.firstMatch(in: attrText, options: [], range: attrRange) != nil {
            report.errors.append("line \(line): <meta http-equiv=\"refresh\"> redirects to an external URL — remove it; artifacts cannot navigate on their own.")
        }
    }

    for match in cssURLRegex.matches(in: html, options: [], range: fullRange) {
        report.errors.append("line \(lineNumber(at: match.range.location, in: ns)): external url() reference in CSS — inline the asset as a data: URI or embed the styles directly.")
    }
    for match in cssImportRegex.matches(in: html, options: [], range: fullRange) {
        report.errors.append("line \(lineNumber(at: match.range.location, in: ns)): @import of an external stylesheet — copy the CSS into an inline <style> block.")
    }
    for match in networkAPIRegex.matches(in: html, options: [], range: fullRange) {
        report.warnings.append("line \(lineNumber(at: match.range.location, in: ns)): script calls a network API with an external URL — all network is blocked at render time; embed the data as <script type=\"application/json\"> instead.")
    }
}

private func validateEmbeddedManifestJSON(in html: String, report: inout ArtifactValidationReport) {
    let ns = html as NSString
    guard let match = manifestScriptRegex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)) else {
        return
    }
    let body = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    do {
        let object = try JSONSerialization.jsonObject(with: Data(body.utf8))
        if !(object is [String: Any]) {
            report.errors.append("bugbook-manifest must be a JSON object.")
        }
    } catch {
        report.errors.append("bugbook-manifest JSON does not parse: \(error.localizedDescription)")
    }
    if Data(ns.substring(to: match.range.location).utf8).count > ArtifactManifest.scanByteLimit {
        report.warnings.append("bugbook-manifest script starts after the first \(ArtifactManifest.scanByteLimit) bytes; the app's bounded scan will not see it. Move it into <head> right after the meta tags.")
    }
}

private func externalReferenceError(line: Int, context: String, value: String) -> String {
    "line \(line): external \(context): \"\(truncatedForMessage(value))\" — artifacts must be fully self-contained; inline the resource (data: URI, inline <script>/<style>, embedded JSON). http(s)/ws(s)/file/protocol-relative references are rejected."
}

private func isExternalReference(_ value: String) -> Bool {
    let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return v.hasPrefix("http:") || v.hasPrefix("https:") || v.hasPrefix("ws:")
        || v.hasPrefix("wss:") || v.hasPrefix("file:") || v.hasPrefix("//")
}

private func srcsetCandidates(_ value: String) -> [String] {
    value.components(separatedBy: ",").compactMap { part in
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.components(separatedBy: .whitespaces).first
    }
}

private func unquotedAttributeValue(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count >= 2,
       (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
        value = String(value.dropFirst().dropLast())
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func truncatedForMessage(_ value: String) -> String {
    value.count > 96 ? String(value.prefix(96)) + "…" : value
}

private func lineNumber(at location: Int, in text: NSString) -> Int {
    var line = 1
    let bound = min(location, text.length)
    var index = 0
    while index < bound {
        if text.character(at: index) == 0x0A { line += 1 }
        index += 1
    }
    return line
}

// MARK: - Path resolution

func resolveArtifactWritePath(_ rawPath: String, workspace: String) throws -> String {
    let normalizedWorkspace = normalizePath(workspace)
    let expanded = (rawPath as NSString).expandingTildeInPath
    let absolute = expanded.hasPrefix("/")
        ? normalizePath(expanded)
        : normalizePath((normalizedWorkspace as NSString).appendingPathComponent(rawPath))

    guard isPathInsideWorkspace(absolute, workspace: normalizedWorkspace) else {
        throw CLIError.invalidInput("Artifact path must be inside the workspace: \(rawPath)")
    }
    guard absolute.lowercased().hasSuffix(".html") else {
        throw CLIError.invalidInput("Artifact path must end in .html: \(rawPath)")
    }
    let baseName = ((absolute as NSString).lastPathComponent as NSString).deletingPathExtension
    guard !baseName.isEmpty else {
        throw CLIError.invalidInput("Artifact path must include a file name: \(rawPath)")
    }
    return absolute
}

func resolveArtifactReadPath(_ rawPath: String, workspace: String) throws -> String {
    let expanded = (rawPath as NSString).expandingTildeInPath
    let absolute = expanded.hasPrefix("/")
        ? normalizePath(expanded)
        : normalizePath((normalizePath(workspace) as NSString).appendingPathComponent(rawPath))
    guard FileManager.default.fileExists(atPath: absolute) else {
        throw CLIError.fileNotFound(rawPath)
    }
    return absolute
}
