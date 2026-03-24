import AppKit
import SwiftUI

/// A small always-on-top pill that shows recording status (red dot + elapsed time).
/// Uses NSPanel with `.floating` level so it remains visible even when Bugbook is backgrounded.
/// Clicking the pill activates the Bugbook window.
class FloatingRecordingPillPanel: NSPanel {
    private let hostingView: NSHostingView<FloatingRecordingPillView>
    private var pillView: FloatingRecordingPillView

    init(startDate: Date) {
        let view = FloatingRecordingPillView(startDate: startDate)
        self.pillView = view
        self.hostingView = NSHostingView(rootView: view)

        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false  // stays visible when app is backgrounded
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = hostingView

        let size = hostingView.fittingSize
        let width = max(size.width, 120)
        let height = max(size.height, 32)

        // Position at top-center of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.maxY - height - 8
            setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }

    override var canBecomeKey: Bool { false }

    func show() {
        orderFront(nil)
    }

    func hidePanel() {
        orderOut(nil)
    }
}

// MARK: - SwiftUI Pill View

struct FloatingRecordingPillView: View {
    let startDate: Date
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: activateBugbook) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)

                Text(formattedTime)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(startDate)
        }
        .onAppear {
            elapsed = Date().timeIntervalSince(startDate)
        }
    }

    private var formattedTime: String {
        let total = Int(elapsed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func activateBugbook() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Bring the main window to front
        for window in NSApplication.shared.windows {
            if !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}
