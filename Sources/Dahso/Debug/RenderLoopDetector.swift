import SwiftUI

/// Detects excessive view re-renders in DEBUG builds.
/// Tracks render counts per view type in a rolling 1-second window.
/// Prints a warning if any view exceeds the threshold (default: 60 renders/sec).
///
/// Usage: Add `.trackRenders("ViewName")` to any view's body.
/// Only active in DEBUG builds — compiles to a no-op in Release.
#if DEBUG
@MainActor
final class RenderLoopDetector {
    static let shared = RenderLoopDetector()

    private var entries: [String: Entry] = [:]
    private let threshold = 60
    private let window: CFAbsoluteTime = 1.0

    private struct Entry {
        var count: Int
        var windowStart: CFAbsoluteTime
        var warned: Bool
    }

    func track(_ name: String) {
        let now = CFAbsoluteTimeGetCurrent()
        if var e = entries[name] {
            if now - e.windowStart > window {
                e = Entry(count: 1, windowStart: now, warned: false)
            } else {
                e.count += 1
                if e.count >= threshold && !e.warned {
                    e.warned = true
                    print("⚠️ RENDER LOOP: \(name) rendered \(e.count)× in 1s")
                }
            }
            entries[name] = e
        } else {
            entries[name] = Entry(count: 1, windowStart: now, warned: false)
        }
    }
}

private struct RenderLoopTracker: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        RenderLoopDetector.shared.track(name)
        return content
    }
}

extension View {
    /// Tracks render frequency. Warns in console if re-render loop detected.
    func trackRenders(_ name: String) -> some View {
        modifier(RenderLoopTracker(name: name))
    }
}
#else
extension View {
    @inline(__always)
    func trackRenders(_ name: String) -> some View { self }
}
#endif
