import SwiftUI
import AppKit

/// Floating formatting toolbar that appears on text selection.
/// Provides buttons for Bold, Italic, Code, Strikethrough, and Link.
struct FormattingToolbar: View {
    let onBold: () -> Void
    let onItalic: () -> Void
    let onCode: () -> Void
    let onStrikethrough: () -> Void
    let onLink: () -> Void
    var onAskAI: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton("B", font: .system(size: 14, weight: .bold), action: onBold)
            toolbarButton("I", font: .system(size: 14).italic(), action: onItalic)
            toolbarButton("</>" , font: .system(size: 12, design: .monospaced), action: onCode)
            toolbarButton("S", font: .system(size: 14), strikethrough: true, action: onStrikethrough)
            Divider().frame(height: 20)
            toolbarButton("link", systemImage: "link", action: onLink)
            if let onAskAI {
                Divider().frame(height: 20)
                toolbarButton("ai", systemImage: "ladybug", action: onAskAI)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .popoverSurface(cornerRadius: Radius.sm)
    }

    @ViewBuilder
    private func toolbarButton(
        _ label: String,
        font: Font = .system(size: 14),
        strikethrough: Bool = false,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14))
                } else {
                    Text(label)
                        .font(font)
                        .strikethrough(strikethrough)
                }
            }
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
