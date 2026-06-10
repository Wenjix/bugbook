import Foundation

/// Assembles AI chat prompts from a question plus referenced workspace files.
/// One place owns the rules: at most `maxReferences` files, workspace-only
/// paths, per-file truncation, fenced-snippet formatting, and the @-mention
/// display form. File access goes through the `readFile` seam, so the rules
/// are testable without disk and callers can run assembly off the main thread.
enum ChatPromptAssembly {
    struct Reference: Equatable, Sendable {
        let path: String
        let name: String
    }

    static let maxReferences = 6
    static let maxCharactersPerFile = 8_000

    /// Display form of a referenced file's name (strips the .md extension).
    static func displayName(for name: String) -> String {
        name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    /// The message shown in the thread: the question plus @-mentions.
    static func displayMessage(question: String, references: [Reference]) -> String {
        guard !references.isEmpty else { return question }
        let refs = references.map { "@\(displayName(for: $0.name))" }.joined(separator: " ")
        return "\(question)\n\n\(refs)"
    }

    /// The full prompt sent to the AI engine: the question plus fenced,
    /// truncated snippets of each referenced workspace file. Reads files via
    /// `readFile`; with the default disk reader, call off the main thread.
    static func prompt(
        question: String,
        references: [Reference],
        workspacePath: String,
        readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) -> String {
        guard !references.isEmpty else { return question }
        var sections: [String] = []

        for reference in references.prefix(maxReferences) {
            let path = reference.path
            let relative = relativePath(for: path, workspacePath: workspacePath)
            guard !workspacePath.isEmpty, path.hasPrefix(workspacePath) else { continue }

            if let content = readFile(path) {
                let snippet = String(content.prefix(maxCharactersPerFile))
                let truncated = content.count > snippet.count ? "\n...[truncated]" : ""
                sections.append(
                    """
                    File: \(relative)
                    ```text
                    \(snippet)\(truncated)
                    ```
                    """
                )
            } else {
                sections.append("File: \(relative)\n[Could not read file content]")
            }
        }

        if sections.isEmpty { return question }

        return """
        \(question)

        Referenced files (treat these as primary context):

        \(sections.joined(separator: "\n\n"))
        """
    }

    private static func relativePath(for path: String, workspacePath: String) -> String {
        guard !workspacePath.isEmpty, path.hasPrefix(workspacePath) else { return path }
        let relative = path.dropFirst(workspacePath.count)
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
    }
}
