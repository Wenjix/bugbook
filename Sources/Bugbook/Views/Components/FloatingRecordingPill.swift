import AppKit
import SwiftUI

// MARK: - Floating Recording Pill Panel

/// A small always-on-top pill that appears when a meeting is recording and Bugbook
/// loses focus. Shows animated green audio bars inside a dark capsule.
/// Clicking it brings Bugbook back to the front.
final class FloatingRecordingPillPanel: NSPanel {
    private let hostingView: NSHostingView<RecordingPillView>

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        self.hostingView = NSHostingView(rootView: RecordingPillView())

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        contentView = hostingView
    }

    func showPill() {
        hostingView.rootView = RecordingPillView(isAnimating: true)

        // Re-evaluate size and position each show (handles display changes)
        let size = hostingView.fittingSize
        setContentSize(size)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size.width / 2
            let y = screenFrame.maxY - size.height - 12
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        orderFront(nil)
    }

    func hidePill() {
        hostingView.rootView = RecordingPillView(isAnimating: false)
        orderOut(nil)
    }
}

// MARK: - Recording Pill SwiftUI View

private struct RecordingPillView: View {
    var isAnimating: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            // App icon (small ladybug)
            Image(systemName: "ladybug.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))

            // Animated audio bars
            AudioBarsView(isAnimating: isAnimating)
                .frame(width: 16, height: 14)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(hex: "1a1a1a"))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        )
        .contentShape(Capsule())
        .onTapGesture {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Animated Audio Bars

private struct AudioBarsView: View {
    var isAnimating: Bool

    private static let barCount = 3
    private static let spacing: CGFloat = 1.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: !isAnimating)) { timeline in
            HStack(spacing: Self.spacing) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    AudioBar(
                        date: timeline.date,
                        seed: index,
                        isAnimating: isAnimating
                    )
                }
            }
        }
    }
}

private struct AudioBar: View {
    var date: Date
    var seed: Int
    var isAnimating: Bool

    private let green = Color(hex: "4ade80")
    private let maxHeight: CGFloat = 14
    private let minFraction: CGFloat = 0.25

    var body: some View {
        let fraction = isAnimating ? barHeight(date: date, seed: seed) : 0.3
        RoundedRectangle(cornerRadius: 1.5)
            .fill(green)
            .frame(width: 3, height: fraction * maxHeight)
            .animation(.easeInOut(duration: 0.15), value: date)
    }

    /// Pseudo-random bar height derived from time + seed for organic movement.
    private func barHeight(date: Date, seed: Int) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        // Different frequency per bar so they don't sync up
        let freq = 2.5 + Double(seed) * 1.3
        let raw = (sin(t * freq) + 1) / 2       // 0...1
        let jitter = sin(t * freq * 2.7) * 0.15  // small wobble
        return max(minFraction, min(1.0, raw + jitter))
    }
}

// MARK: - Controller

/// Manages the lifecycle of the floating recording pill.
/// Owns the panel and responds to app activation / recording state changes.
@MainActor
final class FloatingRecordingPillController {
    private var panel: FloatingRecordingPillPanel?
    private var activateObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?

    /// Whether recording is active. Set from outside; the controller handles show/hide.
    var isRecording: Bool = false {
        didSet {
            guard isRecording != oldValue else { return }
            updateVisibility()
        }
    }

    init() {
        activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        }
    }

    /// Tear down the panel and notification observers. Call from `.onDisappear`
    /// so cleanup runs on MainActor (deinit is nonisolated and can't do this safely).
    func cleanup() {
        if let o = activateObserver { NotificationCenter.default.removeObserver(o) }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        activateObserver = nil
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func updateVisibility() {
        let shouldShow = isRecording && !NSApplication.shared.isActive
        if shouldShow {
            if panel == nil {
                panel = FloatingRecordingPillPanel()
            }
            panel?.showPill()
        } else {
            panel?.hidePill()
        }
    }
}
