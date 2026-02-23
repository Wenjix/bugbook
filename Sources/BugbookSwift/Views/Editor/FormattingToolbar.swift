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

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton("B", font: .system(size: 13, weight: .bold), action: onBold)
            toolbarButton("I", font: .system(size: 13).italic(), action: onItalic)
            toolbarButton("</>" , font: .system(size: 11, design: .monospaced), action: onCode)
            toolbarButton("S", font: .system(size: 13), strikethrough: true, action: onStrikethrough)
            Divider().frame(height: 20)
            toolbarButton("link", systemImage: "link", action: onLink)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    @ViewBuilder
    private func toolbarButton(
        _ label: String,
        font: Font = .system(size: 13),
        strikethrough: Bool = false,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
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
        .foregroundColor(.primary)
    }
}
