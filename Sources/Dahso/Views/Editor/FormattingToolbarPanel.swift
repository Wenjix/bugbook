import AppKit
import SwiftUI

/// Non-activating floating panel that hosts the FormattingToolbar SwiftUI view.
/// Positioned above text selections without stealing keyboard focus from the editor.
class FormattingToolbarPanel: NSPanel {
    private let hostingView: NSHostingView<FormattingToolbar>
    private var formattingToolbar: FormattingToolbar

    init() {
        let noopToolbar = FormattingToolbar(
            onBold: {}, onItalic: {}, onCode: {}, onStrikethrough: {}, onLink: {}, onAskAI: nil
        )
        self.formattingToolbar = noopToolbar
        self.hostingView = NSHostingView(rootView: noopToolbar)

        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = true

        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }

    func updateActions(
        onBold: @escaping () -> Void,
        onItalic: @escaping () -> Void,
        onCode: @escaping () -> Void,
        onStrikethrough: @escaping () -> Void,
        onLink: @escaping () -> Void,
        onAskAI: (() -> Void)? = nil
    ) {
        formattingToolbar = FormattingToolbar(
            onBold: onBold,
            onItalic: onItalic,
            onCode: onCode,
            onStrikethrough: onStrikethrough,
            onLink: onLink,
            onAskAI: onAskAI
        )
        hostingView.rootView = formattingToolbar
    }

    /// Show the panel above the given screen-space rect.
    func show(above rect: CGRect) {
        let intrinsic = hostingView.intrinsicContentSize
        let width = max(intrinsic.width, 180)
        let height = max(intrinsic.height, 36)
        let gap: CGFloat = 6

        let x = rect.midX - width / 2
        let y = rect.maxY + gap

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        orderFront(nil)
    }

    func hidePanel() {
        orderOut(nil)
    }
}
