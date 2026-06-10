import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Transparent NSView underlay that tracks mouse-down to update pane focus
/// without consuming the event. The NSTextView responder chain is unaffected.
#if os(macOS)
struct PaneFocusTracker: NSViewRepresentable {
    let paneId: UUID
    let onFocus: (UUID) -> Void

    func makeNSView(context: Context) -> FocusTrackingNSView {
        let view = FocusTrackingNSView()
        view.paneId = paneId
        view.onFocus = onFocus
        return view
    }

    func updateNSView(_ nsView: FocusTrackingNSView, context: Context) {
        nsView.paneId = paneId
        nsView.onFocus = onFocus
    }

    class FocusTrackingNSView: NSView {
        var paneId: UUID = UUID()
        var onFocus: ((UUID) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    guard let self, let window = self.window, event.window === window else { return event }
                    let locationInView = self.convert(event.locationInWindow, from: nil)
                    if self.bounds.contains(locationInView) {
                        self.onFocus?(self.paneId)
                    }
                    return event
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        override func removeFromSuperview() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            super.removeFromSuperview()
        }
    }
}
#endif
