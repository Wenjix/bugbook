import ArgumentParser
import Foundation

struct Page: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "page",
        abstract: "Read and write markdown pages in the workspace",
        subcommands: [List.self, Get.self, Create.self, Update.self, EmbedDatabase.self, Delete.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List markdown pages in the workspace"
        )

        @OptionGroup var options: Bugbook.Options

        @Option(help: "Maximum number of pages to return")
        var limit: Int = 200

        @Option(name: .long, help: "Filter by frontmatter type")
        var type: String?

        @Option(name: .long, help: "Filter by tag (frontmatter tags or #hashtags)")
        var tag: String?

        @Option(name: .long, help: "Filter to a relative path prefix")
        var pathPrefix: String?

        func run() throws {
            let pages = try listWorkspacePages(
                in: options.resolvedWorkspace,
                pathPrefix: pathPrefix,
                type: type,
                tag: tag
            )

            let output = Array(pages.prefix(limit)).map { $0.toSummaryJSON() }
            try outputJSON(output)
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get a single markdown page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Flag(name: .long, help: "Exclude raw content fields from the response")
        var metadataOnly: Bool = false

        func run() throws {
            let record = try resolveWorkspacePage(page, workspace: options.resolvedWorkspace)
            try outputJSON(record.toDetailJSON(includeContent: !metadataOnly))
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new markdown page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "New page path or name")
        var page: String

        @Option(name: .long, help: "Page title used for default content")
        var title: String?

        @Option(name: .long, help: "Initial content file path, or - for stdin")
        var contentFile: String?

        func run() throws {
            let content = try contentFile.map(readTextInput)
            let record = try createWorkspacePage(
                rawPath: page,
                workspace: options.resolvedWorkspace,
                title: title,
                content: content
            )
            try outputJSON(record.toDetailJSON())
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update an existing markdown page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Option(name: .long, help: "Replace the entire page from a file, or - for stdin")
        var contentFile: String?

        @Option(name: .long, help: "Prepend content from a file, or - for stdin")
        var prependFile: String?

        @Option(name: .long, help: "Append content from a file, or - for stdin")
        var appendFile: String?

        func run() throws {
            let replacement = try contentFile.map(readTextInput)
            let prepend = try prependFile.map(readTextInput)
            let append = try appendFile.map(readTextInput)

            guard replacement != nil || prepend != nil || append != nil else {
                throw CLIError.invalidInput("Provide at least one of --content-file, --prepend-file, or --append-file")
            }
            if replacement != nil && (prepend != nil || append != nil) {
                throw CLIError.invalidInput("--content-file cannot be combined with --prepend-file or --append-file")
            }

            let record = try updateWorkspacePage(
                query: page,
                workspace: options.resolvedWorkspace,
                replacementContent: replacement,
                prependContent: prepend,
                appendContent: append
            )
            try outputJSON(record.toDetailJSON())
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a markdown page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Flag(name: .long, help: "Also delete companion folder content")
        var recursive: Bool = false

        func run() throws {
            let output = try deleteWorkspacePage(
                query: page,
                workspace: options.resolvedWorkspace,
                recursive: recursive
            )
            try outputJSON(output)
        }
    }

    struct EmbedDatabase: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "embed-database",
            abstract: "Append a database embed marker to a page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Argument(help: "Database name, ID, path, or relative path")
        var database: String

        func run() throws {
            let output = try embedDatabaseInPage(
                pageQuery: page,
                databaseQuery: database,
                workspace: options.resolvedWorkspace
            )
            try outputJSON(output)
        }
    }
}
