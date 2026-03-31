import AppKit
import SwiftUI

// MARK: - Floating Recording Pill Panel

/// A small always-on-top pill that appears when a meeting is recording.
/// Shows animated green audio bars, a live duration counter, and a stop button.
/// Clicking the pill body brings Bugbook back to the front.
final class FloatingRecordingPillPanel: NSPanel {
    private let hostingView: NSHostingView<RecordingPillView>

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        self.hostingView = NSHostingView(rootView: RecordingPillView())

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 30),
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

    func showPill(startDate: Date, onStop: @escaping () -> Void) {
        hostingView.rootView = RecordingPillView(
            isAnimating: true,
            recordingStart: startDate,
            onStop: onStop
        )

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
    var recordingStart: Date = .now
    var onStop: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            // Tappable area: icon + bars + duration → brings app to front
            HStack(spacing: 6) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))

                AudioBarsView(isAnimating: isAnimating)
                    .frame(width: 16, height: 14)

                if isAnimating {
                    DurationLabel(since: recordingStart)
                }
            }
            .contentShape(Capsule())
            .onTapGesture {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            if isAnimating {
                // Stop button
                Button {
                    onStop?()
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(hex: "1a1a1a"))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        )
    }
}

// MARK: - Duration Label

private struct DurationLabel: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(since))
            let m = elapsed / 60
            let s = elapsed % 60
            Text(String(format: "%d:%02d", m, s))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.85))
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
        let freq = 2.5 + Double(seed) * 1.3
        let raw = (sin(t * freq) + 1) / 2
        let jitter = sin(t * freq * 2.7) * 0.15
        return max(minFraction, min(1.0, raw + jitter))
    }
}

// MARK: - Controller

/// Manages the lifecycle of the floating recording pill.
/// Owns the panel and responds to recording state changes.
@MainActor
final class FloatingRecordingPillController {
    private var panel: FloatingRecordingPillPanel?
    private var recordingStart: Date?

    /// Called when the user taps the stop button on the pill.
    var onStop: (() -> Void)?

    /// Whether recording is active. Set from outside; the controller handles show/hide.
    var isRecording: Bool = false {
        didSet {
            guard isRecording != oldValue else { return }
            if isRecording {
                recordingStart = .now
            }
            updateVisibility()
        }
    }

    func cleanup() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func updateVisibility() {
        if isRecording {
            if panel == nil {
                panel = FloatingRecordingPillPanel()
            }
            panel?.showPill(startDate: recordingStart ?? .now, onStop: { [weak self] in
                Task { @MainActor in self?.onStop?() }
            })
        } else {
            panel?.hidePill()
            recordingStart = nil
        }
    }
}
