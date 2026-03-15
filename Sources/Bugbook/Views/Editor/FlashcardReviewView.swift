import SwiftUI

struct FlashcardItem: Identifiable {
    let id = UUID()
    let front: String
    let back: String
    let pageName: String
}

struct FlashcardReviewView: View {
    let cards: [FlashcardItem]
    let onDismiss: () -> Void

    @State private var currentIndex: Int = 0
    @State private var revealed: Bool = false
    @State private var correctCount: Int = 0
    @State private var reviewedCount: Int = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        if cards.isEmpty {
            emptyState
        } else if reviewedCount >= cards.count {
            summaryState
        } else {
            cardView
        }
    }

    private var card: FlashcardItem {
        cards[currentIndex]
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No flashcards found")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Write cards inline with the == separator")
                .font(.body)
                .foregroundStyle(.tertiary)
            Text("What is hello in Russian? == Привет")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            Button("Close") { onDismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var summaryState: some View {
        VStack(spacing: 20) {
            Text("Review Complete")
                .font(.title)
                .fontWeight(.semibold)
            Text("\(correctCount) / \(cards.count) correct")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Done") { onDismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var cardView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(card.pageName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(currentIndex + 1) / \(cards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)

            Spacer()

            // Card
            VStack(spacing: 24) {
                Text(card.front)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if revealed {
                    Divider()
                        .frame(maxWidth: 200)
                        .padding(.vertical, 4)

                    Text(card.back)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(40)
            .frame(maxWidth: 500)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }

            Spacer()

            // Controls
            if !revealed {
                Text("Press Space to reveal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 32)
            } else {
                HStack(spacing: 32) {
                    Button {
                        advance(correct: false)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.title3)
                            Text("Missed")
                                .font(.caption)
                        }
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 80, height: 50)
                    }
                    .buttonStyle(.plain)

                    Button {
                        advance(correct: true)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.title3)
                            Text("Got it")
                                .font(.caption)
                        }
                        .foregroundStyle(.green.opacity(0.8))
                        .frame(width: 80, height: 50)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.space) {
            if !revealed {
                withAnimation(.easeOut(duration: 0.15)) { revealed = true }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if revealed { advance(correct: true); return .handled }
            return .ignored
        }
        .onKeyPress(.leftArrow) {
            if revealed { advance(correct: false); return .handled }
            return .ignored
        }
        .onKeyPress(.return) {
            if revealed { advance(correct: true); return .handled }
            return .ignored
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func advance(correct: Bool) {
        if correct { correctCount += 1 }
        reviewedCount += 1
        if currentIndex + 1 < cards.count {
            withAnimation(.easeInOut(duration: 0.15)) {
                revealed = false
                currentIndex += 1
            }
        }
    }
}

// MARK: - Flashcard Scanner

@MainActor
enum FlashcardScanner {

    /// Extract flashcard items from a BlockDocument.
    static func scan(document: BlockDocument, pageName: String) -> [FlashcardItem] {
        var items: [FlashcardItem] = []
        for block in document.blocks {
            items.append(contentsOf: scanBlock(block, pageName: pageName))
        }
        return items
    }

    private static func scanBlock(_ block: Block, pageName: String) -> [FlashcardItem] {
        var items: [FlashcardItem] = []
        // Skip code blocks
        if block.type == .codeBlock { return items }
        if let item = parseFlashcardLine(block.text, pageName: pageName) {
            items.append(item)
        }
        for child in block.children {
            items.append(contentsOf: scanBlock(child, pageName: pageName))
        }
        return items
    }

    private static func parseFlashcardLine(_ text: String, pageName: String) -> FlashcardItem? {
        // Match " == " with spaces to avoid code equality operators
        guard let range = text.range(of: " == ") else { return nil }
        let front = String(text[text.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let back = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        // Strip leading markdown markers (-, *, 1., - [ ], - [x], >)
        let cleanFront = stripMarkdownPrefix(front)
        guard !cleanFront.isEmpty, !back.isEmpty else { return nil }
        return FlashcardItem(front: cleanFront, back: back, pageName: pageName)
    }

    private static func stripMarkdownPrefix(_ text: String) -> String {
        var s = text
        // Checkbox: - [ ] or - [x]
        if let match = s.range(of: #"^- \[[ xX]\] "#, options: .regularExpression) {
            s = String(s[match.upperBound...])
        }
        // Bullet: - or *
        else if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
        else if s.hasPrefix("* ") { s = String(s.dropFirst(2)) }
        // Numbered: 1. 2. etc
        else if let match = s.range(of: #"^\d+\. "#, options: .regularExpression) {
            s = String(s[match.upperBound...])
        }
        // Blockquote
        else if s.hasPrefix("> ") { s = String(s.dropFirst(2)) }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
