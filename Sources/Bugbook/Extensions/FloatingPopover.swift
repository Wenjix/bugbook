import SwiftUI

// MARK: - Popover Dismiss Environment Key

private struct PopoverDismissKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var popoverDismiss: (() -> Void)? {
        get { self[PopoverDismissKey.self] }
        set { self[PopoverDismissKey.self] = newValue }
    }
}

// MARK: - Floating Popover

extension View {
    /// Presents content in a borderless floating panel (macOS) or native popover (iOS).
    /// Always appears directly below the trigger. No arrow, no native clipping.
    /// Content should use `.popoverSurface()` for visual styling.
    func floatingPopover<Content: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        background(
            FloatingPopoverAnchor(
                isPresented: isPresented,
                arrowEdge: arrowEdge,
                content: content
            )
        )
        #else
        popover(isPresented: isPresented, arrowEdge: arrowEdge, content: content)
        #endif
    }

    /// Item-based variant: presents when item is non-nil.
    func floatingPopover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        floatingPopover(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            arrowEdge: arrowEdge
        ) {
            if let value = item.wrappedValue {
                content(value)
            }
        }
    }
}

// MARK: - macOS Panel Implementation

#if os(macOS)

private class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct FloatingPopoverAnchor<PopoverContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let arrowEdge: Edge
    let content: () -> PopoverContent

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            if context.coordinator.panel == nil {
                context.coordinator.show(
                    anchor: nsView,
                    arrowEdge: arrowEdge,
                    content: content(),
                    dismiss: { isPresented = false }
                )
            } else {
                context.coordinator.updateContent(content(), dismiss: { isPresented = false })
            }
        } else {
            context.coordinator.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        var panel: PopoverPanel?
        var hostingView: NSHostingView<AnyView>?
        var localMonitor: Any?
        var globalMonitor: Any?
        var resignObserver: NSObjectProtocol?

        deinit { cleanup() }

        func show(anchor: NSView, arrowEdge: Edge = .top, content: some View, dismiss: @escaping () -> Void) {
            guard panel == nil, let window = anchor.window else { return }

            let wrapped = AnyView(content.environment(\.popoverDismiss, dismiss))
            let hosting = NSHostingView(rootView: wrapped)
            hosting.setFrameSize(hosting.fittingSize)
            let size = hosting.fittingSize
            guard size.width > 0, size.height > 0 else { return }

            let p = PopoverPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .popUpMenu
            p.contentView = hosting
            p.isMovableByWindowBackground = false
            p.isMovable = false

            // Position below the anchor by default, or to the left for .leading
            let anchorBounds = anchor.convert(anchor.bounds, to: nil)
            let screenRect = window.convertToScreen(anchorBounds)
            let gap: Double = 4

            var origin: NSPoint
            if arrowEdge == .leading {
                // To the left of the anchor, vertically centered
                let anchorMidY = screenRect.midY
                origin = NSPoint(
                    x: screenRect.minX - size.width - gap,
                    y: anchorMidY - size.height / 2
                )
            } else {
                // Below the anchor, left-aligned
                origin = NSPoint(
                    x: screenRect.minX,
                    y: screenRect.minY - size.height - gap
                )
            }

            // Keep on screen
            if let screen = window.screen ?? NSScreen.main {
                let vis = screen.visibleFrame
                origin.x = max(vis.minX + 4, min(origin.x, vis.maxX - size.width - 4))
                origin.y = max(vis.minY + 4, min(origin.y, vis.maxY - size.height - 4))
            }

            p.setFrameOrigin(origin)
            p.orderFront(nil)
            self.panel = p
            self.hostingView = hosting

            // Dismiss on click outside or Escape key (local)
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self, let panel = self.panel else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    dismiss()
                    return nil
                }
                if event.window !== panel {
                    dismiss()
                }
                return event
            }

            // Dismiss on click outside (global — other apps)
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard self?.panel != nil else { return }
                dismiss()
            }

            // Dismiss when panel loses key (user clicked main window or another app)
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: p,
                queue: .main
            ) { [weak self] _ in
                guard self?.panel != nil else { return }
                dismiss()
            }
        }

        func updateContent(_ content: some View, dismiss: @escaping () -> Void) {
            hostingView?.rootView = AnyView(content.environment(\.popoverDismiss, dismiss))
        }

        func dismiss() { cleanup() }

        private func cleanup() {
            panel?.close()
            panel = nil
            hostingView = nil
            if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
            if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
            if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        }
    }
}

#endif
