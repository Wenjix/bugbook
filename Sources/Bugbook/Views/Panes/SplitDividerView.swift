import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Draggable divider between two panes in a split.
/// Visual: 1px line with 8px hit area. Hover/drag shows thicker accent line.
struct SplitDividerView: View {
    let axis: PaneNode.Split.Axis
    @Binding var ratio: Double
    let totalSize: CGFloat

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartRatio: Double = 0

    private var isVerticalLine: Bool { axis == .horizontal }

    var body: some View {
        ZStack {
            // Visible divider line
            Rectangle()
                .fill(lineColor)
                .frame(
                    width: isVerticalLine ? lineThickness : nil,
                    height: isVerticalLine ? nil : lineThickness
                )

            // Transparent hit area
            Color.clear
                .frame(
                    width: isVerticalLine ? 8 : nil,
                    height: isVerticalLine ? nil : 8
                )
                .contentShape(Rectangle())
        }
        .frame(
            width: isVerticalLine ? 8 : nil,
            height: isVerticalLine ? nil : 8
        )
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

    private var lineColor: Color {
        if isDragging { return Color.fallbackAccent }
        if isHovered { return Color.fallbackAccent.opacity(Opacity.heavy) }
        return Color.fallbackChromeBorder
    }

    private var lineThickness: CGFloat {
        (isDragging || isHovered) ? 3 : 1
    }
}
