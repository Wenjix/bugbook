import ArgumentParser
import Foundation

struct Context: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Gather context by traversing wikilinks from a page"
    )

    @OptionGroup var options: Bugbook.Options

    @Argument(help: "Page path, relative path, or page name")
    var page: String

    @Option(name: .long, help: "Maximum link traversal depth")
    var depth: Int = 2

    func run() throws {
        guard depth >= 0 else {
            throw CLIError.invalidInput("Depth must be non-negative")
        }

        let workspace = options.resolvedWorkspace
        let record = try resolveWorkspacePage(page, workspace: workspace)

        var visited = Set<String>()
        var pages: [(name: String, content: String)] = []

        try traverse(record: record, workspace: workspace, remainingDepth: depth, visited: &visited, pages: &pages)

        let output = pages.map { "--- Page: \($0.name) ---\n\($0.content)" }.joined(separator: "\n\n")
        FileHandle.standardOutput.write(Data(output.utf8))
    }

    private func traverse(
        record: WorkspacePageRecord,
        workspace: String,
        remainingDepth: Int,
        visited: inout Set<String>,
        pages: inout [(name: String, content: String)]
    ) throws {
        guard visited.insert(record.path).inserted else { return }

        let content = presentedMarkdown(record.content)
        pages.append((name: record.title, content: content))

        guard remainingDepth > 0 else { return }

        for name in record.wikilinks {
            guard let linked = try? resolveWorkspacePage(name, workspace: workspace) else { continue }
            guard !visited.contains(linked.path) else { continue }
            try traverse(record: linked, workspace: workspace, remainingDepth: remainingDepth - 1, visited: &visited, pages: &pages)
        }
    }
}
