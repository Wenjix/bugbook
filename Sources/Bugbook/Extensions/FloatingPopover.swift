import SwiftUI

// MARK: - Popover Dismiss Environment Key

extension EnvironmentValues {
    @Entry var popoverDismiss: (() -> Void)? = nil
    @Entry var workspacePath: String? = nil
}

// MARK: - Floating Popover

extension View {
    /// Presents content in a borderless floating panel (macOS) or native popover (iOS).
    /// Always appears directly below the trigger. No arrow, no native clipping.
    /// Content should use `.popoverSurface()` for visual styling.
    func floatingPopover<Content: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .top,
        becomesKey: Bool = false,
        onDelete: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        background(
            FloatingPopoverAnchor(
                isPresented: isPresented,
                arrowEdge: arrowEdge,
                becomesKey: becomesKey,
                onDelete: onDelete,
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

    /// Tracks all active popover panels so sibling panels don't dismiss each other.
    static var activePanels = NSHashTable<PopoverPanel>.weakObjects()
}

private struct FloatingPopoverAnchor<PopoverContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let arrowEdge: Edge
    let becomesKey: Bool
    var onDelete: (() -> Void)?
    let content: () -> PopoverContent

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            if !context.coordinator.isVisible {
                // Panel hidden or never created — show() handles both reuse and first-time creation.
                context.coordinator.show(
                    anchor: nsView,
                    arrowEdge: arrowEdge,
                    becomesKey: becomesKey,
                    content: content(),
                    onDelete: onDelete,
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
        /// Always kept in sync with the current SwiftUI binding so it never goes stale.
        var dismissClosure: (() -> Void)?
        /// Whether the panel is currently visible (ordered in).
        private(set) var isVisible = false

        deinit { destroyPanel() }

        func show(anchor: NSView, arrowEdge: Edge = .top, becomesKey: Bool = false, content: some View, onDelete: (() -> Void)? = nil, dismiss: @escaping () -> Void) {
            guard let window = anchor.window else { return }

            dismissClosure = dismiss
            let wrapped = AnyView(content.environment(\.popoverDismiss, dismiss))

            // Reuse existing panel + hosting view when possible (avoids expensive
            // NSHostingView creation + fittingSize on repeated show/dismiss cycles).
            if let panel, let hosting = hostingView {
                hosting.rootView = wrapped
                let size = hosting.fittingSize
                guard size.width > 0, size.height > 0 else { return }
                hosting.setFrameSize(size)

                let origin = Self.computeOrigin(anchor: anchor, window: window, arrowEdge: arrowEdge, size: size)
                panel.setFrame(NSRect(origin: origin, size: size), display: true)

                if !isVisible {
                    window.addChildWindow(panel, ordered: .above)
                    if becomesKey {
                        panel.makeKeyAndOrderFront(nil)
                    } else {
                        panel.orderFront(nil)
                    }
                    PopoverPanel.activePanels.add(panel)
                    isVisible = true
                    installEventMonitors(panel: panel, onDelete: onDelete)
                }
                return
            }

            // First-time creation — build the NSPanel + NSHostingView from scratch.
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
            p.level = .floating
            p.contentView = hosting
            p.isMovableByWindowBackground = false
            p.isMovable = false

            let origin = Self.computeOrigin(anchor: anchor, window: window, arrowEdge: arrowEdge, size: size)
            p.setFrameOrigin(origin)
            p.hidesOnDeactivate = true
            window.addChildWindow(p, ordered: .above)
            if becomesKey {
                p.makeKeyAndOrderFront(nil)
            } else {
                p.orderFront(nil)
            }
            PopoverPanel.activePanels.add(p)
            self.panel = p
            self.hostingView = hosting
            self.isVisible = true

            installEventMonitors(panel: p, onDelete: onDelete)
        }

        func updateContent(_ content: some View, dismiss: @escaping () -> Void) {
            dismissClosure = dismiss
            hostingView?.rootView = AnyView(content.environment(\.popoverDismiss, dismiss))

            // Resize the panel to fit updated content (e.g. submenus appearing/disappearing).
            if let hosting = hostingView, let panel {
                let newSize = hosting.fittingSize
                if newSize != panel.frame.size, newSize.width > 0, newSize.height > 0 {
                    var frame = panel.frame
                    // Keep the top-left corner anchored (macOS coordinates: pin maxY).
                    let topY = frame.maxY
                    frame.size = newSize
                    frame.origin.y = topY - newSize.height

                    // Clamp to the visible screen area.
                    if let screen = panel.screen ?? NSScreen.main {
                        let vis = screen.visibleFrame
                        frame.origin.x = max(vis.minX + 4, min(frame.origin.x, vis.maxX - frame.width - 4))
                        frame.origin.y = max(vis.minY + 4, min(frame.origin.y, vis.maxY - frame.height - 4))
                    }

                    panel.setFrame(frame, display: true)
                    hosting.setFrameSize(newSize)
                }
            }
        }

        /// Sets binding to false AND hides the panel immediately.
        func dismissAndCleanup() {
            dismissClosure?()
            hide()
        }

        func dismiss() { hide() }

        /// Hide the panel without destroying it — allows fast reuse on next show().
        private func hide() {
            if let p = panel {
                PopoverPanel.activePanels.remove(p)
                p.parent?.removeChildWindow(p)
                p.orderOut(nil)
            }
            isVisible = false
            removeEventMonitors()
        }

        /// Fully tear down the panel (used only on deinit).
        private func destroyPanel() {
            if let p = panel {
                PopoverPanel.activePanels.remove(p)
                p.parent?.removeChildWindow(p)
            }
            panel?.close()
            panel = nil
            hostingView = nil
            isVisible = false
            removeEventMonitors()
        }

        // MARK: - Positioning

        private static func computeOrigin(anchor: NSView, window: NSWindow, arrowEdge: Edge, size: CGSize) -> NSPoint {
            let anchorBounds = anchor.convert(anchor.bounds, to: nil)
            let screenRect = window.convertToScreen(anchorBounds)
            let gap: Double = 4

            var origin: NSPoint
            if arrowEdge == .leading {
                let anchorMidY = screenRect.midY
                origin = NSPoint(
                    x: screenRect.minX - size.width - gap,
                    y: anchorMidY - size.height / 2
                )
            } else if arrowEdge == .trailing {
                let anchorMidY = screenRect.midY
                origin = NSPoint(
                    x: screenRect.maxX + gap,
                    y: anchorMidY - size.height / 2
                )
            } else {
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

            return origin
        }

        // MARK: - Event Monitors

        private func installEventMonitors(panel: PopoverPanel, onDelete: (() -> Void)?) {
            removeEventMonitors()

            // Dismiss on click outside, Escape, or Backspace (local)
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self, let panel = self.panel else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.dismissAndCleanup()
                    return nil
                }
                // Backspace → delete block (when onDelete is provided, e.g. block menu)
                if event.type == .keyDown, event.keyCode == 51, let onDelete {
                    self.dismissAndCleanup()
                    onDelete()
                    return nil
                }
                if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    if event.window !== panel,
                       !(event.window is PopoverPanel && PopoverPanel.activePanels.contains(event.window as? PopoverPanel)) {
                        self.dismissAndCleanup()
                    }
                }
                return event
            }

            // Dismiss on click outside (global — other apps)
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismissAndCleanup()
            }

            // Dismiss when panel loses key — but only if focus went to a non-popover window
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                guard self?.isVisible == true else { return }
                if let keyWindow = NSApp.keyWindow as? PopoverPanel,
                   PopoverPanel.activePanels.contains(keyWindow) {
                    return
                }
                self?.dismissAndCleanup()
            }
        }

        private func removeEventMonitors() {
            if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
            if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
            if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        }
    }
}

#endif
