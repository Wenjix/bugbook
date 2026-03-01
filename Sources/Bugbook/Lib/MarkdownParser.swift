import Foundation

struct MarkdownParser {

    // MARK: - Metadata Parsing

    /// Parse icon from <!-- icon:VALUE --> comment
    static func parseIcon(from content: String) -> String? {
        let pattern = "<!--\\s*icon:\\s*(.*?)\\s*-->"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        let value = String(content[range]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Parse cover from <!-- cover:URL --> comment
    static func parseCover(from content: String) -> String? {
        let pattern = "<!--\\s*cover:\\s*(.*?)\\s*-->"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        let value = String(content[range]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Parse full-width from <!-- full-width:true --> comment
    static func parseFullWidth(from content: String) -> Bool {
        let pattern = "<!--\\s*full-width:\\s*(true|false)\\s*-->"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return false }
        return String(content[range]) == "true"
    }

    /// Extract the first H1 title from content
    static func parseTitle(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
            // Skip metadata comments
            if trimmed.hasPrefix("<!--") { continue }
            if trimmed.isEmpty { continue }
            break // Non-metadata, non-empty, non-H1 line reached
        }
        return nil
    }

    /// Get body content (everything after metadata + H1 title)
    static func parseBody(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var foundTitle = false
        var bodyStartIndex = 0

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<!--") { continue }
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("# ") && !foundTitle {
                foundTitle = true
                bodyStartIndex = index + 1
                // Skip blank line after title
                if bodyStartIndex < lines.count && lines[bodyStartIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                    bodyStartIndex += 1
                }
                break
            }
            break
        }

        if !foundTitle { return content }

        let bodyLines = Array(lines[bodyStartIndex...])
        return bodyLines.joined(separator: "\n")
    }

    // MARK: - Content Reconstruction

    /// Set icon in content (add/replace/remove the <!-- icon: --> comment)
    static func setIcon(_ icon: String?, in content: String) -> String {
        var result = removeMetadata("icon", from: content)
        if let icon = icon {
            result = "<!-- icon:\(icon) -->\n" + result
        }
        return result
    }

    /// Set cover in content
    static func setCover(_ cover: String?, in content: String) -> String {
        var result = removeMetadata("cover", from: content)
        if let cover = cover {
            let iconLine = parseIcon(from: content).map { "<!-- icon:\($0) -->\n" } ?? ""
            // Insert after icon if exists
            if !iconLine.isEmpty {
                result = removeMetadata("icon", from: result)
                result = iconLine + "<!-- cover:\(cover) -->\n" + result
            } else {
                result = "<!-- cover:\(cover) -->\n" + result
            }
        }
        return result
    }

    /// Reconstruct full content from parts
    static func reconstructContent(title: String, body: String, icon: String?, cover: String?, fullWidth: Bool) -> String {
        var parts: [String] = []

        if let icon = icon {
            parts.append("<!-- icon:\(icon) -->")
        }
        if let cover = cover {
            parts.append("<!-- cover:\(cover) -->")
        }
        if fullWidth {
            parts.append("<!-- full-width:true -->")
        }
        parts.append("# \(title)")
        parts.append("")
        parts.append(body)

        return parts.joined(separator: "\n")
    }

    /// Extract all wiki link names from content
    static func extractWikiLinks(from content: String) -> [String] {
        let pattern = "\\[\\[([^\\]]+)\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[r])
        }
    }

    // MARK: - Helpers

    private static func removeMetadata(_ key: String, from content: String) -> String {
        let pattern = "<!--\\s*\(key):.*?-->\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
    }
}
