import SwiftUI

/// Read-only view for agent skill files (SKILL.md).
/// Parses YAML frontmatter for name/description and renders the body as styled markdown.
struct SkillDetailView: View {
    let filePath: String
    let displayName: String

    @State private var markdownBody: String = ""
    @State private var skillDescription: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 24, weight: .bold))
                        if let desc = skillDescription {
                            Text(desc)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.bottom, 20)

                // Read-only badge
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text("Read-only skill file")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05))
                .clipShape(.rect(cornerRadius: 6))
                .padding(.bottom, 16)

                // Markdown content
                Text(LocalizedStringKey(markdownBody))
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(40)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.fallbackEditorBg)
        .onAppear { loadContent() }
        .onChange(of: filePath) { _, _ in loadContent() }
    }

    private func loadContent() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let content = String(data: data, encoding: .utf8) else {
            markdownBody = "Unable to read skill file."
            return
        }
        let (desc, body) = Self.stripFrontmatter(content)
        skillDescription = desc
        markdownBody = body
    }

    /// Strips YAML frontmatter and extracts the description field.
    static func stripFrontmatter(_ content: String) -> (description: String?, body: String) {
        guard content.hasPrefix("---") else { return (nil, content) }
        let lines = content.components(separatedBy: "\n")
        var description: String?
        var endIndex = 0

        for (i, line) in lines.dropFirst().enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                endIndex = i + 2 // +1 for dropFirst offset, +1 to skip the closing ---
                break
            }
            if trimmed.hasPrefix("description:") {
                let value = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { description = value }
            }
        }

        if endIndex > 0, endIndex < lines.count {
            let body = lines[endIndex...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (description, body)
        }
        return (description, content)
    }
}
