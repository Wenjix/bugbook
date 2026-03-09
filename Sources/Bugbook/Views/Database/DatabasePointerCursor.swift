import SwiftUI

struct DatabasePointerCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> DatabasePointerCursorNSView {
        DatabasePointerCursorNSView()
    }

    func updateNSView(_ nsView: DatabasePointerCursorNSView, context: Context) {
    }
}

final class DatabasePointerCursorNSView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }
}

extension View {
    func databasePointerCursor() -> some View {
        overlay(DatabasePointerCursorOverlay())
    }
}
