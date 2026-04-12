import Foundation
import AppKit

/// Converts between markdown inline formatting and NSAttributedString.
enum AttributedStringConverter {

    // MARK: - Custom Attribute Keys

    /// Stores the original markdown source for round-trip fidelity.
    static let markdownSourceKey = NSAttributedString.Key("DahsoMarkdownSource")

    /// Stores the page name for @[[mention]] spans so clicks can navigate.
    static let mentionPageNameKey = NSAttributedString.Key("DahsoMentionPageName")

    // MARK: - Markdown -> NSAttributedString

    /// Parses inline markdown formatting into an attributed string.
    static func attributedString(
        from markdown: String,
        font: NSFont = .systemFont(ofSize: EditorTypography.bodyFontSize),
        textColor: NSColor = .labelColor
    ) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        guard !markdown.isEmpty else {
            return NSAttributedString(string: "", attributes: baseAttributes)
        }

        let result = NSMutableAttributedString()
        var i = markdown.startIndex

        while i < markdown.endIndex {
            // Bold: **text** or __text__
            if let (text, end) = parseDelimited(markdown, from: i, delimiter: "**") {
                let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                var attrs = baseAttributes
                attrs[.font] = boldFont
                attrs[Self.markdownSourceKey] = "**\(text)**"
                result.append(NSAttributedString(string: text, attributes: attrs))
                i = end
                continue
            }
            if let (text, end) = parseDelimited(markdown, from: i, delimiter: "__") {
                let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                var attrs = baseAttributes
                attrs[.font] = boldFont
                attrs[Self.markdownSourceKey] = "__\(text)__"
                result.append(NSAttributedString(string: text, attributes: attrs))
                i = end
                continue
            }

            // Strikethrough: ~~text~~
            if let (text, end) = parseDelimited(markdown, from: i, delimiter: "~~") {
                var attrs = baseAttributes
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[Self.markdownSourceKey] = "~~\(text)~~"
                result.append(NSAttributedString(string: text, attributes: attrs))
                i = end
                continue
            }

            // Italic: *text* or _text_
            if let (text, end) = parseDelimited(markdown, from: i, delimiter: "*") {
                let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                var attrs = baseAttributes
                attrs[.font] = italicFont
                attrs[Self.markdownSourceKey] = "*\(text)*"
                result.append(NSAttributedString(string: text, attributes: attrs))
                i = end
                continue
            }
            if let (text, end) = parseDelimited(markdown, from: i, delimiter: "_") {
                let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                var attrs = baseAttributes
                attrs[.font] = italicFont
                attrs[Self.markdownSourceKey] = "_\(text)_"
                result.append(NSAttributedString(string: text, attributes: attrs))
                i = end
                continue
            }

            // Inline code: `text`
            if let (text, end) = parseDelimited(markdown, from: i, delimiter: "`") {
                let codeFont = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
                var attrs = baseAttributes
                attrs[.font] = codeFont
                attrs[.backgroundColor] = NSColor.quaternaryLabelColor
                attrs[Self.markdownSourceKey] = "`\(text)`"
                result.append(NSAttributedString(string: text, attributes: attrs))
                i = end
                continue
            }

            // Link: [text](url)
            if let (text, url, end) = parseLink(markdown, from: i) {
                var attrs = baseAttributes
                attrs[.link] = url
                attrs[.foregroundColor] = NSColor(red: 0.831, green: 0.263, blue: 0.196, alpha: 1.0)
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[Self.markdownSourceKey] = "[\(text)](\(url))"
                result.append(NSAttributedString(string: text, attributes: attrs))
                i = end
                continue
            }

            // Mention: @[[Page Name]] → styled inline link with page icon
            if let (name, end) = parseMention(markdown, from: i) {
                var attrs = baseAttributes
                attrs[.foregroundColor] = NSColor.controlAccentColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[Self.markdownSourceKey] = "@[[\(name)]]"
                attrs[Self.mentionPageNameKey] = name
                result.append(NSAttributedString(string: name, attributes: attrs))
                i = end
                continue
            }

            // Double-equals separator: " == " → arrow indicator
            if let end = parseDoubleEqualsSeparator(markdown, from: i) {
                var attrs = baseAttributes
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
                attrs[Self.markdownSourceKey] = " == "
                let arrowFont = NSFont.systemFont(ofSize: font.pointSize * 0.85, weight: .medium)
                attrs[.font] = arrowFont
                result.append(NSAttributedString(string: "  ⇌  ", attributes: attrs))
                i = end
                continue
            }

            // Plain character
            result.append(NSAttributedString(string: String(markdown[i]), attributes: baseAttributes))
            i = markdown.index(after: i)
        }

        return result
    }

    // MARK: - Plain Text (strip markdown markers)

    /// Returns the visible text with all inline markdown formatting removed.
    static func plainText(from markdown: String) -> String {
        guard !markdown.isEmpty else { return "" }
        return attributedString(from: markdown).string
    }

    static func markdownOffset(forDisplayOffset displayOffset: Int, in markdown: String) -> Int {
        let attributed = attributedString(from: markdown)
        let clamped = max(0, min(displayOffset, attributed.length))
        let prefix = attributed.attributedSubstring(from: NSRange(location: 0, length: clamped))
        return (self.markdown(from: prefix) as NSString).length
    }

    // MARK: - NSAttributedString -> Markdown

    /// Converts an attributed string back to markdown with inline formatting.
    static func markdown(from attributedString: NSAttributedString) -> String {
        var result = ""

        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { attrs, range, _ in
            let text = (attributedString.string as NSString).substring(with: range)

            // Check for stored markdown source first (highest fidelity)
            if let source = attrs[Self.markdownSourceKey] as? String {
                result += source
                return
            }

            // Reconstruct from attributes
            var prefix = ""
            var suffix = ""

            // Link
            if let url = attrs[.link] as? String {
                result += "[\(text)](\(url))"
                return
            }

            // Code (check font family)
            if let font = attrs[.font] as? NSFont, font.isFixedPitch {
                result += "`\(text)`"
                return
            }

            // Bold and/or italic (check font traits)
            if let font = attrs[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.boldFontMask) {
                    prefix += "**"
                    suffix = "**" + suffix
                }
                if traits.contains(.italicFontMask) {
                    prefix += "*"
                    suffix = "*" + suffix
                }
            }

            // Strikethrough
            if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                prefix += "~~"
                suffix = "~~" + suffix
            }

            result += prefix + text + suffix
        }

        return result
    }

    // MARK: - Parsing Helpers

    /// Parse delimited inline formatting like **bold** or *italic*
    private static func parseDelimited(
        _ str: String,
        from start: String.Index,
        delimiter: String
    ) -> (String, String.Index)? {
        guard str[start...].hasPrefix(delimiter) else { return nil }

        let delimCount = delimiter.count
        let afterOpen = str.index(start, offsetBy: delimCount)
        guard afterOpen < str.endIndex else { return nil }

        // Don't match if delimiter is followed by whitespace
        if str[afterOpen].isWhitespace { return nil }

        // Find closing delimiter
        var searchFrom = afterOpen
        while searchFrom < str.endIndex {
            guard let closeRange = str.range(of: delimiter, range: searchFrom..<str.endIndex) else {
                return nil
            }
            // Don't match if preceded by whitespace
            let beforeClose = str.index(before: closeRange.lowerBound)
            if beforeClose >= afterOpen && !str[beforeClose].isWhitespace {
                let content = String(str[afterOpen..<closeRange.lowerBound])
                guard !content.isEmpty else { return nil }
                return (content, closeRange.upperBound)
            }
            searchFrom = str.index(after: closeRange.lowerBound)
        }

        return nil
    }

    /// Parse mention: @[[Page Name]] → (name, endIndex)
    private static func parseMention(
        _ str: String,
        from start: String.Index
    ) -> (String, String.Index)? {
        let prefix = "@[["
        guard str[start...].hasPrefix(prefix) else { return nil }
        let nameStart = str.index(start, offsetBy: prefix.count)
        guard let closingRange = str[nameStart...].range(of: "]]") else { return nil }
        let name = String(str[nameStart..<closingRange.lowerBound])
        guard !name.isEmpty else { return nil }
        return (name, closingRange.upperBound)
    }

    /// Parse double-equals separator: " == " (with spaces on both sides)
    private static func parseDoubleEqualsSeparator(
        _ str: String,
        from start: String.Index
    ) -> String.Index? {
        let separator = " == "
        guard str[start...].hasPrefix(separator) else { return nil }
        // Ensure there's content before and after the separator
        guard start > str.startIndex else { return nil }
        let end = str.index(start, offsetBy: separator.count)
        guard end < str.endIndex else { return nil }
        return end
    }

    /// Parse markdown link: [text](url)
    private static func parseLink(
        _ str: String,
        from start: String.Index
    ) -> (String, String, String.Index)? {
        guard str[start] == "[" else { return nil }

        let afterBracket = str.index(after: start)
        guard afterBracket < str.endIndex else { return nil }

        // Find closing ]
        guard let closeBracket = str[afterBracket...].firstIndex(of: "]") else { return nil }
        let text = String(str[afterBracket..<closeBracket])

        // Must be followed by (
        let afterClose = str.index(after: closeBracket)
        guard afterClose < str.endIndex, str[afterClose] == "(" else { return nil }

        let urlStart = str.index(after: afterClose)
        guard urlStart < str.endIndex else { return nil }

        // Find closing )
        guard let closeParen = str[urlStart...].firstIndex(of: ")") else { return nil }
        let url = String(str[urlStart..<closeParen])

        return (text, url, str.index(after: closeParen))
    }

    // MARK: - Formatting Application

    /// Apply or toggle a formatting style on the given range of an attributed string.
    static func toggleBold(in textView: NSTextView, font baseFont: NSFont) {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        guard let textStorage = textView.textStorage else { return }

        let currentFont = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
        let traits = NSFontManager.shared.traits(of: currentFont)
        let newFont: NSFont
        if traits.contains(.boldFontMask) {
            newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .boldFontMask)
        } else {
            newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
        }

        textStorage.addAttribute(.font, value: newFont, range: range)
        // Remove stored markdown source since user is editing
        textStorage.removeAttribute(Self.markdownSourceKey, range: range)
    }

    static func toggleItalic(in textView: NSTextView, font baseFont: NSFont) {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        guard let textStorage = textView.textStorage else { return }

        let currentFont = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
        let traits = NSFontManager.shared.traits(of: currentFont)
        let newFont: NSFont
        if traits.contains(.italicFontMask) {
            newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .italicFontMask)
        } else {
            newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
        }

        textStorage.addAttribute(.font, value: newFont, range: range)
        textStorage.removeAttribute(Self.markdownSourceKey, range: range)
    }

    static func toggleCode(in textView: NSTextView, font baseFont: NSFont) {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        guard let textStorage = textView.textStorage else { return }

        let currentFont = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
        let newFont: NSFont
        if currentFont.isFixedPitch {
            newFont = baseFont
            textStorage.removeAttribute(.backgroundColor, range: range)
        } else {
            newFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
            textStorage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range)
        }

        textStorage.addAttribute(.font, value: newFont, range: range)
        textStorage.removeAttribute(Self.markdownSourceKey, range: range)
    }

    static func toggleStrikethrough(in textView: NSTextView) {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        guard let textStorage = textView.textStorage else { return }

        let current = textStorage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        if current != 0 {
            textStorage.removeAttribute(.strikethroughStyle, range: range)
        } else {
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        textStorage.removeAttribute(Self.markdownSourceKey, range: range)
    }

    static func applyLink(in textView: NSTextView, url: String) {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        guard let textStorage = textView.textStorage else { return }

        textStorage.addAttribute(.link, value: url, range: range)
        textStorage.addAttribute(.foregroundColor, value: NSColor(red: 0.831, green: 0.263, blue: 0.196, alpha: 1.0), range: range)
        textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        textStorage.removeAttribute(Self.markdownSourceKey, range: range)
    }
}
