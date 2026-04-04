import ArgumentParser
import Foundation
import BugbookCore

@main
struct Bugbook: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bugbook",
        abstract: "Local-first notes, databases, and agent workspace CLI",
        subcommands: [Page.self, Block.self, Backlinks.self, Context.self, Skill.self, Board.self, DB.self, QueryCmd.self, Get.self, Create.self, Update.self, Delete.self, Batch.self, Agent.self, Search.self, Install.self, Settings.self]
    )

    struct Options: ParsableArguments {
        @Option(help: "Workspace root path")
        var workspace: String = {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documents.appendingPathComponent("Bugbook", isDirectory: true).path
        }()

        @Option(help: "Output format")
        var format: String = "json"

        /// Expanded workspace path with ~ resolved
        var resolvedWorkspace: String {
            (workspace as NSString).expandingTildeInPath
        }
    }
}
