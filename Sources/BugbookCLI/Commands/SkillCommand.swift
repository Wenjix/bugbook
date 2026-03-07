import ArgumentParser
import Foundation

struct Skill: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill",
        abstract: "Discover markdown skill files in the workspace",
        subcommands: [List.self, Get.self, Create.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List workspace skill files"
        )

        @OptionGroup var options: Bugbook.Options

        @Option(help: "Maximum number of skills to return")
        var limit: Int = 200

        @Option(name: .long, help: "Filter to a relative path prefix under Skills/")
        var pathPrefix: String?

        func run() throws {
            let skills = try listWorkspaceSkills(
                in: options.resolvedWorkspace,
                pathPrefix: pathPrefix
            )
            let output = Array(skills.prefix(limit)).map { $0.toSummaryJSON() }
            try outputJSON(output)
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get a single workspace skill file"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Skill name, relative path, or absolute path")
        var skill: String

        @Flag(name: .long, help: "Exclude raw content fields from the response")
        var metadataOnly: Bool = false

        func run() throws {
            let record = try resolveWorkspaceSkill(skill, workspace: options.resolvedWorkspace)
            try outputJSON(record.toDetailJSON(includeContent: !metadataOnly))
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a workspace skill file"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Skill name or relative path under Skills/")
        var skill: String

        @Option(name: .long, help: "Heading/title for the skill")
        var title: String?

        @Option(name: .long, help: "Short description stored in frontmatter")
        var description: String?

        @Option(name: .long, help: "Initial content file path, or - for stdin")
        var contentFile: String?

        func run() throws {
            let content = try contentFile.map(readTextInput)
            let record = try createWorkspaceSkill(
                rawName: skill,
                workspace: options.resolvedWorkspace,
                title: title,
                description: description,
                content: content
            )
            try outputJSON(record.toDetailJSON())
        }
    }
}
