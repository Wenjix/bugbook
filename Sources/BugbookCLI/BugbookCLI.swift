import ArgumentParser
import Foundation
import BugbookCore

@main
struct Bugbook: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bugbook",
        abstract: "Local-first database CLI",
        subcommands: [DB.self, QueryCmd.self, Get.self, Create.self, Update.self, Delete.self, Batch.self, Agent.self, Search.self]
    )

    struct Options: ParsableArguments {
        @Option(help: "Workspace root path")
        var workspace: String = "~/Documents/Bugbook"

        @Option(help: "Output format")
        var format: String = "json"

        /// Expanded workspace path with ~ resolved
        var resolvedWorkspace: String {
            (workspace as NSString).expandingTildeInPath
        }
    }
}
