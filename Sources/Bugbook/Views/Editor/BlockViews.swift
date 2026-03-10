import SwiftUI

/// Horizontal rule block.
struct HorizontalRuleView: View {
    var body: some View {
        Rectangle()
            .fill(Color.fallbackDividerColor)
            .frame(height: 1)
            .padding(.vertical, 6)
    }
}

/// Image block — renders local or remote images.
struct ImageBlockView: View {
    let block: Block
    @State private var cachedImage: NSImage?

    private var isLocalImage: Bool {
        block.imageSource.hasPrefix("/") || block.imageSource.hasPrefix("file://")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLocalImage {
                if let nsImage = cachedImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: block.imageWidth.map { CGFloat($0) } ?? .infinity)
                        .clipShape(.rect(cornerRadius: 4))
                } else {
                    imagePlaceholder
                }
            } else if let url = URL(string: block.imageSource) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: block.imageWidth.map { CGFloat($0) } ?? .infinity)
                } placeholder: {
                    imagePlaceholder
                }
                .clipShape(.rect(cornerRadius: 4))
            } else {
                imagePlaceholder
            }

            if !block.imageAlt.isEmpty {
                Text(block.imageAlt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: block.imageSource) {
            guard isLocalImage else { return }
            let source = block.imageSource
            let fileURL = source.hasPrefix("file://")
                ? URL(string: source)!
                : URL(fileURLWithPath: source)
            cachedImage = NSImage(contentsOf: fileURL)
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.fallbackSurfaceSubtle)
            .frame(height: 100)
            .overlay(
                Text("Image: \(block.imageSource)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }
}

/// Database embed block — wraps existing DatabaseInlineEmbedView.
struct DatabaseEmbedBlockView: View {
    let block: Block
    var onOpenDatabaseTab: ((String) -> Void)?

    var body: some View {
        DatabaseInlineEmbedView(
            dbPath: block.databasePath,
            onOpenDatabase: { onOpenDatabaseTab?(block.databasePath) }
        )
        .padding(.vertical, 4)
    }
}
