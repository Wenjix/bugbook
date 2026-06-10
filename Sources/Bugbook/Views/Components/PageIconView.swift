import SwiftUI

/// Renders a raw page-icon string (see `PageIcon.parse`) as an SF Symbol,
/// emoji, or custom image file. Custom images load off the main thread via
/// `AsyncLocalImageView`, so no caller does disk I/O in `body`; the caller's
/// placeholder shows while loading and when the icon is missing or unreadable.
struct PageIconView<Placeholder: View>: View {
    let icon: String?
    var imageSize: CGFloat = 14
    var symbolFont: Font = .system(size: 11)
    var emojiFont: Font = .system(size: 13)
    var cornerRadius: CGFloat = 3
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let parsed = PageIcon.parse(icon) {
            switch parsed.type {
            case .custom:
                AsyncLocalImageView(
                    path: parsed.value,
                    width: imageSize,
                    height: imageSize,
                    cornerRadius: cornerRadius
                ) {
                    placeholder()
                }
            case .symbol:
                Image(systemName: parsed.value)
                    .font(symbolFont)
            case .emoji:
                Text(parsed.value)
                    .font(emojiFont)
            }
        } else {
            placeholder()
        }
    }
}
