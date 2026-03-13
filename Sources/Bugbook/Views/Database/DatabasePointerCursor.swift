import SwiftUI

struct CursorRectOverlay: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectNSView {
        CursorRectNSView(cursor: cursor)
    }

    func updateNSView(_ nsView: CursorRectNSView, context: Context) {
        nsView.cursor = cursor
    }
}

final class CursorRectNSView: NSView {
    var cursor: NSCursor {
        didSet {
            guard oldValue !== cursor else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override init(frame frameRect: NSRect) {
        self.cursor = .arrow
        super.init(frame: frameRect)
        wantsLayer = false
    }

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
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
        addCursorRect(bounds, cursor: cursor)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }
}

extension View {
    func appCursor(_ cursor: NSCursor) -> some View {
        overlay(CursorRectOverlay(cursor: cursor))
    }

    func databasePointerCursor() -> some View {
        appCursor(.arrow)
    }

    func editorTextCursor() -> some View {
        appCursor(.iBeam)
    }
}
