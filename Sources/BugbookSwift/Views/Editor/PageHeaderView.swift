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
    private var hasIcon: Bool { !(icon ?? "").isEmpty }
    private var needsIcon: Bool { icon == nil || icon?.isEmpty == true }
    private var needsCover: Bool { coverUrl == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let coverPath = coverUrl {
                ZStack(alignment: .bottomLeading) {
                    coverImageView(path: coverPath)

                    if let iconValue = icon, !iconValue.isEmpty {
                        iconPickerButton(iconValue)
                            .padding(.leading, horizontalPadding)
                            .offset(y: 22)
                    }
                }
                .padding(.bottom, hasIcon ? 26 : 0)
            }

            // Action buttons — show on hover when missing icon/cover
            if needsIcon || needsCover {
                HStack(spacing: 8) {
                    if needsIcon {
                        addIconButton
                    }

                    if needsCover {
                        addCoverButton
                    }

                    Spacer()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, coverUrl != nil ? 10 : 12)
                .opacity(isHovering || showIconPicker || showCoverPicker ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            }

            if coverUrl == nil, let iconValue = icon, !iconValue.isEmpty {
                iconPickerButton(iconValue)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Icon Display

    private var addIconButton: some View {
        Button { showIconPicker = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "face.smiling").font(.system(size: 13))
                Text("Add icon").font(.system(size: 13))
            }
            .foregroundColor(.secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showIconPicker, arrowEdge: .top) {
            iconPickerPopover
        }
    }

    private var addCoverButton: some View {
        Button { showCoverPicker = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "photo").font(.system(size: 13))
                Text("Add cover").font(.system(size: 13))
            }
            .foregroundColor(.secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCoverPicker, arrowEdge: .top) {
            coverPickerPopover
        }
    }

    private func iconPickerButton(_ value: String) -> some View {
        Button(action: { showIconPicker = true }) {
            iconDisplay(value)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showIconPicker, arrowEdge: .top) {
            iconPickerPopover
        }
    }

    private var iconPickerPopover: some View {
        FullEmojiPickerView(
            selectedEmoji: $icon,
            onCustomIconSelected: { path in
                icon = "custom:\(path)"
            }
        )
    }

    private var coverPickerPopover: some View {
        CoverPickerView(coverUrl: $coverUrl, coverYPosition: $coverYPosition)
    }

    @ViewBuilder
    private func iconDisplay(_ value: String) -> some View {
        if value.hasPrefix("sf:") {
            let symbolName = String(value.dropFirst(3))
            Image(systemName: symbolName)
                .font(.system(size: 36))
                .frame(width: 56, height: 56)
        } else if value.hasPrefix("custom:") {
            let path = String(value.dropFirst(7))
            if let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(value).font(.system(size: 40))
            }
        } else {
            Text(value).font(.system(size: 46))
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
                            Rectangle().fill(Color.fallbackBgSecondary)
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
                        .font(.system(size: 12))
                }
                .buttonStyle(CoverActionButtonStyle())
                .popover(isPresented: $showCoverPicker, arrowEdge: .bottom) {
                    coverPickerPopover
                }

                Button(action: { coverUrl = nil; coverYPosition = 50 }) {
                    Label("Remove", systemImage: "xmark")
                        .font(.system(size: 12))
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
