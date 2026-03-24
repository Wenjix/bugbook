import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Manages the floating recording pill panel lifecycle.
class FloatingRecordingPillController {
    #if os(macOS)
    private var panel: FloatingRecordingPillPanel?
    #endif

    var isRecording: Bool = false {
        didSet {
            #if os(macOS)
            if isRecording {
                let p = FloatingRecordingPillPanel(startDate: Date())
                p.orderFront(nil)
                panel = p
            } else {
                panel?.close()
                panel = nil
            }
            #endif
        }
    }

    func cleanup() {
        #if os(macOS)
        panel?.close()
        panel = nil
        #endif
    }
}

/// A floating pill indicator shown when a meeting recording is active.
/// Displays a pulsing red dot, elapsed time, and audio level bars.
struct FloatingRecordingPill: View {
    let audioLevel: Float
    let onStop: () -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var startDate = Date()

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing red dot
            PulsingDot()

            // Elapsed time
            Text(formattedTime)
                .font(.system(size: Typography.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.fallbackTextPrimary)

            // Mini audio bars
            MiniAudioBars(audioLevel: audioLevel)
                .frame(width: 32, height: 14)

            // Stop button
            Button {
                onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(StatusColor.error)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Elevation.popoverBg)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Elevation.popoverBorder, lineWidth: 1)
        )
        .shadow(
            color: Elevation.shadowColor.opacity(Elevation.shadowOpacity),
            radius: Elevation.shadowRadius,
            y: Elevation.shadowY
        )
        .onAppear {
            startDate = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    elapsed = Date().timeIntervalSince(startDate)
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var formattedTime: String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(StatusColor.error)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Mini Audio Bars

private struct MiniAudioBars: View {
    let audioLevel: Float
    private let barCount = 5

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                MiniBar(audioLevel: audioLevel, barIndex: index, totalBars: barCount)
            }
        }
    }
}

private struct MiniBar: View {
    let audioLevel: Float
    let barIndex: Int
    let totalBars: Int

    @State private var animatedHeight: CGFloat = 0.15

    private var targetHeight: CGFloat {
        let center = CGFloat(totalBars) / 2.0
        let distance = abs(CGFloat(barIndex) - center) / center
        let baseHeight: CGFloat = 0.15
        let level = CGFloat(audioLevel)
        let taper = 1.0 - (distance * 0.5)
        let jitter = CGFloat.random(in: 0.85...1.15)
        return max(baseHeight, level * taper * jitter)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(StatusColor.error.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(y: animatedHeight, anchor: .center)
            .onChange(of: audioLevel) { _, _ in
                withAnimation(.easeInOut(duration: 0.08)) {
                    animatedHeight = targetHeight
                }
            }
            .onAppear {
                animatedHeight = targetHeight
            }
    }
}
