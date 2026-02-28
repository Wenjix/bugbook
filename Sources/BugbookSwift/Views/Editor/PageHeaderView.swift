import SwiftUI
import AppKit

struct PageHeaderView: View {
    @Binding var icon: String?
    @Binding var coverUrl: String?
    @Binding var coverPosition: Double
    var fullWidth: Bool

    @State private var showIconPicker = false
    @State private var showCoverPicker = false
    @State private var isDraggingCover = false
    @State private var dragStartCoverPosition: Double = 50
    @State private var isHovering = false
    @State private var isRepositioning = false
    @State private var isCoverHovering = false

    private var horizontalPadding: CGFloat { fullWidth ? 40 : 80 }
    private var hasIcon: Bool { !(icon ?? "").isEmpty }
    private var needsIcon: Bool { icon == nil || icon?.isEmpty == true }
    private var needsCover: Bool { coverUrl == nil }
    private var coverControlsVisible: Bool { isCoverHovering || isRepositioning || showCoverPicker }

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
        .onChange(of: coverUrl) { _, newValue in
            if newValue == nil {
                isRepositioning = false
                coverPosition = 50
            }
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
        CoverPickerView(coverUrl: $coverUrl, coverYPosition: $coverPosition)
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
        ZStack(alignment: .topTrailing) {
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

            if isRepositioning {
                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .overlay(alignment: .center) {
                        Text("Drag to reposition")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDraggingCover {
                                    isDraggingCover = true
                                    dragStartCoverPosition = coverPosition
                                }
                                let sensitivity = 0.85
                                let newPosition = dragStartCoverPosition + Double(value.translation.height) * sensitivity
                                coverPosition = min(100, max(0, newPosition))
                            }
                            .onEnded { _ in
                                isDraggingCover = false
                            }
                    )
            }

            HStack(spacing: 4) {
                Button(action: { showCoverPicker = true }) {
                    Label("Change", systemImage: "photo")
                        .font(.system(size: 12))
                }
                .buttonStyle(CoverActionButtonStyle())
                .popover(isPresented: $showCoverPicker, arrowEdge: .bottom) {
                    coverPickerPopover
                }

                Button(action: {
                    isDraggingCover = false
                    isRepositioning.toggle()
                }) {
                    Label(isRepositioning ? "Done" : "Reposition", systemImage: isRepositioning ? "checkmark" : "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 12))
                }
                .buttonStyle(CoverActionButtonStyle())

                Button(action: {
                    coverUrl = nil
                    coverPosition = 50
                    isRepositioning = false
                }) {
                    Label("Remove", systemImage: "xmark")
                        .font(.system(size: 12))
                }
                .buttonStyle(CoverActionButtonStyle())
            }
            .padding(8)
            .opacity(coverControlsVisible ? 1 : 0)
            .allowsHitTesting(coverControlsVisible)
            .animation(.easeInOut(duration: 0.15), value: coverControlsVisible)
        }
        .frame(height: coverHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            isCoverHovering = hovering
        }
    }

    private func coverOffset(imageSize: NSSize, containerHeight: CGFloat) -> CGFloat {
        guard imageSize.height > 0 else { return 0 }
        let scale = max(1.0, imageSize.height / containerHeight)
        let maxOffset = (imageSize.height - containerHeight) / scale
        let normalizedPosition = coverPosition / 100.0
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
