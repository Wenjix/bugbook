import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Draggable divider between two panes in a split.
/// Visual: 2px line with 8px hit area. Hover/drag shows thicker accent line with grip dots.
struct SplitDividerView: View {
    let axis: PaneNode.Split.Axis
    @Binding var ratio: Double
    let totalSize: CGFloat

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartRatio: Double = 0

    private var isVerticalLine: Bool { axis == .horizontal }

    private let dividerSize: CGFloat = Container.groutGap

    var body: some View {
        ZStack {
            // Grout gap — transparent so window bg shows through
            Color.clear

            // Grip dots — centered on divider, visible on hover/drag
            if isHovered || isDragging {
                gripDots
            }
        }
        .frame(
            width: isVerticalLine ? dividerSize : nil,
            height: isVerticalLine ? nil : dividerSize
        )
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                if isVerticalLine {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
        #endif
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartRatio = ratio
                    }
                    let delta: CGFloat = isVerticalLine ? value.translation.width : value.translation.height
                    guard totalSize > 0 else { return }
                    let newRatio = dragStartRatio + Double(delta / totalSize)
                    ratio = min(max(newRatio, 0.15), 0.85)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                ratio = 0.5
            }
        }
    }

    // MARK: - Grip Dots

    /// Small dots centered on the divider to signal draggability.
    private var gripDots: some View {
        let dotCount = 3
        let dotSize: CGFloat = 3
        let dotSpacing: CGFloat = 3

        return Group {
            if isVerticalLine {
                VStack(spacing: dotSpacing) {
                    ForEach(0..<dotCount, id: \.self) { _ in
                        Circle()
                            .fill(Color.fallbackAccent.opacity(Opacity.strong))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            } else {
                HStack(spacing: dotSpacing) {
                    ForEach(0..<dotCount, id: \.self) { _ in
                        Circle()
                            .fill(Color.fallbackAccent.opacity(Opacity.strong))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
        }
    }

    private var lineColor: Color {
        if isDragging { return Color.fallbackAccent }
        if isHovered { return Color.fallbackAccent.opacity(Opacity.heavy) }
        return Color.fallbackChromeBorder
    }

    private var lineThickness: CGFloat {
        if isDragging || isHovered { return 3 }
        return 2
    }
}
