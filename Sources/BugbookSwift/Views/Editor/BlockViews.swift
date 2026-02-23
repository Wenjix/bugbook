import SwiftUI

/// Horizontal rule block.
struct HorizontalRuleView: View {
    var body: some View {
        Divider()
            .padding(.vertical, 12)
    }
}

/// Image block — renders local or remote images.
struct ImageBlockView: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if block.imageSource.hasPrefix("/") || block.imageSource.hasPrefix("file://") {
                let fileURL = block.imageSource.hasPrefix("file://")
                    ? URL(string: block.imageSource)!
                    : URL(fileURLWithPath: block.imageSource)
                if let nsImage = NSImage(contentsOf: fileURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: block.imageWidth.map { CGFloat($0) } ?? .infinity)
                        .cornerRadius(4)
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
                .cornerRadius(4)
            } else {
                imagePlaceholder
            }

            if !block.imageAlt.isEmpty {
                Text(block.imageAlt)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.1))
            .frame(height: 100)
            .overlay(
                Text("Image: \(block.imageSource)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            )
    }
}

/// Database embed block — wraps existing DatabaseInlineEmbedView.
struct DatabaseEmbedBlockView: View {
    let block: Block

    var body: some View {
        DatabaseInlineEmbedView(dbPath: block.databasePath)
            .padding(.vertical, 4)
    }
}
