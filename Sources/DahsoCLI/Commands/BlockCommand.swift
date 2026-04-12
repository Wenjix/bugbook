import ArgumentParser
import Foundation

struct Block: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "block",
        abstract: "Inspect and edit parsed markdown blocks",
        subcommands: [List.self, Get.self, Replace.self, UpdateText.self, Insert.self, Move.self, Delete.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List blocks in a page"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Option(name: .long, help: "Limit output to a markdown heading section")
        var section: String?

        @Option(name: .long, help: "Limit output to the heading that starts on this line number")
        var sectionLine: Int?

        func run() throws {
            let selectorCount = [section != nil, sectionLine != nil].filter { $0 }.count
            if selectorCount > 1 {
                throw CLIError.invalidInput("Use only one selector: --section or --section-line")
            }

            let pageRecord = try resolveWorkspacePage(page, workspace: options.resolvedWorkspace)
            let selectedSection = try resolveWorkspacePageSection(
                pageRecord,
                headingQuery: section,
                sectionLine: sectionLine
            )

            let source = selectedSection?.content ?? pageRecord.body
            let parsed = parsedPageDocumentJSON(from: source)
            var output = pageRecord.toSummaryJSON()
            output["blocks"] = parsed["blocks"]
            output["document_metadata"] = parsed["document_metadata"]
            if let selectedSection {
                output["selected_section"] = selectedSection.toJSON(includeContent: false)
            }
            try outputJSON(output)
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get a single block from a page"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Argument(help: "Block selector (stable UUID or path:0/1)")
        var block: String

        @Flag(name: .long, help: "Print the selected block's markdown content")
        var raw: Bool = false

        func run() throws {
            let pageRecord = try resolveWorkspacePage(page, workspace: options.resolvedWorkspace)
            let selectedBlock = try resolveWorkspacePageBlock(pageRecord, selector: block)

            if raw {
                FileHandle.standardOutput.write(Data(selectedBlock.content.utf8))
                return
            }

            var output = pageRecord.toSummaryJSON()
            output["block"] = selectedBlock.toJSON()
            try outputJSON(output)
        }
    }

    struct Replace: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "replace",
            abstract: "Replace a block with new markdown blocks"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Argument(help: "Block selector (stable UUID or path:0/1)")
        var block: String

        @Option(name: .long, help: "Replacement markdown file path, or - for stdin")
        var contentFile: String

        @Flag(name: .long, help: "Preview the update without writing the page")
        var dryRun: Bool = false

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .summary

        func run() throws {
            let replacement = try readTextInput(from: contentFile)
            let preview = try previewWorkspacePageBlockUpdate(
                query: page,
                workspace: options.resolvedWorkspace,
                blockSelector: block,
                replacementContent: replacement
            )
            try emit(preview: preview, workspace: options.resolvedWorkspace, output: output, dryRun: dryRun, operation: "replace")
        }
    }

    struct UpdateText: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update-text",
            abstract: "Update only a block's text while preserving its markdown type"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Argument(help: "Block selector (stable UUID or path:0/1)")
        var block: String

        @Option(name: .long, help: "Replacement text file path, or - for stdin")
        var textFile: String

        @Flag(name: .long, help: "Preview the update without writing the page")
        var dryRun: Bool = false

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .summary

        func run() throws {
            let replacement = try readTextInput(from: textFile)
            let preview = try previewWorkspacePageBlockTextUpdate(
                query: page,
                workspace: options.resolvedWorkspace,
                blockSelector: block,
                textContent: replacement
            )
            try emit(preview: preview, workspace: options.resolvedWorkspace, output: output, dryRun: dryRun, operation: "update_text")
        }
    }

    struct Insert: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "insert",
            abstract: "Insert markdown blocks before or after an existing block"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Argument(help: "Block selector (stable UUID or path:0/1)")
        var block: String

        @Option(name: .long, help: "Inserted markdown file path, or - for stdin")
        var contentFile: String

        @Flag(name: .long, help: "Insert before the selected block")
        var before: Bool = false

        @Flag(name: .long, help: "Insert after the selected block")
        var after: Bool = false

        @Flag(name: .long, help: "Preview the update without writing the page")
        var dryRun: Bool = false

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .summary

        func run() throws {
            if before == after {
                throw CLIError.invalidInput("Choose exactly one of --before or --after")
            }

            let content = try readTextInput(from: contentFile)
            let preview = try previewWorkspacePageBlockUpdate(
                query: page,
                workspace: options.resolvedWorkspace,
                blockSelector: block,
                prependContent: before ? content : nil,
                appendContent: after ? content : nil
            )
            try emit(preview: preview, workspace: options.resolvedWorkspace, output: output, dryRun: dryRun, operation: "insert")
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Move a block before or after another block"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Argument(help: "Block selector to move (stable UUID or path:0/1)")
        var block: String

        @Argument(help: "Destination block selector (stable UUID or path:0/1)")
        var destination: String

        @Flag(name: .long, help: "Move before the destination block")
        var before: Bool = false

        @Flag(name: .long, help: "Move after the destination block")
        var after: Bool = false

        @Flag(name: .long, help: "Preview the update without writing the page")
        var dryRun: Bool = false

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .summary

        func run() throws {
            if before == after {
                throw CLIError.invalidInput("Choose exactly one of --before or --after")
            }

            let preview = try previewWorkspacePageBlockMove(
                query: page,
                workspace: options.resolvedWorkspace,
                blockSelector: block,
                destinationSelector: destination,
                placeBefore: before
            )
            try emit(preview: preview, workspace: options.resolvedWorkspace, output: output, dryRun: dryRun, operation: "move")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a block from a page"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Page path, relative path, or page name")
        var page: String

        @Argument(help: "Block selector (stable UUID or path:0/1)")
        var block: String

        @Flag(name: .long, help: "Preview the update without writing the page")
        var dryRun: Bool = false

        @Option(name: .long, help: "Response payload mode: full or summary")
        var output: MutationOutputMode = .summary

        func run() throws {
            let preview = try previewWorkspacePageBlockUpdate(
                query: page,
                workspace: options.resolvedWorkspace,
                blockSelector: block,
                replacementContent: ""
            )
            try emit(preview: preview, workspace: options.resolvedWorkspace, output: output, dryRun: dryRun, operation: "delete")
        }
    }
}

private func emit(
    preview: WorkspacePageBlockUpdatePreview,
    workspace: String,
    output: MutationOutputMode,
    dryRun: Bool,
    operation: String
) throws {
    if !dryRun {
        try preview.updated.content.write(toFile: preview.original.path, atomically: true, encoding: .utf8)
    }

    switch output {
    case .full:
        if dryRun {
            try outputJSON(preview.toJSON())
        } else {
            let record = try loadWorkspacePage(at: preview.original.path, relativeTo: workspace)
            try outputJSON(record.toDetailJSON())
        }
    case .summary:
        if dryRun {
            try outputJSON(blockUpdateSummaryJSON(preview, operation: operation, dryRun: true))
        } else {
            let record = try loadWorkspacePage(at: preview.original.path, relativeTo: workspace)
            try outputJSON(blockUpdateSummaryJSON(record, preview: preview, operation: operation, dryRun: false))
        }
    }
}
