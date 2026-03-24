import SwiftUI

struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block
    @State private var transcriptionService = TranscriptionService()
    @State private var permissionGranted: Bool?

    private var isRecording: Bool {
        transcriptionService.isRecording
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with controls
            header

            Divider()
                .padding(.horizontal, 12)

            // Waveform during recording
            if isRecording {
                AudioBarsView(audioLevel: transcriptionService.audioLevel)
                    .frame(height: 32)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            // Transcript area
            transcriptArea
        }
        .background(Color.primary.opacity(Opacity.subtle))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.primary.opacity(Opacity.light), lineWidth: 1)
        )
        .onChange(of: transcriptionService.currentTranscript) { _, newTranscript in
            guard !newTranscript.isEmpty else { return }
            document.updateBlockProperty(id: block.id) { b in
                b.text = newTranscript
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isRecording ? StatusColor.error : Color.fallbackTextSecondary)

            Text("Meeting Recording")
                .font(.system(size: Typography.bodySmall, weight: .medium))
                .foregroundStyle(Color.fallbackTextPrimary)

            Spacer()

            if let error = transcriptionService.error {
                Text(error)
                    .font(.system(size: Typography.caption2))
                    .foregroundStyle(StatusColor.error)
                    .lineLimit(1)
            }

            if isRecording {
                recordingIndicator
            }

            recordButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var recordingIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(StatusColor.error)
                .frame(width: 6, height: 6)

            Text("Recording")
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(StatusColor.error)
        }
    }

    private var recordButton: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 12))
                Text(isRecording ? "Stop" : "Record")
                    .font(.system(size: Typography.caption, weight: .medium))
            }
            .foregroundStyle(isRecording ? StatusColor.error : Color.fallbackAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (isRecording ? StatusColor.error : Color.fallbackAccent).opacity(Opacity.medium)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transcript

    private var transcriptArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            if block.text.isEmpty && block.transcriptEntries.isEmpty && !isRecording {
                Text("Click Record to start capturing audio")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(Color.fallbackTextMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                // Show finalized transcript entries
                ForEach(Array(block.transcriptEntries.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.system(size: Typography.bodySmall))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                }

                // Show live transcript (current recording in progress)
                if !block.text.isEmpty {
                    Text(block.text)
                        .font(.system(size: Typography.bodySmall))
                        .foregroundStyle(isRecording ? Color.fallbackTextSecondary : Color.fallbackTextPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                }

                Spacer().frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func startRecording() {
        Task {
            if permissionGranted == nil {
                permissionGranted = await transcriptionService.requestPermissions()
            }
            guard permissionGranted == true else { return }
            transcriptionService.startRecording()
        }
    }

    private func stopRecording() {
        let finalTranscript = transcriptionService.currentTranscript
        transcriptionService.stopRecording()

        // Move current live text into transcript entries
        if !finalTranscript.isEmpty {
            document.updateBlockProperty(id: block.id) { b in
                b.transcriptEntries.append(finalTranscript)
                b.text = ""
            }
        }
    }
}

// MARK: - Audio Bars View

struct AudioBarsView: View {
    let audioLevel: Float
    private let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                AudioBar(
                    audioLevel: audioLevel,
                    barIndex: index,
                    totalBars: barCount
                )
            }
        }
    }
}

private struct AudioBar: View {
    let audioLevel: Float
    let barIndex: Int
    let totalBars: Int

    @State private var animatedHeight: CGFloat = 0.1

    private var targetHeight: CGFloat {
        let center = CGFloat(totalBars) / 2.0
        let distance = abs(CGFloat(barIndex) - center) / center
        let baseHeight: CGFloat = 0.1
        let level = CGFloat(audioLevel)
        // Bars near center are taller; edges taper off
        let taper = 1.0 - (distance * 0.6)
        // Add slight randomness for organic feel
        let jitter = CGFloat.random(in: 0.85...1.15)
        return max(baseHeight, level * taper * jitter)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.fallbackAccent.opacity(0.6 + Double(audioLevel) * 0.4))
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
