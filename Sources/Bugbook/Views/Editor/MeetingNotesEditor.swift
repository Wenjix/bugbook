import SwiftUI
import AppKit

/// Lightweight markdown-aware text editor for meeting notes.
/// Renders `- ` as bullets, `# ` as headers, `**text**` as bold.
/// Auto-continues bullets on Enter.
struct MeetingNotesEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: Typography.body)
    var textColor: NSColor = .labelColor
    var placeholder: String = "Write notes..."

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView // SAFETY: scrollableTextView always creates an NSTextView

        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 4, height: 2)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView
        context.coordinator.applyMarkdownStyling()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coord = context.coordinator

        // Only update if text changed externally
        if textView.string != text && !coord.isEditing {
            coord.isUpdating = true
            textView.string = text
            coord.applyMarkdownStyling()
            coord.isUpdating = false
        }

        // Show/hide placeholder
        coord.updatePlaceholder()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MeetingNotesEditor
        weak var textView: NSTextView?
        var isEditing = false
        var isUpdating = false
        private var placeholderView: NSTextField?

        init(_ parent: MeetingNotesEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            isEditing = true
            parent.text = textView.string
            applyMarkdownStyling()
            updatePlaceholder()
            isEditing = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleEnter(textView)
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return handleTab(textView, indent: true)
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                return handleTab(textView, indent: false)
            }
            return false
        }

        // MARK: - Enter: auto-continue bullets

        private func handleEnter(_ textView: NSTextView) -> Bool {
            let string = textView.string as NSString
            let cursorLocation = textView.selectedRange().location
            let lineRange = string.lineRange(for: NSRange(location: cursorLocation, length: 0))
            let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)

            // Detect bullet prefix
            let bulletPrefixes = ["- [ ] ", "- [x] ", "- ", "* ", "+ "]
            for prefix in bulletPrefixes {
                if line.hasPrefix(prefix) {
                    let content = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if content.isEmpty {
                        // Empty bullet — remove it and stop the list
                        let replaceRange = NSRange(location: lineRange.location, length: lineRange.length)
                        textView.insertText("\n", replacementRange: replaceRange)
                        return true
                    }
                    // Detect indentation
                    let indent = leadingWhitespace(line)
                    textView.insertText("\n\(indent)\(prefix)", replacementRange: textView.selectedRange())
                    return true
                }
                // Check with leading whitespace
                let trimmedLine = line.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
                if trimmedLine.hasPrefix(prefix) {
                    let content = String(trimmedLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if content.isEmpty {
                        let replaceRange = NSRange(location: lineRange.location, length: lineRange.length)
                        textView.insertText("\n", replacementRange: replaceRange)
                        return true
                    }
                    let indent = leadingWhitespace(line)
                    textView.insertText("\n\(indent)\(prefix)", replacementRange: textView.selectedRange())
                    return true
                }
            }

            // Detect numbered list (e.g., "1. ")
            let numberedPattern = try? NSRegularExpression(pattern: "^(\\s*)(\\d+)\\. ")
            if let match = numberedPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let indent = leadingWhitespace(line)
                let numRange = Range(match.range(at: 2), in: line)!
                let num = Int(line[numRange]) ?? 1
                let content = String(line.dropFirst(match.range.length)).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    let replaceRange = NSRange(location: lineRange.location, length: lineRange.length)
                    textView.insertText("\n", replacementRange: replaceRange)
                    return true
                }
                textView.insertText("\n\(indent)\(num + 1). ", replacementRange: textView.selectedRange())
                return true
            }

            return false
        }

        // MARK: - Tab: indent/outdent

        private func handleTab(_ textView: NSTextView, indent: Bool) -> Bool {
            let string = textView.string as NSString
            let cursorLocation = textView.selectedRange().location
            let lineRange = string.lineRange(for: NSRange(location: cursorLocation, length: 0))
            let line = string.substring(with: lineRange)

            // Only indent/outdent list items
            let isList = line.trimmingCharacters(in: .whitespaces).hasPrefix("-") ||
                         line.trimmingCharacters(in: .whitespaces).hasPrefix("*") ||
                         line.trimmingCharacters(in: .whitespaces).hasPrefix("+") ||
                         line.trimmingCharacters(in: .whitespaces).range(of: "^\\d+\\. ", options: .regularExpression) != nil

            guard isList else { return false }

            if indent {
                textView.insertText("  " + line, replacementRange: lineRange)
            } else {
                if line.hasPrefix("  ") {
                    textView.insertText(String(line.dropFirst(2)), replacementRange: lineRange)
                }
            }
            return true
        }

        // MARK: - Markdown Styling

        func applyMarkdownStyling() {
            guard let textView, let textStorage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            let string = textStorage.string as NSString

            // Preserve cursor
            let selectedRange = textView.selectedRange()

            textStorage.beginEditing()

            // Reset to base style
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2
            textStorage.setAttributes([
                .font: parent.font,
                .foregroundColor: parent.textColor,
                .paragraphStyle: paragraphStyle
            ], range: fullRange)

            // Process line by line
            string.enumerateSubstrings(in: fullRange, options: .byLines) { line, lineRange, _, _ in
                guard let line else { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Headers: # ## ###
                if trimmed.hasPrefix("### ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: self.parent.font.pointSize + 1, weight: .semibold), range: lineRange)
                } else if trimmed.hasPrefix("## ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: self.parent.font.pointSize + 2, weight: .semibold), range: lineRange)
                } else if trimmed.hasPrefix("# ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: self.parent.font.pointSize + 4, weight: .bold), range: lineRange)
                }

                // Bullets: replace "- " visual with bullet character styling
                if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
                    // Task items — dim the checkbox prefix
                    let prefixLen = trimmed.hasPrefix("- [ ] ") ? 6 : 6
                    let offset = line.count - trimmed.count
                    let prefixRange = NSRange(location: lineRange.location + offset, length: prefixLen)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: prefixRange)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                    // Dim the dash/asterisk
                    let offset = line.count - trimmed.count
                    let dashRange = NSRange(location: lineRange.location + offset, length: 1)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: dashRange)
                }
            }

            // Bold: **text**
            let boldPattern = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
            boldPattern?.enumerateMatches(in: string as String, range: fullRange) { match, _, _ in
                guard let match else { return }
                // Bold the content
                let contentRange = match.range(at: 1)
                let boldFont = NSFontManager.shared.convert(self.parent.font, toHaveTrait: .boldFontMask)
                textStorage.addAttribute(.font, value: boldFont, range: contentRange)
                // Dim the ** markers
                let openRange = NSRange(location: match.range.location, length: 2)
                let closeRange = NSRange(location: match.range.location + match.range.length - 2, length: 2)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeRange)
            }

            // Italic: *text* (not inside **)
            let italicPattern = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)")
            italicPattern?.enumerateMatches(in: string as String, range: fullRange) { match, _, _ in
                guard let match else { return }
                let contentRange = match.range(at: 1)
                let italicFont = NSFontManager.shared.convert(self.parent.font, toHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: italicFont, range: contentRange)
                let openRange = NSRange(location: match.range.location, length: 1)
                let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeRange)
            }

            textStorage.endEditing()

            // Restore cursor
            if selectedRange.location <= textStorage.length {
                textView.setSelectedRange(selectedRange)
            }
        }

        // MARK: - Placeholder

        func updatePlaceholder() {
            guard let textView else { return }

            if textView.string.isEmpty {
                if placeholderView == nil {
                    let label = NSTextField(labelWithString: parent.placeholder)
                    label.font = parent.font
                    label.textColor = .placeholderTextColor
                    label.translatesAutoresizingMaskIntoConstraints = false
                    textView.addSubview(label)
                    NSLayoutConstraint.activate([
                        label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
                        label.topAnchor.constraint(equalTo: textView.topAnchor, constant: 2)
                    ])
                    placeholderView = label
                }
                placeholderView?.isHidden = false
            } else {
                placeholderView?.isHidden = true
            }
        }

        // MARK: - Helpers

        private func leadingWhitespace(_ line: String) -> String {
            String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        }
    }
}
