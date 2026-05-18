import SwiftUI

struct MeetingPagePropertyPills: View {
    let date: Date
    let participants: [String]
    let activeSession: ActiveMeetingSession?
    let canStartRecording: Bool
    let isStartingRecording: Bool
    let isStoppingRecording: Bool
    let showsManualSummaryButton: Bool
    let hasSummaryContent: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onGenerateSummary: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            propertyChip(icon: "calendar", text: Self.pillDateFormatter.string(from: date))
            recordingPill
            if !participants.isEmpty {
                propertyChip(icon: "person.2", text: participants.joined(separator: ", "))
            }
            if showsManualSummaryButton {
                manualSummaryButton
            }
        }
    }

    @ViewBuilder
    private var recordingPill: some View {
        if let activeSession {
            Button(action: onStopRecording) {
                HStack(spacing: 8) {
                    if isStoppingRecording {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                    }
                    TimelineView(.periodic(from: activeSession.startDate, by: 1)) { context in
                        let elapsed = Int(context.date.timeIntervalSince(activeSession.startDate))
                        Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                            .font(.system(size: Typography.bodySmall, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Text(isStoppingRecording ? "Finalizing..." : "Stop Recording")
                        .font(.system(size: Typography.bodySmall, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(StatusColor.error))
            }
            .buttonStyle(.plain)
            .disabled(isStoppingRecording)
        } else if canStartRecording || isStartingRecording {
            Button(action: onStartRecording) {
                HStack(spacing: 5) {
                    if isStartingRecording {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Circle().fill(StatusColor.error).frame(width: 7, height: 7)
                    }
                    Text(isStartingRecording ? "Starting..." : "Record")
                        .font(.system(size: Typography.caption, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(Opacity.medium), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isStartingRecording)
        }
    }

    private var manualSummaryButton: some View {
        Button(action: onGenerateSummary) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                Text(hasSummaryContent ? "Regenerate Summary" : "Generate Summary")
                    .font(.system(size: Typography.caption, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
        }
        .buttonStyle(.borderless)
    }

    private func propertyChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(Opacity.medium), lineWidth: 1)
        )
    }

    private static let pillDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        formatter.timeZone = .current
        return formatter
    }()
}
