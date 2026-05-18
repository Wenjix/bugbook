import AppKit
import SwiftUI

actor LocalImageDataLoader {
    static let shared = LocalImageDataLoader()

    func data(at path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }
}

struct AsyncLocalImageView<Placeholder: View>: View {
    let path: String
    let width: CGFloat
    let height: CGFloat
    var contentMode: ContentMode = .fit
    var cornerRadius: CGFloat = 0
    private let placeholder: Placeholder

    @State private var image: NSImage?

    init(
        path: String,
        width: CGFloat,
        height: CGFloat,
        contentMode: ContentMode = .fit,
        cornerRadius: CGFloat = 0,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.path = path
        self.width = width
        self.height = height
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .clipShape(.rect(cornerRadius: cornerRadius))
            } else {
                placeholder
                    .frame(width: width, height: height)
            }
        }
        .task(id: path) {
            let data = await LocalImageDataLoader.shared.data(at: path)
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:))
        }
    }
}
