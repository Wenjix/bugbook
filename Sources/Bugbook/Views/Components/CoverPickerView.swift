import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CoverPickerView: View {
    @Binding var coverUrl: String?
    @Binding var coverYPosition: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Cover Image")
                .font(.headline)
                .padding(.top, 8)

            if let coverPath = coverUrl {
                // Preview current cover
                if let nsImage = loadCoverImage(from: coverPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                        .clipShape(.rect(cornerRadius: 6))
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
                        dismiss()
                    }
                    .foregroundStyle(.red)
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
    }

    private func loadCoverImage(from path: String) -> NSImage? {
        if path.hasPrefix("file://") || path.hasPrefix("/") {
            let filePath = path.hasPrefix("file://") ? String(path.dropFirst(7)) : path
            return NSImage(contentsOfFile: filePath)
        }
        return nil
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
            dismiss()
        }
    }
}
