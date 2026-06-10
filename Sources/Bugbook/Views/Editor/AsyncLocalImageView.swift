import AppKit
import ImageIO
import SwiftUI

actor LocalImageDataLoader {
    static let shared = LocalImageDataLoader()

    /// Stateless disk read. Nonisolated async so concurrent callers run on the
    /// global executor instead of serializing through this actor.
    nonisolated func data(at path: String) async -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }
}

/// Process-wide cache of downsampled local images, keyed by path + pixel size.
/// Hot lists (palette rows, pickers, sidebar) hit the cache synchronously and
/// render the icon on the first frame; misses decode a bounded thumbnail off
/// the main thread and populate the cache.
enum LocalImageThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    private static func key(_ path: String, _ maxPixelSize: Int) -> NSString {
        "\(maxPixelSize)|\(path)" as NSString
    }

    /// Synchronous cache lookup — safe to call from a view body or init.
    static func cachedImage(at path: String, maxPixelSize: Int) -> NSImage? {
        cache.object(forKey: key(path, maxPixelSize))
    }

    /// Downsampled decode (CGImageSource thumbnail) with cache fill. Runs on
    /// the global executor.
    static func loadImage(at path: String, maxPixelSize: Int) async -> NSImage? {
        if let cached = cachedImage(at: path, maxPixelSize: maxPixelSize) {
            return cached
        }
        guard let image = downsampledImage(at: path, maxPixelSize: maxPixelSize) else {
            return nil
        }
        cache.setObject(image, forKey: key(path, maxPixelSize))
        return image
    }

    private static func downsampledImage(at path: String, maxPixelSize: Int) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
        // Warm cache hit renders on the first frame — no placeholder flash.
        _image = State(initialValue: LocalImageThumbnailCache.cachedImage(
            at: path,
            maxPixelSize: Self.thumbnailPixelSize(width: width, height: height)
        ))
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
            let pixelSize = Self.thumbnailPixelSize(width: width, height: height)
            if let cached = LocalImageThumbnailCache.cachedImage(at: path, maxPixelSize: pixelSize) {
                image = cached
                return
            }
            let loaded = await LocalImageThumbnailCache.loadImage(at: path, maxPixelSize: pixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }

    /// 2x the view's point size for Retina rendering, with a sane minimum.
    private static func thumbnailPixelSize(width: CGFloat, height: CGFloat) -> Int {
        max(Int(ceil(max(width, height) * 2)), 16)
    }
}
