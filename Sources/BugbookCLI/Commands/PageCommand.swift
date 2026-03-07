import ArgumentParser
import Foundation

struct Page: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "page",
        abstract: "Read and write markdown pages in the workspace",
        subcommands: [List.self, Get.self, Headings.self, Format.self, Compact.self, EnsureBlockIDs.self, StripBlockIDs.self, Create.self, Update.self, EmbedDatabase.self, Delete.self]
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

        @Option(name: .long, help: "Limit output to a markdown heading section")
        var section: String?

        @Option(name: .long, help: "Limit output to the heading that starts on this line number")
        var sectionLine: Int?

        @Option(name: .long, help: "Limit output to a block selector (stable UUID or path:0/1)")
        var blockId: String?

        @Flag(name: .long, help: "Print raw markdown content instead of JSON")
        var raw: Bool = false

        @Flag(name: .long, help: "Include internal Bugbook markdown comments such as persisted block IDs")
        var includeInternalComments: Bool = false

        @Flag(name: .long, help: "Include parsed markdown blocks and document metadata in the JSON response")
        var blocks: Bool = false

        @Flag(name: .long, help: "Exclude raw content fields from the response")
        var metadataOnly: Bool = false

        func run() throws {
            let record = try resolveWorkspacePage(page, workspace: options.resolvedWorkspace)
            let selectorCount = [section != nil, sectionLine != nil, blockId != nil].filter { $0 }.count
            if selectorCount > 1 {
                throw CLIError.invalidInput("Use only one selector: --section, --section-line, or --block-id")
            }
            let selectedSection = try resolveWorkspacePageSection(
                record,
                headingQuery: section,
                sectionLine: sectionLine
            )
            let selectedBlock = try blockId.map { try resolveWorkspacePageBlock(record, selector: $0) }

            if raw {
                if metadataOnly || blocks {
                    throw CLIError.invalidInput("--raw cannot be combined with --metadata-only or --blocks")
                }
                let rawContent = selectedBlock?.content ?? selectedSection?.content ?? record.content
                let output = presentedMarkdown(rawContent, includeInternalComments: includeInternalComments)
                FileHandle.standardOutput.write(Data(output.utf8))
                return
            }

            var output = record.toDetailJSON(
                includeContent: !metadataOnly && selectedSection == nil && selectedBlock == nil,
                includeInternalComments: includeInternalComments
            )
            if let selectedBlock {
                output["selected_block"] = selectedBlock.toJSON(includeContent: !metadataOnly)
                if !metadataOnly {
                    output["content"] = selectedBlock.content
                }
            }
            if let selectedSection {
                output["selected_section"] = selectedSection.toJSON(
                    includeContent: !metadataOnly,
                    includeInternalComments: includeInternalComments
                )
                if !metadataOnly {
                    output["content"] = presentedMarkdown(
                        selectedSection.content,
                        includeInternalComments: includeInternalComments
                    )
                    output["body"] = presentedMarkdown(
                        selectedSection.body,
                        includeInternalComments: includeInternalComments
                    )
                }
            }
            if blocks {
                let parsed = parsedPageDocumentJSON(from: selectedBlock?.content ?? selectedSection?.content ?? record.body)
                output["document_metadata"] = parsed["document_metadata"]
                output["blocks"] = parsed["blocks"]
            }
            try outputJSON(output)
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

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .full

        func run() throws {
            let content = try contentFile.map(readTextInput)
            let record = try createWorkspacePage(
                rawPath: page,
                workspace: options.resolvedWorkspace,
                title: title,
                content: content
            )
            switch output {
            case .full:
                try outputJSON(record.toDetailJSON())
            case .summary:
                try outputJSON(pageWriteSummaryJSON(record, operation: "create"))
            }
        }
    }

    struct Headings: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "headings",
            abstract: "List markdown headings in a page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        func run() throws {
            let pageRecord = try resolveWorkspacePage(page, workspace: options.resolvedWorkspace)
            try outputJSON(pageHeadingsJSON(for: pageRecord))
        }
    }

    struct Format: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "format",
            abstract: "Rewrite a markdown page using an explicit markdown formatting style"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Option(name: .long, help: "Formatting style: bugbook or commonmark")
        var style: PageMarkdownFormatStyle = .bugbook

        @Flag(name: .long, help: "Preview the rewrite without writing the page")
        var dryRun: Bool = false

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .full

        func run() throws {
            let preview = try previewWorkspacePageFormat(
                query: page,
                workspace: options.resolvedWorkspace,
                style: style
            )
            try emitFormatResult(
                preview: preview,
                workspace: options.resolvedWorkspace,
                operation: "format",
                output: output,
                dryRun: dryRun,
                style: style
            )
        }
    }

    struct Compact: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compact",
            abstract: "Rewrite a markdown page using Bugbook's compact block formatting"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Flag(name: .long, help: "Preview the rewrite without writing the page")
        var dryRun: Bool = false

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .full

        func run() throws {
            let preview = try previewWorkspacePageCompact(
                query: page,
                workspace: options.resolvedWorkspace
            )
            try emitFormatResult(
                preview: preview,
                workspace: options.resolvedWorkspace,
                operation: "compact",
                output: output,
                dryRun: dryRun,
                style: .bugbook
            )
        }
    }

    struct EnsureBlockIDs: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ensure-block-ids",
            abstract: "Persist stable block IDs into a markdown page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Flag(name: .long, help: "Include parsed block JSON in the response")
        var blocks: Bool = false

        func run() throws {
            var output = try ensureWorkspacePageBlockIDs(
                query: page,
                workspace: options.resolvedWorkspace
            )
            if !blocks {
                output.removeValue(forKey: "blocks")
            }
            try outputJSON(output)
        }
    }

    struct StripBlockIDs: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "strip-block-ids",
            abstract: "Remove persisted block ID comments from a markdown page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        func run() throws {
            let output = try stripWorkspacePageBlockIDs(
                query: page,
                workspace: options.resolvedWorkspace
            )
            try outputJSON(output)
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

        @Option(name: .long, help: "Limit the update to the body of a markdown heading section")
        var section: String?

        @Option(name: .long, help: "Limit the update to the heading that starts on this line number")
        var sectionLine: Int?

        @Option(name: .long, help: "Limit the update to a block selector (stable UUID or path:0/1)")
        var blockId: String?

        @Flag(name: .long, help: "Create the section at the end of the page if it does not exist")
        var createSection: Bool = false

        @Option(name: .long, help: "Heading level to use when creating a missing section")
        var sectionLevel: Int?

        @Option(name: .long, help: "Replace the entire page from a file, or - for stdin")
        var contentFile: String?

        @Option(name: .long, help: "Prepend content from a file, or - for stdin")
        var prependFile: String?

        @Option(name: .long, help: "Append content from a file, or - for stdin")
        var appendFile: String?

        @Option(name: .long, help: "Replace only the selected block's text without changing its markdown type")
        var textFile: String?

        @Flag(name: .long, help: "Preview the update without writing the page")
        var dryRun: Bool = false

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .full

        func run() throws {
            let replacement = try contentFile.map(readTextInput)
            let prepend = try prependFile.map(readTextInput)
            let append = try appendFile.map(readTextInput)
            let textReplacement = try textFile.map(readTextInput)

            guard replacement != nil || prepend != nil || append != nil || textReplacement != nil else {
                throw CLIError.invalidInput("Provide at least one of --content-file, --prepend-file, --append-file, or --text-file")
            }
            if replacement != nil && (prepend != nil || append != nil || textReplacement != nil) {
                throw CLIError.invalidInput("--content-file cannot be combined with --prepend-file, --append-file, or --text-file")
            }
            if textReplacement != nil && (replacement != nil || prepend != nil || append != nil) {
                throw CLIError.invalidInput("--text-file cannot be combined with --content-file, --prepend-file, or --append-file")
            }
            let selectorCount = [section != nil, sectionLine != nil, blockId != nil].filter { $0 }.count
            if selectorCount > 1 {
                throw CLIError.invalidInput("Use only one selector: --section, --section-line, or --block-id")
            }
            if textReplacement != nil && blockId == nil {
                throw CLIError.invalidInput("--text-file requires --block-id")
            }
            if createSection && (section == nil || section?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
                throw CLIError.invalidInput("--create-section requires --section")
            }
            if createSection && (sectionLine != nil || blockId != nil) {
                throw CLIError.invalidInput("--create-section cannot be combined with --section-line or --block-id")
            }
            if sectionLevel != nil && ((section == nil || section?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) || blockId != nil) {
                throw CLIError.invalidInput("--section-level requires --section")
            }

            if let blockId {
                let preview: WorkspacePageBlockUpdatePreview
                if let textReplacement {
                    preview = try previewWorkspacePageBlockTextUpdate(
                        query: page,
                        workspace: options.resolvedWorkspace,
                        blockSelector: blockId,
                        textContent: textReplacement
                    )
                } else {
                    preview = try previewWorkspacePageBlockUpdate(
                        query: page,
                        workspace: options.resolvedWorkspace,
                        blockSelector: blockId,
                        replacementContent: replacement,
                        prependContent: prepend,
                        appendContent: append
                    )
                }

                if !dryRun {
                    try preview.updated.content.write(toFile: preview.original.path, atomically: true, encoding: .utf8)
                }

                if dryRun {
                    switch output {
                    case .full: try outputJSON(preview.toJSON())
                    case .summary: try outputJSON(blockUpdateSummaryJSON(preview, operation: "update", dryRun: true))
                    }
                } else {
                    let record = try loadWorkspacePage(at: preview.original.path, relativeTo: options.resolvedWorkspace)
                    switch output {
                    case .full: try outputJSON(record.toDetailJSON())
                    case .summary: try outputJSON(blockUpdateSummaryJSON(record, preview: preview, operation: "update", dryRun: false))
                    }
                }
            } else {
                let preview = try previewWorkspacePageUpdate(
                    query: page,
                    workspace: options.resolvedWorkspace,
                    section: section,
                    sectionLine: sectionLine,
                    createSectionIfMissing: createSection,
                    sectionLevel: sectionLevel,
                    replacementContent: replacement,
                    prependContent: prepend,
                    appendContent: append
                )

                if !dryRun {
                    try preview.updated.content.write(toFile: preview.original.path, atomically: true, encoding: .utf8)
                }

                if dryRun {
                    switch output {
                    case .full: try outputJSON(preview.toJSON())
                    case .summary: try outputJSON(pageUpdateSummaryJSON(preview, dryRun: true))
                    }
                } else {
                    let record = try loadWorkspacePage(at: preview.original.path, relativeTo: options.resolvedWorkspace)
                    switch output {
                    case .full: try outputJSON(record.toDetailJSON())
                    case .summary: try outputJSON(pageMutationSummaryJSON(record, preview: preview, operation: "update", dryRun: false))
                    }
                }
            }
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

private func emitFormatResult(
    preview: WorkspacePageUpdatePreview,
    workspace: String,
    operation: String,
    output: MutationOutputMode,
    dryRun: Bool,
    style: PageMarkdownFormatStyle
) throws {
    if dryRun {
        switch output {
        case .full:
            var json = preview.toJSON()
            json["format_style"] = style.rawValue
            try outputJSON(json)
        case .summary:
            var json = pageMutationSummaryJSON(preview, operation: operation, dryRun: true)
            json["format_style"] = style.rawValue
            try outputJSON(json)
        }
        return
    }

    try preview.updated.content.write(toFile: preview.original.path, atomically: true, encoding: .utf8)
    switch output {
    case .full:
        let record = try loadWorkspacePage(at: preview.original.path, relativeTo: workspace)
        var json = record.toDetailJSON()
        json["format_style"] = style.rawValue
        try outputJSON(json)
    case .summary:
        let record = try loadWorkspacePage(at: preview.original.path, relativeTo: workspace)
        var json = pageMutationSummaryJSON(record, preview: preview, operation: operation, dryRun: false)
        json["format_style"] = style.rawValue
        try outputJSON(json)
    }
}
