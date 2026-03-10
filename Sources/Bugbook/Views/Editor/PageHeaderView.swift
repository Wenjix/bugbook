import SwiftUI
import AppKit

struct PageHeaderView: View {
    @Binding var icon: String?
    @Binding var coverUrl: String?
    @Binding var coverPosition: Double
    var fullWidth: Bool
    var contentColumnMaxWidth: CGFloat? = nil

    @State private var showIconPicker = false
    @State private var showCoverPicker = false
    @State private var isDraggingCover = false
    @State private var dragStartCoverPosition: Double = 50
    @State private var isHovering = false
    @State private var isRepositioning = false
    @State private var isCoverHovering = false

    // Keep page-header controls and icon aligned with the title/body text column.
    private var horizontalPadding: CGFloat { 76 }
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
                        columnAligned {
                            iconPickerButton(iconValue)
                                .padding(.leading, horizontalPadding)
                        }
                        .offset(y: 22)
                    }
                }
                .padding(.bottom, hasIcon ? 26 : 0)
            }

            // Action buttons — show on hover when missing icon/cover
            if needsIcon || needsCover {
                columnAligned {
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
            }

            if coverUrl == nil, let iconValue = icon, !iconValue.isEmpty {
                columnAligned {
                    HStack(spacing: 0) {
                        iconPickerButton(iconValue)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, horizontalPadding)
                    .padding(.top, 8)
                }
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

    // MARK: - Column Alignment

    @ViewBuilder
    private func columnAligned<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if let maxWidth = contentColumnMaxWidth {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content()
                    .frame(maxWidth: maxWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
        } else {
            content()
        }
    }

    // MARK: - Icon Display

    private var addIconButton: some View {
        Button { showIconPicker = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "face.smiling").font(.system(size: 13))
                Text("Add icon").font(.system(size: 13))
            }
            .foregroundStyle(.secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .floatingPopover(isPresented: $showIconPicker, arrowEdge: .top) {
            iconPickerPopover
        }
    }

    private var addCoverButton: some View {
        Button { showCoverPicker = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "photo").font(.system(size: 13))
                Text("Add cover").font(.system(size: 13))
            }
            .foregroundStyle(.secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .floatingPopover(isPresented: $showCoverPicker, arrowEdge: .top) {
            coverPickerPopover
        }
    }

    private func iconPickerButton(_ value: String) -> some View {
        Button(action: { showIconPicker = true }) {
            iconDisplay(value)
        }
        .buttonStyle(.plain)
        .floatingPopover(isPresented: $showIconPicker, arrowEdge: .top) {
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
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                Text(value).font(.system(size: 40))
            }
        } else {
            Text(value)
                .font(.system(size: 46))
                .frame(width: 56, height: 56, alignment: .leading)
        }
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImageView(path: String) -> some View {
        let coverHeight: CGFloat = 200
        let loadedImage = NSImage(contentsOfFile: path)
        let imgSize = loadedImage?.size ?? .zero
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Group {
                    if let nsImage = loadedImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: coverHeight)
                            .offset(y: coverOffset(imageSize: imgSize, containerSize: CGSize(width: geometry.size.width, height: coverHeight)))
                            .clipped()
                    } else {
                        // Local paths need fileURLWithPath (handles spaces); remote URLs use URL(string:)
                        let url: URL? = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(string: path)
                        if let url = url {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: coverHeight)
                                    .clipped()
                            } placeholder: {
                                Rectangle().fill(Color.fallbackBgSecondary)
                            }
                            .frame(width: geometry.size.width, height: coverHeight)
                        }
                    }
                }

                if isRepositioning {
                    Rectangle()
                        .fill(Color.black.opacity(0.18))
                        .overlay(alignment: .center) {
                            Text("Drag to reposition")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
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
                                    let maxOffset = max(1, coverOverflowHeight(containerSize: CGSize(width: geometry.size.width, height: coverHeight), imageSize: imgSize))
                                    let deltaPercent = Double(value.translation.height / maxOffset) * 100.0
                                    let newPosition = dragStartCoverPosition + deltaPercent
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
                    .floatingPopover(isPresented: $showCoverPicker, arrowEdge: .bottom) {
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
        .frame(height: coverHeight)
    }

    private func coverOverflowHeight(containerSize: CGSize, imageSize: NSSize) -> CGFloat {
        guard containerSize.width > 0,
              containerSize.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else { return 0 }
        let scale = max(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let renderedHeight = imageSize.height * scale
        return max(0, renderedHeight - containerSize.height)
    }

    private func coverOffset(imageSize: NSSize, containerSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return 0 }
        let scale = max(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let renderedHeight = imageSize.height * scale
        let overflow = max(0, renderedHeight - containerSize.height)
        let normalizedPosition = coverPosition / 100.0
        return (overflow / 2) - (overflow * normalizedPosition)
    }
}

private struct CoverActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(configuration.isPressed ? 0.6 : 0.4))
            .clipShape(.rect(cornerRadius: 4))
    }
}
