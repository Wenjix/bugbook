import SwiftUI
import AppKit

struct PageHeaderView: View {
    @Binding var icon: String?
    @Binding var coverUrl: String?
    var fullWidth: Bool

    @State private var showIconPicker = false
    @State private var showCoverPicker = false
    @State private var coverYPosition: Double = 50
    @State private var isDraggingCover = false
    @State private var dragStartY: CGFloat = 0
    @State private var isHovering = false

    private var horizontalPadding: CGFloat { fullWidth ? 40 : 80 }
    private var needsIcon: Bool { icon == nil || icon?.isEmpty == true }
    private var needsCover: Bool { coverUrl == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image
            if let coverPath = coverUrl {
                coverImageView(path: coverPath)
            }

            // Action buttons — show on hover when missing icon/cover
            if needsIcon || needsCover {
                HStack(spacing: 8) {
                    if needsIcon {
                        Button { showIconPicker = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "face.smiling").font(.system(size: 12))
                                Text("Add icon").font(.system(size: 12))
                            }
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    if needsCover {
                        Button { showCoverPicker = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo").font(.system(size: 12))
                                Text("Add cover").font(.system(size: 12))
                            }
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, coverUrl != nil ? 8 : 12)
                .opacity(isHovering || showIconPicker || showCoverPicker ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            }

            // Icon (clickable to change)
            if let iconValue = icon, !iconValue.isEmpty {
                Button(action: { showIconPicker.toggle() }) {
                    iconDisplay(iconValue)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        // Popovers anchored to stable outer view
        .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
            FullEmojiPickerView(
                selectedEmoji: $icon,
                onCustomIconSelected: { path in
                    icon = "custom:\(path)"
                }
            )
        }
        .popover(isPresented: $showCoverPicker, arrowEdge: .bottom) {
            CoverPickerView(coverUrl: $coverUrl, coverYPosition: $coverYPosition)
        }
    }

    // MARK: - Icon Display

    @ViewBuilder
    private func iconDisplay(_ value: String) -> some View {
        if value.hasPrefix("sf:") {
            let symbolName = String(value.dropFirst(3))
            Image(systemName: symbolName)
                .font(.system(size: 32))
                .frame(width: 48, height: 48)
        } else if value.hasPrefix("custom:") {
            let path = String(value.dropFirst(7))
            if let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(value).font(.system(size: 40))
            }
        } else {
            Text(value).font(.system(size: 40))
        }
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImageView(path: String) -> some View {
        let coverHeight: CGFloat = 200
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: coverHeight)
                        .frame(maxWidth: .infinity)
                        .offset(y: coverOffset(imageSize: nsImage.size, containerHeight: coverHeight))
                        .clipped()
                } else {
                    // Local paths need fileURLWithPath (handles spaces); remote URLs use URL(string:)
                    let url: URL? = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(string: path)
                    if let url = url {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.2))
                        }
                        .frame(height: coverHeight)
                        .clipped()
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDraggingCover {
                            isDraggingCover = true
                            dragStartY = value.startLocation.y
                        }
                        let delta = value.location.y - dragStartY
                        let sensitivity = 0.5
                        let newPosition = coverYPosition - delta * sensitivity
                        coverYPosition = min(100, max(0, newPosition))
                        dragStartY = value.location.y
                    }
                    .onEnded { _ in
                        isDraggingCover = false
                    }
            )

            HStack(spacing: 4) {
                Button(action: { showCoverPicker = true }) {
                    Label("Change", systemImage: "photo")
                        .font(.system(size: 11))
                }
                .buttonStyle(CoverActionButtonStyle())

                Button(action: { coverUrl = nil; coverYPosition = 50 }) {
                    Label("Remove", systemImage: "xmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(CoverActionButtonStyle())
            }
            .padding(8)
        }
    }

    private func coverOffset(imageSize: NSSize, containerHeight: CGFloat) -> CGFloat {
        guard imageSize.height > 0 else { return 0 }
        let scale = max(1.0, imageSize.height / containerHeight)
        let maxOffset = (imageSize.height - containerHeight) / scale
        let normalizedPosition = coverYPosition / 100.0
        return -maxOffset * normalizedPosition
    }
}

private struct CoverActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(configuration.isPressed ? 0.6 : 0.4))
            .cornerRadius(4)
    }
}
