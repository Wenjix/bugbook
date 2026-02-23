import SwiftUI
import AppKit

struct PageHeaderView: View {
    @Binding var title: String
    @Binding var icon: String?
    @Binding var coverUrl: String?
    var fullWidth: Bool
    var onTitleCommit: () -> Void

    @State private var showIconPicker = false
    @State private var showCoverPicker = false
    @State private var isHovering = false
    @State private var coverYPosition: Double = 50
    @State private var isDraggingCover = false
    @State private var dragStartY: CGFloat = 0

    private var horizontalPadding: CGFloat { fullWidth ? 40 : 80 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image
            if let coverPath = coverUrl {
                coverImageView(path: coverPath)
            }

            // Hover action buttons (Add icon / Add cover)
            if isHovering {
                hoverButtons
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, coverUrl != nil ? 8 : 12)
                    .transition(.opacity)
            }

            // Icon + Title row
            HStack(alignment: .top, spacing: 8) {
                // Icon
                if let iconValue = icon, !iconValue.isEmpty {
                    Button(action: { showIconPicker.toggle() }) {
                        iconDisplay(iconValue)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showIconPicker) {
                        FullEmojiPickerView(
                            selectedEmoji: $icon,
                            onCustomIconSelected: { path in
                                icon = "custom:\(path)"
                            }
                        )
                    }
                }

                // Title
                TextField("Untitled", text: $title, onCommit: onTitleCommit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 32, weight: .bold))
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, icon != nil ? 4 : (coverUrl != nil ? 12 : (isHovering ? 4 : 40)))
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
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
                    GeometryReader { geo in
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: coverHeight)
                            .offset(y: coverOffset(imageSize: nsImage.size, containerHeight: coverHeight))
                            .clipped()
                    }
                    .frame(height: coverHeight)
                } else if let url = URL(string: path) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(height: coverHeight)
                    .clipped()
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

            if isHovering {
                HStack(spacing: 4) {
                    Button(action: { showCoverPicker = true }) {
                        Label("Reposition", systemImage: "arrow.up.and.down")
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
                .transition(.opacity)
            }
        }
        .popover(isPresented: $showCoverPicker) {
            CoverPickerView(coverUrl: $coverUrl, coverYPosition: $coverYPosition)
        }
    }

    private func coverOffset(imageSize: NSSize, containerHeight: CGFloat) -> CGFloat {
        guard imageSize.height > 0 else { return 0 }
        let scale = max(1.0, imageSize.height / containerHeight)
        let maxOffset = (imageSize.height - containerHeight) / scale
        let normalizedPosition = coverYPosition / 100.0
        return -maxOffset * normalizedPosition
    }

    // MARK: - Hover Buttons

    private var hoverButtons: some View {
        HStack(spacing: 8) {
            if icon == nil || icon?.isEmpty == true {
                HoverActionButton(title: "Add icon", systemImage: "face.smiling") {
                    showIconPicker = true
                }
                .popover(isPresented: $showIconPicker) {
                    FullEmojiPickerView(
                        selectedEmoji: $icon,
                        onCustomIconSelected: { path in
                            icon = "custom:\(path)"
                        }
                    )
                }
            }

            if coverUrl == nil {
                HoverActionButton(title: "Add cover", systemImage: "photo") {
                    showCoverPicker = true
                }
                .popover(isPresented: $showCoverPicker) {
                    CoverPickerView(coverUrl: $coverUrl, coverYPosition: $coverYPosition)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Supporting Views

private struct HoverActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
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
