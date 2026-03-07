import ArgumentParser
import Foundation

struct Board: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Create kanban boards in the workspace",
        subcommands: [Create.self, AddCard.self, MoveCard.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a kanban board database and optionally embed it into a page"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Board name")
        var name: String

        @Option(name: .long, help: "Relative directory inside the workspace (default: databases)")
        var directory: String = "databases"

        @Option(name: .long, help: "Grouping property name for the kanban view")
        var groupName: String = "Status"

        @Option(name: .long, parsing: .singleValue, help: "Column name (repeatable)")
        var column: [String] = []

        @Option(name: .long, parsing: .singleValue, help: "Additional view type to create (repeatable): table, list, calendar, kanban")
        var view: [String] = []

        @Flag(name: .long, help: "Do not add the default table view unless explicitly requested with --view table")
        var noTable: Bool = false

        @Option(name: .long, help: "Date property name used when calendar view is included")
        var datePropertyName: String = "Date"

        @Option(name: .long, help: "Append the board embed to this page after creation")
        var embedIn: String?

        func run() throws {
            let output = try createWorkspaceBoard(
                name: name,
                workspace: options.resolvedWorkspace,
                directory: directory,
                groupName: groupName,
                columns: column,
                extraViews: view,
                includeDefaultTableView: !noTable,
                datePropertyName: datePropertyName,
                embedInPage: embedIn
            )
            try outputJSON(output)
        }
    }

    struct AddCard: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add-card",
            abstract: "Create a new card in a board"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Board name, ID, or path")
        var board: String

        @Argument(help: "Card title")
        var title: String

        @Option(name: .long, help: "Board column name or option ID")
        var column: String?

        @Option(name: .long, parsing: .singleValue, help: "Additional property value (key=value, repeatable)")
        var set: [String] = []

        @Option(name: .long, help: "Date value for the board date property (YYYY-MM-DD)")
        var date: String?

        @Option(name: .long, help: "Body content file path, or - for stdin")
        var bodyFile: String?

        func run() throws {
            let body = try bodyFile.map(readTextInput)
            let output = try addBoardCard(
                boardQuery: board,
                title: title,
                columnQuery: column,
                propertyPairs: set,
                date: date,
                body: body,
                workspace: options.resolvedWorkspace
            )
            try outputJSON(output)
        }
    }

    struct MoveCard: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move-card",
            abstract: "Move an existing card to another board column"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Board name, ID, or path")
        var board: String

        @Argument(help: "Row ID")
        var rowId: String

        @Argument(help: "Destination column name or option ID")
        var column: String

        func run() throws {
            let output = try moveBoardCard(
                boardQuery: board,
                rowId: rowId,
                columnQuery: column,
                workspace: options.resolvedWorkspace
            )
            try outputJSON(output)
        }
    }
}
