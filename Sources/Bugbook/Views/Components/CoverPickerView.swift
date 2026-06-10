import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CoverPickerView: View {
    @Binding var coverUrl: String?
    @Binding var coverYPosition: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.popoverDismiss) private var popoverDismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Cover Image")
                .font(.headline)
                .padding(.top, 8)

            if let coverPath = coverUrl {
                // Preview current cover — loaded off the main thread.
                if let filePath = normalizedCoverPath(coverPath) {
                    AsyncLocalImageView(
                        path: filePath,
                        width: 296,
                        height: 120,
                        contentMode: .fill,
                        cornerRadius: 6
                    ) {
                        Color.primary.opacity(0.05)
                    }
                    .padding(.horizontal, 12)
                }

                // Reposition slider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vertical Position")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Slider(value: $coverYPosition, in: 0...100)
                }
                .padding(.horizontal, 12)

                HStack {
                    Button("Change Image") {
                        chooseCoverImage()
                    }
                    Spacer()
                    Button("Remove Cover") {
                        coverUrl = nil
                        coverYPosition = 50
                        (popoverDismiss ?? { dismiss() })()
                    }
                    .foregroundStyle(.primary)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text("Add a cover image")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text("PNG, JPG, GIF, or WebP.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.7))

                Button("Choose Image") {
                    chooseCoverImage()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Spacer()
        }
        .frame(width: 320, height: 300)
        .padding(8)
        .popoverSurface()
    }

    private func normalizedCoverPath(_ path: String) -> String? {
        if path.hasPrefix("file://") { return String(path.dropFirst(7)) }
        return path.hasPrefix("/") ? path : nil
    }

    private func chooseCoverImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Cover Image"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let savedPath = FileSystemService.saveCover(from: url) {
            coverUrl = savedPath
            coverYPosition = 50
            (popoverDismiss ?? { dismiss() })()
        }
    }
}
