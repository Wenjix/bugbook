import SwiftUI

struct CanvasToolbar: View {
    var document: CanvasDocument
    var visibleCenter: CGPoint
    var onAddFilePicker: () -> Void
    var onAddImage: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: addTextNode) {
                Label("Text", systemImage: "text.alignleft")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))

            Button(action: onAddFilePicker) {
                Label("Page", systemImage: "doc.text")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))

            Button(action: onAddImage) {
                Label("Image", systemImage: "photo")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))

            Divider().frame(height: 20)

            // Shape tools
            Button(action: addRectangle) {
                Label("Rect", systemImage: "rectangle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))

            Button(action: addEllipse) {
                Label("Ellipse", systemImage: "circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))

            Button(action: addDiamond) {
                Label("Diamond", systemImage: "diamond")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))

            if !document.selectedNodeIds.isEmpty || document.selectedEdgeId != nil {
                Divider().frame(height: 20)
                Button(action: deleteSelected) {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.06))
                .clipShape(.rect(cornerRadius: 6))
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 4) {
                Button(action: zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)

                Text("\(Int(document.viewport.zoom * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                Button(action: zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .clipShape(.rect(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }

    private func addTextNode() {
        document.addTextNode(at: visibleCenter)
    }

    private func addRectangle() {
        document.addShapeNode(at: visibleCenter, type: .rectangle)
    }

    private func addEllipse() {
        document.addShapeNode(at: visibleCenter, type: .ellipse)
    }

    private func addDiamond() {
        document.addShapeNode(at: visibleCenter, type: .diamond)
    }

    private func deleteSelected() {
        document.deleteSelection()
    }

    private func zoomIn() {
        document.viewport.zoom = min(3.0, document.viewport.zoom + 0.1)
    }

    private func zoomOut() {
        document.viewport.zoom = max(0.3, document.viewport.zoom - 0.1)
    }
}
