import ArgumentParser
import Foundation

struct Flashcard: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flashcard",
        abstract: "Manage flashcard blocks across the workspace",
        subcommands: [List.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all flashcard blocks across workspace pages"
        )

        @OptionGroup var options: Bugbook.Options

        func run() throws {
            let pages = try listWorkspacePages(in: options.resolvedWorkspace)
            var flashcards: [[String: Any]] = []

            func textLines(from block: [String: Any]) -> [String] {
                var lines: [String] = []
                if let text = block["text"] as? String, !text.isEmpty {
                    lines.append(text)
                }
                if let children = block["children"] as? [[String: Any]] {
                    for child in children {
                        lines.append(contentsOf: textLines(from: child))
                    }
                }
                return lines
            }

            func collectFlashcards(
                from blocks: [[String: Any]],
                pagePath: String
            ) {
                for block in blocks {
                    if block["type"] as? String == "flashcard" {
                        var card: [String: Any] = [
                            "front": block["text"] as? String ?? "",
                            "page": pagePath,
                        ]
                        if let children = block["children"] as? [[String: Any]] {
                            let backText = children.flatMap(textLines(from:)).joined(separator: "\n")
                            card["back"] = backText
                        }
                        if let id = block["id"] as? String {
                            card["id"] = id
                        }
                        flashcards.append(card)
                    }

                    if let children = block["children"] as? [[String: Any]], !children.isEmpty {
                        collectFlashcards(from: children, pagePath: pagePath)
                    }
                }
            }

            for page in pages {
                let parsed = parsedPageDocumentJSON(from: page.body)
                guard let blocks = parsed["blocks"] as? [[String: Any]] else { continue }
                collectFlashcards(from: blocks, pagePath: page.relativePath)
            }

            try outputJSON(flashcards)
        }
    }
}
