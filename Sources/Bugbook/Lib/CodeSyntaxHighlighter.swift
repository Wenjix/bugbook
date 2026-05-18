import AppKit
import Foundation

enum CodeSyntaxHighlighter {
    static let keywordColor = NSColor(red: 0.741, green: 0.353, blue: 0.949, alpha: 1.0)
    static let typeColor = NSColor(red: 0.145, green: 0.525, blue: 0.804, alpha: 1.0)
    static let stringColor = NSColor(red: 0.788, green: 0.396, blue: 0.184, alpha: 1.0)
    static let commentColor = NSColor.secondaryLabelColor
    static let numberColor = NSColor(red: 0.192, green: 0.604, blue: 0.459, alpha: 1.0)

    static func attributedString(
        from code: String,
        language: String,
        font: NSFont,
        textColor: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
        applyHighlighting(to: result, language: language, font: font, textColor: textColor)
        return result
    }

    static func applyHighlighting(
        to storage: NSMutableAttributedString,
        language: String,
        font: NSFont,
        textColor: NSColor
    ) {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        storage.setAttributes([
            .font: font,
            .foregroundColor: textColor
        ], range: fullRange)

        applyPattern("\\b\\d+(?:\\.\\d+)?\\b", color: numberColor, to: storage)
        applyKeywordHighlights(language: language, to: storage)
        applyStringHighlights(to: storage)
        applyCommentHighlights(language: language, to: storage)
    }

    private static func applyKeywordHighlights(language: String, to storage: NSMutableAttributedString) {
        let keywords = keywords(for: language)
        guard !keywords.isEmpty else { return }
        let pattern = "\\b(" + keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b"
        applyPattern(pattern, color: keywordColor, to: storage)

        let types = typeKeywords(for: language)
        guard !types.isEmpty else { return }
        let typePattern = "\\b(" + types.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b"
        applyPattern(typePattern, color: typeColor, to: storage)
    }

    private static func applyStringHighlights(to storage: NSMutableAttributedString) {
        applyPattern(#""([^"\\]|\\.)*""#, color: stringColor, to: storage)
        applyPattern(#"'([^'\\]|\\.)*'"#, color: stringColor, to: storage)
    }

    private static func applyCommentHighlights(language: String, to storage: NSMutableAttributedString) {
        let normalized = normalizedLanguage(language)
        if ["python", "py", "bash", "shell", "sh", "zsh", "yaml", "yml"].contains(normalized) {
            applyPattern("#.*", color: commentColor, to: storage)
        }
        if normalized != "json" {
            applyPattern("//.*", color: commentColor, to: storage)
            applyPattern(#"/\*[\s\S]*?\*/"#, color: commentColor, to: storage)
        }
    }

    private static func applyPattern(
        _ pattern: String,
        color: NSColor,
        to storage: NSMutableAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: storage.length)
        regex.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range, matchRange.location != NSNotFound else { return }
            storage.addAttribute(.foregroundColor, value: color, range: matchRange)
        }
    }

    private static func keywords(for language: String) -> [String] {
        switch normalizedLanguage(language) {
        case "swift":
            [
                "actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class",
                "continue", "defer", "do", "else", "enum", "extension", "false", "for", "func",
                "guard", "if", "import", "in", "init", "inout", "let", "nil", "private", "protocol",
                "public", "return", "self", "static", "struct", "switch", "throw", "throws", "true",
                "try", "var", "where", "while"
            ]
        case "javascript", "js", "typescript", "ts", "tsx", "jsx":
            [
                "async", "await", "break", "case", "catch", "class", "const", "continue", "default",
                "else", "export", "false", "for", "from", "function", "if", "import", "in",
                "interface", "let", "new", "null", "return", "switch", "this", "throw", "true",
                "try", "type", "undefined", "var", "while"
            ]
        case "python", "py":
            [
                "and", "as", "async", "await", "break", "class", "continue", "def", "elif", "else",
                "except", "False", "finally", "for", "from", "if", "import", "in", "is", "lambda",
                "None", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"
            ]
        case "json":
            ["false", "null", "true"]
        case "bash", "shell", "sh", "zsh":
            [
                "case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if",
                "in", "then", "while"
            ]
        default:
            []
        }
    }

    private static func typeKeywords(for language: String) -> [String] {
        switch normalizedLanguage(language) {
        case "swift":
            ["Bool", "Character", "Data", "Date", "Double", "Float", "Int", "String", "UUID", "URL"]
        case "typescript", "ts", "tsx":
            ["Array", "boolean", "number", "Promise", "Record", "string", "unknown", "void"]
        default:
            []
        }
    }

    private static func normalizedLanguage(_ language: String) -> String {
        language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
