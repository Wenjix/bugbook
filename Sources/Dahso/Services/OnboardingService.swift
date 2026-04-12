import Foundation

enum OnboardingService {
    /// Checks if the workspace needs onboarding (no .md files at top level).
    /// If so, creates a "Getting Started.md" file and returns its path.
    /// Returns nil if onboarding is not needed.
    static func ensureOnboarding(workspacePath: String) -> String? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: workspacePath) else {
            return nil
        }

        let hasMdFiles = contents.contains { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
        if hasMdFiles { return nil }

        let filePath = (workspacePath as NSString).appendingPathComponent("Getting Started.md")
        let content = """
        # Welcome to Dahso

        Your personal knowledge workspace. Everything lives as local markdown files — no cloud, no lock-in.

        ## Keyboard Shortcuts

        **Cmd+N** — New page
        **Cmd+P** or **Cmd+K** — Command palette
        **/** — Slash commands (headings, lists, code, etc.)
        **Cmd+B** / **Cmd+I** / **Cmd+E** — Bold, italic, inline code
        **Cmd+Shift+1-9** — Quick block type changes
        **[[Page Name]]** — Link to another page

        ## Features

        **Sidebar** — Browse and organize your pages in the file tree. Drag to reorder.
        **Databases** — Create structured tables with properties, filters, and views.
        **Graph View** — Visualize links between your pages.
        **Daily Notes** — Cmd+P, then search "daily" to create today's note.
        **Templates** — Add .md files to a Templates/ folder to reuse them.

        ## Tips

        - Pages can have sub-pages — right-click in the sidebar to create one.
        - Add icons and cover images from the page header.
        - Use the AI side panel (Cmd+L) if you have an API key configured in settings.

        Start writing — delete this page whenever you're ready.
        """

        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            return filePath
        } catch {
            return nil
        }
    }
}
