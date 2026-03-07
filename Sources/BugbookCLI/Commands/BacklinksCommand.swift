import ArgumentParser
import Foundation

struct Backlinks: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backlinks",
        abstract: "Find pages that link to a page"
    )

    @OptionGroup var options: Bugbook.Options

    @Argument(help: "Page path, relative path, or page name")
    var page: String

    func run() throws {
        let backlinks = try backlinksForPage(query: page, workspace: options.resolvedWorkspace)
        try outputJSON([
            "page": page,
            "results": backlinks,
            "total_count": backlinks.count,
        ])
    }
}
